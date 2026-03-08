status_bracket=(
  background.color=$BACKGROUND_1
  background.border_color=$BACKGROUND_2
  background.border_width=2
)

sketchybar --add item net right \
  --set net script="$PLUGIN_DIR/network.sh" \
  updates=on \
  label.drawing=off \
  --subscribe net wifi_change

sketchybar --add bracket status brew github.bell volume_icon mic net \
  --set status "${status_bracket[@]}"
