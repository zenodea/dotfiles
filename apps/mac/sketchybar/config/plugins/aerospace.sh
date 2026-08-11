#!/usr/bin/env bash

source "$CONFIG_DIR/colors.sh"

# Refreshes all workspace items in one sketchybar call. Runs on
# aerospace_workspace_change (which sets FOCUSED_WORKSPACE), display_change,
# and the forced update at startup — the fallback query covers the last two.
FOCUSED="${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused)}"

# This aerospace version has no %{workspace-is-empty}, so non-empty
# workspaces come from a second query. Padded with spaces for exact matching.
NONEMPTY=" $(aerospace list-workspaces --monitor all --empty no | tr '\n' ' ') "

args=()
while IFS='|' read -r sid monitor visible; do
  item="space.$sid"
  if [ "$sid" = "$FOCUSED" ]; then
    args+=(--set "$item" drawing=on display="$monitor" \
      background.drawing=on background.color="$GREEN" label.color="$BLACK")
  elif [ "$visible" = "true" ]; then
    # Visible on another monitor (each monitor shows one workspace).
    args+=(--set "$item" drawing=on display="$monitor" \
      background.drawing=on background.color="$BACKGROUND_2" label.color="$WHITE")
  elif [[ "$NONEMPTY" == *" $sid "* ]]; then
    args+=(--set "$item" drawing=on display="$monitor" \
      background.drawing=off label.color="$GREY")
  else
    args+=(--set "$item" drawing=off)
  fi
done < <(aerospace list-workspaces --all --format '%{workspace}|%{monitor-appkit-nsscreen-screens-id}|%{workspace-is-visible}')

sketchybar "${args[@]}"
