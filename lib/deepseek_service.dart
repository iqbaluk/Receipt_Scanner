import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'gemini_service.dart';

class DeepSeekSettings {
  final String apiKey;
  final String model;
  final bool hasSavedApiKey;
  final bool usesEnvKey;

  const DeepSeekSettings({
    required this.apiKey,
    required this.model,
    required this.hasSavedApiKey,
    required this.usesEnvKey,
  });

  bool get hasUsableKey => DeepSeekService.isUsableApiKey(apiKey);
}

class DeepSeekSettingsCheckResult {
  final bool success;
  final String? workingModel;
  final bool usedFallback;
  final String? errorMessage;

  const DeepSeekSettingsCheckResult.success({
    required this.workingModel,
    required this.usedFallback,
  })  : success = true,
        errorMessage = null;

  const DeepSeekSettingsCheckResult.failure(this.errorMessage)
      : success = false,
        workingModel = null,
        usedFallback = false;
}

class DeepSeekService {
  static const String defaultModel = 'deepseek-v4-flash';
  static const List<String> fallbackModels = [
    'deepseek-v4-flash',
    'deepseek-chat',
  ];
  static const _apiKeyStorageKey = 'deepseek_api_key';
  static const _modelStorageKey = 'deepseek_model';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static bool isUsableApiKey(String key) => key.trim().isNotEmpty;

  static String _envApiKey() {
    try {
      return (dotenv.env['DEEPSEEK_API_KEY'] ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  static Future<String?> savedApiKey() async {
    try {
      final key = await _storage.read(key: _apiKeyStorageKey);
      final trimmed = key?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  static Future<String> savedModel() async {
    try {
      final model = (await _storage.read(key: _modelStorageKey))?.trim() ?? '';
      return model.isEmpty ? defaultModel : model;
    } catch (_) {
      return defaultModel;
    }
  }

  static Future<DeepSeekSettings> loadSettings() async {
    final storedKey = await savedApiKey();
    final model = await savedModel();
    if (storedKey != null && isUsableApiKey(storedKey)) {
      return DeepSeekSettings(
        apiKey: storedKey,
        model: model,
        hasSavedApiKey: true,
        usesEnvKey: false,
      );
    }
    final envKey = _envApiKey();
    return DeepSeekSettings(
      apiKey: envKey,
      model: model,
      hasSavedApiKey: false,
      usesEnvKey: isUsableApiKey(envKey),
    );
  }

  static Future<void> saveSettings({
    required String apiKey,
    required String model,
  }) async {
    final trimmedKey = apiKey.trim();
    final trimmedModel = model.trim().isEmpty ? defaultModel : model.trim();
    if (trimmedKey.isEmpty) {
      await _storage.delete(key: _apiKeyStorageKey);
    } else {
      await _storage.write(key: _apiKeyStorageKey, value: trimmedKey);
    }
    await _storage.write(key: _modelStorageKey, value: trimmedModel);
  }

  static Future<void> resetSettings() async {
    await _storage.delete(key: _apiKeyStorageKey);
    await _storage.delete(key: _modelStorageKey);
  }

  static Future<bool> hasUsableSettings() async {
    final settings = await loadSettings();
    return settings.hasUsableKey;
  }

  static Future<DeepSeekSettingsCheckResult> checkSettings({
    String? apiKey,
    String? model,
  }) async {
    final settings = await loadSettings();
    final key =
        (apiKey?.trim().isNotEmpty ?? false) ? apiKey!.trim() : settings.apiKey;
    final selectedModel =
        (model?.trim().isNotEmpty ?? false) ? model!.trim() : settings.model;

    if (!isUsableApiKey(key)) {
      return const DeepSeekSettingsCheckResult.failure(
        'DeepSeek API key is not set.',
      );
    }

    final candidates = <String>[
      selectedModel,
      ...fallbackModels,
    ]
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    final failures = <String>[];
    for (final candidate in candidates) {
      final ok = await _testModelConnection(apiKey: key, model: candidate);
      if (ok == null) {
        return DeepSeekSettingsCheckResult.success(
          workingModel: candidate,
          usedFallback: candidate != selectedModel,
        );
      }
      failures.add('$candidate: $ok');
    }
    return DeepSeekSettingsCheckResult.failure(
      'No tested DeepSeek model worked. ${failures.last}',
    );
  }

  static Future<String?> _testModelConnection({
    required String apiKey,
    required String model,
  }) async {
    try {
      final content = await _chatCompletion(
        apiKey: apiKey,
        model: model,
        messages: const [
          {'role': 'system', 'content': 'Reply exactly with OK.'},
          {'role': 'user', 'content': 'OK'},
        ],
      );
      if ((content ?? '').trim().isEmpty) {
        return 'Empty response';
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<ScanResult> parseOcrText(
    String ocrText, {
    required List<String> allowedCategories,
  }) async {
    final settings = await loadSettings();
    if (!settings.hasUsableKey) {
      return ScanResult.failure(
        'DeepSeek API key not set. Open Management > DeepSeek API Settings.',
      );
    }

    final text = ocrText.trim();
    if (text.isEmpty) {
      return ScanResult.failure('No OCR text to parse.');
    }

    final categories = allowedCategories
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    if (categories.isEmpty) {
      return ScanResult.failure('No receipt categories are configured.');
    }

    final prompt = _buildPrompt(text, categories);
    try {
      final content = await _chatCompletion(
        apiKey: settings.apiKey,
        model: settings.model,
        messages: [
          {
            'role': 'system',
            'content':
                'You extract structured data from OCR text. Return only valid JSON object, no markdown.'
          },
          {'role': 'user', 'content': prompt},
        ],
      );
      if (content == null || content.trim().isEmpty) {
        return ScanResult.failure('DeepSeek returned empty response.');
      }
      return _parseResponse(content, categories);
    } catch (e) {
      return ScanResult.failure('DeepSeek parse failed: $e');
    }
  }

  static Future<String?> _chatCompletion({
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
  }) async {
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse('https://api.deepseek.com/chat/completions'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.add(
        utf8.encode(
          jsonEncode({
            'model': model,
            'messages': messages,
            'temperature': 0.1,
            'stream': false,
          }),
        ),
      );
      final response =
          await request.close().timeout(const Duration(seconds: 35));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('HTTP ${response.statusCode}: $body');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final message = choices.first['message'];
        if (message is Map<String, dynamic>) {
          return message['content']?.toString();
        }
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static String _buildPrompt(String ocrText, List<String> categories) {
    final examples = _categoryExamples(categories);
    final hints = _categoryDecisionHints(categories);
    return '''
Extract receipt fields from the OCR text below.

Return EXACT JSON schema:
{
  "date": "YYYY-MM-DD or null",
  "invoice_number": "string or null",
  "supplier": "string or null",
  "category": null,
  "category_confidence": null,
  "vat": number or null,
  "gross": number or null,
  "net": number or null,
  "notes": "short item description or null"
}

Rules:
- UK date interpretation (DD/MM/YYYY -> YYYY-MM-DD).
- Remove currency symbols from numbers.
- If a value is unclear, return null.
- Do NOT classify category. Always return null for category and category_confidence.
$examples
$hints
- Return JSON object only.

OCR TEXT:
$ocrText
''';
  }

  static String _categoryExamples(List<String> categories) {
    final lines = <String>[];
    void addIfPresent(String category, String example) {
      if (categories.contains(category)) {
        lines.add('- $example -> "$category"');
      }
    }

    addIfPresent(
        'Material', 'B&Q, Travis Perkins, Wickes, Selco, Howdens, Screwfix');
    addIfPresent('Subcontractor', 'A plumber, electrician, builder invoice');
    addIfPresent('Utility Bills', 'Gas, electricity, water, council tax');
    addIfPresent('Travel', 'Train, taxi, parking, fuel');
    addIfPresent('Insurance', 'Public liability or building insurance');
    addIfPresent('Sundries', 'Tea, biscuits, small consumables');
    addIfPresent('Other', 'Anything that does not fit the other categories');

    if (lines.isEmpty) return '';
    return lines.join('\n');
  }

  static String _categoryDecisionHints(List<String> categories) {
    final insuranceCategory = _findCategoryByKeywords(
      categories,
      const ['insurance'],
    );
    final serviceCategory = _findCategoryByKeywords(
      categories,
      const ['subcontractor', 'professional', 'labour', 'labor', 'service'],
    );
    final materialCategory = _findCategoryByKeywords(
      categories,
      const ['material', 'sundries', 'supply'],
    );
    final travelCategory = _findCategoryByKeywords(
      categories,
      const ['travel', 'transport', 'fuel', 'mileage', 'parking'],
    );
    final utilitiesCategory = _findCategoryByKeywords(
      categories,
      const ['utility', 'utilities', 'electric', 'water', 'gas'],
    );
    final otherCategory = _findCategoryByKeywords(
      categories,
      const ['other', 'misc'],
    );

    final lines = <String>[];
    if (insuranceCategory != null) {
      lines.add(
        '- Use "$insuranceCategory" ONLY for policy/premium/cover documents from insurers or brokers.',
      );
      final fallback = serviceCategory ?? otherCategory ?? categories.first;
      lines.add(
        '- Inspection/survey/certificate/assessment/compliance jobs are NOT insurance; prefer "$fallback".',
      );
    }
    if (serviceCategory != null) {
      lines.add(
        '- Labour/service/trade callout invoices (inspection, electrician, plumber, fitting, repair) -> "$serviceCategory".',
      );
    }
    if (materialCategory != null) {
      lines.add(
        '- Goods and parts purchases (timber, paint, tools, hardware, consumables) -> "$materialCategory".',
      );
    }
    if (travelCategory != null) {
      lines.add(
        '- Train/taxi/fuel/parking/tolls/mileage receipts -> "$travelCategory".',
      );
    }
    if (utilitiesCategory != null) {
      lines.add(
        '- Electricity, gas, water, telecom or council bills -> "$utilitiesCategory".',
      );
    }
    if (lines.isEmpty) {
      final fallback = otherCategory ?? categories.first;
      lines.add('- If uncertain, use "$fallback" and avoid guessing.');
    }
    return lines.join('\n');
  }

  static String? _findCategoryByKeywords(
    List<String> categories,
    List<String> keywords,
  ) {
    for (final category in categories) {
      final lower = category.toLowerCase();
      for (final keyword in keywords) {
        if (lower.contains(keyword)) return category;
      }
    }
    return null;
  }

  static ScanResult _parseResponse(String content, List<String> categories) {
    try {
      String cleaned = content.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceAll(RegExp(r'^```(?:json)?\s*'), '');
        cleaned = cleaned.replaceAll(RegExp(r'\s*```$'), '');
      }
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      final date = _parseDate(json['date']?.toString());
      final invoiceNumber = _cleanString(
        json['invoice_number'] ?? json['invoiceNumber'] ?? json['invoice_no'],
      );
      final supplier = _cleanString(json['supplier']);
      final vat = _parseDouble(json['vat']);
      final gross = _parseDouble(json['gross']);
      double? net = _parseDouble(json['net']);
      if (net == null && gross != null && vat != null) {
        net = gross - vat;
      }

      final rawCategory = _cleanString(json['category']);
      String? category;
      if (rawCategory != null && categories.contains(rawCategory)) {
        category = rawCategory;
      } else {
        category = categories.contains('Other') ? 'Other' : categories.first;
      }
      double? categoryConfidence = _parseDouble(
        json['category_confidence'] ??
            json['categoryConfidence'] ??
            json['category_score'],
      );
      if (categoryConfidence != null) {
        if (categoryConfidence < 0) categoryConfidence = 0;
        if (categoryConfidence > 100) categoryConfidence = 100;
      }

      final notes = _cleanString(json['notes']);
      return ScanResult.success(
        ReceiptData(
          date: date,
          invoiceNumber: invoiceNumber,
          supplier: supplier,
          category: category,
          categoryConfidence: categoryConfidence,
          vat: vat,
          gross: gross,
          net: net,
          rawNotes: notes,
        ),
      );
    } catch (e) {
      return ScanResult.failure('Could not parse DeepSeek response: $e');
    }
  }

  static String? _cleanString(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;
    return s;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final s =
        value.toString().replaceAll('£', '').replaceAll(RegExp(r'[$,\s]'), '');
    if (s.isEmpty || s.toLowerCase() == 'null') return null;
    return double.tryParse(s);
  }

  static DateTime? _parseDate(String? value) {
    if (value == null) return null;
    final input = value.trim();
    if (input.isEmpty || input.toLowerCase() == 'null') return null;
    final iso = DateTime.tryParse(input);
    if (iso != null) return iso;
    final m =
        RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})$').firstMatch(input);
    if (m == null) return null;
    final d = int.tryParse(m.group(1)!);
    final mo = int.tryParse(m.group(2)!);
    var y = int.tryParse(m.group(3)!);
    if (d == null || mo == null || y == null) return null;
    if (y < 100) y += 2000;
    try {
      return DateTime(y, mo, d);
    } catch (_) {
      return null;
    }
  }
}
