import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/telemetry_models.dart';
import '../services/telemetry_service.dart';

/// State management for host system diagnostics, CPU, RAM, battery, and power controls.
class TelemetryState extends ChangeNotifier {
  final TelemetryService telemetryService;

  TelemetryResult? _telemetry;
  Timer? _pollTimer;
  bool _isActionInProgress = false;

  TelemetryState({required this.telemetryService}) {
    startPolling();
  }

  TelemetryResult? get telemetry => _telemetry;
  bool get isActionInProgress => _isActionInProgress;

  void startPolling() {
    _pollTimer?.cancel();
    poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => poll());
  }

  Future<void> poll() async {
    try {
      _telemetry = await telemetryService.getTelemetry();
      notifyListeners();
    } catch (_) {
      // Silently ignore telemetry poll errors during network drops
    }
  }

  Future<void> triggerPowerAction(String action) async {
    _isActionInProgress = true;
    notifyListeners();
    try {
      await telemetryService.sendPowerAction(action);
    } catch (e) {
      debugPrint('Power action failed: $e');
    } finally {
      _isActionInProgress = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
