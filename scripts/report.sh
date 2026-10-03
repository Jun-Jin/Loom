#!/bin/sh
# scripts/report.sh — single entry point for status writes (transition comparison + notification dispatch)
#
# usage: report.sh <pane_id> <status: working|idle|blocked|unknown> <source: hook|screen> [agent]
#
# Both the hook path (Claude Code Hooks) and the screen detection path (detect.sh) go through here.
# - Compares against the previous status and updates @loom_status_since on a transition (via loom_set_status)
# - Calls notify.sh if the new status is listed in @loom_notify_on
# - If agent is given, sets @loom_agent (for integration hooks; does nothing when $TMUX_PANE is empty)
#
# Setting the environment variable LOOM_NOTIFY=off suppresses notifications only (for the dashboard's on-demand detection).

set -u

LOOM_ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$LOOM_ROOT/scripts/lib/common.sh"

pane=${1:-}
status=${2:-}
source=${3:-}
agent=${4:-}

# Hooks of agents started outside tmux get an empty $TMUX_PANE. Ignore them silently
[ -n "$pane" ] || exit 0
if [ -z "$status" ] || [ -z "$source" ]; then
	echo "usage: report.sh <pane_id> <status> <source> [agent]" >&2
	exit 2
fi

# Do nothing if the pane is already gone (e.g. a hook firing right after exit)
tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$pane" || exit 0

[ -n "$agent" ] && tmux set-option -p -t "$pane" @loom_agent "$agent"

old=$(loom_opt "$pane" @loom_status)
loom_set_status "$pane" "$status" "$source"
new=$(loom_opt "$pane" @loom_status)

# Do not notify when there is no transition (including writes skipped by the hook-priority rule)
[ "$new" = "$old" ] && exit 0

# Decide whether to notify
[ "${LOOM_NOTIFY:-on}" = on ] || exit 0
[ "$(loom_gopt @loom_notify on)" = on ] || exit 0
# The first detection (no previous status) is not a transition, so do not notify
[ -n "$old" ] || exit 0
notify_on=$(loom_gopt @loom_notify_on "blocked,idle")
case ",$notify_on," in
(*",$new,"*) ;;
(*) exit 0 ;;
esac

name=$(loom_opt "$pane" @loom_agent)
loc=$(tmux display-message -p -t "$pane" '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null)
"${LOOM_NOTIFY_CMD:-"$LOOM_ROOT/scripts/notify.sh"}" "${name:-agent}: $new" "${loc:-}"
exit 0
