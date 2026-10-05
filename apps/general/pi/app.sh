# Pi — the palette renders as a pi theme named "dotfiles", which pi hot-reloads
# from ~/.pi/agent/themes, so a running session re-themes itself.

render() {
  local agent_dir="$HOME/.pi/agent"
  generate theme.json "$agent_dir/themes/dotfiles.json"
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

# npm:@scope/name@1.2.3 and npm:@scope/name are the same package, so a pin on
# either side must not add a second entry.
def name(package):
    if isinstance(package, str) and package.startswith("npm:"):
        head, sep, _ = package[5:].partition("@")
        return package[:5] + head
    return package

present = {name(package) for package in existing}
changed = False
for package in packages:
    if name(package) not in present:
        existing.append(package)
        present.add(name(package))
        changed = True

data["packages"] = existing

# Follow the dotfiles palette (themes/dotfiles.json, rendered above).
if data.get("theme") != "dotfiles":
    data["theme"] = "dotfiles"
    changed = True

if changed or not settings_path.exists():
    tmp_path = settings_path.with_suffix(settings_path.suffix + ".tmp")
    tmp_path.write_text(json.dumps(data, indent=2) + "\n")
    os.replace(tmp_path, settings_path)
PY
    note "ensured: ~/.pi/agent/settings.json packages, theme"
  fi

  # Keybindings: ctrl+h/j/k/l move through pi's lists and the session tree.
  local keys="$APP_DIR/keybindings.json" keys_target="$agent_dir/keybindings.json"
  if [[ -f "$keys" && "$(readlink "$keys_target" 2>/dev/null)" != "$keys" ]]; then
    [[ -e "$keys_target" || -L "$keys_target" ]] && mv "$keys_target" "$keys_target.bak"
    ln -s "$keys" "$keys_target"
    note "linked: ~/.pi/agent/keybindings.json"
  fi

  # Permission policy and its model judge. Seeded once, not linked: both
  # extensions rewrite their own config (toggling yolo, picking a judge model).
  local policy
  for policy in "$APP_DIR"/permissions/*.json; do
    [[ -f "$policy" ]] || continue
    local policy_target="$agent_dir/extensions/$(basename "$policy" .json)/config.json"
    [[ -e "$policy_target" ]] && continue
    mkdir -p "$(dirname "$policy_target")"
    cp "$policy" "$policy_target"
    note "seeded: $(pretty "$policy_target")"
  done

  # Local forks: link each into ~/.pi/agent/team-vendor, where settings.json
  # expects them, and install runtime deps on a machine that has none yet.
  local item name target
  for item in "$APP_DIR/team-vendor"/*/; do
    [[ -d "$item" ]] || continue
    item="${item%/}"
    name="$(basename "$item")"
    target="$agent_dir/team-vendor/$name"
    mkdir -p "$agent_dir/team-vendor"

    if [[ -L "$target" ]]; then
      [[ "$(readlink "$target")" == "$item" ]] || { rm "$target" && ln -s "$item" "$target"; }
    else
      [[ -e "$target" ]] && mv "$target" "$target.bak"
      ln -s "$item" "$target"
      note "linked: ~/.pi/agent/team-vendor/$name"
    fi

    if [[ ! -d "$item/node_modules" ]] && have npm; then
      if (cd "$item" && npm ci --omit=dev >/dev/null 2>&1); then
        note "installed deps: team-vendor/$name"
      else
        note "npm ci failed: team-vendor/$name"
      fi
    fi
  done

  [[ -d "$src" ]] || return 0
  mkdir -p "$dst"

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
