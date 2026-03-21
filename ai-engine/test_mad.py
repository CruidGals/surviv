#!/usr/bin/env python3
"""Evaluate trained MAD mel-CNN on MAD_dataset/test.csv (held-out clips)."""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Any, Dict, Tuple

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from tqdm import tqdm

from mad.audio import MelSpectrogramPipeline
from mad.dataset import MADDataset, read_manifest, validate_manifest
from mad.model import LightweightMelCNN

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
logger = logging.getLogger("test_mad")


def load_torch(path: Path) -> Dict[str, Any]:
    try:
        return torch.load(path, map_location="cpu", weights_only=False)
    except TypeError:
        return torch.load(path, map_location="cpu")


@torch.no_grad()
def run_eval(
    model: nn.Module,
    loader: DataLoader,
    device: torch.device,
    num_classes: int,
) -> Tuple[float, float, np.ndarray]:
    model.eval()
    total = 0
    correct = 0
    loss_sum = 0.0
    criterion = nn.CrossEntropyLoss(reduction="sum")
    cm = np.zeros((num_classes, num_classes), dtype=np.int64)
    for mel, y in tqdm(loader, desc="test"):
        mel = mel.to(device)
        y = y.to(device)
        logits = model(mel)
        loss_sum += criterion(logits, y).item()
        pred = logits.argmax(dim=1)
        correct += (pred == y).sum().item()
        total += y.size(0)
        for t, p in zip(y.cpu().numpy(), pred.cpu().numpy()):
            cm[int(t), int(p)] += 1
    acc = correct / max(total, 1)
    loss = loss_sum / max(total, 1)
    return loss, acc, cm


def main() -> None:
    root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="Evaluate MAD mel-CNN on test.csv")
    parser.add_argument("--checkpoint", type=Path, required=True, help="best.pt or last.pt from train_mad")
    parser.add_argument(
        "--data-root",
        type=Path,
        default=root / "MAD_dataset",
        help="Folder containing test/ audio and test.csv",
    )
    parser.add_argument("--test-csv", type=Path, default=None, help="Default: data-root/test.csv")
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--num-workers", type=int, default=0)
    parser.add_argument("--no-scan", action="store_true")
    parser.add_argument("--device", type=str, default=None, help="cuda or cpu (default: auto)")
    args = parser.parse_args()

    test_csv = args.test_csv or (args.data_root / "test.csv")
    if not test_csv.is_file():
        logger.error("Test CSV not found: %s", test_csv)
        sys.exit(1)
    if not args.checkpoint.is_file():
        logger.error("Checkpoint not found: %s", args.checkpoint)
        sys.exit(1)

    ckpt = load_torch(args.checkpoint)
    cfg: Dict[str, Any] = ckpt.get("config") or {}
    if not cfg:
        logger.error("Checkpoint missing 'config'; pass a checkpoint saved by train_mad.py")
        sys.exit(1)

    sample_rate = int(cfg["sample_rate"])
    duration_sec = float(cfg["duration_sec"])
    n_fft = int(cfg["n_fft"])
    hop_length = int(cfg["hop_length"])
    n_mels = int(cfg["n_mels"])
    num_classes = int(cfg["num_classes"])
    dropout = float(cfg.get("dropout", 0.2))

    target_samples = int(sample_rate * duration_sec)
    min_samples = min(512, target_samples // 4)

    manifest = read_manifest(test_csv)
    if not args.no_scan:
        logger.info("Validating test manifest...")
        manifest = validate_manifest(
            args.data_root, manifest, min_samples=min_samples, target_sr=sample_rate
        )
        logger.info("Usable test samples: %d", len(manifest))

    if not manifest:
        logger.error("No test samples to evaluate.")
        sys.exit(1)

    mel_pipe = MelSpectrogramPipeline(
        sample_rate=sample_rate,
        n_fft=n_fft,
        hop_length=hop_length,
        n_mels=n_mels,
    )
    ds = MADDataset(
        args.data_root,
        manifest,
        mel_pipe,
        target_samples,
        training=False,
        augment_fn=None,
        seed=0,
    )
    loader = DataLoader(
        ds,
        batch_size=args.batch_size,
        shuffle=False,
        num_workers=args.num_workers,
        pin_memory=torch.cuda.is_available() and args.device != "cpu",
    )

    model = LightweightMelCNN(num_classes=num_classes, dropout=dropout)
    model.load_state_dict(ckpt["model_state"], strict=True)

    if args.device:
        device = torch.device(args.device)
    else:
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = model.to(device)

    loss, acc, cm = run_eval(model, loader, device, num_classes)
    logger.info("test loss %.4f | accuracy %.4f", loss, acc)

    per_class = []
    for c in range(num_classes):
        row = cm[c].sum()
        hit = cm[c, c]
        rec = hit / row if row else 0.0
        per_class.append((c, rec))
        logger.info("class %d recall (diag/row): %.4f (support %d)", c, rec, int(row))

    out_dir = args.checkpoint.parent
    np.save(out_dir / "confusion_matrix.npy", cm)
    with (out_dir / "test_metrics.json").open("w", encoding="utf-8") as f:
        json.dump(
            {
                "loss": loss,
                "accuracy": acc,
                "per_class_recall": {str(c): r for c, r in per_class},
                "num_samples": int(cm.sum()),
            },
            f,
            indent=2,
        )
    logger.info("Wrote confusion_matrix.npy and test_metrics.json next to checkpoint")


if __name__ == "__main__":
    main()
