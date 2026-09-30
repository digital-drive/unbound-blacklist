# SPECIFICATION.md

Authoritative description of the `unbound-blacklist` container image.

## 1. Purpose

Provide a lightweight Unbound DNS resolver that blocks responses
containing blacklisted IPs listed in either a local file or a remote
HTTP(S) blacklist. The image generates an Unbound response-IP fragment at
startup and reloads Unbound when the blacklist changes.

## 2. Components

| Component          | Description                                                                 |
|--------------------|-----------------------------------------------------------------------------|
| Base image         | `registry.digital-drive.io/tools/unbound`                                   |
| DNS server         | `unbound` running in the foreground under s6 supervision                    |
| Blacklist builder  | Startup script renders `/etc/unbound/conf.d/50-blacklist.conf`              |
| Optional refresher | s6 longrun that re-fetches the remote blacklist and reloads Unbound          |
| File watcher       | s6 longrun that rebuilds the fragment when the local blacklist file changes |
| Exposed ports      | `53/tcp`, `53/udp`                                                          |
| Architectures      | `linux/amd64`, `linux/arm64`                                                |

## 3. Configuration Interface

| Variable                     | Default                      | Behaviour                                                                      |
|-----------------------------|------------------------------|--------------------------------------------------------------------------------|
| `BLACKLIST_FILE`            | `/etc/unbound/blacklist.txt` | Path to a local blacklist file (one IP or netblock per line).                  |
| `BLACKLIST_URL`             | unset                        | When set, download this URL and use it instead of `BLACKLIST_FILE`.            |
| `BLACKLIST_REFRESH_SECONDS` | `600`                        | When `BLACKLIST_URL` is set, re-fetch on this cadence and reload Unbound (`0` disables). |
| `BLACKLIST_REFRESH_INITIAL_SECONDS`| `BLACKLIST_REFRESH_SECONDS` | First refresh delay after the initial sync when using `BLACKLIST_URL`.   |
| `BLACKLIST_FETCH_TIMEOUT`   | `60`                         | Maximum duration in seconds of one `BLACKLIST_URL` download (10s connect timeout, 2 retries). |
| `UNBOUND_LOG_LEVEL`         | `info`                       | Unbound verbosity (`off`, `minimal`, `info`, `verbose`, `debug`, `trace`).      |
| `DNS_LISTEN_PORT`           | `53`                         | TCP/UDP port Unbound listens on inside the container.                          |
| `DNS_ACCESS_CONTROL`        | `0.0.0.0/0 allow ::0/0 allow`| Access-control entries applied to Unbound.                                     |
| `DNSSEC_TRUST_ANCHOR`       | `/var/lib/unbound/root.key`  | Path to the DNSSEC trust anchor consumed by Unbound.                           |
| `PRIVATE_UPSTREAM_SERVERS`  | unset                        | Upstreams for private zones and suffix (comma/space separated).               |
| `PUBLIC_UPSTREAM_SERVERS`   | `1.1.1.1 8.8.8.8 9.9.9.9`     | Upstreams for public resolution (forward-zone ".").                           |
| `PRIVATE_SUFFIX`            | `.docker`                    | Private suffix handled by the private upstream or blocked by default.         |

Only the variables above are supported.

## 4. Blacklist Format and Rendering

Blacklist input rules:

- One IP or CIDR netblock per line, such as `203.0.113.10` or `2001:db8::/64`.
- Empty lines are ignored.
- Everything after `#` is a comment; only the first column of a line is read.
- IPv4 octets must be 0-255 and prefixes at most 32 (IPv4) or 128 (IPv6);
  invalid lines are skipped and their count is logged.
- Addresses without a prefix get `/32` (IPv4) or `/128` (IPv6).
- Duplicate entries are removed.

Each entry is rendered into `/etc/unbound/conf.d/50-blacklist.conf` as:

```
response-ip: <ip-netblock> always_nxdomain
```

This guarantees responses containing those IPs return NXDOMAIN. Unbound
must load the `respip` module (`module-config`), which the base image
provides.

The fragment is installed, then validated with `unbound-checkconf`. When
the check fails, the previous fragment is restored (or an empty one is
written) and Unbound is not reloaded.

## 5. Startup Flow

1. s6 starts the cont-init hook before launching Unbound.
2. The blacklist source is resolved:
   - If `BLACKLIST_URL` is set, the file is downloaded to
     `/var/lib/unbound-blacklist/blacklist.remote.txt`. A download without
     any valid entry is rejected and the cached copy is kept.
   - Otherwise the local file at `BLACKLIST_FILE` is used.
3. The builder generates `50-blacklist.conf` from the resolved file.
4. Unbound starts in the foreground using `/etc/unbound/unbound.conf`.
5. If refresh is enabled, a background task waits
   `BLACKLIST_REFRESH_INITIAL_SECONDS`, then re-fetches the URL every
   `BLACKLIST_REFRESH_SECONDS` and reloads Unbound through s6 when the
   fragment changes. It retries immediately if the startup sync found no
   source.
6. If `BLACKLIST_URL` is unset, changes to the file (watched directly and
   through its directory) trigger an immediate rebuild via inotify, with a
   60-second polling fallback.

## 6. Failure Modes & Limitations

- An unreachable `BLACKLIST_URL` keeps the last known blacklist if a
  cache exists. When no cache or local file exists, a warning is logged
  and the blacklist fragment is generated empty (fail-open).
- Invalid IP/netblock lines are skipped.
- A fragment rejected by `unbound-checkconf` is never loaded.
- The image does not validate that blocked IPs are effective beyond
  Unbound configuration syntax checks.
- DNSSEC validation is enabled by default using `auto-trust-anchor-file`.
- EDNS is enabled with a 1232-byte buffer size.
- Private zones are blocked by default unless `PRIVATE_UPSTREAM_SERVERS`
  is provided.
- The default `DNS_ACCESS_CONTROL` allows every client; restrict it before
  exposing port 53 on a reachable network.

## 7. Expected Usage

1. Deploy this image as the primary DNS resolver.
2. Provide a blacklist via `BLACKLIST_URL` or a mounted file.
3. Point downstream services to the container IP and port 53.
4. Reloads are handled automatically when refresh is enabled.

All behaviour changes must be reflected in `README.md` and
`DockerHub.md` to keep documentation aligned.
