#!/bin/sh
# Build Asterisk APK packages using abuild
# This script runs inside the builder container

set -e

ASTERISK_DIR="${ASTERISK_DIR:-/home/builder/asterisk}"
PACKAGES_DIR="${PACKAGES_DIR:-/home/builder/packages}"
ABUILD_CONF="${ABUILD_CONF:-/home/builder/.abuild/abuild.conf}"

echo "==================================="
echo "Asterisk Alpine Package Builder"
echo "==================================="
echo ""
echo "Build directory: $ASTERISK_DIR"
echo "Output directory: $PACKAGES_DIR"
echo "Config: $ABUILD_CONF"
echo ""

# Check if we're running as builder user
if [ "$(id -u)" = "0" ]; then
    echo "ERROR: This script should not be run as root"
    echo "abuild refuses to run as root for security reasons"
    exit 1
fi

# Check if signing keys exist
if [ ! -f "$HOME/.abuild/packages@asterisk-alpine.rsa" ]; then
    echo "ERROR: Signing keys not found!"
    echo "Please run 'make init-keys' first to generate signing keys"
    exit 1
fi

# Navigate to APKBUILD directory
cd "$ASTERISK_DIR"

# Check if APKBUILD exists
if [ ! -f "APKBUILD" ]; then
    echo "ERROR: APKBUILD not found in $ASTERISK_DIR"
    exit 1
fi

echo "Checking dependencies..."
if ! command -v abuild >/dev/null 2>&1; then
    echo "ERROR: abuild not found. Please install alpine-sdk."
    exit 1
fi

echo ""
echo "Building Asterisk packages..."
echo ""

# Clean previous build artifacts
echo "Cleaning previous builds..."
abuild clean || true
abuild cleanpkg || true

# Generate checksums
echo "Generating checksums..."
abuild checksum

# Build the packages
echo "Building packages (this may take a while)..."
abuild -r

echo ""
echo "==================================="
echo "Build completed successfully!"
echo "==================================="
echo ""
echo "Packages are available in: $PACKAGES_DIR"
echo ""

# List generated packages
if [ -d "$PACKAGES_DIR" ]; then
    echo "Generated packages:"
    find "$PACKAGES_DIR" -name "asterisk*.apk" -type f -exec basename {} \;
    echo ""
    echo "Total package count: $(find "$PACKAGES_DIR" -name "asterisk*.apk" -type f | wc -l)"
fi
