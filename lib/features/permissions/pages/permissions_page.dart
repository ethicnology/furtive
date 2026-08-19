import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/repositories/preferences_repository.dart';
import 'package:furtive/core/widgets/bottom_navigation_widget.dart';
import 'package:furtive/features/onboarding/onboarding_page.dart';
import 'package:furtive/features/permissions/bloc/permissions_bloc.dart';
import 'package:furtive/features/permissions/bloc/permissions_event.dart';
import 'package:furtive/features/permissions/bloc/permissions_state.dart';
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
  final _preferences = PreferencesRepository();

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
    final prefs = await _preferences.fetch();
    if (!mounted) return;
    final destination = prefs.hasCompletedOnboarding
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
      body: BlocConsumer<PermissionsBloc, PermissionsState>(
        listenWhen: (previous, current) =>
            previous.errorMessage != current.errorMessage,
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!.message),
                backgroundColor: kDestructive,
                duration: const Duration(seconds: 3),
              ),
            );
            context.read<PermissionsBloc>().add(const ClearPermissionsError());
          }
        },
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final allRequiredGranted = state.requiredGranted;

          final textTheme = Theme.of(context).textTheme;
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.permissionsInstructions,
                  style: textTheme.bodyMedium?.copyWith(color: kTextMuted),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    itemCount: state.permissions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final permission = state.permissions[index];

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    permission.isGranted
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    color: permission.isGranted
                                        ? kMint
                                        : kTextMuted,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _localizedName(
                                        context,
                                        permission.permission,
                                        permission.name,
                                      ),
                                      style: textTheme.titleMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.only(left: 34),
                                child: Text(
                                  _localizedDescription(
                                    context,
                                    permission.permission,
                                    permission.description,
                                  ),
                                  style: textTheme.bodySmall,
                                ),
                              ),
                              if (!permission.isGranted) ...[
                                const SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.only(left: 34),
                                  child: OutlinedButton(
                                    onPressed: () {
                                      context.read<PermissionsBloc>().add(
                                        RequestPermission(
                                          permission.permission,
                                        ),
                                      );
                                    },
                                    child: Text(l10n.btnGrantPermission),
                                  ),
                                ),
                              ],
                              if (permission.isPermanentlyDenied)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 34,
                                    top: 8,
                                  ),
                                  child: Text(
                                    l10n.permPermanentlyDenied,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: kWarning,
                                    ),
                                  ),
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
