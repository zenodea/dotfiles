# Firefox — userChrome/userContent live in the default profile's chrome/ dir,
# and the prefs that enable them live in user.js. Firefox reads all three only
# at startup, so it's restarted, but only if something actually changed.
#
# The active theme add-on is swapped to Firefox's built-in Light or Dark: that,
# not user.js, is what moves browser.theme.{toolbar,content}-theme. Only one
# theme can be active, so this does turn off any third-party one.

PROFILE=""
DERIVED_PREFS=(browser.theme.content-theme browser.theme.toolbar-theme)

if [[ "$THEME_APPEARANCE" == "light" ]]; then
  FF_THEME_ID="firefox-compact-light@mozilla.org"
else
  FF_THEME_ID="firefox-compact-dark@mozilla.org"
fi

firefox_running() { pgrep -x firefox >/dev/null 2>&1; }

find_profile() {
  local base=""
  if [[ -f "$HOME/.mozilla/firefox/profiles.ini" ]]; then
    base="$HOME/.mozilla/firefox"
  elif [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox/profiles.ini" ]]; then
    # Firefox on Linux moved new installs to XDG paths
    base="${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox"
  elif [[ -f "$HOME/Library/Application Support/Firefox/profiles.ini" ]]; then
    base="$HOME/Library/Application Support/Firefox"
  else
    return 1
  fi

  local rel
  rel=$(awk '/^\[Install/{found=1; next} found && /^Default=/{sub(/^Default=/, ""); print; exit}' \
    "$base/profiles.ini" 2>/dev/null)
  [[ -n "$rel" && -d "$base/$rel" ]] || return 1

  PROFILE="$base/$rel"
}

state() {
  cat "$PROFILE/chrome/userChrome.css" \
    "$PROFILE/chrome/userContent.css" \
    "$PROFILE/user.js" 2>/dev/null | cksum
}

# Returns 1 when the key wasn't there, so callers can report what they removed.
del_pref() { # del_pref <prefs file> <key>
  local file="$1" key="$2"
  grep -q "\"$key\"" "$file" 2>/dev/null || return 1
  sed -i.bak "/user_pref(\"$key\",/d" "$file"
  rm -f "$file.bak"
}

set_pref() {
  local key="$1" val="$2" userjs="$PROFILE/user.js"
  if grep -q "\"$key\"" "$userjs" 2>/dev/null; then
    # -i.bak works with both GNU and BSD sed; bare -i doesn't
    sed -i.bak "s|user_pref(\"$key\",.*);|user_pref(\"$key\", $val);|" "$userjs"
    rm -f "$userjs.bak"
  else
    echo "user_pref(\"$key\", $val);" >>"$userjs"
  fi
}

# Which theme is active lives in extensions.json, Firefox's add-on database; the
# pref only mirrors it. Exactly one theme carries active/!userDisabled, so
# enabling ours means disabling the rest.
#
# Exit codes: 0 nothing left to do, 10 a change is needed (check only),
# 3 theme not installed, 4 database unreadable.
theme_addon() { # theme_addon <check|apply>
  python3 - "$PROFILE/extensions.json" "$FF_THEME_ID" "$1" <<'PY'
import json, os, sys, tempfile

db, want, mode = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(db, encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    sys.exit(4)

themes = [a for a in data.get("addons", []) if a.get("type") == "theme"]
if not any(a.get("id") == want for a in themes):
    sys.exit(3)

changed = False
for a in themes:
    on = a.get("id") == want
    if a.get("active") is not on or a.get("userDisabled") is on:
        a["active"], a["userDisabled"] = on, not on
        changed = True

if not changed:
    sys.exit(0)
if mode == "check":
    sys.exit(10)

# Write via a temp file in the same dir: a half-written add-on database would
# cost the user every extension they have.
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(db), suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh, separators=(",", ":"))
    os.replace(tmp, db)
except Exception:
    os.path.exists(tmp) and os.unlink(tmp)
    raise
PY
}

has_derived_prefs() {
  local key
  for key in "${DERIVED_PREFS[@]}"; do
    grep -q "\"$key\"" "$PROFILE/prefs.js" 2>/dev/null && return 0
  done
  return 1
}

# Firefox recomputes these only when a theme is enabled through the add-on
# manager, which swapping the database directly skips — so a value already in
# prefs.js sticks, including one an older version of this script wrote.
clean_derived_prefs() {
  local key found=0
  for key in "${DERIVED_PREFS[@]}"; do
    del_pref "$PROFILE/prefs.js" "$key" && found=1
  done
  [[ "$found" == 1 ]] && note "cleared stale browser.theme.* from prefs.js"
  return 0
}

# Everything that may only be done with Firefox stopped, in one place.
apply_offline() {
  local rc=0
  theme_addon apply || rc=$?
  case $rc in
  0) ;;
  3) skip "no built-in $THEME_APPEARANCE theme in this Firefox" ;;
  *) skip "could not update extensions.json" ;;
  esac
  clean_derived_prefs
}

CHANGED=0

render() {
  if ! find_profile; then
    skip "no Firefox profile found"
    return 0
  fi

  local before
  before="$(state)"

  generate userChrome.css "$PROFILE/chrome/userChrome.css"
  generate userContent.css "$PROFILE/chrome/userContent.css"

  # systemUsesDarkTheme is a boolean; content-override uses 0=dark, 1=light.
  local sys_dark=1 light=0
  if [[ "$THEME_APPEARANCE" == "light" ]]; then
    sys_dark=0 light=1
  fi

  set_pref "toolkit.legacyUserProfileCustomizations.stylesheets" "true"
  set_pref "ui.systemUsesDarkTheme" "$sys_dark"
  set_pref "layout.css.prefers-color-scheme.content-override" "$light"
  set_pref "browser.startup.page" "3"
  set_pref "extensions.activeThemeID" "\"$FF_THEME_ID\""

  set_pref "font.name.sans-serif.x-western" "\"$FONT_TEXT_FAMILY\""
  set_pref "font.name.monospace.x-western" "\"$FONT_MONO_FAMILY\""

  # These are Firefox's to compute from the active add-on; a copy written here
  # only outlives the theme it came from.
  local key
  for key in "${DERIVED_PREFS[@]}"; do
    del_pref "$PROFILE/user.js" "$key" || true
  done
  note "wrote: user.js (userChrome + $THEME_APPEARANCE mode + session restore)"

  [[ "$(state)" != "$before" ]] && CHANGED=1

  # Stale derived prefs can only be cleared with Firefox down, so on their own
  # they're reason enough to owe a restart even when nothing else moved.
  has_derived_prefs && CHANGED=1

  if ! have python3; then
    skip "python3 not found — Firefox theme add-on left alone"
    return 0
  fi

  # Firefox flushes the add-on database on exit, so writing it under a running
  # instance is overwritten — owe a restart and let reload() do it after.
  if firefox_running; then
    local rc=0
    theme_addon check || rc=$?
    case $rc in
    0) ;;
    10)
      CHANGED=1
      note "theme add-on: $THEME_APPEARANCE (applied on restart)"
      ;;
    3) skip "no built-in $THEME_APPEARANCE theme in this Firefox" ;;
    *) skip "could not read extensions.json" ;;
    esac
  else
    apply_offline
    note "theme add-on: $THEME_APPEARANCE"
  fi

  return 0
}

restarting() {
  [[ -n "$PROFILE" && "$CHANGED" == 1 ]] && firefox_running
}

# Wait out the flush-on-exit, so the instance we just killed can't clobber the
# add-on database we're about to write.
await_exit() {
  local i=0
  while ((i++ < 20)); do
    firefox_running || return 0
    sleep 0.5
  done
  return 1
}

launch_linux() { firefox &>/dev/null & }
launch_mac() { open -a Firefox; }

reload() {
  restarting || return 0
  pkill -x firefox
  if await_exit; then
    apply_offline
  else
    skip "Firefox did not exit — theme add-on left alone"
  fi
  "launch_$PLATFORM"
  note "restarted"
}
