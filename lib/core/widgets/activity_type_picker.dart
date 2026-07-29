import 'package:flutter/material.dart';
import 'package:furtive/core/entities/activity_profile.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/l10n/app_localizations.dart';

IconData activityTypeIcon(ActivityTypeEntity type) => switch (type) {
  ActivityTypeEntity.walk => Icons.directions_walk_rounded,
  ActivityTypeEntity.run => Icons.directions_run_rounded,
  ActivityTypeEntity.bike => Icons.directions_bike_rounded,
  ActivityTypeEntity.car => Icons.directions_car_rounded,
  ActivityTypeEntity.swim => Icons.pool_rounded,
  ActivityTypeEntity.aircraft => Icons.flight_rounded,
  ActivityTypeEntity.other => Icons.explore_rounded,
  ActivityTypeEntity.unknown => Icons.help_outline_rounded,
};

String activityTypeName(AppLocalizations l10n, ActivityTypeEntity type) =>
    switch (type) {
      ActivityTypeEntity.walk => l10n.activityWalk,
      ActivityTypeEntity.run => l10n.activityRun,
      ActivityTypeEntity.bike => l10n.activityBike,
      ActivityTypeEntity.car => l10n.activityCar,
      ActivityTypeEntity.swim => l10n.activitySwim,
      ActivityTypeEntity.aircraft => l10n.activityAircraft,
      ActivityTypeEntity.other => l10n.activityOther,
      ActivityTypeEntity.unknown => l10n.activityUnknown,
    };

/// The activities offered in the picker, in display order.
///
/// [ActivityTypeEntity.unknown] is deliberately absent: it exists for rows that
/// predate the taxonomy and for imports, and offering it as a choice would
/// invite users to record untyped activities on purpose — the one thing the
/// type is meant to stop.
List<ActivityTypeEntity> get selectableActivityTypes => ActivityTypeEntity
    .values
    .where((type) => type != ActivityTypeEntity.unknown)
    .toList(growable: false);

/// Bottom sheet listing every activity, with the current one checked. Returns
/// the chosen type, or null if dismissed.
///
/// A flat list, no grouping: at seven entries the whole set fits on screen and
/// choosing costs a single tap. The categories this used to need were a symptom
/// of the list being too long, not a feature — the previous 25-entry version
/// required a scroll to reach "car".
Future<ActivityTypeEntity?> showActivityTypePicker(
  BuildContext context, {
  required ActivityTypeEntity selected,
}) {
  return showModalBottomSheet<ActivityTypeEntity>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.symmetric(horizontal: context.screenPadding),
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.activityPickerTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            for (final type in selectableActivityTypes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(activityTypeIcon(type)),
                title: Text(activityTypeName(l10n, type)),
                selected: type == selected,
                trailing: type == selected
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(type),
              ),
          ],
        ),
      );
    },
  );
}
