#!/bin/bash

GRAPH_WIDTH=46

# A graph is clipped to its item's background bounds, but only when that
# background is *enabled* — otherwise bar_item.c falls back to the full bar
# height and the trace runs edge to edge. So the background has to be on for
# background.height to inset the plot at all; a transparent color with no border
# keeps it from drawing anything. The bracket supplies the visible box.
net_graph=(
  graph.line_width=2
  icon.drawing=off
  label.drawing=off
  background.drawing=on
  background.color=$TRANSPARENT
  background.border_width=0
  background.height=17
)

# Shared row style from styles.sh, but these two carry numbers rather than
# prose, so they right-align in a narrower column.
graph_popup_row=(
  "${popup_row[@]}"
  label.width=90
  label.align=right
)

# A bracket's bounds swallow its members' padding, so no amount of padding can
# hold this box off the status box beside it — and background.padding_* is inert
# (background_calculate_bounds never reads it). The only thing that separates two
# brackets is an item belonging to neither. Added here, before the graphs, it
# lands between them and the wifi icon.
sketchybar --add item net_spacer right \
  --set net_spacer width=14 \
  background.drawing=off \
  icon.drawing=off \
  label.drawing=off

# net_down is added first, so it lands rightmost: reading left to right, the
# strip runs up-then-down, sitting just left of the wifi icon.
#
# Only net_down carries update_freq — its plugin pushes into both graphs, so
# sampling on net_up too would halve each interval. Both still subscribe to the
# mouse events, since the hover target is the strip as a whole.
sketchybar --add graph net_down right $GRAPH_WIDTH \
  --set net_down "${net_graph[@]}" \
  graph.color=$GRAPH_DOWN \
  graph.fill_color=$GRAPH_DOWN_FILL \
  padding_left=6 \
  padding_right=10 \
  update_freq=2 \
  popup.align=center \
  script="$PLUGIN_DIR/network_graph.sh" \
  --subscribe net_down mouse.entered mouse.exited mouse.exited.global \
  \
  --add graph net_up right $GRAPH_WIDTH \
  --set net_up "${net_graph[@]}" \
  graph.color=$GRAPH_UP \
  graph.fill_color=$GRAPH_UP_FILL \
  padding_left=10 \
  padding_right=6 \
  script="$PLUGIN_DIR/network_graph.sh" \
  --subscribe net_up mouse.entered mouse.exited mouse.exited.global \
  \
  --add item net.download popup.net_down \
  --set net.download "${graph_popup_row[@]}" \
  icon=$NET_DOWN \
  icon.color=$GRAPH_DOWN \
  label="-" \
  \
  --add item net.upload popup.net_down \
  --set net.upload "${graph_popup_row[@]}" \
  icon=$NET_UP \
  icon.color=$GRAPH_UP \
  label="-"

# Its own bracket, styled like the status one next to it: the graphs read as a
# self-contained module sitting beside that cluster instead of dissolving into
# it. net_spacer, above, is what holds the two boxes apart.
network_bracket=(
  background.color=$BACKGROUND_1
  background.border_color=$BACKGROUND_2
  background.border_width=2
  background.corner_radius=9
)

sketchybar --add bracket network net_up net_down \
  --set network "${network_bracket[@]}"
