import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/entities/preferences_entity.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/locale_cubit.dart';
import 'package:furtive/core/locator.dart';
import 'package:furtive/core/ui_languages.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/usecases/update_preferences_use_case.dart';
import 'package:furtive/core/widgets/bottom_navigation_widget.dart';
import 'package:furtive/core/widgets/labeled_dropdown.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';
import 'package:furtive/features/map/bloc/map_event.dart';
import 'package:furtive/features/preferences/page.dart' show mapThemeName;
import 'package:furtive/features/permissions/domain/entities/permission_entity.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_bloc.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_event.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_state.dart';
import 'package:furtive/l10n/app_localizations.dart';

/// First-launch wizard:
/// 1. Welcome
/// 2. Settings (theme + UI language)
/// 3. Permissions (locationWhenInUse required; locationAlways optional).
///    Finish is disabled until locationWhenInUse is granted.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with WidgetsBindingObserver {
  final _pageController = PageController();
  final _updatePreferences = UpdatePreferencesUseCase();
  late final PermissionsBloc _permissionsBloc;

  MapThemeEntity _theme = MapThemeEntity.dark;
  String? _uiLocale; // null = follow system
  int _currentStep = 0;
  bool _saving = false;

  static const _stepCount = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _permissionsBloc = PermissionsBloc()..add(const LoadPermissions());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _permissionsBloc.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android 11+ locationAlways requires the user to go to system
    // settings and come back. Refresh when the app resumes.
    if (state == AppLifecycleState.resumed) {
      _permissionsBloc.add(const LoadPermissions());
    }
  }

  Future<void> _next() async {
    if (_saving) return;
    if (_currentStep < _stepCount - 1) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      await _finish();
    }
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      await _updatePreferences(
        PreferencesEntity(
          mapTheme: _theme,
          hasCompletedOnboarding: true,
          uiLocale: _uiLocale,
          // Stamp the current version so the post-upgrade changelog doesn't
          // immediately pop in front of a user who just finished onboarding.
          lastShownChangelogVersion: Global.app.version,
        ),
      );
      // Apply locale immediately so the app shell uses the chosen language
      // from the first frame after onboarding completes.
      getIt<LocaleCubit>().setLocale(_uiLocale);

      // MapBloc was instantiated at app start with the DB defaults — re-fire
      // InitMap so the user's chosen theme/language take effect before the
      // map page is shown.
      getIt<MapBloc>().add(const InitMap());

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const BottomNavigationWidget()),
      );
    } catch (e, st) {
      logs.severe('Onboarding finish', error: e, trace: st);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.destructive.background,
          content: Text(
            AppLocalizations.of(context).onboardSaveError(e.toString()),
            style: TextStyle(color: AppColors.destructive.foreground),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _permissionsBloc,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _ProgressIndicator(step: _currentStep, total: _stepCount),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentStep = i),
                  children: [
                    _WelcomeStep(),
                    _SettingsStep(
                      theme: _theme,
                      uiLocale: _uiLocale,
                      onThemeChanged: (v) => setState(() => _theme = v),
                      onUiLocaleChanged: (v) {
                        setState(() => _uiLocale = v);
                        // Preview locale change live so the wizard itself
                        // immediately reflects the chosen language.
                        getIt<LocaleCubit>().setLocale(v);
                      },
                    ),
                    const _PermissionsStep(),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(context.screenPadding),
                child: SizedBox(
                  width: double.infinity,
                  child: BlocBuilder<PermissionsBloc, PermissionsState>(
                    builder: (context, permissionsState) {
                      final isLastStep = _currentStep == _stepCount - 1;
                      final canFinish =
                          !isLastStep || permissionsState.requiredGranted;
                      return ElevatedButton(
                        onPressed: (_saving || !canFinish) ? null : _next,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                isLastStep
                                    ? AppLocalizations.of(context).btnFinish
                                    : AppLocalizations.of(context).btnNext,
                              ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressIndicator extends StatelessWidget {
  final int step;
  final int total;
  const _ProgressIndicator({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: List.generate(total, (i) {
          final filled = i <= step;
          return Expanded(
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: filled
                    ? AppColors.primary.background
                    : AppColors.tertiary.background,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _StepShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _StepShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.tertiary.foreground,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _StepShell(
      title: l10n.onboardWelcomeTitle,
      subtitle: l10n.onboardWelcomeSubtitle,
      child: Center(
        child: Icon(
          Icons.directions_run_rounded,
          size: 96,
          color: AppColors.primary.background,
        ),
      ),
    );
  }
}

class _SettingsStep extends StatelessWidget {
  final MapThemeEntity theme;
  final String? uiLocale;
  final ValueChanged<MapThemeEntity> onThemeChanged;
  final ValueChanged<String?> onUiLocaleChanged;

  const _SettingsStep({
    required this.theme,
    required this.uiLocale,
    required this.onThemeChanged,
    required this.onUiLocaleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _StepShell(
      title: l10n.onboardSettingsTitle,
      subtitle: l10n.onboardSettingsSubtitle,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.settingsThemeLabel,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            LabeledDropdown<MapThemeEntity>(
              value: theme,
              items: MapThemeEntity.values,
              labelFor: (t) => mapThemeName(AppLocalizations.of(context), t),
              onChanged: onThemeChanged,
            ),
            const SizedBox(height: 24),
            Text(
              l10n.settingsUiLanguageLabel,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            LabeledDropdown<String?>(
              value: uiLocale,
              items: uiLanguageOptions,
              labelFor: (code) => code == null
                  ? l10n.settingsUiLanguageSystem
                  : (uiLanguageNativeNames[code] ?? code.toUpperCase()),
              onChanged: onUiLocaleChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionsStep extends StatelessWidget {
  const _PermissionsStep();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _StepShell(
      title: l10n.onboardPermissionsTitle,
      subtitle: l10n.onboardPermissionsSubtitle,
      child: BlocBuilder<PermissionsBloc, PermissionsState>(
        builder: (context, state) {
          if (state.isLoading && state.permissions.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.separated(
            itemCount: state.permissions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _PermissionCard(permission: state.permissions[index]);
            },
          );
        },
      ),
    );
  }
}

// Map the runtime Permission to the localised name/description copies in
// app_*.arb. Unknown permissions fall back to the entity's hardcoded text
// so newly-added permissions don't break the build.
String _localizedName(BuildContext context, PermissionEntity p) {
  final l10n = AppLocalizations.of(context);
  if (p.permission == Permission.locationWhenInUse) {
    return l10n.permLocationWhileUsingName;
  }
  if (p.permission == Permission.locationAlways) {
    return l10n.permLocationAlwaysName;
  }
  if (p.permission == Permission.notification) {
    return l10n.permNotificationName;
  }
  return p.name;
}

String _localizedDescription(BuildContext context, PermissionEntity p) {
  final l10n = AppLocalizations.of(context);
  if (p.permission == Permission.locationWhenInUse) {
    return l10n.permLocationWhileUsingDesc;
  }
  if (p.permission == Permission.locationAlways) {
    return l10n.permLocationAlwaysDesc;
  }
  if (p.permission == Permission.notification) {
    return l10n.permNotificationDesc;
  }
  return p.description;
}

class _PermissionCard extends StatelessWidget {
  final PermissionEntity permission;
  const _PermissionCard({required this.permission});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  permission.isGranted
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: permission.isGranted ? kMint : kTextMuted,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _localizedName(context, permission),
                    style: textTheme.titleMedium,
                  ),
                ),
                if (permission.isOptional)
                  Text(
                    AppLocalizations.of(context).permOptional,
                    style: textTheme.labelSmall,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Text(
                _localizedDescription(context, permission),
                style: textTheme.bodySmall,
              ),
            ),
            if (!permission.isGranted) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 34),
                child: OutlinedButton(
                  onPressed: () => context.read<PermissionsBloc>().add(
                    RequestPermission(permission.permission),
                  ),
                  child: Text(AppLocalizations.of(context).btnGrant),
                ),
              ),
            ],
            if (permission.isPermanentlyDenied)
              Padding(
                padding: const EdgeInsets.only(left: 34, top: 8),
                child: Text(
                  AppLocalizations.of(context).permDeniedMsg,
                  style: textTheme.bodySmall?.copyWith(color: kWarning),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
