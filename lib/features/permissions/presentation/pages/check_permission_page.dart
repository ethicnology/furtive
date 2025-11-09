import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/check_version_service.dart';
import 'package:furtive/core/widgets/bottom_navigation_widget.dart';
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

  @override
  void initState() {
    super.initState();
    context.read<PermissionsBloc>().add(const LoadPermissions());
  }

  void _navigate(bool allGranted) {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    checkNewVersion(context);

    if (allGranted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const BottomNavigationWidget()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const PermissionsPage()),
      );
    }
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
