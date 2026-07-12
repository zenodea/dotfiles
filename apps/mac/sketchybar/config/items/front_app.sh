#!/bin/bash

FRONT_APP_SCRIPT='sketchybar --set $NAME label="$INFO"'

front_app=(
  script="$FRONT_APP_SCRIPT"
  icon.drawing=on
  padding_left=0
  label.color=$WHITE
  label.font="$FONT:Black:14.0"
  label.width=80
  associated_display=active
)

sketchybar --add event window_focus \
  --add event windows_on_spaces \
  windows_on_spaces \
  mouse.clicked \
  \
  --add item front_app left \
  --set front_app "${front_app[@]}" \
  --subscribe front_app front_app_switched
