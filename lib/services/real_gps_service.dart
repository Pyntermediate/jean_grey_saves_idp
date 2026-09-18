import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class RealGpsService {
  static final RealGpsService instance = RealGpsService._internal();
  RealGpsService._internal();

  Position? _lastKnownPosition;
  Position? get lastKnownPosition => _lastKnownPosition;

  bool _hasLocationPermission = false;
  bool get hasLocationPermission => _hasLocationPermission;

  /// Request permissions and get current offline GPS coordinates
  Future<Position?> getCurrentPosition() async {
    try {
      // Step 1: Request permission via permission_handler (works across Android 8 through 14+)
      var status = await Permission.locationWhenInUse.status;
      if (!status.isGranted) {
        status = await Permission.locationWhenInUse.request();
      }
      if (!status.isGranted) {
        final status2 = await Permission.location.request();
        _hasLocationPermission = status2.isGranted;
      } else {
        _hasLocationPermission = true;
      }

      if (!_hasLocationPermission) {
        return _lastKnownPosition;
      }

      final isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isLocationServiceEnabled) {
        return _lastKnownPosition;
      }

      // Strategy 1: Instant cached position — returns immediately without blocking
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          _lastKnownPosition = lastKnown;
        }
      } catch (_) {}

      // Strategy 2: Direct Hardware GPS via native LocationManager (forceLocationManager: true)
      // Works reliably on non-GMS, offline, and Android 8/9/10/12/14 devices
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.high,
            forceLocationManager: true,
            timeLimit: const Duration(seconds: 8),
          ),
        );
        _lastKnownPosition = position;
        return position;
      } catch (_) {}

      // Strategy 3: Fused Location Provider fallback (for GMS devices indoors)
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.low,
            forceLocationManager: false,
            timeLimit: const Duration(seconds: 5),
          ),
        );
        _lastKnownPosition = position;
        return position;
      } catch (_) {}

      // Strategy 4: Return cached position if fresh satellite lock is still acquiring
      return _lastKnownPosition;
    } catch (_) {
      return _lastKnownPosition;
    }
  }

  /// Calculates Haversine distance in meters between two GPS coordinates (100% offline)
  static double calculateDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0; // Earth radius in meters
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  /// Calculates bearing angle in degrees (0 - 360) from Point A to Point B
  static double calculateBearingDegrees(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final lat1Rad = _degToRad(lat1);
    final lat2Rad = _degToRad(lat2);
    final dLonRad = _degToRad(lon2 - lon1);

    final y = sin(dLonRad) * cos(lat2Rad);
    final x = cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(dLonRad);

    final radians = atan2(y, x);
    return (_radToDeg(radians) + 360) % 360;
  }

  /// Formats bearing angle into cardinal direction (e.g., "N", "NE", "E", "SE", "S", "SW", "W", "NW")
  static String getCardinalDirection(double bearingDegrees) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'N'];
    final index = ((bearingDegrees + 22.5) / 45).floor() % 8;
    return directions[index];
  }

  static double _degToRad(double deg) => deg * (pi / 180.0);
  static double _radToDeg(double rad) => rad * (180.0 / pi);
}
