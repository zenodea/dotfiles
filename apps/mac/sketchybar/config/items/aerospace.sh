#!/bin/bash

sketchybar --add event aerospace_workspace_change

# One item per workspace. The plugin pins each item to the monitor its
# workspace lives on (display=N), so every monitor's bar shows only its own
# workspaces instead of one global focused-workspace label.
for sid in $(aerospace list-workspaces --all); do
  sketchybar --add item space.$sid left \
    --set space.$sid \
    label="$sid" \
    icon.drawing=off \
    label.color=$GREY \
    label.font="$FONT:Black:14.0" \
    label.padding_left=6 \
    label.padding_right=6 \
    label.width=20 \
    label.align=center \
    background.height=20 \
    background.corner_radius=5 \
    background.drawing=off \
    click_script="aerospace workspace $sid"
done

# A single hidden controller refreshes every workspace item in one pass,
# instead of each item shelling out to aerospace on every switch.
# updates=on is required: with drawing=off the default when_shown would
# keep the script from ever running.
sketchybar --add item aerospace_controller left \
  --subscribe aerospace_controller aerospace_workspace_change display_change \
  --set aerospace_controller \
  drawing=off \
  updates=on \
  script="$CONFIG_DIR/plugins/aerospace.sh"
