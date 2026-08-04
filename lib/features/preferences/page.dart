import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/entities/activity_profile.dart';
import 'package:furtive/core/entities/preferences_entity.dart';
import 'package:furtive/core/repositories/preferences_repository.dart';
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
            // Changes apply immediately — there is no Apply button — so a
            // failed write has no spinner to hide behind: report it. The
            // bloc rolls the control back to the persisted value itself.
            listenWhen: (previous, current) =>
                previous.saveCompleted != current.saveCompleted &&
                current.saveCompleted == false,
            listener: (context, state) {
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

                  // Plain scrollable column: the page used to need a Spacer +
                  // IntrinsicHeight to keep the Apply button reachable on
                  // short viewports; without the button, scrolling alone
                  // covers the accessibility font-scale case.
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      children: [
                        _buildMapThemeSection(context, state),
                        const SizedBox(height: 24),
                        _buildAppLanguageSection(context, state),
                        const SizedBox(height: 24),
                        _buildMapTilesSection(context, state),
                        const SizedBox(height: 24),
                        _buildLockScreenSection(context, state),
                        const SizedBox(height: 24),
                        _buildMapControlsSideSection(context, state),
                        const SizedBox(height: 24),
                        _buildRecordingDetailSection(context, state),
                        const SizedBox(height: 24),
                      ],
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

Widget _buildMapControlsSideSection(
  BuildContext context,
  PreferencesState state,
) {
  final l10n = AppLocalizations.of(context);
  return SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      l10n.prefMapControlsOnRight,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(l10n.prefMapControlsOnRightSubtitle),
    // The toggle presents the default-true direction (controls on the
    // right); storage keeps the historical mapControlsOnLeft column, so the
    // value is inverted at both ends. No migration needed.
    value: !state.preferences.mapControlsOnLeft,
    onChanged: (v) =>
        context.read<PreferencesBloc>().add(ChangeMapControlsOnLeft(!v)),
  );
}

/// Sampling density. Deliberately three named intents rather than a number of
/// seconds: the right interval depends on the activity (which the recorder
/// already knows) and no user can reason about it, while a wrong value
/// silently degrades the trace. The app has been here before — a
/// user-facing GPS precision setting was removed years ago as confusing more
/// than helping, leaving a dead column behind.
Widget _buildRecordingDetailSection(
  BuildContext context,
  PreferencesState state,
) {
  final l10n = AppLocalizations.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        l10n.prefRecordingDetail,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Text(
        l10n.prefRecordingDetailSubtitle,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      LabeledDropdown<RecordingDetailEntity>(
        value: state.preferences.recordingDetail,
        items: RecordingDetailEntity.values,
        labelFor: (d) => recordingDetailName(l10n, d),
        onChanged: (v) =>
            context.read<PreferencesBloc>().add(ChangeRecordingDetail(v)),
      ),
    ],
  );
}

String recordingDetailName(AppLocalizations l10n, RecordingDetailEntity d) =>
    switch (d) {
      RecordingDetailEntity.precise => l10n.prefDetailPrecise,
      RecordingDetailEntity.balanced => l10n.prefDetailBalanced,
      RecordingDetailEntity.endurance => l10n.prefDetailEndurance,
    };

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
