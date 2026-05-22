import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/locale_cubit.dart';
import 'package:furtive/core/usecases/get_preferences_use_case.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';
import 'package:furtive/features/activities/bloc/activities_bloc.dart';
import 'package:furtive/features/permissions/presentation/bloc/permissions_bloc.dart';
import 'package:furtive/features/permissions/presentation/pages/check_permission_page.dart';
import 'package:furtive/l10n/app_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'core/locator.dart';
import 'core/logs.dart';
import 'core/theme.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Load intl date-format symbols for every locale we ship. Without this,
      // DateFormat.yMd('zh').format(...) throws LocaleDataException for any
      // non-en locale.
      await initializeDateFormatting();
      await Global.init();

      final appDir = await getApplicationDocumentsDirectory();
      logs = MyLogs.init(directory: appDir);
      await logs.ensureLogsExist();

      // Register DB + blocs. LocaleCubit is registered separately below
      // because its initial state requires a DB read first.
      Locator.setup();

      // Read the stored locale override so LocaleCubit is correct on frame 1.
      // On first launch the row doesn't exist yet (beforeOpen runs lazily on
      // first query), so fetch() may throw — fall back to system locale.
      Locale? storedLocale;
      try {
        final prefs = await GetPreferencesUseCase()();
        if (prefs.uiLocale != null) {
          storedLocale = parseLocaleTag(prefs.uiLocale!);
        }
      } catch (e, st) {
        logs.warning('Failed to read locale preference', error: e, trace: st);
      }
      getIt.registerSingleton<LocaleCubit>(LocaleCubit(storedLocale));

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
    return MultiBlocProvider(
      providers: [
        // .value because the locator owns the bloc lifetimes — BlocProvider
        // must not close them on widget disposal.
        BlocProvider<LocaleCubit>.value(value: getIt<LocaleCubit>()),
        BlocProvider<MapBloc>.value(value: getIt<MapBloc>()),
        BlocProvider<ActivitiesBloc>.value(value: getIt<ActivitiesBloc>()),
        BlocProvider<PermissionsBloc>.value(value: getIt<PermissionsBloc>()),
      ],
      child: BlocBuilder<LocaleCubit, Locale?>(
        builder: (context, locale) => MaterialApp(
          // onGenerateTitle ensures the title in the OS task switcher is
          // localised every time the locale changes.
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          theme: appTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: const CheckPermissionPage(),
        ),
      ),
    );
  }
}
