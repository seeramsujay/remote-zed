import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../state/telemetry_state.dart';

/// Compact telemetry bar rendering host CPU, RAM, battery metrics, and power triggers.
class TelemetryBar extends StatelessWidget {
  const TelemetryBar({super.key});

  @override
  Widget build(BuildContext context) {
    final telemetryState = context.watch<TelemetryState>();
    final data = telemetryState.telemetry;

    if (data == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: AppTheme.surface,
        child: const Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.textSecondary),
            ),
            SizedBox(width: 8),
            Text(
              'Connecting to host telemetry...',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    final cpuPercent = data.cpuUsagePercent.clamp(0.0, 100.0);
    final memPercent = data.memoryUsagePercent.clamp(0.0, 100.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          // Host & OS
          Icon(Icons.laptop_chromebook, size: 16, color: AppTheme.primaryAccent),
          const SizedBox(width: 6),
          Text(
            data.hostName,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const Spacer(),

          // CPU Usage
          _buildMetricBadge(
            icon: Icons.memory,
            label: '${cpuPercent.toStringAsFixed(0)}%',
            color: cpuPercent > 80 ? AppTheme.danger : AppTheme.primaryAccent,
          ),
          const SizedBox(width: 12),

          // RAM Usage
          _buildMetricBadge(
            icon: Icons.storage,
            label: '${memPercent.toStringAsFixed(0)}%',
            color: memPercent > 85 ? AppTheme.warning : AppTheme.textSecondary,
          ),
          const SizedBox(width: 12),

          // Battery if present
          if (data.batteryPercent != null) ...[
            _buildMetricBadge(
              icon: data.isCharging == true ? Icons.battery_charging_full : Icons.battery_std,
              label: '${data.batteryPercent!.toStringAsFixed(0)}%',
              color: (data.batteryPercent! < 20 && data.isCharging != true)
                  ? AppTheme.danger
                  : AppTheme.success,
            ),
            const SizedBox(width: 12),
          ],

          // Power Control Popup Menu
          PopupMenuButton<String>(
            tooltip: 'Host Power Actions',
            icon: const Icon(Icons.power_settings_new, size: 18, color: AppTheme.textSecondary),
            color: AppTheme.surface,
            onSelected: (action) {
              telemetryState.triggerPowerAction(action);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'sleep',
                child: Row(
                  children: [
                    Icon(Icons.bedtime, size: 16, color: AppTheme.primaryAccent),
                    SizedBox(width: 8),
                    Text('Sleep Host'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'lock',
                child: Row(
                  children: [
                    Icon(Icons.lock, size: 16, color: AppTheme.warning),
                    SizedBox(width: 8),
                    Text('Lock Host Session'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'reboot',
                child: Row(
                  children: [
                    Icon(Icons.restart_alt, size: 16, color: AppTheme.warning),
                    SizedBox(width: 8),
                    Text('Reboot Host'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'shutdown',
                child: Row(
                  children: [
                    Icon(Icons.power_off, size: 16, color: AppTheme.danger),
                    SizedBox(width: 8),
                    Text('Shut Down Host'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }
}
