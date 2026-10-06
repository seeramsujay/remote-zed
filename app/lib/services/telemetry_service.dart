import '../models/telemetry_models.dart';
import 'websocket_client.dart';

/// Service querying laptop hardware metrics and dispatching power controls.
class TelemetryService {
  final WebSocketClient client;

  TelemetryService({required this.client});

  /// Polls the host machine for telemetry data.
  Future<TelemetryResult> getTelemetry() async {
    final res = await client.sendRequest('system/telemetry');
    return TelemetryResult.fromJson(res as Map<String, dynamic>);
  }

  /// Sends a system power state action (e.g. sleep, lock, shutdown, reboot).
  Future<String> sendPowerAction(String action) async {
    final res = await client.sendRequest('system/power', {
      'action': action,
    });
    if (res is Map<String, dynamic>) {
      return res['message'] as String? ?? 'Action acknowledged';
    }
    return res.toString();
  }
}
