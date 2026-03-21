#Project Brief

## Thesis

Surviv is a decentralized, offline mesh network app that turns ordinary iPhones into secure communication lifelines for civilians, journalists, and medical workers in conflict zones, enabling anonymous peer-to-peer messaging, real-time hazard alerts, and AI-powered threat detection without any reliance on cellular or internet infrastructure. By routing critical information—such as the locations of gunfire, missile strikes, and safe corridors—through encrypted multi-hop relay chains, it empowers vulnerable populations to share life-saving intelligence when traditional communication networks have been destroyed or compromised.

## Target Users

- Civilians trapped in active conflict zones
- Journalists and reporters in war-torn areas
- Medical workers and first responders navigating dangerous terrain
- Anyone in a disaster or crisis scenario where cellular/Wi-Fi infrastructure is down

## Platform

- **iOS 18** (Swift / SwiftUI)
- **Xcode** as the development environment
- Real-device testing required for Bluetooth/mesh features

---

## Core Features

### 1. Offline Device Discovery

- Uses Apple's **Multipeer Connectivity** framework to scan for nearby iPhones running surviv via Bluetooth/Wi-Fi Direct.
- No SIM card, no Wi-Fi, no internet required.
- Devices automatically recognize and connect to each other.

### 2. "Whisper" Routing Protocol (Multi-Hop Mesh)

- User A can send a data packet to User C by automatically bouncing it through User B.
- Store-and-forward: if User C is not yet in range, User B holds the message and delivers it when contact is made.
- Enables communication across distances that exceed direct Bluetooth range.

### 3. Offline Map & Hazard Pinning

- Pre-downloaded **Apple MapKit** interface for offline use.
- Users can drop hazard pins on the map:
  - **Danger pins** — gunfire, missile strikes, destroyed bridges, blockades
  - **Safe Route pins** — clear paths, shelters, medical stations
- Pin GPS coordinates are instantly broadcast to every device on the mesh network.

### 4. CoreML Acoustic Threat Detection

- A lightweight, on-device **CoreML** audio classifier that continuously listens via the microphone.
- Detects acoustic signatures of threats: drone rotors, gunfire, artillery, sirens.
- On detection: automatically drops a danger pin at the device's current GPS location and broadcasts it to the mesh.
- Visual alert: screen flashes red and notifies the user.



### 5. "Crisis Mode" Battery Saver

- A toggle that strips the UI to a minimal black-and-white text terminal.
- Dims brightness and throttles background tasks.
- Keeps the mesh network alive as long as possible on a single charge.

### 6. Duress PIN (Plausible Deniability)

- Normal PIN → opens the full tactical map and mesh data.
- Fake "Duress" PIN (e.g., 9999) → instantly wipes all mesh data, pins, and messages, then opens an innocent-looking decoy app (flashlight or notepad).
- Designed to protect users if their device is seized or inspected.

---

## Architecture & Team Roles

### Role 1: Backend & AI Engineer (Windows / Python)

- Trains an audio classifier in Python (e.g., using TensorFlow/PyTorch) to recognize drone, gunfire, and siren sounds.
- Converts the trained model to `.mlmodel` format using `coremltools`.
- Builds a local Python web server (Flask/FastAPI) as a "Command Center" to display a master map of all mesh data in a browser.

### Role 2: P2P Networker — Kyle (Mac / Swift)

- Implements `MCSession`, `MCNearbyServiceBrowser`, and `MCNearbyServiceAdvertiser` for device discovery.
- Writes send/receive functions for data packets between peers.
- Implements store-and-forward routing logic for multi-hop message delivery.

### Role 3: Frontend UI — Khai (Mac / SwiftUI)

- Integrates Apple Maps with offline caching.
- Builds the UI for dropping Danger and Safe Route pins.
- Builds the Crisis Mode low-battery UI.
- Handles the Duress PIN flow and decoy screen.

### Role 4: iOS Integrator — Leo (Mac / Swift)

- **Connects UI to P2P**: Wires Khai's map buttons and pin actions to Kyle's Multipeer Connectivity send functions so tapping a button actually broadcasts data.
- **Plugs in the AI**: Imports the `.mlmodel` file into Xcode, writes Swift code to pipe live microphone audio into the CoreML model, and triggers automatic pin drops on threat detection.
- **Local Database**: Implements a **SwiftData** (or SQLite) store so the device persists all received pins, messages, and threat alerts locally.
- **Glue logic**: Ensures data flows correctly between the network layer, the AI layer, the database, and the UI.

---

## Key Frameworks & Technologies

| Component              | Technology                        |
| ---------------------- | --------------------------------- |
| Peer-to-peer networking | Multipeer Connectivity (MCSession) |
| UI framework            | SwiftUI                           |
| Maps                    | MapKit                            |
| On-device AI            | CoreML                            |
| Audio input             | AVFoundation / AVAudioEngine      |
| Local persistence       | SwiftData                         |
| AI model training       | Python (TensorFlow/PyTorch)       |
| Model conversion        | coremltools                       |
| Command center          | Flask or FastAPI                  |

---

## Hackathon Demo Plan

1. **Device Discovery**: Two phones without SIM/Wi-Fi instantly detect each other.
2. **Multi-Hop Routing**: Phone A sends a message to Phone C via Phone B across a room.
3. **Hazard Pin Sync**: Drop a pin on one device, watch it appear on another with no internet.
4. **Acoustic Detection**: Play a drone sound from YouTube near a phone — it flashes red, auto-drops a pin, and alerts the mesh.
5. **Crisis Mode**: Toggle the battery saver and show the stripped-down UI.
6. **Duress PIN**: Enter the fake PIN and show the data wipe + decoy app.

---

## Hackathon Categories

- **Primary**: Accessibility & Empowerment
- **Secondary**: AI & Data Science
- **Tertiary**: Best Low-Level Hack

---

## Design Principles

- **Offline-first**: Every feature must work with zero internet.
- **Security & anonymity**: No accounts, no identifiable data, encrypted mesh traffic.
- **Battery-conscious**: Minimal resource usage; Crisis Mode extends uptime to days.
- **User safety**: The Duress PIN exists because getting caught with a tactical map in a conflict zone can be fatal.
- **Simplicity under stress**: The UI must be usable by someone who is scared, injured, or in the dark.