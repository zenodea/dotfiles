#!/usr/bin/env bash

# Get the current workspace
FOCUSED_WORKSPACE=$(aerospace list-workspaces --focused)

# Update SketchyBar with the current workspace name
sketchybar --set aerospace_workspace label="$FOCUSED_WORKSPACE"
