.PHONY: help list build clean init-keys build-docker build-packages repo-index test-asterisk shell info validate
.PHONY: build-22 build-23 build-20 build-modern build-all build-full
.PHONY: build-15 build-16 build-17 build-18 build-22-cert build-14 build-13
.PHONY: shell-22 shell-23 shell-20 shell-15 shell-16 shell-17 shell-18 shell-22-cert validate-22 validate-23
.PHONY: test test-all test-22 test-23 test-20 test-18 test-17 test-16 test-15 test-22-cert

# Default target
help:
	@echo "Asterisk Alpine Linux Buildchain - multi-version matrix"
	@echo "========================================================="
	@echo ""
	@echo "Build a single Asterisk line:"
	@echo "  make build-22        Asterisk 22.10.1 (LTS)        on Alpine 3.24"
	@echo "  make build-23        Asterisk 23.4.1 (current)    on Alpine 3.24"
	@echo "  make build-20        Asterisk 20.11.1             on Alpine 3.22"
	@echo ""
	@echo "Build a tier:"
	@echo "  make build-modern    22 + 23 (+ 20)"
	@echo "  make build-all       every line in the matrix"
	@echo ""
	@echo "Republish the repo index after builds:"
	@echo "  make repo-index-22   index the v3.24/main/x86_64 tree"
	@echo ""
	@echo "Inspect / develop:"
	@echo "  make list            show the build matrix from buildchain/versions.mk"
	@echo "  make shell-22        shell into the 22.x builder"
	@echo "  make validate-22     abuild sanitycheck the 22.x APKBUILD"
	@echo "  make info            show built package counts"
	@echo ""
	@echo "Legacy single-version targets (unchanged from M0):"
	@echo "  make build           full M0 build (docker + keys + packages + index)"
	@echo "  make init-keys  build-docker  build-packages  repo-index"
	@echo "  make test-asterisk  shell  clean  clean-all"
	@echo ""

# Show the build matrix
list:
	@echo "Asterisk × Alpine build matrix (buildchain/versions.mk):"
	@echo ""
	@grep -vE '^\s*#|^\s*$$' buildchain/versions.mk | awk -F'[[:space:]]+' 'NF>=7 {printf "  %-6s %-10s alpine %-5s openssl %-5s pj %-8s %-7s %s\n", $$1, $$2, $$3, $$4, $$5, $$6, $$7}'
	@echo ""
	@echo "Lines present in packages/: $$(ls -d packages/*/ 2>/dev/null | sed 's|packages/||;s|/||' | tr '\n' ' ')"

# ============================================================================
# Matrix build targets
# ============================================================================

# Internal: ensure signing keys exist before any build.
init-keys:
	@echo "Initializing signing keys..."
	@if [ ! -f keys/packages@asterisk-alpine.rsa ]; then \
		chmod +x scripts/init-keys.sh && \
		docker compose run --rm builder-20 sh /home/builder/scripts/init-keys.sh; \
	else \
		echo "✅ Keys already exist"; \
	fi

# --- Asterisk 22.x (LTS) on Alpine 3.24 ---
build-22: init-keys
	@echo "Building Asterisk 22.10.1 on Alpine 3.24..."
	@chmod +x scripts/build.sh
	@chmod +x scripts/build-repo-index.sh
	docker compose build builder-22
	docker compose run --rm builder-22 sh /home/builder/scripts/build.sh
	@echo "✅ Asterisk 22.10.1 packages built"
	@$(MAKE) --no-print-directory repo-index-22

shell-22:
	docker compose run --rm builder-22 /bin/sh

validate-22:
	docker compose run --rm builder-22 sh -c "cd /home/builder/asterisk && abuild sanitycheck"

# --- Asterisk 23.x (current) on Alpine 3.24 ---
build-23: init-keys
	@echo "Building Asterisk 23.4.1 on Alpine 3.24..."
	@chmod +x scripts/build.sh
	@chmod +x scripts/build-repo-index.sh
	docker compose build builder-23
	docker compose run --rm builder-23 sh /home/builder/scripts/build.sh
	@echo "✅ Asterisk 23.4.1 packages built"
	@$(MAKE) --no-print-directory repo-index-22

shell-23:
	docker compose run --rm builder-23 /bin/sh

validate-23:
	docker compose run --rm builder-23 sh -c "cd /home/builder/asterisk && abuild sanitycheck"

# --- Green lines 13-18 + 20 + 22-cert on Alpine 3.24 ---
build-20 build-18 build-17 build-16 build-15 build-22-cert build-14 build-13: init-keys
	@echo "Building Asterisk line $(@:build-%=%) on Alpine 3.24..."
	@chmod +x scripts/build.sh scripts/build-repo-index.sh
	docker compose build builder-$(@:build-%=%)
	docker compose run --rm builder-$(@:build-%=%) sh /home/builder/scripts/build.sh
	@$(MAKE) --no-print-directory repo-index-22
	@echo "✅ line $(@:build-%=%) packages built"

shell-18 shell-17 shell-16 shell-15 shell-22-cert:
	docker compose run --rm builder-$(@:shell-%=%) /bin/sh

# --- Tier groupings ---
build-modern: build-20 build-22 build-22-cert build-23
build-full:   build-23 build-22 build-22-cert build-20 build-18 build-17 build-16 build-15
build-all:    build-full

# ============================================================================
# Repository indexing (per Alpine base)
# ============================================================================

repo-index-22:
	@echo "Indexing repository (Alpine 3.24)..."
	docker compose run --rm -e ALPINE_VERSION=v3.24 builder-22 \
		sh /home/builder/scripts/build-repo-index.sh
	@echo "✅ v3.24 repo index created"

# ============================================================================
# Legacy M0 targets (unchanged - single 20.11.1 build on 3.22)
# ============================================================================

# Build everything (M0 single-version path)
build: build-docker init-keys build-packages repo-index
	@echo ""
	@echo "✅ Complete build finished!"
	@echo ""

build-docker:
	@echo "Building Docker builder image (Alpine 3.22)..."
	docker compose build builder-20
	@echo "✅ Builder image ready"

build-packages:
	@echo "Building Asterisk 20.11.1 packages..."
	@chmod +x scripts/build.sh
	docker compose run --rm builder-20 sh /home/builder/scripts/build.sh
	@echo "✅ Packages built"

repo-index:
	@echo "Generating repository index (v3.22)..."
	@chmod +x scripts/build-repo-index.sh
	docker compose run --rm -e ALPINE_VERSION=v3.22 builder-20 \
		sh /home/builder/scripts/build-repo-index.sh
	@echo "✅ Repository index created"

# ============================================================================
# Tests: install a built version from the repo, start it, verify version + run
# ============================================================================

# Internal: build the test image once (version-agnostic; the version is read
# from ASTERISK_VERSION env at run time).
test-image:
	@docker build -t asterisk-alpine-test -f docker/test.Dockerfile --build-arg ALPINE_VERSION=3.24 . 2>&1 | tail -1

# Run the test for one version. Args: VER=<pkgver> [RELAXED=1 for certified]
define _run_test
	@echo ""
	@echo "═══ test asterisk $(1) ═══"
	@docker run --rm \
		-v $(CURDIR)/repository/v3.24/main:/repo:ro \
		-v $(CURDIR)/keys:/keys:ro \
		-e ASTERISK_VERSION=$(1) \
		$(if $(2),-e RELAXED=1,) \
		asterisk-alpine-test
endef

test: test-image
	@echo "Run 'make test-all' to test every green version, or 'make test-<line>'."

test-all: test-image
	@echo "Running tests against all green versions..."
	@$(MAKE) --no-print-directory test-23 test-22 test-22-cert test-20 test-18 test-17 test-16 test-15

test-23:       test-image ; $(call _run_test,23.4.1)
test-22:       test-image ; $(call _run_test,22.10.1)
test-22-cert:  test-image ; $(call _run_test,22.8.0.3,relaxed)
test-20:       test-image ; $(call _run_test,20.20.1)
test-18:       test-image ; $(call _run_test,18.26.4)
test-17:       test-image ; $(call _run_test,17.9.4)
test-16:       test-image ; $(call _run_test,16.30.1)
test-15:       test-image ; $(call _run_test,15.7.4)

# Legacy runtime container (M0)
test-asterisk:
	@echo "Building and starting Asterisk test container..."
	docker compose --profile runtime build asterisk
	docker compose --profile runtime up asterisk

repo-server:
	@echo "Starting repository server at http://localhost:8080"
	docker compose --profile repository up -d repository

shell:
	docker compose run --rm builder-20 /bin/sh

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf packages/asterisk/src packages/asterisk/pkg
	@rm -rf packages/22/src packages/22/pkg
	@rm -rf packages/23/src packages/23/pkg
	@docker compose run --rm builder-20 sh -c "cd /home/builder/asterisk && abuild clean cleanpkg" || true
	@echo "✅ Build artifacts cleaned"

clean-all: clean
	@echo "Cleaning all generated files including keys..."
	@find repository -name '*.apk' -delete 2>/dev/null || true
	@find repository -name 'APKINDEX.tar.gz' -delete 2>/dev/null || true
	@echo "WARNING: Removing signing keys!"
	@rm -rf keys/*
	@echo "✅ Everything cleaned"

info:
	@echo "Package Information"
	@echo "==================="
	@echo ""
	@for line in 22 23 asterisk; do \
		if [ -f packages/$$line/APKBUILD ]; then \
			echo "Line [$$line]:"; \
			echo "  pkgver: $$(grep '^pkgver=' packages/$$line/APKBUILD | cut -d= -f2)"; \
			echo "  subpackages: $$(grep -c '\$$pkgname' packages/$$line/APKBUILD)"; \
		fi; \
	done
	@echo ""
	@echo "Built packages in repository/:"
	@find repository -name "asterisk*.apk" -type f 2>/dev/null | wc -l || echo "0"

validate:
	@echo "Validating APKBUILD (20.x)..."
	docker compose run --rm builder-20 sh -c "cd /home/builder/asterisk && abuild sanitycheck"
	@echo "✅ APKBUILD is valid"
