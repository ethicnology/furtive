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

  /// True while an Apply is being written to storage. The page keeps itself
  /// mounted (and its Apply button disabled) until this clears, so a failed
  /// write can actually be reported — see [saveCompleted].
  final bool isSaving;

  /// Set once an Apply has finished. `true` = persisted, the page may pop;
  /// `false` = the write threw and [error] carries the reason, so the page must
  /// stay put and surface it. Null before any Apply.
  ///
  /// Exists because the page used to dispatch Apply and pop in the same frame:
  /// by the time the DB write settled there was no UI left, so a failed save was
  /// logged and silently swallowed while the user believed their settings were
  /// stored.
  final bool? saveCompleted;

  const PreferencesState({
    required this.preferences,
    required this.persisted,
    this.isLoading = false,
    this.error,
    this.isSaving = false,
    this.saveCompleted,
  });
}
