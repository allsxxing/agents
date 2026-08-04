#!/usr/bin/env bash
# Bootstrap the nfl_mcp fork on your laptop in one command.
#
# What this does:
#   1. Forks gtonic/nfl_mcp -> allsxxing/nfl_mcp and clones it
#   2. Applies the two patches (allowlist + routing eval)
#   3. Copies the cloudflare/ scaffold (wrangler.jsonc, worker/, package.json,
#      tsconfig.json, .github/workflows/deploy.yml) into the fork root
#   4. Runs `npm install`
#   5. Prints the exact list of GitHub secrets you still need to set
#
# What it does NOT do:
#   - Set your Cloudflare API token (secret; belongs in a password manager)
#   - Set the MCP_TOKEN (also secret)
#   - Push the branch (you review + push yourself)
#
# Prereqs: gh (authenticated), git, node 22+, npm.
# Usage:   ./bootstrap.sh [target-dir]     (default: ~/Projects/fantasy)

set -euo pipefail

TARGET_DIR="${1:-$HOME/Projects/fantasy}"
DELIVERABLE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Bootstrap nfl_mcp fork"
echo "    Deliverable:   $DELIVERABLE_DIR"
echo "    Target parent: $TARGET_DIR"

command -v gh   >/dev/null || { echo "ERROR: gh CLI not installed"; exit 1; }
command -v git  >/dev/null || { echo "ERROR: git not installed";   exit 1; }
command -v node >/dev/null || { echo "ERROR: node not installed";  exit 1; }
command -v npm  >/dev/null || { echo "ERROR: npm not installed";   exit 1; }
gh auth status >/dev/null 2>&1 || { echo "ERROR: run 'gh auth login' first"; exit 1; }

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

if [ -d nfl_mcp/.git ]; then
  echo "==> nfl_mcp already cloned, skipping fork+clone"
  cd nfl_mcp
else
  echo "==> Forking + cloning gtonic/nfl_mcp"
  gh repo fork gtonic/nfl_mcp --clone --remote --fork-name nfl_mcp
  cd nfl_mcp
fi

# The patches were generated against upstream main. Branch off latest main.
git fetch upstream main
git checkout -B feat/tool-allowlist upstream/main

echo "==> Applying allowlist patch"
git am "$DELIVERABLE_DIR/nfl_mcp-patches/0001-"*.patch

echo "==> Applying routing eval patch"
git am "$DELIVERABLE_DIR/nfl_mcp-patches/0002-"*.patch

echo "==> Dropping Cloudflare scaffold"
# All at the fork root (deploy.yml goes under .github/workflows).
cp    "$DELIVERABLE_DIR/cloudflare/wrangler.jsonc" .
cp    "$DELIVERABLE_DIR/cloudflare/package.json"   .
cp    "$DELIVERABLE_DIR/cloudflare/tsconfig.json"  .
cp -r "$DELIVERABLE_DIR/cloudflare/worker"         .
mkdir -p .github/workflows
cp    "$DELIVERABLE_DIR/cloudflare/.github/workflows/deploy.yml" .github/workflows/

# Keep node_modules and TS build artifacts out of git.
{ echo "node_modules/"; echo "*.tsbuildinfo"; echo ".wrangler/"; } >> .gitignore

echo "==> Installing worker deps (npm install)"
npm install --no-audit --no-fund

echo "==> Committing scaffold on top of the patches"
git add wrangler.jsonc package.json package-lock.json tsconfig.json worker/ \
        .github/workflows/deploy.yml .gitignore
git commit -m "feat: Cloudflare Worker + Container deploy scaffold"

echo ""
echo "==> DONE."
echo ""
echo "Next 3 things you do:"
echo ""
echo "  1. Set these three GitHub secrets at"
echo "     https://github.com/allsxxing/nfl_mcp/settings/secrets/actions"
echo ""
echo "       CLOUDFLARE_API_TOKEN   (Workers-scoped, from CF dashboard)"
echo "       CLOUDFLARE_ACCOUNT_ID  (right sidebar of any Workers page)"
echo "       MCP_TOKEN              (openssl rand -hex 32 — save both places)"
echo ""
echo "  2. Push the branch:"
echo "       git push -u origin feat/tool-allowlist"
echo ""
echo "     Then merge feat/tool-allowlist -> main via a PR. Merging triggers"
echo "     .github/workflows/deploy.yml, which builds the image on the"
echo "     GH Actions runner (no Docker locally), deploys, and smoke-tests"
echo "     the 401/200 auth pair."
echo ""
echo "  3. Once CI is green, copy the '*.workers.dev' URL from the run"
echo "     summary and run on your laptop:"
echo ""
echo "       $DELIVERABLE_DIR/scripts/wire-clients.sh <url>"
echo ""
