import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:furtive/core/errors.dart';
import 'package:path/path.dart' as p;

class FileSystemFacade {
  static Future<void> save({
    required String content,
    required String filename,
    String? mimeType,
  }) async {
    try {
      final path = await getDirectoryPath();
      if (path == null) throw AppError('Location not selected by the user');

      // utf8.encode — NOT content.codeUnits. codeUnits yields UTF-16 units
      // truncated to bytes, mangling any char above U+00FF (accented activity
      // names, Cyrillic, CJK, emoji) in the exported GPX.
      final XFile textFile = XFile.fromData(
        utf8.encode(content),
        mimeType: mimeType,
        name: filename,
      );
      await textFile.saveTo(p.join(path, filename));
    } catch (e) {
      throw AppError('Failed to save file: $e');
    }
  }
}
