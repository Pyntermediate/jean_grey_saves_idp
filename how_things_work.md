# Flare: Technical Architecture & Mechanics
### System Architecture, Offline Technical Mechanics & Operational Guide

---

## 1. System Overview & Problem Statement

When an individual (Person A) becomes lost or injured deep within wilderness or disaster terrain, traditional communication infrastructure fails completely:
* No Cellular Coverage: Mobile towers do not reach deep backcountry or disaster areas.
* No Internet or Wi-Fi: Cloud servers and messaging platforms cannot be reached.
* No Satellite Phone: Standard smartphones lack satellite uplink hardware.
* Oblivious Contacts: Relatives or dispatchers outside (Person B) have no automated way to receive distress alerts.

Flare solves this problem by turning passing smartphones, search drones, and rescue vehicles into an ad-hoc Multi-Hop Store-and-Forward Mesh Network.

---

## 2. The 3-Tier Mesh Architecture

```
[Person A (Lost in Backcountry)]
        |
        | (Short-Range BLE / LE Coded PHY ~420m)
        v
[Data Mule (Passing Hiker / Drone / Vehicle)] ---> Silently stores encrypted packet
        |
        | (Moves toward network coverage)
        v
[Cellular Gateway / Cell Tower]
        |
        | (Automated SMS / Cloud Relay)
        v
[Person B (Recipient / Emergency Services)]
```

### Tier 1: The Distress Sender (Person A)
* Radio: Operates entirely offline using BLE broadcast frames (`0x53` for SOS, `0x4D`/`0xFE` for chat).
* Payload: Encrypted with recipient public key, stamped with GPS coordinates, altitude, and timestamp.
* Range: ~40-80 meters in standard LE 1M PHY mode, up to ~400+ meters in LE Coded PHY mode where hardware permits.

### Tier 2: The Data Mule Network (Hikers, Drones, Rangers)
* Storage: Encrypted packets are stored in local persistent SQLite/SharedPreferences cache.
* Zero Decryption: Data mules cannot read or alter the payload without the recipient private key.
* Re-broadcast: Every passing mule automatically re-broadcasts packets hop-by-hop as they travel through the terrain.

### Tier 3: The Cellular Gateway & Recipient (Person B)
* As soon as any carrier mule reaches cellular or Wi-Fi coverage, the app detects connectivity and dispatches the buffered distress packet to emergency responders or SMS gateways.
* Person B receives coordinates with direct navigation links.

---

## 3. Offline Hardware Mechanics

### A. How GPS Coordinates Work Offline
* Standard smartphones contain a dedicated physical GPS/GLONASS/Galileo silicon receiver chip completely independent of cellular networks.
* Flare accesses the raw satellite chip via Android `LocationManager.GPS_PROVIDER` (`forceLocationManager: true`), computing coordinates directly from orbital satellite timing signals without requiring cellular tower assistance (A-GPS).

### B. How the Rescue Compass Works Offline
* Distance: Computed using the Haversine spherical trigonometry formula over Earth's radius:
  d = 2R * arcsin(sqrt(sin^2(dlat/2) + cos(lat1)*cos(lat2)*sin^2(dlng/2)))
* Bearing: Computed using forward azimuth spherical formulas.
* Heading: Sensor fusion utilizing hardware magnetometer and accelerometer sensors.

### C. Bluetooth 5.0 LE Coded PHY (Long Range)
* Utilizes forward error correction (FEC S=8 coding) on supported Bluetooth 5.0 hardware to boost link budget by +12 dB, extending radio line-of-sight range up to 400+ meters.

---

## 4. Cryptographic Security & Privacy Modes

### Cryptographic Foundation
1. Identity: Each user generates a persistent X25519 elliptic-curve keypair.
2. Exchange: Public keys are shared offline via QR code scanning or over-the-air contact exchange packets (`0x53 0x7C`).
3. Payload Encryption: Messages use ECDH shared secrets combined with AES-GCM authenticated encryption.
4. Tamper Resistance: SHA-256 integrity digests prevent relay nodes from altering payload data in transit.

### Dispatch Modes
1. Open Emergency Alert (`publicSos`): Distress message and coordinates are broadcast in the clear so all nearby search parties and volunteers can read and respond immediately.
2. Private Message Alert (`privateE2ee`): End-to-end encrypted; only the designated recipient with the matching private key can decrypt the message.
3. Dual Alert (`hybridSos`): Distress coordinates are readable by all searchers for triage, while personal medical notes or sensitive details remain encrypted for trusted contacts only.

---

## 5. Summary of Operational Guarantees

* Zero Infrastructure Required: No cellular towers, no SIM cards, no Wi-Fi, no internet.
* Continuous Background Operation: Silicon-level beaconing maintains connectivity even while phones are locked in pockets.
* Complete Privacy: Data mules passively carry encrypted payloads without the ability to inspect contents.
* Cross-Version Compatibility: Tested and operational from Android 8.0 (API 26) through Android 14+ (API 34).
