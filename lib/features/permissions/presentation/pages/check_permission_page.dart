import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/check_version_service.dart';
import 'package:furtive/core/usecases/get_preferences_use_case.dart';
import 'package:furtive/core/widgets/bottom_navigation_widget.dart';
import 'package:furtive/features/onboarding/onboarding_page.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_bloc.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_event.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_state.dart';
import 'package:furtive/features/permissions/presentation/pages/permissions_page.dart';

class CheckPermissionPage extends StatefulWidget {
  const CheckPermissionPage({super.key});

  @override
  State<CheckPermissionPage> createState() => _PermissionCheckPageState();
}

class _PermissionCheckPageState extends State<CheckPermissionPage> {
  bool _hasNavigated = false;
  final _getPreferences = GetPreferencesUseCase();

  @override
  void initState() {
    super.initState();
    context.read<PermissionsBloc>().add(const LoadPermissions());
  }

  Future<void> _navigate(bool allGranted) async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    // Fire-and-forget — version check is informational, not gating
    unawaited(checkNewVersion(context));

    final prefs = await _getPreferences();
    if (!mounted) return;

    // The wizard now owns the permissions step, so onboarding takes priority
    // over the standalone PermissionsPage. PermissionsPage is only used as a
    // recovery fallback when an onboarded user has had a required permission
    // revoked (e.g. via system settings while the app was backgrounded).
    final Widget destination;
    if (!prefs.hasCompletedOnboarding) {
      destination = const OnboardingPage();
    } else if (!allGranted) {
      destination = const PermissionsPage();
    } else {
      destination = const BottomNavigationWidget();
    }

    await Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PermissionsBloc, PermissionsState>(
      listener: (context, state) {
        if (!state.isLoading) _navigate(state.requiredGranted);
      },
      child: const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}
