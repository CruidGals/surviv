"""Small CNN for single-channel mel spectrograms (mobile-friendly)."""

from __future__ import annotations

import torch
import torch.nn as nn


class LightweightMelCNN(nn.Module):
    """
    Compact conv stack + adaptive pool for variable-length mel time axis.
    Input: [B, 1, n_mels, time].
    """

    def __init__(self, num_classes: int, dropout: float = 0.2):
        super().__init__()
        self.stem = nn.Sequential(
            nn.Conv2d(1, 32, kernel_size=3, padding=1, bias=False),
            nn.BatchNorm2d(32),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(2),
        )
        self.block1 = nn.Sequential(
            nn.Conv2d(32, 64, kernel_size=3, padding=1, bias=False),
            nn.BatchNorm2d(64),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(2),
        )
        self.block2 = nn.Sequential(
            nn.Conv2d(64, 128, kernel_size=3, padding=1, bias=False),
            nn.BatchNorm2d(128),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(2),
        )
        self.pool = nn.AdaptiveAvgPool2d((4, 4))
        self.dropout = nn.Dropout(dropout)
        self.fc = nn.Linear(128 * 4 * 4, num_classes)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.stem(x)
        x = self.block1(x)
        x = self.block2(x)
        x = self.pool(x)
        x = x.flatten(1)
        x = self.dropout(x)
        return self.fc(x)
