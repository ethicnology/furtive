import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/utils/gpx.dart';
import 'package:xml/xml.dart';

XmlElement _trkpt(String body) =>
    XmlDocument.parse('<trkpt $body/>').rootElement;

void main() {
  group('parseTrkpt - coordinate validation', () {
    test('parses a well-formed trkpt with ele + time', () {
      final el = XmlDocument.parse('''
        <trkpt lat="48.8566" lon="2.3522">
          <ele>35.0</ele>
          <time>2026-05-21T14:30:00Z</time>
        </trkpt>
      ''').rootElement;
      final p = parseTrkpt(el);
      expect(p, isNotNull);
      expect(p!.latitude, 48.8566);
      expect(p.longitude, 2.3522);
      expect(p.elevation, 35.0);
      expect(p.time, DateTime.utc(2026, 5, 21, 14, 30));
    });

    test('rejects missing lat/lon attributes', () {
      expect(parseTrkpt(_trkpt('lon="2.0"')), isNull);
      expect(parseTrkpt(_trkpt('lat="48.0"')), isNull);
    });

    test('rejects garbage in lat/lon', () {
      expect(parseTrkpt(_trkpt('lat="oops" lon="2.0"')), isNull);
      expect(parseTrkpt(_trkpt('lat="48.0" lon="not-a-number"')), isNull);
    });

    test('rejects non-finite values', () {
      expect(parseTrkpt(_trkpt('lat="NaN" lon="2.0"')), isNull);
      expect(parseTrkpt(_trkpt('lat="48.0" lon="Infinity"')), isNull);
    });

    test('rejects out-of-range coordinates', () {
      expect(parseTrkpt(_trkpt('lat="91" lon="0"')), isNull);
      expect(parseTrkpt(_trkpt('lat="-91" lon="0"')), isNull);
      expect(parseTrkpt(_trkpt('lat="0" lon="181"')), isNull);
      expect(parseTrkpt(_trkpt('lat="0" lon="-181"')), isNull);
    });

    test('accepts coordinates exactly at the WGS84 boundary', () {
      expect(parseTrkpt(_trkpt('lat="90" lon="180"')), isNotNull);
      expect(parseTrkpt(_trkpt('lat="-90" lon="-180"')), isNotNull);
    });

    test('defaults elevation to 0 when <ele> is missing', () {
      final p = parseTrkpt(_trkpt('lat="0" lon="0"'));
      expect(p, isNotNull);
      expect(p!.elevation, 0.0);
    });

    test('coerces non-finite elevation to 0', () {
      final el = XmlDocument.parse('''
        <trkpt lat="0" lon="0"><ele>NaN</ele></trkpt>
      ''').rootElement;
      final p = parseTrkpt(el);
      expect(p, isNotNull);
      expect(p!.elevation, 0.0);
    });

    test('time is null when missing or unparseable', () {
      expect(parseTrkpt(_trkpt('lat="0" lon="0"'))!.time, isNull);
      final el = XmlDocument.parse('''
        <trkpt lat="0" lon="0"><time>not-a-date</time></trkpt>
      ''').rootElement;
      expect(parseTrkpt(el)!.time, isNull);
    });
  });
}
