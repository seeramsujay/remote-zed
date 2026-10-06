/// Application constants and configuration defaults.
library;

class AppConstants {
  static const String appName = 'Zed Remote';
  static const String appVersion = '0.1.0';

  static const String defaultHost = '100.64.0.1';
  static const int defaultPort = 8443;
  static const String defaultSessionId = 'default';

  static const int reconnectDelayMs = 3000;
  static const int telemetryPollIntervalSeconds = 5;
}
