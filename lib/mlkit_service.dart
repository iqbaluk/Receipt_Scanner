import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'gemini_service.dart';

class MlKitService {
  static Future<MlKitScanPreview> scanReceiptFromPath(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return const MlKitScanPreview.failure('Image file not found.');
      }

      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final recognizedText = await recognizer.processImage(inputImage);
        final lines = recognizedText.text
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        if (lines.isEmpty) {
          return const MlKitScanPreview.failure('No text found in image.');
        }

        final date = _extractDate(lines);
        final invoiceNumber = _extractInvoiceNumber(lines);
        final supplier = _extractSupplier(lines);
        final vat = _extractAmountByKeyword(lines, ['vat']);
        final gross = _extractAmountByKeyword(lines,
            ['gross', 'total', 'amount due', 'invoice total', 'grand total']);
        double? net = _extractAmountByKeyword(lines, ['net', 'subtotal']);
        if (net == null && gross != null && vat != null) {
          net = gross - vat;
        }

        return MlKitScanPreview.success(
          data: ReceiptData(
            date: date,
            invoiceNumber: invoiceNumber,
            supplier: supplier,
            vat: vat,
            gross: gross,
            net: net,
            rawNotes: lines.take(8).join(' | '),
          ),
          rawText: recognizedText.text,
        );
      } finally {
        await recognizer.close();
      }
    } catch (e) {
      return MlKitScanPreview.failure('ML Kit scan failed: $e');
    }
  }

  static DateTime? _extractDate(List<String> lines) {
    final dateRegex = RegExp(r'(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})');
    for (final line in lines) {
      for (final match in dateRegex.allMatches(line)) {
        final day = int.tryParse(match.group(1)!);
        final month = int.tryParse(match.group(2)!);
        var year = int.tryParse(match.group(3)!);
        if (day == null || month == null || year == null) continue;
        if (year < 100) year += 2000;
        if (month < 1 || month > 12 || day < 1 || day > 31) continue;
        try {
          return DateTime(year, month, day);
        } catch (_) {}
      }
    }
    return null;
  }

  static String? _extractInvoiceNumber(List<String> lines) {
    final invoiceRegex = RegExp(
      r'(invoice|inv|receipt)\s*(no|number|#)?\s*[:\-]?\s*([A-Z0-9][A-Z0-9\-\/]{2,})',
      caseSensitive: false,
    );
    for (final line in lines) {
      final match = invoiceRegex.firstMatch(line);
      if (match != null) {
        final value = (match.group(3) ?? '').trim();
        if (value.isNotEmpty) return value.toUpperCase();
      }
    }
    return null;
  }

  static String? _extractSupplier(List<String> lines) {
    const blocked = [
      'invoice',
      'receipt',
      'vat',
      'gross',
      'net',
      'total',
      'subtotal',
      'date',
      'amount',
      'thank you',
      'card',
      'cash',
    ];
    for (final line in lines.take(15)) {
      final lower = line.toLowerCase();
      if (lower.length < 3) continue;
      if (blocked.any(lower.contains)) continue;
      if (RegExp(r'^\d+$').hasMatch(lower)) continue;
      return line;
    }
    return null;
  }

  static double? _extractAmountByKeyword(
      List<String> lines, List<String> keywords) {
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (!keywords.any(lower.contains)) continue;
      final amount = _lastAmount(line);
      if (amount != null) return amount;
    }
    return null;
  }

  static double? _lastAmount(String line) {
    final regex =
        RegExp(r'[-+]?\d{1,3}(?:,\d{3})*(?:\.\d{2})|[-+]?\d+(?:\.\d{2})');
    final matches = regex.allMatches(line).toList();
    if (matches.isEmpty) return null;
    final value = matches.last.group(0);
    if (value == null) return null;
    return double.tryParse(value.replaceAll(',', ''));
  }
}

class MlKitScanPreview {
  final bool success;
  final ReceiptData? data;
  final String? rawText;
  final String? errorMessage;

  const MlKitScanPreview.success({
    required this.data,
    required this.rawText,
  })  : success = true,
        errorMessage = null;

  const MlKitScanPreview.failure(this.errorMessage)
      : success = false,
        data = null,
        rawText = null;
}
