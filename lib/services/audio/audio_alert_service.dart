import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

abstract class AudioAlertService {
  Future<bool> preload();
  Future<bool> speak(String text);
  String? get lastErrorMessage;
}

class FlutterTtsAudioAlertService implements AudioAlertService {
  FlutterTtsAudioAlertService({FlutterTts? flutterTts})
      : _flutterTts = flutterTts ?? FlutterTts();

  final FlutterTts _flutterTts;
  bool _preloaded = false;
  bool _voiceConfigured = false;
  String? _lastErrorMessage;

  @override
  String? get lastErrorMessage => _lastErrorMessage;

  bool _isSuccessfulResult(dynamic result) {
    return result == null || result == true || result == 1;
  }

  void _clearError() {
    _lastErrorMessage = null;
  }

  void _setError(String message) {
    _lastErrorMessage = message;
  }

  @override
  Future<bool> preload() async {
    if (_preloaded) {
      _clearError();
      return true;
    }

    try {
      final result = await _flutterTts.awaitSpeakCompletion(true);
      final ready = _isSuccessfulResult(result);
      if (!ready) {
        _setError('语音插件初始化失败。');
        return false;
      }
      await _configurePreferredVoice();
      _preloaded = true;
      _clearError();
      return true;
    } on MissingPluginException {
      _setError('语音插件未注册，当前设备无法启用试播。');
      return false;
    } on PlatformException catch (error) {
      _setError(_describePlatformException(error));
      return false;
    } catch (_) {
      _setError('语音插件初始化失败。');
      return false;
    }
  }

  Future<void> _configurePreferredVoice() async {
    if (_voiceConfigured) {
      return;
    }
    try {
      await _flutterTts.setLanguage('zh-CN');
      await _flutterTts.setSpeechRate(1.0);
      await _flutterTts.setPitch(1.0);
      final selectedVoice =
          _selectPreferredChineseVoice(await _flutterTts.getVoices);
      if (selectedVoice != null) {
        await _flutterTts.setVoice(selectedVoice);
      }
      _voiceConfigured = true;
    } catch (_) {
      // Keep default engine voice when explicit selection is unavailable.
      _voiceConfigured = true;
    }
  }

  Map<String, String>? _selectPreferredChineseVoice(dynamic rawVoices) {
    if (rawVoices is! Iterable) {
      return null;
    }

    var bestScore = -1 << 30;
    Map<String, String>? bestVoice;
    for (final item in rawVoices) {
      if (item is! Map) {
        continue;
      }
      final map = item.cast<dynamic, dynamic>();
      final locale = '${map['locale'] ?? ''}'.trim();
      final language = '${map['language'] ?? ''}'.trim();
      final normalizedLocale = locale.toLowerCase();
      final normalizedLanguage = language.toLowerCase();
      final isChinese = normalizedLocale.startsWith('zh') ||
          normalizedLocale.contains('-zh') ||
          normalizedLanguage == 'zh';
      if (!isChinese) {
        continue;
      }

      final name = '${map['name'] ?? ''}'.trim();
      if (name.isEmpty || locale.isEmpty) {
        continue;
      }

      final quality = _toInt(map['quality']) ?? 0;
      final latency = _toInt(map['latency']) ?? 500;
      final networkRequired = _toBool(map['network_required']) ?? false;
      final notInstalled = _toBool(map['notInstalled']) ?? false;
      final score = quality * 1000 -
          latency * 10 -
          (networkRequired ? 3000 : 0) -
          (notInstalled ? 5000 : 0);
      if (score <= bestScore) {
        continue;
      }
      bestScore = score;
      bestVoice = {
        'name': name,
        'locale': locale,
      };
    }

    return bestVoice;
  }

  int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }

  bool? _toBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    final normalized = '$value'.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
    return null;
  }

  @override
  Future<bool> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _setError('播报文案为空。');
      return false;
    }

    try {
      final ready = await preload();
      if (!ready) {
        return false;
      }
      await _flutterTts.stop();
      final result = await _flutterTts.speak(trimmed);
      final played = _isSuccessfulResult(result);
      if (!played) {
        _setError('语音播报未成功开始。');
        return false;
      }
      _clearError();
      return true;
    } on MissingPluginException {
      _setError('语音插件未注册，当前设备无法启用试播。');
      return false;
    } on PlatformException catch (error) {
      _setError(_describePlatformException(error));
      return false;
    } catch (_) {
      _setError('语音播报失败。');
      return false;
    }
  }

  String _describePlatformException(PlatformException error) {
    final message = error.message?.trim();
    final code = error.code.trim();

    if (message != null && message.isNotEmpty) {
      final normalized = message.toLowerCase();
      if (normalized.contains('packageinfo is null')) {
        return '语音插件初始化失败：应用语音插件上下文未准备好，请先回到应用前台后重试。';
      }
      if (normalized.contains('not bound to an engine') ||
          normalized.contains('detached from native')) {
        return '语音插件当前未绑定到应用引擎，请回到应用前台后重试。';
      }
      return '语音插件调用失败：$message';
    }

    if (code.isNotEmpty) {
      return '语音插件调用失败：$code';
    }

    return '语音插件调用失败。';
  }
}
