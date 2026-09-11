render() {
  local agent_dir="$HOME/.pi/agent"
  local src="$APP_DIR/extensions"
  local dst="$agent_dir/extensions"
  local packages="$APP_DIR/packages.txt"
  local settings="$agent_dir/settings.json"

  if [[ -f "$packages" ]]; then
    mkdir -p "$agent_dir"
    python3 - "$settings" "$packages" <<'PY'
import json
import os
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
packages_path = Path(sys.argv[2])

packages = []
for line in packages_path.read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    packages.append(line)

try:
    data = json.loads(settings_path.read_text()) if settings_path.exists() else {}
except json.JSONDecodeError as exc:
    raise SystemExit(f"invalid JSON in {settings_path}: {exc}")

existing = data.get("packages", [])
if not isinstance(existing, list):
    raise SystemExit(f"{settings_path}: packages must be a list")

changed = False
for package in packages:
    if package not in existing:
        existing.append(package)
        changed = True

data["packages"] = existing

if changed or not settings_path.exists():
    tmp_path = settings_path.with_suffix(settings_path.suffix + ".tmp")
    tmp_path.write_text(json.dumps(data, indent=2) + "\n")
    os.replace(tmp_path, settings_path)
PY
    note "ensured: ~/.pi/agent/settings.json packages"
  fi

  [[ -d "$src" ]] || return 0
  mkdir -p "$dst"

  local item name target
  for item in "$src"/*; do
    [[ -e "$item" ]] || continue
    name="$(basename "$item")"
    # Plannotator registers the same --plan flag and Ctrl+Alt+P shortcut.
    # Keep the legacy extension in the repo, but don't auto-link it globally.
    [[ "$name" == "plan-mode" ]] && continue
    target="$dst/$name"

    if [[ -L "$target" ]]; then
      [[ "$(readlink "$target")" == "$item" ]] && continue
      rm "$target"
    elif [[ -e "$target" ]]; then
      mv "$target" "$target.bak"
    fi

    ln -s "$item" "$target"
    note "linked: ~/.pi/agent/extensions/$name"
  done
}

reload() {
  note "run /reload in pi"
}
