# git-sync-all

Sync all Git repositories in a directory tree. Commit, pull, push — done.

Built for developers who work on multiple machines and want one command to keep everything in sync.

## Quick Start

```bash
git clone https://github.com/markus-michalski/git-sync-all.git
cd git-sync-all
make link PREFIX=$HOME/.local   # symlink, auto-updates on git pull
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

# Verify all expected repos exist locally
git-sync-all --verify

# Verify only a specific group
git-sync-all --verify --group work

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
--verify             Verify all repos from inventory exist locally
--inventory FILE     Use specific inventory file
--group NAME         Verify only repos in this group (default: all)
--init-inventory     Create inventory file at XDG location
--exclude PATTERN    Exclude repos matching pattern (repeatable)
--include PATTERN    Only sync repos matching pattern (repeatable)
```

## Installation

### Symlink (recommended)

```bash
git clone https://github.com/markus-michalski/git-sync-all.git
cd git-sync-all
make link PREFIX=$HOME/.local   # symlink, auto-updates on git pull
```

### System-wide copy

```bash
sudo make install               # copies to /usr/local/bin
```

### User-local copy (no sudo)

```bash
make install PREFIX=$HOME/.local
# Ensure ~/.local/bin is in your PATH
```

### Git Alias

```bash
git-sync-all --setup-alias
# Now you can use: git check
```

### Windows

Windows has no `make`, so use the PowerShell installer instead. It needs
[Git for Windows](https://git-scm.com/download/win) — git-sync-all is a Bash
program and runs on the bash.exe that ships with it.

```powershell
git clone https://github.com/markus-michalski/git-sync-all.git
cd git-sync-all
.\install.ps1
```

This installs to `%LOCALAPPDATA%\Programs\git-sync-all` and adds its `bin`
directory to your user PATH. Open a new terminal afterwards, then
`git-sync-all` works from PowerShell, cmd.exe and Git Bash alike.

```powershell
.\install.ps1 -Prefix C:\tools\git-sync-all   # custom location
.\install.ps1 -Link                           # point at this clone, updates on git pull
.\install.ps1 -NoPathUpdate                   # do not touch PATH
.\install.ps1 -Uninstall                      # remove it again
```

If PowerShell blocks the script, run it via
`powershell -ExecutionPolicy Bypass -File .\install.ps1`.

Paths in `SYNC_BASE_DIRS` must use Git Bash syntax, because the setting is
colon-separated and a drive letter would split it apart:

```bash
SYNC_BASE_DIRS="/c/Users/you/projekte"   # correct
SYNC_BASE_DIRS="C:/Users/you/projekte"   # breaks: the colon separates entries
```

### Uninstall

```bash
make uninstall PREFIX=$HOME/.local   # removes symlink or copy
# or for system-wide:
sudo make uninstall
```

On Windows: `.\install.ps1 -Uninstall`

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
| `SYNC_INVENTORY_FILE` | (XDG default) | Path to `repos.yml` inventory file |

### Priority

CLI flags > Environment variables > Config file > Built-in defaults

## Repository Inventory

Keep track of which repos should be cloned on each machine using a `repos.yml` inventory file.

```bash
git-sync-all --init-inventory
# Creates ~/.config/git-sync-all/repos.yml
```

See [repos.yml.example](config/repos.yml.example) for the format. Repos are organized in groups:

```yaml
all:
  - git-sync-all
  - dotfiles

work:
  - shopware6-sepa-67
  - oxid-module-gallery

personal:
  - my-website
```

For third-party repos that are not in your GitHub account, add a clone URL:

```yaml
external:
  - osticket: https://github.com/osTicket/osTicket
  - oxid7: https://github.com/OXID-eSales/oxideshop_ce
```

Verify that all expected repos exist locally:

```bash
git-sync-all --verify                   # check "all" group
git-sync-all --verify --group work      # check "work" group only
git-sync-all --verify --group all,work  # check multiple groups
```

Missing repos are listed with clone instructions:
- Repos with a URL: `git clone <url> <target-dir>`
- Your own repos: `gh repo clone <user>/<name>` (requires `gh` CLI)

## Multi-Machine Workflow

**End of work day:**
```bash
git-sync-all    # commits and pushes everything
```

**Arriving at home:**
```bash
git-sync-all --verify   # check all expected repos are cloned
git-sync-all            # pulls all changes from work
```

**Next day at work:**
```bash
git-sync-all    # pulls all changes from home
```

All machines stay in sync.

## Requirements

- **Bash** 4.0+
- **Git** 2.17+ (for `--prune-tags` support)
- On Windows: **Git for Windows**, which provides both

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
