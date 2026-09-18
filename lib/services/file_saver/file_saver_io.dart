import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<bool> saveFileToDisk(String fileName, Uint8List? bytes) async {
  if (bytes == null || bytes.isEmpty) return false;
  try {
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save $fileName',
      fileName: fileName,
      bytes: bytes,
    );
    return savePath != null;
  } catch (_) {
    return false;
  }
}
