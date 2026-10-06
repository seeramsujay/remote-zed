import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zed_remote_app/models/acp_models.dart';
import 'package:zed_remote_app/ui/widgets/thought_card.dart';
import 'package:zed_remote_app/ui/widgets/permission_dialog.dart';

void main() {
  testWidgets('ThoughtCard expands and displays thought chunks on tap', (WidgetTester tester) async {
    final thoughts = [
      ThoughtChunk(text: 'Analyzing AST changes', timestamp: DateTime.now()),
      ThoughtChunk(text: 'Formatting output', timestamp: DateTime.now()),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThoughtCard(thoughts: thoughts),
        ),
      ),
    );

    expect(find.text('Agent Reasoning (2 thought chunks)'), findsOneWidget);
    expect(find.text('Analyzing AST changes'), findsNothing);

    // Tap to expand
    await tester.tap(find.text('Agent Reasoning (2 thought chunks)'));
    await tester.pumpAndSettle();

    expect(find.text('Analyzing AST changes'), findsOneWidget);
    expect(find.text('Formatting output'), findsOneWidget);
  });

  testWidgets('PermissionDialog triggers onApprove callback when tapped', (WidgetTester tester) async {
    bool approved = false;
    final request = PermissionRequest(
      requestId: 99,
      sessionId: 'sess_1',
      toolCallId: 'tc_1',
      toolName: 'terminal/create',
      parameters: {'command': 'git push origin main'},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PermissionDialog(
            request: request,
            onApprove: () => approved = true,
            onReject: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Tool Authorization Required'), findsOneWidget);
    expect(find.text('terminal/create'), findsOneWidget);
    expect(find.text('git push origin main'), findsOneWidget);

    await tester.tap(find.text('Approve'));
    await tester.pump();

    expect(approved, isTrue);
  });
}
