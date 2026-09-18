import 'dart:async';
import 'dart:math';
import '../models/models.dart';
import 'contact_vault.dart';

/// Mesh Simulation Engine handling multi-hop store-and-forward mesh routing,
/// physical radio range checks, relay logs, and cellular gateway SMS dispatch.
class MeshEngine {
  static final MeshEngine instance = MeshEngine._internal();
  MeshEngine._internal() {
    _initNodes();
  }

  final List<MeshNode> _nodes = [];
  final List<SosPacket> _activePackets = [];
  final List<RelayLog> _logs = [];

  final _packetStreamController = StreamController<SosPacket>.broadcast();
  final _logStreamController = StreamController<RelayLog>.broadcast();

  Stream<SosPacket> get packetStream => _packetStreamController.stream;
  Stream<RelayLog> get logStream => _logStreamController.stream;

  List<MeshNode> get nodes => List.unmodifiable(_nodes);
  List<SosPacket> get activePackets => List.unmodifiable(_activePackets);
  List<RelayLog> get logs => List.unmodifiable(_logs);

  TransportEngine activeTransportEngine = TransportEngine.leCodedBle;
  BlePhyMode activePhyMode = BlePhyMode.leCodedS8;

  void _initNodes() {
    _nodes.clear();
    _nodes.addAll([
      MeshNode(
        id: 'person_a',
        name: 'Person A (You - Lost)',
        type: NodeType.personA,
        x: 50,
        y: 250,
        isHasCellular: false,
        publicKey: ContactVault.myKeyPair['publicKey']!,
      ),
      MeshNode(
        id: 'hiker_1',
        name: 'Hiker Alex (Mule)',
        type: NodeType.hiker,
        x: 110,
        y: 220,
        isHasCellular: false,
        publicKey: 'PUB_HIKER_1',
      ),
      MeshNode(
        id: 'drone_1',
        name: 'Rescue Drone Delta',
        type: NodeType.drone,
        x: 170,
        y: 190,
        isHasCellular: false,
        publicKey: 'PUB_DRONE_1',
      ),
      MeshNode(
        id: 'hiker_2',
        name: 'Ranger Sarah (Mule)',
        type: NodeType.hiker,
        x: 230,
        y: 160,
        isHasCellular: false,
        publicKey: 'PUB_RANGER_2',
      ),
      MeshNode(
        id: 'gateway_1',
        name: 'Trailhead Cell Tower',
        type: NodeType.gateway,
        x: 290,
        y: 130,
        isHasCellular: true,
        publicKey: 'PUB_GATEWAY_1',
      ),
      MeshNode(
        id: 'person_b',
        name: 'Person B (Home)',
        type: NodeType.personB,
        x: 350,
        y: 100,
        isHasCellular: true,
        publicKey: ContactVault.getById('person_b')?.publicKey ?? '',
      ),
    ]);
  }

  /// Calculates distance in meters between two nodes
  double distanceBetween(MeshNode a, MeshNode b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
  }

  /// Check if radio range permits packet handshake based on selected PHY/Transport mode
  bool isInRadioRange(MeshNode a, MeshNode b) {
    final range = (activeTransportEngine == TransportEngine.nearbyWifiP2p)
        ? 120.0 // Wi-Fi Direct High Speed Range (~120m)
        : activePhyMode.rangeMeters; // BLE Coded PHY Range
    return distanceBetween(a, b) <= max(range, 120.0); // Reliable range threshold
  }

  /// Dispatch an SOS packet from Person A into the mesh
  SosPacket dispatchSos({
    required String recipientId,
    required MessageMode mode,
    required String customNote,
    required double lat,
    required double lng,
  }) {
    final senderNode = _nodes.firstWhere((n) => n.id == 'person_a');

    final packet = SosPacket(
      packetId:
          'PKT_${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}',
      senderId: senderNode.id,
      senderName: senderNode.name,
      recipientId: recipientId,
      mode: mode,
      cleartextHeader:
          'EMERGENCY SOS | Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)} | Time: ${DateTime.now().hour}:${DateTime.now().minute}',
      encryptedPayload: customNote,
      lat: lat,
      lng: lng,
      altitude: 412.0,
      timestamp: DateTime.now(),
      hopHistory: [senderNode.id],
    );

    _activePackets.add(packet);
    _packetStreamController.add(packet);

    _addLog(
      from: senderNode.name,
      to: 'BLE Broadcast',
      event: 'DISPATCH_SOS',
      details: '${mode.label} broadcast started from forest interior.',
    );

    // Perform initial hop if a node is in range
    simulateStep();

    return packet;
  }

  /// Step simulation forward: advances EXACTLY ONE HOP per call
  void simulateStep() {
    if (_activePackets.isEmpty) return;

    for (final packet in List<SosPacket>.from(_activePackets.reversed)) {
      if (packet.isDeliveredToPersonB || packet.ttl <= 0) continue;

      final currentHolderId = packet.hopHistory.last;
      final currentHolder =
          _nodes.firstWhere((n) => n.id == currentHolderId);

      for (final nextNode in _nodes) {
        if (packet.hopHistory.contains(nextNode.id)) continue;

        if (isInRadioRange(currentHolder, nextNode)) {
          packet.hopHistory.add(nextNode.id);
          packet.ttl--;

          _addLog(
            from: currentHolder.name,
            to: nextNode.name,
            event: 'MESH_HOP',
            details:
                'Packet ${packet.packetId} relayed via BLE/Wi-Fi Aware. TTL: ${packet.ttl}',
          );

          if (nextNode.isHasCellular && !packet.isDeliveredToGateway) {
            packet.isDeliveredToGateway = true;
            _addLog(
              from: nextNode.name,
              to: 'Cellular Network',
              event: 'GATEWAY_UPLINK',
              details:
                  'Relayed to cellular network. Uploading packet to Cloud SOS Dispatch.',
            );

            _triggerDeliveryToPersonB(packet, nextNode);
          } else if (nextNode.id == packet.recipientId ||
              nextNode.type == NodeType.personB) {
            packet.isDeliveredToPersonB = true;
            _addLog(
              from: nextNode.name,
              to: 'Person B Device',
              event: 'DELIVERED_E2EE',
              details:
                  'Direct mesh delivery to Person B. Decrypting payload on device.',
            );
          }

          _packetStreamController.add(packet);
          return; // Advance EXACTLY ONE HOP per call!
        }
      }
    }
  }

  void _triggerDeliveryToPersonB(SosPacket packet, MeshNode gatewayNode) {
    final recipientContact = ContactVault.getById(packet.recipientId);

    if (recipientContact != null && !recipientContact.isAppInstalled) {
      packet.isSmsFallbackTriggered = true;
      packet.isDeliveredToPersonB = true;
      _addLog(
        from: gatewayNode.name,
        to: recipientContact.phoneNumber,
        event: 'SMS_FALLBACK',
        details:
            'Recipient has no app key. Converted packet to standard SMS & dispatched to ${recipientContact.phoneNumber}.',
      );
    } else {
      packet.isDeliveredToPersonB = true;
      _addLog(
        from: gatewayNode.name,
        to: 'Person B App',
        event: 'CELLULAR_PUSH',
        details:
            'App detected on recipient device. Delivered E2EE payload via Push Notification.',
      );
    }
  }

  void moveNode(String nodeId, double dx, double dy, {double? maxX, double? maxY}) {
    final node = _nodes.firstWhere((n) => n.id == nodeId);
    final limitX = maxX ?? 500.0;
    final limitY = maxY ?? 500.0;
    node.x = (node.x + dx).clamp(24.0, limitX - 24.0);
    node.y = (node.y + dy).clamp(24.0, limitY - 24.0);

    if (_activePackets.isNotEmpty) {
      _packetStreamController.add(_activePackets.last);
    } else {
      _addLog(
        from: node.name,
        to: 'Radar Canvas',
        event: 'NODE_MOVED',
        details: '${node.name} position updated on radar canvas.',
      );
    }
  }

  void clearSimulation() {
    _activePackets.clear();
    _logs.clear();
    _initNodes();
  }

  void _addLog({
    required String from,
    required String to,
    required String event,
    required String details,
  }) {
    final log = RelayLog(
      time: DateTime.now(),
      fromNode: from,
      toNode: to,
      event: event,
      details: details,
    );
    _logs.add(log);
    _logStreamController.add(log);
  }
}
