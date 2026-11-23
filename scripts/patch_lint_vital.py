#!/usr/bin/env python3
"""Skip Android lint-vital tasks in every Gradle module.
Lint-vital crashes inside some plugin libraries on CI (NoSuchMethodError in lint itself),
which fails assembleRelease. Idempotent; run from the project root."""
import pathlib, sys

MARK = "lintVital"
root = next((p for p in (pathlib.Path("android/build.gradle.kts"), pathlib.Path("android/build.gradle")) if p.exists()), None)
if root is None:
    sys.exit("no android/build.gradle(.kts) found")
text = root.read_text()
if MARK in text:
    print("lint-vital already disabled")
    sys.exit(0)
if root.suffix == ".kts":
    block = '''
// CI: lint-vital crashes inside some plugin libraries (bug in lint), so skip it for all modules.
subprojects {
    tasks.configureEach {
        if (name.startsWith("lintVital")) {
            enabled = false
        }
    }
}
'''
else:
    block = '''
// CI: lint-vital crashes inside some plugin libraries (bug in lint), so skip it for all modules.
subprojects {
    tasks.configureEach { task ->
        if (task.name.startsWith("lintVital")) {
            task.enabled = false
        }
    }
}
'''
root.write_text(text.rstrip("\n") + "\n" + block)
print("patched", root)
