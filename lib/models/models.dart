/// Message modes supported by the Flare mesh system
enum MessageMode {
  publicSos('Open Emergency Alert', 'Alerts all nearby searchers in range'),
  privateE2ee('Private Message Alert', 'Locked with a digital key for your trusted contacts'),
  hybridSos('Dual Alert', 'Alerts all searchers, but keeps your note private'),
  publicChat('Broadcast Chat', 'Open broadcast to all nearby devices');

  final String label;
  final String description;
  const MessageMode(this.label, this.description);
}

/// System Transport Engines for Dual Transport Mode
enum TransportEngine {
  leCodedBle('LE Coded PHY BLE (Long Range)', 'Uses BLE 5.0 LE Coded PHY for 400m+ Emergency SOS reach'),
  nearbyWifiP2p('Google Nearby Connections (High Speed)', 'Uses Wi-Fi Direct for fast photo, map, and file sharing');

  final String label;
  final String description;
  const TransportEngine(this.label, this.description);
}

/// Bluetooth Physical Layer Modes (Bluetooth 5.0 Adaptive PHY Switching)
enum BlePhyMode {
  speed2M('BLE 2M PHY (High Speed - 2 Mbps)', 40.0, 'Best for nearby file/photo transfers (~40m)', 2000, '2.0 Mbps', 1.0, 0.1),
  standard1M('Standard BLE 1M PHY (1 Mbps)', 130.0, 'Standard BLE - Balanced range/speed (~130m)', 1000, '1.0 Mbps', 0.5, 0.3),
  leCodedS2('LE Coded S=2 PHY (500 kbps)', 250.0, '2x Range (~250m) - Moderate foliage penetration', 500, '500 kbps', 0.25, 0.6),
  leCodedS8('LE Coded S=8 PHY (125 kbps)', 420.0, '4x Max Range (~420m) - Emergency SOS max penetration', 125, '125 kbps', 0.06, 1.0);

  final String label;
  final double rangeMeters;
  final String description;
  final int speedKbps;
  final String speedLabel;
  final double throughputScore;
  final double rangeScore;

  const BlePhyMode(
    this.label,
    this.rangeMeters,
    this.description,
    this.speedKbps,
    this.speedLabel,
    this.throughputScore,
    this.rangeScore,
  );

  /// Calculates actual on-air packet transmission duration in milliseconds
  double estimateAirTimeMs(int payloadSizeBytes) {
    final bits = (payloadSizeBytes + 14) * 8; // Including BLE preamble & header
    return (bits / (speedKbps * 1000)) * 1000;
  }
}

/// Simulated Node Types in the Mesh Network
enum NodeType {
  personA('Person A (Distress Sender)', 'Lost/Stuck Node'),
  hiker('Hiker / Mule', 'Passing Human Mule'),
  drone('Search Drone', 'Aerial Relay'),
  gateway('Cellular Gateway', 'Cell Tower / Satellite Node'),
  personB('Person B (Intended Recipient)', 'External Recipient');

  final String title;
  final String subtitle;
  const NodeType(this.title, this.subtitle);
}

/// A node in the mesh network
class MeshNode {
  final String id;
  final String name;
  final NodeType type;
  double x; // Position X in meters (0-500)
  double y; // Position Y in meters (0-500)
  bool isHasCellular;
  double batteryLevel; // 0.0 - 1.0
  String publicKey;

  MeshNode({
    required this.id,
    required this.name,
    required this.type,
    required this.x,
    required this.y,
    this.isHasCellular = false,
    this.batteryLevel = 0.95,
    required this.publicKey,
  });
}

/// Packet representing an SOS / Mesh message payload
class SosPacket {
  final String packetId;
  final String senderId;
  final String senderName;
  final String recipientId; // Can be 'BROADCAST' or specific Person B ID
  final MessageMode mode;
  final String cleartextHeader; // Public info (GPS, timestamp, SOS flag)
  final String encryptedPayload; // E2EE body
  final double lat;
  final double lng;
  final double altitude;
  final DateTime timestamp;
  int ttl; // Time to live (max hops)
  List<String> hopHistory; // List of node IDs that relayed this packet
  bool isDeliveredToGateway;
  bool isDeliveredToPersonB;
  bool isSmsFallbackTriggered;

  SosPacket({
    required this.packetId,
    required this.senderId,
    required this.senderName,
    required this.recipientId,
    required this.mode,
    required this.cleartextHeader,
    required this.encryptedPayload,
    required this.lat,
    required this.lng,
    required this.altitude,
    required this.timestamp,
    this.ttl = 5,
    List<String>? hopHistory,
    this.isDeliveredToGateway = false,
    this.isDeliveredToPersonB = false,
    this.isSmsFallbackTriggered = false,
  }) : hopHistory = hopHistory ?? [];

  Map<String, dynamic> toJson() => {
        'packetId': packetId,
        'senderId': senderId,
        'senderName': senderName,
        'recipientId': recipientId,
        'mode': mode.name,
        'cleartextHeader': cleartextHeader,
        'encryptedPayload': encryptedPayload,
        'lat': lat,
        'lng': lng,
        'altitude': altitude,
        'timestamp': timestamp.toIso8601String(),
        'ttl': ttl,
        'hopHistory': hopHistory,
        'isDeliveredToGateway': isDeliveredToGateway,
        'isDeliveredToPersonB': isDeliveredToPersonB,
        'isSmsFallbackTriggered': isSmsFallbackTriggered,
      };

  factory SosPacket.fromJson(Map<String, dynamic> json) => SosPacket(
        packetId: json['packetId'],
        senderId: json['senderId'],
        senderName: json['senderName'],
        recipientId: json['recipientId'],
        mode: MessageMode.values.firstWhere((e) => e.name == json['mode']),
        cleartextHeader: json['cleartextHeader'],
        encryptedPayload: json['encryptedPayload'],
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        altitude: (json['altitude'] as num).toDouble(),
        timestamp: DateTime.parse(json['timestamp']),
        ttl: json['ttl'],
        hopHistory: List<String>.from(json['hopHistory'] ?? []),
        isDeliveredToGateway: json['isDeliveredToGateway'] ?? false,
        isDeliveredToPersonB: json['isDeliveredToPersonB'] ?? false,
        isSmsFallbackTriggered: json['isSmsFallbackTriggered'] ?? false,
      );
}

/// Contact Key model saved in Person A's local vault
class ContactKey {
  final String id;
  final String name;
  final String phoneNumber;
  final String publicKey;
  final bool isAppInstalled;
  final DateTime lastSynced;

  ContactKey({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.publicKey,
    required this.isAppInstalled,
    required this.lastSynced,
  });
}

/// Event log for mesh hop trace visualization
class RelayLog {
  final DateTime time;
  final String fromNode;
  final String toNode;
  final String event;
  final String details;

  RelayLog({
    required this.time,
    required this.fromNode,
    required this.toNode,
    required this.event,
    required this.details,
  });
}
