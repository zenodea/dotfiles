#!/usr/bin/env sh

. "$CONFIG_DIR/icons.sh"

# Hover first: the sleep below would otherwise stall the popup for a second
# every time the cursor crossed the icon.
case "$SENDER" in
  mouse.entered)
    dev=$(route get default 2> /dev/null | awk '/interface:/ { print $2 }')

    # networksetup can't read the SSID on macOS 15+ without Location Services;
    # ipconfig's summary still reports it.
    summary=$(ipconfig getsummary "$dev" 2> /dev/null)
    ssid=$(echo "$summary" | awk -F' SSID : ' '/ SSID : / { print $2; exit }')
    security=$(echo "$summary" | awk -F' Security : ' '/ Security : / { print $2; exit }')
    ip=$(ipconfig getifaddr "$dev" 2> /dev/null)

    sketchybar --set net.ssid label="${ssid:-not connected}" \
      --set net.ip label="${ip:-no address}" \
      --set net.security label="${security:-none}" \
      --set net popup.drawing=on
    exit 0
    ;;
  mouse.exited | mouse.exited.global)
    sketchybar --set net popup.drawing=off
    exit 0
    ;;
esac

# When switching between devices, it's possible to get hit with multiple
# concurrent events, some of which may occur before `scutil` picks up the
# changes, resulting in race conditions.
sleep 1

services=$(networksetup -listnetworkserviceorder)
device=$(scutil --nwi | sed -n "s/.*Network interfaces: \([^,]*\).*/\1/p")

test -n "$device" && service=$(echo "$services" |
  sed -n "s/.*Hardware Port: \([^,]*\), Device: $device.*/\1/p")

color=$FG1
case $service in
"iPhone USB") icon=$NET_USB ;;
"Thunderbolt Bridge") icon=$NET_THUNDERBOLT ;;

Wi-Fi)
  ssid=$(networksetup -getairportnetwork "$device" |
    sed -n "s/Current Wi-Fi Network: \(.*\)/\1/p")
  case $ssid in
  *iPhone*) icon=$NET_HOTSPOT ;;
  "")
    icon=$NET_DISCONNECTED
    color=$FG2
    ;;
  *) icon=$NET_WIFI ;;
  esac
  ;;

*)
  wifi_device=$(echo "$services" |
    sed -n "s/.*Hardware Port: Wi-Fi, Device: \([^\)]*\).*/\1/p")
  test -n "$wifi_device" && status=$(
    networksetup -getairportpower "$wifi_device" | awk '{print $NF}'
  )
  icon=$(test "$status" = On && echo "$NET_DISCONNECTED" || echo "$NET_OFF")
  color=$FG2
  ;;
esac

sketchybar --animate sin 5 --set "$NAME" icon="$icon" icon.color="$color"
