#!/bin/sh
# tests/run.sh — manifest regression test against captured screens
#
# tests/fixtures/<agent>/<status>[-variant].txt holds `capture-pane -p` output of a real agent pane.
# For each fixture, exactly the <agent> manifest must identify it (every other manifest must not),
# and its rules must yield <status>. Fixtures under fixtures/none/ must match no manifest at all.
#
# usage: tests/run.sh            (exit 1 on any failure)

set -u

LOOM_ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$LOOM_ROOT/scripts/lib/common.sh"
. "$LOOM_ROOT/scripts/lib/manifest.sh"

manifest_dir=$LOOM_ROOT/manifests
fixture_dir=$LOOM_ROOT/tests/fixtures
pass=0 fail=0

report() { # <ok|NG> <fixture> <message>
	if [ "$1" = ok ]; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
	fi
	printf '%s  %s  %s\n' "$1" "$2" "$3"
}

for fixture in "$fixture_dir"/*/*.txt; do
	[ -f "$fixture" ] || continue
	want_agent=$(basename "$(dirname "$fixture")")
	want_status=$(basename "$fixture" .txt)
	want_status=${want_status%%-*}
	rel=${fixture#"$fixture_dir/"}

	# Which manifests identify this capture? (file-name order, same as detect.sh)
	matched=""
	for m in "$manifest_dir"/*.toml; do
		if loom_manifest_identify "$m" "$fixture"; then
			matched="$matched $(loom_manifest_agent "$m")"
		fi
	done
	matched=${matched# }

	if [ "$want_agent" = none ]; then
		if [ -z "$matched" ]; then
			report ok "$rel" "no manifest matches"
		else
			report NG "$rel" "expected no match, identified as: $matched"
		fi
		continue
	fi

	if [ "$matched" != "$want_agent" ]; then
		report NG "$rel" "identify: expected '$want_agent', got '${matched:-(none)}'"
		continue
	fi

	got=$(loom_manifest_status "$manifest_dir/$want_agent.toml" "$fixture")
	if [ "$got" = "$want_status" ]; then
		report ok "$rel" "$got"
	else
		report NG "$rel" "status: expected '$want_status', got '${got:-(none)}'"
	fi
done

echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
