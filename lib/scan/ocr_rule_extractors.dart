class OcrRuleExtractors {
  static String? extractInvoice(String text) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final labelRegex = RegExp(
      r'(?:(?:invoice|invoce|invoie|inv)\s*(?:no|ne|nr|num|number|#)|inv\s*#)',
      caseSensitive: false,
    );
    final valueRegex = RegExp(
      r'([A-Z0-9][A-Z0-9/_-]{4,40})',
      caseSensitive: false,
    );
    final blockedRegex = RegExp(
      r'(vat\s*no|company\s*no|tel|phone|route|pod|account\s*no)',
      caseSensitive: false,
    );

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!labelRegex.hasMatch(line) || blockedRegex.hasMatch(line)) continue;

      final sameLine = valueRegex.firstMatch(line)?.group(1);
      final cleanedSame = _sanitizeInvoice(sameLine);
      if (_looksLikeInvoice(cleanedSame)) return cleanedSame;

      if (i + 1 < lines.length) {
        final next = lines[i + 1];
        if (blockedRegex.hasMatch(next)) continue;
        final nextVal = valueRegex.firstMatch(next)?.group(1);
        final cleanedNext = _sanitizeInvoice(nextVal);
        if (_looksLikeInvoice(cleanedNext)) return cleanedNext;
      }
    }

    final globalRegex = RegExp(
      r'(?:invoice|invoce|invoie|inv)\s*(?:no|ne|nr|num|number|#)\s*[:#-]?\s*([A-Z0-9][A-Z0-9/_-]{4,40})',
      caseSensitive: false,
    );
    final global = _sanitizeInvoice(globalRegex.firstMatch(text)?.group(1));
    if (_looksLikeInvoice(global)) return global;

    return null;
  }

  static DateTime? extractDate(String text) {
    final dmy = RegExp(r'\b(\d{1,2})[\/-](\d{1,2})[\/-](\d{2,4})\b');
    final match = dmy.firstMatch(text);
    if (match == null) return null;
    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final rawYear = int.tryParse(match.group(3)!);
    if (day == null || month == null || rawYear == null) return null;
    final year = rawYear < 100 ? (2000 + rawYear) : rawYear;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  static double? extractGross(String text) {
    final patterns = <RegExp>[
      RegExp(
          r'(?:grand\s*total|total\s*amount|amount\s*due|total)\s*[:#-]?\s*[A-Z\xC2\xA3$]*\s*([0-9]+(?:\.[0-9]{1,2})?)',
          caseSensitive: false),
      RegExp(r'[\xC2\xA3$]\s*([0-9]+(?:\.[0-9]{1,2})?)'),
    ];
    double? best;
    for (final p in patterns) {
      for (final m in p.allMatches(text)) {
        final v = double.tryParse(m.group(1) ?? '');
        if (v == null || v <= 0) continue;
        if (best == null || v > best) best = v;
      }
      if (best != null) return best;
    }
    return null;
  }

  static double? extractPaid(String text) {
    final paidRegex = RegExp(
      r'(?:paid|payd|pd|amount\s*paid|total\s*paid|card\s*payment|cash\s*payment)\s*[:#-]?\s*[A-Z\xC2\xA3$]*\s*([0-9]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    );
    final m = paidRegex.firstMatch(text);
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  static double? extractVat(String text) {
    final vatRegex = RegExp(
      r'(?:vat(?:\s*@\s*\d+%?)?|tax)\s*[:#-]?\s*[A-Z\xC2\xA3$]*\s*([0-9]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    );
    final m = vatRegex.firstMatch(text);
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  static String? extractSupplier(String text) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    for (final line in lines.take(12)) {
      final lower = line.toLowerCase();
      if (lower.contains('invoice')) continue;
      if (lower.contains('vat no')) continue;
      if (RegExp(r'\d{2}/\d{2}/\d{2,4}').hasMatch(line)) continue;
      if (line.length >= 4 && RegExp(r'[a-zA-Z]').hasMatch(line)) {
        return line;
      }
    }
    return null;
  }

  static String? summarizeLineItems(String text) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final items = <String>[];
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.contains('invoice')) continue;
      if (lower.contains('total')) continue;
      if (lower.contains('vat')) continue;
      if (RegExp(r'\b\d{1,2}[\/-]\d{1,2}[\/-]\d{2,4}\b').hasMatch(line)) {
        continue;
      }
      if (RegExp(r'[A-Za-z]').hasMatch(line) && line.length > 4) {
        final cleaned = line.replaceAll(RegExp(r'\s+'), ' ');
        items.add(cleaned);
      }
      if (items.length >= 3) break;
    }
    if (items.isEmpty) return null;
    return items.join(', ');
  }

  static bool isUsableFastExtraction({
    DateTime? date,
    String? supplier,
    double? gross,
    String? invoice,
  }) {
    var score = 0;
    if (date != null) score++;
    if ((supplier?.trim().isNotEmpty ?? false)) score++;
    if ((gross ?? 0) > 0) score++;
    if ((invoice?.trim().isNotEmpty ?? false)) score++;
    return score >= 2;
  }

  static String? _sanitizeInvoice(String? value) {
    final cleaned = value?.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleaned == null || cleaned.isEmpty) return null;
    return cleaned;
  }

  static bool _looksLikeInvoice(String? value) {
    if (value == null || value.length < 5) return false;
    return RegExp(r'\d').hasMatch(value);
  }
}
