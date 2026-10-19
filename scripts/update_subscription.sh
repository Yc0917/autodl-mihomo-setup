#!/bin/bash
# Update Clash/Mihomo subscription while preserving a fixed default selector.
set -euo pipefail
umask 077

GROUP='Flybit'
NODE='🇸🇬 新加坡 | 03'
DIR=/etc/mihomo
CFG="$DIR/config.yaml"
MIHOMO=/usr/local/bin/mihomo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$DIR"
command -v curl >/dev/null
command -v python3 >/dev/null
command -v "$MIHOMO" >/dev/null
python3 -c 'import yaml' || { echo 'Please install PyYAML: python3 -m pip install pyyaml' >&2; exit 1; }

tmp="$(mktemp "$DIR/.subscription.XXXXXX.yaml")"
trap 'rm -f "$tmp"; unset SUB_URL' EXIT
read -r -s -p "Clash/Mihomo subscription URL (hidden): " SUB_URL
echo
[ -n "$SUB_URL" ] || { echo 'Empty URL' >&2; exit 1; }
case "$SUB_URL" in https://*) ;; *) echo 'Subscription must use HTTPS' >&2; exit 1;; esac

# Never echo or persist the real subscription URL in the repository.
curl -fsSL --retry 2 --connect-timeout 10 --max-time 90 \
  -A 'clash.meta' -o "$tmp" "$SUB_URL"
unset SUB_URL
test -s "$tmp"

python3 "$SCRIPT_DIR/patch_config.py" "$tmp" "$GROUP" "$NODE"
"$MIHOMO" -t -d "$DIR" -f "$tmp"

# Only commit validated configuration.
chmod 600 "$tmp"
mv -f "$tmp" "$CFG"
echo 'Subscription updated and validated.'

# Restart only when the service was already running.
if pgrep -x mihomo >/dev/null; then
  pkill -x mihomo
  for i in $(seq 1 30); do
    pgrep -x mihomo >/dev/null || break
    sleep 0.2
  done
  /root/start_mihomo.sh
  curl --noproxy '*' -fsS --retry 5 --retry-delay 1 \
    'http://127.0.0.1:9090/proxies/Flybit' |
    python3 -c 'import json,sys; d=json.load(sys.stdin); print("Current node:",d["now"]); assert d["now"]=="🇸🇬 新加坡 | 03", "Unexpected node"'
else
  echo 'Mihomo is not running. Start via /root/start_mihomo.sh.'
fi
