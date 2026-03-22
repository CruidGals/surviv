# Surviv

<img src="surviv_logo.png" alt="Surviv Logo" width="200" />

Surviv is a decentralized, offline mesh network app that turns ordinary iPhones into secure communication lifelines for civilians, journalists, and medical workers in conflict zones.

When cellular and internet networks are down, blocked, or unsafe, Surviv still works. It enables anonymous peer-to-peer messaging, real-time hazard alerts, and on-device AI threat detection. Critical reports such as gunfire locations, shelling zones, and safer movement corridors can move through encrypted multi-hop relay chains from phone to phone.

## Why This Matters

In high-risk environments, people do not fail because they lack courage. They fail because they lack trusted information at the right moment.

Surviv focuses on three hard constraints:

- No network dependency: communication should not require towers or internet.
- Low-latency local coordination: nearby people need shared situational awareness now, not later.
- Privacy by design: identity and location sharing should be intentional and minimal.

## What Surviv Does

1. Peer-to-peer emergency messaging
- Admin users can broadcast high-priority alerts.
- Messages relay across nearby devices with hop tracking and deduplication.

2. Live hazard mapping
- Users and admins can create danger and safe-route pins.
- Hazard pins synchronize across the mesh and appear on all connected devices.
- Threat history stores who reported, what type of threat, and when.

3. AI-assisted threat detection on device
- The app runs a Core ML audio model locally.
- It listens in short bursts, classifies likely threats, and can auto-drop danger pins.
- No cloud inference required.

4. Offline-first coordination
- If peers are temporarily unavailable, payloads are queued and flushed when links return.
- The app continues to provide local map awareness and historical context.

## System Design (High Level)

Surviv combines four layers:

- Interface layer (SwiftUI): civilian and admin views, map overlays, alert feed, threat history.
- Coordination layer: app lifecycle, location updates, detector events, pin creation/broadcast flow.
- Mesh transport layer: Multipeer Connectivity session management, relay logic, dedup, pending queues.
- AI layer: PyTorch training pipeline -> Core ML package -> on-device inference.

This structure keeps the product resilient: if one path fails (for example, mesh link drops), local functions still remain available.

## Core Technical Features

- Multipeer networking with multi-hop relay
- Packet and hazard deduplication for mesh stability
- Role-aware behavior (civilian/admin)
- SwiftData persistence for hazard and audio records
- On-device microphone inference with configurable confidence threshold
- Hazard metadata model (source, threat label, reason, timestamp, radius)

## Repository Structure

```text
surviv/
	README.md
	requirements.txt
	surviv_logo.png
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

## Tech Stack

- iOS app: SwiftUI, SwiftData, CoreLocation, AVFoundation, MultipeerConnectivity, Core ML
- AI engine: Python, PyTorch, torchaudio, NumPy
- Model target: Core ML package for on-device iPhone inference

## Quick Start

### A) Run the iOS app

1. Open ios-app/surviv.xcodeproj in Xcode.
2. Select a simulator or iPhone.
3. Build and run.
4. Grant location and microphone permissions.

Default behavior:

- App starts in civilian mode.
- Admin mode enables broadcast and hazard-management controls.
- Mesh messages and hazard pins relay between nearby peers.

### B) Run the AI pipeline

From repository root:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

Install a PyTorch build that matches your system from https://pytorch.org/.

Train:

```bash
cd ai-engine
python train_mad.py --data-root MAD_dataset --epochs 30 --out-dir mad_runs/default
```

Evaluate:

```bash
python test_mad.py --checkpoint mad_runs/default/best.pt --data-root MAD_dataset
```

Live microphone inference:

```bash
python live_mic_mad.py --checkpoint mad_runs/default/best.pt
```

Export to Core ML package:

```bash
pip install coremltools
python export_mad_coreml.py --checkpoint mad_runs/default/best.pt --out MADMelCNN.mlpackage
```

## Demo Flow (Hackathon)

1. Start two or more iPhones with Surviv nearby.
2. Send an admin broadcast from one phone.
3. Verify relay and appearance in alert feed across peers.
4. Drop a danger pin and show map synchronization.
5. Trigger or simulate threat detection and auto-generated hazard pin.
6. Open threat history to show timeline, source attribution, and coordinates.

## Security and Privacy Notes

- Mesh communication is local and peer-to-peer.
- Surviv is designed to avoid dependence on centralized servers during active operation.
- Profile names are user controlled; users can choose low-identity naming.
- Threat detection runs on device, reducing exposure of raw audio data.

## Limitations and Next Steps

Current prototype focus:

- iOS-first implementation
- Local mesh radius bound by peer proximity
- Hazard routing recommendations are still in active development

High-impact next features:

- Delivery acknowledgements and read receipts for critical alerts
- Offline danger-aware route guidance
- Trust scoring and report confidence model for conflicting field reports

## Dataset Label Order (MAD)

1. Communication
2. Shooting
3. Footsteps
4. Shelling
5. Vehicle
6. Helicopter
7. Fighter

## Summary

Surviv is built for the worst day, not the best day.

It provides communication, hazard awareness, and AI-assisted threat signals in environments where traditional infrastructure cannot be trusted or may not exist at all.