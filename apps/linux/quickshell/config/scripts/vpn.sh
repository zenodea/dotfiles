#!/usr/bin/env bash

state_json() {
    if ! command -v mullvad > /dev/null 2>&1; then
        printf '{"state":"absent","relay":"","location":"","city":""}\n'
        return
    fi

    local status
    status=$(mullvad status -v 2> /dev/null)
    [[ -z "$status" ]] && status=$(mullvad status 2> /dev/null)

    if [[ -z "$status" ]]; then
        printf '{"state":"down","relay":"","location":"","city":""}\n'
    elif [[ "$status" == Connected* ]]; then
        local relay location city
        relay=$(sed -n 's/.*Relay:[[:space:]]*//p' <<< "$status" | head -1)
        location=$(sed -n 's/.*Visible location:[[:space:]]*//p' <<< "$status" | head -1)
        [[ -z "$relay" ]] && relay=$(sed -n 's/^Connected to \([^ ]*\).*/\1/p' <<< "$status" | head -1)
        [[ -z "$location" ]] && location=$(sed -n 's/^Connected to [^ ]* in \(.*\)/\1/p' <<< "$status" | head -1)
        location=${location%%. *}
        location=${location%.}
        city=$location
        [[ "$city" == *,* ]] && city=${city##*, }
        printf '{"state":"connected","relay":"%s","location":"%s","city":"%s"}\n' "$relay" "$location" "$city"
    elif [[ "$status" == Connecting* ]]; then
        printf '{"state":"connecting","relay":"","location":"","city":""}\n'
    else
        printf '{"state":"disconnected","relay":"","location":"","city":""}\n'
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
