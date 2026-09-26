#!/usr/bin/env bash

shopt -s nullglob
caps=(/sys/class/leds/*::capslock/brightness)
nums=(/sys/class/leds/*::numlock/brightness)

last=""
while true; do
    c=0
    for f in "${caps[@]}"; do
        read -r v < "$f" 2> /dev/null
        [[ "$v" == "1" ]] && c=1 && break
    done

    n=0
    for f in "${nums[@]}"; do
        read -r v < "$f" 2> /dev/null
        [[ "$v" == "1" ]] && n=1 && break
    done

    state="{\"caps\":$c,\"num\":$n}"
    if [[ "$state" != "$last" ]]; then
        echo "$state"
        last="$state"
    fi
    sleep 0.3
done
