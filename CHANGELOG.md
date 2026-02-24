# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Nothing yet

### Changed

- Nothing yet

### Fixed

- Nothing yet

## [1.0.0] - 2026-02-24

### Added

- Core sync workflow: commit, pull (rebase/merge), push, tag sync
- XDG-compliant configuration file (`~/.config/git-sync-all/config.conf`)
- CLI flags: `--dry-run`, `--status`, `--yes`, `--verbose`, `--quiet`
- Include/exclude filters for repositories (glob patterns)
- `--init-config` to create default configuration
- `--setup-alias` to add `git check` alias
- Lock file to prevent concurrent runs
- Colored output with auto-detection (disable with `--no-color`)
- Modular architecture with separate library files
- Comprehensive test suite (62 tests)
- Makefile with install/uninstall/test/lint/format targets
- GitHub Actions CI pipeline

[Unreleased]: https://github.com/markus-michalski/git-sync-all/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/markus-michalski/git-sync-all/releases/tag/v1.0.0
