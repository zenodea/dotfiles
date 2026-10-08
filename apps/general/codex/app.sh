render() {
  local codex_home="${CODEX_HOME:-$HOME/.codex}"
  have codex || [[ -d "$codex_home" ]] || return 0
  mkdir -p "$codex_home"

  mkdir -p "$codex_home/themes"
  substitute < "$DOTFILES/themes/templates/dotfiles.tmTheme" > "$codex_home/themes/dotfiles.tmTheme"
  note "wrote: $(pretty "$codex_home/themes/dotfiles.tmTheme")"

  python3 - "$codex_home/config.toml" "$APP_DIR/settings.toml" <<'PY'
import os
import re
import sys
import tomllib
from pathlib import Path

config_path, wanted_path = Path(sys.argv[1]), Path(sys.argv[2])
wanted = tomllib.loads(wanted_path.read_text())
text = config_path.read_text() if config_path.exists() else ""
try:
    current = tomllib.loads(text)
except tomllib.TOMLDecodeError as exc:
    raise SystemExit(f"invalid TOML in {config_path}: {exc}")

source = {}
table = ""
for line in wanted_path.read_text().splitlines():
    header = re.match(r"\[([^\]]+)\]\s*$", line)
    if header:
        table = header.group(1)
    elif re.match(r"[A-Za-z0-9_-]+\s*=", line):
        source[(table, line.split("=", 1)[0].strip())] = line

HEADER = re.compile(r"\s*\[")
lines = text.splitlines()
changed = False

def section(name):
    """Line range holding `name`'s own keys; the top level is name == ""."""
    if not name:
        end = next((i for i, line in enumerate(lines) if HEADER.match(line)), len(lines))
        return 0, end
    try:
        start = next(i for i, line in enumerate(lines) if line.strip() == f"[{name}]")
    except StopIteration:
        lines.extend(["", f"[{name}]"])
        return len(lines), len(lines)
    end = next((i for i in range(start + 1, len(lines)) if HEADER.match(lines[i])), len(lines))
    return start + 1, end

for (name, key), line in source.items():
    have = current.get(name, {}) if name else current
    want = wanted.get(name, {}) if name else wanted
    if key in have and have[key] == want[key]:
        continue
    start, end = section(name)
    at = next((i for i in range(start, end) if re.match(rf"{re.escape(key)}\s*=", lines[i])), None)
    if at is None:
        while end > start and not lines[end - 1].strip():
            end -= 1
        lines.insert(end, line)
    else:
        lines[at] = line
    changed = True

if changed:
    merged = "\n".join(lines) + "\n"
    tomllib.loads(merged)
    tmp = config_path.with_suffix(".toml.tmp")
    tmp.write_text(merged)
    os.replace(tmp, config_path)
PY
  note "ensured: $(pretty "$codex_home/config.toml") settings"

  local role
  mkdir -p "$codex_home/agents"
  for role in "$APP_DIR"/agents/*.toml; do
    [[ -f "$role" ]] && link "$role" "$codex_home/agents/$(basename "$role")"
  done

  local agents="$codex_home/AGENTS.md"
  python3 - "$agents" \
    "adhd=$APP_DIR/../pi/rules/adhd.md" "delegation=$APP_DIR/delegation.md" <<'PY'
import sys
from pathlib import Path

agents = Path(sys.argv[1])
text = agents.read_text() if agents.exists() else ""
merged = text
for spec in sys.argv[2:]:
    name, source = spec.split("=", 1)
    source = Path(source)
    if not source.is_file():
        continue
    START, END = f"<!-- dotfiles:{name}:start -->", f"<!-- dotfiles:{name}:end -->"
    block = f"{START}\n{source.read_text().strip()}\n{END}"
    if START in merged and END in merged:
        head, rest = merged.split(START, 1)
        merged = head + block + rest.split(END, 1)[1]
    else:
        merged = (merged.rstrip() + "\n\n" if merged.strip() else "") + block + "\n"
if merged != text:
    agents.write_text(merged)
PY
  note "ensured: $(pretty "$agents") reply style, delegation"
}
