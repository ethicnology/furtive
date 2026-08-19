import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/facades/file_system_facade.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Coverage for the temp-file purge — the privacy-relevant half of this facade.
///
/// Exports and share cards are written to the OS temp directory and carry the
/// user's location: a GPX holds every coordinate, a share-card PNG draws the
/// whole route. They are deliberately NOT deleted straight after sharing,
/// because on iOS the share sheet reads the file asynchronously and an eager
/// delete races that read. The guarantee is instead that the window is bounded:
/// purgeStaleTempFiles() runs at startup, so a one-off sharer's file survives
/// only until the next launch rather than indefinitely.
///
/// That guarantee had no test. The share-sheet and directory-picker paths remain
/// untested here — they are gated on Platform.isAndroid/isIOS and driven by
/// SharePlus/file_selector platform channels, which would need mocking each in
/// turn for little beyond confirming a delegation.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.tempPath);

  final String tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('furtive_purge');
    PathProviderPlatform.instance = _FakePathProvider(temp.path);
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  File write(String name) =>
      File('${temp.path}/$name')..writeAsStringSync('<gpx>48.85,2.35</gpx>');

  Set<String> remaining() => temp
      .listSync()
      .map((e) => e.uri.pathSegments.last)
      .where((n) => n.isNotEmpty)
      .toSet();

  test('a leftover GPX export is purged', () async {
    write('furtive-export-activity.gpx');
    await FileSystemFacade.purgeStaleTempFiles();
    expect(remaining(), isEmpty);
  });

  test('a leftover share-card PNG is purged', () async {
    write('furtive-share-1753524000000.png');
    await FileSystemFacade.purgeStaleTempFiles();
    expect(remaining(), isEmpty);
  });

  test('both prefixes are purged in one pass', () async {
    write('furtive-export-a.gpx');
    write('furtive-share-b.png');
    await FileSystemFacade.purgeStaleTempFiles();
    expect(remaining(), isEmpty);
  });

  test(
    'unrelated files in the shared temp directory are left alone — this runs on '
    'a directory the whole app and its plugins use',
    () async {
      write('some-other-plugin-cache.bin');
      write('furtive_unrelated_name.txt');
      write('furtive-export-mine.gpx');
      await FileSystemFacade.purgeStaleTempFiles();
      expect(remaining(), {
        'some-other-plugin-cache.bin',
        'furtive_unrelated_name.txt',
      });
    },
  );

  test('directories are never deleted, even with a matching name', () async {
    Directory('${temp.path}/furtive-export-dir').createSync();
    await FileSystemFacade.purgeStaleTempFiles();
    expect(
      Directory('${temp.path}/furtive-export-dir').existsSync(),
      isTrue,
      reason: 'the purge is scoped to files',
    );
  });

  test('an empty temp directory is a no-op', () async {
    await FileSystemFacade.purgeStaleTempFiles();
    expect(remaining(), isEmpty);
  });

  test(
    'a missing temp directory never throws — the purge is best-effort and runs '
    'during startup, where an exception would be fatal',
    () async {
      temp.deleteSync(recursive: true);
      await expectLater(FileSystemFacade.purgeStaleTempFiles(), completes);
    },
  );

  test('a failing path provider never throws', () async {
    PathProviderPlatform.instance = _ThrowingPathProvider();
    await expectLater(FileSystemFacade.purgeStaleTempFiles(), completes);
  });
}

class _ThrowingPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async =>
      throw StateError('no temp directory');
}
