# Convert MAD PyTorch Model to CoreML

This project expects a compiled CoreML model named `MADMelCNN.mlmodelc` in the iOS app bundle.

## 1) Install conversion dependencies

```bash
cd ai-engine
python -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install torch coremltools numpy
```

## 2) Convert `best.pt` to `.mlmodel`

Use the existing conversion script:

```bash
python export_mad_coreml.py \
  --checkpoint mad_runs/default/best.pt \
  --output ../ios-app/surviv/Packages/MADMelCNN.mlpackage/Data/com.apple.CoreML/model.mlmodel
```

If your script uses different flags, run:

```bash
python export_mad_coreml.py --help
```

## 3) Compile to `.mlmodelc` for iOS

```bash
xcrun coremlcompiler compile \
  ../ios-app/surviv/Packages/MADMelCNN.mlpackage/Data/com.apple.CoreML/model.mlmodel \
  /tmp/MADMelCNN-compiled
```

This generates `/tmp/MADMelCNN-compiled/model.mlmodelc`.

## 4) Add compiled model to app bundle

Copy `model.mlmodelc` into the app target resources and ensure the folder is named:

- `MADMelCNN.mlmodelc`

The app loader searches by that resource name.

## 5) Runtime pipeline in app

The iOS detector is implemented in:

- `ios-app/surviv/Services/ThreatDetector.swift`

It uses:

- `AVFoundation` for live microphone capture
- `SoundAnalysis` (`SNAnalyzer`, `SNClassifySoundRequest`) for streaming classification
- Auto pin creation (`ThreatSource.audioDetection`) when a threat label crosses threshold
