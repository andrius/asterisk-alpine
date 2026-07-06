---
name: github-actions-buildchain
status: approved
created: 2026-07-06T15:40:00Z
updated: 2026-07-06T15:40:00Z
---

# GitHub Actions Buildchain → Signed APK Repo on GitHub Pages

## Goal

On push and tag, GitHub Actions builds the green Asterisk lines as signed Alpine
APKs, smoke-tests each, assembles one signed repository, and publishes it to
**GitHub Pages**. x86_64 first. Cloudsmith publishing and aarch64 are later phases.

Success criteria:

- Push/PR to `main` builds + smoke-tests the modern tier and reports pass/fail.
- Push-to-`main`/tag publishes a signed repo to Pages that a clean Alpine box can
  `apk add asterisk` from, using only the published public key + the repo URL.
- Documented-fail lines (13, 14) run without failing the whole workflow, so a
  change in the failure frontier is visible.

## Non-goals (later phases, per ROADMAP M5/M6)

- aarch64 (buildx + QEMU binfmt).
- Cloudsmith publish (secret staged now; step added once OSS hosting is approved).
- Upstream-release auto-bump (poll → PR to `versions.mk`).

## Secrets (delivered via `gh secret set`, repo `andrius/asterisk-alpine`)

| Secret | Value | Purpose |
|---|---|---|
| `ABUILD_PRIVATE_KEY` | contents of `keys/packages@asterisk-alpine.rsa` | sign the APKINDEX in CI |
| `ABUILD_KEY_NAME` | `packages@asterisk-alpine.rsa` | key name in `~/.abuild` + `/etc/apk/keys` |
| `CLOUDSMITH_API_KEY` | `csa_…` (from `.ak-secrets.md`) | staged for later Cloudsmith publish; unused now |

- The **public** key (`.rsa.pub`) is not secret. CI derives it from the private
  secret and publishes it; nothing about the private key is committed to git.
- Fork PRs do not receive secrets → PR builds run **unsigned** (build + test only).

## Workflows (`.github/workflows/`)

### `build.yml` - matrix build + smoke test

- Triggers:
  - `push` / `pull_request` on `main` → **modern tier**: 20, 22, 22-cert, 23.
  - `workflow_dispatch` and tag `v*` → **full tier**: + 18, 17, 16, 15.
  - Lines 13, 14 run as `continue-on-error` **frontier watchers**.
- Per matrix leg (`ubuntu-latest`, GitHub-hosted):
  1. checkout
  2. set up Docker buildx
  3. restore signing key from `ABUILD_PRIVATE_KEY` into `~/.abuild` (skipped on fork PRs)
  4. `make build-<line>`
  5. `make test-<line>`
  6. upload that line's APKs as a build artifact

### `publish.yml` - assemble, sign, deploy to Pages

- Runs only on push-to-`main` / tag (never on PRs).
- Steps: download all APK artifacts → assemble `repository/v3.24/main/x86_64/` →
  `make repo-index` (signs the index with the restored key) →
  `actions/upload-pages-artifact` → `actions/deploy-pages`.
- Pages is deployed from the workflow artifact (not a committed `gh-pages`
  branch), so the ~141 APKs never enter git history.

## User-facing result

- Repo URL: `https://andrius.github.io/asterisk-alpine/v3.24/main`
- Install:
  ```sh
  wget -O /etc/apk/keys/packages@asterisk-alpine.rsa.pub \
    https://andrius.github.io/asterisk-alpine/packages@asterisk-alpine.rsa.pub
  echo "https://andrius.github.io/asterisk-alpine/v3.24/main" >> /etc/apk/repositories
  apk update && apk add asterisk
  ```

## Makefile changes this requires

- Add `build-15`, `build-16`, `build-17`, `build-18`, `build-22-cert` targets
  (today only `build-20/22/23` exist) so CI calls `make build-<line>` uniformly.
- Key setup: consume a key from env/secret in CI instead of only generating one
  (`init-keys` currently generates). Add a path that installs `ABUILD_PRIVATE_KEY`.
- Add a `build-full` tier helper (`build-modern` already exists).

## Constraints / accepted risks

- GitHub Pages: soft 100 GB/month bandwidth, not a true CDN. Accepted for now;
  can front with Cloudflare later.
- Build cost: 8 lines × ~30-60 min each, parallelized by matrix. GitHub-hosted
  minutes are free for public repos.
- Signing key in CI: stored as a GitHub Secret. Fork PRs cannot read it, so they
  build unsigned. Rotating the key means updating the secret + republishing pubkey.

## Testing

- Reuse existing `make test-<line>` smoke tests in CI (install from repo →
  `asterisk -V` → daemon runs → modules load). Build-green must also test-green.
- Infra (workflow YAML, Dockerfiles, shell) is TDD-exempt per project policy;
  validated via dry-runs, `act`/manual dispatch, and review.
