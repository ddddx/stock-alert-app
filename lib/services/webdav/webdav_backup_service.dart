import 'dart:convert';
import 'dart:io';

import '../../data/models/app_backup_payload.dart';

class WebDavCredentials {
  const WebDavCredentials({
    required this.endpoint,
    required this.username,
    required this.password,
  });

  final String endpoint;
  final String username;
  final String password;

  Uri get uri {
    final parsed = Uri.tryParse(endpoint.trim());
    if (parsed == null ||
        parsed.host.trim().isEmpty ||
        !(parsed.scheme == 'http' || parsed.scheme == 'https')) {
      throw const WebDavBackupException(
          'WebDAV 地址格式不正确，请输入完整的 http 或 https 地址。');
    }
    return parsed;
  }
}

class WebDavBackupException implements Exception {
  const WebDavBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WebDavBackupService {
  WebDavBackupService({HttpClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? HttpClient.new;

  static const int schemaVersion = 1;

  final HttpClient Function() _clientFactory;

  Future<void> exportPayload({
    required WebDavCredentials credentials,
    required AppBackupPayload payload,
  }) async {
    final response = await _sendRequest(
      method: 'PUT',
      credentials: credentials,
      body: const JsonEncoder.withIndent('  ').convert(payload.toJson()),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebDavBackupException(
        '导出失败（HTTP ${response.statusCode}）：${_normalizeSnippet(response.body)}',
      );
    }
  }

  Future<AppBackupPayload> importPayload({
    required WebDavCredentials credentials,
  }) async {
    final response =
        await _sendRequest(method: 'GET', credentials: credentials);
    final body = response.body;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebDavBackupException(
        '导入失败（HTTP ${response.statusCode}）：${_normalizeSnippet(body)}',
      );
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const WebDavBackupException('导入失败：远端文件不是合法的配置 JSON。');
    }

    final payload = AppBackupPayload.fromJson(decoded.cast<String, dynamic>());
    if (payload.schemaVersion != schemaVersion) {
      throw WebDavBackupException(
        '导入失败：备份版本 ${payload.schemaVersion} 与当前应用不兼容。',
      );
    }
    return payload;
  }

  Future<_WebDavResponse> _sendRequest({
    required String method,
    required WebDavCredentials credentials,
    String? body,
  }) async {
    final client = _clientFactory();
    try {
      client.userAgent = 'stock-alert-app-webdav';
      final request = await client.openUrl(method, credentials.uri);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode('${credentials.username}:${credentials.password}'))}',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        request.write(body);
      }
      final response = await request.close();
      return _WebDavResponse(
        statusCode: response.statusCode,
        body: await utf8.decoder.bind(response).join(),
      );
    } on SocketException catch (error) {
      throw WebDavBackupException('连接 WebDAV 失败：$error');
    } finally {
      client.close(force: true);
    }
  }

  String _normalizeSnippet(String body) {
    final normalized = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      return '服务器未返回更多说明。';
    }
    if (normalized.length <= 120) {
      return normalized;
    }
    return '${normalized.substring(0, 120)}...';
  }
}

class _WebDavResponse {
  const _WebDavResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}
