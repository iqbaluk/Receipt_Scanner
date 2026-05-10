String? cleanNullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}

double? parseLooseDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final text =
      value.toString().replaceAll('£', '').replaceAll(RegExp(r'[$,\s]'), '');
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return double.tryParse(text);
}

String categoryExamplesPrompt(List<String> categories) {
  final lines = <String>[];
  void addIfPresent(String category, String example) {
    if (categories.contains(category)) {
      lines.add('- $example -> "$category"');
    }
  }

  addIfPresent(
    'Material',
    'B&Q, Travis Perkins, Wickes, Selco, Howdens, Screwfix',
  );
  addIfPresent('Subcontractor', 'A plumber, electrician, builder invoice');
  addIfPresent('Utility Bills', 'Gas, electricity, water, council tax');
  addIfPresent('Travel', 'Train, taxi, parking, fuel');
  addIfPresent('Insurance', 'Public liability or building insurance');
  addIfPresent('Sundries', 'Tea, biscuits, small consumables');
  addIfPresent('Other', 'Anything that does not fit the other categories');

  if (lines.isEmpty) {
    return '- Use the closest matching configured category.';
  }
  return lines.join('\n');
}

String categoryDecisionHintsPrompt(List<String> categories) {
  final insuranceCategory = findCategoryByKeywords(
    categories,
    const ['insurance'],
  );
  final serviceCategory = findCategoryByKeywords(
    categories,
    const ['subcontractor', 'professional', 'labour', 'labor', 'service'],
  );
  final materialCategory = findCategoryByKeywords(
    categories,
    const ['material', 'sundries', 'supply'],
  );
  final travelCategory = findCategoryByKeywords(
    categories,
    const ['travel', 'transport', 'fuel', 'mileage', 'parking'],
  );
  final utilitiesCategory = findCategoryByKeywords(
    categories,
    const ['utility', 'utilities', 'electric', 'water', 'gas'],
  );
  final otherCategory = findCategoryByKeywords(
    categories,
    const ['other', 'misc'],
  );

  final lines = <String>[];
  if (insuranceCategory != null) {
    lines.add(
      '- Use "$insuranceCategory" ONLY for policy/premium/cover documents from insurers or brokers.',
    );
    final fallback = serviceCategory ?? otherCategory ?? categories.first;
    lines.add(
      '- Inspection/survey/certificate/assessment/compliance jobs are NOT insurance; prefer "$fallback".',
    );
  }
  if (serviceCategory != null) {
    lines.add(
      '- Labour/service/trade callout invoices (inspection, electrician, plumber, fitting, repair) -> "$serviceCategory".',
    );
  }
  if (materialCategory != null) {
    lines.add(
      '- Goods and parts purchases (timber, paint, tools, hardware, consumables) -> "$materialCategory".',
    );
  }
  if (travelCategory != null) {
    lines.add(
      '- Train/taxi/fuel/parking/tolls/mileage receipts -> "$travelCategory".',
    );
  }
  if (utilitiesCategory != null) {
    lines.add(
      '- Electricity, gas, water, telecom or council bills -> "$utilitiesCategory".',
    );
  }
  if (lines.isEmpty) {
    final fallback = otherCategory ?? categories.first;
    lines.add('- If uncertain, use "$fallback" and avoid guessing.');
  }
  return lines.join('\n');
}

String? findCategoryByKeywords(List<String> categories, List<String> keywords) {
  for (final category in categories) {
    final lower = category.toLowerCase();
    for (final keyword in keywords) {
      if (lower.contains(keyword)) return category;
    }
  }
  return null;
}

DateTime? parseIsoOrUkDate(String? value) {
  if (value == null) return null;
  final input = value.trim();
  if (input.isEmpty || input.toLowerCase() == 'null') return null;
  final iso = DateTime.tryParse(input);
  if (iso != null) return iso;
  final m =
      RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})$').firstMatch(input);
  if (m == null) return null;
  final d = int.tryParse(m.group(1)!);
  final mo = int.tryParse(m.group(2)!);
  var y = int.tryParse(m.group(3)!);
  if (d == null || mo == null || y == null) return null;
  if (y < 100) y += 2000;
  try {
    return DateTime(y, mo, d);
  } catch (_) {
    return null;
  }
}

