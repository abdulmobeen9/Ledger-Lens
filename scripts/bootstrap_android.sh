#!/usr/bin/env bash
# Generates the Android Gradle scaffold and applies the LedgerLens patches.
# Safe to re-run. Run from the project root (the folder containing pubspec.yaml).
set -euo pipefail

[ -f pubspec.yaml ] || { echo "Run this from the project root (pubspec.yaml not found)."; exit 1; }
command -v flutter >/dev/null || { echo "Flutter is not on PATH."; exit 1; }

MANIFEST=android/app/src/main/AndroidManifest.xml
SAVED_MANIFEST="$(mktemp)"
HAVE_MANIFEST=0
if [ -f "$MANIFEST" ]; then cp "$MANIFEST" "$SAVED_MANIFEST"; HAVE_MANIFEST=1; fi

rm -rf android
flutter create --platforms=android --org com.ledgerlens --project-name ledgerlens .

# `flutter create` may add a default widget test that references MyApp and would break `flutter test`.
if [ -f test/widget_test.dart ] && grep -q "MyApp" test/widget_test.dart; then rm test/widget_test.dart; fi

# 1. Restore the LedgerLens manifest (permissions + OAuth callback intent filter).
if [ "$HAVE_MANIFEST" = "1" ]; then cp "$SAVED_MANIFEST" "$MANIFEST"; fi
rm -f "$SAVED_MANIFEST"

# 2. minSdk 23 (ML Kit + biometrics).
for gradle in android/app/build.gradle.kts android/app/build.gradle; do
  if [ -f "$gradle" ]; then
    sed -i -E 's/minSdk = flutter\.minSdkVersion/minSdk = maxOf(flutter.minSdkVersion, 23)/; s/minSdkVersion flutter\.minSdkVersion/minSdkVersion 23/' "$gradle"
  fi
done

# 3. local_auth on Android needs a FragmentActivity.
MAIN_ACTIVITY="$(find android/app/src/main -name 'MainActivity.kt' | head -n 1)"
if [ -n "$MAIN_ACTIVITY" ]; then
  PACKAGE_LINE="$(grep -m1 '^package ' "$MAIN_ACTIVITY")"
  cat > "$MAIN_ACTIVITY" <<KOTLIN
$PACKAGE_LINE

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
KOTLIN
fi

# 4. local_auth's fallback dialogs need an AppCompat-based theme.
for styles in $(find android/app/src/main/res -name styles.xml); do
  sed -i 's#@android:style/Theme.Light.NoTitleBar#Theme.AppCompat.Light.NoActionBar#g; s#@android:style/Theme.Black.NoTitleBar#Theme.AppCompat.NoActionBar#g' "$styles"
done

# 5. Release signing from android/key.properties (falls back to the debug key when absent).
python3 scripts/patch_signing.py || echo "Signing patch skipped."

# 6. R8: ML Kit text recognition references optional CJK/Devanagari modules that are not bundled.
python3 scripts/patch_r8_rules.py || { echo "R8 rules patch failed."; exit 1; }

# 7. Lint-vital crashes inside plugin libraries on CI; skip it.
python3 scripts/patch_lint_vital.py || { echo "Lint patch failed."; exit 1; }

echo "Android scaffold generated and patched."
