---
description: Unbound DNS resolver on Alpine with a managed IP blacklist.
---

# DockerHub.md

Unbound DNS resolver built on `registry.digital-drive.io/alpine/3.22` with
an optional blacklist file or remote URL. The container renders a dedicated
Unbound response-IP fragment for the blacklist and reloads when the list changes.

## Highlights

- Runs Unbound under s6-overlay with PID 1 set to `/init`.
- Supports a local blacklist file or HTTP(S) download.
- Optional refresh interval to keep the blacklist current.
- Uses `response-ip: <ip-netblock> always_nxdomain` for fast blocking.
- Exposes standard DNS over UDP/TCP on port 53.
- DNSSEC validation and EDNS are enabled for modern resolvers.
- Private reverse zones and a custom suffix are blocked by default unless an upstream is configured.

## Quickstart

```bash
docker build -t digitaldriveio/unbound-blacklist .

docker run --name unbound-blacklist \
  -p 53:53/udp -p 53:53/tcp \
  -v /path/to/blacklist.txt:/etc/unbound/blacklist.txt:ro \
  digitaldriveio/unbound-blacklist:snapshot
```

## Runtime configuration

- **Local file:** Mount a blacklist file to `/etc/unbound/blacklist.txt`
  (or change with `BLACKLIST_FILE`).
- **Remote list:** Set `BLACKLIST_URL` to a reachable HTTP(S) URL.
- **Refresh cadence:** Set `BLACKLIST_REFRESH_SECONDS` to a value > 0 to
  re-fetch and reload automatically. Use `BLACKLIST_REFRESH_INITIAL_SECONDS`
  for the first delay after the initial sync.
- **Logging:** Control verbosity with `UNBOUND_LOG_LEVEL`.
- **Access control:** Tune with `DNS_ACCESS_CONTROL` (Unbound format).

## Notes

- The generated blacklist fragment is stored under
  `/etc/unbound/conf.d/50-blacklist.conf`.
- The blacklist file should contain one IP or CIDR netblock per line.
- Use named volumes if you want the downloaded blacklist cached across
  container restarts.
