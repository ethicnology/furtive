import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/usecases/get_preferences_use_case.dart';
import 'package:furtive/core/widgets/bottom_navigation_widget.dart';
import 'package:furtive/features/onboarding/onboarding_page.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_bloc.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_event.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_state.dart';
import 'package:furtive/l10n/app_localizations.dart';
import 'package:permission_handler/permission_handler.dart';

// Map the runtime Permission to the localised name/description in
// app_*.arb. Unknown permissions fall back to the entity copy so a newly
// added permission doesn't break the build.
String _localizedName(BuildContext context, Permission p, String fallback) {
  final l10n = AppLocalizations.of(context);
  if (p == Permission.locationWhenInUse) return l10n.permLocationWhileUsingName;
  if (p == Permission.locationAlways) return l10n.permLocationAlwaysName;
  if (p == Permission.notification) return l10n.permNotificationName;
  return fallback;
}

String _localizedDescription(
  BuildContext context,
  Permission p,
  String fallback,
) {
  final l10n = AppLocalizations.of(context);
  if (p == Permission.locationWhenInUse) return l10n.permLocationWhileUsingDesc;
  if (p == Permission.locationAlways) return l10n.permLocationAlwaysDesc;
  if (p == Permission.notification) return l10n.permNotificationDesc;
  return fallback;
}

class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage>
    with WidgetsBindingObserver {
  final _getPreferences = GetPreferencesUseCase();

  @override
  void initState() {
    super.initState();
    // B19: the WidgetsBindingObserver mixin only fires lifecycle callbacks
    // once the instance is registered with WidgetsBinding.
    WidgetsBinding.instance.addObserver(this);
    context.read<PermissionsBloc>().add(const LoadPermissions());
  }

  Future<void> _onContinue() async {
    // B39: Continue must honor the onboarding flag — otherwise a fresh
    // install that lands on this page (because permissions were denied)
    // skips the wizard once permissions are granted.
    final prefs = await _getPreferences();
    if (!mounted) return;
    final destination =
        prefs.hasCompletedOnboarding
            ? const BottomNavigationWidget()
            : const OnboardingPage();
    await Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => destination));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<PermissionsBloc>().add(const LoadPermissions());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.permissionsTitle)),
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
                Text(l10n.permissionsInstructions),
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
                                      _localizedName(context, permission.permission, permission.name),
                                      style: TextStyle(
                                        color: AppColors.primary.foreground,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                _localizedDescription(context, permission.permission, permission.description),
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
                                child: Text(l10n.btnGrantPermission),
                              ),

                              if (permission.isPermanentlyDenied)
                                Text(l10n.permPermanentlyDenied),
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
                    padding: EdgeInsets.all(context.screenPadding),
                    child: ElevatedButton(
                      onPressed: allRequiredGranted ? _onContinue : null,
                      child: Text(
                        allRequiredGranted
                            ? l10n.btnContinue
                            : l10n.btnGrantToContinue,
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
