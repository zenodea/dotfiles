#!/bin/bash

music=(
  script="$PLUGIN_DIR/music.sh"
  label.padding_right=8
  label.font="OperatorMono Nerd Font:Book Italic:15.0"
  padding_right=16
  icon=􁁒
  # drawing=off
  label="Loading…"
  scroll_texts=false
  label.max_chars=15
  label.align=left
  --subscribe music media_change system_woke
)

sketchybar \
  --add item music left \
  --set music "${music[@]}"
