import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/utils/gpx.dart';
import 'package:xml/xml.dart';

XmlElement _root(String body) => XmlDocument.parse(body).rootElement;

void main() {
  group('parseGpxSegments', () {
    test('single trkseg => one group', () {
      final g = parseGpxSegments(
        _root('''
        <gpx><trk><trkseg>
          <trkpt lat="0" lon="0"/>
          <trkpt lat="0" lon="0.001"/>
        </trkseg></trk></gpx>
      '''),
      );
      expect(g.length, 1);
      expect(g.first.length, 2);
    });

    test('multiple trkseg => one group each (discontinuity preserved)', () {
      final g = parseGpxSegments(
        _root('''
        <gpx><trk>
          <trkseg><trkpt lat="0" lon="0"/><trkpt lat="0" lon="0.001"/></trkseg>
          <trkseg><trkpt lat="0" lon="1"/><trkpt lat="0" lon="1.001"/></trkseg>
        </trk></gpx>
      '''),
      );
      expect(g.length, 2);
    });

    test('multiple trk => one group each', () {
      final g = parseGpxSegments(
        _root('''
        <gpx>
          <trk><trkseg><trkpt lat="0" lon="0"/></trkseg></trk>
          <trk><trkseg><trkpt lat="1" lon="1"/></trkseg></trk>
        </gpx>
      '''),
      );
      expect(g.length, 2);
    });

    test('rte/rtept become a group', () {
      final g = parseGpxSegments(
        _root('''
        <gpx><rte>
          <rtept lat="0" lon="0"/>
          <rtept lat="0" lon="0.001"/>
        </rte></gpx>
      '''),
      );
      expect(g.length, 1);
      expect(g.first.length, 2);
    });

    test('empty / all-invalid segments are dropped', () {
      final g = parseGpxSegments(
        _root('''
        <gpx><trk>
          <trkseg><trkpt lat="99" lon="0"/></trkseg>
          <trkseg><trkpt lat="0" lon="0"/></trkseg>
        </trk></gpx>
      '''),
      );
      expect(g.length, 1);
      expect(g.first.length, 1);
    });

    test('fallback for stray trkpt outside any trkseg', () {
      final g = parseGpxSegments(
        _root('''
        <gpx>
          <trkpt lat="0" lon="0"/>
          <trkpt lat="0" lon="0.001"/>
        </gpx>
      '''),
      );
      expect(g.length, 1);
      expect(g.first.length, 2);
    });

    test('no points => empty', () {
      expect(parseGpxSegments(_root('<gpx></gpx>')), isEmpty);
    });

    test('<trk> with <trkpt> directly (no <trkseg> wrapper) is still collected '
        'even when ANOTHER <trk> in the same file does use <trkseg> — '
        'regression guard: previously only the fallback (which only fires '
        'when every group is empty) covered trkpt-outside-trkseg', () {
      final g = parseGpxSegments(
        _root('''
        <gpx>
          <trk><trkseg><trkpt lat="0" lon="0"/><trkpt lat="0" lon="0.001"/></trkseg></trk>
          <trk><trkpt lat="1" lon="1"/><trkpt lat="1" lon="1.001"/></trk>
        </gpx>
      '''),
      );
      expect(g.length, 2);
      expect(g[0].length, 2);
      expect(g[1].length, 2);
    });

    test('namespace-prefixed elements are matched by local name, not silently '
        'dropped', () {
      final g = parseGpxSegments(
        _root('''
        <x:gpx xmlns:x="http://www.topografix.com/GPX/1/1">
          <x:trk><x:trkseg>
            <x:trkpt lat="0" lon="0"><x:ele>10</x:ele></x:trkpt>
            <x:trkpt lat="0" lon="0.001"/>
          </x:trkseg></x:trk>
        </x:gpx>
      '''),
      );
      expect(g.length, 1);
      expect(g.first.length, 2);
      expect(g.first.first.elevation, 10);
    });
  });

  group('parseTrkpt time parsing', () {
    XmlElement trkpt(String body) => _root(
      '<gpx><trk><trkseg>$body</trkseg></trk></gpx>',
    ).findAllElements('trkpt').first;

    test('a "Z"-suffixed time is parsed as UTC unchanged', () {
      final p = parseTrkpt(
        trkpt(
          '<trkpt lat="0" lon="0"><time>2024-05-01T10:00:00Z</time></trkpt>',
        ),
      );
      expect(p!.time!.isUtc, isTrue);
      expect(p.time!.hour, 10);
    });

    test('an offset-less time (no "Z", no explicit offset) is treated as UTC, '
        'not the local timezone — per the GPX/xsd:dateTime default', () {
      final p = parseTrkpt(
        trkpt(
          '<trkpt lat="0" lon="0"><time>2024-05-01T10:00:00</time></trkpt>',
        ),
      );
      expect(p!.time!.isUtc, isTrue);
      expect(p.time!.hour, 10);
      expect(p.time!.year, 2024);
      expect(p.time!.month, 5);
      expect(p.time!.day, 1);
    });

    test('an explicit offset is honoured and converted correctly', () {
      final p = parseTrkpt(
        trkpt(
          '<trkpt lat="0" lon="0"><time>2024-05-01T10:00:00+02:00</time></trkpt>',
        ),
      );
      expect(p!.time!.isUtc, isTrue);
      expect(p.time!.hour, 8);
    });
  });
}
