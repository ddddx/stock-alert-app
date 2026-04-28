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
    final decoded = await _readDecodedWithRecovery(file);
    if (decoded == null) {
      return null;
    }

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
    final decoded = await _readDecodedWithRecovery(file);
    if (decoded == null) {
      return null;
    }
    if (decoded is List<dynamic>) {
      return decoded;
    }
    return null;
  }

  Future<void> writeJson(Object data) async {
    final file = _requireFile();
    final content = const JsonEncoder.withIndent('  ').convert(data);
    final tempFile = File('${file.path}.tmp');
    await tempFile.writeAsString(content, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
    await _saveBackup(file);
  }

  File _requireFile() {
    final file = _file;
    if (file == null) {
      throw StateError('JsonFileStore not initialized: $fileName');
    }
    return file;
  }

  Future<dynamic> _readDecodedWithRecovery(File file) async {
    final decoded = await _tryReadDecoded(file);
    if (decoded != _decodeFailureSentinel) {
      return decoded;
    }

    final restored = await _restoreFromBackup(file);
    if (!restored) {
      return null;
    }
    final recovered = await _tryReadDecoded(file);
    if (recovered == _decodeFailureSentinel) {
      return null;
    }
    return recovered;
  }

  Future<dynamic> _tryReadDecoded(File file) async {
    if (!await file.exists()) {
      return null;
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return null;
    }
    try {
      return jsonDecode(content);
    } on FormatException {
      return _decodeFailureSentinel;
    }
  }

  Future<bool> _restoreFromBackup(File file) async {
    final backupFile = File('${file.path}.bak');
    if (!await backupFile.exists()) {
      return false;
    }
    if (await file.exists()) {
      await file.delete();
    }
    await backupFile.copy(file.path);
    return true;
  }

  Future<void> _saveBackup(File sourceFile) async {
    final backupFile = File('${sourceFile.path}.bak');
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    await sourceFile.copy(backupFile.path);
  }
}

const Object _decodeFailureSentinel = Object();
