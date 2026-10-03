# scripts/lib/manifest.sh — minimal detection-manifest parser + region extraction + rule evaluation
# POSIX sh. No external dependencies (awk / sed / grep only). common.sh must be sourced first.
#
# Not a full TOML parser. Only the following structures are supported:
#   - top-level `agent = "name"`
#   - [[identify]] / [[rule]] tables containing `key = "value"` entries, one key per line
# Values are read as raw strings with no escape processing. pattern is an ERE passed to grep -E verbatim.

LOOM_TAB=$(printf '\t')

# Return the manifest's agent name
loom_manifest_agent() { # <manifest_file>
	sed -n 's/^agent[[:space:]]*=[[:space:]]*"\(.*\)".*$/\1/p' "$1" | sed -n 1p
}

# Convert the manifest into TAB-separated records and print them:
#   identify<TAB><region><TAB><pattern>
#   rule<TAB><status><TAB><region><TAB><pattern>
loom_manifest_records() { # <manifest_file>
	awk '
		function flush() {
			if (type == "identify" && f["pattern"] != "")
				print "identify\t" f["region"] "\t" f["pattern"]
			else if (type == "rule" && f["pattern"] != "")
				print "rule\t" f["status"] "\t" f["region"] "\t" f["pattern"]
			delete f
		}
		/^\[\[identify\]\]/ { flush(); type = "identify"; next }
		/^\[\[rule\]\]/     { flush(); type = "rule"; next }
		/^[a-z_]+[[:space:]]*=/ {
			if (type == "") next
			key = $0; sub(/[[:space:]]*=.*$/, "", key)
			val = $0; sub(/^[^=]*=[[:space:]]*/, "", val)
			sub(/^"/, "", val); sub(/"[[:space:]]*$/, "", val)
			f[key] = val; next
		}
		END { flush() }
	' "$1"
}

# Extract the lines selected by the region spec from the capture file to stdout.
# region: full | last_line | top_non_empty_lines(N) | bottom_lines(N)
loom_region() { # <region> <capture_file>
	case $1 in
	full)
		cat "$2"
		;;
	last_line)
		# The last line, ignoring trailing blank lines
		awk 'NF { last = $0 } END { if (last != "") print last }' "$2"
		;;
	top_non_empty_lines\(*\))
		_n=${1#"top_non_empty_lines("}
		_n=${_n%")"}
		awk -v n="$_n" 'NF { print; if (++c >= n) exit }' "$2"
		;;
	bottom_lines\(*\))
		# The bottom N lines, ignoring trailing blank lines
		_n=${1#"bottom_lines("}
		_n=${_n%")"}
		loom_tail_lines "$_n" <"$2"
		;;
	*)
		cat "$2"
		;;
	esac
}

# Return 0 if any identify table matches the capture
loom_manifest_identify() { # <manifest_file> <capture_file>
	loom_manifest_records "$1" | (
		while IFS="$LOOM_TAB" read -r _type _region _pattern; do
			[ "$_type" = identify ] || continue
			if loom_region "$_region" "$2" | grep -qE "$_pattern"; then
				exit 0
			fi
		done
		exit 1
	)
}

# Evaluate rules top to bottom and print the first matching status (empty if none match)
loom_manifest_status() { # <manifest_file> <capture_file>
	loom_manifest_records "$1" | while IFS="$LOOM_TAB" read -r _type _status _region _pattern; do
		[ "$_type" = rule ] || continue
		if loom_region "$_region" "$2" | grep -qE "$_pattern"; then
			printf '%s\n' "$_status"
			break
		fi
	done
}
