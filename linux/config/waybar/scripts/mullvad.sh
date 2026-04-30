#!/bin/bash

ICON_ON=$(printf '')
ICON_OFF=$(printf '')

STATUS=$(mullvad status 2>/dev/null)

case "$1" in
  toggle)
    if echo "$STATUS" | grep -q "^Connected"; then
      mullvad disconnect
    else
      mullvad connect
    fi
    ;;
  *)
    if echo "$STATUS" | grep -q "^Connected"; then
      RELAY=$(echo "$STATUS" | grep "Relay:" | sed 's/.*Relay:[[:space:]]*//')
      LOCATION=$(echo "$STATUS" | grep "Visible location:" | sed 's/.*Visible location:[[:space:]]*//')
      echo "{\"text\": \"$ICON_ON\", \"tooltip\": \"$RELAY — $LOCATION\", \"class\": \"connected\"}"
    elif echo "$STATUS" | grep -q "^Connecting"; then
      echo "{\"text\": \"$ICON_OFF\", \"tooltip\": \"Connecting...\", \"class\": \"connecting\"}"
    else
      echo "{\"text\": \"$ICON_OFF\", \"tooltip\": \"Disconnected\", \"class\": \"disconnected\"}"
    fi
    ;;
esac
