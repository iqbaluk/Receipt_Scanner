part of '../main.dart';

class CombinedReportPage extends StatefulWidget {
  final ExportRange initialRange;
  final DateBasis initialDateBasis;

  const CombinedReportPage({
    super.key,
    required this.initialRange,
    required this.initialDateBasis,
  });

  @override
  State<CombinedReportPage> createState() => _CombinedReportPageState();
}

class _CombinedReportPageState extends State<CombinedReportPage> {
  late ExportRange _range;
  late DateBasis _dateBasis;
  late Future<CombinedProjectReport> _future;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
    _dateBasis = widget.initialDateBasis;
    _reload();
  }

  void _reload() {
    _future = DatabaseService.getCombinedProjectReport(
      from: _range.from,
      to: _range.to,
      useScanDate: _dateBasis == DateBasis.scanDate,
    );
  }

  Future<void> _pickRange() async {
    final next = await _pickExportRange(context, title: 'Combined report range');
    if (next == null || !mounted) return;
    setState(() {
      _range = next;
      _reload();
    });
  }

  void _setDateBasis(DateBasis basis) {
    setState(() {
      _dateBasis = basis;
      _reload();
    });
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
        title: const Text('Combined Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Date range',
            onPressed: _pickRange,
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Share report',
            onPressed: _showCombinedExportMenu,
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
      body: FutureBuilder<CombinedProjectReport>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Report failed: ${snapshot.error}'));
          }
          final report = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_rangeLabel()} · ${_dateBasis == DateBasis.scanDate ? "Scan date" : "Invoice date"}',
                  style: TextStyle(color: colorScheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: 12),
              if (report.projects.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Grand Total',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatAppMoney(report.grandTotal, decimals: 0),
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: colorScheme.outlineVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Invoice Count',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                report.invoiceCount.toString(),
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (report.projects.isEmpty || report.categories.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No data in this range.'),
                  ),
                )
              else
                Card(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Table(
                      columnWidths: {
                        0: const FixedColumnWidth(140),
                        for (int i = 0; i < report.projects.length; i++)
                          i + 1: const FixedColumnWidth(100),
                        report.projects.length + 1: const FixedColumnWidth(100),
                      },
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      border: TableBorder(
                        horizontalInside:
                            BorderSide(color: colorScheme.outlineVariant),
                      ),
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                          ),
                          children: [
                            _ReportCell(
                              'Categories',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                            for (final p in report.projects)
                            _ReportCell(
                                p.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                                alignRight: true,
                              ),
                            _ReportCell(
                              'Total',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.red,
                              ),
                              alignRight: true,
                            ),
                          ],
                        ),
                        for (final category in report.categories)
                          TableRow(
                            children: [
                            _ReportCell(
                                category,
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 14,
                                ),
                              ),
                              for (final p in report.projects)
                            _ReportCell(
                                  _moneyOrDash(report.grossByCategoryProject[
                                          category]?[p.id] ??
                                      0),
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontSize: 14,
                                  ),
                                  alignRight: true,
                                ),
                            _ReportCell(
                                _money(
                                  report.projects.fold<double>(
                                    0,
                                    (sum, p) =>
                                        sum +
                                        (report.grossByCategoryProject[
                                                    category]?[p.id] ??
                                            0),
                                  ),
                                ),
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w700,
                                ),
                                alignRight: true,
                              ),
                            ],
                          ),
                        TableRow(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLow,
                          ),
                          children: [
                            _ReportCell(
                              'Total',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            for (final p in report.projects)
                            _ReportCell(
                                _money(report.projectTotals[p.id] ?? 0),
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w800,
                                ),
                                alignRight: true,
                              ),
                            _ReportCell(
                              _money(report.grandTotal),
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w900,
                              ),
                              alignRight: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Projects: ${report.projects.length} · Categories: ${report.categories.length} · Cells: ${report.grossByCategoryProject.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showCombinedExportMenu() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Share combined report'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'summary_pdf'),
            child: const ListTile(
              leading: Icon(Icons.description),
              title: Text('Summary PDF (Recommended)'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'summary_csv'),
            child: const ListTile(
              leading: Icon(Icons.table_view),
              title: Text('Summary CSV'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'summary_tx'),
            child: const ListTile(
              leading: Icon(Icons.table_view),
              title: Text('Summary + transactions CSV'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'tx_photos'),
            child: const ListTile(
              leading: Icon(Icons.cloud_upload),
              title: Text('Transactions + photos'),
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

    if (choice == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Building combined export...')),
    );

    final report = await DatabaseService.getCombinedProjectReport(
      from: _range.from,
      to: _range.to,
      useScanDate: _dateBasis == DateBasis.scanDate,
    );
    final result = await ExportService.shareCombinedReportSummary(
      report: report,
      range: _range,
      dateBasis: _dateBasis,
      summaryAsPdf: choice == 'summary_pdf',
      includeTransactions: choice == 'summary_tx' || choice == 'tx_photos',
      includePhotos: choice == 'tx_photos',
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

  String _money(double value) => formatAppMoney(value, decimals: 0, withSymbol: false);

  String _moneyOrDash(double value) {
    if (value.abs() < 0.005) return '-';
    return _money(value);
  }
}



