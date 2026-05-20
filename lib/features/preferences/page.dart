import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/entities/preferences_entity.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/ui_languages.dart';
import 'package:furtive/core/widgets/labeled_dropdown.dart';
import 'package:furtive/features/preferences/bloc/preferences_bloc.dart';
import 'package:furtive/features/preferences/bloc/preferences_event.dart';
import 'package:furtive/features/preferences/bloc/preferences_state.dart';
import 'package:furtive/l10n/app_localizations.dart';

class PreferencesPage extends StatefulWidget {
  const PreferencesPage({super.key});

  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  // B20: create the bloc once in initState. The previous StatelessWidget +
  // FutureBuilder pattern called PreferencesBloc.create() on every build,
  // spawning a new bloc each rebuild.
  late final Future<PreferencesBloc> _blocFuture;
  // B21: own the bloc lifecycle so it gets closed when the page is popped,
  // otherwise BlocProvider.value would leak it.
  PreferencesBloc? _bloc;

  @override
  void initState() {
    super.initState();
    _blocFuture = PreferencesBloc.create().then((bloc) {
      _bloc = bloc;
      return bloc;
    });
  }

  @override
  void dispose() {
    _bloc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PreferencesBloc>(
      future: _blocFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return BlocProvider.value(
          value: snapshot.data!,
          child: Scaffold(
            appBar: AppBar(
              title: Text(AppLocalizations.of(context).preferencesTitle),
            ),
            body: BlocBuilder<PreferencesBloc, PreferencesState>(
              builder: (context, state) {
                if (state.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                return Column(
                  children: [
                    _buildMapThemeSection(context, state),
                    const SizedBox(height: 24),
                    _buildMapLanguageSection(context, state),
                    const SizedBox(height: 24),
                    _buildAppLanguageSection(context, state),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: EdgeInsets.all(context.screenPadding),
                        child: ElevatedButton(
                          onPressed: () {
                            // Pass state.preferences directly — re-building
                            // a PreferencesEntity by hand drops fields that
                            // aren't edited on this page (e.g.
                            // hasCompletedOnboarding) and silently resets
                            // them to their constructor defaults.
                            context.read<PreferencesBloc>().add(
                              UpdatePreferences(state.preferences),
                            );
                            Navigator.of(context).pop();
                          },
                          child: Text(AppLocalizations.of(context).btnApply),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

Widget _buildMapThemeSection(BuildContext context, PreferencesState state) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        AppLocalizations.of(context).prefMapTheme,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      LabeledDropdown<MapThemeEntity>(
        value: state.preferences.mapTheme,
        items: MapThemeEntity.values,
        labelFor: (t) => t.name.toUpperCase(),
        onChanged:
            (v) => context.read<PreferencesBloc>().add(ChangeMapTheme(v)),
      ),
    ],
  );
}

Widget _buildMapLanguageSection(BuildContext context, PreferencesState state) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        AppLocalizations.of(context).prefMapLanguage,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      LabeledDropdown<MapLanguageEntity>(
        value: state.preferences.mapLanguage,
        items: MapLanguageEntity.values,
        labelFor: (l) => l.name.toUpperCase(),
        onChanged:
            (v) => context.read<PreferencesBloc>().add(ChangeMapLanguage(v)),
      ),
    ],
  );
}

Widget _buildAppLanguageSection(BuildContext context, PreferencesState state) {
  final l10n = AppLocalizations.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        l10n.prefAppLanguage,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      LabeledDropdown<String?>(
        value: state.preferences.uiLocale,
        items: uiLanguageOptions,
        labelFor:
            (code) =>
                code == null
                    ? l10n.settingsUiLanguageSystem
                    : (uiLanguageNativeNames[code] ?? code.toUpperCase()),
        onChanged:
            (v) => context.read<PreferencesBloc>().add(ChangeUiLocale(v)),
      ),
    ],
  );
}
