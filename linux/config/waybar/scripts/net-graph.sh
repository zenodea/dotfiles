#!/bin/bash

DOTFILES_DIR="$HOME/Documents/dotfiles_nixless"
THEME_FILE="$DOTFILES_DIR/themes/$(cat "$DOTFILES_DIR/.current-theme" 2>/dev/null || echo 'nord').sh"
# shellcheck source=/dev/null
[[ -f "$THEME_FILE" ]] && source "$THEME_FILE"
BLUE="${BLUE:-5e81ac}"
RED="${RED:-bf616a}"

HISTORY="/tmp/waybar-netgraph"
BARS="▁▂▃▄▅▆▇█"
SAMPLES=30

IFACE=$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')
if [[ -z "$IFACE" ]]; then
    printf '{"text": "󰤭", "tooltip": "Disconnected", "class": "disconnected"}\n'
    exit 0
fi

read -r rx tx < <(awk -v iface="${IFACE}:" '$1==iface {print $2, $10}' /proc/net/dev)
if [[ -z "$rx" ]]; then
    printf '{"text": "󰤭", "tooltip": "No data", "class": "disconnected"}\n'
    exit 0
fi

declare -a rx_h tx_h
prev_rx=$rx prev_tx=$tx
if [[ -f "$HISTORY" ]]; then
    IFS='|' read -r rx_str tx_str prev_rx prev_tx < "$HISTORY"
    IFS=',' read -ra rx_h <<< "$rx_str"
    IFS=',' read -ra tx_h <<< "$tx_str"
fi
# pad to full width so the bar never shifts on startup
while (( ${#rx_h[@]} < SAMPLES )); do rx_h=("0" "${rx_h[@]}"); done
while (( ${#tx_h[@]} < SAMPLES )); do tx_h=("0" "${tx_h[@]}"); done

drx=$(( rx - prev_rx )); (( drx < 0 )) && drx=0
dtx=$(( tx - prev_tx )); (( dtx < 0 )) && dtx=0

rx_h+=("$drx"); tx_h+=("$dtx")
(( ${#rx_h[@]} > SAMPLES )) && rx_h=("${rx_h[@]:1}")
(( ${#tx_h[@]} > SAMPLES )) && tx_h=("${tx_h[@]:1}")

printf '%s|%s|%s|%s\n' \
    "$(IFS=','; echo "${rx_h[*]}")" \
    "$(IFS=','; echo "${tx_h[*]}")" \
    "$rx" "$tx" > "$HISTORY"

max=102400  # soft floor: 100 KB/s
for v in "${rx_h[@]}" "${tx_h[@]}"; do (( v > max )) && max=$v; done

spark() {
    local s=""
    for v in "$@"; do
        local i=$(( v * 7 / max ))
        (( i > 7 )) && i=7
        s+="${BARS:$i:1}"
    done
    printf '%s' "$s"
}

fmt_speed() {
    local b=$1
    if   (( b >= 1048576 )); then awk "BEGIN{printf \"%.1fMB/s\", $b/1048576}"
    elif (( b >= 1024 ));    then printf "%dKB/s" "$(( b / 1024 ))"
    else printf "%dB/s" "$b"; fi
}

rx_spark=$(spark "${rx_h[@]}")
tx_spark=$(spark "${tx_h[@]}")
tooltip="↓ $(fmt_speed $drx)  ↑ $(fmt_speed $dtx) — $IFACE"
text="<span foreground='#${BLUE}'>${rx_spark}</span><span letter_spacing='14000'> </span><span foreground='#${RED}'>${tx_spark}</span>"

printf '{"text": "%s", "tooltip": "%s"}\n' "$text" "$tooltip"
