String? cleanNullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}

double? parseLooseDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final text = value.toString().replaceAll(RegExp(r'[£$,\\s]'), '');
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

  addIfPresent('Purchases',
      'Stock and direct materials for resale/production, trade supplies, wholesale');
  addIfPresent('Labour / Subcontractor',
      'Payroll, wages, subcontractor labour, agency staff, consultants');
  addIfPresent('Rent and Rates',
      'Office/shop/workshop rent, business rates, property rates');
  addIfPresent(
      'Heat, Light and Power', 'Electricity, gas, water, and utility bills');
  addIfPresent('Motor Expenses',
      'Vehicle fuel, repairs, insurance, road costs, and business mileage');
  addIfPresent('Travelling and Entertainment',
      'Train, taxi, flights, hotels, meals while travelling, client entertainment');
  addIfPresent(
      'Printing and Stationery', 'Paper, ink, office supplies, printing');
  addIfPresent('Telephone and Computer Charges',
      'Phone bills, internet, software subscriptions, computer services');
  addIfPresent('Equipment Hire and Rental',
      'Short-term hire/rental of equipment, plant, and machinery');
  addIfPresent(
      'Maintenance', 'Repairs, cleaning, maintenance materials, and upkeep');
  addIfPresent(
      'Bank Charges and Interest', 'Bank fees, card fees, overdraft interest');
  addIfPresent(
      'Depreciation', 'Depreciation journals and accountant adjustments');
  addIfPresent('Bad Debts', 'Written-off receivables and bad debt adjustments');
  addIfPresent('Advertisement and Marketing',
      'Facebook/Google ads, print ads, promotions, events');
  addIfPresent('Professional Fees',
      'Legal, accounting, subscriptions, bank charges, service fees');
  addIfPresent(
      'Insurance', 'Business, premises, liability, or vehicle insurance');
  addIfPresent('General Expenses',
      'Groceries/refreshments, cleaning supplies, and small miscellaneous expenses');
  addIfPresent('Donations and Charity',
      'Charity donations and charitable contributions');

  if (lines.isEmpty) {
    return '- Use the closest matching configured category.';
  }
  return lines.join('\n');
}

String categoryDecisionHintsPrompt(
  List<String> categories, {
  String? businessNature,
  String? businessDescription,
}) {
  final purchasesCategory = findCategoryByKeywords(
    categories,
    const ['purchase', 'stock', 'goods', 'supply', 'material'],
  );
  final labourSubcontractorCategory = findCategoryByKeywords(
    categories,
    const [
      'labour / subcontractor',
      'labour/subcontractor',
      'gross wages',
      'staff',
      'contractor',
      'labour',
      'payroll',
      'subcontract'
    ],
  );
  final rentRatesCategory = findCategoryByKeywords(
    categories,
    const ['rent and rates', 'rent', 'rates', 'premises'],
  );
  final utilitiesCategory = findCategoryByKeywords(
    categories,
    const [
      'heat',
      'light',
      'power',
      'utilit',
      'electric',
      'water',
      'gas',
      'waste'
    ],
  );
  final motorCategory = findCategoryByKeywords(
    categories,
    const ['motor', 'vehicle', 'fuel'],
  );
  final travelEntertainmentCategory = findCategoryByKeywords(
    categories,
    const [
      'travel',
      'travelling',
      'transport',
      'parking',
      'subsistence',
      'tfl',
      'entertainment'
    ],
  );
  final printingCategory = findCategoryByKeywords(
    categories,
    const ['printing', 'stationery', 'postage'],
  );
  final phoneComputerCategory = findCategoryByKeywords(
    categories,
    const ['telephone', 'computer', 'internet', 'software'],
  );
  final equipmentHireCategory = findCategoryByKeywords(
    categories,
    const ['equipment hire', 'rental', 'hire'],
  );
  final maintenanceCategory = findCategoryByKeywords(
    categories,
    const ['maintenance', 'repair', 'cleaning'],
  );
  final bankChargesCategory = findCategoryByKeywords(
    categories,
    const ['bank charges', 'interest', 'bank'],
  );
  final depreciationCategory = findCategoryByKeywords(
    categories,
    const ['depreciation'],
  );
  final badDebtsCategory = findCategoryByKeywords(
    categories,
    const ['bad debts', 'bad debt'],
  );
  final marketingCategory = findCategoryByKeywords(
    categories,
    const ['advertisement', 'marketing', 'advert', 'promotion', 'campaign'],
  );
  final professionalFeesCategory = findCategoryByKeywords(
    categories,
    const ['professional', 'fees', 'legal', 'account'],
  );
  final insuranceCategory = findCategoryByKeywords(
    categories,
    const ['insurance'],
  );
  final generalExpensesCategory = findCategoryByKeywords(
    categories,
    const ['general expenses', 'sundries', 'misc', 'other'],
  );
  final donationsCategory = findCategoryByKeywords(
    categories,
    const ['donation', 'charity'],
  );

  final lines = <String>[];
  final contextBits = <String>[
    businessNature?.trim() ?? '',
    businessDescription?.trim() ?? '',
  ].where((v) => v.isNotEmpty).toList();
  if (contextBits.isNotEmpty) {
    lines.add(
      '- Business context: ${contextBits.join(' | ')}. Use this context when two categories look similar.',
    );
    lines.add(
      '- Context override examples: groceries for restaurant can be Purchases; groceries for office can be General/Office expenses.',
    );
    lines.add(
      '- Context override examples: fuel for transport/logistics can be Purchases; fuel for normal office can be Travel/Motor.',
    );
    lines.add(
      '- Context override examples: car parts for garage can be Purchases; car parts for non-garage business can be Motor expenses.',
    );
    lines.add(
      '- Context override examples: paper for publisher can be Purchases; paper for office can be Printing/Stationery.',
    );
  }
  if (purchasesCategory != null) {
    lines.add(
      '- Resale stock, wholesale supply, and direct production materials -> "$purchasesCategory".',
    );
  }
  if (labourSubcontractorCategory != null) {
    lines.add(
      '- Salaries, wages, CIS labour, and contractor invoices -> "$labourSubcontractorCategory".',
    );
  }
  if (rentRatesCategory != null) {
    lines.add(
      '- Rent, lease, and business rates -> "$rentRatesCategory".',
    );
  }
  if (utilitiesCategory != null) {
    lines.add(
      '- Electricity, gas, water, and waste bills -> "$utilitiesCategory".',
    );
  }
  if (motorCategory != null) {
    lines.add(
        '- Vehicle fuel, repairs, and motor running costs -> "$motorCategory".');
  }
  if (travelEntertainmentCategory != null) {
    lines.add(
      '- Travel fares, parking, subsistence, and business entertainment -> "$travelEntertainmentCategory".',
    );
  }
  if (printingCategory != null) {
    lines.add('- Printing, stationery, and postage -> "$printingCategory".');
  }
  if (phoneComputerCategory != null) {
    lines.add(
        '- Phone bills, internet, software subscriptions, and computer services -> "$phoneComputerCategory".');
  }
  if (equipmentHireCategory != null) {
    lines.add('- Equipment hire and rental costs -> "$equipmentHireCategory".');
  }
  if (maintenanceCategory != null) {
    lines.add(
        '- Property/equipment repairs, cleaning, and upkeep -> "$maintenanceCategory".');
  }
  if (bankChargesCategory != null) {
    lines.add(
        '- Bank charges, card fees, and interest -> "$bankChargesCategory".');
  }
  if (depreciationCategory != null) {
    lines.add('- Depreciation adjustments -> "$depreciationCategory".');
  }
  if (badDebtsCategory != null) {
    lines.add('- Bad debt write-offs -> "$badDebtsCategory".');
  }
  if (marketingCategory != null) {
    lines.add(
      '- Marketing, ad platforms, campaign, and promotion costs -> "$marketingCategory".',
    );
  }
  if (professionalFeesCategory != null) {
    lines.add(
        '- Legal, accounting, and professional services -> "$professionalFeesCategory".');
  }
  if (insuranceCategory != null) {
    lines.add('- Insurance policies and premiums -> "$insuranceCategory".');
  }
  if (generalExpensesCategory != null) {
    lines.add(
      '- Groceries, tea/coffee/milk, cleaning items, and incidental small expenses -> "$generalExpensesCategory".',
    );
  }
  if (donationsCategory != null) {
    lines.add('- Charity and donation payments -> "$donationsCategory".');
  }
  if (lines.isEmpty) {
    final fallback = generalExpensesCategory ?? categories.first;
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
