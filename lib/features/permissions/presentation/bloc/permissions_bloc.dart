import 'dart:io' show Platform;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/features/permissions/domain/usecases/check_permissions_use_case.dart';
import 'package:furtive/features/permissions/domain/usecases/get_permissions_use_case.dart';
import 'package:furtive/features/permissions/domain/usecases/request_permission_use_case.dart';
import 'package:furtive/features/permissions/domain/usecases/open_app_settings_use_case.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_event.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_state.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsBloc extends Bloc<PermissionsEvent, PermissionsState> {
  final _getPermissionsUseCase = GetPermissionsUseCase();
  final _requestPermissionUseCase = RequestPermissionUseCase();
  final _openAppSettingsUseCase = OpenAppSettingsUseCase();
  final _checkPermissionsUseCase = CheckPermissionsUseCase();

  PermissionsBloc() : super(const PermissionsState()) {
    on<LoadPermissions>(_onLoadPermissions);
    on<RequestPermission>(_onRequestPermission);
    on<CheckAllPermissions>(_onCheckAllPermissions);
    on<ClearPermissionsError>(_onClearPermissionsError);
  }

  void _onClearPermissionsError(
    ClearPermissionsError event,
    Emitter<PermissionsState> emit,
  ) {
    emit(state.copyWith(errorMessage: null));
  }

  Future<void> _onLoadPermissions(
    LoadPermissions event,
    Emitter<PermissionsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      final permissions = await _getPermissionsUseCase();

      final requiredPermissions = permissions.where((p) => !p.isOptional);
      final optionalPermissions = permissions.where((p) => p.isOptional);

      final requiredGranted =
          requiredPermissions.isNotEmpty &&
          requiredPermissions.every((p) => p.isGranted);
      final optionalGranted =
          optionalPermissions.isEmpty ||
          optionalPermissions.every((p) => p.isGranted);

      emit(
        state.copyWith(
          permissions: permissions,
          requiredGranted: requiredGranted,
          optionalGranted: optionalGranted,
          isLoading: false,
        ),
      );
    } catch (e) {
      // B17: must clear isLoading on error or the page is stuck on a spinner
      final err = e is AppError ? e : AppError(e.toString());
      emit(state.copyWith(errorMessage: err, isLoading: false));
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
      //    status to permanentlyDenied, so request() loops forever — it must
      //    go through settings. (iOS can escalate to Always via request().)
      // This keeps a permanently-denied *required* permission reachable
      // (the old code only opened settings for locationAlways).
      final status = await event.permission.status;
      final needsSettings =
          status.isPermanentlyDenied ||
          status.isRestricted ||
          (event.permission == Permission.locationAlways && Platform.isAndroid);
      if (needsSettings) {
        await _openAppSettingsUseCase();
      } else {
        await _requestPermissionUseCase(event.permission);
      }
      add(const LoadPermissions());
    } catch (e) {
      if (e is AppError) {
        emit(state.copyWith(errorMessage: e));
      } else {
        emit(state.copyWith(errorMessage: AppError(e.toString())));
      }
    }
  }

  Future<void> _onCheckAllPermissions(
    CheckAllPermissions event,
    Emitter<PermissionsState> emit,
  ) async {
    try {
      final (:areRequiredPermissionsGranted, :areOptionalPermissionsGranted) =
          await _checkPermissionsUseCase();

      emit(
        state.copyWith(
          requiredGranted: areRequiredPermissionsGranted,
          optionalGranted: areOptionalPermissionsGranted,
        ),
      );

      if (!areRequiredPermissionsGranted || !areOptionalPermissionsGranted) {
        add(const LoadPermissions());
      }
    } catch (e) {
      if (e is AppError) {
        emit(state.copyWith(errorMessage: e));
      } else {
        emit(state.copyWith(errorMessage: AppError(e.toString())));
      }
    }
  }
}
