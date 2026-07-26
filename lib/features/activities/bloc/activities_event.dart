import 'dart:async';

sealed class ActivitiesEvent {
  const ActivitiesEvent();
}

class FetchActivities extends ActivitiesEvent {
  const FetchActivities();
}

class FetchMoreActivities extends ActivitiesEvent {
  const FetchMoreActivities();
}

class ClearActivitiesFeedback extends ActivitiesEvent {
  const ClearActivitiesFeedback();
}

class UpdateActivityName extends ActivitiesEvent {
  const UpdateActivityName({
    required this.activityId,
    required this.newName,
    this.completion,
  });

  final String activityId;
  final String newName;
  final Completer<void>? completion;
}

class DeleteActivity extends ActivitiesEvent {
  const DeleteActivity({required this.activityId, this.completion});

  final String activityId;
  final Completer<void>? completion;
}

class ImportActivityFromGpx extends ActivitiesEvent {
  const ImportActivityFromGpx({required this.filePath});

  final String filePath;
}
