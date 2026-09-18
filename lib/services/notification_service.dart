import 'package:flutter/services.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  static const MethodChannel _channel = MethodChannel('com.example.test_1/foreground_service');

  Future<void> init() async {
    // Initialized in native
  }

  Future<void> showSosNotification(String title, String body) async {
    try {
      await _channel.invokeMethod('showNotification', {
        'title': title,
        'body': body
      });
    } catch (e) {
      print('Failed to show notification: $e');
    }
  }

  Future<void> startMuleService() async {
    try {
      await _channel.invokeMethod('startForegroundService');
    } catch (e) {
      print('Failed to start foreground service: $e');
    }
  }

  Future<void> stopMuleService() async {
    try {
      await _channel.invokeMethod('stopForegroundService');
    } catch (e) {
      print('Failed to stop foreground service: $e');
    }
  }

  Future<bool> isBatteryOptimizationIgnored() async {
    try {
      final res = await _channel.invokeMethod<bool>('isBatteryOptimizationIgnored');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> requestIgnoreBatteryOptimization() async {
    try {
      final res = await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimization');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
