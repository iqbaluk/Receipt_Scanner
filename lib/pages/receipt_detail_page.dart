part of '../main.dart';

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
          '${_current.supplier} ·${_current.gross.toStringAsFixed(2)}\\n\\nThis cannot be undone.',
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
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            _editing ? 132 : 16,
          ),
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
            ],
          ),
        ),
        bottomNavigationBar: !_editing
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 52,
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
              ),
      ),
    );
  }
}

