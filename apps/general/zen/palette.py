"""Validated theme colors for Zen's generated startup stylesheet."""
import argparse
import json
import math
import os
from pathlib import Path
import re
import subprocess

COLORS = ('BG', 'SURFACE', 'BG_ALT', 'BORDER', 'FG', 'FG_BRIGHT', 'ACCENT', 'RED')
HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
NAME = re.compile(r'[a-z0-9][a-z0-9-]{0,63}\Z')


def validate(value):
    if (type(value) is not dict
            or set(value) not in ({'version', 'name', 'appearance', 'colors'},
                                  {'version', 'name', 'appearance', 'colors', 'opacity'})
            or type(value['version']) is not int or value['version'] != 1
            or not isinstance(value['name'], str) or not NAME.fullmatch(value['name'])
            or value['appearance'] not in ('dark', 'light')
            or type(value['colors']) is not dict or set(value['colors']) != set(COLORS)):
        raise ValueError('invalid palette schema')
    colors = {}
    for key in COLORS:
        color = value['colors'][key]
        if not isinstance(color, str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', color):
            raise ValueError('invalid hex color: ' + key)
        colors[key] = color.lower()
    opacity = value.get('opacity', .7 if value['appearance'] == 'dark' else .85)
    # Check type before numeric operations: bool is an int subclass in Python.
    if type(opacity) not in (int, float) or not 0 <= opacity <= 1 or not math.isfinite(opacity):
        raise ValueError('opacity must be a finite number between 0 and 1')
    return dict(version=1, name=value['name'], appearance=value['appearance'],
                colors=colors, opacity=float(opacity))


def encode(value):
    return (json.dumps(validate(value), sort_keys=True, separators=(',', ':')) + '\n').encode()


def from_env(env=os.environ):
    value = dict(version=1, name=env.get('THEME_NAME'),
                 appearance=env.get('THEME_APPEARANCE'),
                 colors={k: '#' + env.get(k, '') for k in COLORS})
    if 'OPACITY' in env:
        value['opacity'] = float(env['OPACITY'])
    return validate(value)


def from_theme(name):
    # Only existing regular, non-symlink repository theme files. Trusted shell code,
    # never a palette-provided path; positional arguments, not shell interpolation.
    if not NAME.fullmatch(name):
        raise ValueError('invalid theme name')
    theme = REPO / 'themes' / (name + '.sh')
    if theme.is_symlink() or not theme.is_file():
        raise ValueError('theme is not an allowlisted repository file')
    script = '''set -e
source "$1/lib/common.sh"
set -a
source "$1/themes/$2.sh"
THEME_NAME="$2"
THEME_APPEARANCE="$(appearance_of "$BG")"
if [[ "$THEME_APPEARANCE" == light ]]; then
    OPACITY="${OPACITY:-0.85}"
else
    OPACITY="${OPACITY:-0.7}"
fi
exec "$3" "$4" env-json
'''
    result = subprocess.run(['/bin/bash', '-c', script, 'zen-palette', str(REPO), name,
                             os.sys.executable, str(HERE / 'palette.py')],
                            capture_output=True, timeout=10, check=True,
                            env={'PATH': '/usr/bin:/bin', 'HOME': os.environ['HOME'],
                                 **({'OPACITY': os.environ['OPACITY']} if 'OPACITY' in os.environ else {})})
    return validate(json.loads(result.stdout))


def cache_dir():
    return Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'dotfiles/zen'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['env-json'])
    parser.parse_args()
    print(encode(from_env()).decode(), end='')


if __name__ == '__main__':
    main()
