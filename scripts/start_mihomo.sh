#!/bin/bash
set -u
MIHOMO=/usr/local/bin/mihomo
CONFIG_DIR=/etc/mihomo
LOG=/tmp/mihomo.log

if pgrep -x mihomo >/dev/null; then
  exit 0
fi

"$MIHOMO" -t -d "$CONFIG_DIR" >>"$LOG" 2>&1 || exit 1
nohup "$MIHOMO" -d "$CONFIG_DIR" >>"$LOG" 2>&1 </dev/null &
sleep 2
if pgrep -x mihomo >/dev/null; then
  echo "Mihomo started successfully"
else
  echo "Mihomo failed to start; see $LOG" >&2
  exit 1
fi
