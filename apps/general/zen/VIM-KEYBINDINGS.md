# Vim keybindings in Zen

## Findings

- **No built-in Vim mode.** Zen's supported feature is rebinding individual browser actions under **Settings → Keyboard Shortcuts** (`about:keyboard` works in 1.24.2b). The shortcut editor rejects unmodified letters and records only one chord, so it cannot express `j` or `gg`. Keep native bindings for workspaces and splits; for example, the Linux defaults for previous/next workspace are `Ctrl+Alt+←/→` in the matching source (the manual lists older defaults). [Zen manual][zen-doc] [1.24.2b keyboard test][about-keys] [1.24.3b recorder test][editor-test] [Recorder][editor] [Workspace keys][zen-keys]
- **Start with Vimium for Firefox** (Mozilla listing `vimium-ff`, displayed as “Vimium”). Zen supports add-ons from Mozilla. Vimium gives you `hjkl`, `gg`/`G`, link hints (`f`/`F`), `/` search, and tab commands, with remappable keys. [Zen extensions guide][extensions] [Vimium README][vimium] [Mozilla listing][amo]
- **Alternatives:** [Tridactyl][tri] adds a `:` command line and `.tridactylrc` support. [Vimium C][vimium-c] adds context-specific mappings and configurable shortcut commands. Neither gives you a native Vim mode for Zen's UI.

## Important limits

Vimium's page bindings don't control the address bar, Zen sidebar, or menus. They also don't run on protected pages such as `about:addons` or the built-in PDF viewer, and `addons.mozilla.org` is restricted by default. Test on a regular website, not the install page. [Mozilla content-script limits][limits]

**Vertical tabs:** Vimium maps `J`/`gT` to previous tab and `K`/`gt` to next. Zen users reported `J` moving up on 1.13.2b. If the direction feels backward on your setup, swap the uppercase keys in Vimium's custom mappings: [Vimium source][vimium-maps] [Zen issue #9423][vertical-issue]

```text
map J nextTab
map K previousTab
```

Lowercase `j`/`k` still scroll the page. Tab ordering across workspaces, Essentials and pinned tabs was not tested.

## Vim keys for Zen's actual UI

[ZenLeap][zenleap] is an unofficial script that adds `j`/`k` for sidebar tabs, `h`/`l` for workspaces, `gg`/`G`, and an optional modal address bar. It runs with full browser privileges, unlike a normal page add-on. ZenLeap 3.5.0 was tested upstream on Zen 1.22.3b and has an open bulk-tab-close bug on 1.24. [ZenLeap release][zenleap-release] [ZenLeap issue #55][zenleap-issue]

ZenLeap's documented manual loader installs `config.js`, which is also managed by this repo's [Zen theme installer](app.sh). Don't copy the loader over it without planning how both scripts would coexist. A simpler default is **Vimium for pages + Zen's shortcuts for the browser UI**.

Checked against installed **1.24.2b** (package source read only) and latest release **1.24.3b** as of 2026-11-19. Nothing was installed or tested in the running browser. [Zen release][release]

[zen-doc]: https://docs.zen-browser.app/user-manual/shortcuts
[about-keys]: https://github.com/zen-browser/desktop/blob/1.24.2b/src/zen/tests/kbs/browser_about_keyboard.js#L23-L27
[editor-test]: https://github.com/zen-browser/desktop/blob/1.24.3b/src/zen/tests/settings/browser_settings_shortcuts.js#L108-L135
[editor]: https://github.com/zen-browser/desktop/blob/1.24.3b/src/zen/settings/sections/ZenSettingsShortcuts.mjs#L401-L444
[zen-keys]: https://github.com/zen-browser/desktop/blob/1.24.2b/src/browser/base/content/zen-keysets.inc.xhtml#L16-L35
[extensions]: https://docs.zen-browser.app/user-manual/extensions
[vimium]: https://github.com/philc/vimium#keyboard-bindings
[amo]: https://addons.mozilla.org/firefox/addon/vimium-ff/
[tri]: https://github.com/tridactyl/tridactyl#highlighted-features
[vimium-c]: https://github.com/gdh1995/vimium-c
[limits]: https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Content_scripts#permissions_restrictions_and_limitations
[vimium-maps]: https://github.com/philc/vimium/blob/master/background_scripts/commands.js#L474-L477
[vertical-issue]: https://github.com/zen-browser/desktop/issues/9423
[zenleap]: https://github.com/yashas-salankimatt/ZenLeap
[zenleap-release]: https://github.com/yashas-salankimatt/ZenLeap/releases/tag/v3.5.0
[zenleap-issue]: https://github.com/yashas-salankimatt/ZenLeap/issues/55
[release]: https://github.com/zen-browser/desktop/releases/tag/1.24.3b
