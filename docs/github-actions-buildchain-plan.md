# GitHub Actions Buildchain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On push/tag, GitHub Actions builds the green Asterisk lines as signed Alpine APKs, smoke-tests each, and publishes one signed repo to GitHub Pages.

**Architecture:** One workflow `.github/workflows/ci.yml` with three jobs: `setup` (picks the tier + publish flag from the trigger), `build` (matrix over Asterisk lines, each running the existing `make build-<line>` + `make test-<line>` in the existing Docker builders, uploading APKs as artifacts), and `publish` (downloads all artifacts, signs the index in the builder container, deploys to Pages). Signing key comes from the `ABUILD_PRIVATE_KEY` secret via a new `scripts/ci-install-signing-key.sh`; fork PRs get an ephemeral throwaway key and never publish.

**Tech Stack:** GitHub Actions, Docker Compose (existing builders), abuild/apk (Alpine), GitHub Pages (artifact deploy).

## Global Constraints

- Single Alpine base `3.24`; repo output path `repository/v3.24/main/x86_64/`; `ALPINE_VERSION=v3.24`, `ARCH=x86_64`.
- Signing key name: `packages@asterisk-alpine.rsa` (secret `ABUILD_KEY_NAME`). Private key from secret `ABUILD_PRIVATE_KEY`; public key derived, never committed.
- Green lines (build + test): `23, 22, 22-cert, 20, 18, 16, git`, plus ancient `1.6, 1.8` and frontier `14`. Modern subset (push/PR): `20, 22, 22-cert, 23`. Full (tag/dispatch): all current lines. (15/17/13 were later dropped; git, 1.6, 1.8 added.)
- Frontier watcher `14`: `continue-on-error`, never blocks the run, never published.
- Infra is TDD-exempt (project policy): validate via `make` locally, `workflow_dispatch`, and review - not red-green unit tests.
- Publish only on push-to-`main` / tag `v*`; never on pull_request. Pages deploy via artifact (no `gh-pages` branch).
- No AI attribution in commits; `git commit --no-gpg-sign`.

---

### Task 1: Makefile - per-line build targets + full tier

**Files:**
- Modify: `Makefile` (add targets alongside existing `build-22`/`build-23`)

**Interfaces:**
- Produces: `make build-16`, `make build-18`, `make build-22-cert`, `make build-git`, `make build-1.6`, `make build-1.8`, `make build-full` - each mirrors the existing `build-22` recipe (compose build + run `build.sh` + `repo-index-22`). CI calls `make build-<line>`.

- [ ] **Step 1: Add the missing per-line build targets**

In `Makefile`, after the existing `build-23` block (~line 88), add (mirrors `build-22` exactly, swapping the service name):

```makefile
# --- Legacy green lines 16, 18 + 22-cert on Alpine 3.24 ---
build-18 build-16 build-22-cert: init-keys
	@echo "Building Asterisk line $(@:build-%=%) on Alpine 3.24..."
	@chmod +x scripts/build.sh scripts/build-repo-index.sh
	docker compose build builder-$(@:build-%=%)
	docker compose run --rm builder-$(@:build-%=%) sh /home/builder/scripts/build.sh
	@$(MAKE) --no-print-directory repo-index-22
	@echo "✅ line $(@:build-%=%) packages built"

shell-18 shell-16 shell-22-cert:
	docker compose run --rm builder-$(@:shell-%=%) /bin/sh
# Note: build-git, build-1.6, build-1.8 each have their own dedicated recipe.
```

- [ ] **Step 2: Add the `build-full` tier and update `build-all`**

Replace the existing `build-modern` / `build-all` block (~lines 94-98) with:

```makefile
# --- Tier groupings ---
build-modern: build-20 build-22 build-22-cert build-23
build-full:   build-23 build-22 build-22-cert build-20 build-18 build-16 build-git
build-all:    build-full
```

- [ ] **Step 3: Update `.PHONY`**

Add the new targets to the `.PHONY` lines at the top of `Makefile`:

```makefile
.PHONY: build-16 build-18 build-22-cert build-git build-1.6 build-1.8 build-full
.PHONY: shell-16 shell-18 shell-22-cert
```

- [ ] **Step 4: Validate locally (one fast line)**

Run: `make build-16`
Expected: builder-16 image builds, `build.sh` runs `abuild -r`, ends with "✅ line 16 packages built"; APKs appear in `repository/v3.24/main/x86_64/`.

- [ ] **Step 5: Commit**

```bash
git add Makefile
git commit --no-gpg-sign -m "Add build targets for 16/18/22-cert and build-full tier"
```

---

### Task 2: CI signing-key installer script

**Files:**
- Create: `scripts/ci-install-signing-key.sh`

**Interfaces:**
- Consumes env: `ABUILD_PRIVATE_KEY` (PEM, may be empty on fork PRs), `ABUILD_KEY_NAME` (default `packages@asterisk-alpine.rsa`).
- Produces host files: `keys/<name>.rsa` (600), `keys/<name>.rsa.pub` (644), `keys/abuild.conf`. Consumed by the existing Docker builders (they mount `./keys` at `/home/builder/.abuild`).

- [ ] **Step 1: Write the script**

```sh
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
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/ci-install-signing-key.sh`

- [ ] **Step 3: Validate locally with the real key**

Run:
```bash
ABUILD_PRIVATE_KEY="$(cat keys/packages@asterisk-alpine.rsa)" \
  ABUILD_KEY_NAME=packages@asterisk-alpine.rsa \
  ./scripts/ci-install-signing-key.sh
openssl rsa -in keys/packages@asterisk-alpine.rsa -check -noout
```
Expected: "Signing key ready…"; `RSA key ok`. (The real key is re-written identically; `abuild.conf` present.)

- [ ] **Step 4: Validate the ephemeral path**

Run: `env -u ABUILD_PRIVATE_KEY ABUILD_KEY_NAME=throwaway.rsa ./scripts/ci-install-signing-key.sh && ls keys/throwaway.rsa* && rm keys/throwaway.rsa*`
Expected: ephemeral key generated, both files listed, then cleaned up.

- [ ] **Step 5: Commit**

```bash
git add scripts/ci-install-signing-key.sh
git commit --no-gpg-sign -m "Add CI signing-key installer script"
```

---

### Task 3: CI workflow - setup + build matrix

**Files:**
- Create: `.github/workflows/ci.yml` (setup + build jobs; publish job added in Task 4)

**Interfaces:**
- Consumes: `make build-<line>`, `make test-<line>` (Tasks 1 + existing), `scripts/ci-install-signing-key.sh` (Task 2), secrets `ABUILD_PRIVATE_KEY`/`ABUILD_KEY_NAME`.
- Produces: artifacts `apks-<line>` (the `.apk` files), job outputs `setup.matrix` and `setup.publish` consumed by Task 4.

- [ ] **Step 1: Write the workflow (setup + build)**

```yaml
name: build-and-publish

on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
    branches: [main]
  workflow_dispatch:
    inputs:
      tier:
        description: Tier to build
        type: choice
        options: [modern, full]
        default: full

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  setup:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.pick.outputs.matrix }}
      publish: ${{ steps.pick.outputs.publish }}
    steps:
      - id: pick
        run: |
          MODERN='["20","22","22-cert","23"]'
          FULL='["23","22","22-cert","20","18","16"]'
          # git, 1.6, 1.8 are added as separate best-effort/ancient matrix entries in the actual ci.yml.
          EVENT='${{ github.event_name }}'
          TIER='${{ github.event.inputs.tier }}'
          if [ "$EVENT" = "pull_request" ]; then
            LINES="$MODERN"; PUBLISH=false
          elif [ "$EVENT" = "push" ] && [ "${{ github.ref }}" = "refs/heads/main" ]; then
            LINES="$MODERN"; PUBLISH=true
          elif [ "$EVENT" = "workflow_dispatch" ] && [ "$TIER" = "modern" ]; then
            LINES="$MODERN"; PUBLISH=true
          else
            LINES="$FULL"; PUBLISH=true
          fi
          echo "matrix={\"line\":$LINES}" >> "$GITHUB_OUTPUT"
          echo "publish=$PUBLISH" >> "$GITHUB_OUTPUT"

  build:
    needs: setup
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.setup.outputs.matrix) }}
    env:
      ABUILD_PRIVATE_KEY: ${{ secrets.ABUILD_PRIVATE_KEY }}
      ABUILD_KEY_NAME: ${{ secrets.ABUILD_KEY_NAME }}
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - name: Install signing key
        run: ./scripts/ci-install-signing-key.sh
      - name: Build ${{ matrix.line }}
        run: make build-${{ matrix.line }}
      - name: Smoke test ${{ matrix.line }}
        run: make test-${{ matrix.line }}
      - name: Upload APKs
        uses: actions/upload-artifact@v4
        with:
          name: apks-${{ matrix.line }}
          path: repository/v3.24/main/x86_64/*.apk
          if-no-files-found: error
```

- [ ] **Step 2: Add the frontier-watcher job (14)**

Append this job (runs only on tag/dispatch full builds; never blocks):

```yaml
  frontier:
    needs: setup
    if: needs.setup.outputs.publish == 'true' && github.event_name != 'push'
    runs-on: ubuntu-latest
    continue-on-error: true
    strategy:
      fail-fast: false
      matrix:
        line: ["14"]
    env:
      ABUILD_PRIVATE_KEY: ${{ secrets.ABUILD_PRIVATE_KEY }}
      ABUILD_KEY_NAME: ${{ secrets.ABUILD_KEY_NAME }}
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - name: Install signing key
        run: ./scripts/ci-install-signing-key.sh
      - name: Attempt build ${{ matrix.line }} (expected to fail)
        run: make build-${{ matrix.line }}
```

- [ ] **Step 3: Lint the YAML**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo OK`
Expected: `OK` (valid YAML).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit --no-gpg-sign -m "Add CI workflow: tier setup + build/test matrix"
```

---

### Task 4: CI workflow - publish job (sign + Pages)

**Files:**
- Modify: `.github/workflows/ci.yml` (add `publish` job)

**Interfaces:**
- Consumes: `setup.publish`, artifacts `apks-*` from Task 3, `scripts/ci-install-signing-key.sh`, `scripts/build-repo-index.sh` (existing), builder-23 compose service.
- Produces: a deployed GitHub Pages site serving `v3.24/main/x86_64/` + the public key.

- [ ] **Step 1: Add the publish job**

Append to `.github/workflows/ci.yml`:

```yaml
  publish:
    needs: [setup, build]
    if: needs.setup.outputs.publish == 'true'
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deploy.outputs.page_url }}
    env:
      ABUILD_PRIVATE_KEY: ${{ secrets.ABUILD_PRIVATE_KEY }}
      ABUILD_KEY_NAME: ${{ secrets.ABUILD_KEY_NAME }}
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: actions/configure-pages@v5
        with:
          enablement: true
      - name: Install signing key
        run: ./scripts/ci-install-signing-key.sh
      - name: Collect built APKs
        uses: actions/download-artifact@v4
        with:
          pattern: apks-*
          merge-multiple: true
          path: repository/v3.24/main/x86_64
      - name: Build + sign the APKINDEX
        run: |
          docker compose build builder-23
          ALPINE_VERSION=v3.24 docker compose run --rm builder-23 \
            sh /home/builder/scripts/build-repo-index.sh
      - name: Assemble Pages site
        run: |
          mkdir -p _site/v3.24/main
          cp -r repository/v3.24/main/x86_64 _site/v3.24/main/
          cp "keys/${ABUILD_KEY_NAME:-packages@asterisk-alpine.rsa}.pub" _site/
          cat > _site/index.html <<'HTML'
          <!doctype html><meta charset=utf-8>
          <title>Asterisk Alpine APK repository</title>
          <h1>Asterisk Alpine APK repository</h1>
          <p>Add the key and repo, then <code>apk add asterisk</code>:</p>
          <pre>wget -O /etc/apk/keys/packages@asterisk-alpine.rsa.pub \
            https://andrius.github.io/asterisk-alpine/packages@asterisk-alpine.rsa.pub
          echo "https://andrius.github.io/asterisk-alpine/v3.24/main" >> /etc/apk/repositories
          apk update &amp;&amp; apk add asterisk</pre>
          HTML
      - uses: actions/upload-pages-artifact@v3
        with:
          path: _site
      - id: deploy
        uses: actions/deploy-pages@v4
```

- [ ] **Step 2: Lint the YAML again**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit --no-gpg-sign -m "Add CI publish job: sign index and deploy repo to Pages"
```

---

### Task 5: README install instructions

**Files:**
- Modify: `README.md` (the "Using Your Custom Repository" section, ~lines 160-178)

**Interfaces:** none (docs only).

- [ ] **Step 1: Replace the local-server install block with the Pages URL**

In `README.md`, under "### Add Repository to Alpine System", replace the placeholder `http://your-server/...` instructions with:

```markdown
1. Trust the repository public key:
   ```bash
   wget -O /etc/apk/keys/packages@asterisk-alpine.rsa.pub \
     https://andrius.github.io/asterisk-alpine/packages@asterisk-alpine.rsa.pub
   ```
2. Add the repository:
   ```bash
   echo "https://andrius.github.io/asterisk-alpine/v3.24/main" >> /etc/apk/repositories
   ```
3. Install (pin a major by version, e.g. Asterisk 20):
   ```bash
   apk update
   apk add "asterisk=~20"
   ```
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit --no-gpg-sign -m "Document GitHub Pages apk repository install"
```

---

### Task 6: End-to-end validation

**Files:** none (validation only).

- [ ] **Step 1: Push the branch and open the run**

```bash
git push origin main
```
Expected: `push` triggers the workflow; `setup` picks the modern tier + `publish=true`.

- [ ] **Step 2: Watch the run**

Run: `gh run watch $(gh run list --workflow=ci.yml -L1 --json databaseId -q '.[0].databaseId')`
Expected: `build` matrix (20/22/22-cert/23) green; `publish` deploys Pages.

- [ ] **Step 3: Verify the published repo installs on clean Alpine**

Run:
```bash
docker run --rm alpine:3.24 sh -c '
  wget -qO /etc/apk/keys/packages@asterisk-alpine.rsa.pub \
    https://andrius.github.io/asterisk-alpine/packages@asterisk-alpine.rsa.pub &&
  echo "https://andrius.github.io/asterisk-alpine/v3.24/main" >> /etc/apk/repositories &&
  apk update && apk add "asterisk=~20" && asterisk -V'
```
Expected: `apk` verifies the signed index with the trusted key, installs, prints `Asterisk 20.x`.

- [ ] **Step 4: Exercise the full tier once**

Run: `gh workflow run ci.yml -f tier=full` then watch.
Expected: 6 green lines (23/22/22-cert/20/18/16) build+test, plus `git` (best-effort) and `frontier` (line 14, best-effort); none of the best-effort failures fail the run.

---

## Notes / risks to watch during validation

- **Runner uid vs container `builder` uid:** `keys/` is written on the host and mounted into the builder. If abuild can't read the key (permission), add `chmod -R a+rX keys` in the install script or align uid. Validate in Task 3 Step 1's first run.
- **Build time:** 6 green + git (7 native lines) × ~30-60 min, parallel by matrix. Consider `docker/build-push-action` layer caching later if runners are slow.
- **`test-<line>` in CI:** the smoke tests start the daemon in a container; ensure the runner's Docker allows it (it does on `ubuntu-latest`). If a noarch subpackage path issue appears, it's the known `.ai-local.md` caveat - install by direct `.apk` path.
- **Pages first deploy:** `configure-pages@v5` with `enablement: true` turns Pages on; the first `deploy-pages` may take a minute to provision the domain.
