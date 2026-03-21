"""Load and normalize waveforms; build fixed-size mel spectrograms."""

from __future__ import annotations

from pathlib import Path
from typing import Optional, Tuple

import torch
import torch.nn as nn
import torchaudio


def load_waveform(
    path: Path,
    target_sr: int,
    mono: bool = True,
    min_samples: int = 1,
) -> Tuple[torch.Tensor, int]:
    """
    Load audio with torchaudio; handle missing/corrupt files and edge cases.

    Returns (waveform [channels, samples], sample_rate).
    Raises FileNotFoundError, RuntimeError on unrecoverable errors.
    """
    if not path.is_file():
        raise FileNotFoundError(path)

    waveform, sr = _load_waveform_raw(path)
    return _normalize_loaded_waveform(waveform, sr, target_sr, mono, min_samples)


def _load_waveform_raw(path: Path) -> Tuple[torch.Tensor, int]:
    """
    Prefer libsndfile via soundfile — avoids torchaudio's TorchCodec path, which
    errors unless the optional `torchcodec` package is installed (common on 2.5+).
    """
    errors: list[str] = []
    try:
        import soundfile as sf

        data, sr = sf.read(str(path), dtype="float32", always_2d=True)
        if data.size == 0:
            raise RuntimeError("empty decode")
        # (samples, ch) -> [C, T]
        waveform = torch.from_numpy(data.T.copy())
        return waveform, int(sr)
    except Exception as e:
        errors.append(f"soundfile: {e}")

    try:
        w, sr = torchaudio.load(str(path), backend="soundfile")
        return w, int(sr)
    except TypeError:
        pass
    except Exception as e:
        errors.append(f"torchaudio[soundfile]: {e}")

    try:
        w, sr = torchaudio.load(str(path))
        return w, int(sr)
    except Exception as e:
        errors.append(f"torchaudio[default]: {e}")
        raise RuntimeError(
            f"failed to load {path} ({'; '.join(errors)}). "
            "Install soundfile (`pip install soundfile`) or torchcodec if needed."
        ) from e


def _normalize_loaded_waveform(
    waveform: torch.Tensor,
    sr: int,
    target_sr: int,
    mono: bool,
    min_samples: int,
) -> Tuple[torch.Tensor, int]:
    if waveform.numel() == 0:
        raise RuntimeError("empty audio buffer after decode")

    if mono and waveform.shape[0] > 1:
        waveform = waveform.mean(dim=0, keepdim=True)
    elif not mono and waveform.shape[0] == 1:
        waveform = waveform.repeat(2, 1)

    if sr != target_sr:
        waveform = torchaudio.functional.resample(waveform, sr, target_sr)
        sr = target_sr

    n = waveform.shape[1]
    if n < min_samples:
        pad = min_samples - n
        waveform = torch.nn.functional.pad(waveform, (0, pad))

    # Peak normalize to reduce clipping / silence extremes (per-file)
    peak = waveform.abs().max().clamp_min(1e-8)
    waveform = waveform / peak

    return waveform, sr


def fixed_length_crop_or_pad(
    waveform: torch.Tensor,
    target_samples: int,
    *,
    random_crop: bool,
    rng: Optional[torch.Generator] = None,
) -> torch.Tensor:
    """
    waveform: [C, T]. Ensure length == target_samples by center/random crop or zero-pad.
    """
    c, t = waveform.shape
    if t == target_samples:
        return waveform
    if t > target_samples:
        if random_crop:
            max_start = t - target_samples
            if rng is not None:
                start = int(torch.randint(0, max_start + 1, (1,), generator=rng).item())
            else:
                start = int(torch.randint(0, max_start + 1, (1,)).item())
            return waveform[:, start : start + target_samples]
        start = (t - target_samples) // 2
        return waveform[:, start : start + target_samples]
    pad = target_samples - t
    return torch.nn.functional.pad(waveform, (0, pad))


class MelSpectrogramPipeline(nn.Module):
    """Mel + log; kept as nn.Module so it can live on device with the model."""

    def __init__(
        self,
        sample_rate: int,
        n_fft: int,
        hop_length: int,
        n_mels: int,
        f_min: float = 0.0,
        f_max: Optional[float] = None,
    ):
        super().__init__()
        self.sample_rate = sample_rate
        if f_max is None:
            f_max = float(sample_rate // 2)
        self.mel = torchaudio.transforms.MelSpectrogram(
            sample_rate=sample_rate,
            n_fft=n_fft,
            hop_length=hop_length,
            n_mels=n_mels,
            f_min=f_min,
            f_max=f_max,
            center=True,
            power=2.0,
        )
        self.to_db = torchaudio.transforms.AmplitudeToDB(stype="power", top_db=80.0)

    def forward(self, waveform: torch.Tensor) -> torch.Tensor:
        # waveform [B, C, T] or [C, T]; mel expects [..., time]
        if waveform.dim() == 2:
            waveform = waveform.unsqueeze(0)
        if waveform.shape[1] > 1:
            waveform = waveform.mean(dim=1, keepdim=True)
        mel = self.mel(waveform)
        mel = self.to_db(mel)
        # Per-sample standardization (stabilizes across clips)
        mean = mel.mean(dim=(-2, -1), keepdim=True)
        std = mel.std(dim=(-2, -1), keepdim=True).clamp_min(1e-5)
        mel = (mel - mean) / std
        # Conv2d expects [B, 1, n_mels, time]. torchaudio may return [B, n_mels, T] or [B, 1, n_mels, T].
        if mel.dim() == 3:
            mel = mel.unsqueeze(1)
        elif mel.dim() == 4 and mel.shape[1] == 1:
            pass
        elif mel.dim() == 4:
            mel = mel.mean(dim=1, keepdim=True)
        else:
            raise RuntimeError(f"unexpected mel shape {tuple(mel.shape)}")
        return mel
