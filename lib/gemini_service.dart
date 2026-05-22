// ============================================================
// Gemini Service - Isolated, failure-safe API wrapper
// ============================================================
// This file is the ONLY place that talks to Gemini.
// If anything in here fails, the rest of the app keeps working.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'utils/ai_extraction_helpers.dart';

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
  final double? paidAmount;
  final double? net;
  final String? rawNotes;
  final List<String> extractionWarnings;

  ReceiptData({
    this.date,
    this.invoiceNumber,
    this.supplier,
    this.category,
    this.categoryConfidence,
    this.vat,
    this.gross,
    this.paidAmount,
    this.net,
    this.rawNotes,
    this.extractionWarnings = const [],
  });

  ReceiptData copyWith({
    DateTime? date,
    String? invoiceNumber,
    String? supplier,
    String? category,
    double? categoryConfidence,
    double? vat,
    double? gross,
    double? paidAmount,
    double? net,
    String? rawNotes,
    List<String>? extractionWarnings,
  }) {
    return ReceiptData(
      date: date ?? this.date,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      supplier: supplier ?? this.supplier,
      category: category ?? this.category,
      categoryConfidence: categoryConfidence ?? this.categoryConfidence,
      vat: vat ?? this.vat,
      gross: gross ?? this.gross,
      paidAmount: paidAmount ?? this.paidAmount,
      net: net ?? this.net,
      rawNotes: rawNotes ?? this.rawNotes,
      extractionWarnings: extractionWarnings ?? this.extractionWarnings,
    );
  }
}

/// Saved Gemini settings.
///
/// Gemini is the only supported AI provider in this app. The key can come from
/// secure device storage, or fall back to the developer .env file.
class GeminiSettings {
  final String apiKey;
  final String model;
  final String scanMode;
  final bool hasSavedApiKey;
  final bool usesEnvKey;

  const GeminiSettings({
    required this.apiKey,
    required this.model,
    required this.scanMode,
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
  static const List<String> selectableModels = [
    'gemini-3.5-flash',
    'gemini-3.1-pro-preview',
    'gemini-3.1-flash-lite',
    'gemini-2.5-pro',
    'gemini-2.5-flash',
    'gemini-1.5-pro',
    'gemini-1.5-flash',
  ];
  static const List<String> fallbackModels = [
    'gemini-3.5-flash',
    'gemini-3.1-flash-lite',
    'gemini-2.5-flash',
    'gemini-1.5-flash',
  ];
  static const _apiKeyStorageKey = 'gemini_api_key';
  static const _modelStorageKey = 'gemini_model';
  static const _scanModeStorageKey = 'gemini_scan_mode';
  static const _modelOptionsStorageKey = 'gemini_model_options_json';
  static const _lastScanModelStorageKey = 'gemini_last_scan_model';
  static const String scanModeFast = 'fast';
  static const String scanModeAccurate = 'accurate';
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

  static Future<String> savedScanMode() async {
    try {
      final mode =
          (await _storage.read(key: _scanModeStorageKey))?.trim() ?? '';
      if (mode == scanModeAccurate) return scanModeAccurate;
      return scanModeFast;
    } catch (_) {
      return scanModeFast;
    }
  }

  static Future<List<String>> savedModelOptions() async {
    try {
      final raw = (await _storage.read(key: _modelOptionsStorageKey)) ?? '';
      if (raw.trim().isEmpty) return List<String>.from(selectableModels);
      final decoded = jsonDecode(raw);
      if (decoded is! List) return List<String>.from(selectableModels);
      final values = decoded
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      if (values.isEmpty) return List<String>.from(selectableModels);
      return values;
    } catch (_) {
      return List<String>.from(selectableModels);
    }
  }

  static Future<void> saveModelOptions(List<String> options) async {
    final sanitized = options
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (sanitized.isEmpty) {
      await _storage.delete(key: _modelOptionsStorageKey);
      return;
    }
    await _storage.write(
      key: _modelOptionsStorageKey,
      value: jsonEncode(sanitized),
    );
  }

  static Future<String?> lastScanModel() async {
    try {
      final model =
          (await _storage.read(key: _lastScanModelStorageKey))?.trim() ?? '';
      return model.isEmpty ? null : model;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _recordLastScanModel(String model) async {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    try {
      await _storage.write(key: _lastScanModelStorageKey, value: trimmed);
    } catch (_) {
      // Non-blocking telemetry hint; ignore storage failures.
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
    final scanMode = await savedScanMode();
    if (storedKey != null && isUsableApiKey(storedKey)) {
      return GeminiSettings(
        apiKey: storedKey,
        model: model,
        scanMode: scanMode,
        hasSavedApiKey: true,
        usesEnvKey: false,
      );
    }

    final envKey = _envApiKey();
    return GeminiSettings(
      apiKey: envKey,
      model: model,
      scanMode: scanMode,
      hasSavedApiKey: false,
      usesEnvKey: isUsableApiKey(envKey),
    );
  }

  static Future<void> saveSettings({
    required String apiKey,
    required String model,
    String? scanMode,
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
    final normalizedMode =
        scanMode == scanModeAccurate ? scanModeAccurate : scanModeFast;
    await _storage.write(key: _scanModeStorageKey, value: normalizedMode);
  }

  static Future<void> resetSettings() async {
    await _storage.delete(key: _apiKeyStorageKey);
    await _storage.delete(key: _modelStorageKey);
    await _storage.delete(key: _scanModeStorageKey);
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
    String? imagePath,
    String? businessNature,
    String? businessDescription,
    String? scanModeOverride,
  }) async {
    // ---- Pre-flight checks ----
    final settings = await loadSettings();
    final mode = (scanModeOverride?.trim().isNotEmpty ?? false)
        ? scanModeOverride!.trim()
        : settings.scanMode;
    final fastMode = mode == scanModeFast;
    final effectiveModel = fastMode ? 'gemini-3.5-flash' : settings.model;
    debugPrint(
      'SCAN_START mode=$mode fastMode=$fastMode model=$effectiveModel imageBytes=${imageBytes.length}',
    );
    if (!settings.hasUsableKey) {
      return ScanResult.failure(
        'Gemini API key not set. Open Operation actions > Gemini settings.',
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
      final totalStopwatch = Stopwatch()..start();
      String? ocrText;
      String? ocrTopRightText;
      String? localOcrInvoiceNumber;
      String aiMimeType = 'image/jpeg';
      Uint8List aiImageBytes = imageBytes;
      Future<_OcrSnapshot?>? ocrSnapshotFuture;
      var ocrResolved = false;
      Future<void> ensureOcrPrepared() async {
        if (ocrResolved) return;
        ocrResolved = true;
        final ocrStopwatch = Stopwatch()..start();
        final ocrSnapshot = await ocrSnapshotFuture;
        ocrStopwatch.stop();
        debugPrint('SCAN_TIMING ocr_ms=${ocrStopwatch.elapsedMilliseconds}');
        ocrText = ocrSnapshot?.fullText;
        ocrTopRightText = ocrSnapshot?.topRightHeaderText;
        if (ocrTopRightText != null && ocrTopRightText!.trim().isNotEmpty) {
          final topRightText = ocrTopRightText!;
          localOcrInvoiceNumber =
              _extractInvoiceNumberFromOcrText(topRightText);
        }
        if ((localOcrInvoiceNumber == null ||
                localOcrInvoiceNumber!.trim().isEmpty) &&
            ocrText != null &&
            ocrText!.trim().isNotEmpty) {
          final deterministicInvoice =
              _extractInvoiceNumberDeterministic(ocrText!);
          if (deterministicInvoice != null &&
              deterministicInvoice.trim().isNotEmpty) {
            localOcrInvoiceNumber = deterministicInvoice;
          }
        }
        if ((localOcrInvoiceNumber == null ||
                localOcrInvoiceNumber!.trim().isEmpty) &&
            ocrText != null &&
            ocrText!.trim().isNotEmpty) {
          localOcrInvoiceNumber = _extractInvoiceNumberFromOcrText(ocrText!);
        }
      }

      if (!fastMode && imagePath != null && imagePath.trim().isNotEmpty) {
        debugPrint('SCAN_PATH local_ocr=enabled imagePath=true');
        // Start OCR in parallel with Gemini call to reduce end-to-end latency.
        ocrSnapshotFuture = _extractOcrSnapshotFromImagePath(imagePath.trim());
        final prepared = await _prepareAiImagePayloadForQuality(imageBytes);
        aiImageBytes = prepared.bytes;
        aiMimeType = prepared.mimeType;
      } else {
        debugPrint('SCAN_PATH local_ocr=skipped fastMode=$fastMode');
      }

      // ---- Build the model ----
      final model = GenerativeModel(
        model: effectiveModel,
        apiKey: settings.apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.1, // Low temp = more consistent extraction
          responseMimeType: 'application/json', // Force JSON response
        ),
      );

      // ---- Build the prompt ----
      // We give Gemini a clear schema and rules so it returns predictable JSON.
      final examples = categoryExamplesPrompt(categories);
      final hints = categoryDecisionHintsPrompt(
        categories,
        businessNature: businessNature,
        businessDescription: businessDescription,
      );
      final businessContextLine = [
        businessNature?.trim() ?? '',
        businessDescription?.trim() ?? '',
      ].where((v) => v.isNotEmpty).join(' | ');
      final prompt = '''
You are extracting structured data from a receipt or invoice image for a UK business.
${businessContextLine.isEmpty ? '' : 'Business profile context: $businessContextLine'}

Extract the following fields and return them as a JSON object with this EXACT schema:
{
  "date": "YYYY-MM-DD or null if not visible",
  "invoice_number": "invoice/receipt/order number or null if not visible",
  "supplier": "supplier/vendor name or null",
  "category": "best matching category from the allowed list, or null if unclear",
  "category_confidence": "0-100 number for category certainty, or null if category is null",
  "vat": "VAT amount as number (e.g. 12.50) or null",
  "gross": "total gross amount as number or null",
  "paid_amount": "amount actually paid (TOTAL TO PAY/card/cash), number or null",
  "net": "net amount as number or null",
  "notes": "brief 1-line description of items if helpful, or null",
  "extraction_warnings": "array of short warning strings, [] if none"
}

Rules:
- CRITICAL invoice_number extraction:
  - Scan the full page, not only headers. Check boxed sections, order details, margins, and footer blocks.
  - Find invoice number labels and extract the value immediately after the label on the same line, or next short line.
  - Preferred labels: Invoice No, Invoice Number, Invoice Ne (OCR typo), Invoce No (OCR typo), Inv No, Inv Nr, Invoice #, Tax Invoice No, Document No, Bill No, Doc Ref.
  - Also check variants: INV NO, INV#, Ref No, Reference No, Document Ref, Sales Invoice No.
  - If a label has no space before value (e.g. Invoice No:BNZ123), still extract BNZ123.
  - Keep invoice_number as printed (trim label text and surrounding punctuation only).
  - If multiple candidate document numbers exist, prioritize the one tied to invoice/billing context near invoice date/total.
  - Ignore values tied to non-invoice labels: VAT No, Company No, Tel, Account No, Customer Ref, Route, POD.
- Use British date format interpretation (DD/MM/YYYY -> YYYY-MM-DD)
- Currency symbols (GBP, pound) should be stripped from numbers
- VAT in UK is usually 20% - if you see VAT separately listed, use that exact figure
- If both invoice total and payment total appear, map invoice total to gross and amount paid to paid_amount
- Typical payment labels: TOTAL TO PAY, AMOUNT PAID, CARD PAYMENT, CASH PAYMENT, VISA/MASTERCARD amount
- Net must represent the invoice net amount (before VAT): net = gross - vat.
- Do NOT set net from paid_amount. paid_amount can be partial and is separate from invoice net/gross.
- Allowed categories (choose exactly one if reasonably clear): ${categories.join(', ')}
- Category confidence must be 0-100 where 100 = very certain.
- Do NOT include personal client data in output fields: person names, home/work addresses, email addresses, or telephone numbers.
- If personal data appears, return null for that field instead of outputting it.
- Keep notes strictly item/description text only. If notes include personal data, return null.
- Category must use business profile context when classifying ambiguous items.
$examples
$hints
- Handwriting rule: you may read handwritten values if clearly legible and tied to a known field label.
- If handwritten text is unclear, return null instead of guessing.
- If any critical field comes from handwriting (invoice_number, date, gross, paid_amount, vat, net), add a warning in extraction_warnings:
  - Example: "Handwritten value used: paid_amount"
- If a field is not visible or unclear, return null for that field (NOT a guess)
- If invoice number cannot be extracted with high confidence, set invoice_number to null and include "Invoice number not detected" in extraction_warnings.
- Return ONLY the JSON object, no commentary, no markdown fences
''';

      // ---- Send the image with a timeout ----
      final primaryStopwatch = Stopwatch()..start();
      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart(aiMimeType, aiImageBytes),
        ]),
      ]).timeout(
        Duration(seconds: fastMode ? 20 : 45),
        onTimeout: () => throw TimeoutException(
          fastMode
              ? 'Gemini took too long to respond (>20s)'
              : 'Gemini took too long to respond (>45s)',
        ),
      );
      primaryStopwatch.stop();
      debugPrint(
        'SCAN_TIMING primary_ms=${primaryStopwatch.elapsedMilliseconds} payload_bytes=${aiImageBytes.length}',
      );

      // ---- Parse the response ----
      final text = response.text;
      if (text == null || text.trim().isEmpty) {
        debugPrint('SCAN_RESULT empty_response');
        return ScanResult.failure('Gemini returned an empty response.');
      }

      final parsed = _parseJsonResponse(text, categories);
      if (!parsed.success || parsed.data == null) {
        debugPrint('SCAN_RESULT parse_failed');
        return parsed;
      }

      var patchedData = parsed.data!;

      // Use local OCR text for numeric fallback only when AI misses paid amount.
      if ((patchedData.paidAmount == null || patchedData.paidAmount! <= 0) &&
          ocrSnapshotFuture != null) {
        await ensureOcrPrepared();
      }
      if ((patchedData.paidAmount == null || patchedData.paidAmount! <= 0) &&
          ocrText != null &&
          ocrText!.trim().isNotEmpty) {
        final paidFromOcr = _extractPaidAmountByRegex(ocrText!);
        if (paidFromOcr != null && paidFromOcr > 0) {
          patchedData = patchedData.copyWith(paidAmount: paidFromOcr);
        } else if (patchedData.gross != null) {
          final balanceDue = _extractBalanceDueByRegex(ocrText!);
          if (balanceDue != null && balanceDue >= 0) {
            final derivedPaid = (patchedData.gross! - balanceDue);
            if (derivedPaid >= 0) {
              patchedData = patchedData.copyWith(paidAmount: derivedPaid);
            }
          }
        }
      }

      if ((parsed.data!.invoiceNumber == null ||
              parsed.data!.invoiceNumber!.trim().isEmpty) &&
          ocrSnapshotFuture != null) {
        await ensureOcrPrepared();
      }
      if ((parsed.data!.invoiceNumber == null ||
              parsed.data!.invoiceNumber!.trim().isEmpty) &&
          localOcrInvoiceNumber != null &&
          localOcrInvoiceNumber!.trim().isNotEmpty) {
        debugPrint('SCAN_INVOICE source=local_ocr');
        await _recordLastScanModel(effectiveModel);
        return ScanResult.success(
          patchedData.copyWith(invoiceNumber: localOcrInvoiceNumber),
        );
      }

      if (!fastMode) {
        var invoiceMissing = patchedData.invoiceNumber == null ||
            patchedData.invoiceNumber!.trim().isEmpty;
        var rescueNeeded = _needsLowQualityRescue(patchedData);

        if (ocrSnapshotFuture != null && (invoiceMissing || rescueNeeded)) {
          await ensureOcrPrepared();
        }
        invoiceMissing = patchedData.invoiceNumber == null ||
            patchedData.invoiceNumber!.trim().isEmpty;
        rescueNeeded = _needsLowQualityRescue(patchedData);

        if (invoiceMissing || rescueNeeded) {
          final shouldRunInvoiceFallback = invoiceMissing &&
              (localOcrInvoiceNumber == null ||
                  localOcrInvoiceNumber!.trim().isEmpty);
          debugPrint(
            'SCAN_PARALLEL invoiceFallback=$shouldRunInvoiceFallback rescue=$rescueNeeded',
          );

          final invoiceFuture = shouldRunInvoiceFallback
              ? _extractInvoiceNumberFallback(
                  apiKey: settings.apiKey,
                  modelName: effectiveModel,
                  imageBytes: aiImageBytes,
                  imageMimeType: aiMimeType,
                  timeoutSeconds: 12,
                )
              : Future<String?>.value(null);

          final rescueFuture = rescueNeeded
              ? _rescueLowQualityExtraction(
                  apiKey: settings.apiKey,
                  modelName: effectiveModel,
                  imageBytes: aiImageBytes,
                  imageMimeType: aiMimeType,
                  categories: categories,
                  ocrText: ocrText,
                  businessNature: businessNature,
                  businessDescription: businessDescription,
                )
              : Future<ReceiptData?>.value(null);

          final fallbackStopwatch = Stopwatch()..start();
          final parallelResults = await Future.wait<Object?>([
            invoiceFuture,
            rescueFuture,
          ]);
          fallbackStopwatch.stop();
          debugPrint(
            'SCAN_TIMING fallback_rescue_ms=${fallbackStopwatch.elapsedMilliseconds}',
          );
          final fallbackInvoiceNumber = parallelResults[0] as String?;
          final rescue = parallelResults[1] as ReceiptData?;

          if (fallbackInvoiceNumber != null &&
              fallbackInvoiceNumber.isNotEmpty) {
            debugPrint('SCAN_INVOICE source=fallback_model');
            patchedData =
                patchedData.copyWith(invoiceNumber: fallbackInvoiceNumber);
          } else {
            debugPrint('SCAN_INVOICE source=fallback_model_none');
          }

          if (rescue != null) {
            debugPrint('SCAN_RESCUE merged=true');
            patchedData = _mergePrimaryWithRescue(patchedData, rescue);
          } else {
            debugPrint('SCAN_RESCUE merged=false');
          }
        } else {
          debugPrint('SCAN_INVOICE fallback_call=skipped');
          debugPrint('SCAN_RESCUE skipped');
        }
      } else {
        debugPrint('SCAN_INVOICE fallback_call=skipped fastMode=$fastMode');
        debugPrint('SCAN_RESCUE skipped fastMode=$fastMode');
      }

      debugPrint('SCAN_RESULT success');
      totalStopwatch.stop();
      debugPrint('SCAN_TIMING total_ms=${totalStopwatch.elapsedMilliseconds}');
      await _recordLastScanModel(effectiveModel);
      return ScanResult.success(patchedData);
    } on TimeoutException catch (e) {
      debugPrint('SCAN_RESULT timeout ${e.message}');
      return ScanResult.failure('Timeout: ${e.message}');
    } on Exception catch (e) {
      debugPrint('SCAN_RESULT exception ${e.toString()}');
      // Catch all other exceptions (network, API, parsing, etc.)
      return ScanResult.failure('Scan failed: ${e.toString()}');
    } catch (e) {
      debugPrint('SCAN_RESULT unexpected ${e.toString()}');
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
      cleaned = _normalizeJsonCandidate(cleaned);
      if (!cleaned.trimLeft().startsWith('{')) {
        final extracted = _extractFirstJsonObject(cleaned);
        if (extracted != null) {
          cleaned = extracted;
        }
      }

      final json = jsonDecode(cleaned) as Map<String, dynamic>;

      // ---- Date ----
      DateTime? date;
      final dateStr = json['date']?.toString();
      if (dateStr != null && dateStr.toLowerCase() != 'null') {
        date = DateTime.tryParse(dateStr);
      }

      // ---- Strings ----
      String? invoiceNumber = cleanNullableString(
        json['invoice_number'] ??
            json['invoiceNumber'] ??
            json['invoice_no'] ??
            json['inv_no'] ??
            json['inv_number'] ??
            json['receipt_no'] ??
            json['receipt_number'] ??
            json['order_no'] ??
            json['order_number'] ??
            json['doc_no'] ??
            json['doc_ref'] ??
            json['document_no'] ??
            json['document_ref'] ??
            json['reference'] ??
            json['reference_no'] ??
            json['ref_no'] ??
            json['tax_invoice_no'],
      );
      if (invoiceNumber != null &&
          invoiceNumber.trim().toUpperCase() == 'NOT_FOUND') {
        invoiceNumber = null;
      }
      String? supplier = cleanNullableString(
        json['supplier'] ?? json['vendor'] ?? json['supplier_name'],
      );
      String? notes = cleanNullableString(
        json['notes'] ?? json['description'] ?? json['item_description'],
      );
      final extractionWarnings = _parseWarnings(
        json['extraction_warnings'] ?? json['warnings'],
      );

      if (strictPrivacyGuard) {
        invoiceNumber = _sanitizeInvoiceNumber(invoiceNumber);
        supplier = _sanitizeSupplier(supplier);
        notes = _sanitizeNotes(notes);
      }

      // ---- Category - validate against allowed list ----
      String? category = cleanNullableString(json['category']);
      if (category != null) {
        final exactMatch = categories.where((c) => c == category).toList();
        if (exactMatch.isNotEmpty) {
          category = exactMatch.first;
        } else {
          final lowerMatch = categories
              .where((c) => c.toLowerCase() == category!.toLowerCase())
              .toList();
          category = lowerMatch.isNotEmpty ? lowerMatch.first : null;
        }
      }
      double? categoryConfidence = parseLooseDouble(
        json['category_confidence'] ??
            json['categoryConfidence'] ??
            json['category_score'],
      );
      if (categoryConfidence != null) {
        if (categoryConfidence < 0) categoryConfidence = 0;
        if (categoryConfidence > 100) categoryConfidence = 100;
      }

      // ---- Numbers ----
      double? vat =
          parseLooseDouble(json['vat'] ?? json['vat_amount'] ?? json['tax']);
      double? gross = parseLooseDouble(
        json['gross'] ??
            json['total'] ??
            json['total_amount'] ??
            json['invoice_total'],
      );
      double? paidAmount = parseLooseDouble(
        json['paid_amount'] ?? json['paidAmount'] ?? json['amount_paid'],
      );
      double? net = parseLooseDouble(json['net']);

      // If paid amount is missing, default paid = gross.
      if (paidAmount == null && gross != null) {
        paidAmount = gross;
      }

      // Net must be invoice net (gross - VAT), never derived from paid amount.
      if (gross != null) {
        net = gross - (vat ?? 0);
      } else if (net == null && paidAmount != null && vat != null) {
        // Fallback only when gross is missing.
        net = paidAmount - vat;
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
          paidAmount: paidAmount,
          net: net,
          rawNotes: notes,
          extractionWarnings: extractionWarnings,
        ),
      );
    } catch (e) {
      debugPrint('SCAN_PARSE error=${e.toString()}');
      return ScanResult.failure(
        'Could not parse Gemini response: ${e.toString()}',
      );
    }
  }

  static String _normalizeJsonCandidate(String value) {
    return value
        .replaceAll('\u201c', '"')
        .replaceAll('\u201d', '"')
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'");
  }

  static String? _extractFirstJsonObject(String value) {
    final start = value.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inQuotes = false;
    var escaped = false;
    for (var i = start; i < value.length; i++) {
      final char = value[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == '\\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inQuotes = !inQuotes;
        continue;
      }
      if (inQuotes) continue;
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          return value.substring(start, i + 1);
        }
      }
    }
    return null;
  }

  static String? _sanitizeInvoiceNumber(String? value) {
    if (value == null) return null;
    var cleaned = value.trim();
    if (cleaned.isEmpty) return null;
    cleaned = cleaned.replaceAll(RegExp(r'[^A-Za-z0-9\\-_/]'), '');
    if (cleaned.isEmpty) return null;
    // Invoice IDs can be long alphanumeric values and may look "phone-like".
    // Do not apply phone-number PII filtering to invoice numbers.
    if (_emailRegex.hasMatch(cleaned) || _addressLineRegex.hasMatch(cleaned)) {
      return null;
    }
    // Reject obvious OCR fragments/non-invoice tokens that often appear
    // when the model returns part of the label (e.g. "oice").
    final lower = cleaned.toLowerCase();
    const blocked = <String>{
      'invoice',
      'nvoice',
      'oice',
      'inv',
      'number',
      'no',
      'ne',
      'nr',
      'date',
      'total',
      'gross',
      'vat',
      'bill',
      'doc',
      'ref',
    };
    if (blocked.contains(lower)) return null;
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

  static Future<String?> _extractInvoiceNumberFallback({
    required String apiKey,
    required String modelName,
    required Uint8List imageBytes,
    String imageMimeType = 'image/jpeg',
    int timeoutSeconds = 18,
  }) async {
    try {
      final model = GenerativeModel(
        model: modelName,
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0,
          responseMimeType: 'application/json',
        ),
      );

      final response = await model.generateContent([
        Content.multi([
          TextPart(
            '''
You are extracting ONLY the invoice number from this invoice/receipt image.

Rules:
- Scan the full document, including order details, boxed sections, margins, and footer.
- Preferred labels: Invoice No, Invoice Number, Invoice Ne (OCR typo), Inv No, Inv Nr, Invoice #, Tax Invoice No, Document No, Bill No, Doc Ref.
- If label has joined value (Invoice No:BNZ2024085940), return the value part.
- Ignore non-invoice labels: VAT No, Company No, Tel, Account No, Customer Ref, Route, POD.
- Return strict JSON only:
{
  "extracted_invoice_number": "alphanumeric identifier or NOT_FOUND"
}
''',
          ),
          DataPart('image/jpeg', imageBytes),
        ]),
      ]).timeout(const Duration(seconds: 18));

      final raw = response.text?.trim() ?? '';
      if (raw.isEmpty) return null;

      String? extracted;
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        extracted = cleanNullableString(
          map['extracted_invoice_number'] ?? map['invoice_number'],
        );
      } catch (_) {
        extracted = null;
      }

      if (extracted != null && extracted.toUpperCase() == 'NOT_FOUND') {
        extracted = null;
      }

      final candidate = _extractInvoiceNumberFromOcrText(extracted ?? raw);
      if (candidate == null || candidate.isEmpty) return null;

      return candidate;
    } catch (_) {
      return null;
    }
  }

  static String? _extractInvoiceNumberByRegex(String text) {
    // PATCH-2026-05-21: Harden invoice regex for OCR typos like "Invoice Ne"
    // and joined labels like "InvoiceNo:BNZ...". This block can be reverted
    // independently if extraction quality drops.
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return null;
    final compact = normalized.replaceAll(' ', '');

    const invoiceLabelPattern =
        r'(?:invoice|invoce|invoie|invoic|inv0ice|inv)\s*(?:no|ne|nr|num|number|#)';
    final patterns = <RegExp>[
      RegExp(
        '$invoiceLabelPattern\\.?\\s*[:#-]*\\s*([A-Z0-9][A-Z0-9/_-]{3,})',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:tax\s*(?:invoice|invoce|invoie|invoic)\s*(?:no|ne|nr|num|number|#)\.?|doc(?:ument)?\s*(?:ref|no|ne|nr|num|number)\.?|bill\s*(?:no|ne|nr|num|number)\.?)\s*[:#-]*\s*([A-Z0-9][A-Z0-9/_-]{3,})',
        caseSensitive: false,
      ),
    ];

    for (final input in [normalized, compact]) {
      for (final regex in patterns) {
        final match = regex.firstMatch(input);
        if (match == null) continue;
        final candidate = _normalizeInvoiceCandidate(match.group(1));
        if (_isLikelyInvoiceNumberCandidate(candidate)) {
          return _sanitizeInvoiceNumber(candidate);
        }
      }
    }

    return null;
  }

  static String? _extractInvoiceNumberFromOcrText(String text) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return _sanitizeInvoiceNumber(_extractInvoiceNumberByRegex(text));
    }

    final labelOnLineRegex = RegExp(
      r'((?:invoice|invoce|invoie|invoic)\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#)|inv\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#)|tax\s*(?:invoice|invoce|invoie|invoic)(?:\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#))?|doc(?:ument)?\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|ref)|bill\s*(?:no\.?|ne\.?|nr\.?|num\.?|number))',
      caseSensitive: false,
    );
    final negativeLabelRegex = RegExp(
      r'(vat\s*no|company\s*no|tel|telephone|account\s*no|customer\s*ref|route|pod)',
      caseSensitive: false,
    );
    final sameLineCaptureRegex = RegExp(
      r'(?:(?:invoice|invoce|invoie|invoic)\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#)|inv\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#)|tax\s*(?:invoice|invoce|invoie|invoic)(?:\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#))?|doc(?:ument)?\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|ref)|bill\s*(?:no\.?|ne\.?|nr\.?|num\.?|number))\s*[:#-]*\s*([A-Z0-9][A-Z0-9 /_-]{3,40})',
      caseSensitive: false,
    );
    final nextLineCandidateRegex = RegExp(
      r'^[A-Z0-9][A-Z0-9 /_-]{3,40}$',
      caseSensitive: false,
    );
    final invoiceOnlyLineRegex = RegExp(
      r'^(?:invoice|inv)\.?\s*$',
      caseSensitive: false,
    );
    final labelTailOnlyLineRegex = RegExp(
      r'^(?:no|ne|nr|num|number|#)\.?\s*[:#-]?\s*$',
      caseSensitive: false,
    );

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!labelOnLineRegex.hasMatch(line)) continue;
      if (negativeLabelRegex.hasMatch(line)) continue;

      final sameLine = sameLineCaptureRegex.firstMatch(line)?.group(1);
      final normalizedSameLine = _normalizeInvoiceCandidate(sameLine);
      final sanitizedSameLine = _sanitizeInvoiceNumber(normalizedSameLine);
      if (_isLikelyInvoiceNumberCandidate(sanitizedSameLine)) {
        return sanitizedSameLine;
      }

      if (i + 1 < lines.length) {
        final nextLine = lines[i + 1];
        if (!negativeLabelRegex.hasMatch(nextLine) &&
            nextLineCandidateRegex.hasMatch(nextLine)) {
          final normalizedNext = _normalizeInvoiceCandidate(nextLine);
          final sanitizedNext = _sanitizeInvoiceNumber(normalizedNext);
          if (_isLikelyInvoiceNumberCandidate(sanitizedNext)) {
            return sanitizedNext;
          }
        }
      }
    }

    // Handle split labels across multiple lines in high-res OCR output:
    // Invoice
    // Ne:
    // BNZ2024085940
    for (var i = 0; i < lines.length; i++) {
      if (!invoiceOnlyLineRegex.hasMatch(lines[i])) continue;
      if (i + 2 >= lines.length) continue;
      final mid = lines[i + 1];
      final valueLine = lines[i + 2];
      if (!labelTailOnlyLineRegex.hasMatch(mid)) continue;
      if (negativeLabelRegex.hasMatch(valueLine)) continue;
      if (!nextLineCandidateRegex.hasMatch(valueLine)) continue;
      final normalized = _normalizeInvoiceCandidate(valueLine);
      final sanitized = _sanitizeInvoiceNumber(normalized);
      if (_isLikelyInvoiceNumberCandidate(sanitized)) {
        return sanitized;
      }
    }

    final normalizedGlobal = _normalizeInvoiceCandidate(
      _extractInvoiceNumberByRegex(text),
    );
    final sanitizedGlobal = _sanitizeInvoiceNumber(normalizedGlobal);
    if (_isLikelyInvoiceNumberCandidate(sanitizedGlobal)) {
      return sanitizedGlobal;
    }

    return null;
  }

  static String? _extractInvoiceNumberDeterministic(String? text) {
    if (text == null) return null;
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;

    final labelRegex = RegExp(
      r'(?:(?:invoice|invoce|invoie|invoic|inv0ice|inv)\s*(?:no|ne|nr|num|number|#))',
      caseSensitive: false,
    );
    final sameLineRegex = RegExp(
      r'(?:(?:invoice|invoce|invoie|invoic|inv0ice|inv)\s*(?:no|ne|nr|num|number|#))\s*[:#-]*\s*([A-Z0-9][A-Z0-9/_-]{2,40})',
      caseSensitive: false,
    );
    final blockedLineRegex = RegExp(
      r'(vat\s*no|company\s*no|route|pod|tel|phone|account\s*no|customer\s*ref)',
      caseSensitive: false,
    );

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!labelRegex.hasMatch(line)) continue;
      if (blockedLineRegex.hasMatch(line)) continue;

      final same = sameLineRegex.firstMatch(line)?.group(1)?.trim();
      final sanitizedSame = _sanitizeInvoiceNumber(same);
      if (_isLikelyInvoiceNumberCandidate(sanitizedSame)) {
        return sanitizedSame;
      }

      if (i + 1 < lines.length) {
        final next = lines[i + 1];
        if (blockedLineRegex.hasMatch(next)) continue;
        final m = RegExp(r'^([A-Z0-9][A-Z0-9/_-]{2,40})$', caseSensitive: false)
            .firstMatch(next);
        final nextValue = m?.group(1)?.trim();
        final sanitizedNext = _sanitizeInvoiceNumber(nextValue);
        if (_isLikelyInvoiceNumberCandidate(sanitizedNext)) {
          return sanitizedNext;
        }
      }
    }

    return null;
  }

  static String? _normalizeInvoiceCandidate(String? value) {
    if (value == null) return null;
    final cleaned = value.trim();
    if (cleaned.isEmpty) return null;
    return cleaned.replaceAll(RegExp(r'\s+'), '');
  }

  static bool _isLikelyInvoiceNumberCandidate(String? value) {
    final candidate = _sanitizeInvoiceNumber(value);
    if (candidate == null || candidate.length < 5) return false;

    final lower = candidate.toLowerCase();
    const blocked = <String>{
      'invoice',
      'nvoice',
      'oice',
      'inv',
      'number',
      'no',
      'ne',
      'nr',
      'date',
      'total',
      'gross',
      'vat',
      'bill',
      'doc',
      'ref',
    };
    if (blocked.contains(lower)) return false;

    return RegExp(r'\d').hasMatch(candidate);
  }

  static double? _extractPaidAmountByRegex(String text) {
    final normalized = text.replaceAll('\n', ' ');
    final paidRegex = RegExp(
      r'(?:total\s*to\s*pay|amount\s*paid|paid|card\s*payment|cash\s*payment|visa\s*debit\s*sale|mastercard)\s*[:#-]?\s*(?:gbp|£)?\s*([0-9]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    );
    final match = paidRegex.firstMatch(normalized);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  static double? _extractBalanceDueByRegex(String text) {
    final normalized = text.replaceAll('\n', ' ');
    final dueRegex = RegExp(
      r'(?:balance\s*due|amount\s*due|outstanding)\s*[:#-]?\s*(?:gbp|£)?\s*([0-9]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    );
    final match = dueRegex.firstMatch(normalized);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  static Future<_OcrSnapshot?> _extractOcrSnapshotFromImagePath(
      String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(inputImage);
      final fullText = recognized.text.trim();
      if (fullText.isEmpty) return null;

      var maxRight = 0.0;
      var maxBottom = 0.0;
      for (final block in recognized.blocks) {
        final box = block.boundingBox;
        if (box.right > maxRight) maxRight = box.right;
        if (box.bottom > maxBottom) maxBottom = box.bottom;
      }

      final topRightBlocks = <String>[];
      if (maxRight > 0 && maxBottom > 0) {
        final minLeft = maxRight * 0.52;
        final maxTop = maxBottom * 0.46;
        for (final block in recognized.blocks) {
          final box = block.boundingBox;
          if (box.left >= minLeft && box.top <= maxTop) {
            final t = block.text.trim();
            if (t.isNotEmpty) {
              topRightBlocks.add(t);
            }
          }
        }
      }

      return _OcrSnapshot(
        fullText: fullText,
        topRightHeaderText: topRightBlocks.join('\n').trim(),
      );
    } catch (_) {
      return null;
    } finally {
      await recognizer.close();
    }
  }

  static List<String> _parseWarnings(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value
          .map((item) => cleanNullableString(item))
          .whereType<String>()
          .toList();
    }
    final single = cleanNullableString(value);
    return single == null ? const [] : <String>[single];
  }

  static bool _needsLowQualityRescue(ReceiptData data) {
    final missingDate = data.date == null;
    final missingSupplier =
        data.supplier == null || data.supplier!.trim().isEmpty;
    final missingGross = data.gross == null || data.gross! <= 0;
    return missingDate || missingSupplier || missingGross;
  }

  static ReceiptData _mergePrimaryWithRescue(
    ReceiptData primary,
    ReceiptData rescue,
  ) {
    final mergedWarnings = <String>{
      ...primary.extractionWarnings,
      ...rescue.extractionWarnings,
      'Low-quality rescue pass applied',
    }.toList();
    return ReceiptData(
      date: primary.date ?? rescue.date,
      invoiceNumber: (primary.invoiceNumber?.trim().isNotEmpty ?? false)
          ? primary.invoiceNumber
          : rescue.invoiceNumber,
      supplier: (primary.supplier?.trim().isNotEmpty ?? false)
          ? primary.supplier
          : rescue.supplier,
      category: (primary.category?.trim().isNotEmpty ?? false)
          ? primary.category
          : rescue.category,
      categoryConfidence:
          primary.categoryConfidence ?? rescue.categoryConfidence,
      vat: primary.vat ?? rescue.vat,
      gross: primary.gross ?? rescue.gross,
      paidAmount: primary.paidAmount ?? rescue.paidAmount,
      net: primary.net ?? rescue.net,
      rawNotes: (primary.rawNotes?.trim().isNotEmpty ?? false)
          ? primary.rawNotes
          : rescue.rawNotes,
      extractionWarnings: mergedWarnings,
    );
  }

  static Future<ReceiptData?> _rescueLowQualityExtraction({
    required String apiKey,
    required String modelName,
    required Uint8List imageBytes,
    String imageMimeType = 'image/jpeg',
    required List<String> categories,
    String? ocrText,
    String? businessNature,
    String? businessDescription,
  }) async {
    try {
      final model = GenerativeModel(
        model: modelName,
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0,
          responseMimeType: 'application/json',
        ),
      );

      final context = [
        businessNature?.trim() ?? '',
        businessDescription?.trim() ?? '',
      ].where((v) => v.isNotEmpty).join(' | ');
      final ocrHint = (ocrText?.trim().isNotEmpty ?? false)
          ? '\nOCR text hint (may be noisy):\n${ocrText!.trim()}'
          : '';

      final prompt = '''
Rescue extraction mode for low-sharp receipt images.
Goal: recover missing critical fields with conservative confidence.
${context.isEmpty ? '' : 'Business profile context: $context'}

Return strict JSON only:
{
  "date": "YYYY-MM-DD or null",
  "invoice_number": "string or null",
  "supplier": "string or null",
  "category": "one of allowed categories or null",
  "category_confidence": "0-100 number or null",
  "vat": "number or null",
  "gross": "number or null",
  "paid_amount": "number or null",
  "net": "number or null",
  "notes": "string or null",
  "extraction_warnings": "array of strings"
}

Rules:
- Prioritize accuracy over completeness; do not guess.
- If unclear, return null for field.
- Allowed categories: ${categories.join(', ')}.
- Use invoice labels and nearby totals to infer values.
- Add warning "Low image quality" if text appears blurry/uncertain.
$ocrHint
''';

      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart(imageMimeType, imageBytes),
        ]),
      ]).timeout(const Duration(seconds: 18));

      final text = response.text?.trim() ?? '';
      if (text.isEmpty) return null;
      final parsed = _parseJsonResponse(text, categories);
      if (!parsed.success || parsed.data == null) return null;
      return parsed.data;
    } catch (_) {
      return null;
    }
  }

  static Future<({Uint8List bytes, String mimeType})>
      _prepareAiImagePayloadForQuality(
    Uint8List originalBytes,
  ) async {
    const maxWidth = 2200;
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(originalBytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width <= maxWidth) {
        return (bytes: originalBytes, mimeType: 'image/jpeg');
      }
      const targetWidth = maxWidth;
      final targetHeight = (height * targetWidth / width).round();
      final codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      final byteData =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        return (bytes: originalBytes, mimeType: 'image/jpeg');
      }
      final resized = byteData.buffer.asUint8List();
      if (resized.length >= originalBytes.length) {
        debugPrint(
          'SCAN_IMAGE downscaled=false reason=larger_payload src_bytes=${originalBytes.length} out_bytes=${resized.length}',
        );
        return (bytes: originalBytes, mimeType: 'image/jpeg');
      }
      debugPrint(
        'SCAN_IMAGE downscaled=true source=${width}x$height target=${targetWidth}x$targetHeight src_bytes=${originalBytes.length} out_bytes=${resized.length}',
      );
      return (bytes: resized, mimeType: 'image/png');
    } catch (_) {
      return (bytes: originalBytes, mimeType: 'image/jpeg');
    }
  }
}

class _OcrSnapshot {
  final String fullText;
  final String? topRightHeaderText;

  const _OcrSnapshot({
    required this.fullText,
    this.topRightHeaderText,
  });
}
