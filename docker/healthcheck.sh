#!/bin/sh
# The bot touches HEARTBEAT_PATH every 30 seconds. A process that is alive
# but no longer working stops touching it, and this is what turns that into
# an unhealthy container.
set -e

path="${HEARTBEAT_PATH:-/app/data/heartbeat}"
max_age="${HEARTBEAT_MAX_AGE_SECONDS:-120}"

[ -f "$path" ] || { echo "no heartbeat at $path" >&2; exit 1; }

written=$(cat "$path" 2>/dev/null || echo 0)
case "$written" in
    ''|*[!0-9]*) echo "heartbeat at $path is not a timestamp" >&2; exit 1 ;;
esac

now=$(($(date +%s) * 1000))
age=$(( (now - written) / 1000 ))
if [ "$age" -gt "$max_age" ]; then
    echo "heartbeat is ${age}s old, over the ${max_age}s limit" >&2
    exit 1
fi
echo "heartbeat is ${age}s old"
