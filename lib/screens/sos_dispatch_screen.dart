import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/models.dart';
import '../services/contact_vault.dart';
import '../services/mesh_engine.dart';

// Re-use shared design tokens from main.dart
const _bg        = Color(0xFF0D1117);
const _surface   = Color(0xFF161B22);
const _border    = Color(0xFF30363D);
const _red       = Color(0xFFCF222E);
const _blue      = Color(0xFF388BFD);
const _text      = Color(0xFFE6EDF3);
const _muted     = Color(0xFF8B949E);

class SosDispatchScreen extends StatefulWidget {
  const SosDispatchScreen({super.key});

  @override
  State<SosDispatchScreen> createState() => _SosDispatchScreenState();
}

class _SosDispatchScreenState extends State<SosDispatchScreen> {
  MessageMode _selectedMode = MessageMode.publicSos;
  String _selectedContactId = 'person_b';
  final TextEditingController _noteController = TextEditingController(
    text: 'Twisted ankle near Ridge Trail #4. Need assistance.',
  );

  bool _isBroadcasting = false;
  SosPacket? _activeSosPacket;

  void _triggerSos() {
    setState(() => _isBroadcasting = true);

    final packet = MeshEngine.instance.dispatchSos(
      recipientId: _selectedContactId,
      mode: _selectedMode,
      customNote: _noteController.text,
      lat: 45.3214,
      lng: -121.6541,
    );

    setState(() => _activeSosPacket = packet);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Row(
          children: [
            const Icon(Icons.sensors, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_selectedMode.label} — broadcasting to nearby mesh nodes',
                style: GoogleFonts.outfit(fontSize: 13, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ContactVault.contacts;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Top Header ─────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('flare',
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: _text,
                              letterSpacing: -0.5,
                            )),
                        const SizedBox(height: 2),
                        
                      ],
                    ),
                  ),
                  _Pill(
                    label: 'OFFLINE',
                    icon: Icons.wifi_off,
                    color: _red,
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // ── Dispatch Button ────────────────────────────────────────
              _DispatchButton(
                broadcasting: _isBroadcasting,
                onTap: _triggerSos,
              ),
              const SizedBox(height: 28),

              // ── Section 1: Transport Engine ────────────────────────────
              _SectionLabel(number: '1', title: 'Radio Transport Engine'),
              const SizedBox(height: 10),
              Row(
                children: TransportEngine.values.map((engine) {
                  final sel = MeshEngine.instance.activeTransportEngine == engine;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          right: engine == TransportEngine.values.last ? 0 : 10),
                      child: _SelectCard(
                        selected: sel,
                        icon: engine == TransportEngine.leCodedBle
                            ? Icons.bluetooth_searching
                            : Icons.wifi_tethering,
                        title: engine == TransportEngine.leCodedBle
                            ? 'BLE Long-Range'
                            : 'Wi-Fi P2P',
                        subtitle: engine == TransportEngine.leCodedBle
                            ? '~420m · LE Coded'
                            : '20+ Mbps',
                        onTap: () => setState(() =>
                            MeshEngine.instance.activeTransportEngine = engine),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // ── Section 2: Dispatch Mode ───────────────────────────────
              _SectionLabel(number: '2', title: 'Dispatch Mode'),
              const SizedBox(height: 10),
              ...MessageMode.values.map((mode) {
                final sel = _selectedMode == mode;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ModeRow(
                    mode: mode,
                    selected: sel,
                    onTap: () => setState(() => _selectedMode = mode),
                  ),
                );
              }),
              const SizedBox(height: 24),

              // ── Section 3: Target Contact ──────────────────────────────
              _SectionLabel(number: '3', title: 'Target Contact'),
              const SizedBox(height: 10),
              _SurfaceBox(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedContactId,
                    dropdownColor: const Color(0xFF1C2128),
                    isExpanded: true,
                    icon: const Icon(Icons.unfold_more, color: _muted, size: 18),
                    items: contacts.map((c) {
                      return DropdownMenuItem<String>(
                        value: c.id,
                        child: Row(
                          children: [
                            Icon(
                              c.isAppInstalled
                                  ? Icons.lock_outline
                                  : Icons.sms_outlined,
                              color: c.isAppInstalled
                                  ? const Color(0xFF3FB950)
                                  : const Color(0xFFD29922),
                              size: 16,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(c.name,
                                      style: GoogleFonts.outfit(
                                          color: _text,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                  Text(
                                    c.isAppInstalled
                                        ? 'E2EE key synced · ${c.phoneNumber}'
                                        : 'No app → SMS fallback',
                                    style: GoogleFonts.outfit(
                                        color: _muted, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) =>
                        setState(() => _selectedContactId = val!),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Section 4: Distress Note ───────────────────────────────
              _SectionLabel(number: '4', title: 'Distress Note'),
              const SizedBox(height: 10),
              TextField(
                controller: _noteController,
                maxLines: 3,
                style: GoogleFonts.outfit(color: _text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter status, injuries, or landmarks…',
                  hintStyle: GoogleFonts.outfit(color: _muted, fontSize: 13),
                  filled: true,
                  fillColor: _surface,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _blue, width: 1.5),
                  ),
                ),
              ),

              // ── Active Packet Status ───────────────────────────────────
              if (_activeSosPacket != null) ...[
                const SizedBox(height: 24),
                _PacketStatusCard(packet: _activeSosPacket!),
              ],

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-Widgets ──────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _Pill({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.outfit(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String number;
  final String title;
  const _SectionLabel({required this.number, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: _blue.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(number,
                style: GoogleFonts.outfit(
                    color: _blue, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: GoogleFonts.outfit(
                color: _text, fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _DispatchButton extends StatelessWidget {
  final bool broadcasting;
  final VoidCallback onTap;
  const _DispatchButton({required this.broadcasting, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: broadcasting
                ? const Color(0xFF7D1A20)
                : _red,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                broadcasting ? Icons.sensors : Icons.warning_amber_rounded,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                broadcasting
                    ? 'Broadcasting SOS signal…'
                    : 'Dispatch Emergency SOS',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SelectCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? _blue.withValues(alpha: 0.12) : _surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _blue : _border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? _blue : _muted, size: 20),
            const SizedBox(height: 8),
            Text(title,
                style: GoogleFonts.outfit(
                    color: _text, fontSize: 13, fontWeight: FontWeight.w600)),
            Text(subtitle,
                style: GoogleFonts.outfit(
                    color: selected ? _blue : _muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  final MessageMode mode;
  final bool selected;
  final VoidCallback onTap;
  const _ModeRow(
      {required this.mode, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _blue.withValues(alpha: 0.1) : _surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _blue : _border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: selected ? _blue : _muted, width: 2),
                color: selected ? _blue : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.circle, color: Colors.white, size: 8)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mode.label,
                      style: GoogleFonts.outfit(
                          color: _text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Text(mode.description,
                      style:
                          GoogleFonts.outfit(color: _muted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurfaceBox extends StatelessWidget {
  final Widget child;
  const _SurfaceBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }
}

class _PacketStatusCard extends StatelessWidget {
  final SosPacket packet;
  const _PacketStatusCard({required this.packet});

  @override
  Widget build(BuildContext context) {
    final delivered = packet.isDeliveredToPersonB;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: delivered
                ? const Color(0xFF3FB950)
                : const Color(0xFFD29922)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub,
                  color: delivered
                      ? const Color(0xFF3FB950)
                      : const Color(0xFFD29922),
                  size: 16),
              const SizedBox(width: 6),
              Text('Active Packet',
                  style: GoogleFonts.outfit(
                      color: delivered
                          ? const Color(0xFF3FB950)
                          : const Color(0xFFD29922),
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              const Spacer(),
              Text(
                delivered ? 'DELIVERED' : 'IN TRANSIT',
                style: GoogleFonts.outfit(
                    color: delivered
                        ? const Color(0xFF3FB950)
                        : const Color(0xFFD29922),
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'ID: ${packet.packetId}  ·  Hops: ${packet.hopHistory.length - 1}  ·  TTL: ${packet.ttl}',
            style: GoogleFonts.outfit(color: _muted, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            packet.hopHistory.join(' → '),
            style: GoogleFonts.outfit(color: _text, fontSize: 11),
          ),
          if (delivered) ...[
            const SizedBox(height: 6),
            Text(
              packet.isSmsFallbackTriggered
                  ? 'Gateway -> SMS dispatched'
                  : 'Delivered to recipient via mesh',
              style: GoogleFonts.outfit(
                  color: const Color(0xFF3FB950),
                  fontWeight: FontWeight.w600,
                  fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

