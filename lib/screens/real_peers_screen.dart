import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/models.dart';
import '../services/real_ble_service.dart';
import '../services/contact_vault.dart';
import '../services/theme_manager.dart';
import '../widgets/neu_widgets.dart';

class RealPeersScreen extends StatefulWidget {
  const RealPeersScreen({super.key});

  @override
  State<RealPeersScreen> createState() => _RealPeersScreenState();
}

class _RealPeersScreenState extends State<RealPeersScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _ble = RealBleService.instance;
  StreamSubscription? _sub;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sub = _ble.peerStream.listen((_) {
      if (mounted) setState(() {});
    });
    // Refresh UI every 2 seconds to update offline states
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  String _getSignalStrength(int rssi, bool isOffline) {
    if (isOffline) return 'Offline';
    if (rssi >= -65) return 'Strong';
    if (rssi >= -85) return 'Moderate';
    return 'Weak';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final peers = _ble.discoveredPeers;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Combine discovered peers and known contacts for 100% screen continuity
    final List<Map<String, dynamic>> displayItems = [];
    final seenHashes = <int>{};
    final knownContactAddresses = <String>{};

    final myPubKey = ContactVault.myKeyPair['publicKey'];
    final myHash = myPubKey != null ? (ContactVault.consistentHash(myPubKey) & 0xFFFF) : 0;

    // First, map which Bluetooth hardware addresses belong to known contacts
    for (final peer in peers) {
      if (myHash != 0 && peer.senderHash == myHash) continue;
      final knownContact = ContactVault.contacts.firstWhere(
        (c) => ContactVault.matchesSender(c, peer.senderHash),
        orElse: () => ContactKey(id: '', name: '', phoneNumber: '', publicKey: '', isAppInstalled: true, lastSynced: DateTime.now()),
      );
      if (knownContact.id.isNotEmpty && peer.deviceAddress != 'UNKNOWN' && peer.deviceAddress != 'OFFLINE') {
        knownContactAddresses.add(peer.deviceAddress);
      }
    }

    for (final peer in peers) {
      if (myHash != 0 && peer.senderHash == myHash) continue;
      final knownContact = ContactVault.contacts.firstWhere(
        (c) => ContactVault.matchesSender(c, peer.senderHash),
        orElse: () => ContactKey(id: '', name: 'Unknown Peer', phoneNumber: '', publicKey: '', isAppInstalled: true, lastSynced: DateTime.now()),
      );
      final isUnknown = knownContact.id.isEmpty;
      // Suppress unknown duplicate ghost peer if the physical device is already a named contact
      if (isUnknown && knownContactAddresses.contains(peer.deviceAddress)) {
        continue;
      }
      if (seenHashes.contains(peer.senderHash)) continue;
      seenHashes.add(peer.senderHash);
      if (!isUnknown) {
        seenHashes.add(ContactVault.getContactHash(knownContact));
      }

      final displayName = !isUnknown ? knownContact.name : 'Peer ${peer.senderHash.toRadixString(16).toUpperCase()}';
      displayItems.add({
        'peer': peer,
        'displayName': displayName,
        'isUnknown': isUnknown,
      });
    }

    for (final c in ContactVault.contacts) {
      if (c.publicKey.isEmpty) continue;
      final cHash = ContactVault.getContactHash(c);
      if (cHash == 0 || (myHash != 0 && cHash == myHash)) continue;
      if (!seenHashes.contains(cHash) && !seenHashes.any((h) => ContactVault.matchesSender(c, h))) {
        seenHashes.add(cHash);
        displayItems.add({
          'peer': RealPeerNode(
            senderHash: cHash,
            deviceAddress: 'OFFLINE',
            lastRssi: -99,
            lastSeen: c.lastSynced,
            phyMode: BlePhyMode.standard1M,
            packetCount: 0,
          ),
          'displayName': c.name,
          'isUnknown': false,
        });
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Nearby Devices',
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.cleaning_services_outlined, size: 20, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                        tooltip: 'Clear Unknown Devices',
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Clear Unknown Devices?'),
                              content: const Text('This will remove all unsaved peer history from nearby devices. Saved contacts will remain intact.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: ThemeManager.accentRed),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await _ble.clearUnknownPeers();
                            if (!context.mounted) return;
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Cleared unknown device history.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.refresh_rounded, size: 20, color: theme.colorScheme.onSurface),
                        tooltip: 'Rescan',
                        onPressed: () async {
                          await _ble.rescanMesh();
                          if (!context.mounted) return;
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Rescanning mesh devices...'),
                              duration: Duration(milliseconds: 1500),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: displayItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.hub_outlined,
                            size: 40,
                            color: isDark ? Colors.white24 : Colors.black26,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No Devices in Range',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 36),
                            child: Text(
                              'Open flare on a nearby phone to connect directly offline.',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                      itemCount: displayItems.length,
                      itemBuilder: (context, index) {
                        final item = displayItems[index];
                        final peer = item['peer'] as RealPeerNode;
                        final displayName = item['displayName'] as String;
                        final isUnknownPeer = item['isUnknown'] as bool? ?? false;
                        final timeAgo = DateTime.now().difference(peer.lastSeen).inSeconds;
                        final isOffline = timeAgo > 90;
                        final displayRssi = isOffline ? 0 : peer.lastRssi;

                        final signalText = isOffline
                            ? 'Signal: Offline (${timeAgo >= 60 ? '${timeAgo ~/ 60}m ago' : '${timeAgo}s ago'})'
                            : 'Signal: $displayRssi dBm (${_getSignalStrength(peer.lastRssi, false)})';

                        return NeuContainer(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF142338) : theme.colorScheme.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isOffline
                                        ? (isDark ? Colors.white24 : Colors.black26)
                                        : (isDark ? ThemeManager.accentCyan : ThemeManager.accentBlue), 
                                    width: 1.5,
                                  ),
                                  boxShadow: isOffline || !isDark ? null : [
                                    BoxShadow(
                                      color: ThemeManager.accentCyan.withValues(alpha: 0.25),
                                      blurRadius: 8,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  isOffline ? Icons.signal_cellular_connected_no_internet_4_bar : Icons.smartphone, 
                                  size: 20, 
                                  color: isOffline
                                      ? (isDark ? Colors.white24 : Colors.black26)
                                      : (isDark ? ThemeManager.accentCyan : ThemeManager.accentBlue),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      style: GoogleFonts.outfit(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isOffline ? (isDark ? Colors.white54 : Colors.black54) : theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    Text(
                                      signalText,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        color: isOffline 
                                            ? ThemeManager.accentRed 
                                            : (isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted),
                                      ),
                                    ),
                                    Text(
                                      'PHY: ${peer.phyMode.label}',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 10, 
                                        color: isOffline ? (isDark ? Colors.white38 : Colors.black38) : (isDark ? ThemeManager.accentCyan : ThemeManager.accentBlue), 
                                        fontWeight: FontWeight.w600
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isOffline)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: ThemeManager.accentGreen.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: ThemeManager.accentGreen.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Text(
                                    'IN MESH',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: ThemeManager.accentGreen,
                                    ),
                                  ),
                                ),
                              if (isUnknownPeer || isOffline)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 16),
                                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                    padding: EdgeInsets.zero,
                                    color: isDark ? Colors.white38 : Colors.black38,
                                    tooltip: 'Delete from history',
                                    onPressed: () async {
                                      await _ble.deletePeer(peer.senderHash);
                                      if (!context.mounted) return;
                                      setState(() {});
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Removed $displayName from nearby history.'),
                                          duration: const Duration(seconds: 2),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}



