import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/datasources/activity_local_data_source.dart';
import 'package:furtive/core/repositories/activity_repository.dart';
import 'package:furtive/core/usecases/import_activity_from_gpx_use_case.dart';
import 'package:xml/xml.dart';

import 'support/fakes.dart';

/// Pins the XML safety properties GPX import relies on.
///
/// These were previously only asserted in a code comment — and asserted wrongly:
/// the comment claimed package:xml expands DTD entities and that a file-size cap
/// mitigated billion-laughs. Neither is true. Since import parses attacker-
/// supplied files (a GPX can come from anywhere), the properties are worth
/// verifying rather than believing, and worth failing loudly on if a future
/// package:xml release starts resolving entities.
void main() {
  group('package:xml does not expand DTD entities', () {
    test('a billion-laughs payload does not expand', () {
      const payload = '''<?xml version="1.0"?>
<!DOCTYPE gpx [
 <!ENTITY a "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">
 <!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">
 <!ENTITY c "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">
 <!ENTITY d "&c;&c;&c;&c;&c;&c;&c;&c;&c;&c;">
]>
<gpx><trk><name>&d;</name></trk></gpx>''';

      final name = XmlDocument.parse(
        payload,
      ).findAllElements('name').first.innerText;

      // Left as the literal reference, not expanded to 40_000 characters.
      expect(name, '&d;');
    });

    test('an external entity is not resolved (no XXE file disclosure)', () {
      const payload = '''<?xml version="1.0"?>
<!DOCTYPE gpx [ <!ENTITY xxe SYSTEM "file:///etc/passwd"> ]>
<gpx><trk><name>&xxe;</name></trk></gpx>''';

      final name = XmlDocument.parse(
        payload,
      ).findAllElements('name').first.innerText;

      expect(name, '&xxe;');
      expect(name, isNot(contains('root:')));
    });
  });

  group('import rejects hostile input on its own terms', () {
    late Directory tmp;
    late LocalDatabase db;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('gpx_safety');
      db = inMemoryDatabase();
    });
    tearDown(() async {
      tmp.deleteSync(recursive: true);
      await db.close();
    });

    ImportActivityFromGpxUseCase importer() => ImportActivityFromGpxUseCase(
      activities: ActivityRepository(local: ActivityLocalDataSource(db: db)),
    );

    File write(String name, String content) =>
        File('${tmp.path}/$name')..writeAsStringSync(content);

    test('an oversized file is refused before it is read into memory', () async {
      // One byte over the cap; the check is on file length, so the content need
      // not be valid GPX.
      final big = write('big.gpx', 'x' * (10 * 1024 * 1024 + 1));
      await expectLater(
        importer().call(big),
        throwsA(
          isA<GpxParseError>().having(
            (e) => e.message,
            'message',
            contains('too large'),
          ),
        ),
      );
    });

    test('a non-gpx root element is refused', () async {
      final f = write('wrong.gpx', '<?xml version="1.0"?><kml></kml>');
      await expectLater(importer().call(f), throwsA(isA<GpxParseError>()));
    });

    test('malformed XML is refused', () async {
      final f = write('broken.gpx', '<gpx><trk>');
      await expectLater(importer().call(f), throwsA(isA<GpxParseError>()));
    });

    test('a well-formed GPX with no usable points is refused', () async {
      final f = write(
        'empty.gpx',
        '<?xml version="1.0"?><gpx><trk><trkseg></trkseg></trk></gpx>',
      );
      await expectLater(importer().call(f), throwsA(isA<GpxNoPointsError>()));
    });
  });
}
