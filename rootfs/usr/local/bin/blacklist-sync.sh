#!/bin/sh
set -eu

CONF_DIR="/etc/unbound/conf.d"
OUTPUT_CONF="${CONF_DIR}/50-blacklist.conf"
BLACKLIST_FILE="${BLACKLIST_FILE:-/etc/unbound/blacklist.txt}"
BLACKLIST_URL="${BLACKLIST_URL:-}"
CACHE_FILE="/etc/unbound/blacklist.remote.txt"

log() {
  printf '%s\n' "$*" >&2
}

fetch_blacklist() {
  local tmp
  tmp="$(mktemp)"
  if curl -fsSL "$BLACKLIST_URL" -o "$tmp"; then
    mv "$tmp" "$CACHE_FILE"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

select_source() {
  if [ -n "$BLACKLIST_URL" ]; then
    if fetch_blacklist; then
      echo "$CACHE_FILE"
      return 0
    fi
    if [ -f "$CACHE_FILE" ]; then
      log "warning: failed to fetch blacklist, using cached list"
      echo "$CACHE_FILE"
      return 0
    fi
    log "error: failed to fetch blacklist and no cache available"
    return 1
  fi
  if [ -f "$BLACKLIST_FILE" ]; then
    echo "$BLACKLIST_FILE"
    return 0
  fi
  log "error: blacklist file not found at ${BLACKLIST_FILE}"
  return 1
}

sanitize_domains() {
  awk '
    BEGIN { }
    {
      gsub(/\r/, "", $0)
      sub(/#.*/, "", $0)
      gsub(/^[ \t]+|[ \t]+$/, "", $0)
      if ($0 == "") next
      n = split($0, fields, /[ \t]+/)
      if (n >= 2 && fields[1] ~ /^[0-9a-fA-F:.]+$/) {
        domain = fields[2]
      } else {
        domain = fields[1]
      }
      if (domain == "") next
      print domain
    }
  '
}

render_conf() {
  local source="$1"
  local tmp
  tmp="$(mktemp)"
  {
    printf '# Generated from %s\n' "$source"
    sanitize_domains <"$source" | sort -u | while read -r domain; do
      [ -z "$domain" ] && continue
      printf 'local-zone: "%s" always_nxdomain\n' "$domain"
    done
  } >"$tmp"
  mv "$tmp" "$OUTPUT_CONF"
}

mkdir -p "$CONF_DIR"
source_file="$(select_source)"
render_conf "$source_file"

if command -v unbound-checkconf >/dev/null 2>&1; then
  if ! unbound-checkconf >/dev/null 2>&1; then
    log "warning: unbound-checkconf failed after blacklist update"
  fi
fi

if [ -x /command/s6-svc ] && [ -d /run/service/unbound ]; then
  /command/s6-svc -h /run/service/unbound 2>/dev/null || true
elif command -v s6-svc >/dev/null 2>&1 && [ -d /run/service/unbound ]; then
  s6-svc -h /run/service/unbound 2>/dev/null || true
fi
