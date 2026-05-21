// ============================================================
// Receipt Scanner - Final Version (Steps 1-4 with smart filenames)
// ============================================================
// - Manual entry always works
// - Photo capture (camera or gallery) is optional
// - Gemini scan auto-fills fields with graceful failure handling
// - Save persists to local SQLite + smart-named photo file
// - Recent Entries with detail view (edit/delete)
// - Export menu sends CSV + photos via Android share sheet
//   (OneDrive, WhatsApp, Gmail, Drive, anything you have installed)
// ============================================================

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'database_service.dart';
import 'export_service.dart';
import 'gemini_service.dart';
import 'utils/ai_extraction_helpers.dart';
import 'utils/text_normalizers.dart';

part 'pages/splash_page.dart';
part 'pages/project_list_page.dart';
part 'pages/receipt_entry_page.dart';
part 'pages/receipt_entry/receipt_entry_save_controller.dart';
part 'pages/receipt_entry/receipt_entry_duplicate_dialogs.dart';
part 'pages/receipt_entry/receipt_entry_scan_controller.dart';
part 'pages/category_manager_page.dart';
part 'pages/gemini_settings_page.dart';
part 'pages/receipt_history_page.dart';
part 'pages/reports_hub_page.dart';
part 'pages/project_report_page.dart';
part 'pages/combined_report_page.dart';
part 'pages/monthly_activity_report_page.dart';
part 'utils/helpers.dart';
part 'pages/receipt_detail_page.dart';
part 'pages/settings_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('Could not load .env file: $e');
  }
  runApp(const ReceiptScannerApp());
}

class ReceiptScannerApp extends StatelessWidget {
  const ReceiptScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF0F766E),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFD2F0EB),
      onPrimaryContainer: Color(0xFF032C28),
      secondary: Color(0xFFC2410C),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFFFE1D2),
      onSecondaryContainer: Color(0xFF3F1300),
      tertiary: Color(0xFF0E7490),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFD4F0F8),
      onTertiaryContainer: Color(0xFF0A2B35),
      error: Color(0xFFB42318),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Color(0xFFFCFEFD),
      onSurface: Color(0xFF0F172A),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF2F7F7),
      surfaceContainer: Color(0xFFE8F2F2),
      surfaceContainerHigh: Color(0xFFDDEBEC),
      surfaceContainerHighest: Color(0xFFD2E3E4),
      onSurfaceVariant: Color(0xFF334155),
      outline: Color(0xFF64748B),
      outlineVariant: Color(0xFFCBD5E1),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF111827),
      onInverseSurface: Color(0xFFF1F5F9),
      inversePrimary: Color(0xFF71D1C8),
    );
    final textTheme = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
    ).textTheme.apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
          fontFamily: 'Roboto',
        );

    return MaterialApp(
      title: 'Receipt Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: colorScheme.surfaceContainerLow,
        textTheme: textTheme.copyWith(
          titleLarge: textTheme.titleLarge?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
          titleMedium: textTheme.titleMedium?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
          bodyLarge: textTheme.bodyLarge?.copyWith(
            fontSize: 16,
            height: 1.35,
            color: colorScheme.onSurface,
          ),
          bodyMedium: textTheme.bodyMedium?.copyWith(
            fontSize: 14.5,
            height: 1.35,
            color: colorScheme.onSurface,
          ),
          labelLarge: textTheme.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          centerTitle: false,
          elevation: 0.5,
          scrolledUnderElevation: 1.2,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: colorScheme.onPrimary,
          ),
          iconTheme: IconThemeData(color: colorScheme.onPrimary),
        ),
        cardTheme: CardThemeData(
          color: colorScheme.surfaceContainerLowest,
          elevation: 0.6,
          shadowColor: colorScheme.shadow.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colorScheme.surfaceContainerLowest,
          labelStyle: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
          hintStyle: TextStyle(color: colorScheme.outline),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colorScheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colorScheme.error, width: 1.4),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.primary,
            side: BorderSide(color: colorScheme.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: colorScheme.surfaceContainerLowest,
          textStyle: TextStyle(color: colorScheme.onSurface, fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titleTextStyle: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
          contentTextStyle: TextStyle(
            fontSize: 15,
            color: colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        dividerTheme: DividerThemeData(
          space: 0,
          thickness: 1,
          color: colorScheme.outlineVariant,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: colorScheme.tertiary,
          foregroundColor: colorScheme.onTertiary,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: colorScheme.inverseSurface,
          contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      home: const StartupSplashPage(),
    );
  }
}

void goToHomePage(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const ProjectListPage()),
    (route) => false,
  );
}

Widget buildPageTitleBanner(
  BuildContext context, {
  required String title,
  required IconData icon,
  bool useLogo = true,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      gradient: AppDecor.heroGradient(colorScheme),
      borderRadius: BorderRadius.circular(16),
      boxShadow: AppDecor.softShadow(colorScheme),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: colorScheme.onPrimary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: useLogo
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/app_logo.png',
                      fit: BoxFit.cover,
                    ),
                  )
                : Icon(icon, color: colorScheme.onPrimary),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ],
    ),
  );
}

Future<void> openInAppPrintPreview(
  BuildContext context, {
  required String title,
  required String fileName,
  required Uint8List pdfBytes,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _InAppPrintPreviewPage(
        title: title,
        fileName: fileName,
        pdfBytes: pdfBytes,
      ),
    ),
  );
}

class _InAppPrintPreviewPage extends StatefulWidget {
  final String title;
  final String fileName;
  final Uint8List pdfBytes;

  const _InAppPrintPreviewPage({
    required this.title,
    required this.fileName,
    required this.pdfBytes,
  });

  @override
  State<_InAppPrintPreviewPage> createState() => _InAppPrintPreviewPageState();
}

class _InAppPrintPreviewPageState extends State<_InAppPrintPreviewPage> {
  bool _printing = false;

  Future<void> _directPrint() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      final printer = await Printing.pickPrinter(context: context);
      if (printer == null) return;
      final printed = await Printing.directPrintPdf(
        printer: printer,
        name: widget.fileName,
        onLayout: (_) async => widget.pdfBytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(printed ? 'Print job sent.' : 'Print not completed.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close preview',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Print',
            onPressed: _printing ? null : _directPrint,
            icon: _printing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_outlined),
          ),
        ],
      ),
      body: PdfPreview(
        allowPrinting: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        pdfFileName: widget.fileName,
        build: (_) async => widget.pdfBytes,
      ),
    );
  }
}

class AppDecor {
  static LinearGradient heroGradient(ColorScheme colorScheme) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        colorScheme.primary,
        Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.45)!,
        colorScheme.tertiary,
      ],
    );
  }

  static List<BoxShadow> softShadow(ColorScheme colorScheme) {
    return [
      BoxShadow(
        color: colorScheme.shadow.withValues(alpha: 0.08),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ];
  }
}
