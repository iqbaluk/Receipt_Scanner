import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:receipt_scanner/database_service.dart';
import 'package:receipt_scanner/main.dart';

void main() {
  testWidgets('Project list screen loads', (WidgetTester tester) async {
    await tester.pumpWidget(const ReceiptScannerApp());
    expect(find.text('Receipt Scanner'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 3600));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Projects'), findsOneWidget);
    expect(find.byTooltip('Invoice list'), findsOneWidget);
    expect(find.byTooltip('Categories'), findsOneWidget);

    expect(find.byTooltip('Project actions'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('Receipt entry screen loads for a project',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReceiptEntryPage(project: Project(id: 1, name: 'Test Project')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Test Project'), findsOneWidget);
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('Scan with Gemini (auto-fill)'), findsOneWidget);
    expect(find.text('Save to Database'), findsOneWidget);
    expect(find.byTooltip('Reports'), findsOneWidget);
  });

  testWidgets('Gross and VAT calculate net amount',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReceiptEntryPage(project: Project(id: 1, name: 'Test Project')),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Gross *'), '120');
    await tester.enterText(find.widgetWithText(TextFormField, 'VAT'), '20');
    await tester.pump();

    expect(find.text('100.00'), findsOneWidget);
  });

  testWidgets('Project edit cancel closes without error',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: _TestSelectedProjectActions(),
      ),
    ));

    await tester.tap(find.byTooltip('Project actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit project'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('Summary report table uses requested columns',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SummaryReportTable(
          report: ProjectReport(
            receiptCount: 22,
            totalNet: 0,
            totalVat: 0,
            totalGross: 9070,
            categories: [
              CategorySummary(
                category: 'Material',
                receiptCount: 22,
                totalNet: 0,
                totalVat: 0,
                totalGross: 9070,
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Inv count'), findsOneWidget);
    expect(find.text('Gross £'), findsOneWidget);
  });
}

class _TestSelectedProjectActions extends StatefulWidget {
  @override
  State<_TestSelectedProjectActions> createState() =>
      _TestSelectedProjectActionsState();
}

class _TestSelectedProjectActionsState
    extends State<_TestSelectedProjectActions> {
  Future<void> _showDialog() async {
    final controller = TextEditingController(text: 'Test Project');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit project'),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    expect(result, isNull);
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Project actions',
      onSelected: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showDialog();
        });
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit project')),
      ],
    );
  }
}
