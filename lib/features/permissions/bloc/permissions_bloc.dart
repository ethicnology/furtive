import 'dart:io' show Platform;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/features/permissions/bloc/permissions_event.dart';
import 'package:furtive/features/permissions/bloc/permissions_state.dart';
import 'package:furtive/features/permissions/permission_repository.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsBloc extends Bloc<PermissionsEvent, PermissionsState> {
  PermissionsBloc({PermissionRepository? permissions})
    : _permissions = permissions ?? PermissionRepository(),
      super(const PermissionsState()) {
    on<LoadPermissions>(_onLoadPermissions);
    on<RequestPermission>(_onRequestPermission);
    on<CheckAllPermissions>(_onCheckAllPermissions);
    on<ClearPermissionsError>(
      (_, emit) => emit(state.copyWith(errorMessage: null)),
    );
  }

  final PermissionRepository _permissions;

  AppError _asAppError(Object e) => e is AppError ? e : AppError(e.toString());

  Future<void> _onLoadPermissions(
    LoadPermissions event,
    Emitter<PermissionsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      final permissions = await _permissions.getPermissions();
      // Single source for this derivation — it used to be written out here AND
      // in CheckPermissionsUseCase, so the two could silently disagree.
      final summary = PermissionRepository.summarise(permissions);
      emit(
        state.copyWith(
          permissions: permissions,
          requiredGranted: summary.requiredGranted,
          optionalGranted: summary.optionalGranted,
          isLoading: false,
        ),
      );
    } catch (e) {
      // Must clear isLoading on error or the page is stuck on a spinner.
      emit(state.copyWith(errorMessage: _asAppError(e), isLoading: false));
    }
  }

  Future<void> _onRequestPermission(
    RequestPermission event,
    Emitter<PermissionsState> emit,
  ) async {
    try {
      // Route to the OS settings screen when an in-app request() would be a
      // silent no-op, otherwise request inline:
      //  - permanently denied / restricted: request() does nothing.
      //  - Android background location ("Allow all the time"): Android 11+
      //    forbids granting it from an in-app dialog and does NOT flip the
      //    status to permanentlyDenied, so request() loops forever — it must go
      //    through settings. (iOS can escalate to Always via request().)
      final status = await event.permission.status;
      final needsSettings =
          status.isPermanentlyDenied ||
          status.isRestricted ||
          (event.permission == Permission.locationAlways && Platform.isAndroid);
      if (needsSettings) {
        await _permissions.openAppSettings();
      } else {
        await _permissions.requestPermission(event.permission);
      }
      add(const LoadPermissions());
    } catch (e) {
      emit(state.copyWith(errorMessage: _asAppError(e)));
    }
  }

  Future<void> _onCheckAllPermissions(
    CheckAllPermissions event,
    Emitter<PermissionsState> emit,
  ) async {
    try {
      final summary = await _permissions.checkAll();
      emit(
        state.copyWith(
          requiredGranted: summary.requiredGranted,
          optionalGranted: summary.optionalGranted,
        ),
      );
      if (!summary.requiredGranted || !summary.optionalGranted) {
        add(const LoadPermissions());
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: _asAppError(e)));
    }
  }
}
