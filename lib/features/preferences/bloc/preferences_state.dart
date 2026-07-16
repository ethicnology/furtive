import 'package:dart_mappable/dart_mappable.dart';
import 'package:furtive/core/entities/preferences_entity.dart';
import 'package:furtive/core/errors.dart';

part 'preferences_state.mapper.dart';

@MappableClass()
class PreferencesState with PreferencesStateMappable {
  final PreferencesEntity preferences;
  final bool isLoading;
  final AppError? error;

  /// The preferences as last read from / written to storage — NOT updated by
  /// the live Change* events, only by _onLoadPreferences and a successful
  /// _onUpdatePreferences. This is what "did theme/tiles/lock-screen actually
  /// change" must diff against; diffing against `preferences` (which the
  /// Change* handlers already mutate as the user edits the form) always
  /// yields "unchanged" and silently skipped every live side effect (map
  /// re-init, lock-screen toggle) until the next app restart. See
  /// docs/REVIEW-2026-07-FULL-APP.md C1.
  final PreferencesEntity persisted;

  const PreferencesState({
    required this.preferences,
    required this.persisted,
    this.isLoading = false,
    this.error,
  });
}
