# Notchi

> [!IMPORTANT]
> If you're currently on Notchi `1.0.0`, please install `1.0.1` or later manually from the DMG [here](https://github.com/sk-ruban/notchi/releases/latest). The in-app updater in `1.0.0` needs that one manual hop.

A macOS notch companion that reacts to Codex CLI activity in real time.

https://github.com/user-attachments/assets/e417bd40-cae8-47c0-998a-905166cf3513

## What it does

- Reacts to Codex CLI events in real time
- Shows session time, activity, and live task state in the notch
- Supports multiple concurrent Codex CLI sessions with individual sprites
- Plays optional sound effects for events and auto-mutes while the terminal is focused
- Auto-updates through Sparkle

## Requirements

- macOS 15.0+ (Sequoia)
- MacBook with notch
- [Codex CLI](https://developers.openai.com/codex) installed

## Install

1. Download `Notchi-x.x.x.dmg` from the [latest GitHub Release](https://github.com/sk-ruban/notchi/releases/latest)
2. Open the DMG and drag Notchi to Applications
3. Launch Notchi — it auto-installs Codex CLI hooks on first launch
4. Start using Codex CLI and watch Notchi react

## How it works

```
Codex CLI --> Hook script --> Unix Socket --> Event Parser --> State Machine --> Animated Sprites
```

Notchi registers a Codex hook script on launch. When Codex CLI emits events such as prompt submission, tool use, permission requests, stop events, and session lifecycle updates, the hook script forwards JSON payloads to a local Unix socket. The app parses those events, maps them to sprite states, and renders the live session feed inside the notch.

Each Codex CLI session gets its own agent marker on the notch dock. Clicking expands the notch panel to show recent activity, session details, and session selection when multiple Codex runs are active.

## Contributing

If you have bugs, ideas, or a pull request, start with [Contributing to Notchi](CONTRIBUTING.md).

## Community Ports

- [notchi-for-windows](https://github.com/AptatoX/notchi-for-windows) by [@AptatoX](https://github.com/AptatoX), a community-made Windows port of Notchi

## Credits

- [Codex](https://openai.com/codex/) — visual direction reference for the current app shell
- [Readout](https://readout.org) — design inspiration for [notchi.app](https://notchi.app)
- [Aseprite](https://www.aseprite.org/) — original icon and mascot workflow reference

## License

GPL-3.0-only. See [LICENSE](LICENSE).
