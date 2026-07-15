.PHONY: help list build clean init-keys build-docker build-packages repo-index test-asterisk shell info validate
.PHONY: build-22 build-23 build-20 build-modern build-all build-full
.PHONY: build-16 build-18 build-22-cert build-14 build-1.8 build-1.6 build-git
.PHONY: shell-22 shell-23 shell-20 shell-16 shell-18 shell-22-cert shell-1.8 shell-1.6 shell-git validate-22 validate-23
.PHONY: test test-all test-22 test-23 test-20 test-18 test-16 test-22-cert test-1.8 test-1.6 test-git

# --- Target architecture (multi-arch builds) --------------------------------
# ARCH selects which Alpine arch to build/test. abuild inside the container
# keys off the container's platform, so we drive it via DOCKER_DEFAULT_PLATFORM.
ARCH ?= x86_64
ifeq ($(ARCH),aarch64)
  DOCKER_DEFAULT_PLATFORM := linux/arm64
else ifeq ($(ARCH),armv7)
  DOCKER_DEFAULT_PLATFORM := linux/arm/v7
else ifeq ($(ARCH),armhf)
  DOCKER_DEFAULT_PLATFORM := linux/arm/v6
else
  DOCKER_DEFAULT_PLATFORM := linux/amd64
endif
export DOCKER_DEFAULT_PLATFORM
# Emulated 32-bit arches validate binary + version only; native arches run the
# full daemon/CLI probe.
ifneq ($(filter armv7 armhf,$(ARCH)),)
  SMOKE_LEVEL := version
else
  SMOKE_LEVEL := full
endif

# --- Alpine base (3.24 stable, or edge canary) -------------------------------
# ALPINE_VERSION is the repo-dir form (v3.24 or edge); the Docker image tag is
# the same with a leading "v" stripped. Edge appends "-edge" to the builder and
# test-image names so the 3.24 and edge trees coexist. Default: stable 3.24.
ALPINE_VERSION ?= v3.24
ALPINE_TAG := $(ALPINE_VERSION:v%=%)
ifeq ($(ALPINE_VERSION),edge)
  ALPINE_SUFFIX := -edge
else
  ALPINE_SUFFIX :=
endif

.PHONY: print-arch
print-arch:
	@echo "ARCH=$(ARCH) DOCKER_DEFAULT_PLATFORM=$(DOCKER_DEFAULT_PLATFORM) SMOKE_LEVEL=$(SMOKE_LEVEL)"

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
	@echo "  make build-modern    20 + 22 + 22-cert + 23 (fast)"
	@echo "  make build-full      20 + 22 + 22-cert + 23 + 18 + 16 + git"
	@echo "  make build-all       alias for build-full"
	@echo ""
	@echo "Build a single line (per-line targets):"
	@echo "  make build-16        Asterisk 16.30.1 on Alpine 3.24"
	@echo "  make build-18        Asterisk 18.26.4 on Alpine 3.24"
	@echo "  make build-22-cert   Asterisk 22.8.0.3 (certified) on Alpine 3.24"
	@echo "  make build-git       Asterisk master snapshot on Alpine 3.24"
	@echo "  make build-14 build-XX (frontier - expected to fail)"
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
	@grep -vE '^\s*#|^\s*$$' buildchain/versions.mk | awk -F'[[:space:]]+' 'NF>=5 { r=""; for(i=5;i<=NF;i++) r=r(i>5?" ":"")$$i; printf "  %-7s %-20s alpine %-5s %-7s %s\n", $$1, $$2, $$3, $$4, r }'
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
	@echo "Building Asterisk 22.10.1 on Alpine $(ALPINE_VERSION)..."
	@chmod +x scripts/build.sh
	@chmod +x scripts/build-repo-index.sh
	docker compose build builder-22$(ALPINE_SUFFIX)
	docker compose run --rm builder-22$(ALPINE_SUFFIX) sh /home/builder/scripts/build.sh
	@echo "✅ Asterisk 22.10.1 packages built"
	@$(MAKE) --no-print-directory repo-index-22

shell-22:
	docker compose run --rm builder-22 /bin/sh

validate-22:
	docker compose run --rm builder-22 sh -c "cd /home/builder/asterisk && abuild sanitycheck"

# --- Asterisk 23.x (current) on Alpine 3.24 ---
build-23: init-keys
	@echo "Building Asterisk 23.4.1 on Alpine $(ALPINE_VERSION)..."
	@chmod +x scripts/build.sh
	@chmod +x scripts/build-repo-index.sh
	docker compose build builder-23$(ALPINE_SUFFIX)
	docker compose run --rm builder-23$(ALPINE_SUFFIX) sh /home/builder/scripts/build.sh
	@echo "✅ Asterisk 23.4.1 packages built"
	@$(MAKE) --no-print-directory repo-index-22

shell-23:
	docker compose run --rm builder-23 /bin/sh

validate-23:
	docker compose run --rm builder-23 sh -c "cd /home/builder/asterisk && abuild sanitycheck"

# --- Green lines (14/16/18/20/22-cert/1.6/1.8) on Alpine 3.24 ---
build-20 build-18 build-16 build-22-cert build-14 build-1.8 build-1.6: init-keys
	@echo "Building Asterisk line $(@:build-%=%) on Alpine $(ALPINE_VERSION)..."
	@chmod +x scripts/build.sh scripts/build-repo-index.sh
	docker compose build builder-$(@:build-%=%)$(ALPINE_SUFFIX)
	docker compose run --rm builder-$(@:build-%=%)$(ALPINE_SUFFIX) sh /home/builder/scripts/build.sh
	@$(MAKE) --no-print-directory repo-index-22
	@echo "✅ line $(@:build-%=%) packages built"

# --- Asterisk git (master snapshot): refresh _gitrev/pkgver, then build ---
build-git: init-keys
	@echo "Snapshotting Asterisk master into packages/git/APKBUILD..."
	@chmod +x scripts/git-snapshot.sh scripts/build.sh scripts/build-repo-index.sh
	./scripts/git-snapshot.sh packages/git/APKBUILD
	docker compose build builder-git$(ALPINE_SUFFIX)
	docker compose run --rm builder-git$(ALPINE_SUFFIX) sh /home/builder/scripts/build.sh
	@$(MAKE) --no-print-directory repo-index-22
	@echo "✅ Asterisk git packages built"

shell-18 shell-16 shell-22-cert shell-1.8 shell-1.6 shell-git:
	docker compose run --rm builder-$(@:shell-%=%) /bin/sh

# --- Tier groupings ---
build-modern: build-20 build-22 build-22-cert build-23
build-full:   build-23 build-22 build-22-cert build-20 build-18 build-16 build-git
build-all:    build-full

# ============================================================================
# Repository indexing (per Alpine base)
# ============================================================================

repo-index-22:
	@echo "Indexing repository ($(ALPINE_VERSION))..."
	docker compose run --rm -e ALPINE_VERSION=$(ALPINE_VERSION) -e ARCH=$(ARCH) builder-22$(ALPINE_SUFFIX) \
		sh /home/builder/scripts/build-repo-index.sh
	@echo "✅ $(ALPINE_VERSION) repo index created"

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
	@docker build -t asterisk-alpine-test$(ALPINE_SUFFIX) -f docker/test.Dockerfile --build-arg ALPINE_VERSION=$(ALPINE_TAG) . 2>&1 | tail -1

# Run the test for one version. Args: VER=<pkgver> [RELAXED=1 for certified]
define _run_test
	@echo ""
	@echo "═══ test asterisk $(1) [$(ALPINE_VERSION)] ═══"
	@docker run --rm \
		-v $(CURDIR)/repository/$(ALPINE_VERSION)/main:/repo:ro \
		-v $(CURDIR)/keys:/keys:ro \
		-e ASTERISK_VERSION=$(1) \
		-e SMOKE_LEVEL=$(SMOKE_LEVEL) \
		$(if $(2),-e RELAXED=1,) \
		asterisk-alpine-test$(ALPINE_SUFFIX)
endef

test: test-image
	@echo "Run 'make test-all' to test every green version, or 'make test-<line>'."

test-all: test-image
	@echo "Running tests against all green versions..."
	@$(MAKE) --no-print-directory test-23 test-22 test-22-cert test-20 test-18 test-16 test-1.8 test-1.6 test-git

test-23:       test-image ; $(call _run_test,23.4.1)
test-22:       test-image ; $(call _run_test,22.10.1)
test-22-cert:  test-image ; $(call _run_test,22.8.0.3,relaxed)
test-20:       test-image ; $(call _run_test,20.20.1)
test-18:       test-image ; $(call _run_test,18.26.4)
test-16:       test-image ; $(call _run_test,16.30.1)
test-1.8:       test-image ; $(call _run_test,1.8.32.3,relaxed)
test-1.6:       test-image ; $(call _run_test,1.6.2.24,relaxed)

# git pkgver is dynamic (set by git-snapshot.sh at build time); read it at
# parse time so 'make test-git' works as its own invocation after build-git.
GIT_PKGVER := $(shell grep '^pkgver=' packages/git/APKBUILD 2>/dev/null | cut -d= -f2)
test-git:       test-image ; $(call _run_test,$(GIT_PKGVER),relaxed)

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
