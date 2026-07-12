#!/bin/bash

MIC_VOLUME=$(osascript -e 'input volume of (get volume settings)')

source "$HOME/.config/sketchybar/icons.sh"

if [[ $MIC_VOLUME -eq 0 ]]; then
  sketchybar -m --set mic icon=$MUTEMIC
elif [[ $MIC_VOLUME -gt 0 ]]; then
  sketchybar -m --set mic icon=$MIC
fi
