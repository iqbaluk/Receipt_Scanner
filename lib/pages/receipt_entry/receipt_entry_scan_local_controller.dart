part of '../../main.dart';

extension _ReceiptEntryLocalScanController on _ReceiptEntryPageState {
  Future<void> _scanWithLocalOnly() async {
    debugPrint('SCAN_BUTTON mode=local');
    if (_imageBytes == null) {
      _showStatus(
        'Please add a photo first using Take Photo or Gallery.',
        isError: true,
      );
      return;
    }
    if (_imageFilePath == null || _imageFilePath!.trim().isEmpty) {
      _showStatus(
        'Local scan needs a valid image path. Please retake or reselect image.',
        isError: true,
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

    _setActiveScanMode('local');
    _setScanningState(true);

    ReceiptData? localData;
    try {
      localData = await FastReceiptPipeline.tryExtract(
        imagePath: _imageFilePath!.trim(),
        categories: _categories,
      );
    } finally {
      if (mounted) {
        _setScanningState(false);
        _setActiveScanMode(null);
      }
    }

    if (!mounted) return;

    if (localData == null) {
      _showStatus(
        'Local scan could not extract enough fields. Use Fast or Quality scan.',
        isError: true,
        duration: const Duration(seconds: 6),
      );
      return;
    }

    final categoryMessage = _applyScanData(
      localData,
      mergeOnly: mergeOnly,
      businessNature: businessNature,
      businessDescription: businessDescription,
    );

    final missing = _missingFieldsAfterScan();
    final baseMessage =
        categoryMessage ?? 'Local scan complete. Review fields.';

    if (missing.isNotEmpty) {
      _showStatus(
        '$baseMessage Please enter manually: ${missing.join(', ')}.',
        isError: true,
        duration: const Duration(seconds: 8),
      );
      return;
    }

    _showStatus(
      baseMessage,
      duration: const Duration(seconds: 6),
    );
  }
}
