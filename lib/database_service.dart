// ============================================================
// Database Service - SQLite + smart-named photos
// ============================================================
// Photos are saved with smart filenames at save time:
//   <scan_no>_<date>_<category>_<supplier>_<amount>.jpg
//   e.g. 00042_2026-04-30_Material_BandQ_127.50.jpg
//
// Schema:
//   tbl_receipts:
//     id              INTEGER PRIMARY KEY AUTOINCREMENT
//     project_id      INTEGER   (links to tbl_projects)
//     scan_no         INTEGER UNIQUE  (sequential, starts at 1)
//     date            TEXT      (YYYY-MM-DD)
//     invoice_number  TEXT
//     category        TEXT
//     supplier        TEXT
//     vat             REAL
//     gross           REAL
//     net             REAL
//     notes           TEXT
//     photo_path      TEXT      (full path to the smart-named jpg)
//     created_at      TEXT
//     updated_at      TEXT
// ============================================================

import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'utils/text_normalizers.dart';

class Project {
  final int? id;
  final String name;
  final String? address;
  final DateTime? startDate;
  final double? budget;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int receiptCount;
  final double totalGross;

  Project({
    this.id,
    required this.name,
    this.address,
    this.startDate,
    this.budget,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.receiptCount = 0,
    this.totalGross = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'address': address,
      'start_date': startDate == null ? null : Receipt.formatDate(startDate!),
      'budget': budget,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Project.fromMap(Map<String, dynamic> map) {
    return Project(
      id: map['id'] as int?,
      name: map['name'] as String,
      address: map['address'] as String?,
      startDate: map['start_date'] == null
          ? null
          : DateTime.parse(map['start_date'] as String),
      budget: (map['budget'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      receiptCount: (map['receipt_count'] as num?)?.toInt() ?? 0,
      totalGross: (map['total_gross'] as num?)?.toDouble() ?? 0,
    );
  }
}

class AppCategory {
  final int? id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  AppCategory({
    this.id,
    required this.name,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory AppCategory.fromMap(Map<String, dynamic> map) {
    return AppCategory(
      id: map['id'] as int?,
      name: map['name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

class CategorySummary {
  final String category;
  final int receiptCount;
  final double totalNet;
  final double totalVat;
  final double totalGross;

  CategorySummary({
    required this.category,
    required this.receiptCount,
    required this.totalNet,
    required this.totalVat,
    required this.totalGross,
  });

  factory CategorySummary.fromMap(Map<String, dynamic> map) {
    return CategorySummary(
      category: map['category'] as String,
      receiptCount: (map['receipt_count'] as num?)?.toInt() ?? 0,
      totalNet: (map['total_net'] as num?)?.toDouble() ?? 0,
      totalVat: (map['total_vat'] as num?)?.toDouble() ?? 0,
      totalGross: (map['total_gross'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ProjectReport {
  final int receiptCount;
  final double totalNet;
  final double totalVat;
  final double totalGross;
  final List<CategorySummary> categories;

  ProjectReport({
    required this.receiptCount,
    required this.totalNet,
    required this.totalVat,
    required this.totalGross,
    required this.categories,
  });
}

class Receipt {
  final int? id;
  final int? projectId;
  final int? scanNo;
  final DateTime date;
  final String? invoiceNumber;
  final String category;
  final String supplier;
  final double vat;
  final double gross;
  final double net;
  final String? notes;
  final String? photoPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  Receipt({
    this.id,
    this.projectId,
    this.scanNo,
    required this.date,
    this.invoiceNumber,
    required this.category,
    required this.supplier,
    required this.vat,
    required this.gross,
    required this.net,
    this.notes,
    this.photoPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (scanNo != null) 'scan_no': scanNo,
      'date': formatDate(date),
      'invoice_number': invoiceNumber,
      'category': category,
      'supplier': supplier,
      'vat': vat,
      'gross': gross,
      'net': net,
      'notes': notes,
      'photo_path': photoPath,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Receipt.fromMap(Map<String, dynamic> map) {
    return Receipt(
      id: map['id'] as int?,
      projectId: map['project_id'] as int?,
      scanNo: map['scan_no'] as int?,
      date: DateTime.parse(map['date'] as String),
      invoiceNumber: map['invoice_number'] as String?,
      category: map['category'] as String,
      supplier: map['supplier'] as String,
      vat: (map['vat'] as num).toDouble(),
      gross: (map['gross'] as num).toDouble(),
      net: (map['net'] as num).toDouble(),
      notes: map['notes'] as String?,
      photoPath: map['photo_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Receipt copyWith({
    int? id,
    int? projectId,
    int? scanNo,
    DateTime? date,
    String? invoiceNumber,
    String? category,
    String? supplier,
    double? vat,
    double? gross,
    double? net,
    String? notes,
    String? photoPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Receipt(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      scanNo: scanNo ?? this.scanNo,
      date: date ?? this.date,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      category: category ?? this.category,
      supplier: supplier ?? this.supplier,
      vat: vat ?? this.vat,
      gross: gross ?? this.gross,
      net: net ?? this.net,
      notes: notes ?? this.notes,
      photoPath: photoPath ?? this.photoPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String formatDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// Build the smart filename for this receipt.
  /// Pattern: NNNNN_YYYY-MM-DD_Category_Supplier_AMOUNT.jpg
  String buildSmartFilename({String ext = 'jpg'}) {
    final scan = (scanNo ?? 0).toString().padLeft(5, '0');
    final dateStr = formatDate(date);
    final cat = _sanitizeForFilename(category);
    final sup = _sanitizeForFilename(supplier);
    final amt = gross.toStringAsFixed(2);
    return '${scan}_${dateStr}_${cat}_${sup}_$amt.$ext';
  }

  /// Sanitise a string for use in a filename:
  /// - Replace & with "and"
  /// - Remove characters that are invalid in filenames
  /// - Trim and replace spaces with nothing (keep readable but compact)
  static String _sanitizeForFilename(String input) {
    var s = input.trim();
    s = s.replaceAll('&', 'and');
    // Remove invalid filename characters: < > : " / \ | ? *
    s = s.replaceAll(RegExp(r'[<>:"/\\|?*]'), '');
    // Replace spaces with nothing for compact names (BandQ, TravisPerkins)
    s = s.replaceAll(' ', '');
    // Strip non-alphanumeric (allow hyphen and dot)
    s = s.replaceAll(RegExp(r'[^A-Za-z0-9\-.]'), '');
    if (s.isEmpty) s = 'unknown';
    // Cap length so filenames don't get silly
    if (s.length > 30) s = s.substring(0, 30);
    return s;
  }
}

class DatabaseService {
  static const String _dbName = 'receipt_scanner.db';
  static const String _table = 'tbl_receipts';
  static const String _projectsTable = 'tbl_projects';
  static const String _categoriesTable = 'tbl_categories';
  static const int _dbVersion = 7;

  static const List<String> defaultCategories = [
    'Material',
    'Subcontractor',
    'Utility Bills',
    'Travel',
    'Insurance',
    'Sundries',
    'Other',
  ];

  static Database? _db;

  static Future<String> getDatabasePath() async {
    final docDir = await getApplicationDocumentsDirectory();
    return p.join(docDir.path, _dbName);
  }

  static Future<Database> _open() async {
    if (_db != null) return _db!;

    final path = await getDatabasePath();

    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createProjectsTable(db);
        await _createCategoriesTable(db);
        await _seedDefaultCategories(db);
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER,
            scan_no INTEGER UNIQUE,
            date TEXT NOT NULL,
            invoice_number TEXT,
            category TEXT NOT NULL,
            supplier TEXT NOT NULL,
            vat REAL NOT NULL DEFAULT 0,
            gross REAL NOT NULL DEFAULT 0,
            net REAL NOT NULL DEFAULT 0,
            notes TEXT,
            photo_path TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(project_id) REFERENCES $_projectsTable(id)
          )
        ''');
        final defaultProjectId = await _insertDefaultProject(db);
        await db.execute('CREATE INDEX idx_${_table}_date ON $_table(date)');
        await db.execute(
            'CREATE INDEX idx_${_table}_invoice_number ON $_table(invoice_number)');
        await db.execute(
            'CREATE INDEX idx_${_table}_category ON $_table(category)');
        await db
            .execute('CREATE INDEX idx_${_table}_scan_no ON $_table(scan_no)');
        await db.execute(
            'CREATE INDEX idx_${_table}_project_id ON $_table(project_id)');
        await _createDuplicateIntegrityTriggers(db);
        await db.update(
          _table,
          {'project_id': defaultProjectId},
          where: 'project_id IS NULL',
        );
      },
      onUpgrade: (db, oldV, newV) async {
        // Future migrations go here
        if (oldV < 2) {
          // V1 -> V2 added scan_no column. Backfill existing rows.
          try {
            await db.execute('ALTER TABLE $_table ADD COLUMN scan_no INTEGER');
            await db.execute(
                'CREATE INDEX idx_${_table}_scan_no ON $_table(scan_no)');
            // Assign sequential scan_no by id
            final rows = await db.query(_table, orderBy: 'id ASC');
            for (var i = 0; i < rows.length; i++) {
              await db.update(
                _table,
                {'scan_no': i + 1},
                where: 'id = ?',
                whereArgs: [rows[i]['id']],
              );
            }
          } catch (e) {
            // Column may already exist if user did a clean install
          }
        }
        if (oldV < 3) {
          await _createProjectsTable(db);
          final defaultProjectId = await _insertDefaultProject(db);
          try {
            await db
                .execute('ALTER TABLE $_table ADD COLUMN project_id INTEGER');
          } catch (_) {
            // Column may already exist if a previous migration was interrupted
          }
          await db.update(
            _table,
            {'project_id': defaultProjectId},
            where: 'project_id IS NULL',
          );
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_${_table}_project_id ON $_table(project_id)');
        }
        if (oldV < 4) {
          await _createCategoriesTable(db);
          await _seedDefaultCategories(db);
        }
        if (oldV < 5) {
          try {
            await db
                .execute('ALTER TABLE $_table ADD COLUMN invoice_number TEXT');
          } catch (_) {
            // Column may already exist if a previous migration was interrupted
          }
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_${_table}_invoice_number ON $_table(invoice_number)');
        }
        if (oldV < 6) {
          await _createDuplicateIntegrityTriggers(db);
        }
        if (oldV < 7) {
          await _refreshDuplicateIntegrityTriggers(db);
        }
      },
    );

    await _refreshDuplicateIntegrityTriggers(_db!);

    return _db!;
  }

  static Future<void> closeConnection() async {
    final db = _db;
    _db = null;
    await db?.close();
  }

  static Future<void> clearEverything() async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete(_table);
      await txn.delete(_projectsTable);
      await txn.delete(_categoriesTable);
      await _seedDefaultCategories(txn);
    });

    final photosDir = await getPhotosDir();
    if (await photosDir.exists()) {
      await for (final entry in photosDir.list()) {
        if (entry is File) {
          try {
            await entry.delete();
          } catch (_) {
            // Ignore files that cannot be removed; database reset still stands.
          }
        }
      }
    }
  }

  static Future<void> _createProjectsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_projectsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        address TEXT,
        start_date TEXT,
        budget REAL,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createDuplicateIntegrityTriggers(
      DatabaseExecutor db) async {
    final existingInvoiceSql = _normalisedInvoiceSql('r.invoice_number');
    final newInvoiceSql = _normalisedInvoiceSql('NEW.invoice_number');
    final existingSupplierSql = _normalisedSupplierSql('r.supplier');
    final newSupplierSql = _normalisedSupplierSql('NEW.supplier');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_receipts_no_dup_invoice_signature_insert
      BEFORE INSERT ON $_table
      WHEN TRIM(COALESCE(NEW.invoice_number, '')) <> ''
      BEGIN
        SELECT RAISE(ABORT, 'DUPLICATE_INVOICE_SIGNATURE')
        WHERE EXISTS (
          SELECT 1
          FROM $_table r
          WHERE $existingInvoiceSql = $newInvoiceSql
            AND $existingSupplierSql = $newSupplierSql
            AND r.date = NEW.date
        );
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_receipts_no_dup_invoice_signature_update
      BEFORE UPDATE ON $_table
      WHEN TRIM(COALESCE(NEW.invoice_number, '')) <> ''
      BEGIN
        SELECT RAISE(ABORT, 'DUPLICATE_INVOICE_SIGNATURE')
        WHERE EXISTS (
          SELECT 1
          FROM $_table r
          WHERE r.id != NEW.id
            AND $existingInvoiceSql = $newInvoiceSql
            AND $existingSupplierSql = $newSupplierSql
            AND r.date = NEW.date
        );
      END;
    ''');
  }

  static Future<void> _refreshDuplicateIntegrityTriggers(
      DatabaseExecutor db) async {
    await db.execute(
        'DROP TRIGGER IF EXISTS trg_receipts_no_dup_invoice_signature_insert');
    await db.execute(
        'DROP TRIGGER IF EXISTS trg_receipts_no_dup_invoice_signature_update');
    await _createDuplicateIntegrityTriggers(db);
  }

  static Future<void> _createCategoriesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_categoriesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _seedDefaultCategories(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();
    for (final name in defaultCategories) {
      await db.insert(
        _categoriesTable,
        {
          'name': name,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  static Future<int> _insertDefaultProject(Database db) async {
    final existing = await db.query(
      _projectsTable,
      where: 'name = ?',
      whereArgs: ['General'],
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.first['id'] as int;
    final now = DateTime.now().toIso8601String();
    return db.insert(_projectsTable, {
      'name': 'General',
      'address': null,
      'start_date': null,
      'budget': null,
      'notes': 'Default project for existing receipts',
      'created_at': now,
      'updated_at': now,
    });
  }

  static Future<int> _defaultProjectId(Database db) async {
    return _insertDefaultProject(db);
  }

  static Future<List<Project>> getProjects() async {
    final db = await _open();
    final rows = await db.rawQuery('''
      SELECT p.*,
             COUNT(r.id) AS receipt_count,
             COALESCE(SUM(r.gross), 0) AS total_gross
      FROM $_projectsTable p
      LEFT JOIN $_table r ON r.project_id = p.id
      GROUP BY p.id
      ORDER BY p.created_at DESC, p.id DESC
    ''');
    return rows.map((r) => Project.fromMap(r)).toList();
  }

  static Future<ProjectReport> getProjectReport({
    int? projectId,
    DateTime? from,
    DateTime? to,
    bool useScanDate = false,
  }) async {
    final db = await _open();
    final filters = <String>[];
    final args = <dynamic>[];

    if (projectId != null) {
      filters.add('project_id = ?');
      args.add(projectId);
    }

    if (from != null && to != null) {
      final dateExpr = useScanDate ? 'substr(created_at, 1, 10)' : 'date';
      filters.add('$dateExpr >= ? AND $dateExpr <= ?');
      args
        ..add(Receipt.formatDate(from))
        ..add(Receipt.formatDate(to));
    }

    final where = filters.isEmpty ? '' : 'WHERE ${filters.join(' AND ')}';
    final totals = await db.rawQuery('''
      SELECT COUNT(*) AS receipt_count,
             COALESCE(SUM(net), 0) AS total_net,
             COALESCE(SUM(vat), 0) AS total_vat,
             COALESCE(SUM(gross), 0) AS total_gross
      FROM $_table
      $where
    ''', args);

    final categoryRows = await db.rawQuery('''
      SELECT category,
             COUNT(*) AS receipt_count,
             COALESCE(SUM(net), 0) AS total_net,
             COALESCE(SUM(vat), 0) AS total_vat,
             COALESCE(SUM(gross), 0) AS total_gross
      FROM $_table
      $where
      GROUP BY category
      ORDER BY total_gross DESC, category ASC
    ''', args);

    final total = totals.first;
    return ProjectReport(
      receiptCount: (total['receipt_count'] as num?)?.toInt() ?? 0,
      totalNet: (total['total_net'] as num?)?.toDouble() ?? 0,
      totalVat: (total['total_vat'] as num?)?.toDouble() ?? 0,
      totalGross: (total['total_gross'] as num?)?.toDouble() ?? 0,
      categories: categoryRows.map((r) => CategorySummary.fromMap(r)).toList(),
    );
  }

  static Future<Project> createProject(Project draft) async {
    final db = await _open();
    final now = DateTime.now();
    final toSave = Project(
      name: draft.name.trim(),
      address: draft.address?.trim().isEmpty == true ? null : draft.address,
      startDate: draft.startDate,
      budget: draft.budget,
      notes: draft.notes?.trim().isEmpty == true ? null : draft.notes,
      createdAt: now,
      updatedAt: now,
    );
    final id = await db.insert(_projectsTable, toSave.toMap());
    return Project(
      id: id,
      name: toSave.name,
      address: toSave.address,
      startDate: toSave.startDate,
      budget: toSave.budget,
      notes: toSave.notes,
      createdAt: toSave.createdAt,
      updatedAt: toSave.updatedAt,
    );
  }

  static Future<List<AppCategory>> getCategories() async {
    final db = await _open();
    final rows = await db.query(
      _categoriesTable,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    if (rows.isEmpty) {
      await _seedDefaultCategories(db);
      final seeded = await db.query(
        _categoriesTable,
        orderBy: 'name COLLATE NOCASE ASC',
      );
      return seeded.map((r) => AppCategory.fromMap(r)).toList();
    }
    return rows.map((r) => AppCategory.fromMap(r)).toList();
  }

  static Future<AppCategory> createCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Category name cannot be empty');
    }
    final db = await _open();
    final now = DateTime.now();
    final category = AppCategory(
      name: trimmed,
      createdAt: now,
      updatedAt: now,
    );
    final id = await db.insert(_categoriesTable, category.toMap());
    return AppCategory(
      id: id,
      name: category.name,
      createdAt: category.createdAt,
      updatedAt: category.updatedAt,
    );
  }

  static Future<int> updateCategory(
      AppCategory category, String newName) async {
    if (category.id == null) {
      throw ArgumentError('Cannot update a category without an id');
    }
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Category name cannot be empty');
    }
    final db = await _open();
    return db.transaction((txn) async {
      await txn.update(
        _categoriesTable,
        {
          'name': trimmed,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [category.id],
      );
      await txn.update(
        _table,
        {
          'category': trimmed,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'category = ?',
        whereArgs: [category.name],
      );
      return 1;
    });
  }

  static Future<int> deleteCategory(AppCategory category) async {
    if (category.id == null) {
      throw ArgumentError('Cannot delete a category without an id');
    }
    final db = await _open();
    final used = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM $_table WHERE category = ?',
            [category.name],
          ),
        ) ??
        0;
    if (used > 0) {
      throw StateError(
        'This category is used by $used receipts. Rename it or move those receipts first.',
      );
    }
    return db.delete(
      _categoriesTable,
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  static Future<int> updateProject(Project project) async {
    if (project.id == null) {
      throw ArgumentError('Cannot update a project without an id');
    }
    final db = await _open();
    final updated = Project(
      id: project.id,
      name: project.name.trim(),
      address: project.address?.trim().isEmpty == true
          ? null
          : project.address?.trim(),
      startDate: project.startDate,
      budget: project.budget,
      notes:
          project.notes?.trim().isEmpty == true ? null : project.notes?.trim(),
      createdAt: project.createdAt,
      updatedAt: DateTime.now(),
    );
    return db.update(
      _projectsTable,
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [project.id],
    );
  }

  static Future<int> deleteProject(Project project) async {
    if (project.id == null) {
      throw ArgumentError('Cannot delete a project without an id');
    }
    final db = await _open();
    final receiptCount = await count(projectId: project.id);
    if (receiptCount > 0) {
      throw StateError('Move or delete receipts before deleting this project.');
    }
    return db.delete(
      _projectsTable,
      where: 'id = ?',
      whereArgs: [project.id],
    );
  }

  /// Get the next scan_no (highest + 1, starting from 1).
  static Future<int> _nextScanNo(Database db) async {
    final result =
        await db.rawQuery('SELECT MAX(scan_no) as max_no FROM $_table');
    final maxNo = result.first['max_no'] as int?;
    return (maxNo ?? 0) + 1;
  }

  /// Photos directory on phone: <docs>/receipts/
  static Future<Directory> getPhotosDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(docDir.path, 'receipts'));
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    return photosDir;
  }

  /// Save photo bytes to a temporary location BEFORE we know the smart name.
  /// Returns the temp path. Used during the scan phase, before save.
  static Future<String> savePhotoTemp(Uint8List bytes,
      {String ext = 'jpg'}) async {
    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final filePath = p.join(tempDir.path, 'pending_$ts.$ext');
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    return filePath;
  }

  /// Save a receipt with photo. Generates scan_no, smart filename, and
  /// moves the temp photo to its final smart-named location.
  /// Returns the saved Receipt with id, scanNo, and final photoPath populated.
  static Future<Receipt> saveReceipt({
    required Receipt draft,
    Uint8List? photoBytes,
  }) async {
    final db = await _open();
    final projectId = draft.projectId ?? await _defaultProjectId(db);
    final scanNo = await _nextScanNo(db);

    String? finalPhotoPath;
    if (photoBytes != null) {
      // Build the smart filename now that we have scan_no
      final receiptForName = draft.copyWith(
        projectId: projectId,
        scanNo: scanNo,
      );
      final filename = receiptForName.buildSmartFilename();
      final photosDir = await getPhotosDir();
      final filePath = p.join(photosDir.path, filename);
      await File(filePath).writeAsBytes(photoBytes);
      finalPhotoPath = filePath;
    }

    final toSave = draft.copyWith(
      projectId: projectId,
      scanNo: scanNo,
      photoPath: finalPhotoPath,
    );

    final id = await db.insert(_table, toSave.toMap());
    return toSave.copyWith(id: id);
  }

  /// Update an existing receipt. If category/supplier/date/amount changed,
  /// the photo file is renamed to match the new smart filename.
  static Future<int> updateReceipt(Receipt r) async {
    if (r.id == null) {
      throw ArgumentError('Cannot update a receipt without an id');
    }
    final db = await _open();

    String? newPhotoPath = r.photoPath;
    if (r.photoPath != null && r.scanNo != null) {
      final expectedName = r.buildSmartFilename();
      final currentName = p.basename(r.photoPath!);
      if (expectedName != currentName) {
        // Rename the file to match the new data
        final photosDir = await getPhotosDir();
        final newPath = p.join(photosDir.path, expectedName);
        try {
          final f = File(r.photoPath!);
          if (await f.exists()) {
            await f.rename(newPath);
            newPhotoPath = newPath;
          }
        } catch (_) {/* keep old path on failure */}
      }
    }

    final updated = r.copyWith(
      photoPath: newPhotoPath,
      updatedAt: DateTime.now(),
    );
    return db.update(
      _table,
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [r.id],
    );
  }

  static Future<int> deleteReceipt(Receipt r) async {
    final db = await _open();
    if (r.photoPath != null) {
      try {
        final f = File(r.photoPath!);
        if (await f.exists()) await f.delete();
      } catch (_) {/* ignore */}
    }
    return db.delete(_table, where: 'id = ?', whereArgs: [r.id]);
  }

  static Future<List<Receipt>> getRecent(
      {int limit = 10, int? projectId}) async {
    final db = await _open();
    final rows = await db.query(
      _table,
      where: projectId == null ? null : 'project_id = ?',
      whereArgs: projectId == null ? null : [projectId],
      orderBy: 'scan_no DESC, id DESC',
      limit: limit,
    );
    return rows.map((r) => Receipt.fromMap(r)).toList();
  }

  static Future<List<Receipt>> searchReceipts({
    String query = '',
    int? projectId,
    int limit = 50,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return getRecent(limit: limit, projectId: projectId);
    }

    final db = await _open();
    final searchTerms = <String>{trimmed, _normaliseDateQuery(trimmed)}
        .where((term) => term.isNotEmpty)
        .toList();
    final filters = <String>[];
    final args = <dynamic>[];

    if (projectId != null) {
      filters.add('project_id = ?');
      args.add(projectId);
    }

    final searchParts = <String>[];
    for (final term in searchTerms) {
      final like = '%$term%';
      searchParts.add('''
        LOWER(supplier) LIKE LOWER(?)
        OR LOWER(invoice_number) LIKE LOWER(?)
        OR LOWER(category) LIKE LOWER(?)
        OR date LIKE ?
        OR substr(created_at, 1, 10) LIKE ?
        OR CAST(scan_no AS TEXT) LIKE ?
        OR printf('%.2f', gross) LIKE ?
        OR printf('%.2f', vat) LIKE ?
        OR printf('%.2f', net) LIKE ?
      ''');
      args
        ..add(like)
        ..add(like)
        ..add(like)
        ..add(like)
        ..add(like)
        ..add(like)
        ..add(like)
        ..add(like)
        ..add(like);
    }
    filters.add('(${searchParts.join(' OR ')})');

    final rows = await db.query(
      _table,
      where: filters.join(' AND '),
      whereArgs: args,
      orderBy: 'scan_no DESC, id DESC',
      limit: limit,
    );
    return rows.map((r) => Receipt.fromMap(r)).toList();
  }

  static Future<List<Receipt>> filterReceipts({
    int? projectId,
    String? supplier,
    String? category,
    double? exactGross,
    double? minGross,
    double? maxGross,
    DateTime? invoiceFrom,
    DateTime? invoiceTo,
    DateTime? scanFrom,
    DateTime? scanTo,
    int limit = 500,
  }) async {
    final db = await _open();
    final filters = <String>[];
    final args = <dynamic>[];

    if (projectId != null) {
      filters.add('project_id = ?');
      args.add(projectId);
    }

    final supplierText = supplier?.trim() ?? '';
    if (supplierText.isNotEmpty) {
      filters.add('LOWER(supplier) LIKE LOWER(?)');
      args.add('%$supplierText%');
    }

    final categoryText = category?.trim() ?? '';
    if (categoryText.isNotEmpty && categoryText != 'All') {
      filters.add('category = ?');
      args.add(categoryText);
    }

    if (exactGross != null) {
      filters.add('ABS(gross - ?) < 0.005');
      args.add(exactGross);
    } else {
      if (minGross != null) {
        filters.add('gross >= ?');
        args.add(minGross);
      }
      if (maxGross != null) {
        filters.add('gross <= ?');
        args.add(maxGross);
      }
    }

    if (invoiceFrom != null) {
      filters.add('date >= ?');
      args.add(Receipt.formatDate(invoiceFrom));
    }
    if (invoiceTo != null) {
      filters.add('date <= ?');
      args.add(Receipt.formatDate(invoiceTo));
    }

    if (scanFrom != null) {
      filters.add('substr(created_at, 1, 10) >= ?');
      args.add(Receipt.formatDate(scanFrom));
    }
    if (scanTo != null) {
      filters.add('substr(created_at, 1, 10) <= ?');
      args.add(Receipt.formatDate(scanTo));
    }

    final rows = await db.query(
      _table,
      where: filters.isEmpty ? null : filters.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'scan_no DESC, id DESC',
      limit: limit,
    );
    return rows.map((r) => Receipt.fromMap(r)).toList();
  }

  static String _normaliseDateQuery(String value) {
    final match = RegExp(r'^(\d{1,2})[\/\-](\d{1,2})(?:[\/\-](\d{2,4}))?$')
        .firstMatch(value.trim());
    if (match == null) return '';
    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    var yearText = match.group(3);
    if (day == null || month == null || day < 1 || month < 1 || month > 12) {
      return '';
    }
    if (yearText == null) {
      return '-${month.toString().padLeft(2, '0')}-'
          '${day.toString().padLeft(2, '0')}';
    }
    if (yearText.length == 2) yearText = '20$yearText';
    final year = int.tryParse(yearText);
    if (year == null) return '';
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  /// Check if a receipt likely already exists.
  /// Exact invoice+supplier+date matches are global; supplier/date/gross fallback is project-scoped.
  /// Used to warn about likely duplicates at save time.
  /// Returns the matching existing receipt(s), or empty list if none.
  /// Optionally exclude a specific id (used when editing — exclude self).
  static Future<List<Receipt>> findPossibleDuplicates({
    int? projectId,
    String? invoiceNumber,
    required String supplier,
    required DateTime date,
    required double gross,
    int? excludeId,
  }) async {
    final db = await _open();
    final args = <dynamic>[];
    final duplicateParts = <String>[];
    final normalizedInvoice = normaliseInvoiceNumber(invoiceNumber);
    if (normalizedInvoice.isNotEmpty) {
      final invoiceSql = _normalisedInvoiceSql('invoice_number');
      final supplierSql = _normalisedSupplierSql('supplier');
      duplicateParts.add(
        "($invoiceSql = ? "
        "AND $supplierSql = ? "
        "AND date = ?)",
      );
      args.addAll([
        normalizedInvoice,
        normaliseSupplier(supplier),
        Receipt.formatDate(date),
      ]);
    }

    final supplierSql = _normalisedSupplierSql('supplier');
    var fallback = '($supplierSql = ? AND date = ? AND ABS(gross - ?) < 0.005';
    final fallbackArgs = <dynamic>[
      normaliseSupplier(supplier),
      Receipt.formatDate(date),
      gross,
    ];
    if (projectId != null) {
      fallback += ' AND project_id = ?';
      fallbackArgs.add(projectId);
    }
    fallback += ')';
    duplicateParts.add(fallback);
    args.addAll(fallbackArgs);

    var where = '(${duplicateParts.join(' OR ')})';
    if (excludeId != null) {
      where += ' AND id != ?';
      args.add(excludeId);
    }
    final rows = await db.query(
      _table,
      where: where,
      whereArgs: args,
      orderBy: 'id ASC',
    );
    return rows.map((r) => Receipt.fromMap(r)).toList();
  }

  static String _normalisedInvoiceSql(String expr) {
    return "UPPER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(COALESCE($expr, '')), ' ', ''), '-', ''), '/', ''), '_', ''), '.', ''))";
  }

  static String _normalisedSupplierSql(String expr) {
    return "LOWER(REPLACE(TRIM(COALESCE($expr, '')), ' ', ''))";
  }

  static Future<Receipt?> findByInvoiceNumber({
    required String invoiceNumber,
    int? projectId,
    int? excludeId,
  }) async {
    final normalizedInvoice = normaliseInvoiceNumber(invoiceNumber);
    if (normalizedInvoice.isEmpty) return null;
    final db = await _open();
    final invoiceSql = _normalisedInvoiceSql('invoice_number');
    final whereParts = <String>["$invoiceSql = ?"];
    final args = <dynamic>[normalizedInvoice];
    if (projectId != null) {
      whereParts.add('project_id = ?');
      args.add(projectId);
    }
    if (excludeId != null) {
      whereParts.add('id != ?');
      args.add(excludeId);
    }
    final rows = await db.query(
      _table,
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Receipt.fromMap(rows.first);
  }

  static Future<Receipt?> findByInvoiceSignature({
    required String invoiceNumber,
    required String supplier,
    required DateTime date,
    int? excludeId,
  }) async {
    final normalizedInvoice = normaliseInvoiceNumber(invoiceNumber);
    if (normalizedInvoice.isEmpty) return null;
    final db = await _open();
    final invoiceSql = _normalisedInvoiceSql('invoice_number');
    final supplierSql = _normalisedSupplierSql('supplier');
    final whereParts = <String>[
      "$invoiceSql = ?",
      "$supplierSql = ?",
      "date = ?",
    ];
    final args = <dynamic>[
      normalizedInvoice,
      normaliseSupplier(supplier),
      Receipt.formatDate(date),
    ];
    if (excludeId != null) {
      whereParts.add('id != ?');
      args.add(excludeId);
    }
    final rows = await db.query(
      _table,
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Receipt.fromMap(rows.first);
  }

  /// Get receipts within a SCAN DATE range (uses created_at, not invoice date).
  static Future<List<Receipt>> getByScanDateRange(
    DateTime from,
    DateTime to, {
    int? projectId,
  }) async {
    final db = await _open();
    // created_at is ISO timestamp; we need to compare just the date portion.
    // SQLite has substr() which works fine for ISO dates.
    final fromStr = Receipt.formatDate(from);
    final toStr = Receipt.formatDate(to);
    final args = <dynamic>[fromStr, toStr];
    var where =
        'substr(created_at, 1, 10) >= ? AND substr(created_at, 1, 10) <= ?';
    if (projectId != null) {
      where += ' AND project_id = ?';
      args.add(projectId);
    }
    final rows = await db.query(
      _table,
      where: where,
      whereArgs: args,
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map((r) => Receipt.fromMap(r)).toList();
  }

  static Future<List<Receipt>> getByDateRange(
    DateTime from,
    DateTime to, {
    int? projectId,
  }) async {
    final db = await _open();
    final args = <dynamic>[Receipt.formatDate(from), Receipt.formatDate(to)];
    var where = 'date >= ? AND date <= ?';
    if (projectId != null) {
      where += ' AND project_id = ?';
      args.add(projectId);
    }
    final rows = await db.query(
      _table,
      where: where,
      whereArgs: args,
      orderBy: 'date DESC, id DESC',
    );
    return rows.map((r) => Receipt.fromMap(r)).toList();
  }

  static Future<Receipt?> getById(int id) async {
    final db = await _open();
    final rows = await db.query(_table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Receipt.fromMap(rows.first);
  }

  static Future<int> count({int? projectId}) async {
    final db = await _open();
    final result = projectId == null
        ? await db.rawQuery('SELECT COUNT(*) as c FROM $_table')
        : await db.rawQuery(
            'SELECT COUNT(*) as c FROM $_table WHERE project_id = ?',
            [projectId],
          );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
