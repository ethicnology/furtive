import 'package:flutter/material.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/l10n/app_localizations.dart';

enum _Metric { pace, speed }

/// Indices of the fastest/slowest full (non-partial) splits for a given
/// metric. "Faster" means a SMALLER pace (less time per km) but a LARGER
/// speed (more distance per hour) — the comparison direction must flip
/// with [fasterIsSmaller], or the fastest/slowest labels get swapped when
/// the metric switches. Exposed at library-private top level (rather than
/// nested in the widget's build method) so it's directly unit-testable.
({int? fastestIdx, int? slowestIdx}) fastestAndSlowestSplitIndices(
  List<KmSplit> fullSplits,
  double Function(KmSplit) value, {
  required bool fasterIsSmaller,
}) {
  int? fastestIdx;
  int? slowestIdx;
  double bestVal = fasterIsSmaller ? double.infinity : -double.infinity;
  double worstVal = fasterIsSmaller ? -double.infinity : double.infinity;
  for (final s in fullSplits) {
    final v = value(s);
    // KmSplit.paceMinPerKm/speedKmh both sentinel to exactly 0 for a
    // degenerate split (zero distance or zero duration — only reachable via
    // a pathological GPX import with duplicate timestamps, never from a
    // live recording). 0 is smaller than any real pace, so without this
    // guard a degenerate split — rendered "--" by the caller — sorts as the
    // fastest km instead of being excluded from the comparison entirely.
    if (v == 0) continue;
    final isBetter = fasterIsSmaller ? v < bestVal : v > bestVal;
    final isWorse = fasterIsSmaller ? v > worstVal : v < worstVal;
    if (isBetter) {
      bestVal = v;
      fastestIdx = s.index;
    }
    if (isWorse) {
      worstVal = v;
      slowestIdx = s.index;
    }
  }
  return (fastestIdx: fastestIdx, slowestIdx: slowestIdx);
}

/// Strava-style per-kilometre splits: one horizontal bar per km in a
/// vertical scroll. Bar length scales with the chosen metric. The
/// fastest km is rendered in primary/teal, the slowest in destructive
/// red, the rest in tertiary blueGrey. Partial trailing km is shown
/// with reduced opacity and excluded from fastest/slowest comparison.
class KmSplitsChart extends StatefulWidget {
  final ActivityEntity activity;
  const KmSplitsChart({super.key, required this.activity});

  @override
  State<KmSplitsChart> createState() => _KmSplitsChartState();
}

class _KmSplitsChartState extends State<KmSplitsChart> {
  _Metric _metric = _Metric.pace;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final splits = widget.activity.kmSplits;
    if (splits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          l10n.splitsNotEnoughData,
          style: TextStyle(color: AppColors.tertiary.foreground),
        ),
      );
    }

    // Partial trailing km is excluded from the fastest/slowest comparison.
    // (fastestAndSlowestSplitIndices additionally excludes any degenerate
    // zero-value split on its own — see its doc comment.)
    final fullSplits = splits.where((s) => !s.isPartial).toList();
    final ranked = fastestAndSlowestSplitIndices(
      fullSplits,
      _value,
      fasterIsSmaller: _metric == _Metric.pace,
    );
    final fastestIdx = ranked.fastestIdx;
    final slowestIdx = ranked.slowestIdx;

    // Filter out non-finite metric values before reducing — a single NaN
    // would poison the rolling max (`NaN > x` is false in both directions),
    // then `NaN / maxValue` would feed NaN into FractionallySizedBox, which
    // throws on non-finite widthFactor.
    final finiteValues = splits.map(_value).where((v) => v.isFinite).toList();
    final rawMax = finiteValues.isEmpty
        ? 0.0
        : finiteValues.reduce((a, b) => a > b ? a : b);
    final maxValue = rawMax > 0 ? rawMax : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.splitsTitle,
                style: TextStyle(
                  color: AppColors.tertiary.foreground,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SegmentedButton<_Metric>(
                segments: [
                  ButtonSegment(
                    value: _Metric.pace,
                    label: Text(l10n.metricPace),
                  ),
                  ButtonSegment(
                    value: _Metric.speed,
                    label: Text(l10n.metricSpeed),
                  ),
                ],
                selected: {_metric},
                onSelectionChanged: (s) => setState(() => _metric = s.first),
                showSelectedIcon: false,
              ),
            ],
          ),
        ),
        for (final s in splits)
          _SplitRow(
            split: s,
            label: _format(s),
            barFraction: _safeFraction(_value(s), maxValue),
            color: _barColor(s, fastestIdx: fastestIdx, slowestIdx: slowestIdx),
            isFastest: !s.isPartial && s.index == fastestIdx,
            isSlowest: !s.isPartial && s.index == slowestIdx,
          ),
      ],
    );
  }

  double _value(KmSplit s) =>
      _metric == _Metric.pace ? s.paceMinPerKm : s.speedKmh;

  /// Last-line defence: FractionallySizedBox throws on a non-finite
  /// widthFactor. _value() can in theory be NaN if a future change drops
  /// the guards in KmSplit, so collapse to 0 here.
  double _safeFraction(double value, num max) {
    final f = value / max;
    return f.isFinite ? f.clamp(0.0, 1.0).toDouble() : 0.0;
  }

  String _format(KmSplit s) {
    if (_metric == _Metric.pace) {
      if (s.paceMinPerKm == 0) return '--';
      return '${formatPace(s.paceMinPerKm)} /km';
    }
    if (s.speedKmh == 0) return '--';
    return '${s.speedKmh.toStringAsFixed(1)} km/h';
  }

  Color _barColor(KmSplit s, {int? fastestIdx, int? slowestIdx}) {
    if (s.isPartial) return AppColors.tertiary.background.withAlpha(120);
    if (fastestIdx != null && s.index == fastestIdx) {
      return AppColors.primary.background;
    }
    if (slowestIdx != null && s.index == slowestIdx) {
      return AppColors.destructive.background;
    }
    return AppColors.tertiary.background;
  }
}

class _SplitRow extends StatelessWidget {
  final KmSplit split;
  final String label;
  final double barFraction;
  final Color color;
  final bool isFastest;
  final bool isSlowest;

  const _SplitRow({
    required this.split,
    required this.label,
    required this.barFraction,
    required this.color,
    required this.isFastest,
    required this.isSlowest,
  });

  @override
  Widget build(BuildContext context) {
    final indexLabel = split.isPartial
        ? (split.distanceMeters / 1000).toStringAsFixed(2)
        : '${split.index}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              indexLabel,
              style: TextStyle(
                color: AppColors.tertiary.foreground,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppColors.tertiary.background.withAlpha(60),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: barFraction.clamp(0.0, 1.0),
                  child: Container(
                    height: 22,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: TextStyle(
                // kDestructive (not kDangerText) is tuned for white text ON
                // a red fill; here the red itself IS the text colour on a
                // dark background, which needs the brighter kDangerText —
                // see theme.dart.
                color: isFastest
                    ? AppColors.primary.background
                    : isSlowest
                    ? kDangerText
                    : AppColors.tertiary.foreground,
                fontSize: 13,
                fontWeight: isFastest || isSlowest
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
