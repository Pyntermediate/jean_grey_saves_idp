# Flare

> Zero-Infrastructure Offline Bluetooth Low Energy (BLE) Multi-Hop Mesh Messaging and Emergency SOS.

Flare is an off-grid mobile communication system engineered for disaster relief, search-and-rescue operations, and wilderness travel where cellular infrastructure, satellite terminals, and internet connectivity are unavailable.

---

## Core Technical Features

- **Offline BLE Peer-to-Peer Mesh**: Communicates directly device-to-device over Bluetooth Low Energy without cellular data, Wi-Fi infrastructure, or SIM cards.
- **Store-and-Forward Mule Routing**: Nodes automatically record and relay encrypted packets across physical terrain as devices move within radio range.
- **Continuous Silicon Beaconing**: Autonomous, low-power background beaconing enables immediate device discovery and signal tracking upon entering radio range.
- **Autonomous Satellite GPS & Navigation**: Native GPS acquisition operates completely offline, computing distance and bearing using spherical trigonometry.
- **Cryptographic Security**: All private communications utilize X25519 elliptic-curve Diffie-Hellman key exchange, AES-GCM encryption, and cryptographic identity signatures.
- **Emergency SOS Dispatch**: Rapid broadcast of high-priority distress alerts with coordinates, altitude, and status notes to all devices within mesh range.

---

## Technical Specifications

- Platform: Flutter (Dart) with native Android Kotlin background subsystem
- Target OS: Android 8.0 (API Level 26) through Android 14+ (API Level 34)
- Radio Protocol: Bluetooth Low Energy 4.2 / 5.0 (LE 1M and LE Coded PHY where supported)
- Architecture: Continuous native foreground service (MeshForegroundService) paired with reactive Flutter UI

---

## Developer Quick Start

### Prerequisites
- Flutter SDK: >=3.12.2
- Dart SDK: >=3.0.0
- Android SDK: API Level 26 minimum, API Level 34 target
- Java Development Kit: JDK 17
- Physical Hardware: Testing requires two physical Android devices with Bluetooth and Location services enabled.

### Build Instructions
`ash
# 1. Fetch dependencies
flutter pub get

# 2. Run static analysis
flutter analyze

# 3. Compile release APK
flutter build apk --release
`
The compiled APK will be located at uild/app/outputs/flutter-apk/app-release.apk.

---

## Project Structure

`
lib/
|-- main.dart                      # Application initialization and lifecycle
|-- models/models.dart             # Protocol data models and packet definitions
|-- screens/
|   |-- real_chat_screen.dart      # Direct messaging interface and transmission queue
|   |-- real_emergency_screen.dart # Emergency SOS dispatch and GPS coordination
|   |-- real_peers_screen.dart     # Nearby active node discovery and RSSI monitor
|   -- real_key_vault_screen.dart # Cryptographic identity management and key sharing
|-- services/
|   |-- real_ble_service.dart      # Dart BLE mesh engine and platform bridge
|   |-- real_gps_service.dart      # Multi-tier GPS acquisition and caching
|   |-- contact_vault.dart         # Contact directory and identity persistence
|   |-- crypto_engine.dart         # X25519 ECDH key generation and AES encryption
|   -- notification_service.dart  # Foreground service control and alert delivery
android/
-- app/src/main/kotlin/com/example/test_1/
    |-- MainActivity.kt            # Platform channel bridge
    -- MeshForegroundService.kt   # Persistent background scanner, beacon, and packet relay
`

For complete protocol packet definitions, hardware beacon specifications, and testing guidelines, refer to DEVELOPER_GUIDE.md.
