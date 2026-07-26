import 'package:permission_handler/permission_handler.dart';
import 'package:furtive/features/permissions/permission_data_source.dart';
import 'package:furtive/features/permissions/permission_entity.dart';

/// Whether the app has everything it needs, split by whether a permission is
/// load-bearing. Required permissions gate recording entirely; optional ones
/// (notifications, background location, battery exemption) only make tracking
/// more robust, so a denial is surfaced but never blocks.
typedef PermissionsSummary = ({bool requiredGranted, bool optionalGranted});

/// Entity-level access to the OS permission state.
///
/// The former GetPermissions / RequestPermission / OpenAppSettings use cases
/// were one-line aliases over the three methods below and are gone.
/// CheckPermissionsUseCase held the [summarise] derivation — which was
/// *duplicated* inline in PermissionsBloc._onLoadPermissions, so the two could
/// drift apart. It now exists once, here.
class PermissionRepository {
  PermissionRepository({PermissionDataSource? dataSource})
    : _dataSource = dataSource ?? PermissionDataSource();

  final PermissionDataSource _dataSource;

  Future<List<PermissionEntity>> getPermissions() async {
    final permissions = await _dataSource.getPermissions();
    return permissions
        .map(
          (p) => PermissionEntity(
            name: p.name,
            description: p.description,
            permission: p.permission,
            isGranted: p.isGranted,
            isPermanentlyDenied: p.isPermanentlyDenied,
            isOptional: p.isOptional,
          ),
        )
        .toList();
  }

  /// Derives the required/optional grant summary from a permission list.
  ///
  /// `requiredGranted` deliberately demands a non-empty required set: an empty
  /// list means the platform returned nothing, which must not read as "all
  /// good". `optionalGranted` is vacuously true when there are no optional
  /// permissions.
  static PermissionsSummary summarise(List<PermissionEntity> permissions) {
    final required = permissions.where((p) => !p.isOptional);
    final optional = permissions.where((p) => p.isOptional);
    return (
      requiredGranted:
          required.isNotEmpty && required.every((p) => p.isGranted),
      optionalGranted: optional.isEmpty || optional.every((p) => p.isGranted),
    );
  }

  /// Convenience: fetch and summarise in one call.
  Future<PermissionsSummary> checkAll() async =>
      summarise(await getPermissions());

  Future<PermissionStatus> requestPermission(Permission permission) =>
      _dataSource.requestPermission(permission);

  Future<bool> openAppSettings() => _dataSource.openSettings();
}
