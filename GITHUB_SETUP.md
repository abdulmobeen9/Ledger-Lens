# GitHub setup — Android build

## 1. Android platform project

GitHub Actions now generates the Android Gradle scaffold automatically (it runs `scripts/bootstrap_android.sh` when `android/settings.gradle(.kts)` is missing), so you can push this folder as-is.

To build locally, run `scripts/bootstrap_android.ps1` (Windows) or `scripts/bootstrap_android.sh` once, then:

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

Do not commit `local.properties`, signing keys, `key.properties`, `.env.json`, or any service-role secret.

## 2. Create the GitHub repository

1. Sign in at https://github.com and choose **New repository**.
2. Name it `ledgerlens`.
3. Choose **Private** (recommended for a financial app), initialize without a README/license/gitignore, and create it.
4. On your computer, from the `ledgerlens` project root:

```powershell
git init
git add .
git commit -m "Initial LedgerLens Android app"
git branch -M main
git remote add origin https://github.com/YOUR_GITHUB_USERNAME/ledgerlens.git
git push -u origin main
```

Replace `YOUR_GITHUB_USERNAME` with your GitHub username. If Git asks for credentials, use GitHub's browser sign-in or a Personal Access Token; do not put a token in the remote URL.

## 3. Add repository Actions secrets

In GitHub: **Settings → Secrets and variables → Actions → New repository secret**. Add:

- `SUPABASE_URL` — your Supabase project URL
- `SUPABASE_ANON_KEY` — your Supabase anon/publishable key

These values are public client configuration, but repository secrets keep environment configuration out of source control. Never add the Supabase service-role key to GitHub Actions or the Flutter app.

## 4. Automatic CI and APK artifact

`.github/workflows/android.yml` runs on pushes to `main`/`master`, pull requests, and manual dispatch. It installs Flutter/Java, runs `pub get`, generates Drift code, runs `flutter analyze` and `flutter test`, then builds a release-mode APK on branch pushes and uploads it as a GitHub Actions artifact.

Find the APK under **Actions → successful workflow run → Artifacts**. This APK uses CI/debug signing and is for device testing only. It is NOT a Google Play upload artifact. Pull requests run validation but do not receive deployment secrets or build the APK.

## 5. Google Play signing (required before Play Console upload)

Create a dedicated upload keystore and keep it outside the repository. For example:

```powershell
keytool -genkey -v -keystore ledgerlens-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias ledgerlens
```

Back up the keystore securely. Never regenerate or lose it without following Google Play upload-key reset procedures. Configure the Android Gradle release signing block to read `android/key.properties` (kept in `.gitignore`) or environment variables. Add the keystore and passwords as protected GitHub Actions secrets before adding a signed AAB job. Do not upload the CI/debug-signed APK to Play Console.

For a local signed build after configuring Gradle signing:

```powershell
flutter build appbundle --release --dart-define=SUPABASE_URL="YOUR_SUPABASE_URL" --dart-define=SUPABASE_ANON_KEY="YOUR_SUPABASE_ANON_KEY"
```

Output: `build/app/outputs/bundle/release/app-release.aab`.

## 6. Supabase deployment

The mobile workflow does not automatically deploy Supabase migrations. Do that deliberately from a trusted workstation after reviewing migrations:

```powershell
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

Confirm Google provider settings and the exact redirect URL configured in the app/Supabase Auth settings before testing OAuth. Keep development and production Supabase projects separate.

## 7. Release gate

Before production: install the APK on a physical Android device; test email/Google sign-in, receipt camera/gallery, OCR extraction, offline create/edit/delete, force-stop/relaunch, reconnect and cross-device sync, signed receipt previews, biometric/PIN fallback, CSV export, RLS with two users, and backup restoration. Check Play Console target API requirements, privacy/data safety declarations, account deletion requirements, app signing, store listing, and screenshots at release time.

## Deploying with GitHub Actions

Add these under **Settings → Secrets and variables → Actions → Repository secrets**.

| Secret | Used by | Notes |
|---|---|---|
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | CI, Release | Project URL and anon (public) key |
| `ANDROID_KEYSTORE_BASE64` | Release | `base64 -w0 upload-keystore.jks` (optional; without it the APK is debug-signed) |
| `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Release | Key password may be omitted if it equals the store password |
| `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD` | Supabase deploy | Token from supabase.com/dashboard/account/tokens |

Create a keystore once: `keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`. Keep it backed up and out of Git.

- **Android CI** (`android.yml`): analyze, test and build an APK on every push and pull request.
- **Release** (`release.yml`): `git tag v1.1.0 && git push origin v1.1.0` builds a signed APK and AAB and publishes a GitHub Release.
- **Supabase deploy** (`supabase-deploy.yml`): runs on pushes that change `supabase/**`, or manually from the Actions tab.
