#!/bin/sh
# scripts/detect.sh — screen detection (capture-pane + manifest evaluation)
#
# usage: detect.sh <pane_id> [--print]
#
# 1. Capture the target pane with capture-pane
# 2. If the agent type is not yet determined, identify it via each manifest's identify and set @loom_agent
#    (once determined, set monitor-silence on the window to wire up the secondary-path trigger)
# 3. Evaluate the matching manifest's rules in order to determine the status
# 4. Write to the pane options via report.sh (source=screen; a transition also fires a notification)
#
# If no rule matches, the previous value is kept (to prevent flicker).
# --print writes the detection result to stdout for debugging.

set -u

LOOM_ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$LOOM_ROOT/scripts/lib/common.sh"
. "$LOOM_ROOT/scripts/lib/manifest.sh"

pane=${1:-}
if [ -z "$pane" ]; then
	echo "usage: detect.sh <pane_id> [--print]" >&2
	exit 2
fi

[ "$(loom_gopt @loom_screen_detection on)" = on ] || exit 0

manifest_dir=$(loom_gopt @loom_manifest_dir "$LOOM_ROOT/manifests")

cap=$(mktemp "${TMPDIR:-/tmp}/loom-cap.XXXXXX")
trap 'rm -f "$cap"' EXIT INT TERM
tmux capture-pane -p -t "$pane" -S -40 >"$cap" 2>/dev/null || exit 0

# Determine the agent type: if already set, use its manifest; otherwise search via identify
agent=$(loom_opt "$pane" @loom_agent)
manifest=""
if [ -n "$agent" ]; then
	if [ -f "$manifest_dir/$agent.toml" ]; then
		manifest="$manifest_dir/$agent.toml"
	else
		for m in "$manifest_dir"/*.toml; do
			[ -f "$m" ] || continue
			if [ "$(loom_manifest_agent "$m")" = "$agent" ]; then
				manifest=$m
				break
			fi
		done
	fi
else
	for m in "$manifest_dir"/*.toml; do
		[ -f "$m" ] || continue
		if loom_manifest_identify "$m" "$cap"; then
			manifest=$m
			agent=$(loom_manifest_agent "$m")
			tmux set-option -p -t "$pane" @loom_agent "$agent"
			break
		fi
	done
fi

# Do nothing for non-agent panes (no fingerprint matches)
[ -n "$manifest" ] || exit 0

# Set monitor-silence on the agent's window (the trigger for the alert-silence hook; see loom.tmux)
timeout=$(loom_gopt @loom_silence_timeout 4)
if [ "$timeout" -gt 0 ] 2>/dev/null; then
	cur=$(tmux show-options -w -t "$pane" -qv monitor-silence)
	[ "$cur" = "$timeout" ] || tmux set-option -w -t "$pane" monitor-silence "$timeout"
fi

status=$(loom_manifest_status "$manifest" "$cap")
if [ -z "$status" ]; then
	# Keep the previous value if there is one; write unknown only on the first run
	prev=$(loom_opt "$pane" @loom_status)
	if [ -n "$prev" ]; then
		[ "${2:-}" = --print ] && printf '%s\t%s\t%s (kept)\n' "$pane" "$agent" "$prev"
		exit 0
	fi
	status=unknown
fi

"$LOOM_ROOT/scripts/report.sh" "$pane" "$status" screen
[ "${2:-}" = --print ] && printf '%s\t%s\t%s\n' "$pane" "$agent" "$status"
exit 0
