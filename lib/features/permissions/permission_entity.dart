import 'package:dart_mappable/dart_mappable.dart';
import 'package:permission_handler/permission_handler.dart';

part 'permission_entity.mapper.dart';

@MappableClass()
class PermissionEntity with PermissionEntityMappable {
  final String name;
  final String description;
  final Permission permission;
  final bool isGranted;
  final bool isPermanentlyDenied;
  final bool isOptional;

  const PermissionEntity({
    required this.name,
    required this.description,
    required this.permission,
    required this.isGranted,
    required this.isPermanentlyDenied,
    this.isOptional = false,
  });
}
