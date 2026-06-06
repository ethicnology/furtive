sealed class ActivitiesEvent {
  const ActivitiesEvent();
}

class FetchActivities extends ActivitiesEvent {
  const FetchActivities();
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

class ImportActivityFromGpx extends ActivitiesEvent {
  const ImportActivityFromGpx({required this.filePath});

  final String filePath;
}
