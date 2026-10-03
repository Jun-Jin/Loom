# scripts/lib/common.sh — shared functions (reading/writing pane options, formatting)
# POSIX sh. Sourced from each script with `. "$LOOM_ROOT/scripts/lib/common.sh"`.

# Read a pane-local user option (empty if unset)
loom_opt() { # <pane_id> <option>
	tmux show-options -p -t "$1" -qv "$2" 2>/dev/null
}

# Read a global option (the default value if unset)
loom_gopt() { # <option> <default>
	_v=$(tmux show-options -gqv "$1" 2>/dev/null)
	printf '%s\n' "${_v:-$2}"
}

# Single entry point for status writes.
# Solely responsible for transition comparison and updating @loom_status_since (M2's report.sh also goes through here).
loom_set_status() { # <pane_id> <status: working|idle|blocked|unknown> <source: hook|screen>
	_pane=$1 _status=$2 _source=$3
	_old=$(loom_opt "$_pane" @loom_status)
	_old_src=$(loom_opt "$_pane" @loom_source)
	# For hook-managed panes, screen detection may only overwrite with blocked (see 02-architecture)
	if [ "$_source" = screen ] && [ "$_old_src" = hook ] && [ "$_status" != blocked ]; then
		return 0
	fi
	if [ "$_status" != "$_old" ]; then
		tmux set-option -p -t "$_pane" @loom_status_since "$(date +%s)"
	fi
	tmux set-option -p -t "$_pane" @loom_status "$_status"
	tmux set-option -p -t "$_pane" @loom_source "$_source"
}

# Run screen detection on all panes in parallel (detect.sh ≈ 100ms/pane) and wait for completion.
# Detection is independent per pane, so the wait does not grow with the number of panes.
# Notifications are suppressed because this is meant to be called for on-demand detection (e.g. just before showing the list)
loom_detect_all() {
	for _p in $(tmux list-panes -a -F '#{pane_id}'); do
		LOOM_NOTIFY=off "$LOOM_ROOT/scripts/detect.sh" "$_p" &
	done
	wait
}

# Build the list rows purely from the cached values (pane options) of all panes (no detection, instant).
# Only panes with @loom_agent set. Sorted in the order blocked > working > idle > other.
# Row format: priority \t pane_id \t status \t agent \t session:win.pane \t since \t path
loom_rows() {
	_t=$(printf '\t')
	tmux list-panes -a -F "#{pane_id}${_t}#{@loom_status}${_t}#{@loom_agent}${_t}#{session_name}:#{window_index}.#{pane_index}${_t}#{@loom_status_since}${_t}#{pane_current_path}" |
		awk -F "$_t" -v OFS="$_t" '
			$3 != "" {
				s = ($2 == "") ? "unknown" : $2
				pri = (s == "blocked") ? 0 : (s == "working") ? 1 : (s == "idle") ? 2 : 3
				print pri, $1, s, $3, $4, $5, $6
			}
		' | sort -t "$_t" -k1,1n -k5,5
}

# Print the last N lines of stdin (trailing blank lines are not counted; blank lines in between are preserved)
loom_tail_lines() { # <n>
	awk -v n="$1" '
		NF { last = NR }
		{ l[NR] = $0 }
		END { i = last - n + 1; if (i < 1) i = 1; for (; i <= last; i++) print l[i] }
	'
}

# Return the time elapsed since an epoch-seconds value as "42s" / "3m" / "2h" ("-" if empty)
loom_fmt_duration() { # <epoch_since>
	if [ -z "${1:-}" ]; then
		printf -- '-\n'
		return 0
	fi
	_d=$(($(date +%s) - $1))
	[ "$_d" -lt 0 ] && _d=0
	if [ "$_d" -lt 60 ]; then
		printf '%ss\n' "$_d"
	elif [ "$_d" -lt 3600 ]; then
		printf '%sm\n' "$((_d / 60))"
	else
		printf '%sh\n' "$((_d / 3600))"
	fi
}
