#!/command/with-contenv bash

set -eu

CONF_DIR="/etc/unbound/conf.d"
OUTPUT_CONF="${CONF_DIR}/50-blacklist.conf"
BLACKLIST_FILE="${BLACKLIST_FILE:-/etc/unbound/blacklist.txt}"
BLACKLIST_URL="${BLACKLIST_URL:-}"
BLACKLIST_FETCH_TIMEOUT="${BLACKLIST_FETCH_TIMEOUT:-60}"
CACHE_DIR="/var/lib/unbound-blacklist"
CACHE_FILE="${CACHE_DIR}/blacklist.remote.txt"
FIRST_SYNC_MARKER="/run/blacklist-first-sync.done"
LOCK_FILE="/run/blacklist-sync.lock"
OUTPUT_CHANGED="true"

case "$BLACKLIST_FETCH_TIMEOUT" in
  ''|*[!0-9]*|0)
    BLACKLIST_FETCH_TIMEOUT=60
    ;;
esac

log() {
  printf 'blacklist-sync: %s\n' "$*" >&2
}

# Prints one normalized netblock per valid line. Invalid lines are skipped
# and counted on stderr so a bad entry can never reach the Unbound config.
sanitize_ips() {
  awk '
    function is_dec(s, max) {
      if (s !~ /^[0-9]+$/ || length(s) > 3) return 0
      return (s + 0) <= max
    }
    function norm_ipv4(addr,    parts, n, i, out) {
      n = split(addr, parts, ".")
      if (n != 4) return ""
      out = ""
      for (i = 1; i <= 4; i++) {
        if (!is_dec(parts[i], 255)) return ""
        out = out (i > 1 ? "." : "") (parts[i] + 0)
      }
      return out
    }
    function valid_ipv6(addr,    rest, groups, n, i, count, last, dc) {
      if (addr !~ /^[0-9a-f:.]+$/ || addr !~ /:/) return 0
      if (addr ~ /:::/) return 0
      rest = addr
      dc = gsub(/::/, "::", rest)
      if (dc > 1) return 0
      if (addr ~ /^:[^:]/ || addr ~ /[^:]:$/) return 0
      n = split(addr, groups, ":")
      count = 0
      for (i = 1; i <= n; i++) {
        if (groups[i] == "") continue
        if (i == n && groups[i] ~ /\./) {
          if (norm_ipv4(groups[i]) == "") return 0
          count += 2
          continue
        }
        if (groups[i] !~ /^[0-9a-f]+$/ || length(groups[i]) > 4) return 0
        count++
      }
      if (dc == 1) return count <= 7
      return count == 8
    }
    {
      gsub(/\r/, "", $0)
      sub(/#.*/, "", $0)
      gsub(/^[ \t]+|[ \t]+$/, "", $0)
      if ($0 == "") next
      split($0, fields, /[ \t]+/)
      entry = tolower(fields[1])
      addr = entry
      prefix = ""
      slash = index(entry, "/")
      if (slash > 0) {
        addr = substr(entry, 1, slash - 1)
        prefix = substr(entry, slash + 1)
      }
      v4 = norm_ipv4(addr)
      if (v4 != "") {
        if (prefix == "") prefix = "32"
        if (is_dec(prefix, 32)) { print v4 "/" (prefix + 0); next }
      } else if (valid_ipv6(addr)) {
        if (prefix == "") prefix = "128"
        if (is_dec(prefix, 128)) { print addr "/" (prefix + 0); next }
      }
      skipped++
    }
    END {
      if (skipped > 0) printf "blacklist-sync: skipped %d invalid line(s)\n", skipped > "/dev/stderr"
    }
  '
}

# Downloads the URL and replaces the cache only when the payload contains at
# least one valid entry (an empty body or an HTML error page is rejected).
fetch_blacklist() {
  local tmp
  mkdir -p "$CACHE_DIR"
  tmp="$(mktemp "${CACHE_DIR}/.download.XXXXXX")"
  if ! curl -fsSL --connect-timeout 10 --max-time "$BLACKLIST_FETCH_TIMEOUT" \
    --retry 2 --retry-delay 2 "$BLACKLIST_URL" -o "$tmp"; then
    rm -f "$tmp"
    log "warning: failed to fetch ${BLACKLIST_URL}"
    return 1
  fi
  if [ -z "$(sanitize_ips <"$tmp" 2>/dev/null | head -n 1)" ]; then
    rm -f "$tmp"
    log "warning: ${BLACKLIST_URL} returned no valid entry, ignoring it"
    return 1
  fi
  chmod 644 "$tmp"
  mv "$tmp" "$CACHE_FILE"
}

select_source() {
  if [ -n "$BLACKLIST_URL" ]; then
    if fetch_blacklist; then
      echo "$CACHE_FILE"
      return 0
    fi
    if [ -f "$CACHE_FILE" ]; then
      log "warning: using cached list ${CACHE_FILE}"
      echo "$CACHE_FILE"
      return 0
    fi
    log "warning: no cached list available, blacklist is empty"
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

install_conf() {
  mv "$1" "$OUTPUT_CONF"
  chown unbound:unbound "$OUTPUT_CONF"
  chmod 640 "$OUTPUT_CONF"
}

config_is_valid() {
  if ! command -v unbound-checkconf >/dev/null 2>&1; then
    return 0
  fi
  local out
  if out="$(unbound-checkconf 2>&1)"; then
    return 0
  fi
  log "error: unbound-checkconf failed: ${out}"
  return 1
}

# Renders the fragment, then installs it only if the full Unbound config still
# validates. On failure the previous fragment is restored and nothing reloads.
render_conf() {
  local source="$1"
  local tmp backup=""
  tmp="$(mktemp /etc/unbound/.50-blacklist.XXXXXX)"
  {
    if [ -n "$source" ]; then
      printf '# Generated from %s\n' "$source"
    else
      printf '# Generated without a blacklist source\n'
    fi
    printf 'server:\n'
    if [ -n "$source" ]; then
      sanitize_ips <"$source" | sort -u | while read -r netblock; do
        printf '  response-ip: %s always_nxdomain\n' "$netblock"
      done
    fi
  } >"$tmp"
  if [ -f "$OUTPUT_CONF" ] && cmp -s "$tmp" "$OUTPUT_CONF"; then
    rm -f "$tmp"
    OUTPUT_CHANGED="false"
    return 0
  fi
  if [ -f "$OUTPUT_CONF" ]; then
    backup="$(mktemp /etc/unbound/.50-blacklist.bak.XXXXXX)"
    cp -p "$OUTPUT_CONF" "$backup"
  fi
  install_conf "$tmp"
  if config_is_valid; then
    [ -n "$backup" ] && rm -f "$backup"
    return 0
  fi
  OUTPUT_CHANGED="false"
  if [ -n "$backup" ]; then
    mv "$backup" "$OUTPUT_CONF"
    log "error: keeping the previous blacklist"
  else
    printf '# Generated blacklist rejected by unbound-checkconf\nserver:\n' >"$OUTPUT_CONF"
    log "error: generated blacklist rejected, using an empty one"
  fi
  return 1
}

signal_unbound() {
  local svc="/run/service/unbound"
  [ -d "$svc" ] || return 0
  if [ -x /command/s6-svc ]; then
    /command/s6-svc "$1" "$svc" 2>/dev/null || true
  elif command -v s6-svc >/dev/null 2>&1; then
    s6-svc "$1" "$svc" 2>/dev/null || true
  fi
}

exec 9>"$LOCK_FILE"
flock 9

mkdir -p "$CONF_DIR"
source_file="$(select_source)"
status=0
render_conf "$source_file" || status=1

if [ "$OUTPUT_CHANGED" = "true" ]; then
  if [ -n "$source_file" ] && [ ! -f "$FIRST_SYNC_MARKER" ]; then
    # First successful sync: restart so Unbound starts from a fresh state.
    signal_unbound -r
  else
    signal_unbound -h
  fi
fi

if [ -n "$source_file" ] && [ ! -f "$FIRST_SYNC_MARKER" ]; then
  touch "$FIRST_SYNC_MARKER"
fi

exit "$status"
