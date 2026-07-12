#!/bin/bash

export BLACK=0xff${BG}
export WHITE=0xff${FG_BRIGHT}
export RED=0xff${RED}
export GREEN=0xff${GREEN}
export BLUE=0xff${ACCENT}
export YELLOW=0xff${YELLOW}
export ORANGE=0xff${ORANGE}
export MAGENTA=0xff${PURPLE}
export GREY=0xff${BORDER}
export TRANSPARENT=0x00000000

# General bar colors
export BAR_COLOR=0x99${BG}
export ICON_COLOR=$WHITE
export LABEL_COLOR=$WHITE
export BACKGROUND_1=0x90${BG_ALT}
export BACKGROUND_2=0x90${BORDER}
export POPUP_BACKGROUND_COLOR=0xff${BG}
export POPUP_BORDER_COLOR=$WHITE
export SHADOW_COLOR=$BLACK

# Network graph. The fills are the same hue as their line at low alpha, so the
# traces read as tinted areas sitting on the status bracket rather than as two
# opaque blocks pasted over it.
export GRAPH_DOWN=0xff${ACCENT}
export GRAPH_DOWN_FILL=0x40${ACCENT}
export GRAPH_UP=0xff${ORANGE}
export GRAPH_UP_FILL=0x40${ORANGE}
