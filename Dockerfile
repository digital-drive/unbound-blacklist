FROM registry.digital-drive.io/tools/unbound:1.1

LABEL maintainer="Maxence Winandy <maxence.winandy@digital-drive.io>" \
      org.opencontainers.image.title="unbound-blacklist" \
      org.opencontainers.image.description="Unbound DNS resolver with a managed IP blacklist" \
      org.opencontainers.image.source="https://github.com/digital-drive/unbound-blacklist" \
      org.opencontainers.image.licenses="GPL-3.0-only"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        curl \
        inotify-tools \
    ; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p /var/lib/unbound-blacklist

COPY rootfs/ /

RUN chmod +x \
    /etc/cont-init.d/20-blacklist \
    /etc/s6-overlay/s6-rc.d/blacklist-refresh/run \
    /etc/s6-overlay/s6-rc.d/blacklist-file-watch/run \
    /usr/local/bin/blacklist-sync.sh
