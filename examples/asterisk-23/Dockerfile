# Asterisk 23 (current) on Alpine 3.24, installed from https://apk.andrius.mobi.
#
# Repository pinning (the "@astalpine" tag) keeps these packages from clashing
# with Alpine's own asterisk (22.9.x in the main repo) - apk will only take
# asterisk from this repo, and won't silently swap it on `apk upgrade`.
# See ../README.md for the full explanation.
#
#   docker build -t asterisk-23 examples/asterisk-23
#   docker run --rm -it asterisk-23
FROM alpine:3.24

# 1. Trust the repository signing key.
ADD https://apk.andrius.mobi/packages@asterisk-alpine.rsa.pub \
    /etc/apk/keys/packages@asterisk-alpine.rsa.pub

# 2. Add the repo under a pin tag; "@astalpine" then selects it explicitly.
RUN echo "@astalpine https://apk.andrius.mobi/v3.24/main" >> /etc/apk/repositories

# 3. Install Asterisk 23 pinned to our repo (=~23 resolves to 23.4.x), plus the
#    sample config so it starts, and a couple of common codecs.
RUN apk add --no-cache \
      "asterisk@astalpine=~23" \
      "asterisk-sample-config@astalpine=~23" \
      "asterisk-opus@astalpine=~23" \
      "asterisk-srtp@astalpine=~23" \
 && asterisk -V

# SIP/PJSIP signalling, ARI/HTTP, and a small RTP media range.
EXPOSE 5060/udp 5060/tcp 8088/tcp 10000-10100/udp

# Run in the foreground with a verbose console.
CMD ["asterisk", "-fvvv"]
