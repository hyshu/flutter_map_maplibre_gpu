#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

./tool/ci/resolve_dependencies.sh
dart format --output=none --set-exit-if-changed lib test example/lib example/test example/integration_test examples/current_location/lib examples/current_location/test
flutter analyze --fatal-infos --no-pub
flutter test --no-pub
for package_dir in example examples/current_location; do
    (
        cd "${package_dir}"
        flutter analyze --fatal-infos --no-pub
        flutter test --no-pub
    )
done
