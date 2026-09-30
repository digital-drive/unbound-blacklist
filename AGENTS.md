# AGENTS.md

## Purpose of the Image

This image delivers a standalone Unbound resolver with a configurable
IP blacklist. It accepts either a mounted blacklist file or a remote
HTTP(S) URL, converts it into an Unbound response-IP fragment, and
reloads Unbound when updates are available.

## Internal Components

### 1. Base Image and Process Supervisor

- Base image: `registry.digital-drive.io/tools/unbound`.
- PID 1 is `/init`, and Unbound runs as an s6 longrun in the foreground.

### 2. Blacklist Pipeline

- Input sources:
    - `BLACKLIST_FILE` (default `/etc/unbound/blacklist.txt`)
    - `BLACKLIST_URL` (optional; overrides the local file)
- The blacklist builder generates
  `/etc/unbound/conf.d/50-blacklist.conf`.
- IPs/netblocks are validated, then rendered as
  `response-ip: <ip-netblock> always_nxdomain`.
- A fragment rejected by `unbound-checkconf` is rolled back and never
  loaded.
- Remote lists are cached in `/var/lib/unbound-blacklist`.

### 3. Runtime Configuration

- `DNS_LISTEN_PORT` selects the TCP/UDP port Unbound binds to.
- `DNS_ACCESS_CONTROL` defines access-control entries.
- `UNBOUND_LOG_LEVEL` sets Unbound verbosity.
- `DNSSEC_TRUST_ANCHOR` overrides the DNSSEC trust anchor path.
- `PRIVATE_UPSTREAM_SERVERS` controls forwarding for private ranges and suffix.
- `PUBLIC_UPSTREAM_SERVERS` controls forwarding for public DNS queries (default: `1.1.1.1 8.8.8.8 9.9.9.9`).
- `PRIVATE_SUFFIX` selects the private suffix (default `.docker`).
- `BLACKLIST_REFRESH_SECONDS` enables periodic refresh when using a URL.
- `BLACKLIST_REFRESH_INITIAL_SECONDS` sets the first delay after the initial sync.
- `BLACKLIST_FETCH_TIMEOUT` bounds each remote download (default `60`).

## Expected Behavior

1. s6 runs cont-init hooks to render Unbound configuration.
2. Unbound starts only after `unbound-checkconf` succeeds.
3. When the blacklist changes, Unbound reloads without container restart.

## Files of Interest

- `Dockerfile` extends the base image (Debian Trixie, s6-overlay, Unbound).
- `rootfs/etc/cont-init.d/20-blacklist` runs the initial blacklist sync.
- `rootfs/usr/local/bin/blacklist-sync.sh` fetches, validates, renders and
  reloads.
- `rootfs/etc/s6-overlay/s6-rc.d/blacklist-refresh/run` refreshes a URL.
- `rootfs/etc/s6-overlay/s6-rc.d/blacklist-file-watch/run` watches a file.
- `/etc/unbound/conf.d/50-blacklist.conf` is generated at runtime.
- `.gitlab-ci.yml` lints, smoke-tests, builds and publishes the image.

## Guidance

- Keep documentation in English and align `README.md`,
  `SPECIFICATION.md`, and `DockerHub.md` when behavior changes.
- Use LF line endings only.
- If you add new variables or refresh logic, update all docs here first.
