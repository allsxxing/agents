---
name: fantasy-routing
description: Route fantasy-football questions to the right MCP server. Two servers, two lanes — Flaim owns league state, nfl-mcp owns analytics. Loads whenever the user asks about a Sleeper league, draft, roster, matchup, waiver, trade, projection, playoff odds, or start/sit call. Also carries the three league IDs so the model never has to ask "which league?" for the common owner.
---

# Fantasy MCP routing

Two servers. Do not confuse them. Route every fantasy question to exactly one.

## Flaim — league state

Standings, rosters, matchups, transactions, free agents, past seasons, whose team is which.
Call `get_user_session` first, always. Then `get_league_info` before any per-league data
tool, unless you're branching to `get_ancient_history` or answering from session data alone.
See the Flaim MCP's own instructions for the full protocol.

## nfl-mcp — analytics

Draft boards, live draft-pick recommendations, mock drafts, projections (per player and per
opportunity), trade fairness, playoff odds, waiver dashboards / FAAB bids, strength of
schedule (regular + playoff weeks), streaming options, weather, Vegas lines, injury
reports, coaching tendencies, opponent scouting. If a question is about **what to do next**
rather than **what is currently the case**, it's this lane.

## Which tool for which question

| Question shape                                           | Server  | Tool(s)                                    |
| -------------------------------------------------------- | ------- | ------------------------------------------ |
| "Who's on my team / roster / bench?"                     | Flaim   | `get_roster`                               |
| "Standings? Who am I playing this week?"                 | Flaim   | `get_standings`, `get_matchups`            |
| "What free agents are available in my league?"           | Flaim   | `get_free_agents`                          |
| "Who's been added/dropped/traded in my league lately?"   | Flaim   | `get_transactions`                         |
| "Build me a draft board" / "who should I take at pick N" | nfl-mcp | `get_draft_board`, `recommend_draft_pick`  |
| "Run a mock draft from slot 7"                           | nfl-mcp | `simulate_draft`                           |
| "Project X's points this week"                           | nfl-mcp | `project_player`, `project_players`        |
| "Set my optimal lineup" / "start Player A or B?"         | nfl-mcp | `analyze_full_lineup`, `compare_players_for_slot` |
| "Playoff odds in league X"                               | nfl-mcp | `get_playoff_odds`                         |
| "Is trade [X for Y] fair?"                               | nfl-mcp | `analyze_trade`                            |
| "Waiver wire dashboard / FAAB bid"                       | nfl-mcp | `get_waiver_wire_dashboard`, `recommend_faab_bid` |
| "Rest-of-season / playoff-weeks SoS"                     | nfl-mcp | `get_strength_of_schedule`, `get_playoff_sos` |
| "Streaming DST/K/QB/TE this week"                        | nfl-mcp | `get_streaming_options`                    |
| "Injuries / inactives / high-confidence status"          | nfl-mcp | `get_injury_report`, `get_gameday_inactives` |
| "Weather / wind for this week's games"                   | nfl-mcp | `get_weather_forecast`                     |
| "Best QB+WR stacks this week"                            | nfl-mcp | `get_stack_opportunities`, `get_vegas_lines` |

**Do not** ask Flaim analytics questions (projections, trade fairness, playoff odds) or
ask nfl-mcp league-state questions (my roster, current standings, my matchup this week).
The nfl-mcp instance is deployed with `NFL_MCP_DISABLED_TOOLS` suppressing the six
Sleeper league-state tools that duplicate Flaim, so any attempt to route a Flaim
question there will simply not find a tool.

## The three leagues

All Sleeper football. When the user says "my league" without naming which one, resolve
via Flaim's `defaultLeague` if set; otherwise ask by name (never expose the numeric ID
back to them).

| League ID              | Name                | Team | Notes                                     |
| ---------------------- | ------------------- | ---- | ----------------------------------------- |
| `1370188155843526656`  | 🏈10 FOR $10❌      | 1    | 12-team standard                          |
| `1389735971536252928`  | ✖️1️⃣2️⃣✖️           | 1    | 12-team                                   |
| `1387653979617386496`  | BE$TBallerz         | 2    | Best ball: draft only. No waivers, no start/sit. |

For BE$TBallerz, decline lineup and waiver questions with "best ball — no in-season
lineup management" rather than answering with stale advice.

## What neither server can do

Both are read-only. Neither can change a lineup, add, drop, submit a waiver claim, or
propose or accept a trade in Sleeper. If asked, say so plainly and stop — do not offer
to "prepare" or "draft" the action, because there is no follow-through path.
