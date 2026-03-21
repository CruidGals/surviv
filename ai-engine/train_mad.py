#!/usr/bin/env python3
"""Train lightweight mel-CNN on MAD_dataset (see MAD_dataset/training.csv)."""

from __future__ import annotations

import argparse
import json
import logging
import random
import sys
from pathlib import Path
from typing import Any, Dict, List, Tuple

import numpy as np
import torch
import torch.nn as nn
import torchaudio
from torch.utils.data import DataLoader
from tqdm import tqdm

from mad.audio import MelSpectrogramPipeline
from mad.dataset import (
    MADDataset,
    group_train_val_split,
    read_manifest,
    validate_manifest,
)
from mad.model import LightweightMelCNN

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
logger = logging.getLogger("train_mad")


def set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def waveform_noise(waveform: torch.Tensor, sigma: float) -> torch.Tensor:
    if sigma <= 0:
        return waveform
    return waveform + sigma * torch.randn_like(waveform)


def spec_augment(
    mel: torch.Tensor,
    freq_mask_param: int,
    time_mask_param: int,
) -> torch.Tensor:
    """torchaudio masks expect (..., freq, time); input mel is [B, 1, F, T]."""
    if freq_mask_param <= 0 and time_mask_param <= 0:
        return mel
    x = mel.squeeze(1)
    if freq_mask_param > 0:
        x = torchaudio.transforms.FrequencyMasking(freq_mask_param)(x)
    if time_mask_param > 0:
        x = torchaudio.transforms.TimeMasking(time_mask_param)(x)
    return x.unsqueeze(1)


def compute_class_weights(labels: List[int], num_classes: int) -> torch.Tensor:
    counts = np.bincount(labels, minlength=num_classes).astype(np.float64)
    counts = np.maximum(counts, 1.0)
    w = 1.0 / counts
    w = w * (num_classes / w.sum())
    return torch.tensor(w, dtype=torch.float32)


def train_one_epoch(
    model: nn.Module,
    loader: DataLoader,
    optimizer: torch.optim.Optimizer,
    criterion: nn.Module,
    device: torch.device,
    spec_aug: bool,
    freq_mask: int,
    time_mask: int,
) -> Tuple[float, float]:
    model.train()
    total, correct, loss_sum = 0, 0, 0.0
    for mel, y in tqdm(loader, desc="train", leave=False):
        mel = mel.to(device)
        y = y.to(device)
        if spec_aug:
            mel = spec_augment(mel, freq_mask, time_mask)
        optimizer.zero_grad(set_to_none=True)
        logits = model(mel)
        loss = criterion(logits, y)
        loss.backward()
        optimizer.step()
        loss_sum += loss.item() * y.size(0)
        pred = logits.argmax(dim=1)
        correct += (pred == y).sum().item()
        total += y.size(0)
    return loss_sum / max(total, 1), correct / max(total, 1)


@torch.no_grad()
def evaluate(
    model: nn.Module,
    loader: DataLoader,
    criterion: nn.Module,
    device: torch.device,
) -> Tuple[float, float]:
    model.eval()
    total, correct, loss_sum = 0, 0, 0.0
    for mel, y in tqdm(loader, desc="val", leave=False):
        mel = mel.to(device)
        y = y.to(device)
        logits = model(mel)
        loss = criterion(logits, y)
        loss_sum += loss.item() * y.size(0)
        pred = logits.argmax(dim=1)
        correct += (pred == y).sum().item()
        total += y.size(0)
    return loss_sum / max(total, 1), correct / max(total, 1)


def build_config(args: argparse.Namespace) -> Dict[str, Any]:
    return {
        "sample_rate": args.sample_rate,
        "duration_sec": args.duration_sec,
        "n_fft": args.n_fft,
        "hop_length": args.hop_length,
        "n_mels": args.n_mels,
        "num_classes": args.num_classes,
        "dropout": args.dropout,
    }


def main() -> None:
    root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="Train MAD mel-CNN")
    parser.add_argument(
        "--data-root",
        type=Path,
        default=root / "MAD_dataset",
        help="Folder containing training/ and test/ audio and CSVs",
    )
    parser.add_argument("--train-csv", type=Path, default=None, help="Default: data-root/training.csv")
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--val-fraction", type=float, default=0.15)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--num-workers", type=int, default=0)
    parser.add_argument("--no-scan", action="store_true", help="Skip manifest validation (faster, risky if files missing)")
    parser.add_argument("--sample-rate", type=int, default=16000)
    parser.add_argument("--duration-sec", type=float, default=3.0)
    parser.add_argument("--n-fft", type=int, default=512)
    parser.add_argument("--hop-length", type=int, default=128)
    parser.add_argument("--n-mels", type=int, default=64)
    parser.add_argument("--num-classes", type=int, default=7)
    parser.add_argument("--dropout", type=float, default=0.2)
    parser.add_argument("--noise-sigma", type=float, default=0.01, help="Gaussian noise on waveform (train only); 0 disables")
    parser.add_argument("--spec-aug", action="store_true", help="Apply SpecAugment during training")
    parser.add_argument("--freq-mask", type=int, default=8)
    parser.add_argument("--time-mask", type=int, default=24)
    parser.add_argument("--out-dir", type=Path, default=root / "mad_runs" / "default")
    parser.add_argument("--export-onnx", action="store_true")
    args = parser.parse_args()

    train_csv = args.train_csv or (args.data_root / "training.csv")
    if not train_csv.is_file():
        logger.error("Training CSV not found: %s", train_csv)
        sys.exit(1)

    set_seed(args.seed)
    args.out_dir.mkdir(parents=True, exist_ok=True)

    manifest = read_manifest(train_csv)
    target_samples = int(args.sample_rate * args.duration_sec)
    min_samples = min(512, target_samples // 4)

    if not args.no_scan:
        logger.info("Validating manifest (drop bad files)...")
        manifest = validate_manifest(
            args.data_root, manifest, min_samples=min_samples, target_sr=args.sample_rate
        )
        logger.info("Usable samples: %d", len(manifest))

    train_rows, val_rows = group_train_val_split(manifest, args.val_fraction, args.seed)
    if not train_rows:
        logger.error("No training samples after split.")
        sys.exit(1)
    if not val_rows:
        logger.warning("Empty validation set; using a random 10%% of train for val")
        n = max(1, len(train_rows) // 10)
        rng = random.Random(args.seed)
        idx = rng.sample(range(len(train_rows)), n)
        val_set = {i for i in idx}
        val_rows = [train_rows[i] for i in idx]
        train_rows = [train_rows[i] for i in range(len(train_rows)) if i not in val_set]

    train_labels = [lab for _, lab in train_rows]
    class_weights = compute_class_weights(train_labels, args.num_classes).to(
        torch.device("cuda" if torch.cuda.is_available() else "cpu")
    )

    mel_pipe = MelSpectrogramPipeline(
        sample_rate=args.sample_rate,
        n_fft=args.n_fft,
        hop_length=args.hop_length,
        n_mels=args.n_mels,
    )

    def aug(w: torch.Tensor) -> torch.Tensor:
        return waveform_noise(w, args.noise_sigma)

    train_ds = MADDataset(
        args.data_root,
        train_rows,
        mel_pipe,
        target_samples,
        training=True,
        augment_fn=aug if args.noise_sigma > 0 else None,
        seed=args.seed,
    )
    val_ds = MADDataset(
        args.data_root,
        val_rows,
        mel_pipe,
        target_samples,
        training=False,
        augment_fn=None,
        seed=args.seed,
    )

    train_loader = DataLoader(
        train_ds,
        batch_size=args.batch_size,
        shuffle=True,
        num_workers=args.num_workers,
        pin_memory=torch.cuda.is_available(),
    )
    val_loader = DataLoader(
        val_ds,
        batch_size=args.batch_size,
        shuffle=False,
        num_workers=args.num_workers,
        pin_memory=torch.cuda.is_available(),
    )

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    class_weights = class_weights.to(device)
    model = LightweightMelCNN(num_classes=args.num_classes, dropout=args.dropout).to(device)

    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=max(args.epochs, 1))
    criterion = nn.CrossEntropyLoss(weight=class_weights)

    config = build_config(args)
    (args.out_dir / "config.json").write_text(json.dumps(config, indent=2), encoding="utf-8")

    best_val = -1.0
    best_path = args.out_dir / "best.pt"

    for epoch in range(1, args.epochs + 1):
        tr_loss, tr_acc = train_one_epoch(
            model,
            train_loader,
            optimizer,
            criterion,
            device,
            spec_aug=args.spec_aug,
            freq_mask=args.freq_mask,
            time_mask=args.time_mask,
        )
        va_loss, va_acc = evaluate(model, val_loader, criterion, device)
        scheduler.step()
        logger.info(
            "epoch %d/%d train loss %.4f acc %.4f | val loss %.4f acc %.4f",
            epoch,
            args.epochs,
            tr_loss,
            tr_acc,
            va_loss,
            va_acc,
        )
        if va_acc > best_val:
            best_val = va_acc
            torch.save(
                {
                    "model_state": model.state_dict(),
                    "config": config,
                    "epoch": epoch,
                    "val_acc": va_acc,
                    "labels": list(range(args.num_classes)),
                },
                best_path,
            )
            logger.info("saved new best to %s (val_acc=%.4f)", best_path, va_acc)

    last_path = args.out_dir / "last.pt"
    torch.save(
        {
            "model_state": model.state_dict(),
            "config": config,
            "epoch": args.epochs,
            "val_acc": va_acc,
        },
        last_path,
    )

    if args.export_onnx and best_path.is_file():
        try:
            try:
                ckpt = torch.load(best_path, map_location="cpu", weights_only=False)
            except TypeError:
                ckpt = torch.load(best_path, map_location="cpu")
            export_mel = MelSpectrogramPipeline(
                sample_rate=args.sample_rate,
                n_fft=args.n_fft,
                hop_length=args.hop_length,
                n_mels=args.n_mels,
            )
            export_model = LightweightMelCNN(num_classes=args.num_classes, dropout=args.dropout)
            export_model.load_state_dict(ckpt["model_state"])
            export_onnx(
                export_model,
                export_mel,
                target_samples,
                args.out_dir / "model.onnx",
            )
        except Exception as e:
            logger.warning("ONNX export failed: %s", e)


def export_onnx(
    model: LightweightMelCNN,
    mel: MelSpectrogramPipeline,
    target_samples: int,
    out_path: Path,
) -> None:
    """End-to-end: waveform [1,1,T] -> logits (CPU, mobile-friendly)."""
    model.eval()
    mel.eval()

    class Wrapper(nn.Module):
        def __init__(self, mel_t: MelSpectrogramPipeline, clf: LightweightMelCNN):
            super().__init__()
            self.mel = mel_t
            self.clf = clf

        def forward(self, waveform: torch.Tensor) -> torch.Tensor:
            m = self.mel(waveform)
            return self.clf(m)

    w = Wrapper(mel, model)
    dummy = torch.zeros(1, 1, target_samples)
    torch.onnx.export(
        w,
        dummy,
        str(out_path),
        input_names=["waveform"],
        output_names=["logits"],
        opset_version=17,
    )
    logger.info("Wrote ONNX to %s", out_path)


if __name__ == "__main__":
    main()
