import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/utils/gpx.dart';
import 'package:xml/xml.dart';

XmlElement _root(String body) => XmlDocument.parse(body).rootElement;

void main() {
  group('parseGpxSegments', () {
    test('single trkseg => one group', () {
      final g = parseGpxSegments(_root('''
        <gpx><trk><trkseg>
          <trkpt lat="0" lon="0"/>
          <trkpt lat="0" lon="0.001"/>
        </trkseg></trk></gpx>
      '''));
      expect(g.length, 1);
      expect(g.first.length, 2);
    });

    test('multiple trkseg => one group each (discontinuity preserved)', () {
      final g = parseGpxSegments(_root('''
        <gpx><trk>
          <trkseg><trkpt lat="0" lon="0"/><trkpt lat="0" lon="0.001"/></trkseg>
          <trkseg><trkpt lat="0" lon="1"/><trkpt lat="0" lon="1.001"/></trkseg>
        </trk></gpx>
      '''));
      expect(g.length, 2);
    });

    test('multiple trk => one group each', () {
      final g = parseGpxSegments(_root('''
        <gpx>
          <trk><trkseg><trkpt lat="0" lon="0"/></trkseg></trk>
          <trk><trkseg><trkpt lat="1" lon="1"/></trkseg></trk>
        </gpx>
      '''));
      expect(g.length, 2);
    });

    test('rte/rtept become a group', () {
      final g = parseGpxSegments(_root('''
        <gpx><rte>
          <rtept lat="0" lon="0"/>
          <rtept lat="0" lon="0.001"/>
        </rte></gpx>
      '''));
      expect(g.length, 1);
      expect(g.first.length, 2);
    });

    test('empty / all-invalid segments are dropped', () {
      final g = parseGpxSegments(_root('''
        <gpx><trk>
          <trkseg><trkpt lat="99" lon="0"/></trkseg>
          <trkseg><trkpt lat="0" lon="0"/></trkseg>
        </trk></gpx>
      '''));
      expect(g.length, 1);
      expect(g.first.length, 1);
    });

    test('fallback for stray trkpt outside any trkseg', () {
      final g = parseGpxSegments(_root('''
        <gpx>
          <trkpt lat="0" lon="0"/>
          <trkpt lat="0" lon="0.001"/>
        </gpx>
      '''));
      expect(g.length, 1);
      expect(g.first.length, 2);
    });

    test('no points => empty', () {
      expect(parseGpxSegments(_root('<gpx></gpx>')), isEmpty);
    });
  });
}
