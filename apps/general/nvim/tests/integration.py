#!/usr/bin/env python3
"""Disposable Rex server + real Neovim RPC; never touches the user's sessions."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[4]
CONFIG = ROOT / "apps/general/nvim/config"
LAZYGIT = (ROOT / 'apps/general/lazygit/templates/config.yml').read_text()


def wait_for(check, seconds=8):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(0.05)
    raise AssertionError("Timed out waiting for test state")


with tempfile.TemporaryDirectory(prefix="rex-nvim-test-") as temporary:
    tmp = Path(temporary)
    project = tmp / "project"
    project.mkdir()
    subprocess.run(["git", "init", "-q", str(project)], check=True)
    original = project / "base.lua"
    original.write_text("local value = 1\nreturn value\n")
    target = project / "a 'quoted' | file.lua"
    target.write_text("first\nsecond\nthird\n")
    config = tmp / "config"
    config.mkdir()
    (config / "nvim").symlink_to(CONFIG, target_is_directory=True)
    (config / "lazygit").mkdir()
    (config / "lazygit/config.yml").write_text(re.sub(r'\$\{[A-Z_]+\}', '888888', LAZYGIT))
    env = dict(os.environ, REX_SERVER=f"unix://{tmp}/rex.sock", XDG_CONFIG_HOME=str(config),
               XDG_STATE_HOME=str(tmp / "state"), XDG_DATA_HOME=str(tmp / "data"),
               NVIM_LOG_FILE="/dev/null", PATH=f"{ROOT / 'bin'}:{os.environ['PATH']}")
    for key in ("REX_SESSION", "REX_BLOCK", "NVIM", "TMUX", "NVIM_APPNAME"):
        env.pop(key, None)
    log = (tmp / "server.log").open("w+")
    server = subprocess.Popen(["rex", "server", "run", "--listen", env["REX_SERVER"],
                               "--state-dir", str(tmp / "rex-state"), "--restore=false",
                               "--config", str(ROOT / "apps/general/rex/init.lua")],
                              env=env, stdout=log, stderr=log)

    def rex(*args, stdin=None):
        result = subprocess.run(["rex", "--autostart=false", *args], env=env, input=stdin,
                                text=True, capture_output=True, timeout=12)
        assert result.returncode == 0, (args, result.stdout, result.stderr)
        return json.loads(result.stdout) if result.stdout.strip() else None

    def state():
        return rex("session", "inspect", session, "--json")

    def focused():
        view = state()
        return next(w["focused_block_id"] for w in view["windows"] if w["window_id"] == view["active_window_id"])

    try:
        wait_for(lambda: (tmp / "rex.sock").exists())
        init = tmp / "init.lua"
        init.write_text(f"vim.opt.rtp:prepend({json.dumps(str(CONFIG))})\n"
                        "require('config.rex').setup()\n"
                        f"for _, spec in ipairs(dofile({json.dumps(str(CONFIG / 'lua/plugins/navigation.lua'))})) do\n"
                        "  if spec[1] == 'christoomey/vim-tmux-navigator' then\n"
                        "    for _, key in ipairs(spec.keys) do vim.keymap.set('n', key[1], key[2]) end\n"
                        "  end\nend\n")
        created = rex("new", "Integration test", "-c", str(project), "--json", "--shell=none", "--",
                      "nvim", "-u", str(init), "-n", "-i", "NONE", str(original))
        session = created["session_id"]
        editor = created["initial_windows"][0]["block_ids"][0]
        records = tmp / "state/nvim/rex-edit"
        record = wait_for(lambda: next(iter(records.glob("*.json")), None))
        socket = json.loads(record.read_text())["socket"]
        assert records.stat().st_mode & 0o777 == 0o700

        def remote(expression, endpoint=None):
            result = subprocess.run(["nvim", "--server", endpoint or socket, "--remote-expr", expression],
                                    env=env, text=True, capture_output=True, timeout=6)
            assert result.returncode == 0, result.stderr
            return result.stdout.strip()

        shell = rex("split", "-s", session, "-b", editor, "--split=right", "--focus=false", "--json",
                    "-c", str(project), "--shell=none", "--", "sh")["block_ids"][0]
        remote("execute('vsplit | wincmd h')")
        left_window = remote('win_getid()')
        rex('do', '-s', session, '-b', editor, 'nvim_navigate', 'key=l')
        wait_for(lambda: remote('win_getid()') != left_window)
        assert focused() == editor
        rex('do', '-s', session, '-b', editor, 'nvim_navigate', 'key=l')
        wait_for(lambda: focused() == shell)
        rex('do', '-s', session, '-b', shell, 'nvim_navigate', 'key=l')
        assert focused() == shell, 'the outside edge must not wrap'
        rex('do', '-s', session, '-b', shell, 'nvim_navigate', 'key=h')
        wait_for(lambda: focused() == editor)
        remote("execute('only')")
        print("PASS: Renux-style named actions, real Neovim key delivery, split edges and return from a sibling shell")

        source_env = dict(env, REX_SESSION=session, REX_BLOCK=shell)
        opened = subprocess.run([str(ROOT / "bin/rex-edit"), "+2", "--", str(target)],
                                env=source_env, cwd=project, capture_output=True, text=True, timeout=12)
        assert opened.returncode == 0, (opened.stdout, opened.stderr)
        assert remote('expand("%:p")') == str(target)
        assert remote('line(".")') == "2"
        assert remote('exists("g:hacked")') == "0"
        assert focused() == editor
        print("PASS: actual CLI-to-Neovim RPC, quoted paths, line positioning and pane focus")

        # A fake Pi speaks the real status/paste protocols, without invoking an LLM.
        fake_pi = tmp / "pi.py"
        received = tmp / "received"
        fake_pi.write_text("import os, tty\n"
                           "tty.setraw(0)\n"
                           "os.write(1, b'\\x1b[?2004h\\x1b]7501;state=idle:app=pi\\x1b\\\\')\n"
                           "while True:\n"
                           "    data = os.read(0, 65536)\n"
                           f"    with open({str(received)!r}, 'ab') as f: f.write(data)\n")
        agent = rex("split", "-s", session, "-b", editor, "--focus=false", "--json", "--shell=none", "--",
                    "python3", str(fake_pi))["block_ids"][0]
        wait_for(lambda: rex("block", "call", "-s", session, "-b", agent, "program_status")["records"])
        remote("luaeval(\"require('config.rex').send(1, 2, 'Explain this')\")")
        try:
            data = wait_for(lambda: received.read_bytes() if received.exists() else b"")
        except AssertionError:
            print('EDITOR MESSAGES:', remote('execute("messages")'))
            print('AGENT STATUS:', rex('block', 'call', '-s', session, '-b', agent, 'program_status'))
            print('AGENT MODES:', rex('block', 'call', '-s', session, '-b', agent, 'modes'))
            raise
        assert data.startswith(b"\x1b[200~") and data.endswith(b"\x1b[201~")
        assert b":1-2\n```\nfirst\nsecond\n```\n\nExplain this" in data
        assert b"\r" not in data
        assert focused() == agent
        print("PASS: real Pi discovery, code/question paste and focus, with no Enter submitted")

        # A floating source must move out of the way, and the popup key must reuse it.
        layer = rex("api", "call", "-s", session, "session.new_layer", json.dumps({
            "bounds": [0.1, 0.1, 0.8, 0.8], "focus": True,
            "layout": {"block": {"flavor": "com.superlogical.terminal.shell", "label": "sleep",
                                   "options": {"command": ["sleep", "60"], "shell": "none", "cwd": str(project)}}},
        }))
        popup = layer["block_ids"][0]
        popup_env = dict(source_env, REX_BLOCK=popup)
        result = subprocess.run([str(ROOT / "bin/rex-edit"), str(target)], env=popup_env,
                                cwd=project, capture_output=True, text=True, timeout=12)
        assert result.returncode == 0, (result.stdout, result.stderr)
        def popup_state():
            return next(l for w in state()["windows"] for l in w["layers"] if l["layer_id"] == layer["layer_id"])
        assert popup_state()["state"] == "minimized"
        rex("do", "-s", session, "-b", editor, "popup", "--args", '{"command":["sleep","60"]}', "--json")
        assert popup_state().get("state", "normal") == "normal"
        assert focused() == popup
        print("PASS: popup handoff minimizes without killing the program; reopening reuses it")

        # Use the actual Lazygit config and its edit key, not just the opener directly.
        rex('focus', '-s', session, editor)
        remote(f'execute("buffer {original}")')
        rex('do', '-s', session, '-b', editor, 'popup', '--args', '{"command":["lazygit"]}', '--json')
        def lazygit_layer():
            return next((l for w in state()['windows'] for l in w['layers']
                         if any(b['label'] == 'lazygit' for b in l['blocks'])), None)
        lazygit = wait_for(lazygit_layer)
        lazygit_block = lazygit['blocks'][0]['block_id']
        wait_for(lambda: rex('block', 'call', '-s', session, '-b', lazygit_block, 'process').get('foreground', {}).get('name') == 'lazygit')
        time.sleep(0.4)
        rex('send-key', '-s', session, '-b', lazygit_block, 'enter')  # first-run welcome in the disposable state directory
        time.sleep(0.2)
        rex('send-key', '-s', session, '-b', lazygit_block, 'down', 'e')  # move from the tree root to the first file
        try:
            wait_for(lambda: lazygit_layer().get('state') == 'minimized')
        except AssertionError:
            print('LAZYGIT SCREEN:', subprocess.run(['rex', '--autostart=false', 'capture', '-s', session, '-b', lazygit_block, '--trim'],
                                                   env=env, capture_output=True, text=True, timeout=6).stdout)
            raise
        assert remote('expand("%:p")') == str(target)
        print('PASS: actual Lazygit popup edit key reuses Neovim with quoted filenames')

        # Multiple editors never silently become a global "last editor wins" socket.
        second = rex('run', '-s', session, '-c', str(project), '--focus=false', '--json', '--shell=none', '--',
                     'nvim', '--headless', '-u', str(init), '-n', '-i', 'NONE', str(original))['block_ids'][0]
        wait_for(lambda: len(list(records.glob('*.json'))) == 2)
        second_socket = next(json.loads(p.read_text())['socket'] for p in records.glob('*.json')
                             if json.loads(p.read_text())['socket'] != socket)
        result = subprocess.run([str(ROOT / 'bin/rex-edit'), str(target)], env=source_env,
                                cwd=project, capture_output=True, text=True, timeout=12)
        assert result.returncode == 0 and focused() == editor, (result.stdout, result.stderr)
        neutral = rex('run', '-s', session, '-c', str(project), '--focus=false', '--json', '--shell=none', '--', 'sh')['block_ids'][0]
        result = subprocess.run([str(ROOT / 'bin/rex-edit'), str(target)], env=dict(source_env, REX_BLOCK=neutral),
                                cwd=project, input='2\n', capture_output=True, text=True, timeout=12)
        assert result.returncode == 0 and f'2: {second}' in result.stdout, (result.stdout, result.stderr)
        assert remote('expand("%:p")', second_socket) == str(target) and focused() == second
        subprocess.run(['nvim', '--server', second_socket, '--remote-send', '<Cmd>qa!<CR>'], env=env, capture_output=True, timeout=6)
        wait_for(lambda: len(list(records.glob('*.json'))) == 1)
        print('PASS: same-tab preference and explicit choice between multiple project editors')

        # Graceful exit removes the registry, so old instances cannot capture later files.
        subprocess.run(["nvim", "--server", socket, "--remote-send", "<Cmd>qa!<CR>"],
                       env=env, capture_output=True, timeout=6)
        wait_for(lambda: not record.exists())
        fallback = subprocess.run(["nvim", "-l", str(CONFIG / "lua/config/rex_edit_cli.lua"), str(target)],
                                  env=source_env, cwd=project, capture_output=True, text=True, timeout=12)
        assert fallback.returncode == 2, (fallback.stdout, fallback.stderr)
        print("PASS: editor registration cleanup and no-editor fallback")
    finally:
        # Only this freshly created server and its temporary sessions are stopped.
        server.terminate()
        server.wait(timeout=8)
        log.close()
