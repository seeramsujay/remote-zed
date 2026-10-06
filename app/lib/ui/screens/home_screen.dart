import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/websocket_client.dart';
import '../../state/agent_state.dart';
import '../widgets/agent_panel.dart';
import '../widgets/permission_dialog.dart';
import '../widgets/repository_panel.dart';
import '../widgets/telemetry_bar.dart';
import 'settings_sheet.dart';

/// Main container screen supporting adaptive dual-panel and mobile tabbed layouts.
class HomeScreen extends StatefulWidget {
  final WebSocketClient client;

  const HomeScreen({super.key, required this.client});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTabIndex = 0;
  bool _isPermissionDialogOpen = false;

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SettingsSheet(client: widget.client),
    );
  }

  void _checkPermissionDialog(AgentState agentState) {
    if (agentState.pendingPermission != null && !_isPermissionDialogOpen) {
      _isPermissionDialogOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => PermissionDialog(
            request: agentState.pendingPermission!,
            onApprove: () {
              agentState.approvePermission();
              Navigator.of(dialogCtx).pop();
              _isPermissionDialogOpen = false;
            },
            onReject: (reason) {
              agentState.rejectPermission(reason);
              Navigator.of(dialogCtx).pop();
              _isPermissionDialogOpen = false;
            },
          ),
        ).then((_) {
          _isPermissionDialogOpen = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final agentState = context.watch<AgentState>();
    _checkPermissionDialog(agentState);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.bolt, color: AppTheme.primary, size: 20),
            const SizedBox(width: 8),
            const Text('Zed Remote'),
            const SizedBox(width: 12),
            _buildConnectionBadge(widget.client.status),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Connection Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Telemetry Bar
            const TelemetryBar(),

            // Layout switcher based on viewport width
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWideScreen = constraints.maxWidth >= 800;

                  if (isWideScreen) {
                    // Dual Panel Layout for Tablets & Foldables
                    return const Row(
                      children: [
                        Expanded(flex: 3, child: AgentPanel()),
                        VerticalDivider(width: 1, color: AppTheme.border),
                        Expanded(flex: 2, child: RepositoryPanel()),
                      ],
                    );
                  } else {
                    // Mobile Single Panel Layout
                    return IndexedStack(
                      index: _currentTabIndex,
                      children: const [
                        AgentPanel(),
                        RepositoryPanel(),
                      ],
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: MediaQuery.of(context).size.width >= 800
          ? null
          : BottomNavigationBar(
              currentIndex: _currentTabIndex,
              backgroundColor: AppTheme.surface,
              selectedItemColor: AppTheme.primaryAccent,
              unselectedItemColor: AppTheme.textSecondary,
              onTap: (index) => setState(() => _currentTabIndex = index),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.chat_bubble_outline),
                  activeIcon: Icon(Icons.chat_bubble),
                  label: 'Agent Chat',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.commit_outlined),
                  activeIcon: Icon(Icons.commit),
                  label: 'Repository',
                ),
              ],
            ),
    );
  }

  Widget _buildConnectionBadge(ConnectionStatus status) {
    Color color;
    String label;

    switch (status) {
      case ConnectionStatus.connected:
        color = AppTheme.success;
        label = 'Connected';
        break;
      case ConnectionStatus.connecting:
        color = AppTheme.warning;
        label = 'Connecting';
        break;
      case ConnectionStatus.disconnected:
        color = AppTheme.textSecondary;
        label = 'Disconnected';
        break;
      case ConnectionStatus.error:
        color = AppTheme.danger;
        label = 'Error';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
