# Surviv

![Surviv Logo](surviv_logo.png)

Offline-first emergency coordination app with:

- iOS mesh networking and hazard mapping
- On-device audio threat detection (Core ML)
- Python training and evaluation pipeline for MAD mel-CNN

## What Is In This Repo

### 1) ios-app

SwiftUI iOS app that supports:

- Two modes: civilian and admin
- Real-time local map with danger and safe-route pins
- Threat history timeline with metadata (source user, class label, reason, radius)
- Mesh relay of admin announcements and hazard pins using Multipeer Connectivity
- On-device microphone burst analysis with bundled Core ML model

Main app entrypoint:

- ios-app/surviv/survivApp.swift

Core app systems:

- Coordinator orchestration: ios-app/surviv/Services/Coordinator.swift
- Mesh transport: ios-app/surviv/P2P/SurvivNetwork.swift
- Hazard pin wire format: ios-app/surviv/P2P/SurvivMeshWire.swift
- Audio detector: ios-app/surviv/Services/ThreatDetector.swift

Bundled model package currently in app source:

- ios-app/surviv/Packages/MADMelCNN.mlpackage

### 2) ai-engine

Python scripts and modules for training and exporting a lightweight mel-CNN:

- train_mad.py: train model checkpoints
- test_mad.py: evaluate checkpoint on held-out test split
- live_mic_mad.py: live microphone inference in terminal
- export_mad_coreml.py: convert trained checkpoint to Core ML .mlpackage

Internal module package:

- ai-engine/mad/

Default training output folder:

- ai-engine/mad_runs/default/

## Repository Layout

```text
surviv/
	README.md
	requirements.txt
	ai-engine/
		train_mad.py
		test_mad.py
		live_mic_mad.py
		export_mad_coreml.py
		mad/
		mad_runs/default/
	ios-app/
		surviv.xcodeproj
		surviv/
			Services/
			P2P/
			Models/
			Packages/MADMelCNN.mlpackage
```

## Prerequisites

### Python side (ai-engine)

- Python 3.11 or 3.12 recommended
- Install PyTorch build matching your hardware from https://pytorch.org/
- Remaining deps from requirements.txt

For Core ML export:

- coremltools installed in the same environment

### iOS side

- macOS + Xcode
- iOS device/simulator target supported by your Xcode toolchain
- Mic and location permissions when running the app

## Quick Start

### 1) Set up Python environment

From repository root:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

Optional for Core ML export:

```bash
pip install coremltools
```

### 2) Train model

From ai-engine:

```bash
cd ai-engine
python train_mad.py --data-root MAD_dataset --epochs 30 --out-dir mad_runs/default
```

Notes:

- Expects MAD_dataset/training.csv and audio files under MAD_dataset/
- Writes best.pt, last.pt, and config.json under out-dir

### 3) Evaluate model

```bash
python test_mad.py --checkpoint mad_runs/default/best.pt --data-root MAD_dataset
```

Outputs next to checkpoint:

- confusion_matrix.npy
- test_metrics.json

### 4) Live microphone inference (terminal)

```bash
python live_mic_mad.py --checkpoint mad_runs/default/best.pt
```

Optional:

- List devices: python live_mic_mad.py --list-devices
- Select device: python live_mic_mad.py --mic-device <index>

### 5) Export to Core ML package

```bash
python export_mad_coreml.py --checkpoint mad_runs/default/best.pt --out MADMelCNN.mlpackage
```

Then place/update the exported package in the iOS app package location as needed.

## Running The iOS App

1. Open ios-app/surviv.xcodeproj in Xcode.
2. Select a simulator or physical device.
3. Build and run.
4. Grant location and microphone permissions.

Behavior at runtime:

- App starts in civilian mode by default.
- Admin mode unlocks map management, broadcast alerts, and threat history views.
- Mesh announcements and hazard pins relay across nearby peers.
- Audio detector can drop danger pins based on on-device model confidence.

## Data And Labels

Default class order for the MAD model (from ai-engine/mad/mad_labels.py):

1. Communication
2. Shooting
3. Footsteps
4. Shelling
5. Vehicle
6. Helicopter
7. Fighter

## Notes

- requirements.txt does not include coremltools by default.
- The Python scripts expect MAD dataset CSV/audio files to be present locally.
- The iOS app uses SwiftData for persisted HazardPin and AudioRecording models.