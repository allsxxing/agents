#!/usr/bin/env bash
# Wire the deployed nfl-mcp URL into Claude Code + Claude Desktop and install
# the Flaim + fantasy-routing skills. Run AFTER the CI deploy has printed the
# workers.dev URL.
#
# Usage: ./wire-clients.sh https://nfl-mcp.<subdomain>.workers.dev

set -euo pipefail

URL="${1:-}"
if [ -z "$URL" ]; then
  echo "Usage: $0 https://nfl-mcp.<subdomain>.workers.dev"
  exit 1
fi
case "$URL" in
  https://nfl-mcp.*.workers.dev) : ;;
  *) echo "ERROR: URL doesn't look like a workers.dev nfl-mcp URL: $URL"; exit 1 ;;
esac

DELIVERABLE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FANTASY_DIR="${FANTASY_DIR:-$HOME/Projects/fantasy}"

# The script never asks for or logs the token — it reads it from the
# environment or prompts once with no echo.
if [ -z "${MCP_TOKEN:-}" ]; then
  echo -n "Paste MCP_TOKEN (input hidden): "
  read -rs MCP_TOKEN
  echo
fi
[ -n "$MCP_TOKEN" ] || { echo "MCP_TOKEN is empty; aborting"; exit 1; }
export MCP_TOKEN

echo "==> 1/4  Verify auth works before wiring"
CODE_UNAUTH=$(curl -sS -o /dev/null -w '%{http_code}' "$URL/health" || echo 000)
CODE_AUTH=$(curl -sS -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $MCP_TOKEN" "$URL/health" || echo 000)
echo "    unauth /health -> $CODE_UNAUTH   (want 401)"
echo "    auth   /health -> $CODE_AUTH   (want 200)"
if [ "$CODE_UNAUTH" != "401" ] || [ "$CODE_AUTH" != "200" ]; then
  echo "ERROR: auth check failed; not wiring clients."
  exit 1
fi

echo "==> 2/4  Add nfl-mcp to Claude Code"
if command -v claude >/dev/null; then
  # If already added, remove first so this is idempotent.
  claude mcp remove nfl-mcp 2>/dev/null || true
  claude mcp add --transport http nfl-mcp "$URL/mcp/" \
    --header "Authorization: Bearer $MCP_TOKEN"
  echo "    Added. Check with: claude mcp list"
else
  echo "    SKIP: 'claude' CLI not on PATH"
fi

echo "==> 3/4  Add nfl-mcp to Claude Desktop"
CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
if [ ! -f "$CFG" ]; then
  echo "    SKIP: Claude Desktop config not found at $CFG"
  echo "          (either not installed, or run Claude Desktop once first)"
else
  # Merge with any existing mcpServers via python — jq isn't always installed.
  python3 - "$CFG" "$URL" "$MCP_TOKEN" <<'PY'
import json, os, sys, shutil
cfg_path, url, token = sys.argv[1], sys.argv[2], sys.argv[3]
with open(cfg_path) as f:
    cfg = json.load(f)
servers = cfg.setdefault("mcpServers", {})
servers["nfl-mcp"] = {
    "command": "npx",
    "args": ["-y", "mcp-remote", f"{url}/mcp/",
             "--header", f"Authorization: Bearer {token}"],
}
shutil.copy(cfg_path, cfg_path + ".bak")
with open(cfg_path, "w") as f:
    json.dump(cfg, f, indent=2)
print(f"    Merged into {cfg_path} (backup: {cfg_path}.bak)")
print("    Restart Claude Desktop for the change to take effect.")
PY
fi

echo "==> 4/4  Install skills"
SKILLS_DIR="${AGENT_SKILLS_DIR:-$HOME/.agents/skills}"
mkdir -p "$SKILLS_DIR"

# Routing skill (ships in this deliverable)
cp -r "$DELIVERABLE_DIR/skills/fantasy-routing" "$SKILLS_DIR/"
echo "    Installed: $SKILLS_DIR/fantasy-routing"

# Flaim skill (lives in the flaim fork)
FLAIM_SKILL_SRC="$FANTASY_DIR/flaim/.agents/skills/flaim-fantasy"
if [ -d "$FLAIM_SKILL_SRC" ]; then
  cp -r "$FLAIM_SKILL_SRC" "$SKILLS_DIR/"
  echo "    Installed: $SKILLS_DIR/flaim-fantasy"
else
  echo "    SKIP: Flaim skill source not found at $FLAIM_SKILL_SRC"
  echo "          Run 'gh repo fork jdguggs10/flaim --clone --fork-name flaim'"
  echo "          in $FANTASY_DIR/ first, then re-run this script."
fi

echo ""
echo "==> DONE. Acceptance test:"
echo "    Open a Claude Code or Claude Desktop session and ask:"
echo ""
echo "      \"Using nfl-mcp, build me a draft board for Sleeper league"
echo "       1370188155843526656.\""
echo ""
echo "    Expected: real player names with VBD values, not an error."
echo "    Also: on flaim.app, change defaultSport to 'football' and"
echo "    set a defaultLeague (plan Task 8) — Flaim will otherwise ask"
echo "    'which league?' on every vague prompt."
