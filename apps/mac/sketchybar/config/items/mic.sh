#!/bin/bash

# This carried a stray `sketchybar` word mid-command, which sketchybar parsed as
# a bogus item name, and quoted "~" paths for its scripts.
mic=(
  script="$PLUGIN_DIR/mic.sh"
  click_script="$PLUGIN_DIR/mic_click.sh"
  update_freq=3
  popup.align=center
)

sketchybar --add item mic right \
  --set mic "${mic[@]}" \
  --subscribe mic mouse.entered \
  mouse.exited \
  mouse.exited.global \
  \
  --add item mic.level popup.mic \
  --set mic.level "${popup_row[@]}" icon=$MIC label="-" \
  \
  --add item mic.hint popup.mic \
  --set mic.hint "${popup_row[@]}" icon=$MIC_HINT label="right-click: settings"
