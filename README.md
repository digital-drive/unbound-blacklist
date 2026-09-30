# README.md

Unbound DNS resolver with a managed IP blacklist source. This image
extends the `registry.digital-drive.io/tools/unbound` base and generates an
Unbound include file from a local blacklist file or a remote URL.
Image: https://hub.docker.com/r/digitaldriveio/unbound-blacklist

## Features

- Unbound runs under s6-overlay as PID 1.
- Blacklist loaded from a mounted file or fetched over HTTP(S).
- Blacklist lines are validated and converted into an Unbound response-IP fragment.
- A new fragment is installed only if `unbound-checkconf` accepts it.
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

Run with public upstream resolvers:

```bash
docker run --rm -p 53:53/udp -p 53:53/tcp \
  -e PUBLIC_UPSTREAM_SERVERS="1.1.1.1 8.8.8.8" \
  unbound-blacklist
```

## Configuration

| Variable                            | Default                       | Description                                                                |
|-------------------------------------|-------------------------------|----------------------------------------------------------------------------|
| `BLACKLIST_FILE`                    | `/etc/unbound/blacklist.txt`  | Path to a file containing one IP or netblock per line.                     |
| `BLACKLIST_URL`                     | unset                         | HTTP(S) URL to fetch the blacklist. When set, it replaces the local file.  |
| `BLACKLIST_REFRESH_SECONDS`         | `600`                         | When `BLACKLIST_URL` is set, re-fetches on this interval (`0` disables).   |
| `BLACKLIST_REFRESH_INITIAL_SECONDS` | `BLACKLIST_REFRESH_SECONDS`   | First refresh delay after the initial sync when using `BLACKLIST_URL`.     |
| `BLACKLIST_FETCH_TIMEOUT`           | `60`                          | Maximum duration in seconds of one `BLACKLIST_URL` download.               |
| `UNBOUND_LOG_LEVEL`                 | `info`                        | Unbound verbosity (`off`, `minimal`, `info`, `verbose`, `debug`, `trace`). |
| `DNS_LISTEN_PORT`                   | `53`                          | TCP/UDP port Unbound listens on inside the container.                      |
| `DNS_ACCESS_CONTROL`                | `0.0.0.0/0 allow ::0/0 allow` | Access-control entries applied to Unbound.                                 |
| `DNSSEC_TRUST_ANCHOR`               | `/var/lib/unbound/root.key`   | Override the DNSSEC trust anchor path.                                     |
| `PRIVATE_UPSTREAM_SERVERS`          | unset                         | Comma/space-separated upstreams for private zones and suffix.              |
| `PUBLIC_UPSTREAM_SERVERS`           | `1.1.1.1 8.8.8.8 9.9.9.9`     | Comma/space-separated upstreams for public resolution (forward-zone ".").  |
| `PRIVATE_SUFFIX`                    | `.docker`                     | Private suffix handled by the private upstream or blocked by default.      |

Blacklist file format:

- One IP or CIDR netblock per line (e.g. `203.0.113.10` or `2001:db8::/64`).
- Blank lines are ignored.
- Everything after `#` is a comment; extra columns after the first are ignored.
- Invalid addresses or prefix lengths are skipped and counted in the logs.

## Volumes

- `/etc/unbound/blacklist.txt` (optional, if using a local file). A
  single-file bind mount works for in-place edits; editors that replace the
  file break such a mount, so prefer mounting a directory and pointing
  `BLACKLIST_FILE` to the file inside it.
- `/var/lib/unbound-blacklist` (optional, keeps the last downloaded list
  across container re-creations when using `BLACKLIST_URL`).
- Custom fragments: mount individual files into `/etc/unbound/conf.d/`
  rather than the whole directory, which also holds the generated fragment
  and the base image fragments. It must stay writable.

## Notes

- Unbound runs in the foreground so `docker logs` shows resolver output.
- The generated blacklist fragment is stored under `/etc/unbound/conf.d/`.
- When `BLACKLIST_URL` is unset, file changes trigger immediate reloads via inotify,
  with a 60-second polling fallback (e.g. for a file created after startup).
- Private zones are blocked by default and only forwarded when `PRIVATE_UPSTREAM_SERVERS` is set.
- An unreachable URL, or a download without any valid entry, keeps the cached
  list. Without a cache or local file the resolver starts with an empty list
  (fail-open) and logs a warning.
- If the generated fragment fails `unbound-checkconf`, the previous fragment is
  kept and Unbound is not reloaded.
- The default `DNS_ACCESS_CONTROL` allows every client. Restrict it (e.g.
  `10.0.0.0/8 allow 192.168.0.0/16 allow`) before publishing port 53 on a
  reachable host, otherwise the container is an open resolver.
- `response-ip` requires the `respip` module in Unbound's `module-config`
  (provided by the base image).
- DNSSEC validation uses `auto-trust-anchor-file`, and EDNS is enabled by default.
