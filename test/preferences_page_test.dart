import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/datasources/preferences_local_data_source.dart';
import 'package:furtive/core/entities/preferences_entity.dart';
import 'package:furtive/core/locale_cubit.dart';
import 'package:furtive/core/locator.dart';
import 'package:furtive/core/repositories/preferences_repository.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/features/preferences/page.dart';
import 'package:furtive/l10n/app_localizations.dart';

import 'support/fakes.dart';

/// Widget coverage for the Apply flow.
///
/// The failed-save case is the reason this file exists: the page used to
/// dispatch Apply and pop in the same frame, so by the time the write settled
/// there was no UI left. A failure was logged and swallowed while the user
/// believed their settings were stored. These tests pin the corrected
/// behaviour — pop only on success, report on failure — so it cannot regress.
class _FailingPreferencesRepository extends PreferencesRepository {
  _FailingPreferencesRepository(LocalDatabase db)
    : super(local: PreferencesLocalDataSource(db: db));

  @override
  Future<void> store(PreferencesEntity preferences) async {
    throw StateError('disk full');
  }
}

/// The page is pumped with the default (English) localisations, so labels can
/// be looked up directly instead of hardcoding display strings in the test.
final enLocalizations = lookupAppLocalizations(const Locale('en'));

void main() {
  late LocalDatabase db;

  setUp(() {
    db = inMemoryDatabase();
    if (getIt.isRegistered<LocaleCubit>()) getIt.unregister<LocaleCubit>();
    getIt.registerSingleton<LocaleCubit>(LocaleCubit(null));
  });

  tearDown(() async {
    await db.close();
    await getIt.reset();
  });

  Future<void> pumpPage(WidgetTester tester, PreferencesRepository repo) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // A route below the page so a successful Apply has somewhere to pop to.
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PreferencesPage(repository: repo),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Apply sits at the bottom of a now-scrollable page, so it may be below the
  /// fold in the default 800x600 test viewport — exactly the situation that used
  /// to overflow the Column and make the button unreachable.
  Future<void> tapApply(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
  }

  testWidgets('a successful Apply persists and pops', (tester) async {
    final repo = PreferencesRepository(
      local: PreferencesLocalDataSource(db: db),
    );
    await pumpPage(tester, repo);

    expect(find.byType(PreferencesPage), findsOneWidget);

    // The lock-screen switch specifically. Every other control on this page
    // (map theme, map tiles) makes PreferencesBloc reach into the service
    // locator for MapBloc to re-init the map, which would turn a preferences
    // test into a test that has to stand up the GPS stack. This toggle only
    // calls LockScreenFacade, which is a no-op off Android.
    //
    // Located by its label rather than by position: this used to be "the last
    // switch", which silently started pointing at a different setting the
    // moment one was added below it.
    final lockScreen = find.ancestor(
      of: find.text(enLocalizations.prefShowOnLockScreen),
      matching: find.byType(SwitchListTile),
    );
    await tester.ensureVisible(lockScreen);
    await tester.pumpAndSettle();
    await tester.tap(lockScreen);
    await tester.pumpAndSettle();
    await tapApply(tester);
    await tester.pumpAndSettle();

    expect(
      find.byType(PreferencesPage),
      findsNothing,
      reason: 'the page pops once the write has actually landed',
    );
    expect((await repo.fetch()).showOnLockScreen, isFalse);
  });

  testWidgets(
    'a failed Apply keeps the page open and reports the failure instead of '
    'silently pretending the settings were saved',
    (tester) async {
      await pumpPage(tester, _FailingPreferencesRepository(db));

      await tapApply(tester);
      await tester.pumpAndSettle();

      expect(
        find.byType(PreferencesPage),
        findsOneWidget,
        reason: 'popping here is what used to hide the failure',
      );
      expect(find.byType(SnackBar), findsOneWidget);
    },
  );

  testWidgets('Apply is disabled while the write is in flight', (tester) async {
    final repo = _SlowPreferencesRepository(db);
    await pumpPage(tester, repo);

    await tapApply(tester);
    await tester.pump(); // let isSaving land, but not the write

    final button = tester.widget<ElevatedButton>(
      find.byType(ElevatedButton).last,
    );
    expect(button.onPressed, isNull, reason: 'no double-dispatch of Apply');
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    repo.complete();
    await tester.pumpAndSettle();
  });
}

/// Storage whose write only completes when the test says so, so the in-flight
/// UI state is observable.
class _SlowPreferencesRepository extends PreferencesRepository {
  _SlowPreferencesRepository(LocalDatabase db)
    : super(local: PreferencesLocalDataSource(db: db));

  final _gate = Completer<void>();

  void complete() => _gate.complete();

  @override
  Future<void> store(PreferencesEntity preferences) async {
    await _gate.future;
  }
}
