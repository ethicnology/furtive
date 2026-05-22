import 'package:permission_handler/permission_handler.dart';
import 'package:furtive/features/permissions/data/models/permission_model.dart';

class PermissionDataSource {
  Future<List<PermissionModel>> getPermissions() async {
    final locationWhenInUseStatus = await Permission.locationWhenInUse.status;
    final locationAlwaysStatus = await Permission.locationAlways.status;

    // The "Tracking active" notification while an activity runs is a
    // foreground-service notification, which Android exempts from
    // POST_NOTIFICATIONS — so we don't ask the user for that permission.
    final permissions = [
      PermissionModel(
        name: 'Location While Using',
        description:
            'Required to track your position and display it on the map.',
        permission: Permission.locationWhenInUse,
        status: locationWhenInUseStatus,
      ),
      PermissionModel(
        name: 'Location Always',
        description: 'Optional: keeps tracking accurate during long activities, even if the OS suspends the app.',
        permission: Permission.locationAlways,
        status: locationAlwaysStatus,
        isOptional: true,
      ),
    ];

    return permissions;
  }

  Future<PermissionStatus> requestPermission(Permission permission) async {
    return await permission.request();
  }

  Future<bool> openSettings() async {
    return await openAppSettings();
  }
}
