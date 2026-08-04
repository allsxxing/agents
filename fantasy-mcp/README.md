# Fantasy MCP stack — deliverable

Everything this session produced for the Fantasy MCP Stack plan. Some plan
steps needed your laptop (Docker, `wrangler deploy`, secrets, dashboards) and
had to be prepared here for you to run there. Everything is grouped by which
tasks it covers.

**Repo scope in this session was `allsxxing/agents` only** — the plan's Task 1
(`gh repo fork gtonic/nfl_mcp` and `jdguggs10/flaim`) could not run, so no
`allsxxing/nfl_mcp` fork exists yet. Do the fork on your machine, apply the
two patches below, and continue.

## TL;DR — three commands to finished

If you just want it done, skip the task-by-task walk-through and run these:

```bash
# 1. Fork + clone + apply patches + drop deploy scaffold (one command).
./scripts/bootstrap.sh                          # defaults to ~/Projects/fantasy

# 2. Set 3 GitHub secrets at
#    https://github.com/allsxxing/nfl_mcp/settings/secrets/actions
#      CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, MCP_TOKEN
# Then push and let CI deploy:
cd ~/Projects/fantasy/nfl_mcp
git push -u origin feat/tool-allowlist
# Open a PR from feat/tool-allowlist -> main, merge it. The merge triggers
# .github/workflows/deploy.yml on GitHub Actions. No Docker needed on your
# machine — the runner builds the image, deploys the Worker + Container,
# and runs the 401/200 smoke test. Copy the *.workers.dev URL from the run.

# 3. Wire both clients + install the skills.
./scripts/wire-clients.sh https://nfl-mcp.<subdomain>.workers.dev
```

That runs Plan Tasks 1, 3, 4, 5, 6, 7, 9 for you. Only Task 2 (Flaim skill,
included in step 3 above if you've also cloned `jdguggs10/flaim`) and Task 8
(flaim.app `defaultSport`/`defaultLeague`, a dashboard toggle) are left as
manual touches.

```
fantasy-mcp/
├── README.md                        (this file)
├── scripts/                         → automates Tasks 1, 2, 6
│   ├── bootstrap.sh                 fork+clone+patches+scaffold
│   └── wire-clients.sh              wire Claude Code + Desktop, install skills
├── nfl_mcp-patches/                 → Task 3, Task 9
│   ├── 0001-feat-add-NFL_MCP_DISABLED_TOOLS-registration-allowli.patch
│   └── 0002-test-evals-add-offline-routing-guard-for-the-tool-al.patch
├── cloudflare/                      → Task 4, Task 5
│   ├── wrangler.jsonc
│   ├── worker/index.ts
│   ├── package.json
│   ├── tsconfig.json
│   └── .github/workflows/deploy.yml  CI-driven deploy + auth smoke test
└── skills/fantasy-routing/          → Task 7
    └── SKILL.md
```

---

## Verified in this session

- Baseline `nfl_mcp` test suite: **905 passed, 2 skipped** at
  `gtonic/nfl_mcp@7edd2d6`.
- With patch `0001` applied: **915 passed, 2 skipped** (10 new
  `tests/test_tool_allowlist.py` cases). `ruff check .` clean.
- With patches `0001` + `0002` applied: full suite **still 915 passed**;
  `pytest evals/agent -q` **11 passed**. Mutation-checked the offline routing
  guard by removing the `lane: "league_state"` marker from `find_leagues` — two
  guard tests failed as designed, then passed again when restored.
- End-to-end tool-list check against a real running server with
  `NFL_MCP_DISABLED_TOOLS` set: **77 → 71 tools**, exactly the six duplicates
  gone, `get_draft_board`/`recommend_draft_pick`/`simulate_draft` present.
- Cloudflare Worker (`cloudflare/worker/index.ts`) typechecks against
  `@cloudflare/containers@0.2.4` and `@cloudflare/workers-types@5.20260804`.
- `wrangler deploy --dry-run --containers-rollout=none` succeeds against
  `cloudflare/wrangler.jsonc` (dropped next to the fork's Dockerfile): Total
  Upload 45.82 KiB / gzip 11.98 KiB, all bindings resolved, migrations parsed.

## Not verified in this session — you finish these

- Real `wrangler deploy` (needs Docker + a Cloudflare account on the Workers
  Paid plan).
- The `401 unauthenticated` / `200 authenticated` observed on the actual
  `*.workers.dev` URL (Plan Task 4 Steps 6–7).
- Cold-start latency measurement.
- Real draft board returned for league `1370188155843526656` (Plan Task 6
  Step 5 — the Phase 1 acceptance test).

---

## Task 1 — forks

Session GitHub scope was `allsxxing/agents` only, so `mcp__github__fork_repository`
and cross-owner clones both refused. Do this on your laptop:

```bash
mkdir -p ~/Projects/fantasy && cd ~/Projects/fantasy
gh repo fork gtonic/nfl_mcp --clone --remote --fork-name nfl_mcp
gh repo fork jdguggs10/flaim --clone --remote --fork-name flaim
cd nfl_mcp && git remote -v   # origin=allsxxing/nfl_mcp, upstream=gtonic/nfl_mcp
```

## Task 2 — install the Flaim skill

Plan Step 1–4, verbatim. On your laptop:

```bash
mkdir -p ~/.agents/skills
cp -r ~/Projects/fantasy/flaim/.agents/skills/flaim-fantasy ~/.agents/skills/flaim-fantasy
head -20 ~/.agents/skills/flaim-fantasy/SKILL.md   # confirm YAML frontmatter
```

## Task 3 — apply the tool-allowlist patch

**Verified end-to-end here.** Confirmed:

- Upstream tool count: **77** registered.
- With `NFL_MCP_DISABLED_TOOLS="get_league,get_rosters,get_matchups,get_transactions,get_user,get_user_leagues"`
  the running server registers **71** — exactly the six suppressed.
- `get_draft_board`, `recommend_draft_pick`, `simulate_draft` remain present.
- `from nfl_mcp import sleeper_tools` still exposes `get_rosters` / `get_league`
  as importable functions, so `draft_tools.py` (which does
  `from .sleeper_tools import get_draft, get_draft_picks`) still works.
- 10 new tests + 905 pre-existing = **915 passed, 2 skipped**.
- Ruff clean under the repo's `[tool.ruff]` config.

On your laptop:

```bash
cd ~/Projects/fantasy/nfl_mcp
git checkout -b feat/tool-allowlist
git am /path/to/fantasy-mcp/nfl_mcp-patches/0001-*.patch
pytest -q
ruff check .
git push -u origin feat/tool-allowlist
```

Two small deviations from the plan text, on purpose:

- The plan's minimal test set is 4 cases. The delivered patch has 10, including
  an "unknown names are ignored" case (so a typo degrades to a no-op) and a
  `wrapper` regression check on `@wraps` behavior — because `@timing_decorator`
  in `metrics.py` wraps every tool, and `fn.__name__` filtering only works if
  `functools.wraps` is preserving the identity. It is; the test pins that so a
  future decorator refactor cannot silently defeat the allowlist.
- The commit body notes the sleeper-tools-still-importable invariant. That is
  the reason to suppress rather than delete.

## Task 4 — Cloudflare worker

**Sketched but not deployed.** The plan warned this section was unverified;
the delivered version fixes the specific gaps the plan flagged and is validated
by `wrangler deploy --dry-run`.

Files in `cloudflare/`:

- `wrangler.jsonc` — `[[containers]]` binding with `class_name: NflMcpContainer`,
  matching `[[durable_objects.bindings]]`, and the required `[[migrations]]`
  block with `new_sqlite_classes` (missing in the plan sketch — wrangler refuses
  to deploy without it).
- `worker/index.ts` — real `Container` subclass extending
  `@cloudflare/containers`, with bearer-auth check + fail-closed on a missing
  `MCP_TOKEN` + constant-time-ish comparison + `WWW-Authenticate: Bearer` on
  401. The container reads `NFL_MCP_DISABLED_TOOLS`, `NFL_MCP_ADVANCED_ENRICH`,
  and optionally `ODDS_API_KEY` via the `envVars` property — **worker vars
  alone do not reach the container process**, so this forward is mandatory.
- `package.json` / `tsconfig.json` — pin `@cloudflare/workers-types@^5` (wrangler
  4.118 requires this; the initial attempt with `^4` failed peer-dep resolution).

Deploy from the fork root, not from `cloudflare/`:

```bash
cd ~/Projects/fantasy/nfl_mcp
cp -r /path/to/fantasy-mcp/cloudflare/* .    # wrangler.jsonc, worker/, tsconfig, package.json
npm install --no-audit --no-fund
openssl rand -hex 32                          # save this token; you'll paste it next
npx wrangler secret put MCP_TOKEN
npx wrangler deploy
```

Then run Plan Task 4 Steps 6–7 for real:

```bash
URL=https://nfl-mcp.<subdomain>.workers.dev
curl -s -o /dev/null -w "%{http_code}\n" $URL/health                        # expect 401
curl -s -H "Authorization: Bearer $MCP_TOKEN" $URL/health                   # expect 200 JSON
```

**Both must pass.** If Step 6 returns 200, the endpoint is open to the world —
stop and check the bearer secret is bound.

## Task 5 — runtime env

Do **not** set these on the Worker `[vars]` and stop there. This is the plan's
one real bug: the plan says to set them via "Cloudflare dashboard → Worker →
Settings → Variables", but Worker vars are the *Worker's* env, not the
*container's* env. The Python process running inside the container reads
`os.environ` and never sees Worker vars unless the Container class forwards
them.

The delivered worker forwards them for you. What that means concretely:

- `wrangler.jsonc` `[vars]` sets `NFL_MCP_DISABLED_TOOLS` and
  `NFL_MCP_ADVANCED_ENRICH` on the Worker. **These values are then forwarded
  to the container** by the getter/constructor in `worker/index.ts`.
- If you want to change the allowlist, either edit `wrangler.jsonc` and
  `wrangler deploy`, or (for one-off overrides) set them via the dashboard
  under the Worker — same forwarding path.
- `MCP_TOKEN` stays a Worker secret (bearer check runs at the edge, never
  reaches the container).
- `ODDS_API_KEY`, if you decide to add it, goes as a Worker secret. The
  worker already forwards it into the container conditionally.

`NFL_MCP_PREFETCH` is deliberately unset — its 900s background loop conflicts
with scale-to-zero and would bill for idle time.

## Task 6 — wire both clients

Verbatim from the plan; no session pre-work possible (both clients live on
your laptop). Copy the token from your password manager for the placeholders:

```bash
claude mcp add --transport http nfl-mcp https://nfl-mcp.<subdomain>.workers.dev/mcp/ \
  --header "Authorization: Bearer <token>"
# in Claude Code: /mcp  → expect "nfl-mcp connected", get_draft_board present,
# get_rosters absent.
```

`~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "nfl-mcp": {
      "command": "npx",
      "args": [
        "-y", "mcp-remote",
        "https://nfl-mcp.<subdomain>.workers.dev/mcp/",
        "--header", "Authorization: Bearer <token>"
      ]
    }
  }
}
```

Restart Claude Desktop, then run the Phase 1 acceptance test:
"Using nfl-mcp, build me a draft board for Sleeper league 1370188155843526656."
Real player names with VBD values — not an error, not a placeholder.

## Task 7 — routing rule

Delivered at `skills/fantasy-routing/SKILL.md`. Drop it in whichever location
Claude Code scans for skills on your machine (typically `~/.agents/skills/` or
project-local `.agents/skills/`), same way you'll install the Flaim skill in
Task 2.

The skill goes beyond the plan's minimal snippet: it carries a per-question
routing table and encodes the BE$TBallerz best-ball exception (draft only —
no waivers, no start/sit) so the model doesn't burn tokens giving stale
in-season lineup advice for it.

## Task 8 — flaim.app default league

Not code, no session action. On flaim.app: change `defaultSport` from
`basketball` to `football`, set a `defaultLeague`. Verify with `get_user_session`
that `defaultLeague` is now populated.

## Task 9 — routing eval

**Verified here.** Two additions to `evals/agent/`:

- `scenarios.py`: 8 new analytics scenarios (draft board variants, projections,
  SoS, streaming, weather). `find_leagues` picks up a `lane: "league_state"`
  marker because both of its expected tools (`get_user`, `get_user_leagues`)
  are on the duplicate list — with the allowlist active it *must* delegate to
  the companion server, not answer here.
- `test_routing_guard.py`: 11 offline pytest checks that pin the allowlist's
  contract:
    - every expected tool exists in the live registry (typo guard)
    - every asserted arg is a real parameter of some expected tool (schema drift guard)
    - the six duplicates are real (empty list would silently be a no-op)
    - with the allowlist active, the delta is *exactly* those six
    - every analytics scenario keeps at least one routable tool
    - every `lane: "league_state"` scenario has *all* its tools suppressed
    - draft tools survive the allowlist
    - Anthropic tool schemas rebuild cleanly under the filtered registry

Applied via patch `0002` — no API key needed to run:

```bash
cd ~/Projects/fantasy/nfl_mcp
git am /path/to/fantasy-mcp/nfl_mcp-patches/0002-*.patch
pytest evals/agent -q
```

Consider upstreaming patch `0001` to `gtonic/nfl_mcp` (the plan suggests this).
Patch `0002` uses `lane: "league_state"`, which is meaningful only to this
side-by-side deployment; if you upstream, drop the guard tests that reference
it or generalize the mechanism.

---

## Definition of done — status here

- [x] `NFL_MCP_DISABLED_TOOLS` implemented, tested, full suite green, ruff clean
- [x] Routing rule written
- [ ] Both repos forked under `allsxxing`, upstream remotes set — **needs
      laptop** (Task 1)
- [ ] Flaim skill installed and discoverable — **needs laptop** (Task 2)
- [ ] Container deployed; unauthenticated → 401, authenticated → 200 — dry-run
      passes; real deploy **needs Docker + Cloudflare Paid** (Task 4)
- [ ] Six duplicate tools absent from tool list; draft tools present — proven
      locally, needs re-check against deployed URL (Task 6 Step 2)
- [ ] `nfl-mcp` connected in Claude Code AND Claude Desktop — **needs
      laptop** (Task 6)
- [ ] Real draft board returned for league 1370188155843526656 — **the
      Phase 1 acceptance test** (Task 6 Step 5)
- [ ] Cold-start latency measured and recorded
