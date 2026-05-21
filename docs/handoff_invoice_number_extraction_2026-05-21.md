# Handoff: Invoice Number Extraction Reliability (May 21, 2026)

## Project
- Root: `C:\Users\iqbal\Projects\receipt_scanner`
- Active target: `lib/gemini_service.dart`

## Goal of this handoff
Fix AI misses for invoice number extraction (example: BANOZE invoice with `Invoice No: BNZ2024085940`) and keep checks targeted/fast.

## What was implemented (already patched)
File changed:
- `lib/gemini_service.dart`

Changes made:
1. Prompt rules strengthened for invoice number extraction:
- Full-page scan instruction (not only header).
- Strong label priority:
  - `Invoice No`, `Invoice Number`, `Inv No`, `Invoice #`, `Tax Invoice No`, `Document No`, `Bill No`, `Doc Ref`.
- Handles stuck label-value cases:
  - e.g. `Invoice No:BNZ123`.
- Multi-candidate selection guidance:
  - choose invoice/billing-context number near invoice date/total.
- Explicit negative labels to ignore:
  - `VAT No`, `Company No`, `Tel`, `Account No`, `Customer Ref`, `Route`, `POD`.

2. JSON schema extended in prompt:
- Added `extraction_warnings` array.

3. Parser updates:
- Handles `invoice_number = "NOT_FOUND"` as null.
- Parses `extraction_warnings` / `warnings` into `ReceiptData.extractionWarnings`.

4. `ReceiptData` model update:
- Added field:
  - `final List<String> extractionWarnings;`

## Why this helps
- Reduces false misses when invoice number is outside top header.
- Reduces false picks from VAT/Company/phone/reference lines.
- Gives explicit warnings back to UI flow for manual correction.

## Pending check (run in PowerShell)
Use only targeted command:

```powershell
cls; cd C:\Users\iqbal\Projects\receipt_scanner; dart format lib\gemini_service.dart; flutter analyze lib\gemini_service.dart
```

If analyze is slow, run in two steps:

```powershell
cls; cd C:\Users\iqbal\Projects\receipt_scanner; dart format lib\gemini_service.dart
cls; cd C:\Users\iqbal\Projects\receipt_scanner; flutter analyze lib\gemini_service.dart
```

## Test case to verify in app
Use the BANOZE invoice image and confirm:
- `Invoice No: BNZ2024085940` is extracted into invoice number field.
- If still missed, app should surface warning (through extraction warnings / existing missing-field warning path).

## If still failing (next step in new chat)
Add deterministic regex fallback over OCR/LLM text in `gemini_service.dart`:
- Run only if parsed `invoiceNumber == null`.
- Regex around preferred labels, with negative-label rejection.
- Return best candidate by label priority and proximity.

## Operating guidance for next session
- Do targeted edits only.
- Check only changed files first.
- Avoid full-project analyze unless user asks.
