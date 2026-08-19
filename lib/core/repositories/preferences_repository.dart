import 'package:furtive/core/datasources/preferences_local_data_source.dart';
import 'package:furtive/core/models/preferences_model.dart';
import 'package:furtive/core/entities/preferences_entity.dart';

/// Entity-level access to the single preferences row.
///
/// GetPreferencesUseCase / UpdatePreferencesUseCase used to wrap [fetch] and
/// [store] one-for-one; they were aliases and are gone. Callers use this
/// directly.
class PreferencesRepository {
  /// [local] defaults to the real datasource so production call sites stay
  /// `PreferencesRepository()`; tests inject a fake.
  PreferencesRepository({PreferencesLocalDataSource? local})
    : local = local ?? PreferencesLocalDataSource();

  final PreferencesLocalDataSource local;

  Future<void> store(PreferencesEntity preferences) async {
    await local.store(PreferencesModel.fromEntity(preferences));
  }

  Future<PreferencesEntity> fetch() async {
    return PreferencesModel.toEntity(await local.fetch());
  }
}
