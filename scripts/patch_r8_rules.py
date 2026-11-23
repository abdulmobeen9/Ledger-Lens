#!/usr/bin/env python3
"""Add ML Kit -dontwarn rules and wire proguard-rules.pro into the release build type.
Idempotent; supports build.gradle and build.gradle.kts. Run from the project root."""
import pathlib, re, sys

app = pathlib.Path("android/app")
rules = app / "proguard-rules.pro"
RULES = """# ML Kit text recognition: optional language modules that are not bundled
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
"""
existing = rules.read_text() if rules.exists() else ""
if "mlkit.vision.text.chinese" not in existing:
    rules.write_text(existing + ("\n" if existing and not existing.endswith("\n") else "") + RULES)

gradle = next((p for p in (app / "build.gradle.kts", app / "build.gradle") if p.exists()), None)
if gradle is None:
    sys.exit("no android/app/build.gradle(.kts) found")
text = gradle.read_text()
if "proguard-rules.pro" in text:
    print("gradle already references proguard-rules.pro")
    sys.exit(0)

kts = gradle.suffix == ".kts"
line = ('proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")'
        if kts else
        "proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'")
m = re.search(r"(buildTypes\s*\{.*?\brelease\s*\{)([ \t]*\n?)", text, re.S)
if not m:
    sys.exit("could not find buildTypes { release { in " + str(gradle))
text = text[:m.end(1)] + "\n            " + line + "\n" + text[m.end(1):]
gradle.write_text(text)
print("patched", gradle)
