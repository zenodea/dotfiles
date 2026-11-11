import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from configure import HEADER, IMPORT, LEGACY_IMPORT, PREFS, configure, find_profile, profile_bases, render_css
from palette import HERE, REPO, from_theme

SHELL = r'''
set -e
have() { command -v "$1" >/dev/null 2>&1; }
note() { :; }
skip() { :; }
pgrep() { [[ "$MOCK_RUNNING" == 1 ]] || return 1; printf '123\n'; [[ "$MOCK_MULTIPLE" != 1 ]] || printf '124\n'; }
osascript() {
    while IFS= read -r line; do printf '%s\n' "$line" >> "$HOME/apple-event"; done
    printf 'quit\n' >> "$HOME/actions"
    [[ "$MOCK_QUIT" != cancel ]] || return 1
    [[ "$MOCK_QUIT" == hang ]] || MOCK_RUNNING=0
}
open() { printf 'open %s\n' "$*" >> "$HOME/actions"; }
sleep() { :; }
source "$APP_DIR/app.sh"
render
[[ "$DO_RELOAD" != 1 ]] || "reload_$PLATFORM"
'''


class RestartTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='zen-restart-tests-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        self.base = profile_bases(self.home)[0]
        self.profile = self.base / 'Profiles/own space-é'
        self.profile.mkdir(parents=True)
        (self.base / 'profiles.ini').write_text('[InstallOWN]\nDefault=Profiles/own space-é\n')
        self.marker = self.home / '.cache/dotfiles/zen/restart-needed'
        self.palette = from_theme('dracula')
        self.app = self.home / 'Zen.app'

    def invoke(self, reload=True, running=True, quit='normal', multiple=False, palette=None, platform='mac'):
        p = palette or self.palette
        env = {'PATH': os.environ['PATH'], 'HOME': str(self.home), 'APP_DIR': str(HERE),
               'ZEN_APP': str(self.app), 'PLATFORM': platform,
               'THEME_NAME': p['name'], 'THEME_APPEARANCE': p['appearance'],
               'OPACITY': str(p['opacity']), 'DO_RELOAD': str(int(reload)),
               'MOCK_RUNNING': str(int(running)), 'MOCK_MULTIPLE': str(int(multiple)),
               'MOCK_QUIT': quit}
        env.update({key: color[1:] for key, color in p['colors'].items()})
        return subprocess.run(['/bin/bash', '-c', SHELL], env=env,
                              capture_output=True, text=True, timeout=10)

    def actions(self):
        p = self.home / 'actions'
        return p.read_text() if p.exists() else ''

    def test_all_repository_themes_render_without_extension_or_unresolved_variables(self):
        for file in (REPO / 'themes').glob('*.sh'):
            p = from_theme(file.stem)
            css = render_css(p)
            self.assertTrue(css.startswith(HEADER))
            self.assertNotIn(b'${', css)
            self.assertNotIn(b'[lwtheme]', css)
            self.assertNotIn(b'color-scheme:', css)
            self.assertIn(p['colors']['ACCENT'].encode(), css)
            self.assertIn(b':root:not([privatebrowsingmode])', css)

    def test_mouse_hover_outline_hidden_without_removing_keyboard_focus(self):
        css = render_css(self.palette).decode()
        self.assertIn('--toolbarbutton-outline-color-hover: transparent !important;', css)
        self.assertIn('--toolbarbutton-outline-color-active: transparent !important;', css)
        self.assertNotIn('--focus-outline:', css)
        self.assertNotIn('outline: none', css)
        self.assertNotIn(':focus-visible', css)
        self.assertIn('@-moz-document url("chrome://browser/content/browser.xhtml")', css)

    def test_web_view_rounding_uses_native_radius_without_overriding_fullscreen(self):
        css = render_css(self.palette).decode()
        self.assertIn('--zen-webview-border-radius: calc(16px * var(--zen-squircle-value)) !important;', css)
        self.assertNotIn('--zen-border-radius:', css)
        self.assertNotIn('--toolbarbutton-border-radius:', css)
        self.assertNotIn('border-radius: 16px', css)
        self.assertNotIn('overflow:', css)
        self.assertIn('@-moz-document url("chrome://browser/content/browser.xhtml")', css)

    def test_create_idempotence_preserve_additions_and_opacity_change(self):
        self.assertTrue(configure(self.profile, self.palette, self.marker))
        css = self.profile / 'chrome/dotfiles-theme.css'
        before = css.stat().st_mtime_ns
        (self.profile / 'user.js').write_bytes(PREFS + b'// User addition\n')
        (self.profile / 'chrome/userChrome.css').write_bytes(IMPORT + b'/* User addition */\n')
        self.assertFalse(configure(self.profile, self.palette, self.marker))
        self.assertEqual(css.stat().st_mtime_ns, before)
        self.assertTrue(configure(self.profile, dict(self.palette, opacity=.42), self.marker))
        self.assertIn(b'0.42)', css.read_bytes())
        self.assertTrue((self.profile / 'user.js').read_bytes().endswith(b'// User addition\n'))

    def test_legacy_import_migrates_to_live_aware_import(self):
        chrome = self.profile / 'chrome'
        chrome.mkdir()
        (chrome / 'userChrome.css').write_bytes(LEGACY_IMPORT + b'/* User addition */\n')
        self.assertTrue(configure(self.profile, self.palette, self.marker))
        self.assertEqual((chrome / 'userChrome.css').read_bytes(), IMPORT + b'/* User addition */\n')
        self.assertIn(b'not (-moz-pref("dotfiles.zen.live"))', IMPORT)

    def test_live_loader_changes_without_restart_and_clears_pending_restart(self):
        self.marker.parent.mkdir(parents=True)
        self.marker.write_text('restart\n')
        self.assertTrue(configure(self.profile, self.palette, self.marker, live=True))
        self.assertFalse(self.marker.exists())
        self.assertTrue(configure(self.profile, from_theme('nord-light'), self.marker, live=True))
        self.assertFalse(self.marker.exists())

    def test_loader_installed_into_app_bundle_once(self):
        resources = self.app / 'Contents/Resources'
        resources.mkdir(parents=True)
        self.invoke(running=False).check_returncode()
        for name in ('config.js', 'defaults/pref/config-prefs.js'):
            self.assertEqual((resources / name).read_bytes(), (HERE / 'loader' / name).read_bytes())
        before = (resources / 'config.js').stat().st_mtime_ns
        self.invoke(running=False).check_returncode()
        self.assertEqual((resources / 'config.js').stat().st_mtime_ns, before)

    def test_missing_app_skips_loader(self):
        self.invoke(running=False).check_returncode()
        self.assertFalse(self.app.exists())

    def test_linux_loader_installed_into_install_root(self):
        self.app.mkdir()
        self.invoke(running=False, platform='linux').check_returncode()
        for name in ('config.js', 'defaults/pref/config-prefs.js'):
            self.assertEqual((self.app / name).read_bytes(), (HERE / 'loader' / name).read_bytes())
        self.assertFalse((self.app / 'Contents').exists())

    def test_linux_palette_change_never_quits_or_reopens(self):
        self.invoke(running=False, platform='linux').check_returncode()
        result = self.invoke(palette=from_theme('nord-light'), platform='linux')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.actions(), '')
        self.assertFalse(self.marker.exists())

    def test_unknown_config_conflict_changes_nothing(self):
        prefs = self.profile / 'user.js'
        prefs.write_text('// Existing user configuration\n')
        with self.assertRaises(ValueError):
            configure(self.profile, self.palette, self.marker)
        self.assertEqual(prefs.read_text(), '// Existing user configuration\n')
        self.assertFalse(self.marker.exists())
        self.assertFalse((self.profile / 'chrome').exists())

    def test_symlink_and_invalid_palette_refused(self):
        target = self.home / 'untouched'
        target.write_text('keep')
        (self.profile / 'user.js').symlink_to(target)
        with self.assertRaises(ValueError):
            configure(self.profile, self.palette, self.marker)
        self.assertEqual(target.read_text(), 'keep')
        (self.profile / 'user.js').unlink()
        with self.assertRaises(ValueError):
            configure(self.profile, dict(self.palette, opacity='0;bad'), self.marker)
        self.assertFalse(self.marker.exists())

    def test_profile_discovery_does_not_guess_ambiguous_defaults(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(find_profile(self.home), self.profile)
            with (self.base / 'profiles.ini').open('a') as stream:
                stream.write('[InstallSECOND]\nDefault=Profiles/another\n')
            with self.assertRaises(ValueError):
                find_profile(self.home)

    def test_no_reload_defers_restart_even_for_next_identical_render(self):
        result = self.invoke(reload=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.actions(), '')
        self.assertTrue(self.marker.exists())
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.actions(), f'quit\nopen -a {self.app}\n')
        self.assertFalse(self.marker.exists())
        event = (self.home / 'apple-event').read_text()
        self.assertIn('app.zen-browser.zen', event)
        self.assertIn('with timeout of 10 seconds', event)

    def test_closed_browser_stays_closed_and_identical_theme_does_not_restart(self):
        result = self.invoke(running=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.actions(), '')
        self.assertFalse(self.marker.exists())
        result = self.invoke(running=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.actions(), '')

    def test_actual_palette_change_requests_normal_restart(self):
        self.invoke(running=False).check_returncode()
        self.invoke(palette=from_theme('nord-light')).check_returncode()
        self.assertEqual(self.actions(), f'quit\nopen -a {self.app}\n')

    def test_cancelled_or_hung_quit_never_force_kills_or_reopens(self):
        for outcome in ('cancel', 'hang'):
            with self.subTest(outcome=outcome):
                self.marker.parent.mkdir(parents=True, exist_ok=True)
                self.marker.write_text('restart\n')
                result = self.invoke(quit=outcome)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn('open', self.actions())
                self.assertFalse(self.marker.exists())
        self.assertNotIn('pkill', (HERE / 'app.sh').read_text())
        self.assertNotIn('kill -', (HERE / 'app.sh').read_text())

    def test_multiple_instances_are_left_alone(self):
        result = self.invoke(multiple=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.actions(), '')
        self.assertFalse(self.marker.exists())

    def test_render_failure_cannot_restart_browser(self):
        (self.profile / 'user.js').write_text('// existing')
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.actions(), '')


if __name__ == '__main__':
    unittest.main()
