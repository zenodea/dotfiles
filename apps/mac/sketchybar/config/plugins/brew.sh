#!/bin/bash

source "$HOME/.config/sketchybar/colors.sh"

# sketchybar ignores SIGCHLD, and the disposition survives exec. Homebrew forks
# via IO.popen and reads $?, which stays nil when children are auto-reaped, so a
# plain `brew` here dies on "undefined method 'success?' for nil". Restore the
# default handler for brew only.
COUNT=$(perl -e '$SIG{CHLD} = "DEFAULT"; exec @ARGV' brew outdated | wc -l | tr -d ' ')

COLOR=$RED

case "$COUNT" in
[3-5][0-9])
  COLOR=$ORANGE
  ;;
[1-2][0-9])
  COLOR=$YELLOW
  ;;
[1-9])
  COLOR=$WHITE
  ;;
0)
  COLOR=$GREEN
  COUNT=􀆅
  ;;
esac

sketchybar --set $NAME label=$COUNT icon.color=$COLOR
