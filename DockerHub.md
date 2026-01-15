---
description: Unbound DNS resolver on Debian Trixie with a managed IP blacklist.
---

# DockerHub.md

## Quick reference

- Maintained by: Maxence Winandy from Digital Drive
- Source: https://github.com/digital-drive/unbound-blacklist
- Where to get help: https://github.com/digital-drive/unbound-blacklist/issues
- Supported architectures: amd64, arm64

## Quickstart

```bash
docker run --name unbound-blacklist \
  -p 53:53/udp -p 53:53/tcp \
  -v /path/to/blacklist.txt:/etc/unbound/blacklist.txt:ro \
  digitaldriveio/unbound-blacklist
```

## Runtime configuration

- **Local file:** Mount a blacklist file to `/etc/unbound/blacklist.txt`
  (or change with `BLACKLIST_FILE`).
- **Remote list:** Set `BLACKLIST_URL` to a reachable HTTP(S) URL.
- **Refresh cadence:** Set `BLACKLIST_REFRESH_SECONDS` to a value > 0 to
  re-fetch and reload automatically. Use `BLACKLIST_REFRESH_INITIAL_SECONDS`
  for the first delay after the initial sync.
- **Public upstreams:** Set `PUBLIC_UPSTREAM_SERVERS` to forward public DNS
  queries (`1.1.1.1 8.8.8.8 9.9.9.9`).
- **Logging:** Control verbosity with `UNBOUND_LOG_LEVEL`.
- **Access control:** Tune with `DNS_ACCESS_CONTROL` (Unbound format).

## Highlights

- Extends the `digital-drive.io/tools/unbound` base image.
- Runs Unbound under s6-overlay with PID 1 set to `/init`.
- Supports a local blacklist file or HTTP(S) download.
- Refresh interval for remote blacklist sync.
- Uses `response-ip: <ip-netblock> always_nxdomain` for fast blocking.
- Exposes standard DNS over UDP/TCP on port 53.
- DNSSEC validation and EDNS are enabled for modern resolvers.
- Private reverse zones and a custom suffix are blocked by default unless an upstream is configured.

## Notes

- The generated blacklist fragment is stored under
  `/etc/unbound/conf.d/50-blacklist.conf`.
- The blacklist file should contain one IP or CIDR netblock per line.
- Use named volumes if you want the downloaded blacklist cached across
  container restarts.

## License

GPL-3.0. See https://github.com/digital-drive/unbound-blacklist/blob/main/LICENSE
