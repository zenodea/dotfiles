# Pi — the palette renders as a pi theme named "dotfiles", which pi hot-reloads
# from ~/.pi/agent/themes, so a running session re-themes itself.
# No third-party packages: everything pi loads beyond itself is in extensions/ here.

render() {
  local agent_dir="$HOME/.pi/agent"
  mkdir -p "$agent_dir/extensions"
  generate theme.json "$agent_dir/themes/dotfiles.json"

  # Rendered, not linked: pi writes lastChangelogVersion into settings.json.
  python3 - "$agent_dir/settings.json" <<'PY'
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    current = json.loads(path.read_text()) if path.exists() else {}
except json.JSONDecodeError as exc:
    raise SystemExit(f"invalid JSON in {path}: {exc}")

rendered = {
    "theme": "dotfiles",
    "quietStartup": True,
    "collapseChangelog": True,
    "defaultProvider": "openai",
    "defaultModel": "gpt-6.1-sol",
    "modelThinkingLevels": {"openai/gpt-6.1-sol": "xhigh", "openai/gpt-6-luna": "max"},
    # pi's own grep and find, in place of a search package.
    "defaultTools": ["+grep", "+find"],
}
if "lastChangelogVersion" in current:
    rendered = {"lastChangelogVersion": current["lastChangelogVersion"], **rendered}
if rendered != current:
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(rendered, indent=2) + "\n")
    os.replace(tmp, path)
PY

  # adhd.ts reads rules/; ctrl+h/j/k/l keybindings; model overrides; extensions.
  pi_link "$APP_DIR/rules" "$agent_dir/rules"
  pi_link "$APP_DIR/keybindings.json" "$agent_dir/keybindings.json"
  pi_link "$APP_DIR/models.json" "$agent_dir/models.json"
  local item
  for item in "$APP_DIR"/extensions/*; do
    pi_link "$item" "$agent_dir/extensions/$(basename "$item")"
  done
  # Links left behind by extensions deleted from here.
  for item in "$agent_dir"/extensions/*; do
    if [[ -L "$item" && ! -e "$item" ]]; then
      rm "$item"
      note "unlinked: $(pretty "$item")"
    fi
  done
  return 0
}

# pi_link SRC DST: point DST at SRC; anything else already there moves to DST.bak.
pi_link() {
  [[ "$(readlink "$2" 2>/dev/null)" == "$1" ]] && return 0
  if [[ -L "$2" ]]; then
    rm "$2"
  elif [[ -e "$2" ]]; then
    mv "$2" "$2.bak"
  fi
  ln -s "$1" "$2"
  note "linked: $(pretty "$2")"
}

reload() {
  note "run /reload in pi"
}
