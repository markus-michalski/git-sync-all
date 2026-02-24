# git-sync-all

Sync all Git repositories in a directory tree. Commit, pull, push — done.

Built for developers who work on multiple machines and want one command to keep everything in sync.

## Quick Start

```bash
git clone https://github.com/markus-michalski/git-sync-all.git
cd git-sync-all
sudo make install
git-sync-all                    # sync ~/projekte
```

## What It Does

For each Git repository found:

1. **Fetches tags** from remote (prunes deleted ones)
2. **Commits** uncommitted changes (with confirmation prompt)
3. **Pulls** new commits from remote (rebase by default)
4. **Pushes** local commits to remote

## Usage

```bash
# Sync all repos in default directory
git-sync-all

# Sync specific directories
git-sync-all ~/work ~/personal

# Preview without changes
git-sync-all --dry-run

# No prompts (CI/cron-friendly)
git-sync-all --yes

# Only show status table
git-sync-all --status

# Exclude repos
git-sync-all --exclude node_modules --exclude vendor

# Only specific repos
git-sync-all --include my-project --include other-project

# Skip pull (only commit + push)
git-sync-all --no-pull

# Skip commit (only pull + push existing)
git-sync-all --no-commit

# Verbose output
git-sync-all -v
```

### All Options

```
-h, --help           Show help and exit
-V, --version        Show version and exit
-n, --dry-run        Show what would happen, change nothing
-v, --verbose        Increase verbosity (stackable: -vv)
-q, --quiet          Suppress all output except errors
-y, --yes            Auto-confirm all repositories
-c, --config FILE    Use specific config file
--init-config        Create default config at XDG location
--setup-alias        Add 'git check' alias to ~/.gitconfig
--no-pull            Skip pulling from remote
--no-push            Skip pushing to remote
--no-tags            Skip tag synchronization
--no-commit          Skip auto-committing
--no-color           Disable colored output
--status             Show repo status only (no sync actions)
--exclude PATTERN    Exclude repos matching pattern (repeatable)
--include PATTERN    Only sync repos matching pattern (repeatable)
```

## Installation

### From Source (recommended)

```bash
git clone https://github.com/markus-michalski/git-sync-all.git
cd git-sync-all
sudo make install          # installs to /usr/local/bin
```

### User-local (no sudo)

```bash
make install PREFIX=$HOME/.local
# Ensure ~/.local/bin is in your PATH
```

### Direct Usage (no install)

```bash
git clone https://github.com/markus-michalski/git-sync-all.git
# Symlink to PATH
ln -s ~/git-sync-all/bin/git-sync-all ~/.local/bin/git-sync-all
```

### Git Alias

```bash
git-sync-all --setup-alias
# Now you can use: git check
```

### Uninstall

```bash
sudo make uninstall
```

## Configuration

```bash
git-sync-all --init-config
# Creates ~/.config/git-sync-all/config.conf
```

See [config.conf.example](config/config.conf.example) for all options.

### Key Settings

| Setting | Default | Description |
|---|---|---|
| `SYNC_BASE_DIRS` | `$HOME/projekte` | Directories to scan (colon-separated) |
| `SYNC_SCAN_DEPTH` | `3` | How deep to scan for repos |
| `SYNC_EXCLUDE` | (empty) | Repos to skip (colon-separated globs) |
| `SYNC_INCLUDE` | (empty) | Only sync these repos |
| `SYNC_PULL_STRATEGY` | `rebase` | `rebase` or `merge` |
| `SYNC_AUTO_CONFIRM` | `false` | Skip confirmation prompts |
| `SYNC_COMMIT_MSG` | `chore: auto-sync from {hostname}` | Commit message template |
| `SYNC_REMOTE` | `origin` | Remote name |

### Priority

CLI flags > Environment variables > Config file > Built-in defaults

## Multi-Machine Workflow

**End of work day:**
```bash
git-sync-all    # commits and pushes everything
```

**Arriving at home:**
```bash
git-sync-all    # pulls all changes from work
```

**Next day at work:**
```bash
git-sync-all    # pulls all changes from home
```

All machines stay in sync.

## Requirements

- **Bash** 4.0+
- **Git** 2.17+ (for `--prune-tags` support)

## Development

```bash
make check        # run all checks (lint + format + test)
make test         # run tests only
make lint         # ShellCheck
make format       # shfmt (check only)
make format-fix   # shfmt (apply changes)
```

## License

[MIT](LICENSE)
