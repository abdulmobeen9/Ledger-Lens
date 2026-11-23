#!/usr/bin/env python3
"""Adds release signing (read from android/key.properties) to android/app/build.gradle.kts.
Without key.properties the build falls back to the debug key, so local builds still work."""
import pathlib, sys

path = pathlib.Path('android/app/build.gradle.kts')
if not path.exists():
    print('build.gradle.kts not found; skipping signing patch (Groovy templates are not patched).')
    sys.exit(0)
text = path.read_text()
if 'keystoreProperties' in text:
    print('Signing already configured.')
    sys.exit(0)

header = (
    'import java.io.FileInputStream\nimport java.util.Properties\n\n'
    'val keystoreProperties = Properties()\n'
    'val keystorePropertiesFile = rootProject.file("key.properties")\n'
    'if (keystorePropertiesFile.exists()) {\n'
    '    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n'
    '}\n\n'
)
signing = (
    'android {\n'
    '    signingConfigs {\n'
    '        create("release") {\n'
    '            if (keystorePropertiesFile.exists()) {\n'
    '                keyAlias = keystoreProperties["keyAlias"] as String\n'
    '                keyPassword = keystoreProperties["keyPassword"] as String\n'
    '                storeFile = file(keystoreProperties["storeFile"] as String)\n'
    '                storePassword = keystoreProperties["storePassword"] as String\n'
    '            }\n'
    '        }\n'
    '    }\n'
)
if 'android {\n' not in text or 'signingConfig = signingConfigs.getByName("debug")' not in text:
    print('Unexpected build.gradle.kts layout; skipping signing patch.')
    sys.exit(0)
text = text.replace('android {\n', signing, 1)
text = text.replace(
    'signingConfig = signingConfigs.getByName("debug")',
    'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")',
)
path.write_text(header + text)
print('Release signing configured.')
