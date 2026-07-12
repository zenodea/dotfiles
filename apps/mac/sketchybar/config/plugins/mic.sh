#!/bin/bash

MIC_VOLUME=$(osascript -e 'input volume of (get volume settings)')

source "$HOME/.config/sketchybar/icons.sh"

case "$SENDER" in
  mouse.entered)
    if [[ $MIC_VOLUME -eq 0 ]]; then
      LEVEL="muted"
    else
      LEVEL="input at ${MIC_VOLUME}%"
    fi
    sketchybar --set mic.level label="$LEVEL" --set mic popup.drawing=on
    exit 0
    ;;
  mouse.exited | mouse.exited.global)
    sketchybar --set mic popup.drawing=off
    exit 0
    ;;
esac

if [[ $MIC_VOLUME -eq 0 ]]; then
  sketchybar -m --set mic icon=$MUTEMIC
elif [[ $MIC_VOLUME -gt 0 ]]; then
  sketchybar -m --set mic icon=$MIC
fi
