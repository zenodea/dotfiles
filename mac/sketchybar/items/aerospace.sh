#!/bin/bash

sketchybar --add event aerospace_workspace_change

# Add a single item for the current workspace
sketchybar --add item aerospace_workspace left \
  --subscribe aerospace_workspace aerospace_workspace_change \
  --set aerospace_workspace \
  label.color=$WHITE \
  label.font="$FONT:Black:14.0" \
  label.width=20 \
  script="$CONFIG_DIR/plugins/aerospace.sh"
