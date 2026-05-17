import 'package:flutter/material.dart';
import 'package:furtive/core/entities/preferences_entity.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/locator.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/usecases/update_preferences_use_case.dart';
import 'package:furtive/core/widgets/bottom_navigation_widget.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';
import 'package:furtive/features/map/bloc/map_event.dart';

/// First-launch wizard. Walks the user through the choices that the rest of
/// the app reads from preferences (theme, language, GPS accuracy) before
/// dropping them on the map.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pageController = PageController();
  final _updatePreferences = UpdatePreferencesUseCase();

  MapThemeEntity _theme = MapThemeEntity.dark;
  MapLanguageEntity _language = MapLanguageEntity.en;
  int _accuracyMeters = 0;
  int _currentStep = 0;
  bool _saving = false;

  static const _stepCount = 4;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
    return Scaffold(
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
                  _ThemeStep(
                    value: _theme,
                    onChanged: (v) => setState(() => _theme = v),
                  ),
                  _LanguageStep(
                    value: _language,
                    onChanged: (v) => setState(() => _language = v),
                  ),
                  _AccuracyStep(
                    value: _accuracyMeters,
                    onChanged: (v) => setState(() => _accuracyMeters = v),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(context.screenPadding),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _next,
                  child:
                      _saving
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : Text(
                            _currentStep == _stepCount - 1 ? 'Finish' : 'Next',
                          ),
                ),
              ),
            ),
          ],
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

class _ThemeStep extends StatelessWidget {
  final MapThemeEntity value;
  final ValueChanged<MapThemeEntity> onChanged;
  const _ThemeStep({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Map theme',
      subtitle: 'Choose a default look for the map.',
      child: RadioGroup<MapThemeEntity>(
        groupValue: value,
        onChanged: (v) => v != null ? onChanged(v) : null,
        child: Column(
          children:
              MapThemeEntity.values
                  .map(
                    (t) => RadioListTile<MapThemeEntity>(
                      title: Text(t.name.toUpperCase()),
                      value: t,
                    ),
                  )
                  .toList(),
        ),
      ),
    );
  }
}

class _LanguageStep extends StatelessWidget {
  final MapLanguageEntity value;
  final ValueChanged<MapLanguageEntity> onChanged;
  const _LanguageStep({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Map language',
      subtitle: 'Language used for map labels.',
      child: RadioGroup<MapLanguageEntity>(
        groupValue: value,
        onChanged: (v) => v != null ? onChanged(v) : null,
        child: Column(
          children:
              MapLanguageEntity.values
                  .map(
                    (l) => RadioListTile<MapLanguageEntity>(
                      title: Text(l.name.toUpperCase()),
                      value: l,
                    ),
                  )
                  .toList(),
        ),
      ),
    );
  }
}

class _AccuracyStep extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _AccuracyStep({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'GPS accuracy',
      subtitle:
          'Minimum distance (m) between recorded points. Lower = more detail, more battery. 0 = every fix.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$value m',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          Slider(
            value: value.toDouble(),
            min: 0,
            max: 50,
            divisions: 50,
            label: '$value m',
            onChanged: (v) => onChanged(v.toInt()),
          ),
        ],
      ),
    );
  }
}
