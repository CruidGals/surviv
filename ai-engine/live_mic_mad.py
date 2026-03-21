#!/usr/bin/env python3
"""
Real-time microphone inference with the trained MAD mel-CNN.

Uses a sliding window of audio (same duration as training), refreshed periodically.
Class names follow the official MAD dataset order (see mad/mad_labels.py).
"""

from __future__ import annotations

import argparse
import json
import queue
import sys
from pathlib import Path
from typing import Any, Dict, List, Tuple

import numpy as np
import torch
import torch.nn.functional as F
import torchaudio

try:
    import sounddevice as sd
except ImportError as e:
    print("Install sounddevice: pip install sounddevice", file=sys.stderr)
    raise SystemExit(1) from e

from mad.audio import MelSpectrogramPipeline, fixed_length_crop_or_pad
from mad.mad_labels import names_for_num_classes
from mad.model import LightweightMelCNN


def load_checkpoint(path: Path) -> Dict[str, Any]:
    try:
        return torch.load(path, map_location="cpu", weights_only=False)
    except TypeError:
        return torch.load(path, map_location="cpu")


def list_input_devices() -> None:
    print(sd.query_devices(kind="input"))


def resample_mono(waveform_1d: np.ndarray, sr_in: int, sr_out: int) -> np.ndarray:
    """waveform_1d: float32 [T] -> [T'] at sr_out."""
    if sr_in == sr_out:
        return waveform_1d.astype(np.float32, copy=False)
    w = torch.from_numpy(waveform_1d.astype(np.float32)).unsqueeze(0).unsqueeze(0)
    w = torchaudio.functional.resample(w, sr_in, sr_out)
    return w.squeeze(0).squeeze(0).numpy()


def ring_to_waveform(
    samples: np.ndarray,
    target_samples: int,
) -> torch.Tensor:
    """[T] mono float32 -> [1, target_samples] with center crop / pad + peak norm (matches training)."""
    w = torch.from_numpy(samples.astype(np.float32)).unsqueeze(0)
    w = fixed_length_crop_or_pad(w, target_samples, random_crop=False, rng=None)
    peak = w.abs().max().clamp_min(1e-8)
    w = w / peak
    return w


@torch.no_grad()
def predict(
    model: torch.nn.Module,
    mel: MelSpectrogramPipeline,
    waveform_1ch: torch.Tensor,
    device: torch.device,
) -> Tuple[int, torch.Tensor]:
    """waveform_1ch: [1, T]"""
    mel.eval()
    model.eval()
    x = waveform_1ch.unsqueeze(0).to(device)
    spec = mel(x)
    logits = model(spec)
    probs = F.softmax(logits, dim=1).squeeze(0)
    pred = int(probs.argmax().item())
    return pred, probs.cpu()


def main() -> None:
    root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="Live mic → MAD mel-CNN")
    parser.add_argument("--checkpoint", type=Path, default=root / "mad_runs" / "default" / "best.pt")
    parser.add_argument("--device", type=str, default=None, help="torch: cuda or cpu (default: auto)")
    parser.add_argument(
        "--mic-device",
        type=int,
        default=None,
        help="sounddevice input device index (default: system default). Use --list-devices",
    )
    parser.add_argument("--list-devices", action="store_true", help="Print audio devices and exit")
    parser.add_argument(
        "--names-json",
        type=Path,
        default=None,
        help="Optional JSON array of class names in index order, overriding built-in MAD names",
    )
    parser.add_argument("--refresh-sec", type=float, default=0.4, help="How often to run inference (seconds)")
    args = parser.parse_args()

    if args.list_devices:
        list_input_devices()
        return

    if not args.checkpoint.is_file():
        print(f"Checkpoint not found: {args.checkpoint}", file=sys.stderr)
        sys.exit(1)

    ckpt = load_checkpoint(args.checkpoint)
    cfg: Dict[str, Any] = ckpt.get("config") or {}
    if not cfg:
        print("Checkpoint missing 'config' (train with train_mad.py).", file=sys.stderr)
        sys.exit(1)

    sample_rate = int(cfg["sample_rate"])
    duration_sec = float(cfg["duration_sec"])
    n_fft = int(cfg["n_fft"])
    hop_length = int(cfg["hop_length"])
    n_mels = int(cfg["n_mels"])
    num_classes = int(cfg["num_classes"])
    dropout = float(cfg.get("dropout", 0.2))

    target_samples = int(sample_rate * duration_sec)

    if args.names_json and args.names_json.is_file():
        names: List[str] = json.loads(args.names_json.read_text(encoding="utf-8"))
        if len(names) < num_classes:
            names = names + [f"Class {i}" for i in range(len(names), num_classes)]
    else:
        names = list(names_for_num_classes(num_classes))

    torch_device = torch.device(args.device or ("cuda" if torch.cuda.is_available() else "cpu"))
    model = LightweightMelCNN(num_classes=num_classes, dropout=dropout)
    model.load_state_dict(ckpt["model_state"], strict=True)
    model = model.to(torch_device)

    mel = MelSpectrogramPipeline(
        sample_rate=sample_rate,
        n_fft=n_fft,
        hop_length=hop_length,
        n_mels=n_mels,
    ).to(torch_device)

    dev_idx = args.mic_device if args.mic_device is not None else sd.default.device[0]
    dev_info = sd.query_devices(dev_idx, "input")
    stream_sr = int(dev_info.get("default_samplerate") or 0)
    if stream_sr <= 0:
        stream_sr = 44100

    blocksize = max(256, int(stream_sr * args.refresh_sec))
    audio_q: queue.Queue = queue.Queue()

    def callback(indata: np.ndarray, frames: int, t: Any, status: Any) -> None:
        if status:
            print(status, file=sys.stderr)
        audio_q.put(indata.copy())

    ring = np.zeros(target_samples, dtype=np.float32)

    print(
        f"Listening (stream {stream_sr} Hz → model {sample_rate} Hz, "
        f"window {duration_sec:.1f}s, refresh ~{args.refresh_sec:.2f}s). Ctrl+C to stop.\n"
    )

    try:
        with sd.InputStream(
            device=dev_idx,
            channels=1,
            samplerate=stream_sr,
            blocksize=blocksize,
            dtype="float32",
            callback=callback,
        ):
            while True:
                chunk = audio_q.get()
                mono = chunk[:, 0] if chunk.ndim > 1 else chunk.reshape(-1)
                mono = resample_mono(mono, stream_sr, sample_rate)
                n = mono.shape[0]
                if n >= target_samples:
                    ring = mono[-target_samples:].astype(np.float32)
                else:
                    ring = np.roll(ring, -n)
                    ring[-n:] = mono

                w = ring_to_waveform(ring, target_samples)
                _, probs = predict(model, mel, w, torch_device)

                topk = 3
                p_np = probs.numpy()
                idx = np.argsort(-p_np)[:topk]
                parts = [f"{names[i]} {100.0 * float(p_np[i]):.1f}%" for i in idx]
                line = "  |  ".join(parts)
                sys.stdout.write(f"\r{line}                    ")
                sys.stdout.flush()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
