import 'package:flutter/material.dart';
import 'package:furtive/core/theme.dart';

/// Numbered circular badge marking one kilometre milestone on a map.
///
/// Lives apart from any map layer because both rendering backends place it
/// during the migration, and it depends on neither.
class KmMilestoneChip extends StatelessWidget {
  final String label;
  const KmMilestoneChip({super.key, required this.label});

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
