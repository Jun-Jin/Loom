# Loom

A tmux plugin of agent dashboard.

Detects panes running AI coding agents (Claude Code, Codex CLI, GitHub Copilot CLI) in tmux and provides a popup list showing each one's status (working / idle / blocked). See [docs/](docs/) for the design documents.

## Installation (TPM)

```tmux
set -g @plugin 'Jun-Jin/Loom'
```

Or manually:

```sh
git clone https://github.com/Jun-Jin/Loom ~/.tmux/plugins/Loom
# Add to .tmux.conf:
run-shell ~/.tmux/plugins/Loom/loom.tmux
```

Requirements: tmux 3.2+ (`display-popup`). After adding the line, reload tmux and press `prefix + I` to let TPM install it.

## Usage

- Press `prefix + a` to open the popup dashboard (the key can be changed with `@loom_key`)
- Keys inside the popup: `j`/`k`/`C-n`/`C-p`/`↑`/`↓` to move, `Enter` to jump to the selected pane, `r` to rescan, `q`/`Esc`/`C-c` to close
- Detection is two-tiered:
  - Primary path: event-driven reporting via Claude Code Hooks (the integration below; accurate, zero overhead)
  - Secondary path: screen detection (decided by the rules in `manifests/*.toml`). It runs the moment the popup opens, and whenever an agent pane has produced no output for `@loom_silence_timeout` seconds (`monitor-silence`)
- Transitions to `blocked` / `idle` trigger a notification (configurable with `@loom_notify_on`)

## Supported agents

| Agent | Manifest | Hooks | Verified against |
|---|---|---|---|
| Claude Code | `manifests/claude.toml` | `integration install claude` | v2.1.301 |
| Codex CLI (OpenAI) | `manifests/codex.toml` | screen detection only | codex-cli 0.163.0 |
| GitHub Copilot CLI | `manifests/copilot.toml` | screen detection only | 1.0.98 |

Detection rules are plain data: to support another agent, add `manifests/<agent>.toml` (or point `@loom_manifest_dir` at your own directory). Fingerprints in `[[identify]]` must be unique to that agent, because manifests are tried in file-name order. `tests/run.sh` checks every manifest against the captured screens in `tests/fixtures/`; add a capture there when you tune a rule.

## Claude Code integration (recommended)

```sh
bin/loom integration install claude    # merge the hooks into ~/.claude/settings.json
bin/loom integration uninstall claude  # remove them (only entries added by loom)
```

Existing hooks are preserved, and re-running the command does not create duplicates. A backup is written to `settings.json.loom-bak` before any change. Claude Code must be restarted for the changes to take effect.

## CLI

`bin/loom` lets you operate agent panes from the outside. `<target>` is a pane ID (`%3`), a tmux target (`sess:1.2`), or an agent name (`claude`).

```sh
bin/loom list --json                          # all agents and their status (for scripting)
bin/loom send %3 "fix the tests"              # send input (Enter is appended by default)
bin/loom wait %3 --status idle --timeout 600  # wait until the given status is reached
bin/loom read %3 --lines 50                   # read output (last N lines, including scrollback)
bin/loom start claude --cwd ~/dev/api         # start an agent in a new window
bin/loom worktree feat/x                      # git worktree + new window
```

Combining `send` → `wait` → `read` lets you script the whole cycle of instructing multiple agents, waiting for them to finish, and collecting their results.

## Configuration

```tmux
set -g @loom_key "a"              # key that opens the popup (prefix + <key>)
set -g @loom_popup_width "80%"
set -g @loom_popup_height "70%"
set -g @loom_screen_detection "on"
set -g @loom_silence_timeout "4"  # monitor-silence interval in seconds (0 disables it)
set -g @loom_notify "on"          # status transition notifications
set -g @loom_notify_on "blocked,idle"
set -g @loom_notify_backend "auto"  # display-message | osc9 | terminal-notifier | auto
set -g @loom_manifest_dir ""      # directory of additional/override manifests
```

## Implementation status

- [x] M1: screen detection (claude manifest) + popup list + jump with Enter
- [x] M2: Claude Code Hooks integration, transition notifications, `monitor-silence` fallback
- [x] M3: CLI (`send`/`read`/`wait`/`worktree`/`start`, `list --json`)
- [x] M4: codex/copilot manifests, TPM registration, compatibility tests (`tests/run.sh`)
