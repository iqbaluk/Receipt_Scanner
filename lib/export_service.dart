// ============================================================
// Export Service - CSV / zipped photo export
// ============================================================
// Workflow:
//   1. User picks date range (today / week / month / custom / all)
//   2. We query matching receipts
//   3. Generate CSV file (Category-first column order)
//   4. Open Android share sheet with reliable attachments:
//      CSV-only shares a CSV; photos are bundled in a ZIP.
//   5. User picks OneDrive / WhatsApp / etc.
// ============================================================

import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'database_service.dart';

class ExportRange {
  final DateTime from;
  final DateTime to;
  final String label;
  ExportRange(this.from, this.to, this.label);

  static ExportRange today() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return ExportRange(start, start, 'today');
  }

  static ExportRange thisWeek() {
    final now = DateTime.now();
    final daysFromMonday = now.weekday - 1;
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: daysFromMonday));
    return ExportRange(
        start, DateTime(now.year, now.month, now.day), 'this_week');
  }

  static ExportRange thisMonth() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    return ExportRange(
        start, DateTime(now.year, now.month, now.day), 'this_month');
  }

  static ExportRange lastMonth() {
    final now = DateTime.now();
    final firstOfThisMonth = DateTime(now.year, now.month, 1);
    final lastOfLastMonth = firstOfThisMonth.subtract(const Duration(days: 1));
    final firstOfLastMonth =
        DateTime(lastOfLastMonth.year, lastOfLastMonth.month, 1);
    return ExportRange(firstOfLastMonth, lastOfLastMonth, 'last_month');
  }

  static ExportRange thisYear() {
    final now = DateTime.now();
    return ExportRange(DateTime(now.year, 1, 1), now, 'this_year_${now.year}');
  }

  static ExportRange allTime() {
    return ExportRange(
      DateTime(2000, 1, 1),
      DateTime(2100, 1, 1),
      'all_time',
    );
  }

  static ExportRange custom(DateTime from, DateTime to) {
    final label =
        '${DateFormat('yyyyMMdd').format(from)}_to_${DateFormat('yyyyMMdd').format(to)}';
    return ExportRange(from, to, label);
  }
}

enum ExportContent {
  /// Just the CSV table
  csvOnly,

  /// Just the photos (no CSV)
  photosOnly,

  /// CSV + photos (typical full export)
  both,
}

/// Which date to use when filtering the export range.
enum DateBasis {
  /// The invoice/transaction date (the date on the receipt itself).
  /// Best for accounting / VAT periods.
  invoiceDate,

  /// The scan date (when the receipt was added to the app).
  /// Best for catching backdated entries / "what did I scan this week".
  scanDate,
}

class ExportResult {
  final bool success;
  final int recordCount;
  final int photoCount;
  final String? errorMessage;
  ExportResult.success(this.recordCount, this.photoCount)
      : success = true,
        errorMessage = null;
  ExportResult.failure(this.errorMessage)
      : success = false,
        recordCount = 0,
        photoCount = 0;
}

class ExportService {
  /// Build the export and open the Android share sheet.
  static Future<ExportResult> exportAndShare(
    ExportRange range, {
    ExportContent content = ExportContent.both,
    DateBasis dateBasis = DateBasis.scanDate,
    int? projectId,
    String? projectName,
  }) async {
    try {
      final receipts = dateBasis == DateBasis.scanDate
          ? await DatabaseService.getByScanDateRange(
              range.from,
              range.to,
              projectId: projectId,
            )
          : await DatabaseService.getByDateRange(
              range.from,
              range.to,
              projectId: projectId,
            );

      if (receipts.isEmpty) {
        return ExportResult.failure(
          'No receipts found in the selected range.',
        );
      }

      final filesToShare = <XFile>[];
      String? csvPath;
      var photoCount = 0;

      // ---- CSV ----
      if (content != ExportContent.photosOnly) {
        csvPath = await _buildCsv(
          receipts,
          range,
          dateBasis,
          projectName: projectName,
        );
      }

      if (content == ExportContent.csvOnly) {
        final csvFile = File(csvPath!);
        if (!await csvFile.exists()) {
          return ExportResult.failure('CSV file was not created.');
        }
        filesToShare.add(XFile(csvPath, mimeType: 'text/csv'));
      } else {
        final photoFiles = await _existingPhotoFiles(receipts);
        photoCount = photoFiles.length;
        if (csvPath != null) {
          final csvFile = File(csvPath);
          if (await csvFile.exists()) {
            filesToShare.add(XFile(csvPath, mimeType: 'text/csv'));
          }
        }
        if (photoFiles.isEmpty) {
          if (content == ExportContent.photosOnly) {
            return ExportResult.failure(
              'No saved receipt photos found in the selected range.',
            );
          }
        } else {
          final zipPath = await _buildZip(
            photoFiles,
            range,
            dateBasis,
            projectName: projectName,
          );
          final zipFile = File(zipPath);
          if (!await zipFile.exists()) {
            return ExportResult.failure('Photo ZIP file was not created.');
          }
          filesToShare.add(XFile(zipPath, mimeType: 'application/zip'));
        }
      }

      if (filesToShare.isEmpty) {
        return ExportResult.failure(
            'Nothing to export — no CSV or photos prepared.');
      }

      // ---- Open share sheet ----
      final result = await Share.shareXFiles(
        filesToShare,
        subject: 'Receipt export - ${_friendlyLabel(range)}',
      );

      if (result.status == ShareResultStatus.unavailable) {
        return ExportResult.failure('Sharing not available on this device.');
      }

      return ExportResult.success(receipts.length, photoCount);
    } catch (e) {
      return ExportResult.failure('Export failed: ${e.toString()}');
    }
  }

  /// Build a CSV file in the app's temp directory and return its path.
  /// Filename: receipts_<range_label>_<basis>_<timestamp>.csv
  static Future<String> _buildCsv(
    List<Receipt> receipts,
    ExportRange range,
    DateBasis basis, {
    String? projectName,
  }) async {
    final csv = StringBuffer();

    // Column order: Category before Supplier (for filtering),
    // BOTH dates included so accountant sees the full picture.
    csv.writeln(
      'ScanNo,InvoiceNo,Category,InvoiceDate,ScanDate,Supplier,Net,VAT,Gross,Notes,PhotoFile',
    );

    for (final r in receipts) {
      final photoFile = r.photoPath != null ? p.basename(r.photoPath!) : '';
      csv.writeln([
        (r.scanNo ?? 0).toString().padLeft(5, '0'),
        _csvEscape(r.invoiceNumber ?? ''),
        _csvEscape(r.category),
        Receipt.formatDate(r.date),
        Receipt.formatDate(r.createdAt),
        _csvEscape(r.supplier),
        r.net.toStringAsFixed(2),
        r.vat.toStringAsFixed(2),
        r.gross.toStringAsFixed(2),
        _csvEscape(r.notes ?? ''),
        _csvEscape(photoFile),
      ].join(','));
    }

    final exportDir = await _exportDir();
    final ts = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final basisTag = basis == DateBasis.scanDate ? 'byScan' : 'byInvoice';
    final projectTag = projectName == null ? null : _filenameTag(projectName);
    final filenameBase = [
      'receipts',
      if (projectTag != null) projectTag,
      range.label,
      basisTag,
      ts,
    ].join('_');
    final csvPath = p.join(
      exportDir.path,
      '$filenameBase.csv',
    );
    await File(csvPath).writeAsString(csv.toString());
    return csvPath;
  }

  static Future<List<File>> _existingPhotoFiles(List<Receipt> receipts) async {
    final files = <File>[];
    for (final r in receipts) {
      final photoPath = r.photoPath;
      if (photoPath == null || photoPath.trim().isEmpty) continue;
      final file = File(photoPath);
      if (await file.exists()) {
        files.add(file);
      }
    }
    return files;
  }

  static Future<String> _buildZip(
    List<File> photoFiles,
    ExportRange range,
    DateBasis basis, {
    String? projectName,
  }) async {
    final exportDir = await _exportDir();
    final ts = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final basisTag = basis == DateBasis.scanDate ? 'byScan' : 'byInvoice';
    final projectTag = projectName == null ? null : _filenameTag(projectName);
    final filenameBase = [
      'receipt_export',
      if (projectTag != null) projectTag,
      range.label,
      basisTag,
      ts,
    ].join('_');
    final zipPath = p.join(exportDir.path, '$filenameBase.zip');

    final usedNames = <String>{};
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    try {
      for (final file in photoFiles) {
        await encoder.addFile(
          file,
          _uniqueZipEntryName('photos/${p.basename(file.path)}', usedNames),
        );
      }
    } finally {
      await encoder.close();
    }
    return zipPath;
  }

  static String _uniqueZipEntryName(String name, Set<String> usedNames) {
    final normalized = name.replaceAll('\\', '/');
    if (usedNames.add(normalized)) return normalized;

    final dir = p.posix.dirname(normalized);
    final basename = p.posix.basenameWithoutExtension(normalized);
    final extension = p.posix.extension(normalized);
    var counter = 2;
    while (true) {
      final nextBase = '$basename-$counter$extension';
      final next = dir == '.' ? nextBase : '$dir/$nextBase';
      if (usedNames.add(next)) return next;
      counter++;
    }
  }

  static Future<Directory> _exportDir() async {
    final tempDir = await getTemporaryDirectory();
    final exportDir = Directory(p.join(tempDir.path, 'exports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    return exportDir;
  }

  static String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static String _friendlyLabel(ExportRange r) {
    switch (r.label) {
      case 'today':
        return 'Today (${DateFormat('dd MMM yyyy').format(r.from)})';
      case 'this_week':
        return 'This week';
      case 'this_month':
        return DateFormat('MMMM yyyy').format(r.from);
      case 'last_month':
        return DateFormat('MMMM yyyy').format(r.from);
      case 'all_time':
        return 'All receipts';
      default:
        if (r.label.startsWith('this_year')) {
          return 'Year ${r.from.year}';
        }
        return '${DateFormat('dd/MM/yy').format(r.from)} - ${DateFormat('dd/MM/yy').format(r.to)}';
    }
  }

  static String _filenameTag(String value) {
    var tag = value.trim().replaceAll('&', 'and');
    tag = tag.replaceAll(RegExp(r'[<>:"/\\|?*]'), '');
    tag = tag.replaceAll(RegExp(r'\s+'), '');
    tag = tag.replaceAll(RegExp(r'[^A-Za-z0-9\-.]'), '');
    if (tag.isEmpty) return 'project';
    if (tag.length > 30) return tag.substring(0, 30);
    return tag;
  }
}
