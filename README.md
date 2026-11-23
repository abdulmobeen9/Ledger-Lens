# LedgerLens — offline-first money manager

Flutter / Dart 3 application for manually recording income and expenses, scanning receipts, reviewing AI-extracted transaction details, and syncing records to Supabase.

> **Release status:** this repository now includes the remaining v1 implementation work (transaction detail/edit, filters, category analytics, durable delete queues, pull/push sync, signed receipt previews, device lock, and OAuth deep-link configuration). It is a release candidate, not a claim of device-certified production software. Run the build, tests, Supabase migration, and physical-device checklist below before relying on it as your only financial record.

## Prerequisites

- Flutter stable (Dart 3.3+), Android Studio / Android SDK
- A free Supabase project (the CLI is optional; the SQL Editor works)
- Google Cloud OAuth web client, only if you want Google sign-in (email/password needs nothing extra)

Everything in this project runs on free tiers: GitHub Actions, Supabase, and on-device ML Kit. There is no paid API.

## 1. Create the Android project

The archive contains the Flutter source plus a customised Android manifest. Generate and patch the Gradle scaffold once (CI does this automatically when `android/` is incomplete):

```bash
bash scripts/bootstrap_android.sh      # macOS / Linux / Git Bash
.\scripts\bootstrap_android.ps1       # Windows PowerShell
```

The script runs `flutter create`, restores the LedgerLens manifest, sets minSdk 23, switches `MainActivity` to `FlutterFragmentActivity` and applies an AppCompat launch theme (both required by `local_auth`). iOS is not set up in this archive; run `flutter create . --platforms=ios` and merge `ios/Runner/Info.plist` yourself if you need it.

## 2. Supabase setup

1. Create a Supabase project and copy its Project URL and anon/publishable key.
2. Link the CLI: `supabase login` then `supabase link --project-ref YOUR_PROJECT_REF`.
3. Apply migrations: `supabase db push` (migrations 001–006).
4. In Authentication → URL Configuration, add `io.supabase.ledgerlens://login-callback/` to the allowed redirect URLs.
5. In Authentication → Providers → Google, enable Google and enter the Google OAuth client ID/secret. Configure the Google OAuth consent screen and add Supabase's Google callback URL to the Google Cloud OAuth client.
6. Confirm the `receipts` Storage bucket is private and its object policies are present. Migration `001_init.sql` creates it.
7. Receipt scanning needs nothing on the server: ML Kit reads the text on the phone and built-in rules extract the fields (free, offline, private).

## 3. Environment and run

Copy `.env.example` to `.env.json` and fill in the Supabase values. It is JSON because Flutter's `--dart-define-from-file` expects JSON. `.env.json` is ignored by git.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run --dart-define-from-file=.env.json
```

`SUPABASE_URL` and `SUPABASE_ANON_KEY` are compile-time defines, not secrets. Never ship a service-role key in the app. Use a different Supabase project for development/staging and production.

## 4. Features

- **Premium dashboard** with a menu button (top-left) that opens a drawer holding every feature: Dashboard, Transactions, Reports, Add income/expense, Scan receipt, Budgets, Savings goals, Categories, Sync, Export CSV, Settings & security, Sign out
- Hero balance card with month switcher, currency selector, income/expense, savings rate; hide-amounts toggle
- 6-month cash-flow chart, spending-by-category donut, insights (daily average, top category, change vs last month)
- **Reports & analytics:** 3/6/12-month range, income vs expenses, category, payee and payment-method breakdowns
- **Budgets:** monthly overall or per-category limits with progress and over-budget colouring (stored on device)
- **Savings goals:** targets, optional dates, add-funds, progress rings (stored on device)
- Transactions grouped by day with search, type/category/date filters, swipe-to-delete, duplicate, edit
- Category manager with icons and colours; light/dark/system theme; default currency
- Email/password (with reset) and Google sign-in; Drift/SQLite offline storage using exact minor units
- Receipt scan: free on-device ML Kit OCR plus a rule-based parser; optional free Gemini AI (your own key) for higher accuracy and any language; every field stays editable before and after saving
- Background and connectivity sync with retry, tombstoned deletes, last-write-wins
- CSV export as a file (formula-injection safe)
- Biometric lock and PIN lock (salted hash, 5-attempt cooldown)

## 5. Offline sync and financial data integrity

- Local writes happen first; UI reads Drift streams.
- Transactions retain `pendingSync=true` until the server acknowledges the upsert.
- Deletes write a durable tombstone in the same SQLite transaction before removing the visible row. Tombstones are replayed before remote pulls.
- The sync worker uploads pending rows, compares timestamps, and pulls newer remote records. It intentionally performs a full user-scoped pull to avoid incremental-cursor gaps in this v1.
- Retry is exponential (2 seconds upward, capped at 5 minutes). Pending rows/tombstones survive process restarts; the foreground retry timer itself does not, and the next launch/connectivity event/periodic work/manual sync resumes work. iOS may defer background work, so do not assume a strict 15-minute sync SLA.
- Server timestamps are copied back after successful upserts to reduce device-clock drift.

**Conflict policy:** strictly newer `updated_at` wins. This is a simple LWW policy, not a merge. Users should avoid editing the same transaction simultaneously on multiple devices. For accounting-grade auditability, consider immutable journal entries and a conflict-review workflow in a later version.

## 6. Biometric / PIN lock

Enable biometrics or set a 4–8 digit PIN in Settings. The PIN is stored using `flutter_secure_storage` (Keychain on iOS / encrypted Android storage where supported). The lock gate locks when the app backgrounds and asks for biometrics or PIN on resume. The app does not upload biometric data.

Set Android `minSdk` to at least 23 for the biometric APIs. Set the iOS deployment target to the minimum required by the pinned Google ML Kit plugin (verify the current plugin release notes; use iOS 15.5 or newer if required). Test biometric fallback on devices without enrolled biometrics. Device lock is a convenience privacy barrier; it does not replace Supabase authentication or operating-system device encryption.

## 7. Google OAuth and release setup

Redirect URI: `io.supabase.ledgerlens://login-callback/`.

- Android: keep the VIEW/BROWSABLE intent filter in the generated `MainActivity` manifest; verify app links return to the app on a physical device.
- iOS: add `io.supabase.ledgerlens` to URL Types and `NSFaceIDUsageDescription`; verify the redirect with a signed build.
- Supabase: add the exact redirect URI to allowed URLs and configure Google provider credentials.
- Android release: create a private upload keystore, store passwords in CI secrets, configure `key.properties` outside version control, then `flutter build appbundle --release --dart-define-from-file=.env.json`.
- iOS release: configure a unique bundle ID, signing team, provisioning profile, app icons, privacy manifest as required by current Apple rules, then `flutter build ipa --release --dart-define-from-file=.env.json`.

Never commit keystores, provisioning profiles, `.env.json`, OAuth client secrets, or Supabase service-role credentials.

## 8. CI

`.github/workflows/android.yml` runs dependency resolution, Drift code generation, analyzer, and tests on pushes / pull requests, then builds a CI-signed APK artifact on branch pushes. See `GITHUB_SETUP.md` for repository creation and Play signing instructions. The CI APK is for testing only, not Play Console submission.

## 9. Pre-publication checklist

- [ ] `flutter analyze` has no errors; `flutter test` passes.
- [ ] `flutter build appbundle --release` succeeds on the production config.
- [ ] iOS archive succeeds on macOS with the final bundle ID and signing identity.
- [ ] Email signup, email sign-in, sign-out, Google OAuth return path, and expired-session behavior tested on devices.
- [ ] Airplane-mode create/edit/delete, app force-stop, relaunch, network restoration, and multi-device conflict tests pass.
- [ ] Receipt upload, OCR, extraction errors, manual corrections, signed preview expiry, and delete behavior tested.
- [ ] RLS verified with two different user accounts; private storage cannot be read by another user.
- [ ] Restore from a Supabase backup has been rehearsed. Export CSV backups regularly.
- [ ] App privacy disclosures, account deletion, support contact, store screenshots, and legal terms completed.

## Future work

Recurring transactions, bank integrations, multi-currency conversion, category edit history, incremental sync cursors, immutable audit ledger, automated backup/export scheduling, and conflict resolution UI are intentionally outside this v1 scope.

## 10. GitHub Android build and deployment

See [`GITHUB_SETUP.md`](GITHUB_SETUP.md) for Windows PowerShell instructions to generate the full Android Gradle scaffold, create and push a GitHub repository, configure Actions secrets, retrieve the APK artifact, configure Play signing, and deploy Supabase separately. The workflow is `.github/workflows/android.yml`. Its CI-signed APK is for testing only; configure a private upload keystore and a signed AAB workflow before Google Play submission.
