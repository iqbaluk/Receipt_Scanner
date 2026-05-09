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
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'database_service.dart';
import 'export_service.dart';
import 'gemini_service.dart';
import 'utils/text_normalizers.dart';


part 'pages/splash_page.dart';
part 'pages/project_list_page.dart';
part 'pages/receipt_entry_page.dart';
part 'pages/category_manager_page.dart';
part 'pages/gemini_settings_page.dart';
part 'pages/receipt_history_page.dart';
part 'pages/project_report_page.dart';
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
      primary: Color(0xFF006D77),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFA7F3EF),
      onPrimaryContainer: Color(0xFF00363B),
      secondary: Color(0xFF6D5BD0),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFE8E2FF),
      onSecondaryContainer: Color(0xFF24145F),
      tertiary: Color(0xFFB45309),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFFFDDB5),
      onTertiaryContainer: Color(0xFF3D1E00),
      error: Color(0xFFB3261E),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Color(0xFFFBFCFA),
      onSurface: Color(0xFF132022),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF0F7F6),
      surfaceContainer: Color(0xFFE7F0EF),
      surfaceContainerHigh: Color(0xFFDCE9E7),
      surfaceContainerHighest: Color(0xFFD0E0DE),
      onSurfaceVariant: Color(0xFF33474B),
      outline: Color(0xFF60777A),
      outlineVariant: Color(0xFFC0D1D2),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF253234),
      onInverseSurface: Color(0xFFEAF2F1),
      inversePrimary: Color(0xFF7DDAD6),
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
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 1,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: colorScheme.onPrimaryContainer,
          ),
          iconTheme: IconThemeData(color: colorScheme.onPrimaryContainer),
        ),
        cardTheme: CardThemeData(
          color: colorScheme.surfaceContainerLowest,
          elevation: 1,
          shadowColor: colorScheme.shadow.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
