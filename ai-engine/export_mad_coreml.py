#!/usr/bin/env python3
"""
Export `train_mad.py` checkpoint (`best.pt`) to Core ML (.mlpackage) for on-device inference.

End-to-end graph matches `live_mic_mad.py` / ONNX export: fixed-length mono waveform
[1, 1, T] -> mel -> LightweightMelCNN -> logits, saved as a **classifier** so iOS can use
`SNClassifySoundRequest` (SoundAnalysis) or `MLModel.prediction`.

Dependencies::

    pip install torch torchaudio coremltools numpy

Use **Python 3.11 or 3.12** (recommended). On **Python 3.14+**, coremltools often installs without
working native extensions (``libcoremlpython`` / ``libmilstoragepython``), which fails at save time
with ``RuntimeError: BlobWriter not loaded``.

Example::

    cd ai-engine
    python export_mad_coreml.py --checkpoint mad_runs/default/best.pt --out MADMelCNN.mlpackage
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List

import numpy as np
import torch
import torch.nn as nn

try:
    import coremltools as ct
except ImportError as e:
    print("Install coremltools: pip install coremltools", file=sys.stderr)
    raise SystemExit(1) from e

from mad.audio import MelSpectrogramPipeline
from mad.mad_labels import names_for_num_classes
from mad.model import LightweightMelCNN


def load_checkpoint(path: Path) -> Dict[str, Any]:
    try:
        return torch.load(path, map_location="cpu", weights_only=False)
    except TypeError:
        return torch.load(path, map_location="cpu")


def main() -> None:
    root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="PyTorch MAD mel-CNN -> Core ML")
    parser.add_argument("--checkpoint", type=Path, default=root / "mad_runs" / "default" / "best.pt")
    parser.add_argument("--out", type=Path, default=root / "MADMelCNN.mlpackage")
    args = parser.parse_args()

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

    names: List[str] = list(names_for_num_classes(num_classes))

    mel = MelSpectrogramPipeline(
        sample_rate=sample_rate,
        n_fft=n_fft,
        hop_length=hop_length,
        n_mels=n_mels,
    )
    clf = LightweightMelCNN(num_classes=num_classes, dropout=dropout)
    clf.load_state_dict(ckpt["model_state"], strict=True)

    class MelCNNWrapper(nn.Module):
        def __init__(self, mel_t: MelSpectrogramPipeline, model: LightweightMelCNN) -> None:
            super().__init__()
            self.mel = mel_t
            self.model = model

        def forward(self, waveform: torch.Tensor) -> torch.Tensor:
            return self.model(self.mel(waveform))

    wrapper = MelCNNWrapper(mel, clf).eval()
    example = torch.zeros(1, 1, target_samples, dtype=torch.float32)

    with torch.no_grad():
        traced = torch.jit.trace(wrapper, example)

    labels = names
    classifier_config = ct.ClassifierConfig(labels)

    ml = ct.convert(
        traced,
        inputs=[
            ct.TensorType(
                name="waveform",
                shape=tuple(example.shape),
                dtype=np.float32,
            )
        ],
        classifier_config=classifier_config,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS18,
    )

    meta = {
        "target_samples": str(target_samples),
        "sample_rate": str(sample_rate),
        "duration_sec": str(duration_sec),
        "n_fft": str(n_fft),
        "hop_length": str(hop_length),
        "n_mels": str(n_mels),
        "num_classes": str(num_classes),
        "class_labels_json": json.dumps(labels),
    }
    for k, v in meta.items():
        ml.user_defined_metadata[k] = v

    out = args.out
    if out.suffix == ".mlpackage" or str(out).endswith(".mlpackage"):
        ml.save(str(out))
    else:
        ml.save(str(out.with_suffix(".mlpackage")))
    print(f"Wrote Core ML classifier to {out}")


if __name__ == "__main__":
    main()
