#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${PROJECT_ROOT}"

for package_dir in . example; do
    if [[ -e "${package_dir}/pubspec_overrides.yaml" ]]; then
        echo "error: remove ${package_dir}/pubspec_overrides.yaml to use published dependencies" >&2
        exit 1
    fi
done

flutter pub get --no-example
(
    cd example
    flutter pub get --enforce-lockfile
)

for lockfile in pubspec.lock example/pubspec.lock; do
    if ! awk '
        /^  maplibre_flutter_gpu:$/ { in_gpu = 1; next }
        in_gpu && /^  [^ ]/ { exit }
        in_gpu && /^    source: hosted$/ { hosted = 1 }
        END { exit !hosted }
    ' "${lockfile}"; then
        echo "error: ${lockfile} must resolve maplibre_flutter_gpu from a hosted package" >&2
        exit 1
    fi
    echo "Hosted maplibre_flutter_gpu dependency verified in ${lockfile}."
done
