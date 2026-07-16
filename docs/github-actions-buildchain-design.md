---
name: github-actions-buildchain
status: approved
created: 2026-07-06T15:40:00Z
updated: 2026-07-16T13:14:27Z
---

# GitHub Actions Buildchain → Signed APK Repo on GitHub Pages

> **Superseded (2026-07): publish + hosting target changed.** This document
> describes the original **GitHub Pages** apk repository (`apk.andrius.mobi`).
> Publishing has since moved to **Cloudsmith** (`asterisk/alpine`); GitHub Pages and
> the `apk.andrius.mobi` domain are retired. The build + CI design below still holds -
> only the publish + hosting target changed (Cloudsmith owns indexing + signing, so
> there is no APKINDEX build or Pages deploy in CI). Current source of truth: the
> [README](../README.md) and `.github/workflows/_publish.yml`; rationale in the KB
> decision "apk hosting on Cloudsmith Open-Source, not GitHub Pages" (2026-07-16).
> Retained as a historical design record.

## Goal

On push and tag, GitHub Actions builds the green Asterisk lines as signed Alpine
APKs, smoke-tests each, assembles one signed repository, and publishes it to
**GitHub Pages**. x86_64 first. Cloudsmith publishing and aarch64 are later phases.

Success criteria:

- Push/PR to `main` builds + smoke-tests the modern tier and reports pass/fail.
- Push-to-`main`/tag publishes a signed repo to Pages that a clean Alpine box can
  `apk add asterisk` from, using only the published public key + the repo URL.
- Documented-fail line 14 runs without failing the whole workflow, so a
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
  - `workflow_dispatch` and tag `v*` → **full tier**: + 18, 16, git (best-effort); ancient 1.6/1.8 and frontier 14 also full-tier/best-effort.
  - Line 14 runs as a `continue-on-error` **frontier watcher**.
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

### Publish matrix and tag deploys

- `v*` tags publish the full matrix to apk.andrius.mobi. The `setup.pick`
  step routes tag pushes to the `full` tier with `publish=true`, so every
  green line is built and the publish job assembles the complete signed
  repository.
- The `github-pages` environment's deployment-branch-policy MUST list both
  `main` (branch type) and `v*` (tag type). Restricting to main-only breaks
  tag deploys because the environment gate rejects non-matching refs. This
  is a required repo setting, not code.
- Every line publishes on full / tag / dispatch runs: 23, 22, 22-cert, 20,
  18, 16, git, ancient 1.6/1.8, and frontier 14 (if the build passes).
  Frontier 14 is best-effort: its build step has no step-level
  `continue-on-error`, so on failure the upload step does not run and no
  14 artifact reaches publish.
- Merge-with-live seed is preserved: the publish job downloads the existing
  live repo index and fills in any arch/line not rebuilt this run, so a
  partial build never wipes an existing package.
- `apk index` prints "Total of N unsatisfiable package names" while building
  the index - this is expected and harmless. The repo ships only Asterisk
  packages, so the system libraries they link against (musl, openssl,
  pjproject, spandsp, etc.) are absent from the indexed set and resolve from
  Alpine main/community at install time. A clean `alpine:3.24` container
  installing `asterisk@andrius-asterisk` from the live repo completes with
  zero resolver errors.

### Edge canary (not published)

`build-edge.yml` builds + smoke-tests the newest lines - LTS 22, dev 23, git
(master) - on **Alpine `edge`** for x86_64 + aarch64, weekly (Mon ~04:43 UTC) +
on dispatch. It is a **canary**: `allow_fail: true`, and **not published** -
artifacts land in `repository/edge/` on the runner only; apk.andrius.mobi serves
only the `v3.24` registry.

The build/test path is parameterized by Alpine version (`ALPINE` / `ALPINE_SUFFIX`
/ `ALPINE_TAG` in the Makefile, `_build.yml` `alpine_version` input, the
`-e REPODEST=/home/builder/packages/$ALPINE_VERSION` runtime override on the
build run, and `builder-{22,23,git}-edge` compose services) so edge reuses the
same `_build.yml` as 3.24. (Gotcha: abuild's `REPODEST` is the `builder.Dockerfile`
`ENV`, not `abuild.conf` - hence the runtime `-e REPODEST` override.)

**Why canary-only:** apk pins deps to ABI-stable sonames (`so:libc.musl-x86_64.so.1`,
`so:libssl.so.3`, …) that Alpine keeps stable across versions, so the v3.24 APKs
install + run on edge - edge users use the v3.24 repo. A published `/edge`
registry would be volatile (edge rolls daily) and extra to sign + maintain. Flip
to publishing `/edge` only if the canary shows v3.24 APKs failing on edge (ABI drift).

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

- Add `build-16`, `build-18`, `build-22-cert`, `build-git`, `build-1.6`, `build-1.8` targets
  (today only `build-20/22/23` exist) so CI calls `make build-<line>` uniformly.
- Key setup: consume a key from env/secret in CI instead of only generating one
  (`init-keys` currently generates). Add a path that installs `ABUILD_PRIVATE_KEY`.
- Add a `build-full` tier helper (`build-modern` already exists).

## Constraints / accepted risks

- GitHub Pages: soft 100 GB/month bandwidth, not a true CDN. Accepted for now;
  can front with Cloudflare later.
- Build cost: 6 green + git (7 native lines) × ~30-60 min each, parallelized by matrix. GitHub-hosted
  minutes are free for public repos.
- Signing key in CI: stored as a GitHub Secret. Fork PRs cannot read it, so they
  build unsigned. Rotating the key means updating the secret + republishing pubkey.

## Testing

- Reuse existing `make test-<line>` smoke tests in CI (install from repo →
  `asterisk -V` → daemon runs → modules load). Build-green must also test-green.
- Infra (workflow YAML, Dockerfiles, shell) is TDD-exempt per project policy;
  validated via dry-runs, `act`/manual dispatch, and review.
