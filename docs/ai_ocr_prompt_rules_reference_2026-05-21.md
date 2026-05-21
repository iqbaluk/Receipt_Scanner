# AI/OCR Prompt and Rules Reference

Date: 2026-05-21  
Project root: `C:\Users\iqbal\Projects\receipt_scanner`

## 1) Main AI extraction call
- File: `lib/pages/receipt_entry_page.dart`
- Call site: around `scanReceipt(...)` (line ~326)
- Inputs passed:
  - image bytes
  - allowed categories
  - company `businessNature`
  - company `businessDescription`

## 2) Main extraction prompt (exact intent)
- File: `lib/gemini_service.dart`
- Prompt starts near line ~396

The model is instructed to return JSON with:
- `date`
- `invoice_number`
- `supplier`
- `category`
- `category_confidence`
- `vat`
- `gross`
- `paid_amount`
- `net`
- `notes`
- `extraction_warnings`

Critical invoice-number instructions in prompt:
- Scan the full page, not only headers.
- Check boxed sections, order details, margins, footer blocks.
- Extract invoice number from preferred labels:
  - `Invoice No`, `Invoice Number`, `Inv No`, `Invoice #`, `Tax Invoice No`, `Document No`, `Bill No`, `Doc Ref`
- Also check variants:
  - `INV NO`, `INV#`, `Ref No`, `Reference No`, `Document Ref`, `Sales Invoice No`
- If joined format appears (e.g. `Invoice No:BNZ123`), extract `BNZ123`.
- If multiple candidate numbers exist, prioritize invoice/billing context near date/total.
- Ignore non-invoice labels:
  - `VAT No`, `Company No`, `Tel`, `Account No`, `Customer Ref`, `Route`, `POD`

Other key numeric rules:
- UK date interpretation (`DD/MM/YYYY`).
- `gross` should be invoice total.
- `paid_amount` should be actual paid value.
- `net` must be invoice net and treated as `gross - vat`.
- Do not derive `net` from `paid_amount`.

## 3) Secondary fallback prompt (invoice-number only)
- File: `lib/gemini_service.dart`
- Method: `_extractInvoiceNumberFallback(...)` near line ~648

Fallback prompt intent:
- Extract **only** invoice number from image.
- Same preferred labels and negative labels.
- Return exactly one token or `NOT_FOUND`.

## 4) Regex fallback used after fallback response
- File: `lib/gemini_service.dart`
- Method: `_extractInvoiceNumberByRegex(...)` near line ~699

Regex pattern:
```dart
r'(?i)\b(?:invoice\s*(?:no|number|#)|inv\s*(?:no|#)?|tax\s*invoice\s*(?:no|number)?|document\s*(?:no|number)?|bill\s*no|doc\s*ref)\b\s*[:#-]?\s*([A-Z0-9][A-Z0-9/_-]{3,})'
```

## 5) Post-scan missing-field warning in UI
- File: `lib/pages/receipt_entry_page.dart`
- Method: `_missingFieldsAfterScan()` near line ~364
- Warns for missing:
  - Invoice date
  - Invoice number
  - Supplier
  - Gross amount
  - Expense category

## 6) Category guidance prompt source
- File: `lib/utils/ai_extraction_helpers.dart`
- Methods:
  - `categoryExamplesPrompt(...)`
  - `categoryDecisionHintsPrompt(...)`
- Includes business-context category examples for ambiguous cases.

## 7) Current OCR note
- `google_mlkit_text_recognition` is listed in `pubspec.yaml`.
- Current active scan flow in `lib/` uses Gemini vision prompts; there is no separate ML Kit OCR pass in the live scan path.
