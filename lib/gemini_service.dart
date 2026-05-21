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
    String? imagePath,
    String? businessNature,
    String? businessDescription,
  }) async {
    // ---- Pre-flight checks ----
    final settings = await loadSettings();
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
      String? ocrText;
      String? ocrTopRightText;
      String? localOcrInvoiceNumber;
      if (imagePath != null && imagePath.trim().isNotEmpty) {
        final ocrSnapshot =
            await _extractOcrSnapshotFromImagePath(imagePath.trim());
        ocrText = ocrSnapshot?.fullText;
        ocrTopRightText = ocrSnapshot?.topRightHeaderText;
        if (ocrTopRightText != null && ocrTopRightText.trim().isNotEmpty) {
          localOcrInvoiceNumber =
              _extractInvoiceNumberFromOcrText(ocrTopRightText);
        }
        if ((localOcrInvoiceNumber == null ||
                localOcrInvoiceNumber.trim().isEmpty) &&
            ocrText != null &&
            ocrText.trim().isNotEmpty) {
          localOcrInvoiceNumber = _extractInvoiceNumberFromOcrText(ocrText);
        }
      }

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
  - Preferred labels: Invoice No, Invoice Number, Invoice Ne (OCR typo), Inv No, Inv Nr, Invoice #, Tax Invoice No, Document No, Bill No, Doc Ref.
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

      final parsed = _parseJsonResponse(text, categories);
      if (!parsed.success || parsed.data == null) {
        return parsed;
      }

      var patchedData = parsed.data!;

      // Use local OCR text for numeric fallback only when AI misses paid amount.
      if ((patchedData.paidAmount == null || patchedData.paidAmount! <= 0) &&
          ocrText != null &&
          ocrText.trim().isNotEmpty) {
        final paidFromOcr = _extractPaidAmountByRegex(ocrText);
        if (paidFromOcr != null && paidFromOcr > 0) {
          patchedData = patchedData.copyWith(paidAmount: paidFromOcr);
        } else if (patchedData.gross != null) {
          final balanceDue = _extractBalanceDueByRegex(ocrText);
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
          localOcrInvoiceNumber != null &&
          localOcrInvoiceNumber.trim().isNotEmpty) {
        return ScanResult.success(
          patchedData.copyWith(invoiceNumber: localOcrInvoiceNumber),
        );
      }

      if (patchedData.invoiceNumber == null ||
          patchedData.invoiceNumber!.trim().isEmpty) {
        final fallbackInvoiceNumber = await _extractInvoiceNumberFallback(
          apiKey: settings.apiKey,
          modelName: settings.model,
          imageBytes: imageBytes,
        );
        if (fallbackInvoiceNumber != null && fallbackInvoiceNumber.isNotEmpty) {
          return ScanResult.success(
            patchedData.copyWith(invoiceNumber: fallbackInvoiceNumber),
          );
        }
      }

      return ScanResult.success(patchedData);
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
      String? supplier = cleanNullableString(json['supplier']);
      String? notes = cleanNullableString(json['notes']);
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
      double? vat = parseLooseDouble(json['vat']);
      double? gross = parseLooseDouble(json['gross']);
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
      return ScanResult.failure(
        'Could not parse Gemini response: ${e.toString()}',
      );
    }
  }

  static String? _sanitizeInvoiceNumber(String? value) {
    if (value == null) return null;
    var cleaned = value.trim();
    if (cleaned.isEmpty) return null;
    cleaned = cleaned.replaceAll(RegExp(r'[^A-Za-z0-9\\-_/]'), '');
    if (cleaned.isEmpty) return null;
    if (_containsSensitiveData(cleaned)) return null;
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

    final patterns = <RegExp>[
      RegExp(
        r'(?:invoice|inv)\s*(?:no|ne|nr|num|number|#)\.?\s*[:#-]*\s*([A-Z0-9][A-Z0-9/_-]{4,})',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:tax\s*invoice\s*(?:no|ne|nr|num|number|#)\.?|doc(?:ument)?\s*(?:ref|no|ne|nr|num|number)\.?|bill\s*(?:no|ne|nr|num|number)\.?)\s*[:#-]*\s*([A-Z0-9][A-Z0-9/_-]{4,})',
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
      r'(invoice\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#)|inv\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#)|tax\s*invoice(?:\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#))?|doc(?:ument)?\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|ref)|bill\s*(?:no\.?|ne\.?|nr\.?|num\.?|number))',
      caseSensitive: false,
    );
    final negativeLabelRegex = RegExp(
      r'(vat\s*no|company\s*no|tel|telephone|account\s*no|customer\s*ref|route|pod)',
      caseSensitive: false,
    );
    final sameLineCaptureRegex = RegExp(
      r'(?:invoice\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#)|inv\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#)|tax\s*invoice(?:\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#))?|doc(?:ument)?\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|ref)|bill\s*(?:no\.?|ne\.?|nr\.?|num\.?|number))\s*[:#-]*\s*([A-Z0-9][A-Z0-9 /_-]{3,40})',
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
      r'(?:total\s*to\s*pay|amount\s*paid|paid|card\s*payment|cash\s*payment|visa\s*debit\s*sale|mastercard)\s*[:#-]?\s*(?:gbp|£|Â£)?\s*([0-9]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    );
    final match = paidRegex.firstMatch(normalized);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  static double? _extractBalanceDueByRegex(String text) {
    final normalized = text.replaceAll('\n', ' ');
    final dueRegex = RegExp(
      r'(?:balance\s*due|amount\s*due|outstanding)\s*[:#-]?\s*(?:gbp|£|Â£)?\s*([0-9]+(?:\.[0-9]{1,2})?)',
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
}

class _OcrSnapshot {
  final String fullText;
  final String? topRightHeaderText;

  const _OcrSnapshot({
    required this.fullText,
    this.topRightHeaderText,
  });
}
