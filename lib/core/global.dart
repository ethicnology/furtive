import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

export 'extensions.dart';
export 'errors.dart';

class Global {
  static const maxZoom = 18.0;
  static const defaultZoom = 12.0;

  static late PackageInfo app;
  static AndroidDeviceInfo? android;
  static IosDeviceInfo? ios;

  /// Attached to MaterialApp so code with no BuildContext of its own (or
  /// whose context is likely to have been unmounted by the time an async
  /// operation settles — e.g. checkNewVersion's HTTP call outliving
  /// CheckPermissionPage's pushReplacement) can still show a SnackBar. See
  /// M4 in REVIEW-2026-07-FULL-APP.md.
  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  static Future<void> init() async {
    app = await PackageInfo.fromPlatform();
    if (Platform.isAndroid) {
      android = await DeviceInfoPlugin().androidInfo;
    } else if (Platform.isIOS) {
      ios = await DeviceInfoPlugin().iosInfo;
    }
  }
}
