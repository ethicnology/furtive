import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/entities/preferences_entity.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/widgets/labeled_dropdown.dart';
import 'package:furtive/features/preferences/bloc/preferences_bloc.dart';
import 'package:furtive/features/preferences/bloc/preferences_event.dart';
import 'package:furtive/features/preferences/bloc/preferences_state.dart';

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
            appBar: AppBar(title: const Text('Preferences')),
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
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: EdgeInsets.all(context.screenPadding),
                        child: ElevatedButton(
                          onPressed: () {
                            context.read<PreferencesBloc>().add(
                              UpdatePreferences(
                                PreferencesEntity(
                                  mapTheme: state.preferences.mapTheme,
                                  mapLanguage: state.preferences.mapLanguage,
                                  accuracyInMeters:
                                      state.preferences.accuracyInMeters,
                                ),
                              ),
                            );
                            Navigator.of(context).pop();
                          },
                          child: const Text('Apply'),
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
      const Text(
        'Map Theme',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
      const Text(
        'Map Language',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
