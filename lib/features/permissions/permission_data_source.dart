import 'package:permission_handler/permission_handler.dart';
import 'package:furtive/features/permissions/permission_model.dart';

class PermissionDataSource {
  Future<List<PermissionModel>> getPermissions() async {
    final locationWhenInUseStatus = await Permission.locationWhenInUse.status;
    final locationAlwaysStatus = await Permission.locationAlways.status;
    final notificationStatus = await Permission.notification.status;

    // POST_NOTIFICATIONS (Android 13+) is NOT required to start or keep the
    // foreground service running — but without it, the "Recording activity"
    // notification is invisible in the notification drawer (only reachable
    // via the Android 13+ Task Manager), so the user loses the visible
    // "a run is being tracked" signal and the setOngoing anti-swipe-kill
    // mitigation. See
    // https://developer.android.com/develop/ui/views/notifications/notification-permission
    // Optional: a denial never blocks recording, it only makes the
    // notification harder to see.
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
        description:
            'Optional: keeps tracking accurate during long activities, even if the OS suspends the app.',
        permission: Permission.locationAlways,
        status: locationAlwaysStatus,
        isOptional: true,
      ),
      PermissionModel(
        name: 'Notifications',
        description:
            'Optional: shows an ongoing "Recording activity" notification, '
            'which also helps Android avoid stopping tracking in the '
            'background.',
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
