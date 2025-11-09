import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/widgets/bottom_navigation_widget.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_bloc.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_event.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_state.dart';

class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    context.read<PermissionsBloc>().add(const LoadPermissions());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<PermissionsBloc>().add(const LoadPermissions());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: BlocBuilder<PermissionsBloc, PermissionsState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final allRequiredGranted = state.requiredGranted;

          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This app needs the following permissions to work properly',
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: state.permissions.length,
                    itemBuilder: (context, index) {
                      final permission = state.permissions[index];

                      return Card(
                        color: AppColors.primary.background,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    permission.isGranted
                                        ? Icons.check_circle
                                        : Icons.cancel,
                                    color:
                                        permission.isGranted
                                            ? Colors.green
                                            : Colors.red,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      permission.name,
                                      style: TextStyle(
                                        color: AppColors.primary.foreground,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                permission.description,
                                style: TextStyle(
                                  color: AppColors.primary.foreground,
                                ),
                              ),
                              ElevatedButton(
                                onPressed:
                                    permission.isGranted
                                        ? null
                                        : () {
                                          context.read<PermissionsBloc>().add(
                                            RequestPermission(
                                              permission.permission,
                                            ),
                                          );
                                        },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      AppColors.quaternary.background,
                                  foregroundColor:
                                      AppColors.quaternary.foreground,
                                ),
                                child: Text('Grant Permission'),
                              ),

                              if (permission.isPermanentlyDenied)
                                const Text(
                                  'This permission has to be enabled in app settings.',
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: EdgeInsets.all(Global.spacing),
                    child: ElevatedButton(
                      onPressed:
                          allRequiredGranted
                              ? () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder:
                                        (context) =>
                                            const BottomNavigationWidget(),
                                  ),
                                );
                              }
                              : null,
                      child: Text(
                        allRequiredGranted
                            ? 'Continue'
                            : 'Grant Required Permissions to Continue',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
