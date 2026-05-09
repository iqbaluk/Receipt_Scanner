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
import 'deepseek_service.dart';
import 'export_service.dart';
import 'gemini_service.dart';
import 'mlkit_service.dart';

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

class StartupSplashPage extends StatefulWidget {
  const StartupSplashPage({super.key});

  @override
  State<StartupSplashPage> createState() => _StartupSplashPageState();
}

class _StartupSplashPageState extends State<StartupSplashPage> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ProjectListPage()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.primary,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: colorScheme.onPrimary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: colorScheme.onPrimary.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Icon(
                    Icons.receipt_long,
                    size: 46,
                    color: colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Receipt Scanner',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 34),
                SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProjectListPage extends StatefulWidget {
  const ProjectListPage({super.key});

  @override
  State<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends State<ProjectListPage> {
  List<Project> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() => _loading = true);
    try {
      final projects = await DatabaseService.getProjects();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load projects: $e')),
      );
    }
  }

  Future<void> _openProject(Project project) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptEntryPage(project: project),
      ),
    );
    await _loadProjects();
  }

  Future<void> _openAllHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ReceiptHistoryPage(),
      ),
    );
    await _loadProjects();
  }

  Future<void> _openHistoryFor(Project project) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptHistoryPage(project: project),
      ),
    );
    await _loadProjects();
  }

  Future<void> _openReports(Project project) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectReportPage(project: project),
      ),
    );
    await _loadProjects();
  }

  Future<void> _openCategories() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CategoryManagerPage(),
      ),
    );
  }

  Future<void> _openGeminiSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const GeminiSettingsPage(),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SettingsPage(),
      ),
    );
    await _loadProjects();
  }

  Future<void> _createProjectFromDialog() async {
    final name = TextEditingController();
    final address = TextEditingController();
    final budget = TextEditingController();
    final notes = TextEditingController();

    final draft = await showDialog<Project>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create project'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Project name *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: address,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: budget,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Budget',
                  prefixText: '£ ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmedName = name.text.trim();
              if (trimmedName.isEmpty) return;
              Navigator.pop(
                ctx,
                Project(
                  name: trimmedName,
                  address:
                      address.text.trim().isEmpty ? null : address.text.trim(),
                  budget: double.tryParse(budget.text),
                  notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                ),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      address.dispose();
      budget.dispose();
      notes.dispose();
    });

    if (draft == null) return;
    try {
      final created = await DatabaseService.createProject(draft);
      if (!mounted) return;
      await _loadProjects();
      if (!mounted) return;
      await _openProject(created);
    } catch (e) {
      _showProjectMessage('Could not create project: $e');
    }
  }

  Future<Project?> _showProjectEditDialog(Project project) async {
    final name = TextEditingController(text: project.name);
    final address = TextEditingController(text: project.address ?? '');
    final budget = TextEditingController(
      text: project.budget == null ? '' : project.budget!.toStringAsFixed(2),
    );
    final notes = TextEditingController(text: project.notes ?? '');

    final result = await showDialog<Project>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit project'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Project name *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: address,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: budget,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Budget',
                  prefixText: '£ ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmedName = name.text.trim();
              if (trimmedName.isEmpty) return;
              Navigator.pop(
                ctx,
                Project(
                  id: project.id,
                  name: trimmedName,
                  address:
                      address.text.trim().isEmpty ? null : address.text.trim(),
                  budget: double.tryParse(budget.text),
                  notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                  createdAt: project.createdAt,
                  updatedAt: project.updatedAt,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      address.dispose();
      budget.dispose();
      notes.dispose();
    });
    return result;
  }

  Future<void> _editProject(Project project) async {
    final updated = await _showProjectEditDialog(project);
    if (updated == null) return;
    try {
      await DatabaseService.updateProject(updated);
      if (!mounted) return;
      await _loadProjects();
    } catch (e) {
      _showProjectMessage('Could not update project: $e');
    }
  }

  Future<void> _deleteProject(Project project) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text(
          'Delete "${project.name}"?\n\nProjects with saved receipts cannot be deleted until their receipts are removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DatabaseService.deleteProject(project);
      if (!mounted) return;
      await _loadProjects();
    } catch (e) {
      _showProjectMessage(e.toString().replaceFirst('Bad state: ', ''));
    }
  }

  void _showProjectMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(
            onPressed: _openAllHistory,
            icon: const Icon(Icons.manage_search),
            tooltip: 'Invoice list',
          ),
          IconButton(
            onPressed: _openCategories,
            icon: const Icon(Icons.category),
            tooltip: 'Categories',
          ),
          PopupMenuButton<String>(
            tooltip: 'Project actions',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'create':
                  _createProjectFromDialog();
                  break;
                case 'gemini_settings':
                  _openGeminiSettings();
                  break;
                case 'settings':
                  _openSettings();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'create',
                child: ListTile(
                  leading: Icon(Icons.add),
                  title: Text('Create project'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'gemini_settings',
                child: ListTile(
                  leading: Icon(Icons.auto_awesome),
                  title: Text('Gemini settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Management'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _projects.isEmpty
                ? _buildEmptyState()
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        'Tap a project to start scanning receipts',
                        style: TextStyle(
                          fontSize: 15,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final project in _projects)
                            _ProjectCard(
                              project: project,
                              onTap: () => _openProject(project),
                              onEdit: () => _editProject(project),
                              onDelete: () => _deleteProject(project),
                              onHistory: () => _openHistoryFor(project),
                              onReports: () => _openReports(project),
                            ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 72, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'No projects yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first project to start\nscanning and tracking receipts.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.outline),
          ),
          const SizedBox(height: 8),
          Text(
            'Use Project actions to create one.',
            style: TextStyle(color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onHistory;
  final VoidCallback? onReports;

  const _ProjectCard({
    required this.project,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onHistory,
    this.onReports,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accents = [
      colorScheme.primary,
      colorScheme.secondary,
      colorScheme.tertiary,
      const Color(0xFF0E7490),
      const Color(0xFF7C3AED),
    ];
    final accent =
        accents[(project.id ?? project.name.length) % accents.length];
    final budget = project.budget;
    final total = project.totalGross;
    final subtitle = [
      if (project.address != null) project.address!,
      '${project.receiptCount} receipts',
      if (budget != null) '£${budget.toStringAsFixed(2)} budget',
    ].join(' · ');

    return SizedBox(
      width: 220,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 5,
                  width: 54,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        project.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Project actions',
                      icon: Icon(Icons.more_vert,
                          size: 20, color: colorScheme.outline),
                      onSelected: (value) {
                        switch (value) {
                          case 'history':
                            onHistory?.call();
                            break;
                          case 'reports':
                            onReports?.call();
                            break;
                          case 'edit':
                            onEdit?.call();
                            break;
                          case 'delete':
                            onDelete?.call();
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'history',
                          child: ListTile(
                            leading: Icon(Icons.receipt_long),
                            title: Text('Invoice List'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'reports',
                          child: ListTile(
                            leading: Icon(Icons.bar_chart),
                            title: Text('Reports'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.edit),
                            title: Text('Edit'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete_outline,
                                color: colorScheme.error),
                            title: Text('Delete',
                                style: TextStyle(color: colorScheme.error)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  '£${total.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'TOTAL AMOUNT',
                  style: TextStyle(
                    letterSpacing: 1.2,
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReceiptEntryPage extends StatefulWidget {
  final Project project;

  const ReceiptEntryPage({super.key, required this.project});

  @override
  State<ReceiptEntryPage> createState() => _ReceiptEntryPageState();
}

class _ReceiptEntryPageState extends State<ReceiptEntryPage> {
  final _formKey = GlobalKey<FormState>();

  DateTime? _selectedDate;
  final _invoiceNumberController = TextEditingController();
  final _supplierController = TextEditingController();
  String? _selectedCategory;
  final _vatController = TextEditingController();
  final _grossController = TextEditingController();
  final _netController = TextEditingController();
  final _notesController = TextEditingController();

  Uint8List? _imageBytes;
  String? _imageFileName;
  String? _imagePath;

  bool _isScanning = false;
  bool _isSaving = false;
  double? _lastCategoryConfidence;
  bool _categoryNeedsReview = false;
  bool _categoryReviewConfirmed = false;

  String? _statusMessage;
  bool _statusIsError = false;

  final ImagePicker _picker = ImagePicker();

  List<Receipt> _recentReceipts = [];
  List<String> _categories = DatabaseService.defaultCategories;
  int _totalReceiptCount = 0;

  @override
  void initState() {
    super.initState();
    _grossController.addListener(_recalculateNet);
    _vatController.addListener(_recalculateNet);
    _loadCategories();
    _loadRecent();
  }

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _supplierController.dispose();
    _vatController.dispose();
    _grossController.dispose();
    _netController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final today = DateTime.now();
      final dayStart = DateTime(today.year, today.month, today.day);
      final todayReceipts = await DatabaseService.getByScanDateRange(
        dayStart,
        dayStart,
        projectId: widget.project.id,
      );
      if (!mounted) return;
      setState(() {
        _recentReceipts = todayReceipts;
        _totalReceiptCount = todayReceipts.length;
      });
    } catch (e) {
      debugPrint('Failed to load recent: $e');
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await DatabaseService.getCategories();
      final latest = await DatabaseService.getRecent(
        limit: 1,
        projectId: widget.project.id,
      );
      final lastSavedCategory = latest.isEmpty ? null : latest.first.category;
      if (!mounted) return;
      setState(() {
        _categories = categories.map((c) => c.name).toList();
        if (_selectedCategory == null &&
            lastSavedCategory != null &&
            _categories.contains(lastSavedCategory)) {
          _selectedCategory = lastSavedCategory;
        } else if (_selectedCategory != null &&
            !_categories.contains(_selectedCategory)) {
          _selectedCategory = null;
        }
      });
    } catch (e) {
      debugPrint('Failed to load categories: $e');
    }
  }

  void _recalculateNet() {
    final gross = double.tryParse(_grossController.text) ?? 0;
    final vat = double.tryParse(_vatController.text) ?? 0;
    final net = gross - vat;
    if (gross > 0) {
      _netController.text = net.toStringAsFixed(2);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  void _showStatus(String message, {bool isError = false, Duration? duration}) {
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
    Future.delayed(duration ?? const Duration(seconds: 4), () {
      if (mounted && _statusMessage == message) {
        setState(() => _statusMessage = null);
      }
    });
  }

  // ---- Image picking ----

  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (photo != null) await _setImage(photo);
    } catch (e) {
      _showStatus('Could not access camera: $e', isError: true);
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (photo != null) await _setImage(photo);
    } catch (e) {
      _showStatus('Could not pick image: $e', isError: true);
    }
  }

  Future<void> _setImage(XFile file) async {
    final bytes = await file.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageFileName = file.name;
      _imagePath = file.path;
    });
    _showStatus(
      'Image loaded. You can scan with Gemini or ML Kit.',
    );
  }

  void _removeImage() {
    setState(() {
      _imageBytes = null;
      _imageFileName = null;
      _imagePath = null;
    });
  }

  // ---- Gemini scan ----

  Future<void> _scanWithGemini() async {
    if (_imageBytes == null) {
      _showStatus(
        'Please add a photo first using Take Photo or Gallery.',
        isError: true,
      );
      return;
    }

    final hasGeminiSettings = await GeminiService.hasUsableSettings();
    if (!hasGeminiSettings) {
      _showStatus(
        'Gemini API key not set. Open Project actions > Gemini settings. Manual entry still works.',
        isError: true,
        duration: const Duration(seconds: 6),
      );
      return;
    }

    final hasManualData = _invoiceNumberController.text.isNotEmpty ||
        _supplierController.text.isNotEmpty ||
        _selectedCategory != null ||
        _vatController.text.isNotEmpty ||
        _grossController.text.isNotEmpty;

    bool mergeOnly = false;
    if (hasManualData) {
      final choice = await _askOverwriteChoice();
      if (choice == null) return;
      if (choice == 'merge') mergeOnly = true;
    }

    setState(() => _isScanning = true);
    final result = await GeminiService.scanReceipt(
      _imageBytes!,
      allowedCategories: _categories,
    );
    if (!mounted) return;
    setState(() => _isScanning = false);

    if (!result.success) {
      _showStatus(
        'Auto-scan unavailable ? please enter manually. (${result.errorMessage})',
        isError: true,
        duration: const Duration(seconds: 6),
      );
      return;
    }

    _applyScanData(result.data!, mergeOnly: mergeOnly);
    _showStatus(
      'Scan complete. Please select category, then review fields before saving.',
    );
  }

  Future<void> _scanWithMlKit() async {
    if (_imagePath == null || _imagePath!.trim().isEmpty) {
      _showStatus(
        'Please add a photo first using Take Photo or Gallery.',
        isError: true,
      );
      return;
    }
    final hasDeepSeekSettings = await DeepSeekService.hasUsableSettings();
    if (!hasDeepSeekSettings) {
      _showStatus(
        'DeepSeek API key not set. Open Management > DeepSeek API Settings.',
        isError: true,
        duration: const Duration(seconds: 6),
      );
      return;
    }

    final hasManualData = _invoiceNumberController.text.isNotEmpty ||
        _supplierController.text.isNotEmpty ||
        _selectedCategory != null ||
        _vatController.text.isNotEmpty ||
        _grossController.text.isNotEmpty ||
        _selectedDate != null;

    bool mergeOnly = false;
    if (hasManualData) {
      final choice = await _askOverwriteChoice();
      if (choice == null) return;
      if (choice == 'merge') mergeOnly = true;
    }

    setState(() => _isScanning = true);
    final ocr = await MlKitService.scanReceiptFromPath(_imagePath!);
    if (!mounted) return;
    if (!ocr.success || (ocr.rawText ?? '').trim().isEmpty) {
      setState(() => _isScanning = false);
      _showStatus(
        'ML Kit OCR could not read enough text. Please enter manually. '
        '(${ocr.errorMessage ?? "No text"})',
        isError: true,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    final parsed = await DeepSeekService.parseOcrText(
      ocr.rawText!,
      allowedCategories: _categories,
    );
    if (!mounted) return;
    setState(() => _isScanning = false);

    if (!parsed.success || parsed.data == null) {
      _showStatus(
        'DeepSeek parse failed. Please enter manually. '
        '(${parsed.errorMessage ?? "No data"})',
        isError: true,
        duration: const Duration(seconds: 6),
      );
      return;
    }

    final useData = await _showMlKitPreviewDialog(
      rawText: ocr.rawText!,
      data: parsed.data!,
    );
    if (useData != true) return;

    _applyScanData(parsed.data!, mergeOnly: mergeOnly);
    _showStatus(
      'ML Kit OCR + DeepSeek parse applied. Please select category, then review and fill missing fields manually.',
      duration: const Duration(seconds: 6),
    );
  }

  Future<bool?> _showMlKitPreviewDialog({
    required String rawText,
    required ReceiptData data,
  }) async {
    final cleanedRawText = rawText.trim();
    final extracted = <String>[
      'Date: ${data.date == null ? "-" : DateFormat('dd/MM/yyyy').format(data.date!)}',
      'Invoice no: ${data.invoiceNumber?.trim().isNotEmpty == true ? data.invoiceNumber!.trim() : "-"}',
      'Category: ${data.category?.trim().isNotEmpty == true ? data.category!.trim() : "-"}',
      'Category confidence: ${data.categoryConfidence == null ? "-" : "${data.categoryConfidence!.toStringAsFixed(0)}%"}',
      'Supplier: ${data.supplier?.trim().isNotEmpty == true ? data.supplier!.trim() : "-"}',
      'VAT: ${data.vat == null ? "-" : data.vat!.toStringAsFixed(2)}',
      'Gross: ${data.gross == null ? "-" : data.gross!.toStringAsFixed(2)}',
      'Net: ${data.net == null ? "-" : data.net!.toStringAsFixed(2)}',
    ];

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ML Kit + DeepSeek Preview'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Extracted fields',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                for (final line in extracted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(line),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Raw OCR text',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                      cleanedRawText.isEmpty ? '-' : cleanedRawText),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: cleanedRawText));
              Navigator.pop(ctx, false);
              _showStatus('OCR text copied to clipboard.');
            },
            child: const Text('Copy text'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Use this data'),
          ),
        ],
      ),
    );
  }

  Future<String?> _askOverwriteChoice() async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Existing entries detected'),
        content: const Text(
          'You have already typed values into the form. How should the scan results be applied?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'merge'),
              child: const Text('Fill empty fields only')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'replace'),
              child: const Text('Replace all')),
        ],
      ),
    );
  }

  void _applyScanData(ReceiptData data, {required bool mergeOnly}) {
    setState(() {
      _lastCategoryConfidence = null;
      _categoryNeedsReview = false;
      _categoryReviewConfirmed = true;
      if (data.date != null && (!mergeOnly || _isDateUntouched())) {
        _selectedDate = data.date!;
      }
      if (data.invoiceNumber != null &&
          (!mergeOnly || _invoiceNumberController.text.isEmpty)) {
        _invoiceNumberController.text = data.invoiceNumber!;
      }
      if (data.supplier != null &&
          (!mergeOnly || _supplierController.text.isEmpty)) {
        _supplierController.text = data.supplier!;
      }
      if (data.vat != null && (!mergeOnly || _vatController.text.isEmpty)) {
        _vatController.text = data.vat!.toStringAsFixed(2);
      }
      if (data.gross != null && (!mergeOnly || _grossController.text.isEmpty)) {
        _grossController.text = data.gross!.toStringAsFixed(2);
      }
      if (data.net != null &&
          data.gross == null &&
          (!mergeOnly || _netController.text.isEmpty)) {
        _netController.text = data.net!.toStringAsFixed(2);
      }
      if (data.rawNotes != null &&
          (!mergeOnly || _notesController.text.isEmpty)) {
        _notesController.text = data.rawNotes!;
      }
    });
  }

  Future<bool> _confirmLowCategoryConfidenceBeforeSave() async {
    final confidence = _lastCategoryConfidence;
    if (!_categoryNeedsReview ||
        _categoryReviewConfirmed ||
        confidence == null) {
      return true;
    }
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.category, color: Theme.of(ctx).colorScheme.primary),
        title: const Text('Recheck category'),
        content: Text(
          'AI category confidence is ${confidence.toStringAsFixed(0)}% (below 85%). '
          'Please verify category before saving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('I Checked'),
          ),
        ],
      ),
    );
    if (approved == true && mounted) {
      setState(() => _categoryReviewConfirmed = true);
      return true;
    }
    return false;
  }

  bool _isDateUntouched() {
    return _selectedDate == null;
  }

  List<String> _missingRequiredFields() {
    final missing = <String>[];
    if (_selectedDate == null) missing.add('Invoice date');
    if (_selectedCategory == null) missing.add('Category');
    if (_supplierController.text.trim().isEmpty) missing.add('Supplier');
    final grossText = _grossController.text.trim();
    if (grossText.isEmpty) {
      missing.add('Gross amount');
    } else if (double.tryParse(grossText) == null) {
      missing.add('Gross amount (valid number)');
    }
    return missing;
  }

  // ---- Save ----

  Future<void> _saveRecord() async {
    final missing = _missingRequiredFields();
    if (missing.isNotEmpty) {
      _formKey.currentState!.validate();
      _showStatus(
        'Please add manually: ${missing.join(', ')}.',
        isError: true,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) {
      _showStatus('Please fix the errors above', isError: true);
      return;
    }
    final canProceed = await _confirmLowCategoryConfidenceBeforeSave();
    if (!canProceed) return;

    final supplier = _supplierController.text.trim();
    final invoiceNumber = _invoiceNumberController.text.trim();
    final gross = double.tryParse(_grossController.text) ?? 0;
    final invoiceDate = _selectedDate!;

    if (invoiceNumber.isNotEmpty) {
      final existingInvoice = await DatabaseService.findByInvoiceSignature(
        invoiceNumber: invoiceNumber,
        supplier: supplier,
        date: invoiceDate,
      );
      if (existingInvoice != null) {
        if (!mounted) return;
        await _showHardDuplicateBlockedDialog(
          context,
          existing: existingInvoice,
        );
        return;
      }
    }

    // ---- Duplicate check ----
    setState(() => _isSaving = true);
    try {
      final dupes = await DatabaseService.findPossibleDuplicates(
        projectId: widget.project.id,
        invoiceNumber: invoiceNumber,
        supplier: supplier,
        date: invoiceDate,
        gross: gross,
      );

      if (dupes.isNotEmpty) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        final action = await _showDuplicateDialog(
          dupes,
          invoiceNumber: invoiceNumber,
          supplier: supplier,
          date: invoiceDate,
          gross: gross,
        );
        if (action == 'cancel' || action == null) return;
        if (action == 'view') {
          // Open the existing one and bail ? user will decide from there
          await _openDetail(dupes.first);
          return;
        }
        setState(() => _isSaving = true);
      }
    } catch (e) {
      // If the duplicate check itself fails, log and continue with save
      debugPrint('Duplicate check failed: $e');
    }

    try {
      final draft = Receipt(
        projectId: widget.project.id,
        date: invoiceDate,
        invoiceNumber: invoiceNumber.isEmpty ? null : invoiceNumber,
        category: _selectedCategory!,
        supplier: supplier,
        vat: double.tryParse(_vatController.text) ?? 0,
        gross: gross,
        net: double.tryParse(_netController.text) ?? 0,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      final saved = await DatabaseService.saveReceipt(
        draft: draft,
        photoBytes: _imageBytes,
      );
      if (!mounted) return;
      _showStatus(
        'Saved as scan #${saved.scanNo!.toString().padLeft(5, '0')}',
      );
      _clearForm(silent: true, keepCategory: true);
      await _loadRecent();
    } catch (e) {
      if (_isDuplicateSignatureError(e)) {
        final existingInvoice = invoiceNumber.isNotEmpty
            ? await DatabaseService.findByInvoiceSignature(
                invoiceNumber: invoiceNumber,
                supplier: supplier,
                date: invoiceDate,
              )
            : null;
        if (!mounted) return;
        await _showHardDuplicateBlockedDialog(
          context,
          existing: existingInvoice,
        );
      } else {
        _showStatus('Save failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Show duplicate warning. Returns one of:
  ///   'cancel' ? abort save
  ///   'view'   ? open the existing receipt
  Future<String?> _showDuplicateDialog(
    List<Receipt> dupes, {
    required String invoiceNumber,
    required String supplier,
    required DateTime date,
    required double gross,
  }) async {
    final existing = dupes.first;
    final hardDuplicate = dupes.any(
      (receipt) => _isExactInvoiceDuplicate(
        receipt,
        invoiceNumber: invoiceNumber,
        supplier: supplier,
        date: date,
      ),
    );

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon:
            Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 32),
        title: Text(
            hardDuplicate ? 'Duplicate receipt found' : 'Possible duplicate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hardDuplicate
                  ? 'A receipt with the same invoice no, supplier, and date already exists. This receipt has not been added again.'
                  : 'A receipt with the same supplier, date, and gross amount already exists.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange.shade200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${existing.scanNo?.toString().padLeft(5, '0') ?? existing.id}'
                    ' ? ${existing.category}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${existing.supplier}\n'
                    '${_invoiceText(existing)}'
                    'Date: ${DateFormat('dd/MM/yyyy').format(existing.date)}\n'
                    'Gross: £${existing.gross.toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Open the existing receipt to review it, or cancel.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'view'),
            child: const Text('View existing'),
          ),
        ],
      ),
    );
  }

  String _invoiceText(Receipt receipt) {
    final invoiceNumber = receipt.invoiceNumber?.trim();
    if (invoiceNumber == null || invoiceNumber.isEmpty) return '';
    return 'Invoice no: $invoiceNumber\n';
  }

  void _clearForm({bool silent = false, bool keepCategory = false}) {
    final retainedCategory = keepCategory ? _selectedCategory : null;
    setState(() {
      _selectedDate = null;
      _invoiceNumberController.clear();
      _supplierController.clear();
      _selectedCategory = retainedCategory;
      _vatController.clear();
      _grossController.clear();
      _netController.clear();
      _notesController.clear();
      _lastCategoryConfidence = null;
      _categoryNeedsReview = false;
      _categoryReviewConfirmed = false;
      _imageBytes = null;
      _imageFileName = null;
      _imagePath = null;
    });
    if (!silent) _showStatus('Form cleared');
  }

  // ---- Export ----

  Future<void> _showExportMenu() async {
    // Step 1: pick range
    final rangeChoice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Export ? pick range'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'today'),
            child: const Text('Today'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'week'),
            child: const Text('This week'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'month'),
            child: const Text('This month'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'last_month'),
            child: const Text('Last month'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'year'),
            child: const Text('This year'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'custom'),
            child: const Text('Custom range...'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: const Text('All receipts'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (rangeChoice == null) return;

    ExportRange? range;
    switch (rangeChoice) {
      case 'today':
        range = ExportRange.today();
        break;
      case 'week':
        range = ExportRange.thisWeek();
        break;
      case 'month':
        range = ExportRange.thisMonth();
        break;
      case 'last_month':
        range = ExportRange.lastMonth();
        break;
      case 'year':
        range = ExportRange.thisYear();
        break;
      case 'all':
        range = ExportRange.allTime();
        break;
      case 'custom':
        if (!mounted) return;
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          range = ExportRange.custom(picked.start, picked.end);
        }
        break;
    }

    if (range == null || !mounted) return;

    // Step 2: pick what to include
    final contentChoice = await showDialog<ExportContent>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('What to include?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ExportContent.csvOnly),
            child: const ListTile(
              leading: Icon(Icons.description),
              title: Text('CSV only (the table)'),
              subtitle: Text('Best for accountant via WhatsApp'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ExportContent.both),
            child: const ListTile(
              leading: Icon(Icons.cloud_upload),
              title: Text('CSV + photos ZIP'),
              subtitle: Text('CSV attached separately, photos zipped'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ExportContent.photosOnly),
            child: const ListTile(
              leading: Icon(Icons.photo_library),
              title: Text('Photos only (ZIP)'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (contentChoice == null || !mounted) return;

    // Step 3: pick which date to filter by
    final basisChoice = await showDialog<DateBasis>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Filter by which date?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, DateBasis.scanDate),
            child: const ListTile(
              leading: Icon(Icons.qr_code_scanner),
              title: Text('Scan date'),
              subtitle: Text(
                  'When I added it to the app\n(default ? catches backdated entries)'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              isThreeLine: true,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, DateBasis.invoiceDate),
            child: const ListTile(
              leading: Icon(Icons.receipt_long),
              title: Text('Invoice date'),
              subtitle: Text(
                  'Date on the receipt itself\n(best for VAT periods / accountant)'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              isThreeLine: true,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (basisChoice == null || !mounted) return;

    _showStatus('Building export...', duration: const Duration(seconds: 3));

    final result = await ExportService.exportAndShare(
      range,
      content: contentChoice,
      dateBasis: basisChoice,
      projectId: widget.project.id,
      projectName: widget.project.name,
    );

    if (!mounted) return;

    if (result.success) {
      _showStatus(
        'Sharing ${result.recordCount} receipts'
        '${result.photoCount > 0 ? " + ${result.photoCount} photos" : ""}.'
        ' Pick OneDrive / WhatsApp / etc.',
        duration: const Duration(seconds: 6),
      );
    } else {
      _showStatus(result.errorMessage ?? 'Export failed', isError: true);
    }
  }

  // ---- Detail navigation ----

  Future<void> _openDetail(Receipt receipt) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReceiptDetailPage(receipt: receipt),
      ),
    );
    if (changed == true) {
      await _loadRecent();
    }
  }

  Future<void> _openReports() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectReportPage(project: widget.project),
      ),
    );
  }

  Future<void> _openInvoiceList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptHistoryPage(project: widget.project),
      ),
    );
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.name),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Invoice list',
            onPressed: _openInvoiceList,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Reports',
            onPressed: _openReports,
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Export / Share',
            onPressed: _showExportMenu,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Clear form',
            onPressed: () => _clearForm(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_statusMessage != null) _buildStatusBanner(),
                _buildSectionHeader('1. Receipt Photo (optional)'),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isScanning ? null : _takePhoto,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Take Photo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isScanning ? null : _pickFromGallery,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Gallery'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildImagePreview(),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: (_imageBytes == null || _isScanning)
                      ? null
                      : _scanWithGemini,
                  icon: _isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    _isScanning
                        ? 'Scanning...'
                        : 'Scan with Gemini (auto-fill)',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple.shade50,
                    foregroundColor: Colors.deepPurple.shade900,
                    disabledBackgroundColor: Colors.grey.shade200,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: (_imagePath == null || _isScanning)
                      ? null
                      : _scanWithMlKit,
                  icon: const Icon(Icons.document_scanner),
                  label: const Text('ML Kit OCR + DeepSeek parse'),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Manual entry below always works, with or without scan.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                _buildSectionHeader('2. Receipt Details'),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Category * (select before save)',
                    labelStyle: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                  items: _categories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(
                            c,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedCategory = v),
                  validator: (v) => v == null ? 'Please select category' : null,
                ),
                const SizedBox(height: 10),
                MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.0),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final twoColumn = constraints.maxWidth >= 360;
                      final gap = twoColumn ? 10.0 : 12.0;
                      final fieldStyle = TextStyle(
                        fontSize: twoColumn ? 18 : 17,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      );

                      final dateField = InkWell(
                        onTap: _pickDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Invoice date *',
                            suffixIcon: Icon(Icons.calendar_today, size: 18),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _selectedDate == null
                                  ? 'dd/mm/yyyy'
                                  : DateFormat('dd/MM/yyyy')
                                      .format(_selectedDate!),
                              maxLines: 1,
                              style: fieldStyle.copyWith(
                                color: _selectedDate == null
                                    ? Theme.of(context).colorScheme.outline
                                    : fieldStyle.color,
                              ),
                            ),
                          ),
                        ),
                      );

                      final supplierField = TextFormField(
                        controller: _supplierController,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'Supplier *',
                          hintText: 'e.g. B&Q, Travis Perkins',
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Please enter supplier'
                            : null,
                      );

                      final invoiceField = TextFormField(
                        controller: _invoiceNumberController,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'Invoice no.',
                          hintText: 'INV-1024',
                        ),
                        textCapitalization: TextCapitalization.characters,
                      );

                      final vatField = TextFormField(
                        controller: _vatController,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'VAT',
                          prefixText: '£ ',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      );

                      final grossField = TextFormField(
                        controller: _grossController,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'Gross *',
                          prefixText: '£ ',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Please enter gross amount';
                          }
                          if (double.tryParse(v) == null) {
                            return 'Enter a valid number';
                          }
                          return null;
                        },
                      );

                      final netField = TextFormField(
                        controller: _netController,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'Net',
                          prefixText: '£ ',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      );

                      final notesField = TextFormField(
                        controller: _notesController,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          hintText: 'Optional',
                        ),
                        maxLines: 2,
                      );

                      if (!twoColumn) {
                        return Column(
                          children: [
                            dateField,
                            SizedBox(height: gap),
                            invoiceField,
                            SizedBox(height: gap),
                            supplierField,
                            SizedBox(height: gap),
                            Row(
                              children: [
                                Expanded(child: netField),
                                const SizedBox(width: 10),
                                Expanded(child: vatField),
                                const SizedBox(width: 10),
                                Expanded(child: grossField),
                              ],
                            ),
                            SizedBox(height: gap),
                            notesField,
                          ],
                        );
                      }

                      return Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 11, child: dateField),
                              const SizedBox(width: 10),
                              Expanded(flex: 12, child: invoiceField),
                            ],
                          ),
                          SizedBox(height: gap),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: supplierField),
                            ],
                          ),
                          SizedBox(height: gap),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: netField),
                              const SizedBox(width: 10),
                              Expanded(child: vatField),
                              const SizedBox(width: 10),
                              Expanded(child: grossField),
                            ],
                          ),
                          SizedBox(height: gap),
                          notesField,
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                _buildRecentEntries(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveRecord,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(
                _isSaving ? 'Saving...' : 'Save to Database',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentEntries() {
    final headerText =
        '3. Recent Entries (Today)${_totalReceiptCount > 0 ? "  (Total: $_totalReceiptCount)" : ""}';

    if (_recentReceipts.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(headerText),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6),
              color: Colors.grey.shade50,
            ),
            child: const Center(
              child: Text(
                'No scans saved today yet.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(headerText),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              for (int i = 0; i < _recentReceipts.length; i++) ...[
                if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
                _buildReceiptRow(_recentReceipts[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptRow(Receipt r) {
    return InkWell(
      onTap: () => _openDetail(r),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: r.photoPath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Image.file(
                        File(r.photoPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image,
                            size: 20,
                            color: Colors.grey),
                      ),
                    )
                  : const Icon(Icons.receipt_long,
                      size: 24, color: Colors.grey),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (r.scanNo != null) ...[
                        Text(
                          '#${r.scanNo!.toString().padLeft(5, '0')}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          r.category,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.indigo.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('dd/MM/yy').format(r.date),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      r.supplier,
                      if ((r.invoiceNumber ?? '').trim().isNotEmpty)
                        'Inv ${r.invoiceNumber!.trim()}',
                    ].join(' - '),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '£${r.gross.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _statusIsError ? Colors.red.shade50 : Colors.blue.shade50,
        border: Border.all(
          color: _statusIsError ? Colors.red.shade300 : Colors.blue.shade300,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            _statusIsError ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: _statusIsError ? Colors.red.shade700 : Colors.blue.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(_statusMessage!)),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => setState(() => _statusMessage = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    if (_imageBytes == null) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
          color: Colors.grey.shade50,
        ),
        child: const Center(
          child:
              Text('No photo selected', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
            child: Image.memory(
              _imageBytes!,
              height: 200,
              width: double.infinity,
              fit: BoxFit.contain,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.image, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _imageFileName ?? 'image',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: _removeImage,
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Remove', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ============================================================
// INVOICE LIST PAGE - receipt filters and saved scans
// ============================================================

class CategoryManagerPage extends StatefulWidget {
  const CategoryManagerPage({super.key});

  @override
  State<CategoryManagerPage> createState() => _CategoryManagerPageState();
}

class _CategoryManagerPageState extends State<CategoryManagerPage> {
  final _newCategoryController = TextEditingController();
  List<AppCategory> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _newCategoryController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() => _loading = true);
    try {
      final categories = await DatabaseService.getCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Could not load categories: $e');
    }
  }

  Future<void> _addCategory() async {
    final name = _newCategoryController.text.trim();
    if (name.isEmpty) {
      _showMessage('Enter a category name first.');
      return;
    }
    try {
      await DatabaseService.createCategory(name);
      if (!mounted) return;
      _newCategoryController.clear();
      await _loadCategories();
    } catch (e) {
      _showMessage('Could not add category: ${_friendlyDbError(e)}');
    }
  }

  Future<void> _editCategory(AppCategory category) async {
    final controller = TextEditingController(text: category.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Category name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(ctx, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    if (newName == null || newName == category.name) return;
    try {
      await DatabaseService.updateCategory(category, newName);
      if (!mounted) return;
      await _loadCategories();
    } catch (e) {
      _showMessage('Could not update category: ${_friendlyDbError(e)}');
    }
  }

  Future<void> _deleteCategory(AppCategory category) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          'Delete "${category.name}"?\n\nThis is blocked if saved receipts still use it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DatabaseService.deleteCategory(category);
      if (!mounted) return;
      await _loadCategories();
    } catch (e) {
      _showMessage(_friendlyDbError(e));
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _friendlyDbError(Object error) {
    final text = error.toString().replaceFirst('Bad state: ', '');
    if (text.contains('UNIQUE constraint failed')) {
      return 'A category with that name already exists.';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newCategoryController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'New category',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _addCategory(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _addCategory,
                    child: const Text('Add'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              for (final category in _categories)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(category.name),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Category actions',
                      onSelected: (value) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          switch (value) {
                            case 'edit':
                              _editCategory(category);
                              break;
                            case 'delete':
                              _deleteCategory(category);
                              break;
                          }
                        });
                      },
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.edit),
                            title: Text('Edit'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete_outline),
                            title: Text('Delete'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class GeminiSettingsPage extends StatefulWidget {
  const GeminiSettingsPage({super.key});

  @override
  State<GeminiSettingsPage> createState() => _GeminiSettingsPageState();
}

class _GeminiSettingsPageState extends State<GeminiSettingsPage> {
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _obscureKey = true;
  bool _usingEnvFallback = false;

  @override
  void initState() {
    super.initState();
    _modelController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    final settings = await GeminiService.loadSettings();
    final savedKey = await GeminiService.savedApiKey();
    if (!mounted) return;
    setState(() {
      _apiKeyController.text = savedKey ?? '';
      _modelController.text = settings.model;
      _usingEnvFallback = settings.usesEnvKey && !settings.hasSavedApiKey;
      _loading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      await GeminiService.saveSettings(
        apiKey: _apiKeyController.text,
        model: _modelController.text,
      );
      if (!mounted) return;
      await _loadSettings();
      if (!mounted) return;
      _showMessage(
        _apiKeyController.text.trim().isEmpty
            ? 'Gemini settings saved. Using .env API key if available.'
            : 'Gemini settings saved.',
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Invalid argument(s): ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testSettings() async {
    setState(() => _testing = true);
    final result = await GeminiService.checkSettings(
      apiKey: _apiKeyController.text,
      model: _modelController.text,
    );
    if (!mounted) return;
    setState(() => _testing = false);
    if (!result.success) {
      _showMessage(result.errorMessage ?? 'Gemini check failed.');
      return;
    }

    final workingModel = result.workingModel;
    if (workingModel == null) {
      _showMessage('Gemini connection works.');
      return;
    }

    if (result.usedFallback) {
      setState(() => _modelController.text = workingModel);
      _showMessage(
          'Selected model failed. $workingModel works and is ready to save.');
    } else {
      _showMessage('Gemini connection works with $workingModel.');
    }
  }

  Future<void> _resetToEnv() async {
    setState(() => _saving = true);
    try {
      await GeminiService.resetSettings();
      if (!mounted) return;
      await _loadSettings();
      if (!mounted) return;
      _showMessage('Gemini settings reset to .env fallback.');
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not reset Gemini settings: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _useModel(String model) {
    _modelController.text = model;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemini settings'),
        backgroundColor: colorScheme.primaryContainer,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Provider: Gemini',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _apiKeyController,
                            obscureText: _obscureKey,
                            keyboardType: TextInputType.visiblePassword,
                            decoration: InputDecoration(
                              labelText: 'Client Gemini API key',
                              helperText: _usingEnvFallback
                                  ? 'No client key saved. The app is using the .env key.'
                                  : 'Leave empty to use the .env key on this device.',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: _obscureKey ? 'Show key' : 'Hide key',
                                onPressed: () {
                                  setState(() => _obscureKey = !_obscureKey);
                                },
                                icon: Icon(
                                  _obscureKey
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _modelController,
                            decoration: const InputDecoration(
                              labelText: 'Gemini model',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('gemini-2.5-flash'),
                                selected: _modelController.text.trim() ==
                                    'gemini-2.5-flash',
                                onSelected: (_) =>
                                    _useModel('gemini-2.5-flash'),
                              ),
                              ChoiceChip(
                                label: const Text('gemini-1.5-flash'),
                                selected: _modelController.text.trim() ==
                                    'gemini-1.5-flash',
                                onSelected: (_) =>
                                    _useModel('gemini-1.5-flash'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _saveSettings,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Save settings'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _testSettings,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check),
                    label: const Text('Check Gemini settings'),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _saving ? null : _resetToEnv,
                    icon: const Icon(Icons.restore),
                    label: const Text('Reset to .env'),
                  ),
                ],
              ),
      ),
    );
  }
}

class DeepSeekSettingsPage extends StatefulWidget {
  const DeepSeekSettingsPage({super.key});

  @override
  State<DeepSeekSettingsPage> createState() => _DeepSeekSettingsPageState();
}

class _DeepSeekSettingsPageState extends State<DeepSeekSettingsPage> {
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _obscureKey = true;
  bool _usingEnvFallback = false;

  @override
  void initState() {
    super.initState();
    _modelController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    final settings = await DeepSeekService.loadSettings();
    final savedKey = await DeepSeekService.savedApiKey();
    if (!mounted) return;
    setState(() {
      _apiKeyController.text = savedKey ?? '';
      _modelController.text = settings.model;
      _usingEnvFallback = settings.usesEnvKey && !settings.hasSavedApiKey;
      _loading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      await DeepSeekService.saveSettings(
        apiKey: _apiKeyController.text,
        model: _modelController.text,
      );
      if (!mounted) return;
      await _loadSettings();
      if (!mounted) return;
      _showMessage(
        _apiKeyController.text.trim().isEmpty
            ? 'DeepSeek settings saved. Using .env API key if available.'
            : 'DeepSeek settings saved.',
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Invalid argument(s): ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testSettings() async {
    setState(() => _testing = true);
    final result = await DeepSeekService.checkSettings(
      apiKey: _apiKeyController.text,
      model: _modelController.text,
    );
    if (!mounted) return;
    setState(() => _testing = false);
    if (!result.success) {
      _showMessage(result.errorMessage ?? 'DeepSeek check failed.');
      return;
    }
    final workingModel = result.workingModel;
    if (workingModel == null) {
      _showMessage('DeepSeek connection works.');
      return;
    }
    if (result.usedFallback) {
      setState(() => _modelController.text = workingModel);
      _showMessage(
        'Selected model failed. $workingModel works and is ready to save.',
      );
    } else {
      _showMessage('DeepSeek connection works with $workingModel.');
    }
  }

  Future<void> _resetToEnv() async {
    setState(() => _saving = true);
    try {
      await DeepSeekService.resetSettings();
      if (!mounted) return;
      await _loadSettings();
      if (!mounted) return;
      _showMessage('DeepSeek settings reset to .env fallback.');
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not reset DeepSeek settings: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _useModel(String model) {
    _modelController.text = model;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('DeepSeek settings'),
        backgroundColor: colorScheme.primaryContainer,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.bolt, color: colorScheme.primary),
                              const SizedBox(width: 10),
                              Text(
                                'Provider: DeepSeek',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _apiKeyController,
                            obscureText: _obscureKey,
                            keyboardType: TextInputType.visiblePassword,
                            decoration: InputDecoration(
                              labelText: 'Client DeepSeek API key',
                              helperText: _usingEnvFallback
                                  ? 'No client key saved. The app is using the .env key.'
                                  : 'Leave empty to use the .env key on this device.',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: _obscureKey ? 'Show key' : 'Hide key',
                                onPressed: () {
                                  setState(() => _obscureKey = !_obscureKey);
                                },
                                icon: Icon(
                                  _obscureKey
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _modelController,
                            decoration: const InputDecoration(
                              labelText: 'DeepSeek model',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('deepseek-v4-flash'),
                                selected: _modelController.text.trim() ==
                                    'deepseek-v4-flash',
                                onSelected: (_) =>
                                    _useModel('deepseek-v4-flash'),
                              ),
                              ChoiceChip(
                                label: const Text('deepseek-chat'),
                                selected: _modelController.text.trim() ==
                                    'deepseek-chat',
                                onSelected: (_) => _useModel('deepseek-chat'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _saveSettings,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Save settings'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _testSettings,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check),
                    label: const Text('Check DeepSeek settings'),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _saving ? null : _resetToEnv,
                    icon: const Icon(Icons.restore),
                    label: const Text('Reset to .env'),
                  ),
                ],
              ),
      ),
    );
  }
}

class ReceiptHistoryPage extends StatefulWidget {
  final Project? project;

  const ReceiptHistoryPage({super.key, this.project});

  @override
  State<ReceiptHistoryPage> createState() => _ReceiptHistoryPageState();
}

class _ReceiptHistoryPageState extends State<ReceiptHistoryPage> {
  final _searchController = TextEditingController();
  List<Receipt> _receipts = [];
  List<Project> _projects = [];
  bool _loading = true;
  bool _tableView = true;
  ExportRange _range = ExportRange.allTime();
  DateBasis _dateBasis = DateBasis.invoiceDate;

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _loadReceipts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    final projects = await DatabaseService.getProjects();
    if (!mounted) return;
    setState(() => _projects = projects);
  }

  Future<void> _loadReceipts({String? query}) async {
    setState(() => _loading = true);
    try {
      final searchText = query ?? _searchController.text;
      final rows = _dateBasis == DateBasis.scanDate
          ? await DatabaseService.getByScanDateRange(
              _range.from,
              _range.to,
              projectId: widget.project?.id,
            )
          : await DatabaseService.getByDateRange(
              _range.from,
              _range.to,
              projectId: widget.project?.id,
            );
      final filtered = rows
          .where((receipt) => _matchesSearchQuery(receipt, searchText))
          .toList();
      if (!mounted) return;
      setState(() {
        _receipts = filtered;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invoice list failed: $e')),
      );
    }
  }

  bool _matchesSearchQuery(Receipt receipt, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final numericQuery =
        double.tryParse(q.replaceAll('£', '').replaceAll(',', '').trim());
    final amountMatches = numericQuery != null &&
        ((receipt.gross - numericQuery).abs() < 0.005 ||
            (receipt.vat - numericQuery).abs() < 0.005 ||
            (receipt.net - numericQuery).abs() < 0.005);

    if (amountMatches) return true;

    final textFields = <String>[
      receipt.supplier,
      receipt.invoiceNumber ?? '',
      receipt.category,
      Receipt.formatDate(receipt.date),
      Receipt.formatDate(receipt.createdAt),
      DateFormat('dd/MM/yyyy').format(receipt.date),
      DateFormat('dd/MM/yyyy').format(receipt.createdAt),
      (receipt.scanNo ?? receipt.id ?? 0).toString(),
      receipt.gross.toStringAsFixed(2),
      receipt.vat.toStringAsFixed(2),
      receipt.net.toStringAsFixed(2),
    ];
    return textFields.any((value) => value.toLowerCase().contains(q));
  }

  Future<void> _openDetail(Receipt receipt) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReceiptDetailPage(receipt: receipt),
      ),
    );
    if (changed == true) {
      await _loadReceipts();
    }
  }

  Future<void> _openReportsFromInvoiceList() async {
    Project? target = widget.project;
    if (target == null) {
      if (_projects.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No projects available for reports.')),
        );
        return;
      }
      final selected = await showDialog<Project>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Choose project report'),
          children: [
            for (final project in _projects)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, project),
                child: Text(project.name),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      target = selected;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectReportPage(project: target!),
      ),
    );
  }

  Future<void> _pickRange() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Invoice list range'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'month'),
            child: const Text('This month'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'last_month'),
            child: const Text('Last month'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'year'),
            child: const Text('This year'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'custom'),
            child: const Text('Custom range...'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: const Text('All receipts'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (choice == null) return;
    if (!mounted) return;

    ExportRange? next;
    switch (choice) {
      case 'month':
        next = ExportRange.thisMonth();
        break;
      case 'last_month':
        next = ExportRange.lastMonth();
        break;
      case 'year':
        next = ExportRange.thisYear();
        break;
      case 'all':
        next = ExportRange.allTime();
        break;
      case 'custom':
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          next = ExportRange.custom(picked.start, picked.end);
        }
        break;
    }
    if (next == null || !mounted) return;
    setState(() => _range = next!);
    await _loadReceipts();
  }

  void _setDateBasis(DateBasis basis) {
    setState(() => _dateBasis = basis);
    _loadReceipts();
  }

  Future<void> _showInvoiceListExportMenu() async {
    final contentChoice = await showDialog<ExportContent>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Share invoice list'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ExportContent.csvOnly),
            child: const ListTile(
              leading: Icon(Icons.description),
              title: Text('CSV only'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ExportContent.both),
            child: const ListTile(
              leading: Icon(Icons.cloud_upload),
              title: Text('CSV + photos ZIP'),
              subtitle: Text('CSV attached separately, photos zipped'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ExportContent.photosOnly),
            child: const ListTile(
              leading: Icon(Icons.photo_library),
              title: Text('Photos only ZIP'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (contentChoice == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Building export...')),
    );

    final result = await ExportService.exportAndShare(
      _range,
      content: contentChoice,
      dateBasis: _dateBasis,
      projectId: widget.project?.id,
      projectName: widget.project?.name,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? 'Sharing ${result.recordCount} receipts${result.photoCount > 0 ? " + ${result.photoCount} photos" : ""}.'
              : result.errorMessage ?? 'Export failed',
        ),
        backgroundColor:
            result.success ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _resetSearch() {
    _searchController.clear();
    _loadReceipts(query: '');
  }

  String _rangeLabel() {
    switch (_range.label) {
      case 'all_time':
        return 'All receipts';
      case 'this_month':
        return DateFormat('MMMM yyyy').format(_range.from);
      case 'last_month':
        return DateFormat('MMMM yyyy').format(_range.from);
      default:
        if (_range.label.startsWith('this_year')) {
          return 'Year ${_range.from.year}';
        }
        return '${DateFormat('dd/MM/yy').format(_range.from)} - ${DateFormat('dd/MM/yy').format(_range.to)}';
    }
  }

  String _projectName(int? id) {
    if (id == null) return 'Unassigned';
    for (final project in _projects) {
      if (project.id == id) return project.name;
    }
    if (widget.project?.id == id) return widget.project!.name;
    return 'Project $id';
  }

  double get _totalGross =>
      _receipts.fold<double>(0, (sum, receipt) => sum + receipt.gross);

  String _money(double value) => '£${value.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice List'),
        backgroundColor: colorScheme.primaryContainer,
        actions: [
          IconButton(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range),
            tooltip: 'Date range',
          ),
          IconButton(
            onPressed: _showInvoiceListExportMenu,
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Upload/share',
          ),
          PopupMenuButton<DateBasis>(
            tooltip: 'Date filter',
            icon: const Icon(Icons.filter_alt),
            onSelected: _setDateBasis,
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: DateBasis.invoiceDate,
                child: Text('Invoice date'),
              ),
              PopupMenuItem(
                value: DateBasis.scanDate,
                child: Text('Scan date'),
              ),
            ],
          ),
          IconButton(
            onPressed: _openReportsFromInvoiceList,
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Reports',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search invoice, supplier, category, amount',
                hintText: 'e.g. CESV218200, tesco, sundries, 31.60',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _resetSearch,
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear search',
                      ),
              ),
              textInputAction: TextInputAction.search,
              onChanged: (value) => _loadReceipts(query: value),
              onSubmitted: (value) => _loadReceipts(query: value),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_rangeLabel()} · ${_dateBasis == DateBasis.scanDate ? "Scan date" : "Invoice date"}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _resetSearch,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset'),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.table_rows),
                      label: Text('Table'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.view_agenda),
                      label: Text('Cards'),
                    ),
                  ],
                  selected: {_tableView},
                  onSelectionChanged: (selection) {
                    setState(() => _tableView = selection.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                Text(
                  '${_receipts.length} results',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Total gross: ${_money(_totalGross)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_receipts.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: Text(
                    'No matching invoices.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else if (_tableView)
              _InvoiceTable(
                receipts: _receipts,
                onOpen: _openDetail,
              )
            else
              for (final receipt in _receipts) ...[
                _HistoryReceiptTile(
                  receipt: receipt,
                  projectName: widget.project == null
                      ? _projectName(receipt.projectId)
                      : null,
                  onTap: () => _openDetail(receipt),
                ),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class _InvoiceTable extends StatelessWidget {
  final List<Receipt> receipts;
  final ValueChanged<Receipt> onOpen;

  const _InvoiceTable({
    required this.receipts,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final headerStyle = TextStyle(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w800,
      fontSize: 12,
      letterSpacing: 0.3,
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(3.2),
          1: FlexColumnWidth(4.3),
          2: FlexColumnWidth(2.5),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: colorScheme.surfaceContainerHigh),
            children: [
              _InvoiceTableCell('Date', style: headerStyle),
              _InvoiceTableCell('Supplier', style: headerStyle),
              _InvoiceTableCell('Gross £',
                  style: headerStyle, alignRight: true),
            ],
          ),
          for (final receipt in receipts)
            TableRow(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              children: [
                _InvoiceTableCell(
                  DateFormat('dd/MM/yyyy').format(receipt.date),
                  onTap: () => onOpen(receipt),
                ),
                _InvoiceTableCell(
                  receipt.supplier,
                  maxLines: 3,
                  onTap: () => onOpen(receipt),
                ),
                _InvoiceTableCell(
                  '£${receipt.gross.toStringAsFixed(2)}',
                  alignRight: true,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                  onTap: () => onOpen(receipt),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _InvoiceTableCell extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final bool alignRight;
  final int maxLines;
  final VoidCallback? onTap;

  const _InvoiceTableCell(
    this.text, {
    this.style,
    this.alignRight = false,
    this.maxLines = 1,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
    if (onTap == null) return child;
    return InkWell(onTap: onTap, child: child);
  }
}

class _HistoryReceiptTile extends StatelessWidget {
  final Receipt receipt;
  final String? projectName;
  final VoidCallback onTap;

  const _HistoryReceiptTile({
    required this.receipt,
    this.projectName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      '#${(receipt.scanNo ?? 0).toString().padLeft(5, '0')}',
      receipt.category,
      if (projectName != null) projectName!,
      'Invoice ${DateFormat('dd/MM/yyyy').format(receipt.date)}',
      'Scanned ${DateFormat('dd/MM/yyyy').format(receipt.createdAt)}',
    ];

    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      leading: receipt.photoPath == null
          ? const Icon(Icons.receipt_long)
          : ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.file(
                File(receipt.photoPath!),
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
              ),
            ),
      title: Text(
        [
          receipt.supplier,
          if ((receipt.invoiceNumber ?? '').trim().isNotEmpty)
            'Inv ${receipt.invoiceNumber!.trim()}',
        ].join(' - '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitleParts.join(' · '),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: SizedBox(
        width: 92,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                '£${receipt.gross.toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}
// ============================================================
// REPORT PAGE - project totals and category breakdown
// ============================================================

class ProjectReportPage extends StatefulWidget {
  final Project project;

  const ProjectReportPage({super.key, required this.project});

  @override
  State<ProjectReportPage> createState() => _ProjectReportPageState();
}

class _ProjectReportPageState extends State<ProjectReportPage> {
  ExportRange _range = ExportRange.allTime();
  DateBasis _dateBasis = DateBasis.invoiceDate;
  late Future<ProjectReport> _reportFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _reportFuture = DatabaseService.getProjectReport(
      projectId: widget.project.id,
      from: _range.from,
      to: _range.to,
      useScanDate: _dateBasis == DateBasis.scanDate,
    );
  }

  Future<void> _pickRange() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Report range'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'month'),
            child: const Text('This month'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'last_month'),
            child: const Text('Last month'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'year'),
            child: const Text('This year'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'custom'),
            child: const Text('Custom range...'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: const Text('All receipts'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (choice == null) return;

    ExportRange? next;
    switch (choice) {
      case 'month':
        next = ExportRange.thisMonth();
        break;
      case 'last_month':
        next = ExportRange.lastMonth();
        break;
      case 'year':
        next = ExportRange.thisYear();
        break;
      case 'all':
        next = ExportRange.allTime();
        break;
      case 'custom':
        if (!mounted) return;
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          next = ExportRange.custom(picked.start, picked.end);
        }
        break;
    }

    if (next == null || !mounted) return;
    setState(() {
      _range = next!;
      _reload();
    });
  }

  void _setDateBasis(DateBasis basis) {
    setState(() {
      _dateBasis = basis;
      _reload();
    });
  }

  Future<void> _openInvoiceList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptHistoryPage(project: widget.project),
      ),
    );
  }

  Future<void> _showReportExportMenu() async {
    final contentChoice = await showDialog<ExportContent>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Share report'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ExportContent.csvOnly),
            child: const ListTile(
              leading: Icon(Icons.description),
              title: Text('CSV only'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ExportContent.both),
            child: const ListTile(
              leading: Icon(Icons.cloud_upload),
              title: Text('CSV + photos ZIP'),
              subtitle: Text('CSV attached separately, photos zipped'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ExportContent.photosOnly),
            child: const ListTile(
              leading: Icon(Icons.photo_library),
              title: Text('Photos only ZIP'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (contentChoice == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Building report export...')),
    );

    final result = await ExportService.exportAndShare(
      _range,
      content: contentChoice,
      dateBasis: _dateBasis,
      projectId: widget.project.id,
      projectName: widget.project.name,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? 'Sharing ${result.recordCount} receipts${result.photoCount > 0 ? " + ${result.photoCount} photos" : ""}.'
              : result.errorMessage ?? 'Export failed',
        ),
        backgroundColor:
            result.success ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  String _rangeLabel() {
    switch (_range.label) {
      case 'all_time':
        return 'All receipts';
      case 'this_month':
        return DateFormat('MMMM yyyy').format(_range.from);
      case 'last_month':
        return DateFormat('MMMM yyyy').format(_range.from);
      default:
        if (_range.label.startsWith('this_year')) {
          return 'Year ${_range.from.year}';
        }
        return '${DateFormat('dd/MM/yy').format(_range.from)} - ${DateFormat('dd/MM/yy').format(_range.to)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Invoice list',
            onPressed: _openInvoiceList,
          ),
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Report range',
            onPressed: _pickRange,
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Share report',
            onPressed: _showReportExportMenu,
          ),
          PopupMenuButton<DateBasis>(
            tooltip: 'Date basis',
            icon: const Icon(Icons.filter_alt),
            onSelected: _setDateBasis,
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: DateBasis.invoiceDate,
                child: Text('Invoice date'),
              ),
              PopupMenuItem(
                value: DateBasis.scanDate,
                child: Text('Scan date'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<ProjectReport>(
          future: _reportFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Report failed: ${snapshot.error}'));
            }
            final report = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildReportHeader(colorScheme),
                if (report.categories.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SummaryReportTable(report: report),
                ],
                if (widget.project.budget != null) ...[
                  const SizedBox(height: 16),
                  _BudgetProgress(
                    budget: widget.project.budget!,
                    spent: report.totalGross,
                  ),
                ],
                if (report.categories.isEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      border: Border.all(color: colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.inbox,
                              size: 48, color: colorScheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            'No receipts in this range.',
                            style: TextStyle(color: colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildReportHeader(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.project.name,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${_rangeLabel()} ? ${_dateBasis == DateBasis.scanDate ? "Scan date" : "Invoice date"}',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildSummaryCards(ProjectReport report, ColorScheme colorScheme) {
    return Row(
      children: [
        Expanded(
            child: _buildStatCard(
          label: 'Receipts',
          value: report.receiptCount.toString(),
          icon: Icons.receipt_long,
          colorScheme: colorScheme,
        )),
        const SizedBox(width: 12),
        Expanded(
            child: _buildStatCard(
          label: 'Net Total',
          value: '£${report.totalNet.toStringAsFixed(2)}',
          icon: Icons.account_balance_wallet,
          colorScheme: colorScheme,
        )),
        const SizedBox(width: 12),
        Expanded(
            child: _buildStatCard(
          label: 'VAT',
          value: '£${report.totalVat.toStringAsFixed(2)}',
          icon: Icons.money_off,
          colorScheme: colorScheme,
        )),
        const SizedBox(width: 12),
        Expanded(
            child: _buildStatCard(
          label: 'Gross Total',
          value: '£${report.totalGross.toStringAsFixed(2)}',
          icon: Icons.summarize,
          highlight: true,
          colorScheme: colorScheme,
        )),
      ],
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
    required ColorScheme colorScheme,
    bool highlight = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: highlight
                    ? colorScheme.primary.withValues(alpha: 0.12)
                    : colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon,
                  size: 18,
                  color: highlight ? colorScheme.primary : colorScheme.outline),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: highlight ? colorScheme.primary : colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SummaryReportTable extends StatelessWidget {
  final ProjectReport report;

  const SummaryReportTable({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final headerStyle = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 13,
      color: colorScheme.onPrimaryContainer,
      letterSpacing: 0.5,
    );
    const totalStyle = TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 15,
      color: Colors.red,
    );
    final cellStyle = TextStyle(fontSize: 14, color: colorScheme.onSurface);

    return Card(
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.45),
          1: FlexColumnWidth(0.95),
          2: FlexColumnWidth(1.05),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: colorScheme.outlineVariant),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: colorScheme.primaryContainer),
            children: [
              _ReportCell('Categories', style: headerStyle),
              _ReportCell('Inv count', style: headerStyle, alignRight: true),
              _ReportCell('Gross £', style: headerStyle, alignRight: true),
            ],
          ),
          for (final summary in report.categories)
            TableRow(
              children: [
                _ReportCell(summary.category, style: cellStyle),
                _ReportCell(
                  summary.receiptCount.toString(),
                  style: cellStyle,
                  alignRight: true,
                ),
                _ReportCell(
                  summary.totalGross.toStringAsFixed(2),
                  style: cellStyle,
                  alignRight: true,
                ),
              ],
            ),
          TableRow(
            decoration: BoxDecoration(color: colorScheme.surfaceContainerLow),
            children: [
              const _ReportCell('Total', style: totalStyle),
              _ReportCell(
                report.receiptCount.toString(),
                style: totalStyle,
                alignRight: true,
              ),
              _ReportCell(
                report.totalGross.toStringAsFixed(2),
                style: totalStyle,
                alignRight: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportCell extends StatelessWidget {
  final String text;
  final TextStyle style;
  final bool alignRight;

  const _ReportCell(
    this.text, {
    required this.style,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

class _BudgetProgress extends StatelessWidget {
  final double budget;
  final double spent;

  const _BudgetProgress({
    required this.budget,
    required this.spent,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ratio = budget <= 0 ? 0.0 : (spent / budget).clamp(0.0, 1.0);
    final remaining = budget - spent;
    final overBudget = remaining < 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: overBudget
                        ? colorScheme.error.withValues(alpha: 0.12)
                        : colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    overBudget ? Icons.warning : Icons.account_balance,
                    size: 18,
                    color: overBudget ? colorScheme.error : colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Budget',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        '£${spent.toStringAsFixed(2)} / £${budget.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: overBudget
                        ? colorScheme.error.withValues(alpha: 0.1)
                        : colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${(ratio * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color:
                          overBudget ? colorScheme.error : colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                backgroundColor: colorScheme.surfaceContainerLow,
                color: overBudget ? colorScheme.error : colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  overBudget
                      ? '£${remaining.abs().toStringAsFixed(2)} over budget'
                      : '£${remaining.toStringAsFixed(2)} remaining',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: overBudget ? colorScheme.error : colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  'Budget: £${budget.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

bool _isExactInvoiceDuplicate(
  Receipt receipt, {
  required String invoiceNumber,
  required String supplier,
  required DateTime date,
}) {
  final invoice = _normaliseInvoiceNumber(invoiceNumber);
  if (invoice.isEmpty) return false;
  return _normaliseInvoiceNumber(receipt.invoiceNumber) == invoice &&
      _normaliseSupplier(receipt.supplier) == _normaliseSupplier(supplier) &&
      Receipt.formatDate(receipt.date) == Receipt.formatDate(date);
}

String _normaliseInvoiceNumber(String? value) {
  if (value == null) return '';
  return value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
}

String _normaliseSupplier(String? value) {
  if (value == null) return '';
  return value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
}

bool _isAmountsBalanced({
  required double net,
  required double vat,
  required double gross,
}) {
  return ((net + vat) - gross).abs() < 0.01;
}

bool _isDuplicateSignatureError(Object error) {
  final text = error.toString().toUpperCase();
  return text.contains('DUPLICATE_INVOICE_SIGNATURE');
}

Future<void> _showHardDuplicateBlockedDialog(
  BuildContext context, {
  Receipt? existing,
}) async {
  if (!context.mounted) return;
  final existingRef = existing == null
      ? null
      : '#${(existing.scanNo ?? existing.id ?? 0).toString().padLeft(5, '0')}';
  final details = existing == null
      ? null
      : '${existing.supplier}\n'
          'Date: ${DateFormat('dd/MM/yyyy').format(existing.date)}\n'
          'Gross: £${existing.gross.toStringAsFixed(2)}';

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 32),
      title: const Text('Duplicate receipt found'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            existingRef == null
                ? 'A receipt with the same invoice no, supplier, and date already exists.'
                : 'A receipt with the same invoice no, supplier, and date already exists as $existingRef.',
          ),
          if (details != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange.shade200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(details.toString()),
            ),
          ],
          const SizedBox(height: 10),
          const Text('This duplicate cannot be saved.'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

// ============================================================
// DETAIL PAGE - view, edit, delete
// ============================================================

class ReceiptDetailPage extends StatefulWidget {
  final Receipt receipt;
  const ReceiptDetailPage({super.key, required this.receipt});

  @override
  State<ReceiptDetailPage> createState() => _ReceiptDetailPageState();
}

class _ReceiptDetailPageState extends State<ReceiptDetailPage> {
  late Receipt _current;

  int? _projectId;
  late DateTime _date;
  late String _category;
  late TextEditingController _invoiceNumber;
  late TextEditingController _supplier;
  late TextEditingController _vat;
  late TextEditingController _gross;
  late TextEditingController _net;
  late TextEditingController _notes;
  List<Project> _projects = [];
  List<String> _categories = DatabaseService.defaultCategories;

  bool _editing = false;
  bool _saving = false;
  bool _didUpdate = false;

  @override
  void initState() {
    super.initState();
    _current = widget.receipt;
    _projectId = _current.projectId;
    _date = _current.date;
    _category = _current.category;
    _invoiceNumber = TextEditingController(text: _current.invoiceNumber ?? '');
    _supplier = TextEditingController(text: _current.supplier);
    _vat = TextEditingController(text: _current.vat.toStringAsFixed(2));
    _gross = TextEditingController(text: _current.gross.toStringAsFixed(2));
    _net = TextEditingController(text: _current.net.toStringAsFixed(2));
    _notes = TextEditingController(text: _current.notes ?? '');
    _loadProjects();
    _loadCategories();
  }

  @override
  void dispose() {
    _invoiceNumber.dispose();
    _supplier.dispose();
    _vat.dispose();
    _gross.dispose();
    _net.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await DatabaseService.getCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories.map((c) => c.name).toList();
        if (!_categories.contains(_category)) {
          _categories = [_category, ..._categories];
        }
      });
    } catch (e) {
      debugPrint('Failed to load categories: $e');
    }
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await DatabaseService.getProjects();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        if (_projectId == null && projects.isNotEmpty) {
          _projectId = projects.first.id;
        }
      });
    } catch (e) {
      debugPrint('Failed to load projects: $e');
    }
  }

  Future<void> _save() async {
    final newSupplier = _supplier.text.trim();
    final newInvoiceNumber = _invoiceNumber.text.trim();
    final newVat = double.tryParse(_vat.text) ?? 0;
    final newGross = double.tryParse(_gross.text) ?? 0;
    final newNet = double.tryParse(_net.text) ?? 0;
    final newProjectId = _projectId ?? _current.projectId;

    if (!_isAmountsBalanced(net: newNet, vat: newVat, gross: newGross)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unbalanced entry: Net + VAT must equal Gross. '
            'Current total is £${(newNet + newVat).toStringAsFixed(2)} '
            'vs Gross £${newGross.toStringAsFixed(2)}.',
          ),
        ),
      );
      return;
    }

    if (newInvoiceNumber.isNotEmpty) {
      final existingInvoice = await DatabaseService.findByInvoiceSignature(
        invoiceNumber: newInvoiceNumber,
        supplier: newSupplier,
        date: _date,
        excludeId: _current.id,
      );
      if (existingInvoice != null) {
        if (!mounted) return;
        await _showHardDuplicateBlockedDialog(
          context,
          existing: existingInvoice,
        );
        return;
      }
    }

    // Check for duplicate against OTHER receipts (not self)
    setState(() => _saving = true);
    try {
      final dupes = await DatabaseService.findPossibleDuplicates(
        projectId: newProjectId,
        invoiceNumber: newInvoiceNumber,
        supplier: newSupplier,
        date: _date,
        gross: newGross,
        excludeId: _current.id,
      );
      if (dupes.isNotEmpty) {
        if (!mounted) return;
        setState(() => _saving = false);
        final hardDuplicate = dupes.any(
          (receipt) => _isExactInvoiceDuplicate(
            receipt,
            invoiceNumber: newInvoiceNumber,
            supplier: newSupplier,
            date: _date,
          ),
        );
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(Icons.warning_amber,
                color: Colors.orange.shade700, size: 32),
            title: Text(
              hardDuplicate
                  ? 'Duplicate receipt found'
                  : 'Edit creates a duplicate',
            ),
            content: Text(
              hardDuplicate
                  ? 'A receipt with the same invoice no, supplier, and date already exists. These changes were not saved.'
                  : 'Saving these changes would match an existing receipt with the same supplier, date, and gross amount (#${dupes.first.scanNo?.toString().padLeft(5, '0') ?? dupes.first.id}). These changes were not saved.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
            ],
          ),
        );
        if (ok != true) return;
        setState(() => _saving = true);
      }
    } catch (e) {
      debugPrint('Duplicate check failed: $e');
    }

    try {
      final projectChanged = newProjectId != _current.projectId;
      final updated = _current.copyWith(
        projectId: newProjectId,
        date: _date,
        category: _category,
        invoiceNumber: newInvoiceNumber.isEmpty ? '' : newInvoiceNumber,
        supplier: newSupplier,
        vat: newVat,
        gross: newGross,
        net: newNet,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      await DatabaseService.updateReceipt(updated);
      if (!mounted) return;
      if (projectChanged) {
        Navigator.pop(context, true);
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      // Reload from DB so we get the renamed photo path
      final fresh = await DatabaseService.getById(_current.id!);
      if (fresh != null) {
        setState(() {
          _current = fresh;
          _editing = false;
          _didUpdate = true;
        });
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Updated')),
      );
    } catch (e) {
      if (!mounted) return;
      if (_isDuplicateSignatureError(e)) {
        final existingInvoice = newInvoiceNumber.isNotEmpty
            ? await DatabaseService.findByInvoiceSignature(
                invoiceNumber: newInvoiceNumber,
                supplier: newSupplier,
                date: _date,
                excludeId: _current.id,
              )
            : null;
        if (!mounted) return;
        await _showHardDuplicateBlockedDialog(
          context,
          existing: existingInvoice,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _projectNameById(int? id) {
    if (id == null) return 'Unassigned';
    for (final project in _projects) {
      if (project.id == id) return project.name;
    }
    return 'Project $id';
  }

  Future<void> _shareInvoice() async {
    try {
      final csvFile = await _buildSingleInvoiceCsv(_current);
      final filesToShare = <XFile>[
        XFile(csvFile.path, mimeType: 'text/csv'),
      ];
      final photoPath = _current.photoPath;
      if (photoPath != null && photoPath.trim().isNotEmpty) {
        final file = File(photoPath);
        if (await file.exists()) {
          filesToShare.add(XFile(file.path, mimeType: 'image/jpeg'));
        }
      }
      await Share.shareXFiles(
        filesToShare,
        subject:
            'Invoice #${(_current.scanNo ?? _current.id ?? 0).toString().padLeft(5, '0')}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    }
  }

  Future<File> _buildSingleInvoiceCsv(Receipt receipt) async {
    final dir = await getTemporaryDirectory();
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final scanNo =
        (receipt.scanNo ?? receipt.id ?? 0).toString().padLeft(5, '0');
    final filename = 'invoice_${scanNo}_$ts.csv';
    final path = p.join(dir.path, filename);
    final csv = StringBuffer();
    csv.writeln(
      'ScanNo,Project,InvoiceDate,ScanDate,InvoiceNo,Category,Supplier,Net,VAT,Gross,Notes,PhotoFile',
    );
    final photoFile = receipt.photoPath == null
        ? ''
        : receipt.photoPath!.split('/').last.split('\\').last;
    final values = [
      scanNo,
      _csvEscape(_projectNameById(receipt.projectId)),
      Receipt.formatDate(receipt.date),
      Receipt.formatDate(receipt.createdAt),
      _csvEscape(receipt.invoiceNumber ?? ''),
      _csvEscape(receipt.category),
      _csvEscape(receipt.supplier),
      receipt.net.toStringAsFixed(2),
      receipt.vat.toStringAsFixed(2),
      receipt.gross.toStringAsFixed(2),
      _csvEscape(receipt.notes ?? ''),
      _csvEscape(photoFile),
    ];
    csv.writeln(values.join(','));
    return File(path).writeAsString(csv.toString());
  }

  String _csvEscape(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this receipt?'),
        content: Text(
          '${_current.supplier} — £${_current.gross.toStringAsFixed(2)}\\n\\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await DatabaseService.deleteReceipt(_current);
        if (!mounted) return;
        Navigator.pop(context, true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final scanLabel = _current.scanNo != null
        ? '#${_current.scanNo!.toString().padLeft(5, '0')}'
        : '#${_current.id}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _didUpdate);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Receipt $scanLabel'),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          actions: [
            IconButton(
              icon: const Icon(Icons.cloud_upload),
              tooltip: 'Upload/share invoice',
              onPressed: _shareInvoice,
            ),
            if (!_editing)
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit',
                onPressed: () => setState(() => _editing = true),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: _confirmDelete,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_current.photoPath != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_current.photoPath!),
                    height: 280,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      height: 80,
                      color: Colors.grey.shade100,
                      child: const Center(
                        child: Text('Photo file missing',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'File: ${_current.photoPath != null ? _current.photoPath!.split('/').last.split('\\').last : ""}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
              MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.0),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final twoColumn = constraints.maxWidth >= 360;
                    final gap = twoColumn ? 10.0 : 12.0;
                    final fieldStyle = TextStyle(
                      fontSize: twoColumn ? 18 : 17,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    );

                    final dateField = InkWell(
                      onTap: _editing ? _pickDate : null,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Date',
                          enabled: _editing,
                          suffixIcon: _editing
                              ? const Icon(Icons.calendar_today, size: 18)
                              : null,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            DateFormat('dd/MM/yyyy').format(_date),
                            maxLines: 1,
                            style: fieldStyle,
                          ),
                        ),
                      ),
                    );

                    final invoiceField = TextField(
                      controller: _invoiceNumber,
                      enabled: _editing,
                      style: fieldStyle,
                      textCapitalization: TextCapitalization.characters,
                      decoration:
                          const InputDecoration(labelText: 'Invoice no.'),
                    );

                    final categoryField = DropdownButtonFormField<String>(
                      initialValue: _category,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Category'),
                      style: fieldStyle,
                      selectedItemBuilder: (context) => _categories
                          .map(
                            (c) => Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                c,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: fieldStyle,
                              ),
                            ),
                          )
                          .toList(),
                      items: _categories
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(
                                c,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _editing
                          ? (v) => setState(() => _category = v ?? _category)
                          : null,
                    );

                    final supplierField = TextField(
                      controller: _supplier,
                      enabled: _editing,
                      style: fieldStyle,
                      decoration: const InputDecoration(labelText: 'Supplier'),
                    );

                    final projectField = DropdownButtonFormField<int>(
                      key: ValueKey(
                        'receipt-project-${_projectId ?? 0}-${_projects.length}',
                      ),
                      initialValue: _projects.any((p) => p.id == _projectId)
                          ? _projectId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Project'),
                      style: fieldStyle,
                      selectedItemBuilder: (context) => _projects
                          .where((p) => p.id != null)
                          .map(
                            (p) => Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: fieldStyle,
                              ),
                            ),
                          )
                          .toList(),
                      items: _projects
                          .where((p) => p.id != null)
                          .map(
                            (p) => DropdownMenuItem<int>(
                              value: p.id,
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _editing
                          ? (value) => setState(() => _projectId = value)
                          : null,
                    );

                    final netField = TextField(
                      controller: _net,
                      enabled: _editing,
                      style: fieldStyle,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Net',
                        prefixText: '£ ',
                      ),
                    );

                    final vatField = TextField(
                      controller: _vat,
                      enabled: _editing,
                      style: fieldStyle,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'VAT',
                        prefixText: '£ ',
                      ),
                    );

                    final grossField = TextField(
                      controller: _gross,
                      enabled: _editing,
                      style: fieldStyle,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Gross',
                        prefixText: '£ ',
                      ),
                    );

                    final notesField = TextField(
                      controller: _notes,
                      enabled: _editing,
                      style: fieldStyle,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Notes'),
                    );

                    if (!twoColumn) {
                      return Column(
                        children: [
                          dateField,
                          SizedBox(height: gap),
                          invoiceField,
                          SizedBox(height: gap),
                          categoryField,
                          SizedBox(height: gap),
                          supplierField,
                          SizedBox(height: gap),
                          projectField,
                          SizedBox(height: gap),
                          Row(
                            children: [
                              Expanded(child: netField),
                              const SizedBox(width: 10),
                              Expanded(child: vatField),
                              const SizedBox(width: 10),
                              Expanded(child: grossField),
                            ],
                          ),
                          SizedBox(height: gap),
                          notesField,
                        ],
                      );
                    }

                    return Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 11, child: dateField),
                            const SizedBox(width: 10),
                            Expanded(flex: 12, child: invoiceField),
                          ],
                        ),
                        SizedBox(height: gap),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 9, child: categoryField),
                            const SizedBox(width: 10),
                            Expanded(flex: 14, child: supplierField),
                          ],
                        ),
                        SizedBox(height: gap),
                        projectField,
                        SizedBox(height: gap),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: netField),
                            const SizedBox(width: 10),
                            Expanded(child: vatField),
                            const SizedBox(width: 10),
                            Expanded(child: grossField),
                          ],
                        ),
                        SizedBox(height: gap),
                        notesField,
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Saved: ${DateFormat('dd/MM/yyyy HH:mm').format(_current.createdAt)}'
                  '${_current.updatedAt.difference(_current.createdAt).inSeconds > 5 ? "\nLast edited: ${DateFormat('dd/MM/yyyy HH:mm').format(_current.updatedAt)}" : ""}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 24),
              if (_editing)
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Saving...' : 'Save changes'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _settingsStorage = FlutterSecureStorage();
  static const _clientNameKey = 'client_name';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Management')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader(title: 'Client'),
          Card(
            child: FutureBuilder<String>(
              future: _clientName(),
              builder: (context, snapshot) {
                final clientName = snapshot.data?.trim() ?? '';
                return ListTile(
                  leading: Icon(Icons.person, color: colorScheme.primary),
                  title: const Text('Client name'),
                  subtitle: Text(
                    clientName.isEmpty ? 'Not set' : clientName,
                  ),
                  trailing: const Icon(Icons.edit, size: 20),
                  onTap: () => _editClientName(context),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          const _SectionHeader(title: 'Data'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.backup, color: colorScheme.primary),
                  title: const Text('Backup database and images'),
                  subtitle: const Text('Creates a restorable ZIP backup'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _runBackup(context),
                ),
                _SettingsDivider(),
                ListTile(
                  leading:
                      Icon(Icons.photo_library, color: colorScheme.primary),
                  title: const Text('Backup receipt images'),
                  subtitle:
                      const Text('Creates a ZIP of invoice/receipt photos'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _runPhotoBackup(context),
                ),
                _SettingsDivider(),
                ListTile(
                  leading: Icon(Icons.restore, color: colorScheme.primary),
                  title: const Text('Restore backup'),
                  subtitle:
                      const Text('Restore from backups created on this phone'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _runRestore(context),
                ),
                _SettingsDivider(),
                ListTile(
                  leading: Icon(Icons.delete_forever, color: colorScheme.error),
                  title: Text('Reset database',
                      style: TextStyle(color: colorScheme.error)),
                  subtitle: const Text(
                      'Delete receipts, projects, categories, and photos'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _confirmReset(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionHeader(title: 'App'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.auto_awesome, color: colorScheme.primary),
                  title: const Text('Gemini API Settings'),
                  subtitle: const Text('Configure API key and model'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const GeminiSettingsPage()),
                    );
                  },
                ),
                _SettingsDivider(),
                ListTile(
                  leading: Icon(Icons.bolt, color: colorScheme.primary),
                  title: const Text('DeepSeek API Settings'),
                  subtitle: const Text('OCR text parsing key and model'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const DeepSeekSettingsPage()),
                    );
                  },
                ),
                _SettingsDivider(),
                ListTile(
                  leading: Icon(Icons.info_outline,
                      color: colorScheme.onSurfaceVariant),
                  title: const Text('About'),
                  subtitle: const Text('Receipt Scanner v0.9.0'),
                ),
                _SettingsDivider(),
                ListTile(
                  leading: Icon(Icons.exit_to_app, color: colorScheme.error),
                  title: Text('Exit app',
                      style: TextStyle(color: colorScheme.error)),
                  onTap: () => SystemNavigator.pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _clientName() async {
    return (await _settingsStorage.read(key: _clientNameKey))?.trim() ?? '';
  }

  Future<void> _editClientName(BuildContext context) async {
    final controller = TextEditingController(text: await _clientName());
    if (!context.mounted) {
      controller.dispose();
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Client name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Client name',
            hintText: 'e.g. Iqbal Ahmed',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    if (result == null) return;
    await _settingsStorage.write(key: _clientNameKey, value: result);
    if (!context.mounted) return;
    _showMessage(context, 'Client name saved.');
    (context as Element).markNeedsBuild();
  }

  Future<void> _runBackup(BuildContext context) async {
    _showMessage(context, 'Building backup...');
    try {
      final backup = await _createFullBackupZip();
      if (!context.mounted) return;
      await Share.shareXFiles(
        [XFile(backup.path, mimeType: 'application/zip')],
        subject: 'Receipt Scanner Backup',
        text:
            'Full backup ZIP. Keep this file to restore database and receipt images.',
      );
      if (!context.mounted) return;
      _showMessage(context, 'Backup ready: ${p.basename(backup.path)}');
    } catch (e) {
      if (!context.mounted) return;
      _showMessage(context, 'Backup failed: $e');
    }
  }

  Future<void> _runPhotoBackup(BuildContext context) async {
    _showMessage(context, 'Building image backup...');
    try {
      final backup = await _createPhotoBackupZip();
      if (!context.mounted) return;
      await Share.shareXFiles(
        [XFile(backup.path, mimeType: 'application/zip')],
        subject: 'Receipt Image Backup',
        text: 'Receipt/invoice image ZIP backup.',
      );
      if (!context.mounted) return;
      _showMessage(context, 'Image backup ready: ${p.basename(backup.path)}');
    } catch (e) {
      if (!context.mounted) return;
      _showMessage(context, 'Image backup failed: $e');
    }
  }

  Future<void> _runRestore(BuildContext context) async {
    final backups = await _localFullBackups();
    if (!context.mounted) return;
    if (backups.isEmpty) {
      _showMessage(
          context, 'No local full backups found. Create a backup first.');
      return;
    }

    final selected = await showDialog<File>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Restore backup'),
        children: [
          for (final backup in backups)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, backup),
              child: Text(
                '${p.basename(backup.path)}\n${DateFormat('dd/MM/yyyy HH:mm').format(backup.lastModifiedSync())}',
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber, color: Colors.orange.shade700),
        title: const Text('Restore this backup?'),
        content: Text(
          'This will replace the current database and receipt images with:\n\n${p.basename(selected.path)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await _restoreFullBackup(selected);
      if (!context.mounted) return;
      _showMessage(context, 'Restored. Close and reopen the app.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      _showMessage(context, 'Restore failed: $e');
    }
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber, color: Colors.orange.shade700),
        title: const Text('Reset database?'),
        content: const Text(
          'This will permanently delete all receipts, projects, custom categories, and photos.\n\n'
          'Default categories will be re-created. This cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );

    if (ok != true || !context.mounted) return;

    try {
      await DatabaseService.clearEverything();
      if (!context.mounted) return;
      _showMessage(context, 'Database reset.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      _showMessage(context, 'Reset failed: $e');
    }
  }

  Future<File> _createFullBackupZip() async {
    final backupsDir = await _backupsDir();
    final tempDir = await getTemporaryDirectory();
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final clientTag = _filenameTag(await _clientName());
    final backupName = [
      'receipt_scanner_backup',
      if (clientTag.isNotEmpty) clientTag,
      ts,
    ].join('_');
    final backupPath = p.join(
      backupsDir.path,
      '$backupName.zip',
    );

    await DatabaseService.closeConnection();
    final dbPath = await DatabaseService.getDatabasePath();
    final photosDir = await DatabaseService.getPhotosDir();
    final manifest =
        File(p.join(tempDir.path, 'receipt_backup_manifest_$ts.json'));
    await manifest.writeAsString(
      jsonEncode({
        'type': 'receipt_scanner_full_backup',
        'created_at': DateTime.now().toIso8601String(),
        'client_name': await _clientName(),
        'database': 'receipt_scanner.db',
        'photos_dir': 'receipts',
      }),
    );

    final encoder = ZipFileEncoder();
    encoder.create(backupPath);
    await encoder.addFile(File(dbPath), 'receipt_scanner.db');
    await encoder.addFile(manifest, 'manifest.json');
    if (await photosDir.exists()) {
      await encoder.addDirectory(photosDir, includeDirName: true);
    }
    await encoder.close();
    return File(backupPath);
  }

  Future<File> _createPhotoBackupZip() async {
    final photosDir = await DatabaseService.getPhotosDir();
    final photoCount = await _countFiles(photosDir);
    if (photoCount == 0) {
      throw StateError('No receipt images found.');
    }
    final backupsDir = await _backupsDir();
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final clientTag = _filenameTag(await _clientName());
    final backupName = [
      'receipt_images_backup',
      if (clientTag.isNotEmpty) clientTag,
      ts,
    ].join('_');
    final backupPath = p.join(
      backupsDir.path,
      '$backupName.zip',
    );
    final encoder = ZipFileEncoder();
    encoder.create(backupPath);
    await encoder.addDirectory(photosDir, includeDirName: true);
    await encoder.close();
    return File(backupPath);
  }

  Future<void> _restoreFullBackup(File backup) async {
    final tempDir = await getTemporaryDirectory();
    final restoreDir = Directory(
      p.join(tempDir.path,
          'receipt_restore_${DateTime.now().millisecondsSinceEpoch}'),
    );
    if (await restoreDir.exists()) {
      await restoreDir.delete(recursive: true);
    }
    await restoreDir.create(recursive: true);

    final archive = ZipDecoder().decodeBytes(await backup.readAsBytes());
    await extractArchiveToDisk(archive, restoreDir.path);

    final restoredDb = File(p.join(restoreDir.path, 'receipt_scanner.db'));
    if (!await restoredDb.exists()) {
      throw StateError('Backup does not contain receipt_scanner.db.');
    }

    await DatabaseService.closeConnection();
    final dbPath = await DatabaseService.getDatabasePath();
    await restoredDb.copy(dbPath);

    final restoredPhotos = Directory(p.join(restoreDir.path, 'receipts'));
    final photosDir = await DatabaseService.getPhotosDir();
    if (await photosDir.exists()) {
      await photosDir.delete(recursive: true);
    }
    await photosDir.create(recursive: true);
    if (await restoredPhotos.exists()) {
      await _copyDirectoryContents(restoredPhotos, photosDir);
    }
  }

  Future<List<File>> _localFullBackups() async {
    final dir = await _backupsDir();
    final backups = dir
        .listSync()
        .whereType<File>()
        .where((file) =>
            p.basename(file.path).startsWith('receipt_scanner_backup_') &&
            p.extension(file.path).toLowerCase() == '.zip')
        .toList();
    backups
        .sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return backups;
  }

  Future<Directory> _backupsDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docDir.path, 'backups'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _copyDirectoryContents(
      Directory source, Directory target) async {
    await for (final entity in source.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: source.path);
      final destination = File(p.join(target.path, relative));
      await destination.parent.create(recursive: true);
      await entity.copy(destination.path);
    }
  }

  Future<int> _countFiles(Directory dir) async {
    if (!await dir.exists()) return 0;
    var count = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) count++;
    }
    return count;
  }

  String _filenameTag(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 56,
      endIndent: 16,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
