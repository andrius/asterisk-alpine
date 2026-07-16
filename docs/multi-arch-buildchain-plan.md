# Multi-Architecture Buildchain Implementation Plan

> **Superseded (2026-07): publish + hosting target changed.** This plan implements
> the original **GitHub Pages** apk repository (`apk.andrius.mobi`). Publishing has
> since moved to **Cloudsmith** (`asterisk/alpine`); GitHub Pages and the
> `apk.andrius.mobi` domain are retired. The multi-arch build + matrix work below
> still holds - only the publish task changed: instead of building one signed
> per-arch `APKINDEX` and deploying to Pages, CI pushes the built `.apk`s to
> Cloudsmith, which reads each package's arch from its metadata and owns indexing +
> signing. Current source of truth: the [README](../README.md) and
> `.github/workflows/_publish.yml`; rationale in the KB decision "apk hosting on
> Cloudsmith Open-Source, not GitHub Pages" (2026-07-16). Retained as a historical
> implementation record.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish signed apk packages for x86_64, aarch64, armv7, and armhf from the existing GitHub Actions buildchain, served from one repository that apk resolves per client arch automatically.

**Architecture:** Reuse the `abuild`-in-Alpine-container flow unchanged; run the builder container as the target platform (native on `ubuntu-latest`/`ubuntu-24.04-arm`, QEMU `binfmt` for 32-bit). `abuild` writes to `main/$CARCH/` by itself. The CI matrix gains an arch dimension; the publish job builds one signed `APKINDEX` per arch and shares a single canonical `noarch/` tree.

**Tech Stack:** GitHub Actions, Docker Compose, `abuild`, `apk` (Alpine 3.24 / apk-tools 3.x), `docker/setup-qemu-action`, `jq`, Make, POSIX sh.

## Global Constraints

- Single Alpine base **3.24**; repo path `v3.24/main/<arch>/`; pin tag **`@andrius-asterisk`**; signing key `packages@asterisk-alpine.rsa` from the `ABUILD_PRIVATE_KEY` secret.
- Arches and lines: native (x86_64, aarch64) build every tier line; 32-bit (armv7, armhf) build only on the **full** tier, only lines **22, 23, 22-cert**, and are **best-effort** (`continue-on-error: true`). Line 20 and the ancient lines are **not** built on 32-bit.
- Docker platform map: aarch64 -> `linux/arm64`, armv7 -> `linux/arm/v7`, armhf -> `linux/arm/v6`, x86_64 -> `linux/amd64`.
- Infra changes (Makefile, ci.yml, shell, Dockerfiles) are **TDD-exempt**: verify with dry-runs / smoke / lint, not failing-test-first.
- No AI / co-author attribution in commits, code, or messages. No em-dashes or en-dashes (plain hyphen only). Commit with `git commit --no-gpg-sign`.
- Work happens on branch `multi-arch-buildchain` (already created; the spec commit is its first commit).

---

### Task 1: Make the smoke test arch-agnostic

The test hardcodes the x86_64 noarch path (a pre-noarch-fix workaround). Now that `noarch/` is published, `sample-config` resolves from the repo on any arch. Also add a `SMOKE_LEVEL=version` mode so emulated arches validate the binary + version without the QEMU-fragile full daemon probe.

**Files:**
- Modify: `scripts/test-run.sh:26-44` (install block) and after `:59` (version-check exit)

**Interfaces:**
- Produces: env var `SMOKE_LEVEL` (values `full` default, `version`) consumed by `Makefile` (Task 2) and CI.

- [ ] **Step 1: Replace the direct-file-path install block**

Replace lines 26-44 (from the `# 2. Install ...` comment through the `echo "  installed: ..."` line) with:

```sh
# 2. Install asterisk + sample-config from our repo. Both resolve from the repo
# now that noarch packages are published under noarch/ (apk 3.x fetches noarch
# packages from <repo>/noarch/). No arch-specific paths needed.
echo "[2/5] installing asterisk ${VER} (with sample-config) from local repo..."
apk add --no-cache --repository /repo "asterisk=${VER}-r0" "asterisk-sample-config=${VER}-r0" \
    >/tmp/apk-install.log 2>&1 || {
    echo "FAIL: apk add failed:"; tail -25 /tmp/apk-install.log; exit 2
}
echo "  installed: $(apk info asterisk 2>/dev/null | head -1)"
```

- [ ] **Step 2: Add the version-only early exit after the version check**

Immediately after the `esac` that closes the `[3/5] version check` block (currently line 59), insert:

```sh
# Emulated (QEMU) arch builds validate the binary + reported version only; the
# full daemon/CLI probe is unreliable under user-mode emulation.
if [ "${SMOKE_LEVEL:-full}" = "version" ]; then
    echo "PASS (version-only): asterisk ${VER} installed and reports version"
    exit 0
fi
```

- [ ] **Step 3: Verify the full (x86_64) path still passes**

The x86_64 repo is already built locally. Run:

```bash
make test-23
```

Expected: ends with `PASS: asterisk 23.4.1 runs, reports version, core + HEP modules load` (exit 0).

- [ ] **Step 4: Verify the version-only path exits early**

```bash
make test-image
docker run --rm -v "$PWD/repository/v3.24/main:/repo:ro" -v "$PWD/keys:/keys:ro" \
  -e ASTERISK_VERSION=23.4.1 -e SMOKE_LEVEL=version asterisk-alpine-test
```

Expected: ends with `PASS (version-only): asterisk 23.4.1 installed and reports version` (exit 0), and does NOT print the `[4/5] starting asterisk` line.

- [ ] **Step 5: Commit**

```bash
git add scripts/test-run.sh
git commit --no-gpg-sign -m "Make smoke test arch-agnostic and add version-only mode

sample-config now resolves from the repo (noarch/ is published), dropping the
hardcoded x86_64 path. SMOKE_LEVEL=version validates binary + version without
the QEMU-fragile daemon probe, for emulated arches."
```

---

### Task 2: Parameterize the Makefile by target arch

Drive the container platform from an `ARCH` variable, pass `ARCH` to the indexer, and select the smoke level. Native x86_64 behavior must be unchanged when `ARCH` is unset.

**Files:**
- Modify: `Makefile` (add arch block near top; update `repo-index-22`, `_run_test`; add `print-arch`)

**Interfaces:**
- Consumes: `ARCH` (default `x86_64`); exports `DOCKER_DEFAULT_PLATFORM`; passes `ARCH` to `scripts/build-repo-index.sh` and `SMOKE_LEVEL` to `scripts/test-run.sh`.
- Produces: `make build-<line> ARCH=<arch>`, `make test-<line> ARCH=<arch>`, `make repo-index-22 ARCH=<arch>`, `make print-arch ARCH=<arch>`.

- [ ] **Step 1: Add the arch block after the `.PHONY` lines (after line 5)**

```makefile
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

.PHONY: print-arch
print-arch:
	@echo "ARCH=$(ARCH) DOCKER_DEFAULT_PLATFORM=$(DOCKER_DEFAULT_PLATFORM) SMOKE_LEVEL=$(SMOKE_LEVEL)"
```

- [ ] **Step 2: Pass `ARCH` to the indexer**

Replace the `repo-index-22` recipe body (line 122-123) so the `docker compose run` line reads:

```makefile
	docker compose run --rm -e ALPINE_VERSION=v3.24 -e ARCH=$(ARCH) builder-22 \
		sh /home/builder/scripts/build-repo-index.sh
```

- [ ] **Step 3: Pass `SMOKE_LEVEL` to the test container**

In the `_run_test` define (lines 164-173), add the env line so the `docker run` invocation includes it, right after the `-e ASTERISK_VERSION=$(1) \` line:

```makefile
		-e SMOKE_LEVEL=$(SMOKE_LEVEL) \
```

- [ ] **Step 4: Verify the arch -> platform mapping**

```bash
make print-arch                 # ARCH=x86_64 DOCKER_DEFAULT_PLATFORM=linux/amd64 SMOKE_LEVEL=full
make print-arch ARCH=aarch64    # ...linux/arm64 SMOKE_LEVEL=full
make print-arch ARCH=armv7      # ...linux/arm/v7 SMOKE_LEVEL=version
make print-arch ARCH=armhf      # ...linux/arm/v6 SMOKE_LEVEL=version
```

Expected: each prints exactly the platform and smoke level shown in the comment.

- [ ] **Step 5: Verify native build+test is unchanged**

```bash
make build-23 ARCH=x86_64 && make test-23 ARCH=x86_64
```

Expected: build completes and the smoke test ends with `PASS: asterisk 23.4.1 ...` (exit 0). Packages land in `repository/v3.24/main/x86_64/`.

- [ ] **Step 6: Commit**

```bash
git add Makefile
git commit --no-gpg-sign -m "Parameterize Makefile build/test/index by ARCH

ARCH maps to DOCKER_DEFAULT_PLATFORM so the builder container runs as the target
arch; ARCH flows to the indexer and SMOKE_LEVEL to the test. Default x86_64 keeps
current behavior."
```

---

### Task 3: CI triggers (paths-ignore) + arch x line matrix

Rewrite the `setup` job to emit a GitHub `include` matrix carrying each combo's runner, platform, and best-effort flag. Add `paths-ignore` so docs/examples pushes stop triggering full builds.

**Files:**
- Modify: `.github/workflows/ci.yml:3-15` (`on.push.paths-ignore`) and `:27-51` (`setup` job)

**Interfaces:**
- Produces: `needs.setup.outputs.matrix` = `{"include":[{line,arch,runner,platform,allow_fail}, ...]}`; `outputs.publish` (bool string); `outputs.tier` (`modern`|`full`). Consumed by Tasks 4 and 5.

- [ ] **Step 1: Add `paths-ignore` to the push trigger**

Under `on.push` (which has `branches` and `tags`), add:

```yaml
    paths-ignore:
      - '**.md'
      - 'docs/**'
      - 'examples/**'
```

- [ ] **Step 2: Replace the `setup` job `pick` step**

Replace the `run: |` body of the `pick` step (lines 35-51) with:

```yaml
        run: |
          EVENT='${{ github.event_name }}'
          INPUT_TIER='${{ github.event.inputs.tier }}'
          REF='${{ github.ref }}'
          if [ "$EVENT" = "pull_request" ]; then
            TIER=modern; PUBLISH=false
          elif [ "$EVENT" = "push" ] && [ "$REF" = "refs/heads/main" ]; then
            TIER=modern; PUBLISH=true
          elif [ "$EVENT" = "workflow_dispatch" ] && [ "$INPUT_TIER" = "modern" ]; then
            TIER=modern; PUBLISH=true
          else
            TIER=full; PUBLISH=true
          fi

          if [ "$TIER" = "modern" ]; then
            LINES='["20","22","22-cert","23"]'
          else
            LINES='["23","22","22-cert","20","18","16"]'
          fi

          # Native arches build every tier line.
          NATIVE=$(echo "$LINES" | jq -c '[ .[] as $l |
            {line:$l, arch:"x86_64",  runner:"ubuntu-latest",    platform:"", allow_fail:false},
            {line:$l, arch:"aarch64", runner:"ubuntu-24.04-arm", platform:"", allow_fail:false} ]')

          # 32-bit arches: full tier only, lines 22/23/22-cert, best-effort.
          if [ "$TIER" = "full" ]; then
            ARM32=$(jq -cn '[ ["22","23","22-cert"][] as $l |
              {line:$l, arch:"armv7", runner:"ubuntu-latest", platform:"linux/arm/v7", allow_fail:true},
              {line:$l, arch:"armhf", runner:"ubuntu-latest", platform:"linux/arm/v6", allow_fail:true} ]')
          else
            ARM32='[]'
          fi

          INCLUDE=$(jq -cn --argjson a "$NATIVE" --argjson b "$ARM32" '$a + $b')
          echo "matrix={\"include\":$INCLUDE}" >> "$GITHUB_OUTPUT"
          echo "publish=$PUBLISH" >> "$GITHUB_OUTPUT"
          echo "tier=$TIER" >> "$GITHUB_OUTPUT"
```

- [ ] **Step 3: Verify the matrix logic locally for each event**

Copy the pick step's shell body (everything after `run: |`) into `/tmp/pick.sh`, prepend a `#!/bin/sh` line, and replace the three `'${{ ... }}'` placeholders with `"$EVENT"`, `"$INPUT_TIER"`, `"$REF"` so it reads from the environment. Then run it per event with `GITHUB_OUTPUT` pointed at stdout and inspect the matrix:

```bash
check() { EVENT="$1" INPUT_TIER="$2" REF="$3" GITHUB_OUTPUT=/dev/stdout sh /tmp/pick.sh \
  | sed -n 's/^matrix=//p' | jq -c '{n:(.include|length), arches:(.include|map(.arch)|unique), arm32_ok:(.include|map(select(.arch|test("arm")))|all(.allow_fail))}' ; }
check pull_request '' refs/heads/x            # modern
check push '' refs/heads/main                 # modern
check workflow_dispatch full refs/heads/multi-arch-buildchain   # full
```

Expected `check` output (the matrix line only; `publish`/`tier` also print on their own lines in full stdout):
- `pull_request`: `{"n":8,"arches":["aarch64","x86_64"],"arm32_ok":true}` (modern, native only; `publish=false tier=modern`).
- `push` to main: `{"n":8,"arches":["aarch64","x86_64"],"arm32_ok":true}` (`publish=true tier=modern`).
- `workflow_dispatch` full: `{"n":20,"arches":["aarch64","armhf","armv7","x86_64"],"arm32_ok":true}` - 14 native (6 green + git = 7 lines x 2) + 6 32-bit (3 lines x 2); `arm32_ok:true` confirms every armv7/armhf combo is best-effort (`publish=true tier=full`). Also confirm 32-bit lines are only 22/23/22-cert: `... | jq -c '.include|map(select(.arch|test("arm"))|.line)|unique'` -> `["22","22-cert","23"]`.

- [ ] **Step 4: Lint the workflow**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); print('ci.yml OK')"
```

Expected: `ci.yml OK`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml
git commit --no-gpg-sign -m "Emit arch x line CI matrix and skip docs-only pushes

setup now outputs an include matrix with per-combo runner/platform/allow_fail:
native x86_64+aarch64 for every tier line, plus best-effort armv7/armhf for
22/23/22-cert on the full tier. paths-ignore stops docs/examples pushes from
triggering builds."
```

---

### Task 4: Build job consumes the arch matrix

Run each combo on its own runner, register QEMU only for emulated arches, build+test with `ARCH`, and upload per-arch artifacts.

**Files:**
- Modify: `.github/workflows/ci.yml` `build` job (lines 53-80)

**Interfaces:**
- Consumes: `needs.setup.outputs.matrix` (`matrix.line`, `matrix.arch`, `matrix.runner`, `matrix.platform`, `matrix.allow_fail`).
- Produces: artifacts named `apks-<arch>-<line>` containing `repository/v3.24/main/<arch>/*.apk`. Consumed by Task 5.

- [ ] **Step 1: Replace the `build` job**

Replace the whole `build:` job (lines 53-80) with:

```yaml
  build:
    needs: setup
    runs-on: ${{ matrix.runner }}
    continue-on-error: ${{ matrix.allow_fail }}
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.setup.outputs.matrix) }}
    env:
      ABUILD_PRIVATE_KEY: ${{ secrets.ABUILD_PRIVATE_KEY }}
      ABUILD_KEY_NAME: ${{ secrets.ABUILD_KEY_NAME }}
    steps:
      - uses: actions/checkout@v4
      - name: Set up QEMU (emulated arches only)
        if: matrix.platform != ''
        uses: docker/setup-qemu-action@v3
      - uses: docker/setup-buildx-action@v3
      - name: Install signing key
        run: ./scripts/ci-install-signing-key.sh
      - name: Make bind-mounted dirs writable by the container builder
        run: |
          mkdir -p repository/v3.24/main/${{ matrix.arch }}
          sudo chmod -R a+rwX packages repository keys
      - name: Build ${{ matrix.line }} (${{ matrix.arch }})
        run: make build-${{ matrix.line }} ARCH=${{ matrix.arch }}
      - name: Smoke test ${{ matrix.line }} (${{ matrix.arch }})
        run: make test-${{ matrix.line }} ARCH=${{ matrix.arch }}
      - name: Upload APKs
        uses: actions/upload-artifact@v4
        with:
          name: apks-${{ matrix.arch }}-${{ matrix.line }}
          path: repository/v3.24/main/${{ matrix.arch }}/*.apk
          if-no-files-found: error
```

- [ ] **Step 2: Lint the workflow**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); print('ci.yml OK')"
```

Expected: `ci.yml OK`.

- [ ] **Step 3: Review the emulated-arch path by hand**

Confirm: `matrix.platform != ''` gates the QEMU step (empty for native x86_64/aarch64, set for armv7/armhf); `runs-on` is `ubuntu-24.04-arm` for aarch64 combos and `ubuntu-latest` otherwise; artifact name and path both use `matrix.arch`. No automated run here - the real check is the PR run at the end.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit --no-gpg-sign -m "Build each arch x line combo on its own runner

runs-on/continue-on-error come from the matrix; QEMU binfmt is registered only
for emulated arches; build+test pass ARCH; artifacts are per-arch."
```

---

### Task 5: Publish job - per-arch indexes, shared canonical noarch, multi-arch site

Distribute per-arch artifacts, build one signed index per arch, and share a single canonical `noarch/` tree so every arch index references identical noarch checksums.

**Files:**
- Modify: `.github/workflows/ci.yml` `publish` job (lines 106-163)

**Interfaces:**
- Consumes: artifacts `apks-<arch>-<line>` (Task 4); `scripts/build-repo-index.sh` (reads `ARCH`, mirrors `A:noarch` files into `main/noarch/`).
- Produces: deployed `_site/v3.24/main/{x86_64,aarch64,armv7,armhf,noarch}/`.

- [ ] **Step 1: Replace the artifact-collect + index + assemble steps**

Replace the steps from `- name: Collect built APKs` through the `Assemble Pages site` step (lines 124-157) with:

```yaml
      - name: Collect built APKs
        uses: actions/download-artifact@v4
        with:
          pattern: apks-*
          path: _artifacts
      - name: Distribute APKs into per-arch repo dirs
        run: |
          for d in _artifacts/apks-*; do
            [ -d "$d" ] || continue
            arch=$(basename "$d" | cut -d- -f2)
            mkdir -p "repository/v3.24/main/$arch"
            cp "$d"/*.apk "repository/v3.24/main/$arch/"
          done
          echo "arches present: $(ls repository/v3.24/main)"
      - name: Make bind-mounted dirs writable by the container builder
        run: sudo chmod -R a+rwX repository keys
      - name: Build + sign per-arch APKINDEX (shared canonical noarch)
        run: |
          docker compose build builder-23
          for arch in x86_64 aarch64 armv7 armhf; do
            [ -d "repository/v3.24/main/$arch" ] || continue
            # x86_64 is indexed first and defines the canonical noarch set
            # (build-repo-index.sh mirrors A:noarch files into main/noarch/).
            # Overlay those canonical files into each later arch dir so every
            # index references identical noarch checksums; apk serves them from
            # the shared noarch/ path.
            if [ -d repository/v3.24/main/noarch ]; then
              cp -f repository/v3.24/main/noarch/*.apk "repository/v3.24/main/$arch/" 2>/dev/null || true
            fi
            docker compose run --rm -e ALPINE_VERSION=v3.24 -e ARCH="$arch" builder-23 \
              sh /home/builder/scripts/build-repo-index.sh
          done
      - name: Assemble Pages site
        run: |
          mkdir -p _site/v3.24/main
          for arch in x86_64 aarch64 armv7 armhf noarch; do
            [ -d "repository/v3.24/main/$arch" ] && cp -r "repository/v3.24/main/$arch" _site/v3.24/main/
          done
          cp "keys/${ABUILD_KEY_NAME:-packages@asterisk-alpine.rsa}.pub" _site/
          echo "apk.andrius.mobi" > _site/CNAME
          cat > _site/index.html <<'HTML'
          <!doctype html><meta charset=utf-8>
          <title>Asterisk Alpine APK repository</title>
          <h1>Asterisk Alpine APK repository</h1>
          <p>Signed apk packages for x86_64, aarch64, armv7, armhf. Add the key and repo:</p>
          <pre>wget -O /etc/apk/keys/packages@asterisk-alpine.rsa.pub \
            https://apk.andrius.mobi/packages@asterisk-alpine.rsa.pub
          echo "@andrius-asterisk https://apk.andrius.mobi/v3.24/main" >> /etc/apk/repositories
          apk add "asterisk@andrius-asterisk=~23"</pre>
          HTML
```

- [ ] **Step 2: Dry-run the distribute + canonical-overlay shell logic locally**

```bash
cd "$(mktemp -d)"
mkdir -p _artifacts/apks-x86_64-23 _artifacts/apks-aarch64-23 _artifacts/apks-x86_64-22-cert
touch _artifacts/apks-x86_64-23/asterisk-23.4.1-r0.apk _artifacts/apks-aarch64-23/asterisk-23.4.1-r0.apk _artifacts/apks-x86_64-22-cert/asterisk-22.8.0.3-r0.apk
for d in _artifacts/apks-*; do arch=$(basename "$d" | cut -d- -f2); mkdir -p "repository/v3.24/main/$arch"; cp "$d"/*.apk "repository/v3.24/main/$arch/"; done
ls repository/v3.24/main            # expect: aarch64  x86_64
ls repository/v3.24/main/x86_64     # expect both the 23 and 22-cert apks
```

Expected: arch is parsed correctly for both `x86_64`/`aarch64` and the dashed line `22-cert` (arch = `x86_64`).

- [ ] **Step 3: Lint the workflow**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); print('ci.yml OK')"
```

Expected: `ci.yml OK`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit --no-gpg-sign -m "Publish per-arch indexes with a shared canonical noarch tree

Distribute per-arch artifacts, index each arch, and overlay x86_64's noarch set
into every arch before indexing so all indexes agree on noarch checksums. Site
carries all arch dirs; index.html shows the @andrius-asterisk pin."
```

---

### Task 6: Rename the pin tag and document architectures

Rename `@astalpine` -> `@andrius-asterisk` everywhere it appears in docs, and add a short architectures note.

**Files:**
- Modify: `README.md`, `examples/README.md`, `examples/asterisk-23/Dockerfile`, `examples/asterisk-22-cert/Dockerfile`

- [ ] **Step 1: Replace every `@astalpine` occurrence**

In all four files, replace `@astalpine` with `@andrius-asterisk`. In `examples/README.md`, also change the prose `(any name; we use "astalpine")` to `(any name; we use "andrius-asterisk")`.

```bash
sed -i 's/@astalpine/@andrius-asterisk/g; s/"astalpine"/"andrius-asterisk"/g' \
  README.md examples/README.md examples/asterisk-23/Dockerfile examples/asterisk-22-cert/Dockerfile
```

- [ ] **Step 2: Add an "Architectures" note to `README.md`**

After the "Available lines" paragraph (around line 11), add:

```markdown

**Architectures:** x86_64, aarch64 (Apple Silicon / RPi 4-5 / Graviton), and
armv7 / armhf (32-bit Raspberry Pi). The same repo line works everywhere - apk
resolves packages for the running architecture automatically.
```

- [ ] **Step 3: Verify no stale tag remains and examples still build**

```bash
grep -rn 'astalpine' README.md docs examples .github ; echo "grep exit: $?"
docker build --no-cache -t ex23 examples/asterisk-23 && docker run --rm ex23 asterisk -V
```

Expected: `grep` prints nothing and reports `grep exit: 1` (no matches); the image builds and prints `Asterisk 23.4.1` (the tag rename resolves against the live repo).

- [ ] **Step 4: Commit**

```bash
git add README.md examples
git commit --no-gpg-sign -m "Rename pin tag to @andrius-asterisk and note architectures

Brand the repository pin tag and document x86_64/aarch64/armv7/armhf coverage."
```

---

### Task 7: Record arch coverage

Document the arch x line coverage next to the version matrix and in the roadmap.

**Files:**
- Modify: `buildchain/versions.mk` (append an arch-coverage comment block), `ROADMAP.md` (add a section)

- [ ] **Step 1: Append an arch-coverage block to `buildchain/versions.mk`**

At the end of the file add:

```makefile

# ---- ARCHITECTURE COVERAGE (see docs/multi-arch-buildchain-design.md) ----
# native  x86_64, aarch64 : every target line (modern on PR/push, full on tag)
# 32-bit  armv7,  armhf   : 22, 23 (targets) + 22-cert (best-effort), full tier
#                           only, continue-on-error. Line 20 and ancient lines
#                           are x86_64/aarch64 only.
```

- [ ] **Step 2: Add a "Multi-architecture" section to `ROADMAP.md`**

Append this section to `ROADMAP.md`:

```markdown
## Multi-architecture coverage

Packages are published for four Alpine arches from one repository; apk resolves
the running arch automatically.

| Arch | Build | Lines | When |
|---|---|---|---|
| x86_64  | native (`ubuntu-latest`)     | all target lines | modern on PR/push, full on tag |
| aarch64 | native (`ubuntu-24.04-arm`)  | all target lines | modern on PR/push, full on tag |
| armv7   | QEMU (`linux/arm/v7`)        | 22, 23 (+22-cert best-effort) | full tier only, continue-on-error |
| armhf   | QEMU (`linux/arm/v6`)        | 22, 23 (+22-cert best-effort) | full tier only, continue-on-error |

Arch-independent packages (sample-config, doc, sounds, openrc) are published
once under a shared `v3.24/main/noarch/` tree referenced by every arch index.
See `docs/multi-arch-buildchain-design.md`.
```

- [ ] **Step 3: Verify the matrix listing still parses**

```bash
make list
```

Expected: prints the version matrix without error (the appended comment block is ignored by the `list` parser, which skips comment lines).

- [ ] **Step 4: Commit**

```bash
git add buildchain/versions.mk ROADMAP.md
git commit --no-gpg-sign -m "Document multi-arch coverage in versions.mk and ROADMAP"
```

---

## Post-implementation validation (whole branch)

After all tasks: push the branch and open a PR. The PR run exercises only the **modern native** matrix (x86_64 + aarch64, no publish) - the first real proof aarch64 builds. To exercise 32-bit before merge, trigger `workflow_dispatch` with tier `full` on the branch and watch the armv7/armhf best-effort combos. On merge to `main`, the publish job deploys the multi-arch site; verify:

```bash
for a in x86_64 aarch64; do
  curl -s -o /dev/null -w "%{http_code} $a\n" "https://apk.andrius.mobi/v3.24/main/$a/APKINDEX.tar.gz"
done
docker run --rm --platform linux/arm64 alpine:3.24 sh -c '
  wget -qO /etc/apk/keys/packages@asterisk-alpine.rsa.pub https://apk.andrius.mobi/packages@asterisk-alpine.rsa.pub
  echo "@andrius-asterisk https://apk.andrius.mobi/v3.24/main" >> /etc/apk/repositories
  apk add --no-cache "asterisk@andrius-asterisk=~23" "asterisk-sample-config@andrius-asterisk=~23" && asterisk -V'
```

Expected: both native indexes return `200`; the aarch64 container installs asterisk 23 and prints its version.

**Known risk:** if the full daemon smoke test proves unreliable under QEMU for armv7/armhf, the mitigation is already in place - those combos already run `SMOKE_LEVEL=version` (Task 2) and are `continue-on-error`, so a flaky daemon never blocks the release and never publishes a broken combo.
