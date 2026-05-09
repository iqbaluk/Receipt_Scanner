# Receipt Scanner

Android receipt and invoice tracker for property renovation work.

The app is currently at version 0.9. It supports editable categories, project
tracking, project reports, scan history search, manual receipt entry, optional
photo capture, Gemini-powered auto-fill, local SQLite storage, duplicate
detection, smart photo filenames, and CSV/photo export through the Android share
sheet.

## Current Features

- Project list home screen for separating different renovation jobs.
- First page actions for selecting a project and scanning, with project create,
  history, edit, and delete grouped in a compact actions menu.
- Scan history search by supplier, invoice date, scan date, scan number, VAT,
  net, or gross amount.
- Editable receipt categories. Gemini scanning uses the current category list.
- Project reports with receipt count, gross/net/VAT totals, category breakdowns,
  date ranges, invoice-vs-scan date basis, and budget progress.
- Manual entry always works, even without network access or a Gemini API key.
- Take a receipt photo with the camera or choose one from the gallery.
- Scan a photo with Gemini to extract date, supplier, category, VAT, gross, net,
  and notes.
- Save receipts locally to SQLite with app-private photo storage.
- Recent receipts list with thumbnail, scan number, category, supplier, date,
  amount, detail view, edit, and delete.
- Smart filenames such as
  `00042_2026-04-30_Material_BandQ_127.50.jpg`.
- Duplicate detection using supplier, invoice date, and gross amount.
- Export wizard for range, content type, and date basis.
- CSV exports include both invoice date and scan date.

## Source Layout

- `lib/main.dart` - UI, form state, recent list, detail page, duplicate dialogs,
  and export flow.
- `lib/database_service.dart` - SQLite schema, migrations, receipt model, photo
  file handling, smart filenames, and duplicate queries.
- `lib/export_service.dart` - date range filtering, CSV generation, and Android
  share sheet handoff.
- `lib/gemini_service.dart` - Gemini API wrapper with defensive parsing and
  failure-safe scan results.

## Setup

1. Install Flutter for Windows from `https://docs.flutter.dev/install/windows`.
2. Install Android Studio and accept Android SDK licences.
3. Enable USB debugging on the Android phone.
4. Create `C:\Users\iqbal\Projects\receipt_scanner\.env` with:

```text
GEMINI_API_KEY=your_key_here
```

5. Fetch packages and run:

```powershell
cd C:\Users\iqbal\Projects\receipt_scanner
flutter pub get
flutter run
```

## Verification

```powershell
flutter analyze
flutter test
```

## iOS CI/CD (Codemagic + Shorebird)

This repository now includes `codemagic.yaml` with two iOS workflows:

- `ios-development-build`: builds and publishes a signed iOS IPA to TestFlight
  for internal testing.
- `ios-shorebird-release`: creates a Shorebird-enabled iOS release and publishes
  it to TestFlight.

### One-time Codemagic setup

1. Connect this repository in Codemagic.
2. Create an App Store Connect integration in Codemagic.
3. In `codemagic.yaml`, replace `APP_STORE_CONNECT` with your integration name.
4. Upload/manage iOS signing assets in Codemagic for bundle ID
   `com.example.receiptScanner` (or change the bundle ID in `codemagic.yaml`
   first, then use that ID in signing).
5. Create a secret variable group named `shorebird` and add
   `SHOREBIRD_TOKEN` (for Shorebird workflows only).

### Build order

1. Run `ios-development-build` first to test on iPhone via TestFlight.
2. When ready to go live with OTA support:
   - run `shorebird init` once locally,
   - commit `shorebird.yaml`,
   - run `ios-shorebird-release`.
3. After that, use Shorebird patching for Dart/UI logic changes, and ship a new
   store build for native/plugin changes.

## Roadmap

- Later: multi-photo receipts, mileage logging, recurring templates, Sage CSV
  export, optional cloud sync, and iOS production rollout hardening.
