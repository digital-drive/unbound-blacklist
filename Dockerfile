FROM registry.digital-drive.io/tools/unbound:1.0.0

LABEL maintainer="Maxence Winandy <maxence.winandy@digital-drive.io>"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        curl \
        inotify-tools \
    ; \
    rm -rf /var/lib/apt/lists/*

COPY rootfs/ /

RUN chmod +x \
    /etc/cont-init.d/20-blacklist \
    /etc/s6-overlay/s6-rc.d/blacklist-refresh/run \
    /etc/s6-overlay/s6-rc.d/blacklist-file-watch/run \
    /usr/local/bin/blacklist-sync.sh
