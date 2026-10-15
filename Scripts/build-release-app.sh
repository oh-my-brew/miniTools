#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?Usage: build-release-app.sh <version>}"
EXECUTABLE_NAME="MiniTools"
HELPER_EXECUTABLE_NAME="MiniToolsPowerHelper"
APP_DIR="${APP_OUTPUT_PATH:-"$ROOT/dist/miniTools.app"}"
BUILD_DIR="$ROOT/.build/release-arm64"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:?Set CODE_SIGN_IDENTITY to a code-signing identity.}"

if [[ ! "$VERSION" =~ ^([0-9]{4}\.[0-9]{2}\.[0-9]{2})\.[1-9][0-9]*$ ]]; then
    echo "App version must use YYYY.MM.DD.N format: $VERSION" >&2
    exit 1
fi
PARSED_VERSION="$(/bin/date -j -f '%Y.%m.%d' \
    "${BASH_REMATCH[1]}" '+%Y.%m.%d' 2>/dev/null || true)"
if [[ "$PARSED_VERSION" != "${BASH_REMATCH[1]}" ]]; then
    echo "App version contains an invalid calendar date: $VERSION" >&2
    exit 1
fi

cd "$ROOT"
BUILD_ARGUMENTS=(
    -c release
    --triple arm64-apple-macosx26.0
    --scratch-path "$BUILD_DIR"
)
swift build "${BUILD_ARGUMENTS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGUMENTS[@]}" --show-bin-path)"

EXECUTABLE_PATH="$BIN_DIR/$EXECUTABLE_NAME"
HELPER_EXECUTABLE_PATH="$BIN_DIR/$HELPER_EXECUTABLE_NAME"
SPARKLE_FRAMEWORK_PATH="$BIN_DIR/Sparkle.framework"

ARCHITECTURES="$(lipo -archs "$EXECUTABLE_PATH")"
if [[ "$ARCHITECTURES" != "arm64" ]]; then
    echo "Executable is not arm64-only: $ARCHITECTURES" >&2
    exit 1
fi

HELPER_ARCHITECTURES="$(lipo -archs "$HELPER_EXECUTABLE_PATH")"
if [[ "$HELPER_ARCHITECTURES" != "arm64" ]]; then
    echo "Helper is not arm64-only: $HELPER_ARCHITECTURES" >&2
    exit 1
fi

APP_VERSION="$VERSION" \
APP_BUILD="${APP_BUILD:-1}" \
CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
MINITOOLS_POWER_HELPER_PATH="$HELPER_EXECUTABLE_PATH" \
MINITOOLS_SPARKLE_FRAMEWORK_PATH="$SPARKLE_FRAMEWORK_PATH" \
    "$ROOT/Scripts/assemble-app.sh" "$EXECUTABLE_PATH" "$APP_DIR"

echo "Architectures: $ARCHITECTURES"
echo "Helper architectures: $HELPER_ARCHITECTURES"
