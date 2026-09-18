import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/models.dart';
import '../services/mesh_engine.dart';

const _bg      = Color(0xFF0D1117);
const _surface = Color(0xFF161B22);
const _border  = Color(0xFF30363D);
const _blue    = Color(0xFF388BFD);
const _text    = Color(0xFFE6EDF3);
const _muted   = Color(0xFF8B949E);
const _red     = Color(0xFFCF222E);
const _amber   = Color(0xFFD29922);
const _green   = Color(0xFF3FB950);

class MeshRadarScreen extends StatefulWidget {
  const MeshRadarScreen({super.key});

  @override
  State<MeshRadarScreen> createState() => _MeshRadarScreenState();
}

class _MeshRadarScreenState extends State<MeshRadarScreen> {
  final mesh = MeshEngine.instance;
  StreamSubscription? _logSub;
  StreamSubscription? _packetSub;

  @override
  void initState() {
    super.initState();
    _logSub = mesh.logStream.listen((_) {
      if (mounted) setState(() {});
    });
    _packetSub = mesh.packetStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _packetSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text('Mesh Radar',
            style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w700, fontSize: 17, color: _text)),
        backgroundColor: _bg,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
        actions: [
          // PHY Selector inline in AppBar
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<BlePhyMode>(
                value: mesh.activePhyMode,
                dropdownColor: const Color(0xFF1C2128),
                style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _blue),
                icon: const Icon(Icons.expand_more, size: 16, color: _muted),
                items: BlePhyMode.values.map((phy) {
                  return DropdownMenuItem<BlePhyMode>(
                    value: phy,
                    child: Text(phy.label),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => mesh.activePhyMode = val);
                },
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded, color: _blue, size: 22),
            tooltip: 'Step one hop',
            onPressed: () => setState(() => mesh.simulateStep()),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _muted, size: 20),
            tooltip: 'Reset simulation',
            onPressed: () => setState(() => mesh.clearSimulation()),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [

          // ── Canvas ──────────────────────────────────────────────────────
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      // Grid painter
                      CustomPaint(
                        size: Size.infinite,
                        painter: RadarGridPainter(),
                      ),
                      // Connection lines
                      CustomPaint(
                        size: Size.infinite,
                        painter: MeshConnectionsPainter(
                          nodes: mesh.nodes,
                          activePackets: mesh.activePackets,
                        ),
                      ),
                      // Draggable nodes
                      ...mesh.nodes.map((node) {
                        return Positioned(
                          left: node.x - 24,
                          top: node.y - 24,
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              setState(() {
                                mesh.moveNode(
                                  node.id,
                                  details.delta.dx,
                                  details.delta.dy,
                                  maxX: constraints.maxWidth,
                                  maxY: constraints.maxHeight,
                                );
                              });
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _nodeColor(node.type),
                                    border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.15),
                                        width: 1.5),
                                  ),
                                  child: Icon(
                                    _nodeIcon(node.type),
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    node.name.split(' ').first,
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            ),
          ),

          // ── Log Panel ────────────────────────────────────────────────────
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Log header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: Row(
                      children: [
                        Text('Event Log',
                            style: GoogleFonts.spaceGrotesk(
                                color: _text,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('${mesh.logs.length} events',
                            style: GoogleFonts.spaceGrotesk(
                                color: _muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  Container(height: 1, color: _border),
                  Expanded(
                    child: mesh.logs.isEmpty
                        ? Center(
                            child: Text(
                              'No events yet. Trigger an SOS first.',
                              style: GoogleFonts.spaceGrotesk(
                                  color: _muted, fontSize: 12),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            itemCount: mesh.logs.length,
                            separatorBuilder: (_, i) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final log =
                                  mesh.logs[mesh.logs.length - 1 - index];
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(
                                      _eventIcon(log.event),
                                      color: _eventColor(log.event),
                                      size: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text:
                                                '${log.fromNode} → ${log.toNode}  ',
                                            style: GoogleFonts.spaceGrotesk(
                                                color: _text,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600),
                                          ),
                                          TextSpan(
                                            text: log.details,
                                            style: GoogleFonts.spaceGrotesk(
                                                color: _muted, fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${log.time.minute.toString().padLeft(2, '0')}:${log.time.second.toString().padLeft(2, '0')}',
                                    style: GoogleFonts.spaceGrotesk(
                                        color: _muted, fontSize: 10),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _nodeColor(NodeType type) {
    switch (type) {
      case NodeType.personA:  return _red;
      case NodeType.hiker:    return _amber;
      case NodeType.drone:    return const Color(0xFF8957E5);
      case NodeType.gateway:  return _blue;
      case NodeType.personB:  return _green;
    }
  }

  IconData _nodeIcon(NodeType type) {
    switch (type) {
      case NodeType.personA:  return Icons.person_pin_circle;
      case NodeType.hiker:    return Icons.directions_walk;
      case NodeType.drone:    return Icons.flight;
      case NodeType.gateway:  return Icons.cell_tower;
      case NodeType.personB:  return Icons.home;
    }
  }

  IconData _eventIcon(String event) {
    switch (event) {
      case 'DISPATCH_SOS':    return Icons.warning_amber_rounded;
      case 'MESH_HOP':        return Icons.swap_horiz;
      case 'GATEWAY_UPLINK':  return Icons.cloud_upload_outlined;
      case 'SMS_FALLBACK':    return Icons.sms_outlined;
      case 'CELLULAR_PUSH':
      case 'DELIVERED_E2EE':  return Icons.check_circle_outline;
      default:                return Icons.info_outline;
    }
  }

  Color _eventColor(String event) {
    switch (event) {
      case 'DISPATCH_SOS':    return _red;
      case 'MESH_HOP':        return _amber;
      case 'GATEWAY_UPLINK':  return _blue;
      case 'SMS_FALLBACK':    return const Color(0xFFD29922);
      case 'CELLULAR_PUSH':
      case 'DELIVERED_E2EE':  return _green;
      default:                return _muted;
    }
  }
}

// ── Painters ─────────────────────────────────────────────────────────────────

class RadarGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF30363D).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, (size.width / 8) * i, paint);
    }

    // Crosshair lines
    final linePaint = Paint()
      ..color = const Color(0xFF30363D).withValues(alpha: 0.4)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), linePaint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MeshConnectionsPainter extends CustomPainter {
  final List<MeshNode> nodes;
  final List<SosPacket> activePackets;

  MeshConnectionsPainter({required this.nodes, required this.activePackets});

  @override
  void paint(Canvas canvas, Size size) {
    final rangePaint = Paint()
      ..color = const Color(0xFF388BFD).withValues(alpha: 0.15)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final hopPaint = Paint()
      ..color = const Color(0xFFD29922)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Radio range lines
    for (int i = 0; i < nodes.length; i++) {
      for (int j = i + 1; j < nodes.length; j++) {
        final a = nodes[i];
        final b = nodes[j];
        final dx = a.x - b.x;
        final dy = a.y - b.y;
        final r = MeshEngine.instance.activePhyMode.rangeMeters;
        if ((dx * dx + dy * dy) <= r * r) {
          canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), rangePaint);
        }
      }
    }

    // Active packet hop trace
    for (final pkt in activePackets) {
      if (pkt.hopHistory.length >= 2) {
        for (int k = 0; k < pkt.hopHistory.length - 1; k++) {
          final n1 = nodes.firstWhere((n) => n.id == pkt.hopHistory[k]);
          final n2 = nodes.firstWhere((n) => n.id == pkt.hopHistory[k + 1]);
          canvas.drawLine(Offset(n1.x, n1.y), Offset(n2.x, n2.y), hopPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
