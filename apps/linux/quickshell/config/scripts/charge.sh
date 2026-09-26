#!/usr/bin/env bash

group=$(id -gn)
rule=/etc/udev/rules.d/99-dotfiles-charge-limit.rules
modconf=/etc/modprobe.d/dotfiles-charge-limit.conf

attr() {
    local bat
    for bat in /sys/class/power_supply/BAT*; do
        if [[ -e "$bat/charge_control_end_threshold" ]]; then
            printf '%s\n' "$bat/charge_control_end_threshold"
            return 0
        fi
    done
    return 1
}

clamp() {
    local value="${1:-100}"
    [[ "$value" =~ ^[0-9]+$ ]] || value=100
    ((value < 50)) && value=50
    ((value > 100)) && value=100
    printf '%s\n' "$value"
}

yesno() {
    if "$@" > /dev/null 2>&1; then printf 'true'; else printf 'false'; fi
}

state_json() {
    local path limit

    if path=$(attr); then
        limit=$(< "$path")
        printf '{"supported":true,"writable":%s,"backend":"sysfs","limit":%d}\n' \
            "$(yesno test -w "$path")" "$(clamp "$limit")"
    elif command -v framework_tool > /dev/null 2>&1; then
        limit=$(sudo -n framework_tool --charge-limit 2> /dev/null | grep -oE '[0-9]+' | head -1)
        printf '{"supported":true,"writable":%s,"backend":"framework","limit":%d}\n' \
            "$(yesno sudo -n true)" "$(clamp "$limit")"
    else
        printf '{"supported":false,"writable":false,"backend":"none","limit":100}\n'
    fi
}

write_attr() {
    local path="$1" value="$2"

    if [[ -w "$path" ]]; then
        printf '%s\n' "$value" > "$path"
    else
        printf '%s\n' "$value" | sudo -n tee "$path" > /dev/null
    fi
}

set_limit() {
    local value path start
    value=$(clamp "$1")

    if path=$(attr); then
        start="${path%end_threshold}start_threshold"
        if [[ -e "$start" ]] && (($(< "$start") >= value)); then
            write_attr "$start" "$((value > 55 ? value - 5 : 50))" || return 1
        fi
        write_attr "$path" "$value" || return 1
    elif command -v framework_tool > /dev/null 2>&1; then
        sudo -n framework_tool --charge-limit "$value" > /dev/null 2>&1 || return 1
    else
        return 1
    fi
}

setup() {
    sudo tee "$rule" > /dev/null <<RULE
ACTION=="add|change", SUBSYSTEM=="power_supply", KERNEL=="BAT*", RUN+="/bin/sh -c 'for a in charge_control_end_threshold charge_control_start_threshold; do test -e /sys%p/\$a && chgrp $group /sys%p/\$a && chmod 0664 /sys%p/\$a; done'"
RULE
    sudo udevadm control --reload

    # Framework boards refuse to bind cros_charge_control unless told otherwise
    if ! attr > /dev/null && modinfo -p cros_charge_control 2> /dev/null | grep -q probe_with_fwk_charge_control; then
        printf 'options cros_charge_control probe_with_fwk_charge_control=1\n' | sudo tee "$modconf" > /dev/null
        sudo modprobe -r cros_charge_control 2> /dev/null
        sudo modprobe cros_charge_control
        udevadm settle
    fi

    sudo udevadm trigger --subsystem-match=power_supply
    udevadm settle

    if attr > /dev/null; then
        echo "ready: $(attr)"
    elif ! command -v framework_tool > /dev/null 2>&1; then
        echo "this kernel exposes no charge_control_end_threshold; install framework-system to use framework_tool instead"
        return 1
    fi
}

case "$1" in
    set) set_limit "$2" ;;
    setup) setup ;;
    *) state_json ;;
esac
