render() {
  local claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  have claude || [[ -d "$claude_dir" ]] || return 0
  mkdir -p "$claude_dir/output-styles" "$claude_dir/agents" "$claude_dir/themes"

  local rules="$APP_DIR/../pi/rules/adhd.md"
  if [[ -f "$rules" ]]; then
    {
      printf '%s\n' '---' 'name: ADHD' \
        'description: Result first, progress restated, one next step, no tangents' \
        'keep-coding-instructions: true' '---' ''
      cat "$rules"
    } >"$claude_dir/output-styles/adhd.md"
    note "wrote: $(pretty "$claude_dir/output-styles/adhd.md")"
  fi

  local agent
  for agent in "$APP_DIR"/agents/*.md; do
    [[ -f "$agent" ]] && link "$agent" "$claude_dir/agents/$(basename "$agent")"
  done
  link "$APP_DIR/CLAUDE.md" "$claude_dir/CLAUDE.md"
  link "$APP_DIR/keybindings.json" "$claude_dir/keybindings.json"

  python3 "$APP_DIR/theme.py" "$claude_dir/themes/dotfiles.json" "${THEME_APPEARANCE:-dark}"
  note "wrote: $(pretty "$claude_dir/themes/dotfiles.json")"

  python3 - "$claude_dir/settings.json" "$APP_DIR/settings.json" \
    "$APP_DIR/statusline.sh" "custom:dotfiles" <<'PY'
import json
import os
import sys
from pathlib import Path

settings_path, wanted_path, statusline, theme = sys.argv[1:5]
settings_path = Path(settings_path)
try:
    data = json.loads(settings_path.read_text()) if settings_path.exists() else {}
except json.JSONDecodeError as exc:
    raise SystemExit(f"invalid JSON in {settings_path}: {exc}")
before = json.dumps(data, sort_keys=True)

wanted = json.loads(Path(wanted_path).read_text())
wanted["statusLine"] = {"type": "command", "command": statusline}
wanted["theme"] = theme

for key, value in wanted.items():
    if key != "permissions":
        data[key] = value
deny = data.setdefault("permissions", {}).setdefault("deny", [])
deny.extend(rule for rule in wanted.get("permissions", {}).get("deny", []) if rule not in deny)

if json.dumps(data, sort_keys=True) != before:
    tmp = settings_path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    os.replace(tmp, settings_path)
PY
  note "ensured: $(pretty "$claude_dir/settings.json") settings"
}
