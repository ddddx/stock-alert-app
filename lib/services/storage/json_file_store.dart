import 'dart:convert';
import 'dart:io';

class JsonFileStore {
  JsonFileStore({required this.fileName});

  final String fileName;
  File? _file;

  Future<void> initialize(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _file = File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  Future<Map<String, dynamic>?> readObject() async {
    final file = _requireFile();
    if (!await file.exists()) {
      return null;
    }

    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return null;
  }

  Future<List<dynamic>?> readList() async {
    final file = _requireFile();
    if (!await file.exists()) {
      return null;
    }

    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(content);
    if (decoded is List<dynamic>) {
      return decoded;
    }
    return null;
  }

  Future<void> writeJson(Object data) async {
    final file = _requireFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
  }

  File _requireFile() {
    final file = _file;
    if (file == null) {
      throw StateError('JsonFileStore not initialized: $fileName');
    }
    return file;
  }
}
