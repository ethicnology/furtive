import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/check_version_service.dart';

void main() {
  group('stripLeadingV', () {
    test('strips a single leading v/V', () {
      expect(stripLeadingV('v1.2.0'), '1.2.0');
      expect(stripLeadingV('V1.2.0'), '1.2.0');
      expect(stripLeadingV('1.2.0'), '1.2.0');
    });

    test('leaves a non-leading v intact', () {
      expect(stripLeadingV('1.2.0-dev'), '1.2.0-dev');
      expect(stripLeadingV('1.2.0+rev'), '1.2.0+rev');
    });

    test('trims surrounding whitespace', () {
      expect(stripLeadingV('  v1.2.0  '), '1.2.0');
    });
  });

  group('isNewerVersion', () {
    test('detects strictly newer releases', () {
      expect(isNewerVersion('1.2.1', '1.2.0'), isTrue);
      expect(isNewerVersion('1.3.0', '1.2.9'), isTrue);
      expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(isNewerVersion('1.2.10', '1.2.9'), isTrue); // numeric, not lexical
    });

    test('equal or older is not newer', () {
      expect(isNewerVersion('1.2.0', '1.2.0'), isFalse);
      expect(isNewerVersion('1.2.0', '1.2.1'), isFalse);
      expect(isNewerVersion('1.2.0', '1.3.0'), isFalse);
    });

    test('missing trailing components count as 0', () {
      expect(isNewerVersion('1.2', '1.2.0'), isFalse);
      expect(isNewerVersion('1.2.0', '1.2'), isFalse);
      expect(isNewerVersion('1.2.1', '1.2'), isTrue);
    });

    test('ignores pre-release / build suffixes', () {
      expect(isNewerVersion('1.2.0+3', '1.2.0'), isFalse);
      expect(isNewerVersion('1.2.0-rc1', '1.2.0'), isFalse);
      expect(isNewerVersion('1.2.1-rc1', '1.2.0'), isTrue);
    });

    test('malformed input never reports newer', () {
      expect(isNewerVersion('garbage', '1.2.0'), isFalse);
    });
  });
}
