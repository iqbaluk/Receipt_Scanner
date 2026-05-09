part of '../main.dart';

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
