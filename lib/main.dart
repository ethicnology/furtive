import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';
import 'package:furtive/features/activities/bloc/activities_bloc.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_bloc.dart';
import 'package:furtive/features/permissions/presentation/pages/check_permission_page.dart';
import 'package:path_provider/path_provider.dart';
import 'core/locator.dart';
import 'core/logs.dart';
import 'core/theme.dart';

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await dotenv.load();
      await Global.init();

      final appDir = await getApplicationDocumentsDirectory();
      logs = MyLogs.init(directory: appDir);
      await logs.ensureLogsExist();

      Locator.setup();

      FlutterError.onError = (FlutterErrorDetails details) {
        logs.severe(
          'Flutter error',
          error: details.exception,
          trace: details.stack,
        );
      };

      runApp(const MyApp());
    },
    (error, stack) {
      logs.severe(error.toString(), error: error, trace: stack);
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    screen = MediaQuery.of(context).size; // initialize screen size

    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => getIt<MapBloc>()),
        BlocProvider(create: (context) => getIt<ActivitiesBloc>()),
        BlocProvider(create: (context) => getIt<PermissionsBloc>()),
      ],
      child: MaterialApp(
        title: 'Map App',
        theme: appTheme,
        home: const CheckPermissionPage(),
      ),
    );
  }
}
