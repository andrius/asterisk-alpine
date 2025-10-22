.PHONY: help build clean init-keys build-docker build-packages repo-index test-asterisk shell

# Default target
help:
	@echo "Asterisk Alpine Linux Buildchain"
	@echo "================================="
	@echo ""
	@echo "Available targets:"
	@echo "  make init-keys       - Generate RSA signing keys for packages"
	@echo "  make build-docker    - Build the Docker builder image"
	@echo "  make build-packages  - Build all Asterisk APK packages"
	@echo "  make repo-index      - Generate repository index (APKINDEX)"
	@echo "  make build           - Complete build (docker + packages + index)"
	@echo "  make test-asterisk   - Build and run Asterisk test container"
	@echo "  make shell           - Open shell in builder container"
	@echo "  make clean           - Clean build artifacts"
	@echo "  make clean-all       - Clean everything including keys"
	@echo ""

# Build everything
build: build-docker init-keys build-packages repo-index
	@echo ""
	@echo "✅ Complete build finished!"
	@echo ""

# Build Docker builder image
build-docker:
	@echo "Building Docker builder image..."
	docker compose build builder
	@echo "✅ Builder image ready"

# Initialize signing keys
init-keys:
	@echo "Initializing signing keys..."
	@if [ ! -f keys/packages@asterisk-alpine.rsa ]; then \
		docker compose run --rm builder sh -c "cd /home/builder && sh /home/builder/asterisk/init-keys.sh" || \
		(chmod +x scripts/init-keys.sh && KEYS_DIR=./keys scripts/init-keys.sh); \
	else \
		echo "✅ Keys already exist"; \
	fi

# Build packages
build-packages:
	@echo "Building Asterisk packages..."
	@chmod +x scripts/build.sh
	docker compose run --rm builder sh /home/builder/asterisk/build.sh
	@echo "✅ Packages built"

# Generate repository index
repo-index:
	@echo "Generating repository index..."
	@chmod +x scripts/build-repo-index.sh
	docker compose run --rm builder sh /home/builder/asterisk/build-repo-index.sh
	@echo "✅ Repository index created"

# Test Asterisk
test-asterisk:
	@echo "Building and starting Asterisk test container..."
	docker compose --profile runtime build asterisk
	docker compose --profile runtime up asterisk
	@echo "✅ Asterisk running"

# Start repository server
repo-server:
	@echo "Starting repository server..."
	@echo "Repository will be available at http://localhost:8080"
	docker compose --profile repository up -d repository
	@echo "✅ Repository server running"
	@echo ""
	@echo "Test with: curl http://localhost:8080/v3.22/main/x86_64/"

# Open shell in builder
shell:
	@echo "Opening shell in builder container..."
	docker compose run --rm builder /bin/sh

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf packages/asterisk/src packages/asterisk/pkg
	@docker compose run --rm builder sh -c "cd /home/builder/asterisk && abuild clean cleanpkg" || true
	@echo "✅ Build artifacts cleaned"

# Clean everything including keys
clean-all: clean
	@echo "Cleaning all generated files including keys..."
	@rm -rf repository/v3.22/main/x86_64/*.apk
	@rm -rf repository/v3.22/main/x86_64/APKINDEX.tar.gz
	@echo "WARNING: Removing signing keys!"
	@rm -rf keys/*
	@echo "✅ Everything cleaned"

# Show package info
info:
	@echo "Package Information"
	@echo "==================="
	@echo ""
	@echo "APKBUILD location: packages/asterisk/APKBUILD"
	@if [ -f packages/asterisk/APKBUILD ]; then \
		echo "Package name: $$(grep '^pkgname=' packages/asterisk/APKBUILD | cut -d= -f2)"; \
		echo "Version: $$(grep '^pkgver=' packages/asterisk/APKBUILD | cut -d= -f2)"; \
		echo "Release: $$(grep '^pkgrel=' packages/asterisk/APKBUILD | cut -d= -f2)"; \
		echo ""; \
		echo "Subpackages:"; \
		grep -A 20 '^subpackages=' packages/asterisk/APKBUILD | grep '$$pkgname' | sed 's/\t/  /g'; \
	fi
	@echo ""
	@echo "Built packages:"
	@find repository -name "asterisk*.apk" -type f 2>/dev/null | wc -l || echo "0"

# Validate APKBUILD
validate:
	@echo "Validating APKBUILD..."
	docker compose run --rm builder sh -c "cd /home/builder/asterisk && abuild sanitycheck"
	@echo "✅ APKBUILD is valid"
