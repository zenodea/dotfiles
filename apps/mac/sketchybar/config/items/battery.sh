#!/bin/bash

battery=(
  script="$PLUGIN_DIR/battery.sh"
  click_script="open 'x-apple.systempreferences:com.apple.Battery-Settings.extension'"
  icon.font="$FONT:Regular:19.0"
  padding_right=5
  padding_left=0
  label.drawing=off
  update_freq=120
  updates=on
  popup.align=center
)

sketchybar --add item battery right \
  --set battery "${battery[@]}" \
  --subscribe battery power_source_change \
  system_woke \
  mouse.entered \
  mouse.exited \
  mouse.exited.global \
  \
  --add item battery.charge popup.battery \
  --set battery.charge "${popup_row[@]}" icon=$BATTERY_100 label="-" \
  \
  --add item battery.time popup.battery \
  --set battery.time "${popup_row[@]}" icon=$BATTERY_TIME label="-"
