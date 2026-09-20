#!/usr/bin/env bash

state_json() {
    if ! command -v mullvad > /dev/null 2>&1; then
        printf '{"state":"absent","relay":"","location":""}\n'
        return
    fi

    local status
    status=$(mullvad status 2>/dev/null)

    if [[ -z "$status" ]]; then
        printf '{"state":"down","relay":"","location":""}\n'
    elif [[ "$status" == Connected* ]]; then
        local relay location
        relay=$(sed -n 's/.*Relay:[[:space:]]*//p' <<< "$status" | head -1)
        location=$(sed -n 's/.*Visible location:[[:space:]]*//p' <<< "$status" | head -1)
        printf '{"state":"connected","relay":"%s","location":"%s"}\n' "$relay" "$location"
    elif [[ "$status" == Connecting* ]]; then
        printf '{"state":"connecting","relay":"","location":""}\n'
    else
        printf '{"state":"disconnected","relay":"","location":""}\n'
    fi
}

case "$1" in
    toggle)
        if mullvad status 2> /dev/null | grep -q '^Connected'; then
            mullvad disconnect
        else
            mullvad connect
        fi
        ;;
    watch)
        while true; do
            state_json
            sleep 2
        done
        ;;
    *) state_json ;;
esac
