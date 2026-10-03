#!/bin/sh
# scripts/notify.sh — status transition notifications
#
# usage: notify.sh <title> [body]
#
# The backend is selected with @loom_notify_backend:
#   display-message   : tmux status-line message (always available)
#   osc9              : writes an OSC 9 escape directly to each client's tty (iTerm2, WezTerm, etc.)
#   terminal-notifier : macOS Notification Center (requires terminal-notifier)
#   auto              : terminal-notifier if available, otherwise display-message

set -u

LOOM_ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$LOOM_ROOT/scripts/lib/common.sh"

title=${1:-}
body=${2:-}
if [ -z "$title" ]; then
	echo "usage: notify.sh <title> [body]" >&2
	exit 2
fi

backend=$(loom_gopt @loom_notify_backend auto)
if [ "$backend" = auto ]; then
	if command -v terminal-notifier >/dev/null 2>&1; then
		backend=terminal-notifier
	else
		backend=display-message
	fi
fi

msg="loom: $title${body:+ — $body}"

case $backend in
(display-message)
	tmux display-message "$msg" 2>/dev/null
	;;
(osc9)
	tmux list-clients -F '#{client_tty}' 2>/dev/null | while read -r tty; do
		[ -w "$tty" ] && printf '\033]9;%s\007' "$msg" >"$tty" 2>/dev/null
	done
	;;
(terminal-notifier)
	terminal-notifier -title "loom" -subtitle "$title" -message "${body:-$title}" >/dev/null 2>&1
	;;
(*)
	echo "notify.sh: unknown backend: $backend" >&2
	exit 1
	;;
esac
exit 0
