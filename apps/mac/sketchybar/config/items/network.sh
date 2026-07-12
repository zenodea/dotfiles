status_bracket=(
  background.color=$BACKGROUND_1
  background.border_color=$BACKGROUND_2
  background.border_width=2
)

net=(
  script="$PLUGIN_DIR/network.sh"
  click_script="open 'x-apple.systempreferences:com.apple.wifi-settings-extension'"
  updates=on
  label.drawing=off
  popup.align=center
)

sketchybar --add item net right \
  --set net "${net[@]}" \
  --subscribe net wifi_change \
  mouse.entered \
  mouse.exited \
  mouse.exited.global \
  \
  --add item net.ssid popup.net \
  --set net.ssid "${popup_row[@]}" icon=$NET_WIFI label="-" \
  \
  --add item net.ip popup.net \
  --set net.ip "${popup_row[@]}" icon=$NET_IP label="-" \
  \
  --add item net.security popup.net \
  --set net.security "${popup_row[@]}" icon=$NET_LOCK label="-"

sketchybar --add bracket status brew github.bell volume_icon mic net \
  --set status "${status_bracket[@]}"
