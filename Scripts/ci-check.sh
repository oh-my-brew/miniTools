#!/usr/bin/env bash
# Shared macOS Actions validation for source PRs and immutable release candidates.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift --version
xcodebuild -version
git diff --check
plutil -lint Support/Info.plist
for script in Scripts/*.sh; do
    bash -n "$script"
done
python3 -m unittest discover -s Tests/ReleaseWorkflow
swift test
