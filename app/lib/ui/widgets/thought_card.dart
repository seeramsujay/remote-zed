import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/acp_models.dart';

/// Collapsible card displaying the agent's step-by-step reasoning thought stream.
class ThoughtCard extends StatefulWidget {
  final List<ThoughtChunk> thoughts;

  const ThoughtCard({super.key, required this.thoughts});

  @override
  State<ThoughtCard> createState() => _ThoughtCardState();
}

class _ThoughtCardState extends State<ThoughtCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.thoughts.isEmpty) return const SizedBox.shrink();

    final count = widget.thoughts.length;
    final summaryText = count == 1 ? '1 thought chunk' : '$count thought chunks';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      decoration: BoxDecoration(
        color: AppTheme.thoughtBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.thoughtBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Row(
                children: [
                  const Icon(
                    Icons.psychology_outlined,
                    size: 18,
                    color: AppTheme.primaryAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Agent Reasoning ($summaryText)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.thoughts.map((t) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      t.text,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
