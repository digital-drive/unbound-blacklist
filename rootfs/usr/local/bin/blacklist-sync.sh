#!/command/with-contenv bash

set -eu

CONF_DIR="/etc/unbound/conf.d"
OUTPUT_CONF="${CONF_DIR}/50-blacklist.conf"
BLACKLIST_FILE="${BLACKLIST_FILE:-/etc/unbound/blacklist.txt}"
BLACKLIST_URL="${BLACKLIST_URL:-}"
CACHE_FILE="/etc/unbound/blacklist.remote.txt"
FIRST_SYNC_MARKER="/run/blacklist-first-sync.done"

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
    log "warning: failed to fetch blacklist and no cache available"
    echo ""
    return 0
  fi
  if [ -f "$BLACKLIST_FILE" ]; then
    echo "$BLACKLIST_FILE"
    return 0
  fi
  log "warning: blacklist file not found at ${BLACKLIST_FILE}"
  echo ""
  return 0
}

sanitize_ips() {
  awk '
    function is_ipv4(addr) {
      return addr ~ /^[0-9]{1,3}(\.[0-9]{1,3}){3}$/
    }
    function is_ipv6(addr) {
      return addr ~ /:/
    }
    {
      gsub(/\r/, "", $0)
      sub(/#.*/, "", $0)
      gsub(/^[ \t]+|[ \t]+$/, "", $0)
      if ($0 == "") next
      n = split($0, fields, /[ \t]+/)
      ip = fields[1]
      if (ip == "") next
      if (ip ~ /\//) {
        print ip
        next
      }
      if (is_ipv4(ip)) {
        print ip "/32"
        next
      }
      if (is_ipv6(ip)) {
        print ip "/128"
        next
      }
    }
  '
}

render_conf() {
  local source="$1"
  local tmp
  tmp="$(mktemp)"
  {
    if [ -n "$source" ]; then
      printf '# Generated from %s\n' "$source"
    else
      printf '# Generated without a blacklist source\n'
    fi
    printf 'server:\n'
    if [ -n "$source" ]; then
      sanitize_ips <"$source" | sort -u | while read -r netblock; do
        [ -z "$netblock" ] && continue
        printf '  response-ip: %s always_nxdomain\n' "$netblock"
      done
    fi
  } >"$tmp"
  mv "$tmp" "$OUTPUT_CONF"
  chown unbound:unbound "$OUTPUT_CONF"
  chmod 640 "$OUTPUT_CONF"
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

if [ -n "$source_file" ] && [ ! -f "$FIRST_SYNC_MARKER" ]; then
  touch "$FIRST_SYNC_MARKER"
  if [ -x /command/s6-svc ] && [ -d /run/service/unbound ]; then
    /command/s6-svc -r /run/service/unbound 2>/dev/null || true
  elif command -v s6-svc >/dev/null 2>&1 && [ -d /run/service/unbound ]; then
    s6-svc -r /run/service/unbound 2>/dev/null || true
  fi
fi
