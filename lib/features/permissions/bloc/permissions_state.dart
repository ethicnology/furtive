import 'package:dart_mappable/dart_mappable.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/features/permissions/permission_entity.dart';

part 'permissions_state.mapper.dart';

@MappableClass()
class PermissionsState with PermissionsStateMappable {
  final List<PermissionEntity> permissions;
  final bool isLoading;
  final bool requiredGranted;
  final bool optionalGranted;
  final AppError? errorMessage;

  const PermissionsState({
    this.permissions = const [],
    this.isLoading = false,
    this.requiredGranted = false,
    this.optionalGranted = false,
    this.errorMessage,
  });
}
