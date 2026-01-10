# CHANGELOG.md

# 1.0.0 (2026-01-10)

### Features

* Unbound recursive resolver with response-IP (NXDOMAIN) blocking from an IP blacklist
* Blacklist sourced from local file or remote URL with refresh and file watch
* DNSSEC validation enabled with trust anchor management
* Public upstream forwarding defaults (1.1.1.1, 8.8.8.8, 9.9.9.9) and private upstream support
* Healthcheck via DNS query and s6-supervised services
