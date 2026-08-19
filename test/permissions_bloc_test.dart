import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/features/permissions/bloc/permissions_bloc.dart';
import 'package:furtive/features/permissions/bloc/permissions_event.dart';
import 'package:furtive/features/permissions/bloc/permissions_state.dart';
import 'package:furtive/features/permissions/permission_entity.dart';
import 'package:furtive/features/permissions/permission_repository.dart';
import 'package:permission_handler/permission_handler.dart';

/// Repository whose permission list the test controls outright, so the
/// required/optional grant logic can be exercised without a platform channel.
class _FakePermissionRepository extends PermissionRepository {
  _FakePermissionRepository(this._permissions);

  List<PermissionEntity> _permissions;
  bool throwOnFetch = false;
  int settingsOpened = 0;
  final requested = <Permission>[];

  set permissions(List<PermissionEntity> value) => _permissions = value;

  @override
  Future<List<PermissionEntity>> getPermissions() async {
    if (throwOnFetch) throw StateError('platform unavailable');
    return _permissions;
  }

  @override
  Future<PermissionStatus> requestPermission(Permission permission) async {
    requested.add(permission);
    return PermissionStatus.granted;
  }

  @override
  Future<bool> openAppSettings() async {
    settingsOpened++;
    return true;
  }
}

PermissionEntity perm({
  required String name,
  required bool granted,
  bool optional = false,
  Permission permission = Permission.location,
}) => PermissionEntity(
  name: name,
  description: '',
  permission: permission,
  isGranted: granted,
  isPermanentlyDenied: false,
  isOptional: optional,
);

void main() {
  group('summarise', () {
    test('all granted', () {
      final summary = PermissionRepository.summarise([
        perm(name: 'location', granted: true),
        perm(name: 'notifications', granted: true, optional: true),
      ]);
      expect(summary.requiredGranted, isTrue);
      expect(summary.optionalGranted, isTrue);
    });

    test('a denied optional permission does not block the required set', () {
      final summary = PermissionRepository.summarise([
        perm(name: 'location', granted: true),
        perm(name: 'notifications', granted: false, optional: true),
      ]);
      expect(summary.requiredGranted, isTrue);
      expect(summary.optionalGranted, isFalse);
    });

    test('no optional permissions is vacuously satisfied', () {
      final summary = PermissionRepository.summarise([
        perm(name: 'location', granted: true),
      ]);
      expect(summary.optionalGranted, isTrue);
    });

    test('an empty list is NOT "all good" — it means the platform returned '
        'nothing, which must not unlock recording', () {
      expect(PermissionRepository.summarise([]).requiredGranted, isFalse);
    });
  });

  group('PermissionsBloc', () {
    blocTest<PermissionsBloc, PermissionsState>(
      'load populates the list and the derived flags',
      build: () => PermissionsBloc(
        permissions: _FakePermissionRepository([
          perm(name: 'location', granted: true),
          perm(name: 'notifications', granted: false, optional: true),
        ]),
      ),
      act: (bloc) => bloc.add(const LoadPermissions()),
      wait: const Duration(milliseconds: 40),
      verify: (bloc) {
        expect(bloc.state.isLoading, isFalse);
        expect(bloc.state.permissions.length, 2);
        expect(bloc.state.requiredGranted, isTrue);
        expect(bloc.state.optionalGranted, isFalse);
      },
    );

    blocTest<PermissionsBloc, PermissionsState>(
      'a failed load clears isLoading — otherwise the page is stuck on a '
      'spinner forever',
      build: () => PermissionsBloc(
        permissions: _FakePermissionRepository([])..throwOnFetch = true,
      ),
      act: (bloc) => bloc.add(const LoadPermissions()),
      wait: const Duration(milliseconds: 40),
      verify: (bloc) {
        expect(bloc.state.isLoading, isFalse);
        expect(bloc.state.errorMessage, isNotNull);
      },
    );

    blocTest<PermissionsBloc, PermissionsState>(
      'checkAll refreshes the flags',
      build: () => PermissionsBloc(
        permissions: _FakePermissionRepository([
          perm(name: 'location', granted: true),
        ]),
      ),
      act: (bloc) => bloc.add(const CheckAllPermissions()),
      wait: const Duration(milliseconds: 60),
      verify: (bloc) => expect(bloc.state.requiredGranted, isTrue),
    );

    blocTest<PermissionsBloc, PermissionsState>(
      'the error is clearable',
      build: () => PermissionsBloc(
        permissions: _FakePermissionRepository([])..throwOnFetch = true,
      ),
      act: (bloc) async {
        bloc.add(const LoadPermissions());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        bloc.add(const ClearPermissionsError());
      },
      wait: const Duration(milliseconds: 60),
      verify: (bloc) => expect(bloc.state.errorMessage, isNull),
    );
  });
}
