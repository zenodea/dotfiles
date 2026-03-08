# dotfiles

Personal config files managed with symlinks.

## Structure

```
configFiles/
├── install.sh
├── general/          # all platforms
│   ├── zshrc
│   └── config/
│       └── nvim/
├── linux/            # Linux only
│   └── config/
│       └── hypr/
└── mac/              # macOS only
    └── config/
        └── aerospace/
```

- Root-level files → `$HOME/.<name>`
- `config/` entries → `$HOME/.config/<name>`

## Usage

```sh
./install.sh
```

Existing files are backed up as `<file>.bak` before being replaced.
