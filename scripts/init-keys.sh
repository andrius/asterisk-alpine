#!/bin/sh
# Generate RSA signing keys for APK packages
# This script should be run once to set up your package signing keys

set -e

KEYS_DIR="${KEYS_DIR:-/home/builder/.abuild}"
KEY_NAME="${KEY_NAME:-packages@asterisk-alpine.rsa}"

echo "Generating RSA signing keys..."
echo "Keys directory: $KEYS_DIR"
echo "Key name: $KEY_NAME"

# Create keys directory if it doesn't exist
mkdir -p "$KEYS_DIR"

# Check if key already exists
if [ -f "$KEYS_DIR/$KEY_NAME" ]; then
    echo "WARNING: Key already exists at $KEYS_DIR/$KEY_NAME"
    echo "Do you want to overwrite it? (y/N)"
    read -r answer
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
        echo "Aborting. Using existing key."
        exit 0
    fi
    echo "Removing existing key..."
    rm -f "$KEYS_DIR/$KEY_NAME" "$KEYS_DIR/$KEY_NAME.pub"
fi

# Generate the key
echo "Generating new RSA key pair..."
openssl genrsa -out "$KEYS_DIR/$KEY_NAME" 2048
openssl rsa -in "$KEYS_DIR/$KEY_NAME" -pubout -out "$KEYS_DIR/$KEY_NAME.pub"

echo ""
echo "Keys generated successfully!"
echo "Private key: $KEYS_DIR/$KEY_NAME"
echo "Public key: $KEYS_DIR/$KEY_NAME.pub"
echo ""
echo "IMPORTANT: Keep the private key secure!"
echo "Add the public key to /etc/apk/keys/ on systems using your repository."
echo ""
echo "Setting up abuild config..."

# Create abuild.conf if it doesn't exist
if [ ! -f "$KEYS_DIR/abuild.conf" ]; then
    cat > "$KEYS_DIR/abuild.conf" <<EOF
# abuild configuration
PACKAGER_PRIVKEY="/home/builder/.abuild/$KEY_NAME"
MAINTAINER="Andrius Kairiukstis <k@c0.lt>"
# Output to <repo>/v<alpine>/main/<arch>/ so versions coexist by repo path.
REPODEST="/home/builder/packages/v3.24"
EOF
    echo "Created $KEYS_DIR/abuild.conf"
else
    echo "abuild.conf already exists"
fi

# Set proper permissions
chmod 600 "$KEYS_DIR/$KEY_NAME"
chmod 644 "$KEYS_DIR/$KEY_NAME.pub"

echo ""
echo "Setup complete! You can now build packages."
