# Test image: installs a built asterisk version from our repo, starts it,
# and verifies it runs + reports the right version + loads key modules.
# Build args:
#   ASTERISK_VERSION  e.g. 22.10.1   (must match a pkgver in the repo)
#   ALPINE_VERSION    e.g. 3.24
ARG ALPINE_VERSION=3.24
FROM alpine:${ALPINE_VERSION}

ARG ASTERISK_VERSION=22.10.1
ENV ASTERISK_VERSION=${ASTERISK_VERSION}

# Install asterisk from our local repo (mounted at /repo at test time).
# The public key is mounted at /keys. We do the install in an entrypoint so
# the same image can be reused across versions; the version is baked in.
# /etc/apk/cache must exist on Alpine 3.24 (apk 3.0) or repo resolution fails.
RUN mkdir -p /etc/apk/cache \
    && apk add --no-cache \
        ca-certificates \
        util-linux \
    && addgroup -S asterisk 2>/dev/null \
    && adduser -S -D -h /var/lib/asterisk -s /sbin/nologin -G asterisk asterisk 2>/dev/null \
    || true

# The test runner: install, configure, start, probe, report.
COPY scripts/test-run.sh /usr/local/bin/test-run.sh
RUN chmod +x /usr/local/bin/test-run.sh

ENTRYPOINT ["/usr/local/bin/test-run.sh"]
