# README.md

Unbound DNS resolver with a managed IP blacklist source. The image loads
Unbound on top of `registry.digital-drive.io/alpine/3.22` (s6-overlay)
and generates an Unbound include file from a local blacklist file or a
remote URL.

## Features

- Unbound runs under s6-overlay as PID 1.
- Blacklist loaded from a mounted file or fetched over HTTP(S).
- Blacklist lines are converted into an Unbound response-IP fragment.
- If an upstream response contains a listed IP, Unbound returns NXDOMAIN.
- IPv4/IPv6 UDP/TCP DNS service on port 53.
- DNSSEC validation enabled with an auto-managed trust anchor.
- EDNS buffer tuned for modern resolvers (1232 bytes).
- Designed for `linux/amd64` and `linux/arm64`.

## Quick Start

Build:

```bash
docker build -t unbound-blacklist .
```

Run with a mounted blacklist file:

```bash
docker run --rm -p 53:53/udp -p 53:53/tcp \
  -v ./blacklist.txt:/etc/unbound/blacklist.txt:ro \
  unbound-blacklist
```

Run with a remote blacklist URL:

```bash
docker run --rm -p 53:53/udp -p 53:53/tcp \
  -e BLACKLIST_URL=https://example.com/blacklist.txt \
  unbound-blacklist
```

## Configuration

| Variable                    | Default                          | Description                                                                 |
|----------------------------|----------------------------------|-----------------------------------------------------------------------------|
| `BLACKLIST_FILE`           | `/etc/unbound/blacklist.txt`     | Path to a file containing one IP or netblock per line.                      |
| `BLACKLIST_URL`            | unset                            | HTTP(S) URL to fetch the blacklist. When set, it replaces the local file.   |
| `BLACKLIST_REFRESH_SECONDS`| `600`                            | When `BLACKLIST_URL` is set, re-fetches on this interval and reloads.         |
| `BLACKLIST_REFRESH_INITIAL_SECONDS`| `600`                   | First refresh delay after the initial sync when using `BLACKLIST_URL`.       |
| `UNBOUND_LOG_LEVEL`        | `info`                           | Unbound verbosity (`off`, `minimal`, `info`, `verbose`, `debug`, `trace`).   |
| `DNS_LISTEN_PORT`          | `53`                             | TCP/UDP port Unbound listens on inside the container.                        |
| `DNS_ACCESS_CONTROL`       | `0.0.0.0/0 allow ::0/0 allow`     | Access-control entries applied to Unbound.                                   |
| `DNSSEC_TRUST_ANCHOR`      | `/var/lib/unbound/root.key`      | Override the DNSSEC trust anchor path.                                       |
| `PRIVATE_UPSTREAM_SERVERS` | unset                            | Comma/space-separated upstreams for private zones and suffix.                |
| `PRIVATE_SUFFIX`           | `.docker`                        | Private suffix handled by the private upstream or blocked by default.        |

Blacklist file format:

- One IP or CIDR netblock per line (e.g. `203.0.113.10` or `2001:db8::/64`).
- Blank lines are ignored.
- Lines starting with `#` are ignored.

## Volumes

- `/etc/unbound/blacklist.txt` (optional, if using a local file)
- `/etc/unbound/conf.d` (optional, if you want to add custom fragments)

## Notes

- Unbound runs in the foreground so `docker logs` shows resolver output.
- The generated blacklist fragment is stored under `/etc/unbound/conf.d/`.
- When `BLACKLIST_URL` is unset, file changes trigger immediate reloads via inotify.
- Private zones are blocked by default and only forwarded when `PRIVATE_UPSTREAM_SERVERS` is set.
- Missing or unreachable blacklist sources log a warning and leave the response-IP list empty.
- DNSSEC validation uses `auto-trust-anchor-file`, and EDNS is enabled by default.
