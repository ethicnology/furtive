import 'package:permission_handler/permission_handler.dart';
import 'package:furtive/features/permissions/data/datasources/permission_data_source.dart';
import 'package:furtive/features/permissions/domain/entities/permission_entity.dart';

class PermissionRepository {
  final _dataSource = PermissionDataSource();

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

  Future<PermissionStatus> requestPermission(Permission permission) async {
    return await _dataSource.requestPermission(permission);
  }

  Future<bool> openAppSettings() async {
    return await _dataSource.openSettings();
  }
}
