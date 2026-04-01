# Contributing to git-sync-all

## Development Setup

```bash
git clone https://github.com/markus-michalski/git-sync-all.git
cd git-sync-all
make link PREFIX=$HOME/.local   # Symlink for development
make test                       # Run test suite
```

## Code Style

- **Shell:** Bash 4.4+, `set -euo pipefail` in core.sh only
- **Indentation:** 4 spaces (see `.editorconfig`)
- **Linting:** ShellCheck with `enable=all` (`make lint`)
- **Formatting:** shfmt with `-i 4 -ci -bn` (`make format`)
- **Comments:** English
- **Variables:** `UPPER_SNAKE` for globals/config, `lower_snake` for locals
- **Functions:** Lowercase with underscores, always declare locals with `local`

## Architecture

Modular structure with a thin entrypoint and separate library files in `lib/`:

- Each lib uses a source guard: `[[ -n "${_GSA_XXX_LOADED:-}" ]] && return 0`
- All globals use `GSA_` or `SYNC_` prefix
- Config priority: CLI flags > Environment variables > Config file > Defaults

### Adding a New Feature

1. Identify which library the feature belongs to
2. Write the function following existing patterns
3. Add tests in `tests/`
4. Run `make check` (lint + format + test)

## Testing

Custom test framework in `tests/test-helpers.sh`:

```bash
make test              # Run all tests
bash tests/run-tests.sh  # Run directly
```

Available assertions: `assert_equals`, `assert_contains`, `assert_not_contains`, `assert_exit_code`, `assert_file_exists`, `assert_file_contains`.

Tests create isolated Git repos in `tests/tmp/` (auto-cleaned).

## CI

GitHub Actions on push/PR to main: ShellCheck + shfmt + Tests.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add new feature
fix: correct a bug
docs: update documentation
refactor: restructure code
test: add or modify tests
chore: maintenance tasks
```

## Pull Requests

1. Create a feature branch from `main`
2. Make your changes
3. Ensure `make check` passes (lint + format + tests)
4. Open a PR with a clear description
