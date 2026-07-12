#!/bin/bash

# Drives both the net_down and net_up graphs: one script, two --push calls, so
# the pair always samples the same interval. Both graphs subscribe to the mouse
# events, but only net_down samples — net_up would otherwise halve each
# interval by consuming the shared state file out of turn.

STATE="${TMPDIR:-/tmp}/sketchybar_net_graph"

# Graphs take a 0..1 value, so a rate needs a scale to map onto. This one is
# logarithmic: a decade of throughput per quarter of graph height, which keeps
# idle chatter legible at the bottom while leaving a spike somewhere to go.
# Below FLOOR reads as silence; above CEIL pins to full height.
FLOOR=1024                # 1 KB/s
CEIL=$((10 * 1024 * 1024)) # 10 MB/s

popup() { sketchybar --set net_down popup.drawing="$1"; }

case "$SENDER" in
  mouse.entered)
    popup on
    exit 0
    ;;
  mouse.exited | mouse.exited.global)
    popup off
    exit 0
    ;;
esac

# Routine updates fire on both graphs; only one of them may advance the state.
[ "$NAME" = "net_down" ] || exit 0

IFACE="$(route get default 2> /dev/null | awk '/interface:/ { print $2 }')"

if [ -z "$IFACE" ]; then
  sketchybar --set net.download label="offline" --set net.upload label="offline"
  exit 0
fi

# netstat prints a row per address on an interface, all carrying the same
# cumulative counters — take the <Link#> row and stop.
read -r RX TX <<< "$(netstat -ib -I "$IFACE" | awk '/<Link#/ { print $7, $10; exit }')"
NOW="$(date +%s)"

PREV_TIME="" PREV_RX="" PREV_TX=""
[ -r "$STATE" ] && read -r PREV_TIME PREV_RX PREV_TX < "$STATE"
echo "$NOW $RX $TX" > "$STATE"

# Nothing to diff against on the first run, and the counters restart from zero
# when the interface changes — either way, wait for the next sample.
if [ -z "$PREV_TIME" ] || [ "$NOW" -le "$PREV_TIME" ] ||
  [ "$RX" -lt "${PREV_RX:-0}" ] || [ "$TX" -lt "${PREV_TX:-0}" ]; then
  exit 0
fi

read -r DOWN_VALUE UP_VALUE LABELS <<< "$(
  awk -v rx="$RX" -v tx="$TX" -v prx="$PREV_RX" -v ptx="$PREV_TX" \
    -v dt="$((NOW - PREV_TIME))" -v floor="$FLOOR" -v ceil="$CEIL" '
    function log_scale(b,   v) {
      if (b <= floor) return 0
      v = log(b / floor) / log(ceil / floor)
      return v > 1 ? 1 : v
    }
    function human(b) {
      if (b >= 1048576) return sprintf("%.1f MB/s", b / 1048576)
      if (b >= 1024)    return sprintf("%.0f KB/s", b / 1024)
      return sprintf("%.0f B/s", b)
    }
    BEGIN {
      down = (rx - prx) / dt
      up   = (tx - ptx) / dt
      printf "%.4f %.4f %s|%s\n", log_scale(down), log_scale(up), human(down), human(up)
    }'
)"

# human() emits a space ("1.2 MB/s"), so both labels ride in one trailing
# |-separated field rather than being split apart by word.
DOWN_LABEL="${LABELS%%|*}"
UP_LABEL="${LABELS##*|}"

sketchybar --push net_down "$DOWN_VALUE" \
  --push net_up "$UP_VALUE" \
  --set net.download label="$DOWN_LABEL" \
  --set net.upload label="$UP_LABEL"
