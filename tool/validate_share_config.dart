import 'dart:io';
import 'dart:typed_data';

import 'package:furtive_share/furtive_share.dart';

void main() {
  try {
    final viewerBase = (Platform.environment['SHARE_VIEWER_URL'] ?? '').trim();
    final configuredRelays = (Platform.environment['SHARE_RELAYS'] ?? '')
        .trim();
    final relayConfig = configuredRelays.isEmpty
        ? defaultShareRelayConfig
        : configuredRelays;
    final relays = relayConfig
        .split(',')
        .map((relay) => relay.trim())
        .where((relay) => relay.isNotEmpty)
        .toList(growable: false);
    final link = ShareLink(
      publisherPublicKey: ''.padLeft(64, '0'),
      shareSecret: Uint8List(32),
      relays: relays,
    ).toUri(viewerBase);
    if (Uri.parse(link).scheme != 'https') {
      throw ArgumentError('release viewer must use HTTPS');
    }
    stdout.writeln('Live-share release configuration is valid.');
  } on Object catch (error) {
    final detail = error is ArgumentError
        ? error.message
        : error.runtimeType.toString();
    stderr.writeln('Invalid live-share release configuration: $detail');
    exitCode = 64;
  }
}
