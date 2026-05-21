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
  final _paidController = TextEditingController();
  final _netController = TextEditingController();
  final _notesController = TextEditingController();

  Uint8List? _imageBytes;
  String? _imageFileName;
  String? _imageFilePath;

  bool _isScanning = false;
  bool _isSaving = false;
  bool _isAutoAmountUpdate = false;
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
    _grossController.addListener(_syncAmountFields);
    _vatController.addListener(_syncAmountFields);
    _paidController.addListener(_syncAmountFields);
    _loadCategories();
    _loadRecent();
  }

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _supplierController.dispose();
    _vatController.dispose();
    _grossController.dispose();
    _paidController.dispose();
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

  void _syncAmountFields() {
    if (_isAutoAmountUpdate) return;
    final gross = double.tryParse(_grossController.text) ?? 0;
    final vat = double.tryParse(_vatController.text) ?? 0;
    var paid = double.tryParse(_paidController.text);

    _isAutoAmountUpdate = true;
    try {
      if (paid == null && gross > 0) {
        paid = gross;
        _paidController.text = gross.toStringAsFixed(2);
      }
      if (gross > 0) {
        _netController.text = (gross - vat).toStringAsFixed(2);
      } else if (_netController.text.trim().isEmpty) {
        _netController.clear();
      }
    } finally {
      _isAutoAmountUpdate = false;
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
        imageQuality: 100,
        maxWidth: 3200,
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
        imageQuality: 100,
        maxWidth: 3200,
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
      _imageFilePath = file.path;
    });
    _showStatus(
      'Image loaded. You can scan with Gemini.',
    );
  }

  void _removeImage() {
    setState(() {
      _imageBytes = null;
      _imageFileName = null;
      _imageFilePath = null;
    });
  }

  Future<void> _openScanImageViewer() async {
    if (_imageBytes == null) return;
    final action = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (value) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Scan image quality check'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: () => Navigator.of(value).pop(),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 6.0,
              child: Image.memory(
                _imageBytes!,
                fit: BoxFit.contain,
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(value).pop('camera'),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Retake'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(value).pop('gallery'),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(value).pop('use'),
                      icon: const Icon(Icons.check),
                      label: const Text('Use this'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || action == null || action == 'use') return;
    if (_isScanning) return;
    if (action == 'camera') {
      await _takePhoto();
    } else if (action == 'gallery') {
      await _pickFromGallery();
    }
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
        'Gemini API key not set. Open Operation actions > Gemini settings. Manual entry still works.',
        isError: true,
        duration: const Duration(seconds: 6),
      );
      return;
    }

    final profile = await DatabaseService.getCompanyProfile();
    final missingCompanyInfo = profile == null ||
        profile.clientName.trim().isEmpty ||
        profile.companyCode.trim().isEmpty ||
        profile.businessNature.trim().isEmpty ||
        profile.businessDescription.trim().isEmpty;
    if (missingCompanyInfo) {
      _showStatus(
        'Company info is required before scan. Open Management > Company info and complete all fields.',
        isError: true,
        duration: const Duration(seconds: 7),
      );
      return;
    }
    final businessNature = profile.businessNature.trim();
    final businessDescription = profile.businessDescription.trim();

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
      imagePath: _imageFilePath,
      businessNature: businessNature,
      businessDescription: businessDescription,
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

    final categoryMessage = _applyScanData(
      result.data!,
      mergeOnly: mergeOnly,
      businessNature: businessNature,
      businessDescription: businessDescription,
    );
    final missing = _missingFieldsAfterScan();
    final warnings = result.data!.extractionWarnings
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList();
    final handwritingWarnings =
        warnings.where((w) => w.toLowerCase().contains('handwritten')).toList();
    final baseMessage =
        categoryMessage ?? 'Scan complete. Review fields and category.';
    final warningSuffix =
        warnings.isEmpty ? '' : ' Check: ${warnings.join(' | ')}.';
    if (missing.isNotEmpty) {
      _showStatus(
        '$baseMessage Please enter manually: ${missing.join(', ')}.$warningSuffix',
        isError: true,
        duration: const Duration(seconds: 8),
      );
      return;
    }
    _showStatus(
      '$baseMessage$warningSuffix',
      isError: handwritingWarnings.isNotEmpty,
      duration: const Duration(seconds: 8),
    );
  }

  List<String> _missingFieldsAfterScan() {
    final missing = <String>[];
    if (_selectedDate == null) missing.add('Invoice date');
    if (_invoiceNumberController.text.trim().isEmpty) {
      missing.add('Invoice number');
    }
    if (_supplierController.text.trim().isEmpty) missing.add('Supplier');
    final gross = double.tryParse(_grossController.text.trim()) ?? 0;
    if (gross <= 0) missing.add('Gross amount');
    if (_selectedCategory == null) missing.add('Expense category');
    return missing;
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

  String? _applyScanData(
    ReceiptData data, {
    required bool mergeOnly,
    String? businessNature,
    String? businessDescription,
  }) {
    final suggestion = _categorySuggestionFromScan(
      data,
      businessNature: businessNature,
      businessDescription: businessDescription,
    );
    bool categoryApplied = false;
    bool categoryKept = false;
    String? appliedCategory;
    double? appliedConfidence;
    setState(() {
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
      if (data.paidAmount != null &&
          (!mergeOnly || _paidController.text.isEmpty)) {
        _paidController.text = data.paidAmount!.toStringAsFixed(2);
      }
      if (data.net != null &&
          data.gross == null &&
          data.paidAmount == null &&
          (!mergeOnly || _netController.text.isEmpty)) {
        _netController.text = data.net!.toStringAsFixed(2);
      }
      if (data.rawNotes != null &&
          (!mergeOnly || _notesController.text.isEmpty)) {
        _notesController.text = data.rawNotes!;
      }

      if (suggestion != null) {
        if (!mergeOnly || _selectedCategory == null) {
          _selectedCategory = suggestion.category;
          appliedCategory = suggestion.category;
          appliedConfidence = suggestion.confidence;
          categoryApplied = true;
        } else {
          categoryKept = true;
        }
      }

      if (categoryApplied) {
        _lastCategoryConfidence = appliedConfidence;
        _categoryNeedsReview =
            appliedConfidence != null && appliedConfidence! < 85;
        _categoryReviewConfirmed = !_categoryNeedsReview;
      } else {
        _lastCategoryConfidence = null;
        _categoryNeedsReview = false;
        _categoryReviewConfirmed = true;
      }
    });

    if (categoryApplied && appliedCategory != null) {
      final confidenceText = appliedConfidence == null
          ? ''
          : ' (${appliedConfidence!.toStringAsFixed(0)}% match)';
      return 'Scan complete. Category suggested: $appliedCategory$confidenceText. You can change it before saving.';
    }
    if (categoryKept && suggestion != null) {
      return 'Scan complete. Suggested category: ${suggestion.category}. Your current selected category was kept.';
    }
    return null;
  }

  String? _matchConfiguredCategory(String? rawCategory) {
    if (rawCategory == null) return null;
    final cleaned = rawCategory.trim();
    if (cleaned.isEmpty) return null;

    for (final category in _categories) {
      if (category.toLowerCase() == cleaned.toLowerCase()) {
        return category;
      }
    }

    final loose = cleaned.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    for (final category in _categories) {
      final candidate =
          category.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      if (candidate == loose) return category;
    }
    return null;
  }

  ({String category, double confidence})? _categorySuggestionFromScan(
    ReceiptData data, {
    String? businessNature,
    String? businessDescription,
  }) {
    final aiCategory = _matchConfiguredCategory(data.category);
    if (aiCategory != null) {
      final confidence =
          (data.categoryConfidence ?? 90).clamp(0, 100).toDouble();
      return (category: aiCategory, confidence: confidence);
    }

    final hintText = [
      data.rawNotes ?? '',
      data.supplier ?? '',
      data.invoiceNumber ?? '',
    ].join(' ').toLowerCase();
    if (hintText.trim().isEmpty) return null;
    final contextText = [
      businessNature ?? '',
      businessDescription ?? '',
    ].join(' ').toLowerCase();

    bool contextHas(List<String> words) =>
        words.any((word) => contextText.contains(word));
    bool invoiceHas(List<String> words) =>
        words.any((word) => hintText.contains(word));

    final purchasesCategory = findCategoryByKeywords(
      _categories,
      const ['purchase', 'stock', 'material'],
    );
    final motorCategory = findCategoryByKeywords(
      _categories,
      const ['motor', 'vehicle'],
    );
    final travelCategory = findCategoryByKeywords(
      _categories,
      const ['travel', 'transport', 'fuel', 'subsistence', 'tfl'],
    );
    final officeCategory = findCategoryByKeywords(
      _categories,
      const ['office', 'admin', 'stationery', 'printing'],
    );
    final generalCategory = findCategoryByKeywords(
      _categories,
      const ['general', 'sundries', 'misc', 'other'],
    );

    // Context-aware overrides for ambiguous transactions.
    final restaurantLike =
        contextHas(const ['restaurant', 'cafe', 'food', 'hospitality']);
    final transportLike = contextHas(
      const ['transport', 'logistics', 'courier', 'haulage', 'taxi', 'fleet'],
    );
    final garageLike = contextHas(
      const ['garage', 'automotive', 'vehicle repair', 'mechanic', 'car parts'],
    );
    final publisherLike = contextHas(
      const ['publisher', 'publishing', 'print house', 'newspaper', 'magazine'],
    );

    if (invoiceHas(const ['grocery', 'groceries', 'supermarket'])) {
      if (restaurantLike && purchasesCategory != null) {
        return (category: purchasesCategory, confidence: 88);
      }
      if (generalCategory != null) {
        return (category: generalCategory, confidence: 82);
      }
    }

    if (invoiceHas(const ['fuel', 'petrol', 'diesel'])) {
      if (transportLike && purchasesCategory != null) {
        return (category: purchasesCategory, confidence: 87);
      }
      if (travelCategory != null) {
        return (category: travelCategory, confidence: 84);
      }
      if (motorCategory != null) {
        return (category: motorCategory, confidence: 83);
      }
    }

    if (invoiceHas(const [
      'car part',
      'car parts',
      'auto part',
      'autoparts',
      'vehicle part',
      'spares',
    ])) {
      if (garageLike && purchasesCategory != null) {
        return (category: purchasesCategory, confidence: 89);
      }
      if (motorCategory != null) {
        return (category: motorCategory, confidence: 86);
      }
    }

    if (invoiceHas(const ['paper', 'printing stock', 'print stock'])) {
      if (publisherLike && purchasesCategory != null) {
        return (category: purchasesCategory, confidence: 87);
      }
      if (officeCategory != null) {
        return (category: officeCategory, confidence: 84);
      }
    }

    final sundriesCategory = findCategoryByKeywords(
      _categories,
      const ['sundries', 'misc', 'other'],
    );
    if (sundriesCategory != null) {
      final groceryKeywords = <String>[
        'grocery',
        'groceries',
        'supermarket',
        'tesco',
        'asda',
        'sainsbury',
        'aldi',
        'lidl',
        'waitrose',
        'morrisons',
        'coop',
        'co-op',
        'refreshment',
        'tea',
        'coffee',
        'milk',
        'snack',
      ];
      final stockKeywords = <String>[
        'wholesale',
        'resale',
        'inventory',
        'trade supply',
        'bulk stock',
      ];
      final hasGrocerySignal =
          groceryKeywords.any((keyword) => hintText.contains(keyword));
      final hasStockSignal =
          stockKeywords.any((keyword) => hintText.contains(keyword));
      if (hasGrocerySignal && !hasStockSignal) {
        return (category: sundriesCategory, confidence: 78);
      }
    }

    final rules = <({
      List<String> categoryKeys,
      List<String> invoiceKeywords,
      double baseConfidence
    })>[
      (
        categoryKeys: const ['purchases', 'purchase', 'stock', 'material'],
        invoiceKeywords: const [
          'purchase',
          'stock',
          'material',
          'parts',
          'wholesale',
          'resale',
          'trade supply',
          'inventory'
        ],
        baseConfidence: 62
      ),
      (
        categoryKeys: const ['staff', 'contractor', 'labour', 'payroll'],
        invoiceKeywords: const [
          'subcontract',
          'sub-contractor',
          'labour',
          'cis',
          'site',
          'day rate',
          'salary',
          'wage',
          'payroll',
          'agency staff',
          'consultant',
          'bricklay',
          'plaster',
          'electrical labour',
          'plumbing labour'
        ],
        baseConfidence: 67
      ),
      (
        categoryKeys: const ['marketing', 'advert', 'promotion'],
        invoiceKeywords: const [
          'advert',
          'ad ',
          'ads',
          'marketing',
          'promo',
          'campaign',
          'seo',
          'ppc',
          'facebook ads',
          'google ads'
        ],
        baseConfidence: 64
      ),
      (
        categoryKeys: const ['premises', 'utilit', 'rent', 'rates'],
        invoiceKeywords: const ['rent', 'lease'],
        baseConfidence: 65
      ),
      (
        categoryKeys: const ['premises', 'utilit', 'electric', 'water', 'gas'],
        invoiceKeywords: const [
          'business rates',
          'council rates',
          'rates',
          'electric',
          'electricity',
          'gas',
          'water',
          'energy',
          'utility',
          'waste'
        ],
        baseConfidence: 66
      ),
      (
        categoryKeys: const [
          'professional',
          'fees',
          'legal',
          'account',
          'bank'
        ],
        invoiceKeywords: const [
          'fee',
          'fees',
          'charge',
          'accountant',
          'accounting',
          'legal',
          'bank charge',
          'service fee',
          'subscription',
          'membership',
          'license'
        ],
        baseConfidence: 64
      ),
      (
        categoryKeys: const ['insurance'],
        invoiceKeywords: const [
          'insurance',
          'premium',
          'policy',
          'liability cover',
          'public liability'
        ],
        baseConfidence: 67
      ),
      (
        categoryKeys: const [
          'travel',
          'transport',
          'fuel',
          'subsistence',
          'tfl'
        ],
        invoiceKeywords: const [
          'fuel',
          'petrol',
          'diesel',
          'taxi',
          'uber',
          'train',
          'parking',
          'tfl',
          'transport for london',
          'bus',
          'travel',
          'mileage',
          'meal',
          'accommodation',
          'hotel'
        ],
        baseConfidence: 66
      ),
      (
        categoryKeys: const ['office', 'admin', 'software', 'stationery'],
        invoiceKeywords: const [
          'software',
          'saas',
          'subscription',
          'stationery',
          'printing',
          'postage',
          'paper',
          'telephone',
          'phone',
          'mobile',
          'sim',
          'telecom',
          'internet',
          'broadband'
        ],
        baseConfidence: 65
      ),
      (
        categoryKeys: const ['repair', 'maintenance', 'cleaning'],
        invoiceKeywords: const [
          'repair',
          'maintenance',
          'service',
          'fix',
          'cleaning',
          'upkeep'
        ],
        baseConfidence: 65
      ),
      (
        categoryKeys: const ['donation', 'charity'],
        invoiceKeywords: const [
          'charity',
          'donation',
          'contribution',
          'fundraiser',
          'sponsorship'
        ],
        baseConfidence: 68
      ),
      (
        categoryKeys: const ['sundries', 'misc', 'general'],
        invoiceKeywords: const [
          'misc',
          'sundry',
          'general expense',
          'grocery',
          'groceries',
          'supermarket',
          'tesco',
          'asda',
          'sainsbury',
          'aldi',
          'lidl',
          'waitrose',
          'morrisons',
          'coop',
          'co-op',
          'refreshment',
          'tea',
          'coffee',
          'milk',
          'snack',
          'cleaning supply'
        ],
        baseConfidence: 64
      ),
    ];

    String? bestCategory;
    double bestConfidence = 0;

    for (final rule in rules) {
      final category = findCategoryByKeywords(_categories, rule.categoryKeys);
      if (category == null) continue;

      var hits = 0;
      for (final keyword in rule.invoiceKeywords) {
        if (hintText.contains(keyword)) hits++;
      }
      if (hits == 0) continue;

      final confidence = (rule.baseConfidence + (hits * 6)).clamp(55, 83);
      if (confidence > bestConfidence) {
        bestConfidence = confidence.toDouble();
        bestCategory = category;
      }
    }

    if (bestCategory == null) return null;
    return (category: bestCategory, confidence: bestConfidence);
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
          'Please verify the expense category before saving.',
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

  void _setSavingState(bool value) {
    if (!mounted) return;
    setState(() => _isSaving = value);
  }

  // Save flow and duplicate dialogs were extracted into
  // receipt_entry/receipt_entry_save_controller.dart and
  // receipt_entry/receipt_entry_duplicate_dialogs.dart.

  void _clearForm({bool silent = false, bool keepCategory = false}) {
    final retainedCategory = keepCategory ? _selectedCategory : null;
    setState(() {
      _selectedDate = null;
      _invoiceNumberController.clear();
      _supplierController.clear();
      _selectedCategory = retainedCategory;
      _vatController.clear();
      _grossController.clear();
      _paidController.clear();
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
        builder: (value) => ReceiptDetailPage(receipt: receipt),
      ),
    );
    if (changed == true) {
      await _loadRecent();
    }
  }

  Future<void> _openReports() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (value) => ReportsHubPage(initialProject: widget.project),
      ),
    );
  }

  Future<void> _openInvoiceList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (value) => const ReceiptHistoryPage(),
      ),
    );
  }

  Future<void> _openCategoryManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CategoryManagerPage(),
      ),
    );
    await _loadCategories();
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => goToHomePage(context),
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Invoice list',
            onPressed: _openInvoiceList,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Reports',
            onPressed: _openReports,
          ),
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Categories',
            onPressed: _openCategoryManager,
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
                buildPageTitleBanner(
                  context,
                  title: 'Receipt entry and scan',
                  icon: Icons.document_scanner_outlined,
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.business_center_outlined,
                        size: 18,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Operation:',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
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
                    backgroundColor: colorScheme.secondaryContainer,
                    foregroundColor: colorScheme.onSecondaryContainer,
                    disabledBackgroundColor: colorScheme.surfaceContainerHigh,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manual entry below always works, with or without scan.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
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
                    labelText: 'Expense category * (select before save)',
                    labelStyle: TextStyle(
                      color: colorScheme.secondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: TextStyle(
                    color: colorScheme.secondary,
                    fontWeight: FontWeight.w800,
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
                              color: colorScheme.secondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    _selectedCategory = v;
                    _categoryReviewConfirmed = true;
                    _categoryNeedsReview = false;
                  }),
                  validator: (v) =>
                      v == null ? 'Please select an expense category' : null,
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

                      final paidField = TextFormField(
                        controller: _paidController,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'Paid',
                          hintText: 'Defaults to Gross',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
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
                            paidField,
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
                          paidField,
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
    final colorScheme = Theme.of(context).colorScheme;
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
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
              color: colorScheme.surfaceContainerLowest,
            ),
            child: Center(
              child: Text(
                'No scans saved today yet.',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
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
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
            color: colorScheme.surfaceContainerLowest,
          ),
          child: Column(
            children: [
              for (int i = 0; i < _recentReceipts.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, color: colorScheme.outlineVariant),
                _buildReceiptRow(_recentReceipts[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptRow(Receipt r) {
    final colorScheme = Theme.of(context).colorScheme;
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
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: r.photoPath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.file(
                        File(r.photoPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (ignored, __, ___) => Icon(
                          Icons.broken_image,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.receipt_long,
                      size: 24,
                      color: colorScheme.onSurfaceVariant,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (r.scanNo != null) ...[
                        Text(
                          '#${r.scanNo!.toString().padLeft(5, '0')}',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          r.category,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        DateFormat('dd/MM/yy').format(r.date),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
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
            Icon(
              Icons.chevron_right,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _statusIsError
            ? colorScheme.errorContainer
            : colorScheme.primaryContainer,
        border: Border.all(
          color: _statusIsError
              ? colorScheme.error.withValues(alpha: 0.42)
              : colorScheme.primary.withValues(alpha: 0.34),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            _statusIsError ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: _statusIsError
                ? colorScheme.onErrorContainer
                : colorScheme.onPrimaryContainer,
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
    final colorScheme = Theme.of(context).colorScheme;
    if (_imageBytes == null) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
          color: colorScheme.surfaceContainerLowest,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image_outlined,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                'No photo selected',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            child: InkWell(
              onTap: _openScanImageViewer,
              child: Image.memory(
                _imageBytes!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.image,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_imageFileName ?? 'image'}  -  tap to zoom',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: _isScanning ? null : _takePhoto,
                  icon: const Icon(Icons.camera_alt, size: 14),
                  label: const Text('Retake', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
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
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 20,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
