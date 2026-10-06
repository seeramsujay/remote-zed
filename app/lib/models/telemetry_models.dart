/// Data models for system telemetry and power actions.

class TelemetryResult {
  final String hostName;
  final String os;
  final double cpuUsagePercent;
  final int memoryUsedBytes;
  final int memoryTotalBytes;
  final double? batteryPercent;
  final bool? isCharging;
  final int uptimeSeconds;

  TelemetryResult({
    required this.hostName,
    required this.os,
    required this.cpuUsagePercent,
    required this.memoryUsedBytes,
    required this.memoryTotalBytes,
    this.batteryPercent,
    this.isCharging,
    required this.uptimeSeconds,
  });

  factory TelemetryResult.fromJson(Map<String, dynamic> json) {
    return TelemetryResult(
      hostName: json['host_name'] as String? ?? json['hostName'] as String? ?? 'host',
      os: json['os'] as String? ?? 'OS',
      cpuUsagePercent: (json['cpu_usage_percent'] as num?)?.toDouble() ??
          (json['cpuUsagePercent'] as num?)?.toDouble() ??
          0.0,
      memoryUsedBytes: json['memory_used_bytes'] as int? ?? json['memoryUsedBytes'] as int? ?? 0,
      memoryTotalBytes: json['memory_total_bytes'] as int? ?? json['memoryTotalBytes'] as int? ?? 0,
      batteryPercent: (json['battery_percent'] as num?)?.toDouble() ??
          (json['batteryPercent'] as num?)?.toDouble(),
      isCharging: json['is_charging'] as bool? ?? json['isCharging'] as bool?,
      uptimeSeconds: json['uptime_seconds'] as int? ?? json['uptimeSeconds'] as int? ?? 0,
    );
  }

  double get memoryUsagePercent {
    if (memoryTotalBytes == 0) return 0.0;
    return (memoryUsedBytes / memoryTotalBytes) * 100.0;
  }
}
