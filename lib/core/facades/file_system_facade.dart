import 'dart:typed_data';
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

      final XFile textFile = XFile.fromData(
        Uint8List.fromList(content.codeUnits),
        mimeType: mimeType,
        name: filename,
      );
      await textFile.saveTo(p.join(path, filename));
    } catch (e) {
      throw AppError('Failed to save file: $e');
    }
  }
}
