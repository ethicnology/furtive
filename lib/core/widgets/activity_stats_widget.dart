import 'package:flutter/material.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/extensions.dart';
import 'package:furtive/core/theme.dart';

class ActivityStatsWidget extends StatelessWidget {
  final ActivityEntity activity;
  final Duration elapsedTime;
  // When true (live recording overlay on the map), paint a black backdrop
  // so the stats stand out over the map tiles. When false (inside a themed
  // bottom sheet), inherit the parent surface so we don't render a black
  // rectangle inside the blueGrey sheet.
  final bool opaqueBackground;

  const ActivityStatsWidget({
    super.key,
    required this.activity,
    required this.elapsedTime,
    this.opaqueBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.tertiary.foreground;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Flexible(
                child: Text(
                  'Recording Activity',
                  style: TextStyle(
                    color: fg,
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                elapsedTime.toHHMMSS(),
                style: TextStyle(
                  color: fg,
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
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
                  duration: activity.activeDuration.toHHMMSS(),
                  distance: activity.activeDistanceInKm.fmt2,
                  speed: activity.activeSpeedKmh.fmt2,
                  pace: activity.activePaceMinPerKm,
                  elevationGain: activity.activeElevationGain,
                  foreground: fg,
                ),
                _buildStatsPage(
                  duration: activity.pausedDuration.toHHMMSS(),
                  distance: activity.pausedDistanceInKm.fmt2,
                  speed: activity.pausedSpeedKmh.fmt2,
                  pace: activity.pausedPaceMinPerKm,
                  elevationGain: null,
                  foreground: fg,
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
  required String duration,
  required String distance,
  required String speed,
  required String pace,
  required double? elevationGain,
  required Color foreground,
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
            _StatItem(
              icon: Icons.straighten,
              label: 'Distance',
              value: '$distance km',
              foreground: foreground,
            ),
            _StatItem(
              icon: Icons.timer,
              label: 'Pace',
              value: pace,
              foreground: foreground,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _StatItem(
              icon: Icons.speed,
              label: 'Speed',
              value: '$speed km/h',
              foreground: foreground,
            ),
            if (elevationGain != null)
              _StatItem(
                icon: Icons.terrain,
                label: 'Elevation',
                value: '${elevationGain.round()} m',
                foreground: foreground,
              ),
          ],
        ),
      ],
    ),
  );
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color foreground;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: foreground),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: foreground,
                fontSize: 25,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
