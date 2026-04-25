#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PROJECT_PATH="${ROOT_DIR}/Nocline/Nocline.xcodeproj"
SCHEME="Nocline"
DESTINATION="platform=macOS"

BUILD_ROOT="${ROOT_DIR}/build/local-install"
DERIVED_DATA_PATH="${BUILD_ROOT}/DerivedData"
SOURCE_PACKAGES_PATH="${ROOT_DIR}/build/SourcePackages"
PACKAGE_CACHE_PATH="${ROOT_DIR}/build/cache/swiftpm"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Debug/Nocline.app"
INSTALL_PATH="/Applications/Nocline.app"

step() {
    echo ""
    echo "===> $1"
    echo ""
}

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

require_command() {
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        fail "Missing required command: ${command_name}"
    fi
}

prepare_dirs() {
    mkdir -p "$BUILD_ROOT" "$SOURCE_PACKAGES_PATH" "$PACKAGE_CACHE_PATH"
}

resolve_packages() {
    xcodebuild \
        -resolvePackageDependencies \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_PATH" \
        -packageCachePath "$PACKAGE_CACHE_PATH"
}

build_app() {
    xcodebuild \
        build \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -destination "$DESTINATION" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_PATH" \
        -packageCachePath "$PACKAGE_CACHE_PATH" \
        -disableAutomaticPackageResolution \
        -skipPackageUpdates \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        ENABLE_DEBUG_DYLIB=NO
}

sign_app() {
    codesign --force --deep --sign - "$APP_PATH"
}

verify_app() {
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
}

install_app() {
    sudo ditto "$APP_PATH" "$INSTALL_PATH"
}

main() {
    require_command xcodebuild
    require_command codesign
    require_command ditto
    require_command sudo

    prepare_dirs

    step "Resolve Swift Packages"
    resolve_packages

    step "Build Nocline"
    build_app

    [[ -d "$APP_PATH" ]] || fail "Build completed without producing ${APP_PATH}"

    step "Sign App Bundle"
    sign_app

    step "Verify App Bundle"
    verify_app

    step "Install To Applications"
    install_app

    step "Done"
    echo "Installed ${INSTALL_PATH}"
}

main "$@"
