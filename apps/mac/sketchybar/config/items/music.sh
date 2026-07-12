#!/bin/bash

# The --subscribe line used to sit inside this array, so sketchybar took it for
# --set properties and the item never subscribed to anything.
#
# update_freq is what actually drives the item now: media_change no longer fires
# on macOS 15.4+ (see plugins/music.sh). The subscription is kept anyway — it
# costs nothing and starts working again the day the event does.
music=(
  script="$PLUGIN_DIR/music.sh"
  click_script="media-control toggle-play-pause"
  label.font="$FONT:Semibold:13.0"
  label.padding_right=8
  label.max_chars=25
  label.align=left
  padding_right=16
  scroll_texts=on
  update_freq=3
  drawing=off
)

# The cover is added first so it sits left of the title: left-side items are laid
# out in the order they're added. Its width is set by the plugin, from the actual
# image — artwork is square for music but 16:9 for a video thumbnail.
music_cover=(
  icon.drawing=off
  label.drawing=off
  background.image.scale=1.0
  background.drawing=on
  background.color=$TRANSPARENT
  background.corner_radius=3
  padding_left=6
  padding_right=0
  drawing=off
)

sketchybar --add item music.cover left \
  --set music.cover "${music_cover[@]}" \
  \
  --add item music left \
  --set music "${music[@]}" \
  --subscribe music media_change system_woke
