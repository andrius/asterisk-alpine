# Asterisk 22.8 (certified) on Alpine 3.24, installed from Cloudsmith (asterisk/alpine).
#
# Three asterisk 22.x builds are visible at once: this repo's certified 22.8.0.3,
# this repo's LTS 22.10.1, and Alpine's own 22.9.0 in the main repo. To land on
# the certified build specifically we pin BOTH:
#   - the repo, via the "@andrius-asterisk" tag, and
#   - the version, via "=~22.8" (fuzzy match on the 22.8 line only).
# See ../README.md for the full explanation.
#
#   docker build -t asterisk-22-cert examples/asterisk-22-cert
#   docker run --rm -it asterisk-22-cert
FROM alpine:3.24

# 1. Trust the repository signing key.
ADD https://dl.cloudsmith.io/public/asterisk/alpine/cfg/rsa/rsa.25B0C9A992BE0CEF.key \
    /etc/apk/keys/alpine@asterisk-25B0C9A992BE0CEF.rsa.pub

# 2. Add the repo under a pin tag; "@andrius-asterisk" then selects it explicitly.
RUN echo "@andrius-asterisk https://dl.cloudsmith.io/public/asterisk/alpine/alpine/v3.24/main" >> /etc/apk/repositories

# 3. Install the certified 22.8 line pinned to our repo. "=~22.8" excludes both
#    the 22.10 LTS in this repo and Alpine's 22.9.0 in main.
RUN apk add --no-cache \
      "asterisk@andrius-asterisk=~22.8" \
      "asterisk-sample-config@andrius-asterisk=~22.8" \
      "asterisk-opus@andrius-asterisk=~22.8" \
 && asterisk -V

# SIP/PJSIP signalling, ARI/HTTP, and a small RTP media range.
EXPOSE 5060/udp 5060/tcp 8088/tcp 10000-10100/udp

# Run in the foreground with a verbose console.
CMD ["asterisk", "-fvvv"]
