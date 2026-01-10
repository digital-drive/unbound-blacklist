FROM registry.digital-drive.io/debian/trixie

LABEL maintainer="Maxence Winandy <maxence.winandy@digital-drive.io>"

ENV ENABLE_CRON=false

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dns-root-data \
        dnsutils \
        inotify-tools \
        unbound \
    ; \
    rm -rf /var/lib/apt/lists/*

COPY rootfs/ /

RUN chmod +x \
    /etc/cont-init.d/10-unbound \
    /etc/cont-init.d/20-blacklist \
    /etc/s6-overlay/s6-rc.d/unbound/run \
    /etc/s6-overlay/s6-rc.d/blacklist-refresh/run \
    /etc/s6-overlay/s6-rc.d/blacklist-file-watch/run \
    /usr/local/bin/blacklist-sync.sh

ENTRYPOINT ["/init"]

HEALTHCHECK --interval=15s --timeout=5s --retries=3 CMD sh -c 'dig @127.0.0.1 -p "${DNS_LISTEN_PORT:-53}" example.org A +time=2 +tries=1 +short >/dev/null'
