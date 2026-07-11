import 'package:flutter/material.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/extensions.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/widgets/stat_block.dart';
import 'package:furtive/l10n/app_localizations.dart';

class ActivityStatsWidget extends StatelessWidget {
  final ActivityEntity activity;
  final Duration elapsedTime;
  // When true (live recording overlay on the map), paint a black backdrop
  // so the stats stand out over the map tiles. When false (inside a themed
  // bottom sheet), inherit the parent surface so we don't render a black
  // rectangle inside the sheet.
  final bool opaqueBackground;

  const ActivityStatsWidget({
    super.key,
    required this.activity,
    required this.elapsedTime,
    this.opaqueBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  l10n.statsRecordingTitle,
                  style: textTheme.labelSmall,
                ),
              ),
              // The one number that should draw the eye first while
              // recording — displayMedium + mint, everything else below is
              // white/muted.
              Text(
                elapsedTime.toHHMMSS(),
                style: textTheme.displayMedium?.copyWith(
                  fontSize: 28,
                  color: kMint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 145),
            child: PageView(
              children: [
                _buildStatsPage(
                  l10n: l10n,
                  duration: activity.activeDuration.toHHMMSS(),
                  distance: activity.activeDistanceInKm.fmt2,
                  speed: activity.activeSpeedKmh.fmt2,
                  pace: activity.activePaceMinPerKm,
                  elevationGain: activity.activeElevationGain,
                ),
                _buildStatsPage(
                  l10n: l10n,
                  duration: activity.pausedDuration.toHHMMSS(),
                  distance: activity.pausedDistanceInKm.fmt2,
                  speed: activity.pausedSpeedKmh.fmt2,
                  pace: activity.pausedPaceMinPerKm,
                  elevationGain: null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!opaqueBackground) return content;
    return ColoredBox(color: Colors.black, child: content);
  }
}

Widget _buildStatsPage({
  required AppLocalizations l10n,
  required String duration,
  required String distance,
  required String speed,
  required String pace,
  required double? elevationGain,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Distance is the primary stat while recording — emphasized in
            // mint, the rest stay white/muted so it doesn't get lost among
            // four equally-loud numbers.
            StatBlock(
              icon: Icons.straighten_rounded,
              label: l10n.statDistance,
              value: '$distance km',
              emphasize: true,
            ),
            StatBlock(icon: Icons.timer_outlined, label: l10n.statPace, value: pace),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            StatBlock(
              icon: Icons.speed_rounded,
              label: l10n.statSpeed,
              value: '$speed km/h',
            ),
            if (elevationGain != null)
              StatBlock(
                icon: Icons.terrain_rounded,
                label: l10n.statElevation,
                value: '${elevationGain.round()} m',
              ),
          ],
        ),
      ],
    ),
  );
}
