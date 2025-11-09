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
                  distance: activity.activeDistanceInKm.toStringAsFixed(2),
                  speed: activity.activeSpeedKmh.toStringAsFixed(1),
                  pace: activity.activePaceMinPerKm,
                  elevation: activity.activeElevation,
                ),
                _buildStatsPage(
                  label: 'Paused',
                  duration: activity.pausedDuration.toHHMMSS(),
                  distance: activity.pausedDistanceInKm.toStringAsFixed(2),
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
            Tooltip(
              message: 'Distance',
              child: Row(
                children: [
                  Icon(Icons.straighten, size: 20),
                  SizedBox(width: 8),
                  Text(
                    distance,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            Tooltip(
              message: 'Pace: Minutes per kilometer',
              child: Row(
                children: [
                  Icon(Icons.timer, size: 20),
                  SizedBox(width: 8),
                  Text(
                    pace,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: 'Speed: Kilometers per hour',
              child: Row(
                children: [
                  Icon(Icons.speed, size: 20),
                  SizedBox(width: 8),
                  Text(
                    speed,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            if (elevation != null)
              Tooltip(
                message: 'Elevation gain / Elevation loss',
                child: Row(
                  children: [
                    Icon(Icons.terrain, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '+${elevation.gain.toStringAsFixed(0)}m / ${elevation.loss.toStringAsFixed(0)}m',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
