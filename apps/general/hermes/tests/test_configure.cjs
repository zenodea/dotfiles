'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { afterEach, test } = require('node:test');

const ROOT = path.resolve(__dirname, '../../../..');
const APP_DIR = path.resolve(__dirname, '..');
const CONFIGURE = path.join(APP_DIR, 'configure.cjs');
const THEMES = path.join(ROOT, 'themes');
const REAL_HERMES_REPO = path.join(os.homedir(), '.hermes', 'hermes-agent');
const COLOR_NAMES = [
  'BG', 'SURFACE', 'BG_ALT', 'BORDER', 'MUTED', 'FG', 'FG_BRIGHT',
  'ACCENT', 'BLUE', 'RED', 'GREEN', 'YELLOW', 'ORANGE', 'PURPLE'
];
const BASE_PALETTE = {
  BG: '101218', SURFACE: '171a22', BG_ALT: '242936', BORDER: '394151',
  MUTED: '7f899d', FG: 'd9dfeb', FG_BRIGHT: 'ffffff', ACCENT: '8aadf4',
  BLUE: '7dc4e4', RED: 'ed8796', GREEN: 'a6da95', YELLOW: 'eed49f',
  ORANGE: 'f5a97f', PURPLE: 'c6a0f6', THEME_NAME: 'fixture', THEME_APPEARANCE: 'dark'
};
const temporaryRoots = [];

function fixture(config = 'display:\n  skin: default\n') {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'dotfiles-hermes-test-'));
  temporaryRoots.push(root);
  const home = path.join(root, 'home');
  const hermesHome = path.join(home, '.hermes');
  const cache = path.join(root, 'cache');
  fs.mkdirSync(hermesHome, { recursive: true });
  if (config !== null) fs.writeFileSync(path.join(hermesHome, 'config.yaml'), config, { mode: 0o600 });
  return { root, home, hermesHome, cache };
}

afterEach(() => {
  for (const root of temporaryRoots.splice(0)) fs.rmSync(root, { recursive: true, force: true });
});

function environment(target, palette = BASE_PALETTE, overrides = {}) {
  return {
    ...process.env,
    ...palette,
    HOME: target.home,
    XDG_CACHE_HOME: target.cache,
    HERMES_HOME: target.hermesHome,
    HERMES_REPO: REAL_HERMES_REPO,
    APP_DIR,
    ...overrides
  };
}

function run(command, args, env) {
  return spawnSync(command, args, { env, encoding: 'utf8', timeout: 20_000 });
}

function runConfigure(target, command, palette = BASE_PALETTE, overrides = {}) {
  return run(process.execPath, [CONFIGURE, command], environment(target, palette, overrides));
}

function runApp(target, palette = BASE_PALETTE, reload = true, overrides = {}) {
  const script = `
set -e
have() { command -v "$1" >/dev/null 2>&1; }
note() { printf 'NOTE:%s\\n' "$1"; }
skip() { printf 'SKIP:%s\\n' "$1"; }
source "$APP_DIR/app.sh"
render
${reload ? 'reload' : ':'}
`;
  return run('bash', ['-c', script], environment(target, palette, overrides));
}

function activeSkin(target, profile = 'default') {
  const home = profile === 'default' ? target.hermesHome : path.join(target.hermesHome, 'profiles', profile);
  return path.join(home, 'skins', 'dotfiles.yaml');
}

function configPath(target, profile = 'default') {
  return profile === 'default'
    ? path.join(target.hermesHome, 'config.yaml')
    : path.join(target.hermesHome, 'profiles', profile, 'config.yaml');
}

function stagedSkin(target) {
  return path.join(target.cache, 'dotfiles', 'hermes', 'dotfiles.yaml');
}

function loadThemePalette(file) {
  const script = `
set -a
source "$1"
set +a
: "\${MUTED:=\${FG}}"
printf '%s\\0' ${COLOR_NAMES.map(name => `"\${${name}}"`).join(' ')}
`;
  const result = spawnSync('bash', ['-c', script, 'theme-fixture', file], { encoding: 'buffer' });
  assert.equal(result.status, 0, result.stderr.toString());
  const values = result.stdout.toString().split('\0');
  values.pop();
  const palette = Object.fromEntries(COLOR_NAMES.map((name, index) => [name, values[index]]));
  const name = path.basename(file, '.sh');
  palette.THEME_NAME = name;
  palette.THEME_APPEARANCE = name.endsWith('-light') ? 'light' : 'dark';
  return palette;
}

function assertFailed(result, pattern) {
  assert.notEqual(result.status, 0, `expected failure, got stdout: ${result.stdout}`);
  assert.match(result.stderr, pattern);
  assert.doesNotMatch(result.stderr, /api[_-]?key|super-secret/i);
}

test('all 28 named palettes stage through the actual app hook without active writes', () => {
  const themeFiles = fs.readdirSync(THEMES)
    .filter(name => name.endsWith('.sh'))
    .sort();
  assert.equal(themeFiles.length, 28);

  for (const name of themeFiles) {
    const target = fixture('# palette fixture\ndisplay:\n  skin: default\n');
    const original = fs.readFileSync(configPath(target), 'utf8');
    const result = runApp(target, loadThemePalette(path.join(THEMES, name)), false);
    assert.equal(result.status, 0, `${name}: ${result.stderr}`);
    assert.match(result.stdout, /staged Hermes palette for 1 config/);
    assert.equal(fs.readFileSync(configPath(target), 'utf8'), original, name);
    assert.equal(fs.existsSync(activeSkin(target)), false, name);
    assert.match(fs.readFileSync(stagedSkin(target), 'utf8'), /name: dotfiles/);
  }
});

test('publish writes the complete seed palette and preserves config bytes and comments', () => {
  const source = '# keep this comment\napi_key: super-secret\ndisplay:\n  skin: "default" # keep inline\n  density: compact\nother: true\n';
  const target = fixture(source);
  fs.chmodSync(configPath(target), 0o640);
  const result = runApp(target);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /native watcher handles live updates/);

  const expected = source.replace('"default"', 'dotfiles');
  assert.equal(fs.readFileSync(configPath(target), 'utf8'), expected);
  assert.equal(fs.statSync(configPath(target)).mode & 0o777, 0o640);
  const backup = `${configPath(target)}.dotfiles-theme.bak`;
  assert.equal(fs.readFileSync(backup, 'utf8'), source);
  assert.equal(fs.statSync(backup).mode & 0o777, 0o600);

  const skin = fs.readFileSync(activeSkin(target), 'utf8');
  assert.match(skin, /^# Generated by dotfiles Hermes palette integration/);
  const expectedTokens = {
    background: BASE_PALETTE.BG, ui_text: BASE_PALETTE.FG, ui_accent: BASE_PALETTE.ACCENT,
    ui_border: BASE_PALETTE.BORDER, banner_dim: BASE_PALETTE.MUTED, ui_error: BASE_PALETTE.RED,
    ui_ok: BASE_PALETTE.GREEN, ui_warn: BASE_PALETTE.YELLOW,
    completion_menu_bg: BASE_PALETTE.SURFACE,
    completion_menu_current_bg: BASE_PALETTE.BG_ALT,
    status_bar_bg: BASE_PALETTE.BG, status_bar_critical: BASE_PALETTE.RED,
    shell_dollar: BASE_PALETTE.BLUE, session_border: BASE_PALETTE.BORDER
  };
  for (const [token, color] of Object.entries(expectedTokens)) {
    assert.match(skin, new RegExp(`  ${token}: "#${color}"`));
  }
});

test('root and safe existing profiles publish; unrelated and symlink profiles are skipped', () => {
  const target = fixture('root: yes\n');
  const profiles = path.join(target.hermesHome, 'profiles');
  fs.mkdirSync(path.join(profiles, 'coding-teacher'), { recursive: true });
  fs.mkdirSync(path.join(profiles, 'Uppercase'), { recursive: true });
  fs.mkdirSync(path.join(profiles, 'no-config'), { recursive: true });
  fs.writeFileSync(configPath(target, 'coding-teacher'), 'display:\n  layout: wide\n');
  fs.writeFileSync(path.join(profiles, 'Uppercase', 'config.yaml'), 'display:\n  skin: untouched\n');
  const outside = path.join(target.root, 'outside');
  fs.mkdirSync(outside);
  fs.writeFileSync(path.join(outside, 'config.yaml'), 'display:\n  skin: outside\n');
  fs.symlinkSync(outside, path.join(profiles, 'linked'));

  const result = runApp(target);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /for 2 config/);
  assert.match(fs.readFileSync(configPath(target), 'utf8'), /display:\n  skin: dotfiles\n$/);
  assert.match(fs.readFileSync(configPath(target, 'coding-teacher'), 'utf8'), /  skin: dotfiles/);
  assert.equal(fs.readFileSync(path.join(profiles, 'Uppercase', 'config.yaml'), 'utf8'), 'display:\n  skin: untouched\n');
  assert.equal(fs.readFileSync(path.join(outside, 'config.yaml'), 'utf8'), 'display:\n  skin: outside\n');
  assert.equal(fs.existsSync(activeSkin(target, 'coding-teacher')), true);
});

test('repeat publish preserves active mtimes; a new palette updates only skin data', async () => {
  const target = fixture('display:\n  skin: default\n');
  let result = runApp(target);
  assert.equal(result.status, 0, result.stderr);
  const skinPath = activeSkin(target);
  const backupPath = `${configPath(target)}.dotfiles-theme.bak`;
  const first = {
    skin: fs.statSync(skinPath, { bigint: true }).mtimeNs,
    config: fs.statSync(configPath(target), { bigint: true }).mtimeNs,
    backup: fs.statSync(backupPath, { bigint: true }).mtimeNs
  };

  await new Promise(resolve => setTimeout(resolve, 20));
  result = runApp(target);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.statSync(skinPath, { bigint: true }).mtimeNs, first.skin);
  assert.equal(fs.statSync(configPath(target), { bigint: true }).mtimeNs, first.config);
  assert.equal(fs.statSync(backupPath, { bigint: true }).mtimeNs, first.backup);

  await new Promise(resolve => setTimeout(resolve, 20));
  const next = { ...BASE_PALETTE, BG: '223344', ACCENT: 'abcdef', THEME_NAME: 'next-palette' };
  result = runApp(target, next);
  assert.equal(result.status, 0, result.stderr);
  assert.notEqual(fs.statSync(skinPath, { bigint: true }).mtimeNs, first.skin);
  assert.equal(fs.statSync(configPath(target), { bigint: true }).mtimeNs, first.config);
  assert.equal(fs.statSync(backupPath, { bigint: true }).mtimeNs, first.backup);
  assert.match(fs.readFileSync(skinPath, 'utf8'), /background: "#223344"/);
  assert.match(fs.readFileSync(skinPath, 'utf8'), /ui_accent: "#abcdef"/);
});

test('missing config, installation, or parser skips without creating user or cache directories', () => {
  const missingHome = fixture(null);
  fs.rmdirSync(missingHome.hermesHome);
  let env = environment(missingHome);
  delete env.HERMES_REPO;
  let result = run('bash', ['-c', `have(){ command -v "$1" >/dev/null; }; note(){ :; }; skip(){ printf 'SKIP:%s\\n' "$1"; }; source "$APP_DIR/app.sh"; render`], env);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /no Hermes config found/);
  assert.equal(fs.existsSync(missingHome.hermesHome), false);
  assert.equal(fs.existsSync(missingHome.cache), false);

  const noInstall = fixture();
  env = environment(noInstall);
  delete env.HERMES_REPO;
  result = run('bash', ['-c', `have(){ command -v "$1" >/dev/null; }; note(){ :; }; skip(){ printf 'SKIP:%s\\n' "$1"; }; source "$APP_DIR/app.sh"; render`], env);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /installation not found/);
  assert.equal(fs.existsSync(noInstall.cache), false);

  const noParser = fixture();
  fs.mkdirSync(path.join(noParser.hermesHome, 'hermes-agent'));
  env = environment(noParser);
  delete env.HERMES_REPO;
  result = run('bash', ['-c', `have(){ command -v "$1" >/dev/null; }; note(){ :; }; skip(){ printf 'SKIP:%s\\n' "$1"; }; source "$APP_DIR/app.sh"; render`], env);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /YAML parser not found/);
  assert.equal(fs.existsSync(noParser.cache), false);
});

test('invalid palette, theme name, and appearance are rejected before staging', () => {
  const cases = [
    [{ ...BASE_PALETTE, BG: '#123456' }, /palette variable BG/],
    [{ ...BASE_PALETTE, FG: '12345g' }, /palette variable FG/],
    [{ ...BASE_PALETTE, THEME_NAME: '../escape' }, /THEME_NAME is invalid/],
    [{ ...BASE_PALETTE, THEME_APPEARANCE: 'sepia' }, /THEME_APPEARANCE/]
  ];
  for (const [palette, message] of cases) {
    const target = fixture();
    const result = runApp(target, palette, false);
    assertFailed(result, message);
    assert.equal(fs.existsSync(target.cache), false);
  }
});

test('malformed, duplicate, alias, and ambiguous configs fail without leaking content', () => {
  const cases = [
    ['api_key: super-secret\ndisplay: [\n', /malformed/],
    ['api_key: super-secret\ndisplay:\n  skin: one\n  skin: two\n', /duplicate/],
    ['base: &base\n  skin: default\ndisplay: *base\n', /aliases|anchors/],
    ['api_key: super-secret\ndisplay: disabled\n', /display must be a mapping/],
    ['display: { density: compact }\n', /flow-style/]
  ];
  for (const [config, message] of cases) {
    const target = fixture(config);
    const result = runApp(target, BASE_PALETTE, false);
    assertFailed(result, message);
    assert.equal(fs.existsSync(target.cache), false);
    assert.equal(fs.readFileSync(configPath(target), 'utf8'), config);
  }
});

test('missing display, missing skin, implicit null display, and implicit null skin use minimal structural edits', () => {
  const cases = [
    ['one: 1\n', 'one: 1\ndisplay:\n  skin: dotfiles\n'],
    ['display:\n  density: compact\nother: 2\n', 'display:\n  density: compact\n  skin: dotfiles\nother: 2\n'],
    ['display:\nother: 2\n', 'display:\n  skin: dotfiles\nother: 2\n'],
    ['display:\n  skin: # retain\n  density: compact\n', 'display:\n  skin: dotfiles # retain\n  density: compact\n']
  ];
  for (const [config, expected] of cases) {
    const target = fixture(config);
    const result = runApp(target);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(configPath(target), 'utf8'), expected);
  }
});

test('unsafe transform shapes are refused without staging or active writes', () => {
  const cases = [
    ['display:\n    rich: true\nmodel: x\n', /indentation is not supported/],
    ['{model: x}\n', /flow-style root maps/],
    ['display:\n  skin: |\n    default\n  rich: true\nmodel: x\n', /block-scalar/],
    ['display: null\nmodel: x\n', /explicit null/],
    ['display: ~\nwrongname: x\n', /explicit null/]
  ];

  for (const [config, message] of cases) {
    const target = fixture(config);
    const result = runApp(target);
    assertFailed(result, message);
    assert.equal(fs.readFileSync(configPath(target), 'utf8'), config);
    assert.equal(fs.existsSync(stagedSkin(target)), false);
    assert.equal(fs.existsSync(activeSkin(target)), false);
    assert.equal(fs.existsSync(`${configPath(target)}.dotfiles-theme.bak`), false);
  }
});

test('publish preflights transformed YAML for every profile before all active writes', () => {
  const rootConfig = '# root retained\ndisplay:\n  skin: default\nmodel: root\n';
  const profileConfig = '# profile retained\ndisplay:\n  skin: default\nmodel: news\n';
  const invalidProfile = 'display:\n  skin: |\n    default\n  rich: true\nmodel: news\n';
  const target = fixture(rootConfig);
  fs.mkdirSync(path.dirname(configPath(target, 'news')), { recursive: true });
  fs.writeFileSync(configPath(target, 'news'), profileConfig);

  let result = runApp(target, BASE_PALETTE, false);
  assert.equal(result.status, 0, result.stderr);
  fs.writeFileSync(configPath(target, 'news'), invalidProfile);
  const manifestPath = path.join(target.cache, 'dotfiles', 'hermes', 'stage.json');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  manifest.targets.find(entry => entry.profile === 'news').configSha256 =
    crypto.createHash('sha256').update(invalidProfile).digest('hex');
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

  result = runConfigure(target, 'publish');
  assertFailed(result, /block-scalar/);
  assert.equal(fs.readFileSync(configPath(target), 'utf8'), rootConfig);
  assert.equal(fs.readFileSync(configPath(target, 'news'), 'utf8'), invalidProfile);
  assert.equal(fs.existsSync(activeSkin(target)), false);
  assert.equal(fs.existsSync(activeSkin(target, 'news')), false);
  assert.equal(fs.existsSync(`${configPath(target)}.dotfiles-theme.bak`), false);
  assert.equal(fs.existsSync(`${configPath(target, 'news')}.dotfiles-theme.bak`), false);
});

test('a config change after staging blocks every publish target', () => {
  const target = fixture('display:\n  skin: default\n');
  fs.mkdirSync(path.dirname(configPath(target, 'news')), { recursive: true });
  fs.writeFileSync(configPath(target, 'news'), 'display:\n  skin: default\n');
  let result = runApp(target, BASE_PALETTE, false);
  assert.equal(result.status, 0, result.stderr);
  fs.appendFileSync(configPath(target, 'news'), '# concurrent change\n');
  result = runConfigure(target, 'publish');
  assertFailed(result, /config changed since staging/);
  assert.equal(fs.existsSync(activeSkin(target)), false);
  assert.equal(fs.existsSync(activeSkin(target, 'news')), false);
  assert.equal(fs.existsSync(`${configPath(target)}.dotfiles-theme.bak`), false);
});

test('an unrelated dotfiles.yaml is never overwritten', () => {
  const target = fixture();
  fs.mkdirSync(path.dirname(activeSkin(target)));
  fs.writeFileSync(activeSkin(target), 'name: personal\ncolors: {}\n');
  const before = fs.readFileSync(activeSkin(target), 'utf8');
  const result = runApp(target);
  assertFailed(result, /not owned by dotfiles/);
  assert.equal(fs.readFileSync(activeSkin(target), 'utf8'), before);
  assert.equal(fs.readFileSync(configPath(target), 'utf8'), 'display:\n  skin: default\n');
  assert.equal(fs.existsSync(`${configPath(target)}.dotfiles-theme.bak`), false);
});

test('config symlinks and hardlinks are rejected', () => {
  const symlinked = fixture(null);
  const external = path.join(symlinked.root, 'external-config.yaml');
  fs.writeFileSync(external, 'display:\n  skin: external\n');
  fs.symlinkSync(external, configPath(symlinked));
  let result = runApp(symlinked, BASE_PALETTE, false);
  assertFailed(result, /safe regular file/);
  assert.equal(fs.readFileSync(external, 'utf8'), 'display:\n  skin: external\n');

  const linked = fixture();
  const second = path.join(linked.root, 'second-link.yaml');
  fs.linkSync(configPath(linked), second);
  result = runApp(linked, BASE_PALETTE, false);
  assertFailed(result, /safe regular file/);
  assert.equal(fs.readFileSync(second, 'utf8'), 'display:\n  skin: default\n');
});

test('Hermes and cache parent symlink routes are rejected without touching targets', () => {
  const hermesRoute = fixture(null);
  const externalHome = path.join(hermesRoute.root, 'external-hermes-home');
  fs.mkdirSync(path.join(externalHome, '.hermes'), { recursive: true });
  fs.writeFileSync(path.join(externalHome, '.hermes', 'config.yaml'), 'display:\n  skin: external\n');
  fs.symlinkSync(externalHome, path.join(hermesRoute.home, 'linked-home'));
  let result = runApp(hermesRoute, BASE_PALETTE, false, {
    HERMES_HOME: path.join(hermesRoute.home, 'linked-home', '.hermes')
  });
  assertFailed(result, /HERMES_HOME route is not safe/);
  assert.equal(fs.readFileSync(path.join(externalHome, '.hermes', 'config.yaml'), 'utf8'), 'display:\n  skin: external\n');

  const cacheRoute = fixture();
  const externalCache = path.join(cacheRoute.root, 'external-parent');
  fs.mkdirSync(externalCache);
  const linkedParent = path.join(cacheRoute.home, 'linked-cache');
  fs.symlinkSync(externalCache, linkedParent);
  result = runApp(cacheRoute, BASE_PALETTE, false, {
    XDG_CACHE_HOME: path.join(linkedParent, 'cache')
  });
  assertFailed(result, /cache route is not safe/);
  assert.deepEqual(fs.readdirSync(externalCache), []);
});

test('skin, backup, and staging symlink routes are rejected without touching targets', () => {
  const skinLink = fixture();
  let result = runApp(skinLink, BASE_PALETTE, false);
  assert.equal(result.status, 0, result.stderr);
  const externalSkin = path.join(skinLink.root, 'external-skin.yaml');
  fs.writeFileSync(externalSkin, 'external skin\n');
  fs.mkdirSync(path.dirname(activeSkin(skinLink)));
  fs.symlinkSync(externalSkin, activeSkin(skinLink));
  result = runConfigure(skinLink, 'publish');
  assertFailed(result, /safe regular file/);
  assert.equal(fs.readFileSync(externalSkin, 'utf8'), 'external skin\n');

  const backupLink = fixture();
  result = runApp(backupLink, BASE_PALETTE, false);
  assert.equal(result.status, 0, result.stderr);
  const externalBackup = path.join(backupLink.root, 'external-backup');
  fs.writeFileSync(externalBackup, 'external backup\n');
  fs.symlinkSync(externalBackup, `${configPath(backupLink)}.dotfiles-theme.bak`);
  result = runConfigure(backupLink, 'publish');
  assertFailed(result, /config backup is not a safe regular file/);
  assert.equal(fs.readFileSync(externalBackup, 'utf8'), 'external backup\n');
  assert.equal(fs.existsSync(activeSkin(backupLink)), false);

  const stageLink = fixture();
  const externalDirectory = path.join(stageLink.root, 'external-cache');
  fs.mkdirSync(externalDirectory, { recursive: true });
  fs.mkdirSync(stageLink.cache, { recursive: true });
  fs.symlinkSync(externalDirectory, path.join(stageLink.cache, 'dotfiles'));
  result = runApp(stageLink, BASE_PALETTE, false);
  assertFailed(result, /cache directory is not a safe directory/);
  assert.deepEqual(fs.readdirSync(externalDirectory), []);
});

test('hardlinked active skin, staged files, and backup are rejected', () => {
  const target = fixture();
  let result = runApp(target, BASE_PALETTE, false);
  assert.equal(result.status, 0, result.stderr);

  fs.mkdirSync(path.dirname(activeSkin(target)));
  fs.copyFileSync(stagedSkin(target), activeSkin(target));
  fs.linkSync(activeSkin(target), path.join(target.root, 'skin-link'));
  result = runConfigure(target, 'publish');
  assertFailed(result, /active skin is not a safe regular file/);
  assert.equal(fs.readFileSync(configPath(target), 'utf8'), 'display:\n  skin: default\n');

  const staged = fixture();
  result = runApp(staged, BASE_PALETTE, false);
  assert.equal(result.status, 0, result.stderr);
  fs.linkSync(stagedSkin(staged), path.join(staged.root, 'stage-link'));
  result = runConfigure(staged, 'publish');
  assertFailed(result, /staged skin is not a safe regular file/);

  const backup = fixture();
  result = runApp(backup, BASE_PALETTE, false);
  assert.equal(result.status, 0, result.stderr);
  const backupPath = `${configPath(backup)}.dotfiles-theme.bak`;
  fs.copyFileSync(configPath(backup), backupPath);
  fs.linkSync(backupPath, path.join(backup.root, 'backup-link'));
  result = runConfigure(backup, 'publish');
  assertFailed(result, /config backup is not a safe regular file/);
  assert.equal(fs.existsSync(activeSkin(backup)), false);
});

test('stage preflights both owned outputs before changing either one', () => {
  const target = fixture();
  let result = runApp(target, BASE_PALETTE, false);
  assert.equal(result.status, 0, result.stderr);
  const originalSkin = fs.readFileSync(stagedSkin(target), 'utf8');
  const manifest = path.join(target.cache, 'dotfiles', 'hermes', 'stage.json');
  fs.writeFileSync(manifest, '{"owner":"someone-else"}\n');

  const next = { ...BASE_PALETTE, BG: '334455', THEME_NAME: 'next' };
  result = runApp(target, next, false);
  assertFailed(result, /stage manifest is not owned by dotfiles/);
  assert.equal(fs.readFileSync(stagedSkin(target), 'utf8'), originalSkin);
});
