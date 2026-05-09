part of '../main.dart';

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
    final next = await _pickExportRange(
      context,
      title: 'Invoice list range',
    );
    if (next == null || !mounted) return;
    setState(() => _range = next);
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
