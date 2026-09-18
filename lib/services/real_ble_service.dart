import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'contact_vault.dart';
import 'notification_service.dart';
import 'crypto_engine.dart';
import 'real_gps_service.dart';

/// Real Hardware BLE Packet Model
class RealBlePacket {
  final String packetId;
  final MessageMode mode;
  final BlePhyMode phyMode;
  final double lat;
  final double lng;
  final double altitude;
  final int ttl;
  final int senderHash;
  final int recipientHash;
  final String rawPayload;
  final String decryptedPayload;
  final int rssi;
  final DateTime receivedTime;
  final String deviceAddress;
  final int hopCount;
  final bool isRelayedByMe;
  final String? senderPubKey;

  RealBlePacket({
    required this.packetId,
    required this.mode,
    required this.phyMode,
    required this.lat,
    required this.lng,
    required this.altitude,
    required this.ttl,
    required this.senderHash,
    required this.recipientHash,
    required this.rawPayload,
    required this.decryptedPayload,
    required this.rssi,
    required this.receivedTime,
    required this.deviceAddress,
    this.hopCount = 0,
    this.isRelayedByMe = false,
    this.senderPubKey,
  });

  /// Nominal transmission bitrate
  int get transmissionSpeedKbps => phyMode.speedKbps;

  /// Transmission speed label (e.g., "125 kbps", "1.0 Mbps", "2.0 Mbps")
  String get transmissionSpeedLabel => phyMode.speedLabel;

  /// On-air packet transmission latency in milliseconds
  double get packetAirTimeMs => phyMode.estimateAirTimeMs(rawPayload.length);

  /// Approximate distance calculation based on RSSI and Path Loss formula (offline)
  double get estimatedDistanceMeters {
    if (rssi == 0) return -1.0;
    const measuredPower = -59; // RSSI at 1 meter
    const n = 2.5; // Path loss exponent in outdoors / light foliage
    final ratio = (measuredPower - rssi) / (10 * n);
    return pow(10, ratio).toDouble().clamp(0.5, 1000.0);
  }
}

/// Discovered Physical Peer Node
class RealPeerNode {
  final int senderHash;
  final String deviceAddress;
  final int lastRssi;
  final DateTime lastSeen;
  final BlePhyMode phyMode;
  final double? lat;
  final double? lng;
  final int packetCount;

  RealPeerNode({
    required this.senderHash,
    required this.deviceAddress,
    required this.lastRssi,
    required this.lastSeen,
    required this.phyMode,
    this.lat,
    this.lng,
    this.packetCount = 1,
  });

  String get transmissionSpeedLabel => phyMode.speedLabel;
  int get transmissionSpeedKbps => phyMode.speedKbps;

  double get estimatedDistanceMeters {
    const measuredPower = -59;
    const n = 2.5;
    final ratio = (measuredPower - lastRssi) / (10 * n);
    return pow(10, ratio).toDouble().clamp(0.5, 1000.0);
  }
}

/// Native Hardware BLE 5.0 LE Coded PHY Service & Mesh Relay Engine
class RealBleService {
  static final RealBleService instance = RealBleService._internal();
  RealBleService._internal();

  static const MethodChannel _methodChannel = MethodChannel('com.example.flare/ble');
  static const EventChannel _packetEventChannel = EventChannel('com.example.flare/packet_stream');
  static const EventChannel _statusEventChannel = EventChannel('com.example.flare/status_stream');

  // Notify UI when local messages are added to SharedPreferences
  
  // Notify UI when local messages are added to SharedPreferences
  static final StreamController<void> messageHistoryNotifier = StreamController<void>.broadcast();

  // Fragment Buffers for incoming chopped messages
  final Map<int, Map<int, Uint8List>> _fragmentBuffers = {};


  bool _isInitialized = false;
  bool _isBroadcasting = false;
  bool _isEmergencySosBroadcasting = false;
  bool _isScanning = false;
  DateTime? _broadcastStartTime;
  Timer? _heartbeatTimer;

  void recordLastReceivedMsgId(int msgId) {}

  bool get isBroadcasting => _isBroadcasting;
  bool get isEmergencySosBroadcasting => _isEmergencySosBroadcasting;
  bool get isScanning => _isScanning;
  DateTime? get broadcastStartTime => _broadcastStartTime;

  Map<String, dynamic> _hardwareCapabilities = {
    'isBluetoothEnabled': false,
    'isLeCodedPhySupported': false,
    'isLe2MPhySupported': false,
    'isExtendedAdvertisingSupported': false,
  };
  Map<String, dynamic> get hardwareCapabilities => _hardwareCapabilities;

  BlePhyMode activePhyMode = BlePhyMode.standard1M;

  final List<RealBlePacket> _receivedPackets = [];
  final Map<String, RealPeerNode> _discoveredPeers = {};
  final Set<String> _seenPacketIds = {};

  final _packetStreamController = StreamController<RealBlePacket>.broadcast();
  final _peerStreamController = StreamController<List<RealPeerNode>>.broadcast();
  final _statusStreamController = StreamController<String>.broadcast();

  Stream<RealBlePacket> get packetStream => _packetStreamController.stream;
  Stream<List<RealPeerNode>> get peerStream => _peerStreamController.stream;
  Stream<String> get statusStream => _statusStreamController.stream;

  List<RealBlePacket> get receivedPackets => List.unmodifiable(_receivedPackets);
  List<RealPeerNode> get discoveredPeers => _discoveredPeers.values.toList();

  RealBlePacket? _currentActiveSos;
  RealBlePacket? get currentActiveSos => _currentActiveSos;

  int _broadcastSessionId = 0;

  /// Initialize hardware, check LE Coded PHY capabilities, request runtime permissions
  Future<bool> init() async {
    if (_isInitialized) return true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('seen_packets'); // Purge legacy poisoned packet cache

      // 1. Request Runtime Permissions adaptively across Android 8 through 14+
      try {
        if (!await Permission.locationWhenInUse.isGranted) {
          await Permission.locationWhenInUse.request();
        }
      } catch (_) {}

      try {
        if (!await Permission.bluetoothScan.isGranted) {
          await [
            Permission.bluetoothScan,
            Permission.bluetoothAdvertise,
            Permission.bluetoothConnect,
          ].request();
        }
      } catch (_) {}

      try {
        if (!await Permission.notification.isGranted) {
          await Permission.notification.request();
        }
      } catch (_) {}

      // Non-blocking battery optimization check (UI onboarding dialog handles interactive prompt)
      NotificationService.instance.isBatteryOptimizationIgnored().then((isIgnored) {
        if (!isIgnored) {
          NotificationService.instance.requestIgnoreBatteryOptimization();
        }
      }).catchError((_) {});

      // 2. Query Native Hardware Capabilities
      final caps = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('checkHardwareSupport');
      if (caps != null) {
        _hardwareCapabilities = Map<String, dynamic>.from(caps);
      }

      // 3. Fallback PHY if device hardware does not support LE Coded PHY
      if (_hardwareCapabilities['isLeCodedPhySupported'] != true) {
        activePhyMode = BlePhyMode.standard1M;
      }

      // 4. Setup Native Event Channels
      _packetEventChannel.receiveBroadcastStream().listen(
        _onNativePacketReceived,
        onError: (err) {},
      );

      _statusEventChannel.receiveBroadcastStream().listen(
        (status) {
          _statusStreamController.add(status.toString());
        },
        onError: (err) {},
      );

      // 5. Replay any pending packets captured by native Kotlin while app was closed
      Future.delayed(const Duration(milliseconds: 300), () async {
        await replayPendingBackgroundPackets();
      });

      // 6. Rehydrate discovered peers from persistent cache (saved by native service or previous session)
      await reloadNearbyPeersCache();

      _isInitialized = true;
      await startScanning();
      startHeartbeat();
      return true;
    } catch (_) {
      return false;
    }
  }

  // Consistent hash for a string to avoid Dart's randomized isolate hashCodes
  int consistentHash(String str) {
    final clean = str.trim().replaceAll('PUB_KEY_', '').toUpperCase();
    int hash = 0;
    for (int i = 0; i < clean.length; i++) {
      hash = 0x1fffffff & (hash + clean.codeUnitAt(i));
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }

  /// Periodic Presence Heartbeat is managed continuously in hardware silicon by native MeshForegroundService
  void startHeartbeat() {
    _heartbeatTimer?.cancel();
    try {
      _methodChannel.invokeMethod('startPresenceHeartbeat');
    } catch (_) {}
    // Periodic watchdog to ensure presence beacon stays fresh across deep sleep or long sessions
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!_isBroadcasting && !_isEmergencySosBroadcasting) {
        try {
          _methodChannel.invokeMethod('startPresenceHeartbeat');
        } catch (_) {}
      }
    });
  }

  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  DateTime? _lastPeerPersistTime;
  void _persistDiscoveredPeers() {
    final now = DateTime.now();
    if (_lastPeerPersistTime != null && now.difference(_lastPeerPersistTime!).inMilliseconds < 2500) {
      return;
    }
    _lastPeerPersistTime = now;
    Future.microtask(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final list = _discoveredPeers.values.map((p) => {
          'senderHash': p.senderHash,
          'lastRssi': p.lastRssi,
          'lastSeen': p.lastSeen.millisecondsSinceEpoch,
          'deviceAddress': p.deviceAddress,
          'packetCount': p.packetCount,
        }).toList();
        final jsonStr = jsonEncode(list);
        await prefs.setString('flare_nearby_peers_cache', jsonStr);
        await prefs.setString('resqmesh_nearby_peers_cache', jsonStr);
      } catch (_) {}
    });
  }

  /// Delete a single peer from discovered peers, persistent cache, and native service
  Future<void> deletePeer(int senderHash) async {
    final senderKey = senderHash.toString();
    _discoveredPeers.remove(senderKey);
    _peerStreamController.add(_discoveredPeers.values.toList());

    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _discoveredPeers.values.map((p) => {
        'senderHash': p.senderHash,
        'lastRssi': p.lastRssi,
        'lastSeen': p.lastSeen.millisecondsSinceEpoch,
        'deviceAddress': p.deviceAddress,
        'packetCount': p.packetCount,
      }).toList();
      final jsonStr = jsonEncode(list);
      await prefs.setString('flare_nearby_peers_cache', jsonStr);
      await prefs.setString('resqmesh_nearby_peers_cache', jsonStr);
    } catch (_) {}

    try {
      await _methodChannel.invokeMethod('deletePeer', {'senderHash': senderHash});
    } catch (_) {}
  }

  /// Remove all unknown peers (peers not saved in ContactVault) from history
  Future<void> clearUnknownPeers() async {
    final knownHashes = ContactVault.contacts
        .where((c) => c.publicKey.isNotEmpty)
        .map((c) => ContactVault.getContactHash(c))
        .toSet();

    _discoveredPeers.removeWhere((key, p) => !knownHashes.contains(p.senderHash) && !ContactVault.contacts.any((c) => ContactVault.matchesSender(c, p.senderHash)));
    _peerStreamController.add(_discoveredPeers.values.toList());

    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _discoveredPeers.values.map((p) => {
        'senderHash': p.senderHash,
        'lastRssi': p.lastRssi,
        'lastSeen': p.lastSeen.millisecondsSinceEpoch,
        'deviceAddress': p.deviceAddress,
        'packetCount': p.packetCount,
      }).toList();
      final jsonStr = jsonEncode(list);
      await prefs.setString('flare_nearby_peers_cache', jsonStr);
      await prefs.setString('resqmesh_nearby_peers_cache', jsonStr);
    } catch (_) {}

    try {
      await _methodChannel.invokeMethod('clearUnknownPeers');
    } catch (_) {}
  }

  /// Broadcast a Chat Message over Bluetooth Mesh (fast, silent, burst with auto-stop)
  Future<String?> broadcastChatMessage({
    required MessageMode mode,
    required String text,
    String? targetContactId,
    BlePhyMode phy = BlePhyMode.standard1M,
    int? customMsgId,
  }) async {
    await init();
    _heartbeatTimer?.cancel();
    await startScanning();

    final myPubKey = ContactVault.myKeyPair['publicKey'];
    final myHash = myPubKey != null ? consistentHash(myPubKey) & 0xFFFF : 0;

    int recipientHash = 0;
    String? targetPubKey;
    if (mode == MessageMode.privateE2ee && targetContactId != null) {
      final c = ContactVault.getById(targetContactId);
      if (c != null) {
        recipientHash = ContactVault.getContactHash(c);
        targetPubKey = c.publicKey;
      } else if (targetContactId.startsWith('peer_')) {
        final pHash = int.tryParse(targetContactId.substring(5)) ?? 0;
        recipientHash = pHash;
        try {
          final prefs = await SharedPreferences.getInstance();
          targetPubKey = prefs.getString('unknown_pubkey_$pHash');
          if (targetPubKey == null || targetPubKey.isEmpty) {
            targetPubKey = ContactVault.generateKeyForHash(pHash);
          }
        } catch (_) {}
      }
    }

    Uint8List payloadBytes;
    if (mode == MessageMode.privateE2ee && targetPubKey != null && myPubKey != null) {
      final rawBytes = Uint8List.fromList(utf8.encode(text));
      payloadBytes = CryptoEngine.encryptBytes(
        rawBytes: rawBytes,
        recipientPubKey: targetPubKey,
        senderPubKey: myPubKey,
      );
    } else {
      payloadBytes = Uint8List.fromList(utf8.encode(text));
    }

    final randomInt = (DateTime.now().microsecondsSinceEpoch ^ (text.hashCode)) & 0xFFFF;
    final msgId = customMsgId ?? (randomInt == 0 ? 1 : randomInt);
    final packetId = 'PKT_${msgId}_$myHash';

    final phyString = (phy == BlePhyMode.leCodedS8 || phy == BlePhyMode.leCodedS2) ? 'leCodedS8' : 'standard1M';

    // 1. Single-Frame Packet: fits in <= 24 bytes legacy advertisement (zero scan response needed!)
    if (payloadBytes.length <= 12) {
      final packet = ByteData(12 + payloadBytes.length);
      packet.setUint8(0, 0x52); // 'R'
      packet.setUint8(1, 0x51); // 'Q'
      packet.setUint8(2, 0x4D); // 'M' = Mesh Chat Packet
      packet.setUint8(3, mode.index);
      packet.setUint16(4, msgId, Endian.big);
      packet.setUint8(6, 3); // TTL = 3
      packet.setUint16(7, myHash, Endian.big);
      packet.setUint16(9, recipientHash, Endian.big);
      packet.setUint8(11, payloadBytes.length);
      for (int i = 0; i < payloadBytes.length; i++) {
        packet.setUint8(12 + i, payloadBytes[i]);
      }

      final frame = packet.buffer.asUint8List();
      final sessionId = ++_broadcastSessionId;
      _activeBroadcastingBytes = frame;
      _isBroadcasting = true;
      _broadcastStartTime = DateTime.now();

      await _methodChannel.invokeMethod<bool>('startAdvertising', {
        'payload': frame,
        'phyMode': phyString,
      });

      // Listen for early delivery ACK to stop broadcasting immediately once received (for private chats)
      StreamSubscription? ackSub;
      if (mode == MessageMode.privateE2ee) {
        ackSub = packetStream.listen((pkt) {
          if (pkt.decryptedPayload == '__ACK__:$msgId' || pkt.rawPayload == '__ACK__:$msgId') {
            ackSub?.cancel();
            if (_broadcastSessionId == sessionId && !_isEmergencySosBroadcasting) {
              stopBroadcasting();
            }
          }
        });
      }

      // Continuous broadcast: 6.0s for private chat (guarantees receiver captures under Android 8 duty cycle), 2.8s for public chat
      final broadcastDuration = (mode == MessageMode.privateE2ee) ? 6000 : 2800;
      Future.delayed(Duration(milliseconds: broadcastDuration), () {
        ackSub?.cancel();
        if (_broadcastSessionId == sessionId && !_isEmergencySosBroadcasting) {
          stopBroadcasting();
        }
      });

      return packetId;
    }

    // 2. Fragmented Packet: for text > 12 bytes (12-byte slices fit 100% in chunk1 with zero scan response)
    final chunks = <Uint8List>[];
    const sliceSize = 12;
    int totalChunks = (payloadBytes.length / sliceSize).ceil();
    if (totalChunks > 255) totalChunks = 255;

    for (int i = 0; i < totalChunks; i++) {
      int start = i * sliceSize;
      int end = (start + sliceSize).clamp(0, payloadBytes.length);
      final slice = payloadBytes.sublist(start, end);

      final buffer = ByteData(12 + slice.length);
      buffer.setUint8(0, 0x52); // 'R'
      buffer.setUint8(1, 0x51); // 'Q'
      buffer.setUint8(2, 0xFE); // 0xFE = Fragmented frame
      buffer.setUint8(3, mode.index);
      buffer.setUint16(4, msgId, Endian.big);
      buffer.setUint8(6, totalChunks);
      buffer.setUint8(7, i); // chunk index
      buffer.setUint16(8, myHash, Endian.big);
      buffer.setUint16(10, recipientHash, Endian.big);
      for (int j = 0; j < slice.length; j++) {
        buffer.setUint8(12 + j, slice[j]);
      }
      chunks.add(buffer.buffer.asUint8List());
    }

    final sessionId = ++_broadcastSessionId;
    _isBroadcasting = true;
    _broadcastStartTime = DateTime.now();

    StreamSubscription? ackSub;
    if (mode == MessageMode.privateE2ee) {
      ackSub = packetStream.listen((pkt) {
        if (pkt.decryptedPayload == '__ACK__:$msgId' || pkt.rawPayload == '__ACK__:$msgId') {
          ackSub?.cancel();
          if (_broadcastSessionId == sessionId && !_isEmergencySosBroadcasting) {
            stopBroadcasting();
          }
        }
      });
    }

    // Cycle through fragments 5 times with 350ms delay per fragment (spans Android 8 duty cycle, cancels early on ACK)
    () async {
      for (int cycle = 0; cycle < 5; cycle++) {
        for (final chunk in chunks) {
          if (_broadcastSessionId != sessionId || _isEmergencySosBroadcasting) {
            ackSub?.cancel();
            return;
          }
          _activeBroadcastingBytes = chunk;
          await _methodChannel.invokeMethod<bool>('startAdvertising', {
            'payload': chunk,
            'phyMode': phyString,
          });
          await Future.delayed(const Duration(milliseconds: 350));
        }
      }
      ackSub?.cancel();
      if (_broadcastSessionId == sessionId && !_isEmergencySosBroadcasting) {
        await stopBroadcasting();
      }
    }();

    return packetId;
  }

  /// Send Delivery Confirmation ACK back to sender (binary 10-byte frame 0x41)
  Future<void> sendDeliveryAck({
    required int targetRecipientHash,
    required int msgId,
    BlePhyMode phy = BlePhyMode.standard1M,
  }) async {
    final myPubKey = ContactVault.myKeyPair['publicKey'];
    final myHash = myPubKey != null ? consistentHash(myPubKey) & 0xFFFF : 0;

    final packet = ByteData(10);
    packet.setUint8(0, 0x52); // 'R'
    packet.setUint8(1, 0x51); // 'Q'
    packet.setUint8(2, 0x41); // 'A' = Dedicated Delivery ACK Frame!
    packet.setUint8(3, 3);    // TTL = 3 (so mules can relay it!)
    packet.setUint16(4, msgId, Endian.big);
    packet.setUint16(6, myHash, Endian.big);
    packet.setUint16(8, targetRecipientHash & 0xFFFF, Endian.big);

    final frame = packet.buffer.asUint8List();
    final phyString = (phy == BlePhyMode.leCodedS8 || phy == BlePhyMode.leCodedS2) ? 'leCodedS8' : 'standard1M';

    _heartbeatTimer?.cancel();
    final sessionId = ++_broadcastSessionId;
    _activeBroadcastingBytes = frame;
    _isBroadcasting = true;
    _broadcastStartTime = DateTime.now();

    // Broadcast ACK for 3200ms to guarantee sender catches the ACK without locking up the radio
    await _methodChannel.invokeMethod<bool>('startAdvertising', {
      'payload': frame,
      'phyMode': phyString,
    });

    Future.delayed(const Duration(milliseconds: 3200), () async {
      if (_broadcastSessionId == sessionId && !_isEmergencySosBroadcasting) {
        await stopBroadcasting();
      }
    });
  }

  /// Dedicated Emergency SOS Broadcasting (Continuous Distress Beacon)
  Future<String?> startBroadcastingEmergencySos({
    required MessageMode mode,
    required String note,
    required BlePhyMode phy,
    String? targetContactId,
    double? customLat,
    double? customLng,
  }) async {
    await init();
    await startScanning();

    Position? pos;
    try {
      pos = await RealGpsService.instance.getCurrentPosition().timeout(const Duration(seconds: 5), onTimeout: () => throw Exception());
    } catch (_) {}

    final lat = customLat ?? pos?.latitude ?? 0.0;
    final lng = customLng ?? pos?.longitude ?? 0.0;
    final alt = pos?.altitude ?? 0.0;

    int recipientHash = 0;
    if (targetContactId != null) {
      final c = ContactVault.getById(targetContactId);
      if (c != null) {
        recipientHash = ContactVault.getContactHash(c);
      }
    }

    final myPubKey = ContactVault.myKeyPair['publicKey'];
    final myHash = myPubKey != null ? consistentHash(myPubKey) & 0xFFFF : 0;

    final randomInt = (DateTime.now().microsecondsSinceEpoch ^ (note.hashCode)) & 0xFFFF;
    final msgId = randomInt == 0 ? 1 : randomInt;
    final packetId = 'PKT_SOS_${msgId}_$myHash';

    final cleanNote = note.trim();
    final noteBytes = Uint8List.fromList(utf8.encode(cleanNote));
    final cappedNoteBytes = (noteBytes.length > 27) ? noteBytes.sublist(0, 27) : noteBytes;

    final packet = ByteData(21 + cappedNoteBytes.length);
    packet.setUint8(0, 0x52); // 'R'
    packet.setUint8(1, 0x51); // 'Q'
    packet.setUint8(2, 0x53); // 'S' = Dedicated Emergency SOS Frame with Note (up to 48 bytes)
    packet.setUint8(3, mode.index);
    packet.setUint8(4, 5);    // TTL = 5
    packet.setUint16(5, msgId, Endian.big);
    packet.setUint16(7, myHash, Endian.big);
    packet.setUint16(9, recipientHash, Endian.big);
    packet.setFloat32(11, lat, Endian.big);
    packet.setFloat32(15, lng, Endian.big);
    packet.setInt8(19, alt.toInt().clamp(-128, 127));
    packet.setUint8(20, cappedNoteBytes.length);
    for (int i = 0; i < cappedNoteBytes.length; i++) {
      packet.setUint8(21 + i, cappedNoteBytes[i]);
    }

    final binaryPacket = packet.buffer.asUint8List();
    final phyString = (phy == BlePhyMode.leCodedS8 || phy == BlePhyMode.leCodedS2) ? 'leCodedS8' : 'standard1M';

    _heartbeatTimer?.cancel();
    _isEmergencySosBroadcasting = true;
    _isBroadcasting = true;
    _broadcastStartTime = DateTime.now();
    _startEmergencyPulseLoop(binaryPacket, phyString);

    return packetId;
  }

  void _startEmergencyPulseLoop(Uint8List packet, String phyString) async {
    while (_isEmergencySosBroadcasting) {
      // 1. Broadcast the Emergency SOS frame (GPS + Note) for 800ms
      _activeBroadcastingBytes = packet;
      try {
        await _methodChannel.invokeMethod<bool>('startAdvertising', {
          'payload': packet,
          'phyMode': phyString,
        });
      } catch (_) {}

      await Future.delayed(const Duration(milliseconds: 800));
      if (!_isEmergencySosBroadcasting) break;

      // 2. Pause advertising for 1200ms so our own radio can scan & hear nearby devices and delivery ACKs
      try {
        await _methodChannel.invokeMethod('stopAdvertising');
      } catch (_) {}
      _activeBroadcastingBytes = null;
      await startScanning();

      await Future.delayed(const Duration(milliseconds: 1200));
    }
  }

  /// Backward-compatible wrapper for Emergency SOS
  Future<String?> startBroadcastingSos({
    required MessageMode mode,
    required String note,
    required BlePhyMode phy,
    String? targetContactId,
    double? customLat,
    double? customLng,
  }) => startBroadcastingEmergencySos(
    mode: mode,
    note: note,
    phy: phy,
    targetContactId: targetContactId,
    customLat: customLat,
    customLng: customLng,
  );

  Uint8List? _activeBroadcastingBytes;
  Uint8List? get activeBroadcastingBytes => _activeBroadcastingBytes;

  static List<int> hexToBytes(String hex) {
    hex = hex.trim().replaceAll('PUB_KEY_', '');
    final bytes = <int>[];
    for (int i = 0; i < hex.length && i + 1 < hex.length; i += 2) {
      final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (byte != null) bytes.add(byte);
    }
    return bytes;
  }

  static String bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<bool> broadcastRawBytes({
    required Uint8List bytes,
    required BlePhyMode phy,
  }) async {
    await init();
    _heartbeatTimer?.cancel();
    ++_broadcastSessionId;
    _activeBroadcastingBytes = bytes;
    _broadcastStartTime = DateTime.now();
    final phyString = (phy == BlePhyMode.leCodedS8 || phy == BlePhyMode.leCodedS2) ? 'leCodedS8' : 'standard1M';
    final success = await _methodChannel.invokeMethod<bool>('startAdvertising', {
      'payload': bytes,
      'phyMode': phyString,
    });
    _isBroadcasting = success ?? true;
    return _isBroadcasting;
  }

  Future<void> stopBroadcasting() async {
    try {
      await _methodChannel.invokeMethod('stopAdvertising');
    } catch (_) {}
    _isBroadcasting = false;
    _isEmergencySosBroadcasting = false;
    _activeBroadcastingBytes = null;
    _broadcastStartTime = null;
    await startScanning();
    startHeartbeat();
  }

  final Map<String, DateTime> _recentSyncReplies = {};
  DateTime? _lastReciprocalBroadcastTime;

  static Uint8List buildContactSyncPacket({required String name, required String rawPublicKey}) {
    final strippedKey = rawPublicKey.replaceAll('PUB_KEY_', '').trim();
    final cleanName = name.trim().isEmpty ? 'User' : name.trim();
    final trimmedName = cleanName.length > 13 ? cleanName.substring(0, 13) : cleanName;
    final keyBytes = hexToBytes(strippedKey);
    return Uint8List.fromList([
      0x53, // 'S'
      0x7C, // '|'
      ...utf8.encode(trimmedName),
      0x7C, // '|'
      ...keyBytes,
    ]);
  }

  Future<void> sendReciprocalSyncCard() async {
    if (_isBroadcasting) return;
    final now = DateTime.now();
    if (_lastReciprocalBroadcastTime != null &&
        now.difference(_lastReciprocalBroadcastTime!).inSeconds < 8) {
      return;
    }
    _lastReciprocalBroadcastTime = now;

    final myKey = ContactVault.myKeyPair['publicKey'];
    final prefs = await SharedPreferences.getInstance();
    final myName = prefs.getString('my_profile_name') ?? 'User';
    if (myKey == null || myKey.isEmpty) return;

    final packetBytes = buildContactSyncPacket(name: myName, rawPublicKey: myKey);
    await broadcastRawBytes(bytes: packetBytes, phy: BlePhyMode.standard1M);
    Future.delayed(const Duration(milliseconds: 3200), () {
      stopBroadcasting();
    });
  }

  void _processIncomingSyncCard({
    required String peerName,
    required String rawHexKey,
    required int rssi,
    required String deviceAddress,
  }) {
    final cleanPeerKey = rawHexKey.toLowerCase();
    final myKey = (ContactVault.myKeyPair['publicKey'] ?? '').trim().replaceAll('PUB_KEY_', '').toLowerCase();
    if (myKey.isNotEmpty && cleanPeerKey == myKey) {
      return; // Drop our own packet!
    }

    final fullPubKey = 'PUB_KEY_${rawHexKey.toUpperCase()}';
    final senderHash = consistentHash(fullPubKey) & 0xFFFF;
    final myHash = myKey.isNotEmpty ? (consistentHash(myKey) & 0xFFFF) : 0;
    if (myHash != 0 && senderHash == myHash) {
      return; // Drop our own packet!
    }
    final displayName = peerName.trim().isEmpty ? 'Nearby User' : peerName.trim();

    // 1. Update Live Nearby Peers Radar
    final senderKey = senderHash.toString();
    _discoveredPeers[senderKey] = RealPeerNode(
      senderHash: senderHash,
      deviceAddress: deviceAddress,
      lastRssi: rssi,
      lastSeen: DateTime.now(),
      phyMode: BlePhyMode.standard1M,
      lat: null,
      lng: null,
      packetCount: (_discoveredPeers[senderKey]?.packetCount ?? 0) + 1,
    );
    _peerStreamController.add(_discoveredPeers.values.toList());
    _persistDiscoveredPeers();

    // 2. Schedule reciprocal broadcast to fire after sender finishes (at 3.6s)
    final now = DateTime.now();
    final lastReply = _recentSyncReplies[cleanPeerKey];
    if (lastReply == null || now.difference(lastReply).inSeconds > 4) {
      _recentSyncReplies[cleanPeerKey] = now;
      Timer(const Duration(milliseconds: 3600), () {
        sendReciprocalSyncCard();
      });
    }

    // 3. Dispatch to packet stream so UI displays Incoming Contact Sync modal dialog
    final rawText = 'SYNC|$displayName|$fullPubKey';
    final parsedSync = RealBlePacket(
      packetId: 'PKT_SYNC_${senderHash}_${DateTime.now().millisecondsSinceEpoch ~/ 4000}',
      mode: MessageMode.publicSos,
      phyMode: BlePhyMode.standard1M,
      lat: 0.0,
      lng: 0.0,
      altitude: 0.0,
      ttl: 0,
      senderHash: senderHash,
      recipientHash: 0,
      rawPayload: rawText,
      decryptedPayload: rawText,
      rssi: rssi,
      receivedTime: DateTime.now(),
      deviceAddress: deviceAddress,
    );
    _receivedPackets.insert(0, parsedSync);
    _packetStreamController.add(parsedSync);
  }

  Future<void> startScanning() async {
    if (_isScanning) return;
    try {
      await _methodChannel.invokeMethod('startScanning');
      _isScanning = true;
    } catch (_) {}
  }

  Future<void> wakeUpMesh() async {
    try {
      await _methodChannel.invokeMethod('wakeUpMesh');
      _isScanning = true;
    } catch (_) {
      await startScanning();
    }
    startHeartbeat();
    await reloadNearbyPeersCache();
    await replayPendingBackgroundPackets();
  }

  Future<void> rescanMesh() async {
    _isScanning = false;
    await wakeUpMesh();
  }

  void injectWifiPacket(String payload) {

    final packetId = 'PKT_WIFI_';
    final parsed = RealBlePacket(
      packetId: packetId,
      mode: MessageMode.privateE2ee,
      phyMode: BlePhyMode.standard1M,
      lat: 0.0,
      lng: 0.0,
      altitude: 0.0,
      ttl: 1,
      senderHash: 0,
      recipientHash: 0,
      rawPayload: payload,
      decryptedPayload: payload,
      rssi: -30,
      receivedTime: DateTime.now(),
      deviceAddress: 'WIFI_DIRECT',
    );
    
    _receivedPackets.insert(0, parsed);
    _packetStreamController.add(parsed);
  }

  /// Rehydrate discovered peers immediately from persistent cache saved by background service
  Future<void> reloadNearbyPeersCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final peersCacheJson = prefs.getString('flare_nearby_peers_cache') ?? prefs.getString('resqmesh_nearby_peers_cache');
      if (peersCacheJson != null && peersCacheJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(peersCacheJson);
        final myPubKey = ContactVault.myKeyPair['publicKey'];
        final myHash = myPubKey != null ? (consistentHash(myPubKey) & 0xFFFF) : 0;
        final knownHashes = ContactVault.contacts
            .where((c) => c.publicKey.isNotEmpty)
            .map((c) => ContactVault.getContactHash(c))
            .toSet();

        for (final item in list) {
          final senderHash = (item['senderHash'] as num?)?.toInt() ?? 0;
          if (senderHash == 0 || (myHash != 0 && senderHash == myHash)) continue;
          final lastRssi = (item['lastRssi'] as num?)?.toInt() ?? -70;
          final lastSeenMillis = (item['lastSeen'] as num?)?.toInt() ?? 0;
          final deviceAddress = (item['deviceAddress'] as String?) ?? 'UNKNOWN';
          final packetCount = (item['packetCount'] as num?)?.toInt() ?? 1;

          // If this is an unknown peer hash but deviceAddress belongs to an already loaded known contact, skip ghost entry
          final isUnknown = !knownHashes.contains(senderHash) &&
              !ContactVault.contacts.any((c) => ContactVault.matchesSender(c, senderHash));
          if (isUnknown && deviceAddress != 'UNKNOWN' && deviceAddress != 'OFFLINE') {
            final matchesKnownContact = _discoveredPeers.values.any(
              (p) => knownHashes.contains(p.senderHash) && p.deviceAddress == deviceAddress,
            );
            if (matchesKnownContact) continue;
          }

          final senderKey = senderHash.toString();
          final existing = _discoveredPeers[senderKey];
          final newLastSeen = lastSeenMillis > 0
              ? DateTime.fromMillisecondsSinceEpoch(lastSeenMillis)
              : (existing?.lastSeen ?? DateTime.now());

          if (existing == null || newLastSeen.isAfter(existing.lastSeen)) {
            _discoveredPeers[senderKey] = RealPeerNode(
              senderHash: senderHash,
              deviceAddress: deviceAddress,
              lastRssi: lastRssi,
              lastSeen: newLastSeen,
              phyMode: BlePhyMode.standard1M,
              packetCount: packetCount,
            );
          }
        }
        if (_discoveredPeers.isNotEmpty) {
          _peerStreamController.add(_discoveredPeers.values.toList());
        }
      }
    } catch (_) {}
  }

  /// Replay pending packets captured by native background service
  Future<void> replayPendingBackgroundPackets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingJson = prefs.getString('pending_background_packets');
      if (pendingJson != null && pendingJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(pendingJson);
        await prefs.remove('pending_background_packets');
        for (final item in list) {
          try {
            final payloadBase64 = item['payload'] as String;
            final payloadBytes = Uint8List.fromList(base64Decode(payloadBase64));
            final rssi = (item['rssi'] as num?)?.toInt() ?? -50;
            final deviceAddress = (item['deviceAddress'] as String?) ?? 'UNKNOWN';
            _onNativePacketReceived({
              'payload': payloadBytes,
              'rssi': rssi,
              'deviceAddress': deviceAddress,
            }, isReplay: true);
          } catch (_) {}
        }
        messageHistoryNotifier.add(null);
      }
    } catch (_) {}
  }

  /// Process incoming raw BLE advertisement payload received from hardware
  void _onNativePacketReceived(dynamic rawEvent, {bool isReplay = false}) {
    if (rawEvent is! Map) return;

    try {
      final payloadBytes = rawEvent['payload'] as Uint8List?;
      final rssi = (rawEvent['rssi'] as num?)?.toInt() ?? -70;
      final deviceAddress = rawEvent['deviceAddress'] as String? ?? 'UNKNOWN';
      final primaryPhy = (rawEvent['primaryPhy'] as num?)?.toInt() ?? 1;

      if (payloadBytes == null || payloadBytes.length < 8) return;

      // 0. Drop our own active broadcast packet immediately
      if (_activeBroadcastingBytes != null && listEquals(payloadBytes, _activeBroadcastingBytes)) {
        return;
      }

      // 1. Compact Auto Sync format: 'S' (0x53) '|' (0x7C) name '|' 8_bytes_key (length 11 to 24 bytes)
      if (payloadBytes.length >= 11 && payloadBytes[0] == 0x53 && payloadBytes[1] == 0x7C) {
        int secondSep = -1;
        for (int i = 2; i < payloadBytes.length; i++) {
          if (payloadBytes[i] == 0x7C) {
            secondSep = i;
            break;
          }
        }
        if (secondSep != -1 && payloadBytes.length >= secondSep + 1 + 8) {
          final nameBytes = payloadBytes.sublist(2, secondSep);
          final keyBytes = payloadBytes.sublist(secondSep + 1, secondSep + 1 + 8);
          final peerName = utf8.decode(nameBytes, allowMalformed: true).trim();
          final rawHexKey = bytesToHex(keyBytes);

          _processIncomingSyncCard(
            peerName: peerName,
            rawHexKey: rawHexKey,
            rssi: rssi,
            deviceAddress: deviceAddress,
          );
          return;
        }
      }

      // 2. Legacy / String Auto Sync Fallback
      final rawText = utf8.decode(payloadBytes, allowMalformed: true).trim().replaceAll('\u0000', '');
      if (rawText.startsWith('SYNC|') || rawText.startsWith('CONTACT_SYNC|')) {
        final parts = rawText.split('|');
        if (parts.length >= 3) {
          final peerName = parts[1].trim();
          final rawHexKey = parts[2].trim().replaceAll('PUB_KEY_', '');
          _processIncomingSyncCard(
            peerName: peerName,
            rawHexKey: rawHexKey,
            rssi: rssi,
            deviceAddress: deviceAddress,
          );
          return;
        }
      }

      final parsed = _deserializePacket(payloadBytes, rssi, deviceAddress, primaryPhy);
      if (parsed == null) return;

      final myPubKey = ContactVault.myKeyPair['publicKey'];
      final myHash = myPubKey != null ? (consistentHash(myPubKey) & 0xFFFF) : 0;
      if (myHash != 0 && parsed.senderHash == myHash) {
        return; // Drop our own packet!
      }

      // Update Live Nearby Peers Radar
      final senderKey = parsed.senderHash.toString();
      _discoveredPeers[senderKey] = RealPeerNode(
        senderHash: parsed.senderHash,
        deviceAddress: deviceAddress, // Update silently behind the scenes
        lastRssi: rssi,
        lastSeen: DateTime.now(),
        phyMode: parsed.phyMode,
        lat: (parsed.lat != 0.0) ? parsed.lat : _discoveredPeers[senderKey]?.lat,
        lng: (parsed.lng != 0.0) ? parsed.lng : _discoveredPeers[senderKey]?.lng,
        packetCount: (_discoveredPeers[senderKey]?.packetCount ?? 0) + 1,
      );
      _peerStreamController.add(_discoveredPeers.values.toList());
      _persistDiscoveredPeers();

      // Silently consume presence heartbeats without adding to chat or firing alarms
      if (parsed.decryptedPayload == '__HEARTBEAT__') {
        return;
      }

      // Trigger System Push Notification strictly if intended for me and is a REAL emergency distress beacon!
      bool isForMe = false;
      final bool isAck = parsed.decryptedPayload.startsWith('__ACK__:');

      if (parsed.mode == MessageMode.privateE2ee) {
        final myPubKey = ContactVault.myKeyPair['publicKey'];
        if (myPubKey != null) {
          final myHash = consistentHash(myPubKey) & 0xFFFF;
          if (parsed.recipientHash == myHash) {
            isForMe = true;
          }
        }
      } else {
        isForMe = true;
      }

      // Auto-reply with delivery ACK immediately if this message is for me, is not an ACK, and is not a replayed background packet.
      // CRITICAL: We send the ACK BEFORE dropping duplicates! If sender missed our first ACK, sender's retransmission
      // will trigger this re-ACK, guaranteeing sender gets their white delivery tick!
      if (isForMe && !isAck && !isReplay) {
        final parts = parsed.packetId.split('_');
        int? msgId;
        if (parts.length >= 3 && parts[1] == 'SOS') {
          msgId = int.tryParse(parts[2]);
        } else if (parts.length >= 2) {
          msgId = int.tryParse(parts[1]);
        }
        if (msgId != null && parsed.senderHash != 0) {
          sendDeliveryAck(
            targetRecipientHash: parsed.senderHash,
            msgId: msgId,
            phy: activePhyMode,
          );
        }
      }

      // Deduplication check (strictly in-memory rolling LRU)
      // Dropping here ensures duplicates are ACKed above, but NOT inserted into chat UI or alert sound
      final isNew = _seenPacketIds.add(parsed.packetId);
      if (!isNew) return;

      if (_seenPacketIds.length > 500) {
        _seenPacketIds.remove(_seenPacketIds.first);
      }

      _receivedPackets.insert(0, parsed);
      _packetStreamController.add(parsed);

      // Loud SOS Push Notification is STRICTLY reserved for Emergency SOS mode!
      // Broadcast chat (publicChat), ACKs, and normal private messages NEVER fire this alarm.
      if (isForMe && !isAck && !isReplay) {
        if (parsed.mode == MessageMode.publicSos || parsed.mode == MessageMode.hybridSos) {
          final title = parsed.mode == MessageMode.publicSos ? 'Public Emergency SOS!' : 'Private Emergency SOS!';
          NotificationService.instance.showSosNotification(title, 'Received emergency packet from mesh network.');
        }
      }
    } catch (_) {}
  }

  /// Binary Packet Serializer (Legacy format)
  Uint8List serializeLegacyPacket({
    required String packetId,
    required MessageMode mode,
    required BlePhyMode phyMode,
    required double lat,
    required double lng,
    required double alt,
    required int ttl,
    required int senderHash,
    required int recipientHash,
    required String payload,
  }) {
    final isCompact = payload.startsWith("SOS|");
    final payloadUtf8 = utf8.encode(payload);
    final clampedPayload = payloadUtf8.take(180).toList(); // Compact size for BLE 5.0
    
    final headerSize = isCompact ? 14 : 24;

    final buffer = ByteData(headerSize + clampedPayload.length);
    // Magic bytes: 'R' (0x52), 'Q' (0x51)
    buffer.setUint8(0, 0x52);
    buffer.setUint8(1, 0x51);

    // Mode: 0=Public, 1=Private, 2=Hybrid
    buffer.setUint8(2, mode.index);
    // PHY: 0=1M, 1=CodedS8, 2=CodedS2, 3=2M
    buffer.setUint8(3, phyMode.index);

    if (isCompact) {
       buffer.setUint8(4, ttl);
       buffer.setUint32(5, packetId.hashCode & 0xFFFFFFFF, Endian.big);
       buffer.setUint16(9, senderHash & 0xFFFF, Endian.big);
       buffer.setUint16(11, recipientHash & 0xFFFF, Endian.big);
       buffer.setUint8(13, clampedPayload.length);
       
       for (int i = 0; i < clampedPayload.length; i++) {
         buffer.setUint8(14 + i, clampedPayload[i]);
       }
    } else {
        // GPS Lat / Lng (Float32 = 4 bytes each)
        buffer.setFloat32(4, lat, Endian.big);
        buffer.setFloat32(8, lng, Endian.big);
    
        // Alt (Int16 = 2 bytes)
        buffer.setInt16(12, alt.toInt(), Endian.big);
    
        // TTL
        buffer.setUint8(14, ttl);
    
        // Packet Hash
        buffer.setUint32(15, packetId.hashCode & 0xFFFFFFFF, Endian.big);
    
        // Sender / Recipient
        buffer.setUint16(19, senderHash & 0xFFFF, Endian.big);
        buffer.setUint16(21, recipientHash & 0xFFFF, Endian.big);
        
        // Payload length
        buffer.setUint8(23, clampedPayload.length);
        
        // Payload
        for (int i = 0; i < clampedPayload.length; i++) {
          buffer.setUint8(24 + i, clampedPayload[i]);
        }
    }

    return buffer.buffer.asUint8List();
  }

  /// Binary Packet Deserializer
  RealBlePacket? _deserializePacket(Uint8List bytes, int rssi, String deviceAddress, int primaryPhy) {
    if (bytes.length < 8) return null;

    final view = ByteData.sublistView(bytes);
    final magic0 = view.getUint8(0);
    final magic1 = view.getUint8(1);

    if (magic0 != 0x52 || magic1 != 0x51) return null;

    final formatByte = view.getUint8(2);

    // 0. Format 0x41: Dedicated Binary Delivery ACK Packet (10 bytes)
    if (formatByte == 0x41) {
      if (bytes.length < 10) return null;
      final ttl = view.getUint8(3);
      final msgId = view.getUint16(4, Endian.big);
      final ackSenderHash = view.getUint16(6, Endian.big);
      final targetRecipientHash = view.getUint16(8, Endian.big);

      final myPubKey = ContactVault.myKeyPair['publicKey'];
      final myHash = myPubKey != null ? (consistentHash(myPubKey) & 0xFFFF) : 0;

      // Only process if addressed to me (or broadcast target 0)
      if (myPubKey == null || (targetRecipientHash != myHash && targetRecipientHash != 0)) {
        return null;
      }

      final ackPacketId = 'PKT_ACK_${msgId}_$ackSenderHash';
      return RealBlePacket(
        packetId: ackPacketId,
        mode: MessageMode.privateE2ee,
        phyMode: BlePhyMode.standard1M,
        lat: 0.0,
        lng: 0.0,
        altitude: 0.0,
        ttl: ttl,
        senderHash: ackSenderHash,
        recipientHash: targetRecipientHash,
        rawPayload: '__ACK__:$msgId',
        decryptedPayload: '__ACK__:$msgId',
        rssi: rssi,
        receivedTime: DateTime.now(),
        deviceAddress: deviceAddress,
      );
    }

    // 0b. Format 0x48: Periodic Presence Heartbeat Beacon (8 bytes)
    if (formatByte == 0x48) {
      if (bytes.length < 8) return null;
      final senderHash = view.getUint16(4, Endian.big);
      final seqNum = view.getUint16(6, Endian.big);

      final myPubKey = ContactVault.myKeyPair['publicKey'];
      final myHash = myPubKey != null ? (consistentHash(myPubKey) & 0xFFFF) : 0;
      if (senderHash == myHash) return null; // Drop our own heartbeat

      return RealBlePacket(
        packetId: 'PKT_HB_${senderHash}_$seqNum',
        mode: MessageMode.privateE2ee,
        phyMode: BlePhyMode.standard1M,
        lat: 0.0,
        lng: 0.0,
        altitude: 0.0,
        ttl: 1,
        senderHash: senderHash,
        recipientHash: 0,
        rawPayload: '__HEARTBEAT__',
        decryptedPayload: '__HEARTBEAT__',
        rssi: rssi,
        receivedTime: DateTime.now(),
        deviceAddress: deviceAddress,
      );
    }

    // 0c. Format 0x53: Dedicated Compact Emergency SOS Beacon (20 bytes)
    if (formatByte == 0x53) {
      if (bytes.length < 20) return null;
      final modeIndex = view.getUint8(3).clamp(0, MessageMode.values.length - 1);
      final mode = MessageMode.values[modeIndex];
      final ttl = view.getUint8(4);
      final msgId = view.getUint16(5, Endian.big);
      final senderHash = view.getUint16(7, Endian.big);
      final recipientHash = view.getUint16(9, Endian.big);
      final lat = view.getFloat32(11, Endian.big);
      final lng = view.getFloat32(15, Endian.big);
      final alt = view.getInt8(19).toDouble();

      final myPubKey = ContactVault.myKeyPair['publicKey'];
      if (myPubKey != null && senderHash == (consistentHash(myPubKey) & 0xFFFF)) {
        return null; // Drop our own SOS packet
      }

      if (mode == MessageMode.privateE2ee && myPubKey != null) {
        final myHash = consistentHash(myPubKey) & 0xFFFF;
        if (recipientHash != myHash && recipientHash != 0) {
          return null; // Addressed to a different contact
        }
      }

      String noteStr = '';
      if (bytes.length > 20) {
        final noteLen = view.getUint8(20).clamp(0, bytes.length - 21);
        if (noteLen > 0) {
          noteStr = utf8.decode(bytes.sublist(21, 21 + noteLen), allowMalformed: true).trim();
        }
      }

      final locStr = "${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}";
      final payloadText = noteStr.isNotEmpty ? "$noteStr\n$locStr" : locStr;
      final packetId = 'PKT_SOS_${msgId}_$senderHash';

      return RealBlePacket(
        packetId: packetId,
        mode: mode,
        phyMode: BlePhyMode.standard1M,
        lat: lat,
        lng: lng,
        altitude: alt,
        ttl: ttl,
        senderHash: senderHash,
        recipientHash: recipientHash,
        rawPayload: payloadText,
        decryptedPayload: payloadText,
        rssi: rssi,
        receivedTime: DateTime.now(),
        deviceAddress: deviceAddress,
      );
    }

    // 1. Format 0x4D: Compact Single-Frame Mesh Chat Packet (<= 24 bytes)
    if (formatByte == 0x4D) {
      if (bytes.length < 12) return null;
      final modeIndex = view.getUint8(3).clamp(0, MessageMode.values.length - 1);
      final mode = MessageMode.values[modeIndex];
      final msgId = view.getUint16(4, Endian.big);
      final ttl = view.getUint8(6);
      final senderHash = view.getUint16(7, Endian.big);
      final recipientHash = view.getUint16(9, Endian.big);
      final payloadLen = view.getUint8(11);

      // Self-drop: ignore packets sent by ourselves
      final myPubKey = ContactVault.myKeyPair['publicKey'];
      if (myPubKey != null && senderHash == (consistentHash(myPubKey) & 0xFFFF)) {
        return null;
      }

      // If private, verify it is addressed to me
      if (mode == MessageMode.privateE2ee && myPubKey != null) {
        final myHash = consistentHash(myPubKey) & 0xFFFF;
        if (recipientHash != myHash) {
          return null; // Addressed to a different contact
        }
      }

      final safeLen = payloadLen.clamp(0, bytes.length - 12);
      final rawData = bytes.sublist(12, 12 + safeLen);

      String decryptedText = '';
      String? discoveredSenderPubKey;

      if (mode == MessageMode.privateE2ee && myPubKey != null) {
        String? senderPubKey;
        for (final c in ContactVault.contacts) {
          if (ContactVault.matchesSender(c, senderHash)) {
            senderPubKey = c.publicKey;
            break;
          }
        }

        if (senderPubKey != null) {
          try {
            final decryptedBytes = CryptoEngine.decryptBytes(
              cipherBytes: rawData,
              recipientPubKey: myPubKey,
              senderPubKey: senderPubKey,
            );
            decryptedText = utf8.decode(decryptedBytes, allowMalformed: true);
          } catch (_) {
            decryptedText = utf8.decode(rawData, allowMalformed: true);
          }
        } else {
          decryptedText = utf8.decode(rawData, allowMalformed: true);
        }
      } else {
        decryptedText = utf8.decode(rawData, allowMalformed: true);
      }

      final packetId = decryptedText.startsWith('SOS|')
          ? 'PKT_SOS_${msgId}_$senderHash'
          : 'PKT_${msgId}_$senderHash';
      return RealBlePacket(
        packetId: packetId,
        mode: mode,
        phyMode: BlePhyMode.standard1M,
        lat: 0.0,
        lng: 0.0,
        altitude: 0.0,
        ttl: ttl,
        senderHash: senderHash,
        recipientHash: recipientHash,
        rawPayload: decryptedText,
        decryptedPayload: decryptedText,
        rssi: rssi,
        receivedTime: DateTime.now(),
        deviceAddress: deviceAddress,
        senderPubKey: discoveredSenderPubKey,
      );
    }

    // 2. Format 0xFE: Fragmented Mesh Message
    if (formatByte == 0xFE) {
      if (bytes.length < 12) return null;
      final modeIndex = view.getUint8(3).clamp(0, MessageMode.values.length - 1);
      final mode = MessageMode.values[modeIndex];
      final msgId = view.getUint16(4, Endian.big);
      final total = view.getUint8(6);
      final index = view.getUint8(7);
      final senderHash = view.getUint16(8, Endian.big);
      final recipientHash = view.getUint16(10, Endian.big);

      if (total == 0 || index >= total) return null;

      final myPubKey = ContactVault.myKeyPair['publicKey'];
      if (myPubKey != null && senderHash == (consistentHash(myPubKey) & 0xFFFF)) {
        return null;
      }

      if (mode == MessageMode.privateE2ee && myPubKey != null) {
        final myHash = consistentHash(myPubKey) & 0xFFFF;
        if (recipientHash != myHash) return null;
      }

      final chunkBytes = bytes.sublist(12);
      _fragmentBuffers.putIfAbsent(msgId, () => {});
      final bufferMap = _fragmentBuffers[msgId]!;
      bufferMap[index] = chunkBytes;

      if (bufferMap.length == total) {
        final allBytes = <int>[];
        for (int i = 0; i < total; i++) {
          final part = bufferMap[i];
          if (part != null) allBytes.addAll(part);
        }
        _fragmentBuffers.remove(msgId);

        String decryptedText = '';
        String? discoveredSenderPubKey;

        if (mode == MessageMode.privateE2ee && myPubKey != null) {
          String? senderPubKey;
          for (final c in ContactVault.contacts) {
            if (ContactVault.matchesSender(c, senderHash)) {
              senderPubKey = c.publicKey;
              break;
            }
          }

          if (senderPubKey != null) {
            try {
              final decryptedBytes = CryptoEngine.decryptBytes(
                cipherBytes: Uint8List.fromList(allBytes),
                recipientPubKey: myPubKey,
                senderPubKey: senderPubKey,
              );
              decryptedText = utf8.decode(decryptedBytes, allowMalformed: true);
            } catch (_) {
              decryptedText = utf8.decode(allBytes, allowMalformed: true);
            }
          } else {
            decryptedText = utf8.decode(allBytes, allowMalformed: true);
          }
        } else {
          decryptedText = utf8.decode(allBytes, allowMalformed: true);
        }

        final packetId = decryptedText.startsWith('SOS|')
            ? 'PKT_SOS_${msgId}_$senderHash'
            : 'PKT_${msgId}_$senderHash';
        return RealBlePacket(
          packetId: packetId,
          mode: mode,
          phyMode: BlePhyMode.standard1M,
          lat: 0.0,
          lng: 0.0,
          altitude: 0.0,
          ttl: 3,
          senderHash: senderHash,
          recipientHash: recipientHash,
          rawPayload: decryptedText,
          decryptedPayload: decryptedText,
          rssi: rssi,
          receivedTime: DateTime.now(),
          deviceAddress: deviceAddress,
          senderPubKey: discoveredSenderPubKey,
        );
      }
      return null;
    }

    // 3. Format SOS / Full Packet (GPS coordinates)
    if (bytes.length < 14) return null;

    final isCompact = bytes.length >= 14 && view.getUint8(13) == bytes.length - 14;
    if (!isCompact && bytes.length < 24) return null;

    final modeIndex = formatByte.clamp(0, MessageMode.values.length - 1);
    final mode = MessageMode.values[modeIndex];

    final phyIndex = view.getUint8(3).clamp(0, BlePhyMode.values.length - 1);
    final phyMode = (primaryPhy == 3) ? BlePhyMode.leCodedS8 : BlePhyMode.values[phyIndex];

    double lat = 0, lng = 0, alt = 0;
    int ttl, packetHash, senderHash, recipientHash, payloadLen;

    if (isCompact) {
      ttl = view.getUint8(4);
      packetHash = view.getUint32(5, Endian.big);
      senderHash = view.getUint16(9, Endian.big);
      recipientHash = view.getUint16(11, Endian.big);
      payloadLen = view.getUint8(13);
    } else {
      lat = view.getFloat32(4, Endian.big);
      lng = view.getFloat32(8, Endian.big);
      alt = view.getInt16(12, Endian.big).toDouble();
      ttl = view.getUint8(14);
      packetHash = view.getUint32(15, Endian.big);
      senderHash = view.getUint16(19, Endian.big);
      recipientHash = view.getUint16(21, Endian.big);
      payloadLen = view.getUint8(23);
    }

    final myPubKey = ContactVault.myKeyPair['publicKey'];
    if (myPubKey != null && senderHash == (consistentHash(myPubKey) & 0xFFFF)) {
      return null;
    }

    final start = isCompact ? 14 : 24;
    final safePayloadLen = min(payloadLen, bytes.length - start);
    final rawPayload = utf8.decode(
      bytes.sublist(start, start + safePayloadLen),
      allowMalformed: true,
    );

    return RealBlePacket(
      packetId: 'PKT_${packetHash.toRadixString(16)}_$senderHash',
      mode: mode,
      phyMode: phyMode,
      lat: lat,
      lng: lng,
      altitude: alt,
      ttl: ttl,
      senderHash: senderHash,
      recipientHash: recipientHash,
      rawPayload: rawPayload,
      decryptedPayload: rawPayload,
      rssi: rssi,
      receivedTime: DateTime.now(),
      deviceAddress: deviceAddress,
    );
  }
}



