import 'package:dart_mappable/dart_mappable.dart';
import 'package:permission_handler/permission_handler.dart';

part 'permission_model.mapper.dart';

@MappableClass()
class PermissionModel with PermissionModelMappable {
  final String name;
  final String description;
  final Permission permission;
  final PermissionStatus status;
  final bool isOptional;

  const PermissionModel({
    required this.name,
    required this.description,
    required this.permission,
    required this.status,
    this.isOptional = false,
  });

  bool get isGranted =>
      status == PermissionStatus.granted || status == PermissionStatus.limited;

  bool get isDenied => status == PermissionStatus.denied;

  bool get isPermanentlyDenied => status == PermissionStatus.permanentlyDenied;
}
