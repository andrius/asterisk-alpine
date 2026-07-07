# Asterisk 22.8 (certified) on Alpine 3.24, installed from https://apk.andrius.mobi.
#
# Three asterisk 22.x builds are visible at once: this repo's certified 22.8.0.3,
# this repo's LTS 22.10.1, and Alpine's own 22.9.0 in the main repo. To land on
# the certified build specifically we pin BOTH:
#   - the repo, via the "@astalpine" tag, and
#   - the version, via "=~22.8" (fuzzy match on the 22.8 line only).
# See ../README.md for the full explanation.
#
#   docker build -t asterisk-22-cert examples/asterisk-22-cert
#   docker run --rm -it asterisk-22-cert
FROM alpine:3.24

# 1. Trust the repository signing key.
ADD https://apk.andrius.mobi/packages@asterisk-alpine.rsa.pub \
    /etc/apk/keys/packages@asterisk-alpine.rsa.pub

# 2. Add the repo under a pin tag; "@astalpine" then selects it explicitly.
RUN echo "@astalpine https://apk.andrius.mobi/v3.24/main" >> /etc/apk/repositories

# 3. Install the certified 22.8 line pinned to our repo. "=~22.8" excludes both
#    the 22.10 LTS in this repo and Alpine's 22.9.0 in main.
RUN apk add --no-cache \
      "asterisk@astalpine=~22.8" \
      "asterisk-sample-config@astalpine=~22.8" \
      "asterisk-opus@astalpine=~22.8" \
 && asterisk -V

# SIP/PJSIP signalling, ARI/HTTP, and a small RTP media range.
EXPOSE 5060/udp 5060/tcp 8088/tcp 10000-10100/udp

# Run in the foreground with a verbose console.
CMD ["asterisk", "-fvvv"]
