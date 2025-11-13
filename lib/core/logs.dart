import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:furtive/core/global.dart';
import 'package:logging_colorful/logging_colorful.dart' as dep;
export 'package:logging_colorful/logging_colorful.dart';

MyLogs logs = MyLogs.init();

class MyLogs {
  final Directory dir;
  final dep.LoggerColorful logger;
  static const _logFilename = 'logs.tsv';
  File get logsFile => File('${dir.path}/$_logFilename');

  Future<void>? _currentWrite;

  MyLogs._(this.dir, this.logger) {
    dep.Logger.root.level = dep.Level.ALL;

    dep.Logger.root.onRecord.listen((record) {
      final time = record.time.toIso8601String();
      final content = [time, record.level.name, record.message];

      final (:String error, :String trace) = record.stringifyErrorAndTrace();
      content.addAll([error, trace]);

      final sanitizedContent = content.map((e) => logger.sanitize(e)).toList();
      final tsvLine = sanitizedContent.join('\t');

      if (record.level != dep.Level.INFO) _queueWrite(tsvLine);

      if (kDebugMode) {
        final debug = content.sublist(1, 3);
        debugPrint(debug.join('\t'));
      }
    });
  }

  void _queueWrite(String log) {
    final write = () async {
      await _currentWrite;
      await logsFile.writeAsString('$log\n', mode: FileMode.append);
    }();

    _currentWrite = write;
  }

  MyLogs.init({String name = 'MyLogs', Directory? directory})
    : this._(
        directory ?? Directory.current,
        // iOS emulator doesn't support colors –> https://github.com/flutter/flutter/issues/20663
        // We don't want colors in release mode either
        dep.LoggerColorful(
          name,
          disabledColors: Platform.isIOS || kReleaseMode,
        ),
      );

  Future<void> ensureLogsExist() async {
    try {
      if (await logsFile.exists()) return;

      await logsFile.create(recursive: true);
      fine('Logs created');
      addContextInfos();
    } catch (e) {
      severe('Logs existence: $e');
    }
  }

  void addContextInfos() {
    config('Version: ${Global.app.version}+${Global.app.buildNumber}');
    config('Signature: ${Global.app.buildSignature}');
    if (Platform.isAndroid) {
      final android = Global.android!;
      config('Manufacturer: ${android.manufacturer}');
      config('Brand: ${android.brand}');
      config('Model: ${android.model}');
      config('Device: ${android.device}');
      config('Android: ${android.version.release}');
      config('Sdk: ${android.version.sdkInt}');
    } else if (Platform.isIOS) {
      final ios = Global.ios!;
      config('Model: ${ios.model}');
      config('Model Name: ${ios.modelName}');
      config('Name: ${ios.name}');
      config('System Name: ${ios.systemName}');
      config('System Version: ${ios.systemVersion}');
      config('UTS Version: ${ios.utsname.version}');
      config('UTS Release: ${ios.utsname.release}');
      config('UTS Machine: ${ios.utsname.machine}');
      config('iOS App on Mac: ${ios.isiOSAppOnMac}');
    }
  }

  Future<List<String>> readLogs() async {
    try {
      final logs = await logsFile.readAsString();
      return logs.split('\n').where((e) => e.isNotEmpty).toList();
    } catch (e) {
      severe('Failed to read logs: $e');
      rethrow;
    }
  }

  /// Logs information messages that are part of the normal operation of the app.
  /// These messages are typically written to file only and not kept in memory.
  /// Use for recording general app flow and user actions.
  void info(Object? message, {Object? error, StackTrace? trace}) {
    logger.info(message, error, trace);
  }

  /// Logs static configuration information at startup or during major configuration changes.
  /// Use for logging app settings, environment details, or significant state changes.
  void config(Object? message, {Object? error, StackTrace? trace}) {
    logger.config(message, error, trace);
  }

  /// Logs basic tracing information for debugging.
  /// Use for high-level flow tracking during development and troubleshooting.
  void fine(Object? message, {Object? error, StackTrace? trace}) {
    logger.fine(message, error, trace);
  }

  /// Logs detailed tracing information.
  /// Use for more granular debugging information than fine(), such as loop iterations or method entry/exit.
  void finer(Object? message, {Object? error, StackTrace? trace}) {
    logger.finer(message, error, trace);
  }

  /// Logs highly detailed tracing information.
  /// Use for the most detailed level of debugging, such as variable values within loops.
  void finest(Object? message, {Object? error, StackTrace? trace}) {
    logger.finest(message, error, trace);
  }

  /// Logs potentially harmful situations that don't prevent the app from working.
  /// Use for recoverable errors or unexpected but handled conditions.
  void warning(Object? message, {Object? error, StackTrace? trace}) {
    logger.warning(message, error, trace);
  }

  /// Logs serious errors that may prevent parts of the app from working correctly.
  /// Use for unrecoverable errors that require immediate attention.
  void severe(Object? message, {Object? error, StackTrace? trace}) {
    logger.severe(message, error, trace);
  }

  /// Logs critical errors that could crash the app or make it unusable.
  /// Use for the most severe errors that require immediate intervention.
  void shout(Object? message, {Object? error, StackTrace? trace}) {
    logger.shout(message, error, trace);
  }

  Future<void> deleteLogs() async {
    await logsFile.writeAsString('');
    logs.shout('Logs deleted');
    addContextInfos();
  }
}
