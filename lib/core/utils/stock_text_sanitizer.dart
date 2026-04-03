class StockTextSanitizer {
  static const int _replacementRune = 0xFFFD;

  static String sanitizeStockName(
    String? rawName, {
    String fallbackName = '',
    String stockCode = '',
  }) {
    final normalizedRaw = _normalize(rawName);
    if (isReadableStockName(normalizedRaw)) {
      return normalizedRaw;
    }

    final normalizedFallback = _normalize(fallbackName);
    if (isReadableStockName(normalizedFallback)) {
      return normalizedFallback;
    }

    final normalizedCode = stockCode.trim();
    if (normalizedCode.isNotEmpty) {
      return normalizedCode;
    }

    return normalizedRaw.isNotEmpty ? normalizedRaw : normalizedFallback;
  }

  static String sanitizeReadableText(
    String? rawText, {
    String stockCode = '',
    String rawStockName = '',
    String fallbackStockName = '',
  }) {
    var text = _normalize(rawText);
    final normalizedCode = stockCode.trim();
    final normalizedFallback = _normalize(fallbackStockName);
    final sanitizedName = sanitizeStockName(
      rawStockName,
      fallbackName: fallbackStockName,
      stockCode: stockCode,
    );
    final originalName = _normalize(rawStockName);

    if (text.isEmpty) {
      return sanitizedName;
    }

    if (originalName.isNotEmpty &&
        sanitizedName.isNotEmpty &&
        originalName != sanitizedName) {
      text = text.replaceAll(originalName, sanitizedName);
    }

    if (normalizedCode.isNotEmpty &&
        isReadableStockName(normalizedFallback) &&
        sanitizedName == normalizedCode) {
      text = text.replaceAll(normalizedCode, normalizedFallback);
    }

    return text.trim().isEmpty ? sanitizedName : text;
  }

  static bool isReadableStockName(String? value) {
    final text = _normalize(value);
    if (text.isEmpty) {
      return false;
    }
    if (RegExp(r'^[0-9]{6}$').hasMatch(text)) {
      return false;
    }
    if (_containsReplacementOrControl(text)) {
      return false;
    }
    if (_looksLikeMojibake(text)) {
      return false;
    }
    return true;
  }

  static String _normalize(String? value) {
    if (value == null) {
      return '';
    }
    return value
        .replaceAll(RegExp(r'[\u0000-\u001F]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _containsReplacementOrControl(String text) {
    for (final rune in text.runes) {
      if (rune == _replacementRune) {
        return true;
      }
      if (rune >= 0xE000 && rune <= 0xF8FF) {
        return true;
      }
      if (rune < 0x20) {
        return true;
      }
    }
    return false;
  }

  static bool _looksLikeMojibake(String text) {
    if (text.contains('Ã') ||
        text.contains('Â') ||
        text.contains('¤') ||
        text.contains('€')) {
      return true;
    }

    var suspiciousCount = 0;
    for (final rune in text.runes) {
      if (_suspiciousRunes.contains(rune)) {
        suspiciousCount += 1;
      }
    }

    return suspiciousCount >= 2;
  }

  static const Set<int> _suspiciousRunes = {
    0x9375,
    0x93BE,
    0x7487,
    0x9477,
    0x947C,
    0x5F6D,
    0x95A2,
    0x93F3,
    0x8A9E,
    0x6B77,
    0x53F2,
    0x8A2D,
    0x7F6E,
    0x81EA,
    0x9078,
    0x6F67,
    0x695E,
    0x8930,
  };
}
