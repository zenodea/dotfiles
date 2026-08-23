#!/usr/bin/env bash
alive="$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"
out=""
grep -qx lazygit <<<"$alive" && out+="#[fg=#${YELLOW}]󰊢 "
grep -qx codex <<<"$alive" && out+="#[fg=#${BLUE}]󰚩 "
grep -qx claude <<<"$alive" && out+="#[fg=#${PURPLE}]󰚩 "
[[ -n "$out" ]] && printf '%s#[fg=#%s]│' "$out" "${BORDER}"
exit 0
