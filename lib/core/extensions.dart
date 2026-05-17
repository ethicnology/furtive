import 'package:flutter/widgets.dart';

extension BuildContextLayout on BuildContext {
  /// Standard padding/spacing = 10% of screen width.
  /// Read at call site so values stay correct on rotation / hot reload.
  double get screenPadding => MediaQuery.sizeOf(this).width * 0.1;
}

extension NumFormatting on num {
  /// Standard 2-decimal display for distances, speeds and elevations.
  String get fmt2 => toStringAsFixed(2);
}

extension DurationExtension on Duration {
  String toHHMMSS() {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = inHours;
    final minutes = inMinutes.remainder(60);
    final seconds = inSeconds.remainder(60);

    if (hours > 0) {
      return '${twoDigits(hours)}h${twoDigits(minutes)}m${twoDigits(seconds)}s';
    } else {
      return '${twoDigits(minutes)}m${twoDigits(seconds)}s';
    }
  }
}
