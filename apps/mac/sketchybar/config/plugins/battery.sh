#!/bin/bash

source "$HOME/.config/sketchybar/icons.sh"
source "$HOME/.config/sketchybar/colors.sh"

# pmset's battery line reads:
#   -InternalBattery-0 (id=…)	51%; discharging; 4:25 remaining present: true
# The time field is "(no estimate)" while it settles, and absent on AC.
case "$SENDER" in
  mouse.entered)
    BATT_LINE=$(pmset -g batt | tail -1)
    PCT=$(echo "$BATT_LINE" | grep -Eo '[0-9]+%')
    STATE=$(echo "$BATT_LINE" | awk -F'; ' '{ print $2 }')
    REMAINING=$(echo "$BATT_LINE" | awk -F'; ' '{ print $3 }' | sed 's/ present: true//')

    case "$REMAINING" in
      *:*) REMAINING="${REMAINING% remaining} remaining" ;;
      *) REMAINING="no estimate yet" ;;
    esac

    sketchybar --set battery.charge label="${PCT} · ${STATE}" \
      --set battery.time label="$REMAINING" \
      --set battery popup.drawing=on
    exit 0
    ;;
  mouse.exited | mouse.exited.global)
    sketchybar --set battery popup.drawing=off
    exit 0
    ;;
esac

PERCENTAGE=$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)
CHARGING=$(pmset -g batt | grep 'AC Power')

if [ $PERCENTAGE = "" ]; then
  exit 0
fi

DRAWING=on
COLOR=$WHITE
case ${PERCENTAGE} in
9[0-9] | 100)
  COLOR=$GREEN
  ICON=$BATTERY_100
  ;;
[6-8][0-9])
  COLOR=$GREEN
  ICON=$BATTERY_75
  ;;
[3-5][0-9])
  ICON=$BATTERY_50
  ;;
[1-2][0-9])
  ICON=$BATTERY_25
  COLOR=$ORANGE
  ;;
*)
  ICON=$BATTERY_0
  COLOR=$RED
  ;;
esac

if [[ $CHARGING != "" ]]; then
  ICON=$BATTERY_CHARGING
  DRAWING=off
fi

sketchybar --set $NAME drawing=$DRAWING icon="$ICON" icon.color=$COLOR
