#!/bin/bash

# Shared item styling, sourced by sketchybarrc after colors.sh and icons.sh so
# every item file can reuse it.

# A row inside a hover popup. sketchybar has no tooltips, so a popup of these,
# toggled on mouse.entered/mouse.exited, is what stands in for one. The fixed
# label width keeps the popup from resizing as values change under the cursor.
popup_row=(
  icon.font="$FONT:Semibold:12.0"
  icon.padding_left=10
  icon.padding_right=6
  icon.color=$GREY
  label.font="$FONT:Regular:12.0"
  label.color=$LABEL_COLOR
  label.padding_right=10
  label.align=left
  label.width=150
  background.padding_left=0
  background.padding_right=0
)
