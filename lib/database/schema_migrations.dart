part of '../database_service.dart';

Future<void> _dbCreateProjectsTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseService._projectsTable} (
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

Future<void> _dbCreateDuplicateIntegrityTriggers(DatabaseExecutor db) async {
  final existingInvoiceSql =
      DatabaseService._normalizedInvoiceSql('r.invoice_number');
  final newInvoiceSql =
      DatabaseService._normalizedInvoiceSql('NEW.invoice_number');
  final existingSupplierSql =
      DatabaseService._normalizedSupplierSql('r.supplier');
  final newSupplierSql = DatabaseService._normalizedSupplierSql('NEW.supplier');

  await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_receipts_no_dup_invoice_signature_insert
      BEFORE INSERT ON ${DatabaseService._table}
      WHEN TRIM(COALESCE(NEW.invoice_number, '')) <> ''
      BEGIN
        SELECT RAISE(ABORT, 'DUPLICATE_INVOICE_SIGNATURE')
        WHERE EXISTS (
          SELECT 1
          FROM ${DatabaseService._table} r
          WHERE $existingInvoiceSql = $newInvoiceSql
            AND $existingSupplierSql = $newSupplierSql
            AND r.date = NEW.date
            AND ABS(r.gross - NEW.gross) < 0.005
        );
      END;
    ''');

  await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_receipts_no_dup_invoice_signature_update
      BEFORE UPDATE ON ${DatabaseService._table}
      WHEN TRIM(COALESCE(NEW.invoice_number, '')) <> ''
      BEGIN
        SELECT RAISE(ABORT, 'DUPLICATE_INVOICE_SIGNATURE')
        WHERE EXISTS (
          SELECT 1
          FROM ${DatabaseService._table} r
          WHERE r.id != NEW.id
            AND $existingInvoiceSql = $newInvoiceSql
            AND $existingSupplierSql = $newSupplierSql
            AND r.date = NEW.date
            AND ABS(r.gross - NEW.gross) < 0.005
        );
      END;
    ''');

  await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_receipts_no_dup_supplier_date_gross_insert
      BEFORE INSERT ON ${DatabaseService._table}
      BEGIN
        SELECT RAISE(ABORT, 'DUPLICATE_SUPPLIER_DATE_GROSS')
        WHERE EXISTS (
          SELECT 1
          FROM ${DatabaseService._table} r
          WHERE $existingSupplierSql = $newSupplierSql
            AND r.date = NEW.date
            AND ABS(r.gross - NEW.gross) < 0.005
        );
      END;
    ''');

  await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_receipts_no_dup_supplier_date_gross_update
      BEFORE UPDATE ON ${DatabaseService._table}
      BEGIN
        SELECT RAISE(ABORT, 'DUPLICATE_SUPPLIER_DATE_GROSS')
        WHERE EXISTS (
          SELECT 1
          FROM ${DatabaseService._table} r
          WHERE r.id != NEW.id
            AND $existingSupplierSql = $newSupplierSql
            AND r.date = NEW.date
            AND ABS(r.gross - NEW.gross) < 0.005
        );
      END;
    ''');
}

Future<void> _dbRefreshDuplicateIntegrityTriggers(DatabaseExecutor db) async {
  await db.execute(
    'DROP TRIGGER IF EXISTS trg_receipts_no_dup_invoice_signature_insert',
  );
  await db.execute(
    'DROP TRIGGER IF EXISTS trg_receipts_no_dup_invoice_signature_update',
  );
  await db.execute(
    'DROP TRIGGER IF EXISTS trg_receipts_no_dup_supplier_date_gross_insert',
  );
  await db.execute(
    'DROP TRIGGER IF EXISTS trg_receipts_no_dup_supplier_date_gross_update',
  );
  await _dbCreateDuplicateIntegrityTriggers(db);
}

Future<void> _dbCreateCombinedReportView(DatabaseExecutor db) async {
  await db
      .execute('DROP VIEW IF EXISTS ${DatabaseService._combinedReportView}');
  await db.execute('''
      CREATE VIEW IF NOT EXISTS ${DatabaseService._combinedReportView} AS
      SELECT
        r.id AS receipt_id,
        r.project_id AS project_id,
        p.name AS project_name,
        r.category AS category,
        r.gross AS gross,
        r.date AS invoice_date,
        substr(r.created_at, 1, 10) AS scan_date
      FROM ${DatabaseService._table} r
      LEFT JOIN ${DatabaseService._projectsTable} p ON p.id = r.project_id
      WHERE r.project_id IS NOT NULL
    ''');
}

Future<void> _dbCreateCategoriesTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseService._categoriesTable} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
}

Future<void> _dbCreateCompanyProfileTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseService._companyTable} (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        client_name TEXT NOT NULL,
        company_code TEXT NOT NULL DEFAULT '',
        business_nature TEXT NOT NULL,
        business_description TEXT NOT NULL,
        financial_year_start_month INTEGER NOT NULL DEFAULT 4,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
}

Future<void> _dbSeedDefaultCategories(DatabaseExecutor db) async {
  final now = DateTime.now().toIso8601String();
  for (final name in DatabaseService.defaultCategories) {
    await db.insert(
      DatabaseService._categoriesTable,
      {
        'name': name,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}

Future<void> _dbMigrateToBusinessExpenseCategories(DatabaseExecutor db) async {
  final now = DateTime.now().toIso8601String();
  const legacyToNew = <String, String>{
    'Material': 'Purchases',
    'Subcontractor': 'Subcontractor',
    'Utility Bills': 'Utility',
    'Travel': 'Travelling',
    'Insurance': 'Fees',
    'Other': 'Sundries',
  };

  for (final entry in legacyToNew.entries) {
    await db.rawUpdate(
      '''
        UPDATE ${DatabaseService._table}
        SET category = ?, updated_at = ?
        WHERE LOWER(TRIM(category)) = LOWER(?)
        ''',
      [entry.value, now, entry.key],
    );
  }

  const businessV9Categories = <String>[
    'Purchases',
    'Subcontractor',
    'Commissions',
    'Advertisement',
    'Salary',
    'Rent',
    'Rates',
    'Utility',
    'Travelling',
    'Subsistence',
    'Telephone',
    'Computer',
    'Fees',
    'Repair',
    'Sundries',
  ];

  for (final category in businessV9Categories) {
    await db.rawUpdate(
      '''
        UPDATE ${DatabaseService._table}
        SET category = ?, updated_at = ?
        WHERE LOWER(TRIM(category)) = LOWER(?)
        ''',
      [category, now, category],
    );
  }

  final normalizedDefaults =
      businessV9Categories.map((c) => c.toLowerCase()).toList();
  final placeholders = List.filled(normalizedDefaults.length, '?').join(',');
  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE TRIM(COALESCE(category, '')) = ''
         OR LOWER(TRIM(category)) NOT IN ($placeholders)
      ''',
    ['Sundries', now, ...normalizedDefaults],
  );

  await db.delete(DatabaseService._categoriesTable);
  final seedNow = DateTime.now().toIso8601String();
  for (final name in businessV9Categories) {
    await db.insert(
      DatabaseService._categoriesTable,
      {
        'name': name,
        'created_at': seedNow,
        'updated_at': seedNow,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}

Future<void> _dbMigrateToCondensedMainCategories(DatabaseExecutor db) async {
  final now = DateTime.now().toIso8601String();
  const oldToMain = <String, String>{
    'Purchases': 'Purchases',
    'Subcontractor': 'Staff & Contractors',
    'Commissions': 'Professional Fees',
    'Advertisement': 'Marketing',
    'Salary': 'Staff & Contractors',
    'Rent': 'Rent & Rates',
    'Rates': 'Rent & Rates',
    'Utility': 'Utilities',
    'Premises & Utilities': 'Rent & Rates',
    'Travelling': 'Travel',
    'Subsistence': 'Travel',
    'Telephone': 'Office Admin',
    'Computer': 'Office Admin',
    'Fees': 'Professional Fees',
    'Repair': 'Repair & Maintenance',
    'Sundries': 'Sundries',
    'Insurance': 'Insurance',
    'Charity': 'Donations & Charity',
    'Charity Donation': 'Donations & Charity',
    'Donations & Charity': 'Donations & Charity',
  };

  for (final entry in oldToMain.entries) {
    await db.rawUpdate(
      '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE LOWER(TRIM(category)) = LOWER(?)
      ''',
      [entry.value, now, entry.key],
    );
  }

  final normalizedDefaults =
      DatabaseService.defaultCategories.map((c) => c.toLowerCase()).toList();
  final placeholders = List.filled(normalizedDefaults.length, '?').join(',');
  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE TRIM(COALESCE(category, '')) = ''
         OR LOWER(TRIM(category)) NOT IN ($placeholders)
      ''',
    ['Sundries', now, ...normalizedDefaults],
  );

  await db.delete(DatabaseService._categoriesTable);
  await _dbSeedDefaultCategories(db);
}

Future<void> _dbMigratePremisesUtilitiesSplit(DatabaseExecutor db) async {
  final now = DateTime.now().toIso8601String();
  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE LOWER(TRIM(category)) = LOWER(?)
      ''',
    ['Rent & Rates', now, 'Premises & Utilities'],
  );
  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE LOWER(TRIM(category)) = LOWER(?)
      ''',
    ['Utilities', now, 'Utility'],
  );
  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE LOWER(TRIM(category)) = LOWER(?)
      ''',
    ['Rent & Rates', now, 'Rent'],
  );
  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE LOWER(TRIM(category)) = LOWER(?)
      ''',
    ['Rent & Rates', now, 'Rates'],
  );

  await db.delete(
    DatabaseService._categoriesTable,
    where: 'LOWER(TRIM(name)) = LOWER(?)',
    whereArgs: ['Premises & Utilities'],
  );
  await _dbSeedDefaultCategories(db);
}

Future<void> _dbMigrateToPnlCategoriesV15(DatabaseExecutor db) async {
  await db.delete(DatabaseService._categoriesTable);
  await _dbSeedDefaultCategories(db);
}

Future<void> _dbRenameDefaultProjectToOperation(DatabaseExecutor db) async {
  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._projectsTable}
      SET name = ?, updated_at = ?
      WHERE LOWER(TRIM(name)) = LOWER(?)
      ''',
    ['General Operation', DateTime.now().toIso8601String(), 'General'],
  );
}

Future<int> _dbInsertDefaultProject(Database db) async {
  final existing = await db.query(
    DatabaseService._projectsTable,
    where: 'LOWER(TRIM(name)) = LOWER(?) OR LOWER(TRIM(name)) = LOWER(?)',
    whereArgs: ['General Operation', 'General'],
    limit: 1,
  );
  if (existing.isNotEmpty) return existing.first['id'] as int;
  final now = DateTime.now().toIso8601String();
  return db.insert(DatabaseService._projectsTable, {
    'name': 'General Operation',
    'address': null,
    'start_date': null,
    'budget': null,
    'notes': 'Default operation for existing receipts',
    'created_at': now,
    'updated_at': now,
  });
}

Future<int> _dbDefaultProjectId(Database db) async {
  return _dbInsertDefaultProject(db);
}
