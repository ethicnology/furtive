import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

export 'extensions.dart';
export 'errors.dart';

Size screen = Size(0, 0);

class Global {
  static const maxZoom = 18.0;
  static const defaultZoom = 12.0;

  static final padding = screen.width * 0.1;
  static final spacing = screen.width * 0.1;
  static late PackageInfo infos;

  static Future<void> init() async {
    infos = await PackageInfo.fromPlatform();
  }
}
