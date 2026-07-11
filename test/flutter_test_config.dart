import 'dart:async';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// Flutter's test binding renders text with a placeholder "Ahem" font
/// (deterministic boxes instead of real glyphs) by default — fine for
/// widget assertions, but useless for visually reviewing a design via
/// golden-file screenshots. This loads the app's real bundled font once for
/// every test file in this directory (Flutter auto-discovers
/// flutter_test_config.dart), so golden PNGs show actual Space Grotesk
/// glyphs.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadFont('SpaceGrotesk', 'assets/fonts/SpaceGrotesk-Variable.ttf');
  await testMain();
}

Future<void> _loadFont(String family, String assetPath) async {
  final data = await rootBundle.load(assetPath);
  final loader = FontLoader(family)..addFont(Future.value(data));
  await loader.load();
}
