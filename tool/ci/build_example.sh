#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "Usage: $0 <android|ios>" >&2
    exit 64
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${PROJECT_ROOT}/example"

case "$1" in
    android)
        flutter build apk \
            --debug \
            --no-pub \
            --target-platform android-arm64,android-x64
        python3 - <<'PY'
from zipfile import ZipFile

with ZipFile('build/app/outputs/flutter-apk/app-debug.apk') as apk:
    entries = set(apk.namelist())
for abi in ('arm64-v8a', 'x86_64'):
    library = f'lib/{abi}/libmaplibre_bridge.so'
    if library not in entries:
        raise SystemExit(f'error: APK is missing {library}')
    print(f'APK includes {library}.')
PY
        ;;
    ios)
        flutter build ios \
            --simulator \
            --debug \
            --no-codesign \
            --no-pub
        ;;
    *)
        echo "error: unsupported example platform: $1" >&2
        exit 64
        ;;
esac
