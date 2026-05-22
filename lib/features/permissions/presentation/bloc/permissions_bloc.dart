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
      switch (event.permission) {
        case Permission.locationAlways:
          await _openAppSettingsUseCase();
          break;
        default:
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
