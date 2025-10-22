# Asterisk PBX runtime image
# Minimal Alpine-based image for running Asterisk
FROM alpine:3.22

# Add custom repository (will be configured at build time)
# For now, we'll use the official Alpine packages
RUN apk add --no-cache \
    asterisk \
    asterisk-sample-config \
    asterisk-sounds-en \
    asterisk-sounds-moh

# Optional modules (uncomment as needed):
# RUN apk add --no-cache \
#     asterisk-opus \
#     asterisk-speex \
#     asterisk-curl \
#     asterisk-prometheus \
#     asterisk-mobile \
#     asterisk-fax \
#     asterisk-pgsql \
#     asterisk-odbc \
#     asterisk-ldap

# Create necessary directories
RUN mkdir -p \
    /var/run/asterisk \
    /var/log/asterisk \
    /var/spool/asterisk \
    && chown -R asterisk:asterisk \
        /var/run/asterisk \
        /var/log/asterisk \
        /var/spool/asterisk

# Expose ports
# 5060: SIP UDP
# 5061: SIP TLS
# 10000-10099: RTP (adjust range as needed)
EXPOSE 5060/udp 5061/tcp 10000-10099/udp

VOLUME ["/etc/asterisk", "/var/lib/asterisk", "/var/log/asterisk", "/var/spool/asterisk"]

USER asterisk
WORKDIR /var/lib/asterisk

CMD ["/usr/sbin/asterisk", "-f", "-vvv"]
