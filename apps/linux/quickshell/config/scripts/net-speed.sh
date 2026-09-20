#!/usr/bin/env bash

BARS="▁▂▃▄▅▆▇█"
SAMPLES=30

fmt_speed() {
    local b=$1
    if ((b >= 1048576)); then awk "BEGIN{printf \"%.1f MB/s\", $b/1048576}"
    elif ((b >= 1024)); then printf '%d KB/s' "$((b / 1024))"
    else printf '%d B/s' "$b"; fi
}

spark() {
    local max=$1 v i s=""
    shift
    for v in "$@"; do
        i=$((v * 7 / max))
        ((i > 7)) && i=7
        s+="${BARS:i:1}"
    done
    printf '%s' "$s"
}

declare -a rx_h tx_h
for ((i = 0; i < SAMPLES; i++)); do
    rx_h+=(0)
    tx_h+=(0)
done
prev_rx=0 prev_tx=0 first=1

while true; do
    iface=$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')
    if [[ -z "$iface" ]]; then
        printf '{"iface":"","rx":"","tx":"","down":"","up":""}\n'
        sleep 1
        continue
    fi

    read -r rx tx < <(awk -v i="${iface}:" '$1==i {print $2, $10}' /proc/net/dev)
    [[ -z "$rx" ]] && rx=0 && tx=0

    drx=$((rx - prev_rx))
    dtx=$((tx - prev_tx))
    ((drx < 0 || first)) && drx=0
    ((dtx < 0 || first)) && dtx=0
    prev_rx=$rx prev_tx=$tx first=0

    rx_h=("${rx_h[@]:1}" "$drx")
    tx_h=("${tx_h[@]:1}" "$dtx")

    max=102400 # soft floor: 100 KB/s, so an idle link stays flat
    for v in "${rx_h[@]}" "${tx_h[@]}"; do ((v > max)) && max=$v; done

    printf '{"iface":"%s","rx":"%s","tx":"%s","down":"%s","up":"%s"}\n' \
        "$iface" "$(spark "$max" "${rx_h[@]}")" "$(spark "$max" "${tx_h[@]}")" \
        "$(fmt_speed "$drx")" "$(fmt_speed "$dtx")"

    sleep 1
done
