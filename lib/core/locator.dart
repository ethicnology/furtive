import 'package:get_it/get_it.dart';
import 'package:furtive/features/activities/bloc/activities_bloc.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_bloc.dart';
import 'package:furtive/core/database/local_database.dart';

final getIt = GetIt.instance;

class Locator {
  static void setup() {
    // Database is a real singleton — one connection per app lifetime
    getIt.registerLazySingleton<LocalDatabase>(() => LocalDatabase());

    // BLoCs are lazy singletons so cross-bloc dispatch (e.g. PreferencesBloc
    // re-initing the MapBloc on theme change) reaches the live instance.
    getIt.registerLazySingleton<MapBloc>(() => MapBloc());
    getIt.registerLazySingleton<ActivitiesBloc>(() => ActivitiesBloc());
    getIt.registerLazySingleton<PermissionsBloc>(() => PermissionsBloc());
  }
}
