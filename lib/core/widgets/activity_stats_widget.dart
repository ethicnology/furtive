import 'package:flutter/material.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/extensions.dart';

class ActivityStatsWidget extends StatelessWidget {
  final ActivityEntity activity;
  final Duration elapsedTime;

  const ActivityStatsWidget({
    super.key,
    required this.activity,
    required this.elapsedTime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(color: Colors.black),
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
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                elapsedTime.toHHMMSS(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: 145),
            child: PageView(
              children: [
                _buildStatsPage(
                  label: 'Active',
                  duration: activity.activeDuration.toHHMMSS(),
                  distance: activity.activeDistanceInKm.toStringAsFixed(1),
                  speed: activity.activeSpeedKmh.toStringAsFixed(1),
                  pace: activity.activePaceMinPerKm,
                  elevation: activity.activeElevation,
                ),
                _buildStatsPage(
                  label: 'Paused',
                  duration: activity.pausedDuration.toHHMMSS(),
                  distance: activity.pausedDistanceInKm.toStringAsFixed(1),
                  speed: activity.pausedSpeedKmh.toStringAsFixed(1),
                  pace: activity.pausedPaceMinPerKm,
                  elevation: null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildStatsPage({
  required String label,
  required String duration,
  required String distance,
  required String speed,
  required String pace,
  required ({double gain, double loss})? elevation,
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
            ),
            _StatItem(icon: Icons.timer, label: 'Pace', value: pace),
          ],
        ),
        SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _StatItem(icon: Icons.speed, label: 'Speed', value: '$speed km/h'),
            if (elevation != null)
              _StatItem(
                icon: Icons.terrain,
                label: 'Elevation',
                value:
                    '${elevation.gain.toStringAsFixed(0)}/${elevation.loss.toStringAsFixed(0)}m',
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

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            Text(
              value,
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ],
    );
  }
}
