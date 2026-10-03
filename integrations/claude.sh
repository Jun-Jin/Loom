#!/bin/sh
# integrations/claude.sh — install/uninstall Claude Code Hooks
#
# usage: claude.sh install|uninstall [settings_path]
#
# Merges report.sh invocations into the hooks in ~/.claude/settings.json.
# - Existing hooks are preserved and nothing is inserted twice (idempotent)
# - Entries from this plugin are identified by the "# loom" marker at the end of the command
# - A backup is written to <settings>.loom-bak before any change
#
# Hooks installed (docs/03-state-detection.md):
#   UserPromptSubmit → working / PreToolUse → working /
#   Notification → blocked / Stop → idle
# (SubagentStop is not reported because the parent may still be working)

set -u

LOOM_ROOT=$(cd "$(dirname "$0")/.." && pwd)

mode=${1:-}
settings=${2:-"$HOME/.claude/settings.json"}

case $mode in
(install | uninstall) ;;
(*)
	echo "usage: claude.sh install|uninstall [settings_path]" >&2
	exit 2
	;;
esac

if ! command -v python3 >/dev/null 2>&1; then
	echo "loom: integration requires python3" >&2
	exit 1
fi

LOOM_MODE=$mode LOOM_SETTINGS=$settings LOOM_REPORT="$LOOM_ROOT/scripts/report.sh" python3 <<'PY'
import json, os, shutil, sys

mode = os.environ["LOOM_MODE"]
path = os.environ["LOOM_SETTINGS"]
report = os.environ["LOOM_REPORT"]

MARKER = "# loom"
EVENTS = {
    "UserPromptSubmit": "working",
    "PreToolUse": "working",
    "Notification": "blocked",
    "Stop": "idle",
}

if os.path.exists(path):
    with open(path) as f:
        raw = f.read()
    data = json.loads(raw) if raw.strip() else {}
else:
    if mode == "uninstall":
        print(f"loom: {path} does not exist; nothing to do")
        sys.exit(0)
    data = {}

if not isinstance(data, dict):
    print(f"loom: {path} is not a JSON object", file=sys.stderr)
    sys.exit(1)

def is_ours(entry):
    return any(MARKER in h.get("command", "") for h in entry.get("hooks", []))

hooks = data.get("hooks", {})
changed = False

for event, status in EVENTS.items():
    entries = [e for e in hooks.get(event, []) if not is_ours(e)]
    removed = len(hooks.get(event, [])) - len(entries)
    if mode == "install":
        cmd = f'"{report}" "$TMUX_PANE" {status} hook claude {MARKER}'
        entries.append({"hooks": [{"type": "command", "command": cmd}]})
        changed = True
    elif removed:
        changed = True
    if entries:
        hooks[event] = entries
    elif event in hooks:
        del hooks[event]

if hooks:
    data["hooks"] = hooks
elif "hooks" in data:
    del data["hooks"]

if not changed:
    print("loom: no changes")
    sys.exit(0)

if os.path.exists(path):
    shutil.copy2(path, path + ".loom-bak")
os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")

verb = "installed into" if mode == "install" else "removed from"
print(f"loom: Claude Code hooks {verb} {path} (backup: {path}.loom-bak)")
if mode == "install":
    print("loom: restart Claude Code for the changes to take effect")
PY
