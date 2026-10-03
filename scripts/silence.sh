#!/bin/sh
# scripts/silence.sh — secondary-path trigger called from the alert-silence hook
#
# usage: silence.sh [window_id]
#
# Runs screen detection on each pane of the target window when "N seconds without output = something finished".
# In environments where window_id is unavailable (#{hook_window} unsupported), falls back to scanning all panes.

set -u

LOOM_ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$LOOM_ROOT/scripts/lib/common.sh"

[ "$(loom_gopt @loom_screen_detection on)" = on ] || exit 0

win=${1:-}
if [ -n "$win" ]; then
	panes=$(tmux list-panes -t "$win" -F '#{pane_id}' 2>/dev/null)
else
	panes=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null)
fi

for p in $panes; do
	"$LOOM_ROOT/scripts/detect.sh" "$p"
done
exit 0
