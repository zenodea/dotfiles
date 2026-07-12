#!/bin/bash

# macOS 15.4 locked down the MediaRemote framework that sketchybar's
# media_change event reads, so on anything newer that event fires once at launch
# and never again (upstream issue #708) — the $INFO this used to parse arrives
# empty forever. media-control reaches the same now-playing service through a
# signed adapter that still works, so poll that instead. It's player-agnostic:
# Music, Spotify and browser tabs all report through it.

ART_DIR="${TMPDIR:-/tmp}/sketchybar-art"
ART_HEIGHT=22

hide() {
  sketchybar --set music drawing=off --set music.cover drawing=off
  exit 0
}

command -v media-control > /dev/null 2>&1 || hide

INFO="$(media-control get 2> /dev/null)"

TITLE="$(echo "$INFO" | jq -r '.title // empty' 2> /dev/null)"
ARTIST="$(echo "$INFO" | jq -r '.artist // empty' 2> /dev/null)"
PLAYING="$(echo "$INFO" | jq -r '.playing // false' 2> /dev/null)"

# Nothing holds the now-playing slot — hide rather than leave a stale track in
# the bar.
[ -z "$TITLE" ] && [ -z "$ARTIST" ] && hide

if [ "$PLAYING" = "true" ]; then
  ICON=􀊄
else
  ICON=􀊆
fi

LABEL="$TITLE"
[ -n "$ARTIST" ] && [ -n "$TITLE" ] && LABEL="$ARTIST — $TITLE"

sketchybar --set music drawing=on icon="$ICON" label="$LABEL"

# --- artwork ----------------------------------------------------------------
#
# The artwork arrives as base64 on every poll, but decoding and rescaling it
# three times a minute for a track that hasn't changed is pure waste — so it's
# cached under a key derived from the track, and only rebuilt when that changes.
# sketchybar draws background.image at its natural size, so the image is resized
# on the way in rather than scaled at draw time.

mkdir -p "$ART_DIR"

KEY="$(printf '%s' "${TITLE}${ARTIST}" | md5 -q)"
COVER="$ART_DIR/$KEY.jpg"

if [ ! -f "$COVER" ]; then
  RAW="$ART_DIR/$KEY.raw"
  echo "$INFO" | jq -r '.artworkData // empty' 2> /dev/null | base64 -d > "$RAW" 2> /dev/null

  if [ -s "$RAW" ]; then
    sips --resampleHeight "$ART_HEIGHT" "$RAW" --out "$COVER" > /dev/null 2>&1
    # Whatever else is cached is for a track that is no longer playing.
    find "$ART_DIR" -type f ! -name "$KEY.jpg" -delete 2> /dev/null
  fi
  rm -f "$RAW"
fi

if [ -s "$COVER" ]; then
  WIDTH="$(sips -g pixelWidth "$COVER" 2> /dev/null | awk '/pixelWidth/ { print $2 }')"
  sketchybar --set music.cover drawing=on \
    background.image="$COVER" \
    background.image.scale=1.0 \
    background.drawing=on \
    width="$((${WIDTH:-$ART_HEIGHT} + 4))"
else
  # Plenty of sources publish a title with no artwork at all.
  sketchybar --set music.cover drawing=off
fi
