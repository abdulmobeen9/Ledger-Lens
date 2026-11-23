#!/usr/bin/env bash
# Installs the APK on a running emulator, launches it, and captures the crash log.
# Usage: scripts/smoke_test.sh path/to/app-release.apk
set -u
APK="${1:?apk path}"
PKG="com.ledgerlens.ledgerlens"
OUT="smoke-logs"
mkdir -p "$OUT"

adb logcat -c
adb install -r "$APK" 2>&1 | tee "$OUT/install.txt"
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 2>&1 | tee "$OUT/launch.txt"
sleep 30

adb logcat -d > "$OUT/logcat_full.txt" 2>&1
adb logcat -d -b crash > "$OUT/crash.txt" 2>&1
adb shell pidof "$PKG" > "$OUT/pid.txt" 2>&1 || true

echo "=== crash buffer ==="
cat "$OUT/crash.txt"
echo "=== app-related errors ==="
grep -E "FATAL EXCEPTION|AndroidRuntime|Fatal signal|SIGSEGV|ledgerlens|flutter" "$OUT/logcat_full.txt" | grep -Ei "error|exception|fatal|signal|caused by|E/" | head -80

if [ -s "$OUT/pid.txt" ] && ! grep -q "FATAL EXCEPTION\|Fatal signal" "$OUT/logcat_full.txt"; then
  echo "SMOKE TEST PASSED: app is still running after 30s."
  exit 0
fi
echo "SMOKE TEST FAILED: app crashed or exited."
exit 1
