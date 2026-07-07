#!/bin/sh
# Generate APKINDEX for the package repository
# This creates the repository index that APK uses to find packages

set -e

REPO_DIR="${REPO_DIR:-/home/builder/packages}"
ALPINE_VERSION="${ALPINE_VERSION:-v3.22}"
ARCH="${ARCH:-x86_64}"
KEYS_DIR="${KEYS_DIR:-/home/builder/.abuild}"

REPO_PATH="$REPO_DIR/$ALPINE_VERSION/main/$ARCH"

echo "==================================="
echo "APK Repository Index Builder"
echo "==================================="
echo ""
echo "Repository path: $REPO_PATH"
echo "Alpine version: $ALPINE_VERSION"
echo "Architecture: $ARCH"
echo ""

# Check if packages exist
if [ ! -d "$REPO_PATH" ]; then
    echo "ERROR: Repository directory not found: $REPO_PATH"
    exit 1
fi

PKG_COUNT=$(find "$REPO_PATH" -name "*.apk" -type f | wc -l)
if [ "$PKG_COUNT" -eq 0 ]; then
    echo "WARNING: No .apk files found in $REPO_PATH"
    echo "Have you built the packages yet?"
    exit 1
fi

echo "Found $PKG_COUNT package(s)"
echo ""

# Navigate to repository directory
cd "$REPO_PATH"

# Trust our own signing key so apk index accepts our signed packages.
# Without this, apk reports every .apk as "UNTRUSTED signature" and exits,
# because this fresh container never had the key added to /etc/apk/keys.
PUBKEY="$KEYS_DIR/packages@asterisk-alpine.rsa.pub"
if [ -f "$PUBKEY" ]; then
    echo "Trusting signing public key for indexing..."
    sudo cp "$PUBKEY" /etc/apk/keys/
fi

echo "Generating APKINDEX.tar.gz..."

# Generate the index
# -x: include checksums
# -o: output file
apk index -vU -o APKINDEX.tar.gz *.apk

echo "Signing APKINDEX..."

# Sign the index
if [ -f "$KEYS_DIR/packages@asterisk-alpine.rsa" ]; then
    abuild-sign -k "$KEYS_DIR/packages@asterisk-alpine.rsa" APKINDEX.tar.gz
    echo "Index signed successfully"
else
    echo "WARNING: Signing key not found, index will not be signed"
    echo "Packages can still be installed with --allow-untrusted flag"
fi

# apk-tools 3.x fetches noarch packages from a <repo>/noarch/ path, not from the
# arch directory. The x86_64 index already lists them (A:noarch); we only need
# the package files reachable under noarch/, so mirror them there.
NOARCH_PATH="$REPO_DIR/$ALPINE_VERSION/main/noarch"
mkdir -p "$NOARCH_PATH"
tar -xzOf APKINDEX.tar.gz APKINDEX 2>/dev/null | awk '
    BEGIN { RS = ""; FS = "\n" }
    {
        p = ""; v = ""; a = ""
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^P:/) p = substr($i, 3)
            if ($i ~ /^V:/) v = substr($i, 3)
            if ($i ~ /^A:/) a = substr($i, 3)
        }
        if (a == "noarch") print p "-" v ".apk"
    }' | while read -r f; do
        [ -f "$REPO_PATH/$f" ] && cp "$REPO_PATH/$f" "$NOARCH_PATH/"
    done
echo "Mirrored $(find "$NOARCH_PATH" -name '*.apk' 2>/dev/null | wc -l) noarch package(s) to $NOARCH_PATH"

echo ""
echo "==================================="
echo "Repository index created!"
echo "==================================="
echo ""
echo "Repository is ready at: $REPO_PATH"
echo ""
echo "To use this repository, add to /etc/apk/repositories:"
echo "  http://your-server/$ALPINE_VERSION/main"
echo ""
echo "And copy the public key to /etc/apk/keys/:"
echo "  $KEYS_DIR/packages@asterisk-alpine.rsa.pub"
echo ""

# Show repository contents
echo "Repository contents:"
ls -lh APKINDEX.tar.gz
echo ""
find . -name "asterisk*.apk" -type f -exec ls -lh {} \;
