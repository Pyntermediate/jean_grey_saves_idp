import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/models.dart';
import '../services/contact_vault.dart';
import '../services/crypto_engine.dart';
import '../services/mesh_engine.dart';

const _bg      = Color(0xFF0D1117);
const _surface = Color(0xFF161B22);
const _border  = Color(0xFF30363D);
const _text    = Color(0xFFE6EDF3);
const _muted   = Color(0xFF8B949E);
const _red     = Color(0xFFCF222E);
const _amber   = Color(0xFFD29922);
const _green   = Color(0xFF3FB950);


class IncomingAlertsScreen extends StatefulWidget {
  const IncomingAlertsScreen({super.key});

  @override
  State<IncomingAlertsScreen> createState() => _IncomingAlertsScreenState();
}

class _IncomingAlertsScreenState extends State<IncomingAlertsScreen> {
  final mesh = MeshEngine.instance;
  StreamSubscription? _packetSub;
  StreamSubscription? _logSub;

  @override
  void initState() {
    super.initState();
    _packetSub = mesh.packetStream.listen((_) {
      if (mounted) setState(() {});
    });
    _logSub = mesh.logStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _packetSub?.cancel();
    _logSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activePackets = mesh.activePackets;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text('Alert Receiver',
            style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w700, fontSize: 17, color: _text)),
        backgroundColor: _bg,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _muted, size: 20),
            tooltip: 'Refresh',
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: activePackets.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inbox_outlined, size: 48, color: _muted),
                  const SizedBox(height: 14),
                  Text('No active broadcasts',
                      style: GoogleFonts.spaceGrotesk(color: _text, fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Dispatch an SOS from the first tab to see alerts here.',
                      style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 12)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: activePackets.length,
              itemBuilder: (context, index) {
                final packet = activePackets[index];
                return Column(
                  children: [
                    _PersonBCard(packet: packet),
                    const SizedBox(height: 12),
                    _HikerCard(packet: packet),
                    const SizedBox(height: 20),
                  ],
                );
              },
            ),
    );
  }
}

class _PersonBCard extends StatelessWidget {
  final SosPacket packet;
  const _PersonBCard({required this.packet});

  @override
  Widget build(BuildContext context) {
    final personBPrivKey =
        CryptoEngine.generateKeyPair('person_b')['privateKey']!;
    final decryptedNote = CryptoEngine.decryptPayload(
      encryptedPayload: packet.encryptedPayload,
      recipientPrivKey: personBPrivKey,
      senderPubKey: ContactVault.myKeyPair['publicKey']!,
      mode: packet.mode,
    );

    final delivered = packet.isDeliveredToPersonB;

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: delivered ? _green : _amber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: delivered
                  ? _green.withValues(alpha: 0.08)
                  : _amber.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(Icons.person_outline,
                    color: delivered ? _green : _amber, size: 15),
                const SizedBox(width: 7),
                Text('PERSON B — RECEIVER VIEW',
                    style: GoogleFonts.spaceGrotesk(
                        color: delivered ? _green : _amber,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (delivered ? _green : _amber).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    delivered ? 'DELIVERED' : 'IN TRANSIT',
                    style: GoogleFonts.spaceGrotesk(
                        color: delivered ? _green : _amber,
                        fontSize: 10,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(packet.cleartextHeader,
                    style: GoogleFonts.spaceGrotesk(
                        color: _text,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(packet.mode.label,
                          style: GoogleFonts.spaceGrotesk(
                              color: _muted, fontSize: 10,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(decryptedNote,
                          style: GoogleFonts.spaceGrotesk(
                              color: _green,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (packet.isSmsFallbackTriggered) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.sms_outlined,
                          color: _amber, size: 13),
                      const SizedBox(width: 6),
                      Text('Dispatched via Gateway SMS',
                          style: GoogleFonts.spaceGrotesk(
                              color: _amber, fontSize: 11)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HikerCard extends StatelessWidget {
  final SosPacket packet;
  const _HikerCard({required this.packet});

  @override
  Widget build(BuildContext context) {
    final isPublic = packet.mode == MessageMode.publicSos ||
        packet.mode == MessageMode.hybridSos;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isPublic
            ? _red.withValues(alpha: 0.07)
            : _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isPublic ? _red.withValues(alpha: 0.6) : _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPublic ? Icons.warning_amber_rounded : Icons.lock_outline,
                color: isPublic ? _red : _muted,
                size: 15,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  isPublic
                      ? 'THIRD-PARTY HIKER — UNIVERSAL SOS ALARM'
                      : 'THIRD-PARTY HIKER — SILENT MULE RELAY',
                  style: GoogleFonts.spaceGrotesk(
                      color: isPublic ? _red : _muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isPublic) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Compass widget
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _red.withValues(alpha: 0.1),
                    border: Border.all(color: _red.withValues(alpha: 0.5)),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.navigation, color: _red, size: 22),
                      SizedBox(height: 2),
                      Text('35m NW',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Distress signal detected nearby',
                          style: GoogleFonts.spaceGrotesk(
                              color: _text,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(
                          'GPS: ${packet.lat.toStringAsFixed(4)}, ${packet.lng.toStringAsFixed(4)}',
                          style:
                              GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11)),
                      const SizedBox(height: 2),
                      Text('HIGH PRIORITY ALARM ACTIVE',
                          style: GoogleFonts.spaceGrotesk(
                              color: _red,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(
              'Silent relay active — carrying encrypted payload for intended recipient only.',
              style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
