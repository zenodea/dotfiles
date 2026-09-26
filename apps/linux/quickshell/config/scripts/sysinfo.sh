#!/usr/bin/env bash

interval=2
prev_total=0
prev_idle=0

hwmon=""
for h in /sys/class/hwmon/hwmon*; do
    case "$(cat "$h/name" 2> /dev/null)" in
        coretemp | k10temp | zenpower) hwmon="$h/temp1_input"; break ;;
    esac
done
[[ -z "$hwmon" ]] && hwmon=$(ls /sys/class/hwmon/hwmon*/temp1_input 2> /dev/null | head -1)

while true; do
    read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
    total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    idle_all=$((idle + iowait))
    d_total=$((total - prev_total))
    d_idle=$((idle_all - prev_idle))
    prev_total=$total
    prev_idle=$idle_all
    if ((d_total > 0)); then
        cpu=$(awk "BEGIN{printf \"%.3f\", 1 - $d_idle / $d_total}")
    else
        cpu=0
    fi

    top_name=""
    top_cpu=0
    if awk "BEGIN{exit !($cpu >= 0.4)}"; then
        read -r top_cpu top_name < <(top -bn2 -d0.3 -w 200 | awk '/^top -/ {n++} n == 2 && $1 ~ /^[0-9]+$/ {print int($9), $12; exit}')
        top_name=$(tr -cd '[:alnum:]._+-' <<< "$top_name")
    fi

    mem_total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    mem_avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    mem_used=$((mem_total - mem_avail))
    mem=$(awk "BEGIN{printf \"%.3f\", $mem_used / $mem_total}")

    temp=0
    [[ -n "$hwmon" && -r "$hwmon" ]] && temp=$(($(cat "$hwmon") / 1000))

    read -r disk_used disk_total < <(df -kP / | awk 'NR==2 {print $3, $2}')
    disk=$(awk "BEGIN{printf \"%.3f\", $disk_used / $disk_total}")

    up=$(awk '{printf "%d", $1}' /proc/uptime)

    printf '{"cpu":%s,"mem":%s,"memUsedMb":%d,"memTotalMb":%d,"temp":%d,"disk":%s,"uptime":%d,"top":"%s","topCpu":%d}\n' \
        "$cpu" "$mem" "$((mem_used / 1024))" "$((mem_total / 1024))" "$temp" "$disk" "$up" "$top_name" "${top_cpu:-0}"

    sleep "$interval"
done
