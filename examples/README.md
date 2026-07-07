# Examples

Ready-to-build Docker images that install Asterisk from
[`https://apk.andrius.mobi`](https://apk.andrius.mobi/).

| Example | Asterisk | Version |
|---|---|---|
| [`asterisk-23/`](asterisk-23/) | 23 (current) | 23.4.x |
| [`asterisk-22-cert/`](asterisk-22-cert/) | 22 certified | 22.8.0.x |

```bash
docker build -t asterisk-23 examples/asterisk-23
docker run --rm -it asterisk-23        # foreground console
```

## Avoiding conflicts with Alpine's asterisk

Alpine Linux ships its **own** `asterisk` package in the always-enabled `main`
repository (Alpine 3.24 = `asterisk-22.9.0`). Because our packages use the same
names, apk sees several candidates for `asterisk` at once:

```
20.20.1-r0   @astalpine   (this repo)
22.8.0.3-r0  @astalpine   (this repo - certified)
22.9.0-r0    main         (Alpine)
22.10.1-r0   @astalpine   (this repo - LTS)
23.4.1-r0    @astalpine   (this repo)
```

Without pinning, `apk add asterisk` just picks the highest version, and a later
`apk upgrade` can silently swap our build for Alpine's (or vice versa) whenever
the version ordering changes. That is rarely what you want.

The fix is Alpine's built-in [repository pinning](https://wiki.alpinelinux.org/wiki/Repository_pinning):
give our repo a **tag** and reference it explicitly.

```sh
# 1. tag the repo (any name; we use "astalpine")
echo "@astalpine https://apk.andrius.mobi/v3.24/main" >> /etc/apk/repositories

# 2. install with the tag -> apk can only take asterisk from our repo
apk add "asterisk@astalpine=~23"       # 23.x  (current)
apk add "asterisk@astalpine=~22"       # 22.x  (LTS 22.10)
apk add "asterisk@astalpine=~22.8"     # 22.8  (certified)
apk add "asterisk@astalpine=~20"       # 20.x
```

Two things are pinned here:

- **`@astalpine`** - the *repository*. A tagged repo is never used implicitly, so
  apk won't pull our `asterisk` unless you ask for `@astalpine`, and won't
  upgrade across the tag. Tag any subpackages the same way
  (`asterisk-opus@astalpine`), since those names collide too.
- **`=~<version>`** - the *line*. `=~22.8` fuzzy-matches only the `22.8` line, so
  the certified build is chosen over both the `22.10` LTS in this repo and
  Alpine's `22.9`. For `20` and `23` there is no Alpine equivalent, but pinning
  the repo is still the safe habit.

If you don't need Alpine's own asterisk at all, pinning is still the recommended
approach - it keeps upgrades deterministic.
