import 'package:permission_handler/permission_handler.dart';

class PermissionsEvent {
  const PermissionsEvent();
}

class LoadPermissions extends PermissionsEvent {
  const LoadPermissions();
}

class RequestPermission extends PermissionsEvent {
  final Permission permission;

  const RequestPermission(this.permission);
}

class CheckAllPermissions extends PermissionsEvent {
  const CheckAllPermissions();
}

/// Dismisses PermissionsState.errorMessage after the UI has shown it —
/// mirrors MapBloc's ClearError. Without a way to clear it, errorMessage was
/// set on a failed load/request but nothing ever read it, so a permission
/// check/request failure was silently invisible to the user (see M1 in
/// REVIEW-2026-07-FULL-APP.md).
class ClearPermissionsError extends PermissionsEvent {
  const ClearPermissionsError();
}
