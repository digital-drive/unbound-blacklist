FROM registry.digital-drive.io/alpine/3.22

LABEL maintainer="Maxence Winandy <maxence.winandy@digital-drive.io>"

RUN set -eux; \
    apk add --no-cache \
        ca-certificates \
        curl \
        inotify-tools \
        unbound \
    ; \
    rm -rf /var/cache/apk/*

COPY rootfs/ /

RUN chmod +x \
    /etc/cont-init.d/10-unbound \
    /etc/cont-init.d/20-blacklist \
    /etc/s6-overlay/s6-rc.d/unbound/run \
    /etc/s6-overlay/s6-rc.d/blacklist-refresh/run \
    /etc/s6-overlay/s6-rc.d/blacklist-file-watch/run \
    /usr/local/bin/blacklist-sync.sh

ENTRYPOINT ["/init"]
