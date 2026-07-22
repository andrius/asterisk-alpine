# Alpine Linux package builder for Asterisk
# This container provides a complete build environment for creating APK packages.
# Parameterized by ALPINE_VERSION so the same template serves every line of the
# build matrix. Every line now builds on the single 3.24 base (the "failure
# frontier" approach - see ROADMAP §1), with edge as a canary; the parameter
# remains so a different base can be tried without editing this file.
#
# Keep this default in step with the Makefile's ALPINE_VERSION. Compose passes
# the value explicitly for all builder services, so this only applies to a bare
# `docker build` - which is exactly where a stale default goes unnoticed.
ARG ALPINE_VERSION=3.24
FROM alpine:${ALPINE_VERSION}

# Install build tools and dependencies
RUN apk add --no-cache \
    alpine-sdk \
    sudo \
    abuild \
    && mkdir -p /var/cache/distfiles \
    && chmod a+w /var/cache/distfiles \
    # abuild 3.17+ (Alpine 3.24) enables an apk cache mode that requires
    # /etc/apk/cache to exist, else builddeps fail with
    # "opening from cache ... No such file or directory" / "masked in: cache".
    && mkdir -p /etc/apk/cache

# Create builder user (required by abuild - won't build as root)
RUN adduser -D -G abuild builder \
    && echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Set up abuild directories
RUN mkdir -p /home/builder/packages \
    && chown -R builder:abuild /home/builder

# Switch to builder user
USER builder
WORKDIR /home/builder

# Create abuild config
RUN mkdir -p ~/.abuild

# Set default package destination
ENV PACKAGER_PRIVKEY="/home/builder/.abuild/packages@asterisk-alpine.rsa"
# abuild writes packages to $REPODEST/$repo/$arch/ where $repo is the parent
# dir name of the APKBUILD. We mount the APKBUILD tree at /home/builder/main/
# asterisk so $repo=main. REPODEST versions the output: <repo>/v3.24/main/<arch>/.
# Override at runtime for other Alpine bases: -e REPODEST=/home/builder/packages/edge
ENV REPODEST="/home/builder/packages/v3.24"

# The APKBUILD tree is mounted at /home/builder/main/asterisk (so abuild sees
# $repo=main), not /home/builder/asterisk - the latter path no longer exists in
# any builder service.
VOLUME ["/home/builder/main/asterisk", "/home/builder/packages", "/home/builder/.abuild"]

CMD ["/bin/sh"]
