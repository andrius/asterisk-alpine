#!/bin/sh
# Install the abuild signing key for CI.
# With ABUILD_PRIVATE_KEY set (trusted events): use the real key.
# Without it (fork PRs): generate an ephemeral throwaway key so build+test
# still run; such runs never publish.
set -eu

KEY_NAME="${ABUILD_KEY_NAME:-packages@asterisk-alpine.rsa}"
mkdir -p keys

if [ -n "${ABUILD_PRIVATE_KEY:-}" ]; then
    printf '%s\n' "$ABUILD_PRIVATE_KEY" > "keys/$KEY_NAME"
    echo "Installed signing key from ABUILD_PRIVATE_KEY."
else
    echo "No ABUILD_PRIVATE_KEY (fork PR?) - generating ephemeral key."
    openssl genrsa -out "keys/$KEY_NAME" 2048
fi

chmod 600 "keys/$KEY_NAME"
openssl rsa -in "keys/$KEY_NAME" -pubout -out "keys/$KEY_NAME.pub" 2>/dev/null
chmod 644 "keys/$KEY_NAME.pub"

cat > keys/abuild.conf <<EOF
PACKAGER_PRIVKEY="/home/builder/.abuild/$KEY_NAME"
MAINTAINER="Andrius Kairiukstis <k@c0.lt>"
REPODEST="/home/builder/packages/v3.24"
EOF

echo "Signing key ready: keys/$KEY_NAME"
