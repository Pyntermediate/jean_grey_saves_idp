# Design System: Flare

> **Semantic Design System Specification (Stitch & UI Max Pro)**
> Preserves 100% of Flare's core screen layouts, widget trees, and continuous BLE/GPS mechanics while defining three high-agency visual variations.

---

## 1. Visual Atmosphere & Principles

Flare is a mission-critical, 100% offline emergency communicator. The visual system must balance high-stakes emergency clarity with refined, non-generic craft:

- **Density:** Cockpit Balanced (6-7 / 10). High data density (RSSI dBm, GPS coordinates, packet counters) presented through disciplined typographic hierarchy rather than visual clutter.
- **Elevation Philosophy:** Zero heavy dropshadows. Elevation is expressed through subtle background value stepping (`--scaffold-bg` -> `--surface-card` -> `--surface-elevated`) and 1px border strokes.
- **Component Geometry:** Modular rectangular containers (`NeuContainer`) with controlled corner rounding (10px - 14px). No bloated bubbly shapes.
- **Typography:** `Space Grotesk` (headings, action labels, section headers) paired with `JetBrains Mono` / monospace for all telemetry, coordinates, and packet metrics.

---

## 2. Preserved Screen Layout Specifications

Every variation strictly preserves the existing Flutter widget structure across all 4 primary screens:

### A. Emergency SOS Screen (`RealEmergencyScreen`)
1. **Header Row:** Screen title (`Emergency SOS`) + live status pill (`IDLE` / `SENDING SIGNAL` with blinking radar dot).
2. **Section 1: Modes (PHY Selection):** 2 side-by-side `NeuContainer` cards (`Maximum Range [LE Coded S=8]` with `Low Strength` badge vs `Standard Range [1M PHY]` with `High Strength` badge).
3. **Section 2: Privacy Selection:** 3 vertically stacked selection cards (`Open Emergency Alert`, `Private Message Alert`, `Dual Alert`) with radio selection indicators.
4. **Section 3: Distress Details:** Satellite GPS telemetry card (`Latitude`, `Longitude`, `Acquire Fresh` button, satellite fix status) + custom situation note input field.
5. **Section 4: Primary Action:** Full-width tactile `BROADCAST EMERGENCY SOS` button with high-contrast emergency accent.

### B. Mesh Radar / Nearby Devices Screen (`RealPeersScreen`)
1. **Header Row:** `Nearby Devices` title + `Clear Unknown Devices` cleanup action.
2. **Active Node List:** Clean vertical list of `NeuContainer` peer cards featuring:
   - Peer Name & Device Type.
   - Status badge (`Online` / `Offline`).
   - Signal Strength text (`Strong`, `Moderate`, `Weak`) with live RSSI (`-52 dBm`).
   - Packet counter chip.
3. **Status Footer:** Persistent background silicon heartbeat indicator (`0x48`).

### C. Mesh Chat Screen (`RealChatScreen`)
1. **Contact Header:** Recipient name, verified X25519 public key badge, direct BLE hop telemetry.
2. **Message Bubbles:**
   - Received message: Neutral card surface, timestamp, incoming RSSI.
   - Sent message: High-contrast primary accent, delivery acknowledgment tick (`OK`).
   - Mule relay notices: Border-dashed store-and-forward indicator.
3. **Input Bar:** Attachment button, text entry field, circular send action.

### D. Key Vault Screen (`RealKeyVaultScreen`)
1. **Identity Card:** Centered X25519 public key QR matrix, public key hash chip (`PUB_KEY_...`), copy fingerprint action.
2. **Sync Action:** Direct BLE Contact Card Sync broadcast button (`0x53 0x7C`).

---

## 3. The 3 Stitch Visual Variations

### Variation 1: Obsidian Machined Tactical (Avionics & Aerospace Precision)
- **Concept:** Military heads-up display (HUD) and tactical GPS unit. Minimizes glare and eye fatigue during night operations in wilderness terrain.
- **Scaffold Background:** `#08090B` (Deep OLED Black)
- **Surface Card:** `#12151B` (Machined Carbon)
- **Surface Elevated:** `#191E27` (Tactical Slate)
- **Border Outline:** `#232A36` (1px Machined Steel)
- **Primary Accent:** `#FF7300` (Aerospace Safety Amber)
- **Distress Accent:** `#FF2B43` (High-Vis Beacon Crimson)
- **Link/Success Accent:** `#00E676` (Phosphor Radar Green)
- **Text Primary:** `#F0F4F8` (Crisp Off-White)
- **Text Muted:** `#7E8C9F` (Cool Slate)
- **Corner Radius:** `12px`

### Variation 2: Nordic Minimalist / Swiss Monolith (Cobalt & Emerald Precision)
- **Concept:** Ultra-clean architectural design language. High typographical contrast, hairline dividers, and disciplined whitespace for executive command.
- **Scaffold Background:** `#0C0E12` (Obsidian Core)
- **Surface Card:** `#141820` (Graphite Plate)
- **Surface Elevated:** `#1C222E` (Elevated Graphite)
- **Border Outline:** `#252D3D` (Hairline Steel)
- **Primary Accent:** `#3B82F6` (Electric Cobalt)
- **Distress Accent:** `#EF4444` (Signal Red)
- **Link/Success Accent:** `#10B981` (Signal Emerald)
- **Text Primary:** `#F8FAFC` (Pure White)
- **Text Muted:** `#94A3B8` (Slate 400)
- **Corner Radius:** `14px`

### Variation 3: Solar High-Vis SAR (Field Sunlight & Rugged Contrast)
- **Concept:** High-contrast search-and-rescue gear engineered for blinding direct sunlight, glare over snow/water, and heavy rain.
- **Scaffold Background:** `#111317` (Industrial Zinc)
- **Surface Card:** `#1B1F27` (Chassis Charcoal)
- **Surface Elevated:** `#242A35` (Elevated Zinc)
- **Border Outline:** `#374151` (High-Contrast Chamfer)
- **Primary Accent:** `#FFD600` (Solar Warning Yellow)
- **Distress Accent:** `#FF3B30` (International Orange)
- **Link/Success Accent:** `#00FF88` (Safety Field Green)
- **Text Primary:** `#FFFFFF` (High-Contrast White)
- **Text Muted:** `#9CA3AF` (Neutral Gray)
- **Corner Radius:** `10px`

---

## 4. Flutter Implementation Roadmap

Because Flare was refactored to use `Theme.of(context)` and `NeuContainer` throughout `lib/screens/`, activating any of these 3 design variations requires **zero code changes** to screen logic, radio packets, or background services.

Simply update the 6 static color tokens in `lib/services/theme_manager.dart`:
```dart
// Example: Variation 1 (Obsidian Machined Tactical)
static const Color darkBg         = Color(0xFF08090B);
static const Color darkSurface    = Color(0xFF12151B);
static const Color darkSurfaceAlt = Color(0xFF191E27);
static const Color darkBorder     = Color(0xFF232A36);
static const Color accentBlue     = Color(0xFFFF7300); // Replaced with Aerospace Amber
static const Color accentRed      = Color(0xFFFF2B43);
static const Color accentGreen    = Color(0xFF00E676);
```
