#!/bin/bash

MIC_VOLUME=$(osascript -e 'input volume of (get volume settings)')

source "$HOME/.config/sketchybar/icons.sh"

if [[ $MIC_VOLUME -eq 0 ]]; then
  osascript -e 'set volume input volume 25'
  sketchybar -m --set mic icon=$MIC
elif [[ $MIC_VOLUME -gt 0 ]]; then
  osascript -e 'set volume input volume 0'
  sketchybar -m --set mic icon=$MUTEMIC
fi
