part of '../main.dart';

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
    });
    _showStatus(
      'Image loaded. You can scan with Gemini.',
    );
  }

  void _removeImage() {
    setState(() {
      _imageBytes = null;
      _imageFileName = null;
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
                    'Gross: ${formatAppMoney(existing.gross)}',
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
    });
    if (!silent) _showStatus('Form cleared');
  }

  // ---- Export ----

  Future<void> _showExportMenu() async {
    // Step 1: pick range
    final range = await _pickExportRange(
      context,
      title: 'Export - pick range',
      includeTodayWeek: true,
    );
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
              formatAppMoney(r.gross),
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

