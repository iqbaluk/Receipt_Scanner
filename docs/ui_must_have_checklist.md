# Receipt Scanner UI Must-Have Checklist

Use this checklist after every UI change to avoid regressions.

## Source of truth
- Active project folder: `C:\Users\iqbal\Projects\receipt_scanner`
- Do not apply changes in any copied/old project folder.

## 1) Home (Operations) page
- Top bar must show:
  - Reports hub icon
  - Management icon
- Summary card title uses: `Summary`
- Summary card fields:
  - `Receipts`
  - `Gross`
- Operation cards:
  - Compact size
  - Receipts count shown once only
- Bottom fixed actions:
  - `Close App` (red background, white text)
  - `+` create operation button

## 2) Receipt entry and scan page
- Top bar must show:
  - Back
  - Home
  - Invoice list
  - Reports
  - Categories
  - Upload/share
  - Clear/reset
- Page must show current operation name.
- Amount logic:
  - `Net = Gross - VAT`
  - `Paid` is separate (can be partial payment)
- Recent entries row must not overflow on mobile width.

## 3) Invoice list and exports page
- Header title: `Invoice list and exports`
- Search box visible
- Operation filter visible
- View toggle:
  - Table
  - Cards
- Selection controls visible:
  - `Select all`
  - `Clear all`
  - selected count
- Upload/print must use selected rows when any are selected.

## 4) Reports hub page
- No duplicate Home/Upload/Print rows if already in top bar.
- Keep links:
  - Invoice list and exports
  - Operation report
  - Combined report
  - Monthly activity report
- Remove link if moved elsewhere (avoid duplicates).

## 5) Management page
- Sections visible:
  - Company
  - Data
  - Operations
  - App
- Must include:
  - Company info
  - Backup database and images
  - Restore backup
  - Restore from file
  - Reset database (keeps operations)
  - Expense categories
  - Edit operation
  - Delete operation
  - Gemini API settings

## 6) Categories page
- Must be reachable from:
  - Receipt entry top bar
  - Management page
- Supports:
  - Add category
  - Edit category
  - Delete category (with safety checks)

## 7) Print/Preview behavior
- In-app print preview must have clear close/back path.
- User should never be trapped in preview screen.

## 8) Logo behavior
- Shared app logo file: `assets/app_logo.png`
- Logo should fill page banner icon area correctly.
- Launcher icon should be regenerated after logo replacement.

## 9) Validation before handing over a UI change
- Check only touched page(s), not full app.
- Confirm:
  - no overflow stripes
  - required icons/buttons still present
  - changed behavior works on mobile device

## 10) Quick targeted check command pattern
```powershell
cls
cd C:\Users\iqbal\Projects\receipt_scanner
dart format <touched_files>
flutter analyze <touched_files>
```
