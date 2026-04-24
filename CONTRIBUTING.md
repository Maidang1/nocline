# Contributing to Nocline

This document covers bug reports, feature ideas, and pull requests.

## Quick Guide

### I found a bug

Search [existing issues](https://github.com/sk-ruban/notchi/issues) first. If it is new, open an issue with steps to reproduce, your macOS version, and any relevant logs.

### I have an idea for a feature

Open an issue describing the change and why it matters. That keeps scope clear before code lands.

### I'd like to contribute code

1. Find an existing issue or open one first.
2. Comment on the issue so ownership is visible.
3. Submit a PR that references the issue.

## Local Development

1. Clone the repo
2. Open `notchi/notchi.xcodeproj` in Xcode
3. Build and run with `⌘R`

The app auto-installs the Codex CLI hook on launch, so start Codex CLI to see live activity.

## Code Style

- Match existing patterns
- `@MainActor` is the default isolation
- Prefer small, focused PRs
- Keep dependencies light

## Hook Safety

Hook changes go through the installer service and bundled script:

- `notchi/notchi/Resources/notchi-codex-hook.sh`
- `notchi/notchi/Services/CodexHookInstaller.swift`

The installer updates `~/.codex/hooks.json` through JSON merge logic that preserves existing user hooks.

Rebuild and relaunch the app after hook changes.

## License

By contributing, you agree that your contributions are licensed under GPL-3.0-only.
