# Receipt Scanner Handoff

## Project
- Name: `receipt_scanner`
- Root: `C:\Users\iqbal\Projects\receipt_scanner`
- Stack: Flutter + SQLite (`sqflite`)
- Main entry: `lib/main.dart`

## Current State
- App builds and runs on Android.
- Major UI fixes completed for Invoice List (table/card view flow, gross alignment, mobile fit improvements).
- Duplicate-save protection is enforced (invoice signature checks + DB integrity trigger path).
- Export/share flows are active for:
  - Invoice list exports
  - Project report summary exports
  - Combined report summary exports
- Restore flow now includes backup structure + DB validation before replace.

## Important Files
- App shell and shared imports: `lib/main.dart`
- Data layer and DB migrations/triggers/views: `lib/database_service.dart`
- Export and sharing logic (CSV/ZIP/PDF): `lib/export_service.dart`
- Shared helpers and formatting: `lib/utils/helpers.dart`
- Pages:
  - `lib/pages/receipt_entry_page.dart`
  - `lib/pages/receipt_history_page.dart` (Invoice List)
  - `lib/pages/project_report_page.dart`
  - `lib/pages/combined_report_page.dart`
  - `lib/pages/receipt_detail_page.dart`
  - `lib/pages/settings_page.dart`
  - `lib/pages/splash_page.dart`

## Build / Run (Windows + Android device)
```powershell
cd C:\Users\iqbal\Projects\receipt_scanner
flutter pub get
flutter analyze
flutter build apk --debug
flutter run -d 46061FDAS007U3
```

## Android Client Testing Build
- Recommended output for client testing:
```powershell
flutter build apk --release
```
- APK path:
  - `build\app\outputs\flutter-apk\app-release.apk`

## iOS Handover Status
- iOS handover zip prepared in project root:
  - `ReceiptScanner_iOS_Handover.zip`
- iOS conversion notes doc:
  - `iOS_App_Conversion_Steps.doc`

## Known Non-Blocking Analyzer Infos
- `prefer_const_constructors` in `lib/pages/combined_report_page.dart`
- `use_build_context_synchronously` in `lib/utils/helpers.dart`
- No blocking errors at last successful build.

## Known UX Decisions
- Currency symbol can be omitted in list/report numeric values to avoid encoding display issues.
- Invoice List table currently prioritizes readability on narrow mobile screens.
- Recent entries on scan page are day-focused.

## Pending / Nice-to-Have
- Optional cleanup of remaining analyzer info hints.
- Add lightweight regression tests for:
  - duplicate blocking behavior
  - export artifact combinations
  - restore validation path
- Continue modular refactor if desired (current code is page-split but still `part`-based under `main.dart`).

## Git / Workspace Notes
- Workspace may contain ongoing edits and untracked folders (example: regenerated `android/`, `test/`).
- Before release checkpoint:
```powershell
git status --short
git add .
git commit -m "project checkpoint"
```

## Quick Troubleshooting
- If Flutter tooling hangs:
```powershell
Remove-Item -Recurse -Force .dart_tool -ErrorAction SilentlyContinue
flutter pub get
```
- If device is not detected:
```powershell
flutter devices
```

