import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/entities/preferences_entity.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/locator.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/usecases/update_preferences_use_case.dart';
import 'package:furtive/core/widgets/bottom_navigation_widget.dart';
import 'package:furtive/core/widgets/labeled_dropdown.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';
import 'package:furtive/features/map/bloc/map_event.dart';
import 'package:furtive/features/permissions/domain/entities/permission_entity.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_bloc.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_event.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_state.dart';

/// First-launch wizard:
/// 1. Welcome
/// 2. Settings (theme + language + accuracy)
/// 3. Permissions (locationWhenInUse required; locationAlways and
///    notification optional). Finish is disabled until locationWhenInUse
///    is granted.
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
  MapLanguageEntity _language = MapLanguageEntity.en;
  int _accuracyMeters = 0;
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
          mapLanguage: _language,
          accuracyInMeters: _accuracyMeters,
          hasCompletedOnboarding: true,
        ),
      );

      // MapBloc was instantiated at app start with the DB defaults — re-fire
      // InitMap so the user's chosen theme/language/accuracy take effect
      // before the map page is shown.
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
            'Could not save your choices: $e',
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
                      language: _language,
                      accuracyMeters: _accuracyMeters,
                      onThemeChanged: (v) => setState(() => _theme = v),
                      onLanguageChanged: (v) => setState(() => _language = v),
                      onAccuracyChanged:
                          (v) => setState(() => _accuracyMeters = v),
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
                        child:
                            _saving
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : Text(isLastStep ? 'Finish' : 'Next'),
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
                color:
                    filled
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
    return _StepShell(
      title: 'Welcome to Furtive',
      subtitle:
          'Privacy-first activity tracking. No accounts, no telemetry, no Google services. Let\'s pick a few defaults.',
      child: Center(
        child: Icon(
          Icons.directions_run,
          size: 96,
          color: AppColors.primary.background,
        ),
      ),
    );
  }
}

class _SettingsStep extends StatelessWidget {
  final MapThemeEntity theme;
  final MapLanguageEntity language;
  final int accuracyMeters;
  final ValueChanged<MapThemeEntity> onThemeChanged;
  final ValueChanged<MapLanguageEntity> onLanguageChanged;
  final ValueChanged<int> onAccuracyChanged;

  const _SettingsStep({
    required this.theme,
    required this.language,
    required this.accuracyMeters,
    required this.onThemeChanged,
    required this.onLanguageChanged,
    required this.onAccuracyChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Map settings',
      subtitle: 'Pick your defaults — you can change them later in settings.',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Theme',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            LabeledDropdown<MapThemeEntity>(
              value: theme,
              items: MapThemeEntity.values,
              labelFor: (t) => t.name.toUpperCase(),
              onChanged: onThemeChanged,
            ),
            const SizedBox(height: 24),
            const Text(
              'Language',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            LabeledDropdown<MapLanguageEntity>(
              value: language,
              items: MapLanguageEntity.values,
              labelFor: (l) => l.name.toUpperCase(),
              onChanged: onLanguageChanged,
            ),
            const SizedBox(height: 24),
            const Text(
              'GPS accuracy',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Minimum distance (m) between recorded points. Lower = more detail, more battery. 0 = every fix.',
              style: TextStyle(color: AppColors.tertiary.foreground),
            ),
            const SizedBox(height: 8),
            Text(
              '$accuracyMeters m',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            Slider(
              value: accuracyMeters.toDouble(),
              min: 0,
              max: 50,
              divisions: 50,
              label: '$accuracyMeters m',
              onChanged: (v) => onAccuracyChanged(v.toInt()),
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
    return _StepShell(
      title: 'Permissions',
      subtitle:
          'Grant location to track your runs. Notifications and background '
          'access are optional.',
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

class _PermissionCard extends StatelessWidget {
  final PermissionEntity permission;
  const _PermissionCard({required this.permission});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primary.background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  permission.isGranted ? Icons.check_circle : Icons.cancel,
                  color: permission.isGranted ? Colors.green : Colors.red,
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
                if (permission.isOptional)
                  Text(
                    'Optional',
                    style: TextStyle(color: AppColors.primary.foreground),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              permission.description,
              style: TextStyle(color: AppColors.primary.foreground),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed:
                  permission.isGranted
                      ? null
                      : () => context.read<PermissionsBloc>().add(
                        RequestPermission(permission.permission),
                      ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.quaternary.background,
                foregroundColor: AppColors.quaternary.foreground,
              ),
              child: const Text('Grant'),
            ),
            if (permission.isPermanentlyDenied)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Denied — enable it in app settings.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
