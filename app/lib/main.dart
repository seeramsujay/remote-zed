import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'services/agent_service.dart';
import 'services/git_service.dart';
import 'services/telemetry_service.dart';
import 'services/websocket_client.dart';
import 'state/agent_state.dart';
import 'state/git_state.dart';
import 'state/telemetry_state.dart';
import 'ui/screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final wsClient = WebSocketClient(
    host: AppConstants.defaultHost,
    port: AppConstants.defaultPort,
    token: '',
    useTls: false,
  );

  // Auto-connect on startup
  wsClient.connect();

  final agentService = AgentService(client: wsClient);
  final gitService = GitService(client: wsClient);
  final telemetryService = TelemetryService(client: wsClient);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AgentState(agentService: agentService),
        ),
        ChangeNotifierProvider(
          create: (_) => GitState(gitService: gitService),
        ),
        ChangeNotifierProvider(
          create: (_) => TelemetryState(telemetryService: telemetryService),
        ),
      ],
      child: ZedRemoteApp(client: wsClient),
    ),
  );
}

class ZedRemoteApp extends StatelessWidget {
  final WebSocketClient client;

  const ZedRemoteApp({super.key, required this.client});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: HomeScreen(client: client),
    );
  }
}
