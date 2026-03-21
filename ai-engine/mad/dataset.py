"""CSV manifest, group split, and PyTorch Dataset for MAD audio."""

from __future__ import annotations

import csv
import logging
import random
from collections import defaultdict
from pathlib import Path
from typing import Callable, Dict, List, Optional, Sequence, Tuple

import torch
from torch.utils.data import Dataset

from mad.audio import MelSpectrogramPipeline, fixed_length_crop_or_pad, load_waveform

logger = logging.getLogger(__name__)


def read_manifest(csv_path: Path) -> List[Tuple[Path, int]]:
    """Read MAD training or test CSV; return list of (relative_path, label)."""
    rows: List[Tuple[Path, int]] = []
    with csv_path.open(encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rel = row.get("path") or row.get("Path")
            if not rel:
                continue
            label = int(str(row["label"]).strip())
            rows.append((Path(rel), label))
    return rows


def video_group_key(relative_path: Path) -> str:
    """training/398/0.wav -> training/398 — keep all clips from one source together."""
    parts = relative_path.parts
    if len(parts) >= 2:
        return str(Path(parts[0]) / parts[1])
    return parts[0]


def group_train_val_split(
    manifest: Sequence[Tuple[Path, int]],
    val_fraction: float,
    seed: int,
) -> Tuple[List[Tuple[Path, int]], List[Tuple[Path, int]]]:
    """Split by video folder so train/val don't share the same YouTube clip."""
    groups: Dict[str, List[Tuple[Path, int]]] = defaultdict(list)
    for rel, lab in manifest:
        groups[video_group_key(rel)].append((rel, lab))

    group_keys = sorted(groups.keys())
    rng = random.Random(seed)
    rng.shuffle(group_keys)

    n_val = max(1, int(round(len(group_keys) * val_fraction)))
    n_val = min(n_val, len(group_keys) - 1) if len(group_keys) > 1 else 0
    val_keys = set(group_keys[:n_val]) if n_val else set()

    train_rows: List[Tuple[Path, int]] = []
    val_rows: List[Tuple[Path, int]] = []
    for k in group_keys:
        if k in val_keys:
            val_rows.extend(groups[k])
        else:
            train_rows.extend(groups[k])
    return train_rows, val_rows


def validate_manifest(
    data_root: Path,
    manifest: Sequence[Tuple[Path, int]],
    min_samples: int,
    target_sr: int,
) -> List[Tuple[Path, int]]:
    """Drop entries that cannot be loaded (missing file, corrupt, too short after resample)."""
    ok: List[Tuple[Path, int]] = []
    for rel, lab in manifest:
        full = data_root / rel
        try:
            w, _ = load_waveform(full, target_sr, mono=True, min_samples=min_samples)
            if w.shape[1] < min_samples:
                logger.warning("skip too short after load: %s", full)
                continue
        except Exception as e:
            logger.warning("skip %s: %s", full, e)
            continue
        ok.append((rel, lab))
    return ok


class MADDataset(Dataset):
    def __init__(
        self,
        data_root: Path,
        manifest: Sequence[Tuple[Path, int]],
        mel: MelSpectrogramPipeline,
        target_samples: int,
        training: bool,
        augment_fn: Optional[Callable[[torch.Tensor], torch.Tensor]] = None,
        seed: int = 0,
    ):
        self.data_root = data_root
        self.rows = list(manifest)
        self.mel = mel
        self.target_samples = target_samples
        self.training = training
        self.augment_fn = augment_fn
        self._rng = torch.Generator().manual_seed(seed)

    def __len__(self) -> int:
        return len(self.rows)

    def __getitem__(self, idx: int) -> Tuple[torch.Tensor, int]:
        rel, label = self.rows[idx]
        full = self.data_root / rel
        sr = self.mel.sample_rate
        waveform, _ = load_waveform(full, sr, mono=True, min_samples=1)
        waveform = fixed_length_crop_or_pad(
            waveform,
            self.target_samples,
            random_crop=self.training,
            rng=self._rng if self.training else None,
        )
        if self.augment_fn is not None and self.training:
            waveform = self.augment_fn(waveform)
        mel = self.mel(waveform)
        return mel.squeeze(0), label
