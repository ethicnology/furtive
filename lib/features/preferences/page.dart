import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/entities/preferences_entity.dart';
import 'package:furtive/core/repositories/preferences_repository.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/ui_languages.dart';
import 'package:furtive/core/widgets/labeled_dropdown.dart';
import 'package:furtive/features/preferences/bloc/preferences_bloc.dart';
import 'package:furtive/features/preferences/bloc/preferences_event.dart';
import 'package:furtive/features/preferences/bloc/preferences_state.dart';
import 'package:furtive/l10n/app_localizations.dart';

class PreferencesPage extends StatefulWidget {
  const PreferencesPage({super.key, this.repository});

  /// Injectable storage, defaulting to the real one. Only set in tests — it is
  /// what makes the failed-save path (which must keep the page mounted and show
  /// an error) reachable at all.
  final PreferencesRepository? repository;

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
    _blocFuture = PreferencesBloc.create(repository: widget.repository).then((
      bloc,
    ) {
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
          child: BlocListener<PreferencesBloc, PreferencesState>(
            // Pop only once the write has actually landed; surface a failure
            // instead of pretending it succeeded. Before this, Apply popped in
            // the same frame it dispatched, so a failed save vanished.
            listenWhen: (previous, current) =>
                previous.saveCompleted != current.saveCompleted &&
                current.saveCompleted != null,
            listener: (context, state) {
              if (state.saveCompleted == true) {
                Navigator.of(context).pop();
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppLocalizations.of(context).prefSaveFailed),
                  backgroundColor: AppColors.destructive.background,
                ),
              );
            },
            child: Scaffold(
              appBar: AppBar(
                title: Text(AppLocalizations.of(context).preferencesTitle),
              ),
              body: BlocBuilder<PreferencesBloc, PreferencesState>(
                builder: (context, state) {
                  if (state.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // Scrollable + IntrinsicHeight rather than a bare Column:
                  // the Spacer below pushes Apply to the bottom when there is
                  // room, but with five sections a short screen — or the same
                  // screen at an accessibility font scale — overflowed the
                  // Column and pushed Apply off the viewport entirely, making
                  // the settings impossible to save. LayoutBuilder feeds the
                  // viewport height in as a minimum so the Spacer keeps working
                  // when it fits, and the whole thing scrolls when it doesn't.
                  return LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            children: [
                              _buildMapThemeSection(context, state),
                              const SizedBox(height: 24),
                              _buildAppLanguageSection(context, state),
                              const SizedBox(height: 24),
                              _buildCheckUpdatesSection(context, state),
                              const SizedBox(height: 24),
                              _buildMapTilesSection(context, state),
                              const SizedBox(height: 24),
                              _buildLockScreenSection(context, state),
                              const Spacer(),
                              SizedBox(
                                width: double.infinity,
                                child: Padding(
                                  padding: EdgeInsets.all(
                                    context.screenPadding,
                                  ),
                                  child: ElevatedButton(
                                    // Disabled while the write is in flight so Apply
                                    // can't be double-dispatched.
                                    onPressed: state.isSaving
                                        ? null
                                        : () {
                                            // Pass state.preferences directly —
                                            // re-building a PreferencesEntity by hand
                                            // drops fields that aren't edited on this
                                            // page (e.g. hasCompletedOnboarding) and
                                            // silently resets them to their constructor
                                            // defaults.
                                            //
                                            // No pop() here: the page must outlive the
                                            // write so a failure can be shown. The
                                            // BlocListener above pops on success.
                                            context.read<PreferencesBloc>().add(
                                              UpdatePreferences(
                                                state.preferences,
                                              ),
                                            );
                                          },
                                    child: state.isSaving
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Text(
                                            AppLocalizations.of(
                                              context,
                                            ).btnApply,
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
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
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      LabeledDropdown<MapThemeEntity>(
        value: state.preferences.mapTheme,
        items: MapThemeEntity.values,
        labelFor: (t) => mapThemeName(AppLocalizations.of(context), t),
        onChanged: (v) =>
            context.read<PreferencesBloc>().add(ChangeMapTheme(v)),
      ),
    ],
  );
}

/// Localised display name for a map theme. Shared with the onboarding wizard.
String mapThemeName(AppLocalizations l10n, MapThemeEntity theme) =>
    switch (theme) {
      MapThemeEntity.light => l10n.prefThemeLight,
      MapThemeEntity.dark => l10n.prefThemeDark,
      MapThemeEntity.white => l10n.prefThemeWhite,
      MapThemeEntity.grayscale => l10n.prefThemeGrayscale,
      MapThemeEntity.black => l10n.prefThemeBlack,
    };

Widget _buildCheckUpdatesSection(BuildContext context, PreferencesState state) {
  final l10n = AppLocalizations.of(context);
  return SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      l10n.prefCheckUpdates,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(l10n.prefCheckUpdatesSubtitle),
    value: state.preferences.checkUpdates,
    onChanged: (v) =>
        context.read<PreferencesBloc>().add(ChangeCheckUpdates(v)),
  );
}

Widget _buildMapTilesSection(BuildContext context, PreferencesState state) {
  final l10n = AppLocalizations.of(context);
  return SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      l10n.prefMapTiles,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(l10n.prefMapTilesSubtitle),
    value: state.preferences.mapTilesEnabled,
    onChanged: (v) =>
        context.read<PreferencesBloc>().add(ChangeMapTilesEnabled(v)),
  );
}

Widget _buildLockScreenSection(BuildContext context, PreferencesState state) {
  final l10n = AppLocalizations.of(context);
  return SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      l10n.prefShowOnLockScreen,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(l10n.prefShowOnLockScreenSubtitle),
    value: state.preferences.showOnLockScreen,
    onChanged: (v) =>
        context.read<PreferencesBloc>().add(ChangeShowOnLockScreen(v)),
  );
}

Widget _buildAppLanguageSection(BuildContext context, PreferencesState state) {
  final l10n = AppLocalizations.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        l10n.prefAppLanguage,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      LabeledDropdown<String?>(
        value: state.preferences.uiLocale,
        items: uiLanguageOptions,
        labelFor: (code) => code == null
            ? l10n.settingsUiLanguageSystem
            : (uiLanguageNativeNames[code] ?? code.toUpperCase()),
        onChanged: (v) =>
            context.read<PreferencesBloc>().add(ChangeUiLocale(v)),
      ),
    ],
  );
}
