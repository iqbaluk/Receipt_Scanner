// ============================================================
// Gemini Service - Isolated, failure-safe API wrapper
// ============================================================
// This file is the ONLY place that talks to Gemini.
// If anything in here fails, the rest of the app keeps working.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The result of a scan attempt - either success with data, or failure with reason.
class ScanResult {
  final bool success;
  final ReceiptData? data;
  final String? errorMessage;

  ScanResult.success(this.data)
      : success = true,
        errorMessage = null;

  ScanResult.failure(this.errorMessage)
      : success = false,
        data = null;
}

/// The data Gemini extracts from a receipt image.
/// All fields are nullable - Gemini may not find every field on every receipt.
class ReceiptData {
  final DateTime? date;
  final String? invoiceNumber;
  final String? supplier;
  final String? category;
  final double? categoryConfidence;
  final double? vat;
  final double? gross;
  final double? net;
  final String? rawNotes;

  ReceiptData({
    this.date,
    this.invoiceNumber,
    this.supplier,
    this.category,
    this.categoryConfidence,
    this.vat,
    this.gross,
    this.net,
    this.rawNotes,
  });
}

/// Saved Gemini settings.
///
/// Gemini is the only supported AI provider in this app. The key can come from
/// secure device storage, or fall back to the developer .env file.
class GeminiSettings {
  final String apiKey;
  final String model;
  final bool hasSavedApiKey;
  final bool usesEnvKey;

  const GeminiSettings({
    required this.apiKey,
    required this.model,
    required this.hasSavedApiKey,
    required this.usesEnvKey,
  });

  bool get hasUsableKey => GeminiService.isUsableApiKey(apiKey);
}

class GeminiSettingsCheckResult {
  final bool success;
  final String? workingModel;
  final bool usedFallback;
  final String? errorMessage;

  const GeminiSettingsCheckResult.success({
    required this.workingModel,
    required this.usedFallback,
  })  : success = true,
        errorMessage = null;

  const GeminiSettingsCheckResult.failure(this.errorMessage)
      : success = false,
        workingModel = null,
        usedFallback = false;
}

class GeminiService {
  static const String defaultModel = 'gemini-2.5-flash';
  static const List<String> fallbackModels = [
    'gemini-2.5-flash',
    'gemini-1.5-flash',
  ];
  static const _apiKeyStorageKey = 'gemini_api_key';
  static const _modelStorageKey = 'gemini_model';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const bool strictPrivacyGuard = true;
  static final RegExp _emailRegex = RegExp(
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
    caseSensitive: false,
  );
  static final RegExp _phoneRegex = RegExp(
    r'(\+?\d[\d\s().-]{7,}\d)',
    caseSensitive: false,
  );
  static final RegExp _addressLineRegex = RegExp(
    r'\b(\d+\s+[a-z0-9][a-z0-9\s,.-]{4,}|postcode|post code|road|street|avenue|lane|drive|flat|unit)\b',
    caseSensitive: false,
  );

  static bool isUsableApiKey(String key) {
    final trimmed = key.trim();
    return trimmed.isNotEmpty && trimmed != 'YOUR_GEMINI_API_KEY_HERE';
  }

  /// Returns true if Gemini API key looks usable.
  /// We check this before showing the scan button as enabled.
  static bool isConfigured() {
    try {
      final key = dotenv.env['GEMINI_API_KEY'] ?? '';
      return isUsableApiKey(key);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasUsableSettings() async {
    final settings = await loadSettings();
    return settings.hasUsableKey;
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

  static String _envApiKey() {
    try {
      return (dotenv.env['GEMINI_API_KEY'] ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  static Future<GeminiSettings> loadSettings() async {
    final storedKey = await savedApiKey();
    final model = await savedModel();
    if (storedKey != null && isUsableApiKey(storedKey)) {
      return GeminiSettings(
        apiKey: storedKey,
        model: model,
        hasSavedApiKey: true,
        usesEnvKey: false,
      );
    }

    final envKey = _envApiKey();
    return GeminiSettings(
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
      if (!isUsableApiKey(trimmedKey)) {
        throw ArgumentError('Enter a valid Gemini API key.');
      }
      await _storage.write(key: _apiKeyStorageKey, value: trimmedKey);
    }
    await _storage.write(key: _modelStorageKey, value: trimmedModel);
  }

  static Future<void> resetSettings() async {
    await _storage.delete(key: _apiKeyStorageKey);
    await _storage.delete(key: _modelStorageKey);
  }

  static Future<ScanResult> testSettings({
    String? apiKey,
    String? model,
  }) async {
    final settings = await loadSettings();
    final key =
        (apiKey?.trim().isNotEmpty ?? false) ? apiKey!.trim() : settings.apiKey;
    final selectedModel =
        (model?.trim().isNotEmpty ?? false) ? model!.trim() : settings.model;

    if (!isUsableApiKey(key)) {
      return ScanResult.failure('Gemini API key is not set.');
    }

    return _testModelConnection(apiKey: key, model: selectedModel);
  }

  static Future<GeminiSettingsCheckResult> checkSettings({
    String? apiKey,
    String? model,
  }) async {
    final settings = await loadSettings();
    final key =
        (apiKey?.trim().isNotEmpty ?? false) ? apiKey!.trim() : settings.apiKey;
    final selectedModel =
        (model?.trim().isNotEmpty ?? false) ? model!.trim() : settings.model;

    if (!isUsableApiKey(key)) {
      return const GeminiSettingsCheckResult.failure(
        'Gemini API key is not set.',
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
      final result = await _testModelConnection(
        apiKey: key,
        model: candidate,
      );
      if (result.success) {
        return GeminiSettingsCheckResult.success(
          workingModel: candidate,
          usedFallback: candidate != selectedModel,
        );
      }
      failures.add('$candidate: ${result.errorMessage ?? 'failed'}');
    }

    return GeminiSettingsCheckResult.failure(
      'No tested Gemini model worked. ${failures.last}',
    );
  }

  static Future<ScanResult> _testModelConnection({
    required String apiKey,
    required String model,
  }) async {
    try {
      final testModel = GenerativeModel(
        model: model,
        apiKey: apiKey,
        generationConfig: GenerationConfig(temperature: 0),
      );
      final response = await testModel.generateContent([
        Content.text('Reply with OK only.'),
      ]).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'Gemini test took too long to respond (>15s)',
        ),
      );
      final text = response.text?.trim() ?? '';
      if (text.isEmpty) {
        return ScanResult.failure('Gemini returned an empty test response.');
      }
      return ScanResult.success(null);
    } on TimeoutException catch (e) {
      return ScanResult.failure('Timeout: ${e.message}');
    } on Exception catch (e) {
      return ScanResult.failure('Gemini test failed: ${e.toString()}');
    } catch (e) {
      return ScanResult.failure('Unexpected test error: ${e.toString()}');
    }
  }

  /// Send an image to Gemini and try to extract receipt fields.
  /// Returns a ScanResult that always tells you what happened.
  /// Never throws - all errors are caught and reported via ScanResult.
  static Future<ScanResult> scanReceipt(
    Uint8List imageBytes, {
    required List<String> allowedCategories,
  }) async {
    // ---- Pre-flight checks ----
    final settings = await loadSettings();
    if (!settings.hasUsableKey) {
      return ScanResult.failure(
        'Gemini API key not set. Open Project actions > Gemini settings.',
      );
    }

    if (imageBytes.isEmpty) {
      return ScanResult.failure('No image data to scan.');
    }

    final categories = allowedCategories
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    if (categories.isEmpty) {
      return ScanResult.failure('No receipt categories are configured.');
    }

    // Sanity check on image size (Gemini has a 20MB limit)
    if (imageBytes.length > 19 * 1024 * 1024) {
      return ScanResult.failure(
        'Image too large (${(imageBytes.length / 1024 / 1024).toStringAsFixed(1)} MB). '
        'Please use a smaller photo.',
      );
    }

    try {
      // ---- Build the model ----
      final model = GenerativeModel(
        model: settings.model,
        apiKey: settings.apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.1, // Low temp = more consistent extraction
          responseMimeType: 'application/json', // Force JSON response
        ),
      );

      // ---- Build the prompt ----
      // We give Gemini a clear schema and rules so it returns predictable JSON.
      final examples = _categoryExamples(categories);
      final hints = _categoryDecisionHints(categories);
      final prompt = '''
You are extracting structured data from a receipt or invoice image for a UK property renovation business.

Extract the following fields and return them as a JSON object with this EXACT schema:
{
  "date": "YYYY-MM-DD or null if not visible",
  "invoice_number": "invoice/receipt/order number or null if not visible",
  "supplier": "supplier/vendor name or null",
  "category": "null (user selects category manually in app)",
  "category_confidence": "null",
  "vat": "VAT amount as number (e.g. 12.50) or null",
  "gross": "total gross amount as number or null",
  "net": "net amount as number or null",
  "notes": "brief 1-line description of items if helpful, or null"
}

Rules:
- Extract invoice_number from labels such as Invoice No, Invoice #, Receipt No, Order No, Tax Invoice No, or Document No
- Keep invoice_number exactly as printed where possible, but remove surrounding label text
- Use British date format interpretation (DD/MM/YYYY -> YYYY-MM-DD)
- Currency symbols (GBP, pound) should be stripped from numbers
- VAT in UK is usually 20% - if you see VAT separately listed, use that exact figure
- Do NOT classify category. Always return null for "category" and "category_confidence".
- Do NOT include personal client data in output fields: person names, home/work addresses, email addresses, or telephone numbers.
- If personal data appears, return null for that field instead of outputting it.
- Keep notes strictly item/description text only. If notes include personal data, return null.
$examples
$hints
- If a field is not visible or unclear, return null for that field (NOT a guess)
- Return ONLY the JSON object, no commentary, no markdown fences
''';

      // ---- Send the image with a timeout ----
      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes),
        ]),
      ]).timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw TimeoutException(
          'Gemini took too long to respond (>25s)',
        ),
      );

      // ---- Parse the response ----
      final text = response.text;
      if (text == null || text.trim().isEmpty) {
        return ScanResult.failure('Gemini returned an empty response.');
      }

      return _parseJsonResponse(text, categories);
    } on TimeoutException catch (e) {
      return ScanResult.failure('Timeout: ${e.message}');
    } on Exception catch (e) {
      // Catch all other exceptions (network, API, parsing, etc.)
      return ScanResult.failure('Scan failed: ${e.toString()}');
    } catch (e) {
      // Final safety net - even non-Exception throwables
      return ScanResult.failure('Unexpected error: ${e.toString()}');
    }
  }

  /// Parse the JSON Gemini sent us into a ReceiptData object.
  /// Defensive: any parsing failure returns a useful error message.
  static ScanResult _parseJsonResponse(String text, List<String> categories) {
    try {
      // Strip any markdown code fences just in case Gemini ignores our instruction
      String cleaned = text.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceAll(RegExp(r'^```(?:json)?\s*'), '');
        cleaned = cleaned.replaceAll(RegExp(r'\s*```$'), '');
      }

      final json = jsonDecode(cleaned) as Map<String, dynamic>;

      // ---- Date ----
      DateTime? date;
      final dateStr = json['date']?.toString();
      if (dateStr != null && dateStr.toLowerCase() != 'null') {
        date = DateTime.tryParse(dateStr);
      }

      // ---- Strings ----
      String? invoiceNumber = _cleanString(
        json['invoice_number'] ?? json['invoiceNumber'] ?? json['invoice_no'],
      );
      String? supplier = _cleanString(json['supplier']);
      String? notes = _cleanString(json['notes']);

      if (strictPrivacyGuard) {
        invoiceNumber = _sanitizeInvoiceNumber(invoiceNumber);
        supplier = _sanitizeSupplier(supplier);
        notes = _sanitizeNotes(notes);
      }

      // ---- Category - validate against allowed list ----
      String? category = _cleanString(json['category']);
      if (category != null && !categories.contains(category)) {
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

      // ---- Numbers ----
      double? vat = _parseDouble(json['vat']);
      double? gross = _parseDouble(json['gross']);
      double? net = _parseDouble(json['net']);

      // If gross is present but net isn't, calculate it
      if (gross != null && net == null && vat != null) {
        net = gross - vat;
      }

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
      return ScanResult.failure(
        'Could not parse Gemini response: ${e.toString()}',
      );
    }
  }

  static String? _cleanString(dynamic value) {
    if (value == null) return null;
    final str = value.toString().trim();
    if (str.isEmpty || str.toLowerCase() == 'null') return null;
    return str;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final str =
        value.toString().replaceAll('£', '').replaceAll(RegExp(r'[$,\\s]'), '');
    if (str.isEmpty || str.toLowerCase() == 'null') return null;
    return double.tryParse(str);
  }

  static String? _sanitizeInvoiceNumber(String? value) {
    if (value == null) return null;
    var cleaned = value.trim();
    if (cleaned.isEmpty) return null;
    cleaned = cleaned.replaceAll(RegExp(r'[^A-Za-z0-9\\-_/]'), '');
    if (cleaned.isEmpty) return null;
    if (_containsSensitiveData(cleaned)) return null;
    return cleaned;
  }

  static String? _sanitizeSupplier(String? value) {
    if (value == null) return null;
    final cleaned = value.trim();
    if (cleaned.isEmpty) return null;
    if (_containsSensitiveData(cleaned)) return null;
    return cleaned;
  }

  static String? _sanitizeNotes(String? value) {
    if (value == null) return null;
    final cleaned = value.trim();
    if (cleaned.isEmpty) return null;
    if (_containsSensitiveData(cleaned)) return null;
    return cleaned;
  }

  static bool _containsSensitiveData(String value) {
    return _emailRegex.hasMatch(value) ||
        _phoneRegex.hasMatch(value) ||
        _addressLineRegex.hasMatch(value);
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

    if (lines.isEmpty) {
      return '- Use the closest matching configured category.';
    }
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
}
