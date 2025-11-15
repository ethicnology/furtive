import 'package:furtive/core/entities/activity_entity.dart';

sealed class ActivitiesEvent {
  const ActivitiesEvent();
}

class FetchActivities extends ActivitiesEvent {
  const FetchActivities();
}

class SelectActivity extends ActivitiesEvent {
  const SelectActivity({required this.activity});

  final ActivityEntity activity;
}

class UpdateActivityName extends ActivitiesEvent {
  const UpdateActivityName({required this.activityId, required this.newName});

  final String activityId;
  final String newName;
}

class DeleteActivity extends ActivitiesEvent {
  const DeleteActivity({required this.activityId});

  final String activityId;
}
