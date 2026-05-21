part of '../../main.dart';

extension _ReceiptEntryScanController on _ReceiptEntryPageState {
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

    var mergeOnly = false;
    if (hasManualData) {
      final choice = await _askOverwriteChoice();
      if (choice == null) return;
      if (choice == 'merge') mergeOnly = true;
    }

    _setScanningState(true);
    final result = await GeminiService.scanReceipt(
      _imageBytes!,
      allowedCategories: _categories,
      imagePath: _imageFilePath,
      businessNature: businessNature,
      businessDescription: businessDescription,
    );
    if (!mounted) return;
    _setScanningState(false);

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
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'merge'),
            child: const Text('Fill empty fields only'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'replace'),
            child: const Text('Replace all'),
          ),
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
    var categoryApplied = false;
    var categoryKept = false;
    String? appliedCategory;
    double? appliedConfidence;
    _applyScanStateMutations(
      data: data,
      mergeOnly: mergeOnly,
      suggestion: suggestion,
      onCategoryApplied: (category, confidence) {
        appliedCategory = category;
        appliedConfidence = confidence;
        categoryApplied = true;
      },
      onCategoryKept: () {
        categoryKept = true;
      },
    );

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

  void _applyScanStateMutations({
    required ReceiptData data,
    required bool mergeOnly,
    required ({String category, double confidence})? suggestion,
    required void Function(String category, double confidence)
        onCategoryApplied,
    required VoidCallback onCategoryKept,
  }) {
    _mutateEntryState(() {
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
          onCategoryApplied(suggestion.category, suggestion.confidence);
        } else {
          onCategoryKept();
        }
      }

      if (suggestion != null && (!mergeOnly || _selectedCategory != null)) {
        _lastCategoryConfidence = suggestion.confidence;
        _categoryNeedsReview = suggestion.confidence < 85;
        _categoryReviewConfirmed = !_categoryNeedsReview;
      } else {
        _lastCategoryConfidence = null;
        _categoryNeedsReview = false;
        _categoryReviewConfirmed = true;
      }
    });
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
      final candidate = category.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
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
    var bestConfidence = 0.0;

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

  bool _isDateUntouched() {
    return _selectedDate == null;
  }
}
