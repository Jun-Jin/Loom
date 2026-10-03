#!/bin/sh
# scripts/dashboard.sh — popup dashboard (list + preview + jump with Enter)
#
# no args  : open the display-popup (entry point called from the key binding)
# --ui     : the TUI itself, run inside the popup
#
# The list is computed lazily when the popup opens and on rescan (no resident monitoring).
# Keys: j/k/C-n/C-p/↑/↓ move, Enter jump, r rescan, q/Esc/C-c close

set -u

LOOM_ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$LOOM_ROOT/scripts/lib/common.sh"

TAB=$(printf '\t')
ESC=$(printf '\033')
CR=$(printf '\r')
CTRL_N=$(printf '\016')
CTRL_P=$(printf '\020')
CTRL_C=$(printf '\003')

C_RESET=$(printf '\033[0m')
C_BOLD=$(printf '\033[1m')
# Use explicit colors for the selected row instead of reverse video. EL (\033[K) fills to the end of
# the line with the background color, so the highlight spans the full popup width (EL cannot paint reverse video)
C_SEL=$(printf '\033[30;47m')
C_RED=$(printf '\033[31m')
C_GREEN=$(printf '\033[32m')
C_YELLOW=$(printf '\033[33m')
C_DIM=$(printf '\033[90m')

open_popup() {
	if [ -z "${TMUX:-}" ]; then
		echo "loom: must be run inside tmux" >&2
		exit 1
	fi
	w=$(loom_gopt @loom_popup_width 80%)
	h=$(loom_gopt @loom_popup_height 70%)
	exec tmux display-popup -E -w "$w" -h "$h" "\"$LOOM_ROOT/scripts/dashboard.sh\" --ui"
}

# Rebuild the list (the actual assembly is loom_rows in common.sh; no detection, instant)
build_rows() {
	ROWS=$(loom_rows)
	if [ -n "$ROWS" ]; then
		NROWS=$(printf '%s\n' "$ROWS" | wc -l | tr -d ' ')
	else
		NROWS=0
	fi
	[ "$SEL" -gt "$NROWS" ] && SEL=$NROWS
	[ "$SEL" -lt 1 ] && SEL=1
	return 0
}

# Run detection on all panes (loom_detect_all in common.sh), then rebuild the list
scan() {
	loom_detect_all
	build_rows
}

row() { # <n> — return the record on line n
	printf '%s\n' "$ROWS" | sed -n "${1}p"
}

hr() {
	awk -v n="$COLS" 'BEGIN { while (n-- > 0) printf "─"; print "" }'
}

# Layout that uses the popup's full height and width:
#   header(1) + hr(1) + list(NROWS) + hr(1) + preview heading(1) + preview(all remaining) + hr(1) + footer(1)
# The footer is printed without a newline to pin it to the bottom row (a trailing \n would cause scrolling)
render() {
	# Inside a popup TERM may not resolve and tput can fail, so get the size via stty size (ioctl)
	set -- $(stty size 2>/dev/null) 24 80
	LINES=$1 COLS=$2
	printf '\033[H\033[2J'
	printf ' %sLoom — agent dashboard%s\n' "$C_BOLD" "$C_RESET"
	hr
	if [ "$NROWS" -eq 0 ]; then
		printf '\n  No agents found.\n'
		printf '  Start claude or another agent inside tmux, then press r to rescan.\n'
		pad=$((LINES - 7))
		while [ "$pad" -gt 0 ]; do
			printf '\n'
			pad=$((pad - 1))
		done
	else
		i=1
		printf '%s\n' "$ROWS" | while IFS="$TAB" read -r _pri pane status agent loc since path; do
			case $status in
			blocked) icon='⚠' color=$C_RED ;;
			working) icon='●' color=$C_YELLOW ;;
			idle) icon='◌' color=$C_GREEN ;;
			*) icon='·' color=$C_DIM ;;
			esac
			dur=$(loom_fmt_duration "$since")
			case $path in "$HOME"*) path="~${path#"$HOME"}" ;; esac
			line=$(printf ' %s %-8.8s %-8.8s %-20.20s %5s  %s' \
				"$icon" "$agent" "$status" "$loc" "$dur" "$path")
			line=$(printf "%.${COLS}s" "$line")
			if [ "$i" -eq "$SEL" ]; then
				printf '%s%s\033[K%s\n' "$C_SEL" "$line" "$C_RESET"
			else
				printf '%s%s%s\n' "$color" "$line" "$C_RESET"
			fi
			i=$((i + 1))
		done
		hr
		sel_pane=$(row "$SEL" | cut -f2)
		sel_agent=$(row "$SEL" | cut -f4)
		printf ' %spreview: %s%s\n' "$C_BOLD" "$sel_agent" "$C_RESET"
		pv=$((LINES - NROWS - 6))
		[ "$pv" -lt 0 ] && pv=0
		if [ "$pv" -gt 0 ]; then
			# Use -e to keep the original colors. Truncating over-wide lines with substr would break escape
			# sequences, so leave the clipping to the terminal by disabling autowrap (\033[?7l in ui()).
			# The trailing \033[0m keeps colors from leaking into the padding or the next line, and the
			# blank-line padding keeps the preview area at exactly pv lines (pinning the footer in place)
			tmux capture-pane -p -e -t "$sel_pane" 2>/dev/null |
				loom_tail_lines "$pv" |
				awk -v n="$pv" '{ printf "%s\033[0m\n", $0; c++ } END { while (c++ < n) print "" }'
		fi
	fi
	hr
	printf ' [j/k/C-n/C-p]move [Enter]jump [r]rescan [q]close'
}

getkey() {
	k=$(dd bs=1 count=1 2>/dev/null)
	case $k in
	"$ESC")
		stty min 0 time 1 2>/dev/null
		rest=$(dd bs=2 count=1 2>/dev/null)
		stty min 1 time 0 2>/dev/null
		case $rest in
		'[A') echo up ;;
		'[B') echo down ;;
		*) echo esc ;;
		esac
		;;
	'' | "$CR") echo enter ;;
	"$CTRL_N") echo down ;;
	"$CTRL_P") echo up ;;
	"$CTRL_C") echo quit ;;
	*) printf '%s\n' "$k" ;;
	esac
}

do_jump() {
	[ "$NROWS" -ge 1 ] || return 0
	r=$(row "$SEL")
	pane=$(printf '%s' "$r" | cut -f2)
	loc=$(printf '%s' "$r" | cut -f5)
	win=${loc%.*}
	tmux switch-client -t "$win" 2>/dev/null || true
	tmux select-window -t "$win" 2>/dev/null || true
	tmux select-pane -t "$pane" 2>/dev/null || true
	exit 0
}

ui() {
	SAVED_STTY=$(stty -g 2>/dev/null || true)
	cleanup() {
		[ -n "$SAVED_STTY" ] && stty "$SAVED_STTY" 2>/dev/null
		printf '\033[?25h\033[?7h'
	}
	trap cleanup EXIT
	trap 'exit 130' INT TERM
	# -isig: read C-c as a plain key rather than a signal and treat it as quit, so the popup closes reliably
	stty -icanon -echo -isig min 1 time 0 2>/dev/null
	# ?7l: disable autowrap. The preview is streamed in color (capture-pane -e), so
	# over-wide lines are clipped at the right edge instead of wrapping (= a broken layout)
	printf '\033[?25l\033[?7l'

	SEL=1
	NROWS=0
	# Render immediately from the cached status first, deferring detection until after the first paint.
	# Once detection finishes, the render at the top of the loop replaces it with the latest results
	build_rows
	render
	scan
	while :; do
		render
		key=$(getkey)
		case $key in
		j | down) [ "$SEL" -lt "$NROWS" ] && SEL=$((SEL + 1)) ;;
		k | up) [ "$SEL" -gt 1 ] && SEL=$((SEL - 1)) ;;
		enter) do_jump ;;
		r) scan ;;
		q | esc | quit) exit 0 ;;
		esac
	done
}

case ${1:-} in
--ui) ui ;;
*) open_popup ;;
esac
