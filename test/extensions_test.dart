import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/extensions.dart';

void main() {
  group('NumFormatting.fmt2', () {
    test('two decimals for integers', () {
      expect(0.fmt2, '0.00');
      expect(42.fmt2, '42.00');
    });

    test('two decimals for fractions', () {
      expect(1.2345.fmt2, '1.23');
      expect(9.999.fmt2, '10.00');
    });
  });

  group('DurationExtension.toHHMMSS', () {
    test('renders sub-hour as MMmSSs', () {
      expect(const Duration(seconds: 5).toHHMMSS(), '00m05s');
      expect(const Duration(minutes: 12, seconds: 34).toHHMMSS(), '12m34s');
    });

    test('renders hour+ as HHhMMmSSs', () {
      expect(
        const Duration(hours: 1, minutes: 2, seconds: 3).toHHMMSS(),
        '01h02m03s',
      );
    });
  });
}
