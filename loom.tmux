#!/usr/bin/env sh
# loom.tmux — TPM entry point: loads options, binds keys, and wires the alert-silence hook
# .tmux.conf: set -g @plugin 'Jun-Jin/Loom'

CURRENT_DIR=$(cd "$(dirname "$0")" && pwd)

key=$(tmux show-options -gqv @loom_key)
[ -n "$key" ] || key=a

tmux bind-key "$key" run-shell "\"$CURRENT_DIR/scripts/dashboard.sh\""

# Secondary-path wiring: run screen detection once when a window has been silent for N seconds (monitor-silence).
# monitor-silence itself is set by detect.sh only on windows identified as hosting an agent.
# Append (-a) so existing hooks are not clobbered, and use grep to prevent duplicate registration on reload.
if [ "$(tmux show-options -gqv @loom_screen_detection)" != off ]; then
	if ! tmux show-hooks -g 2>/dev/null | grep -q 'scripts/silence\.sh'; then
		tmux set-hook -ga alert-silence "run-shell -b \"'$CURRENT_DIR/scripts/silence.sh' '#{hook_window}'\""
	fi
fi
