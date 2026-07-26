import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/theme.dart';

/// Numbered chip markers placed at each kilometre milestone of an activity.
/// Builds an empty layer when the activity has covered less than one km so
/// it can be included unconditionally in the FlutterMap children list.
class KmMilestonesLayer extends StatelessWidget {
  final ActivityEntity activity;
  const KmMilestonesLayer({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    final milestones = activity.kmMilestones;
    if (milestones.isEmpty) return const MarkerLayer(markers: []);
    return MarkerLayer(
      markers: milestones
          .map(
            (m) => Marker(
              point: m.position.toLatLng(),
              width: 28,
              height: 28,
              alignment: Alignment.center,
              child: _Chip(label: '${m.km}'),
            ),
          )
          .toList(),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.background,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
      ),
      alignment: Alignment.center,
      // noScaling: the marker is a fixed-diameter circle on the map, so a
      // scaled-up system font would spill the "5" outside its own badge rather
      // than making anything more readable. Map furniture is sized in map
      // pixels, not text pixels.
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: Text(
          label,
          style: TextStyle(
            color: AppColors.primary.foreground,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
