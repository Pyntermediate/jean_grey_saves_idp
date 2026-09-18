# Flare: Developer & Architecture Guide

## 1. System Philosophy & Core Mechanics

Flare is engineered to provide reliable, 100% offline peer-to-peer communication across physical terrain without requiring cellular base stations, Wi-Fi networks, or internet gateways.

### The Hybrid Architecture
- Native Android Kotlin Subsystem (`MeshForegroundService.kt`): Runs 24/7 as an Android foreground service with a persistent notification. It manages continuous Bluetooth Low Energy (BLE) scanning (`SCAN_MODE_LOW_LATENCY`), silicon-level presence beaconing, duplicate packet filtering, and autonomous packet relaying.
- Flutter / Dart UI & Cryptography Engine (`lib/`): Manages presentation, local storage, end-to-end cryptographic key generation (X25519), message serialization, and user interaction.

```
+----------------------------------------------------------------+
|                   Flutter UI Layer (Dart)                      |
|  [Chat Screen]   [Radar Screen]   [SOS Screen]   [Key Vault]   |
+----------------------------------------------------------------+
                               | MethodChannel & EventChannels
+----------------------------------------------------------------+
|              Platform Interface (`MainActivity.kt`)            |
+----------------------------------------------------------------+
                               | Direct Method Invocations
+----------------------------------------------------------------+
|             Native Subsystem (`MeshForegroundService.kt`)      |
|  * 24/7 BLE Low-Latency Scanner (Continuous)                   |
|  * Autonomous Silicon Presence Beaconing (0x48)                |
|  * Hardware Advertising Set / Legacy Fallback                  |
|  * Persistent Rolling Packet De-duplication Cache              |
|  * Multi-Hop Store-and-Forward Relay Engine                    |
+----------------------------------------------------------------+
```

---

## 2. Directory Architecture

```
lib/
|-- main.dart                      # App entry point, lifecycle hooks, and notification channel init
|-- models/models.dart             # Packet models (RealBlePacket, RealPeerNode, ContactKey)
|-- screens/
|   |-- real_chat_screen.dart      # Direct messaging interface and message queue management
|   |-- real_emergency_screen.dart # SOS dispatch controls and satellite GPS monitor
|   |-- real_peers_screen.dart     # Nearby active devices radar and live RSSI monitor
|   |-- real_key_vault_screen.dart # Identity keypair management and QR code contact exchange
|   `-- real_settings_screen.dart  # Operational preferences and system configuration
|-- services/
|   |-- real_ble_service.dart      # Dart BLE mesh engine, packet serialization, and channel bridge
|   |-- real_gps_service.dart      # Multi-tier GPS fallback engine (LocationManager + Fused GMS)
|   |-- contact_vault.dart         # Contact persistence and cryptographic identity key vault
|   |-- crypto_engine.dart         # X25519 ECDH key generation, AES encryption, and SHA-256
|   |-- notification_service.dart  # Foreground service control and high-priority alert dispatch
|   `-- theme_manager.dart         # Theme preferences persistence
android/app/src/main/kotlin/com/example/test_1/
|-- MainActivity.kt                # Platform channel bridge (MethodChannel and EventChannels)
|-- MeshForegroundService.kt       # 24/7 native background scanner, silicon beacon, and relay
`-- BootReceiver.kt                # Re-engages foreground service on device reboot
```

---

## 3. Binary Radio Frame Specifications

All BLE communication uses raw Manufacturer Specific Data under Manufacturer ID `0x5251`.
Every packet fits within standard 24-byte advertisement limits (or uses 2-chunk extended framing) to guarantee compatibility across all Android devices (Android 8.0 through Android 14+).

| Opcode | Frame Type | Length | Structure | Description |
| :--- | :--- | :--- | :--- | :--- |
| 0x48 | Presence Heartbeat | 8 bytes | [0x52, 0x51, 0x48, TTL=1, HashH, HashL, SeqH, SeqL] | Emitted continuously in silicon every 250ms to keep nearby devices visible in the radar with live RSSI. |
| 0x4D | Single-Frame Chat | 17-24 bytes | [0x52, 0x51, 0x4D, Mode, MsgId(2), TTL(1), SenderHash(2), RecipientHash(2), Len, Payload] | Direct message payload for messages under 14 bytes. |
| 0xFE | Fragmented Chat | 17-24 bytes | [0x52, 0x51, 0xFE, Mode, MsgId(2), TotalChunks, ChunkIdx, SenderHash(2), RecipientHash(2), Len, Payload] | Slices larger messages into 14-byte segments across sequential radio frames. |
| 0x41 | Delivery ACK | 10 bytes | [0x52, 0x51, 0x41, TTL=3, MsgId(2), SenderHash(2), TargetRecipientHash(2)] | Transmitted immediately upon message receipt to confirm delivery on sender device. |
| 0x53 | Emergency SOS | 20 bytes | [0x52, 0x51, 0x53, Mode, Lat(4), Lng(4), Alt(2), SenderHash(2), RecipientHash(2), Len, Note] | High-priority distress beacon. |
| 0x53 0x7C | Contact Card | 17-24 bytes | Multi-chunk payload containing public key and display name. | Broadcasts contact card for one-tap contact exchange. |

---

## 4. Multi-Tier GPS Architecture (RealGpsService)

To ensure devices without SIM cards, offline test phones, or devices running older Android versions can acquire coordinates reliably, Flare implements a 4-tier acquisition chain:

1. Tier 1 (Cached Fix): `Geolocator.getLastKnownPosition()` immediately retrieves cached coordinates without waiting for hardware spin-up.
2. Tier 2 (Hardware GPS Lock): Queries native satellite hardware directly via Android `LocationManager.GPS_PROVIDER` (`forceLocationManager: true`, `accuracy: LocationAccuracy.high`, 8-second time limit), bypassing Google Play Services.
3. Tier 3 (Fused Location Fallback): If satellite acquisition times out (e.g. indoors), falls back to `FusedLocationProviderClient` (`forceLocationManager: false`, 5-second time limit).
4. Tier 4 (Cache Retention): Retains last known valid coordinates so emergency displays never flash empty or reset to 0.0.

---

## 5. Development & Testing Workflow

### Prerequisites
- Flutter SDK: >=3.12.2
- JDK: Java 17
- Android SDK: compileSdk = 34, minSdk = 26 (Android 8.0 Oreo), targetSdk = 34

### Commands
```bash
# Install dependencies
flutter pub get

# Static analysis (must pass with 0 errors and 0 warnings)
flutter analyze

# Build release APK
flutter build apk --release
```

### Physical Device Testing Requirements
1. Physical Devices Required: Android BLE advertising cannot be tested in software emulators. Testing must be conducted between two physical Android devices.
2. Location Services Enabled: Android requires Location services (GPS) to be turned ON in system quick settings for BLE scanning to return results.
3. Battery Optimization: For continuous background operation when the screen is turned off, set Flare app battery usage to Unrestricted in Android device settings on both devices.

---

## 6. Git Branching & Contribution Guidelines

- `main`: Production-ready, fully tested code.
- `feature/<name>`: New feature branches.
- `fix/<issue>`: Bug fixes and protocol enhancements.

Before committing, always run `flutter analyze` to verify zero static analysis issues.
