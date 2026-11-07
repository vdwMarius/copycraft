#!/usr/bin/env bash
# Build the debug APK into build/fancraft-debug.apk (run tools/bootstrap.py once first).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$here/godot.sh" --headless --import --quit >/dev/null 2>&1 || true
"$here/godot.sh" --headless --export-debug Android "$here/../build/fancraft-debug.apk"
ls -lh "$here/../build/fancraft-debug.apk"
