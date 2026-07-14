import 'package:flutter/material.dart';
import 'package:furtive/core/theme.dart';

/// Shared "icon + label + value" stat display, replacing the ad hoc
/// solid-mint pill chips and one-off `_StatItem` widgets that used to be
/// duplicated (with slightly different styling each time) across the
/// activities list, the recording overlay and the activity detail sheet.
///
/// Two densities:
/// - [StatBlock] — icon, small caps label, large value. Used where a stat
///   is the primary thing on screen (recording overlay, detail sheet).
/// - [StatBlock.compact] — single-line "icon value" for tight spaces (the
///   activities list row), still readable without competing with the list
///   item's title.
///
/// [emphasize] renders the value in the mint accent instead of white — use
/// sparingly (one emphasized stat per group) so the accent still reads as
/// "the headline number" rather than becoming another wash of colour.
class StatBlock extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool emphasize;
  final bool compact;

  const StatBlock({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.emphasize = false,
    this.compact = false,
  });

  const StatBlock.compact({
    super.key,
    required this.icon,
    required this.value,
    this.emphasize = false,
  }) : label = '',
       compact = true;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final valueColor = emphasize ? kMint : Colors.white;

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: emphasize ? kMint : kTextMuted),
          const SizedBox(width: 4),
          Text(
            value,
            style: textTheme.bodySmall?.copyWith(
              color: valueColor,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              fontFeatures: kTabularFigures,
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: kTextMuted),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: textTheme.labelSmall),
            Text(
              value,
              style: textTheme.titleLarge?.copyWith(
                color: valueColor,
                fontFeatures: kTabularFigures,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
