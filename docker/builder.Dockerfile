# Alpine Linux package builder for Asterisk
# This container provides a complete build environment for creating APK packages
FROM alpine:3.22

# Install build tools and dependencies
RUN apk add --no-cache \
    alpine-sdk \
    sudo \
    abuild \
    && mkdir -p /var/cache/distfiles \
    && chmod a+w /var/cache/distfiles

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
ENV REPODEST="/home/builder/packages"

VOLUME ["/home/builder/asterisk", "/home/builder/packages", "/home/builder/.abuild"]

CMD ["/bin/sh"]
