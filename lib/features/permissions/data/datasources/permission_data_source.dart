import 'package:permission_handler/permission_handler.dart';
import 'package:furtive/features/permissions/data/models/permission_model.dart';

class PermissionDataSource {
  Future<List<PermissionModel>> getPermissions() async {
    final locationWhenInUseStatus = await Permission.locationWhenInUse.status;
    final notificationStatus = await Permission.notification.status;

    final permissions = [
      PermissionModel(
        name: 'Location When In Use',
        description:
            'Required to track your position and display it on the map',
        permission: Permission.locationWhenInUse,
        status: locationWhenInUseStatus,
      ),
      PermissionModel(
        name: 'Notifications',
        description:
            'Optional: shows an ongoing notification while you are recording '
            'an activity, even when the app is in the background.',
        permission: Permission.notification,
        status: notificationStatus,
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
