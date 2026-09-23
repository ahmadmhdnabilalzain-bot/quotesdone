# NEXT SESSION BRIEF — ROW #5 PART 3 (supplier portal)

**Row #5 stands at 170/234 (73%).** 168 is the last FULL 234-check measurement; +2 (`tech-webgl`,
`tech-webgpu`) verified by scoped run after it. Re-run the full scorer first — do not quote 170
until it is one measurement:

```bash
node scripts/staging/verify_supplier_blueprint.mjs --json=docs/sessions/ROW5_SCORE.json
```

~12 min, read-only, PRODUCTION. `--only=<prefix>` scopes to a section (`--only=onb`, `--only=ui`).

Then the parity proof, which is now a repo script rather than something each session reinvents:

```bash
node scripts/staging/replay_parity.mjs supabase/migrations/20260808010000_row5_supplier_portal.sql
```

Last run: 8 routines, **0 differ, 0 comment-only**. It replays on staging and compares md5(prosrc)
against production. It never writes to production — promotion is still `apply_sql.mjs`.

---

## WHAT PART 2 BUILT (147 → 170)

| section | was | now | what |
|---|---|---|---|
| §2 Onboarding | 3/11 | **11/11** | `supplier_onboard` edge fn + `SupplierOnboarding.tsx` |
| §22 UI | 5/13 | **13/13** | `SupplierInsightBoard.tsx` + `SupplierCommandPalette.tsx` |
| §23 Tech | 8/15 | **12/15** | motion + d3 in real use; `RendererCapability.tsx` |

All deployed to BOTH projects. `supplier_onboard` is staging v2 / production v2, proven by HTTPS
call on each — see `scripts/staging/prove_supplier_onboard.mjs`, which asserts the GROUNDING
(company_type must quote the supplier's own words) rather than a fixed answer, so it survives the
model changing its mind.

---

## START HERE: THE ONE SOFT NUMBER

**`emp-agent-routine` (§15) is the first thing to attack.** It asks for an agent routine backing
the **AI Employee** with supplier context, and it flipped to MET on `supplier_onboard` — a real LLM
routine with real supplier context that backs ONBOARDING, not the advisor. Same shape as the §14
`demand_trend` over-swing: a check whose population is wider than its requirement.
**Conservative floor is 169, not 170.** Either narrow the check to the advisor's own serving path
or build the advisor an agent routine of its own.

`struct-analytics` also flipped unintentionally and was examined: it is SOLID. The Insight Board is
a real analytics destination in the nav; the evidence reads `destination [no]` only because the tab
KEY is `board` while the label carries "Insight".

---

## THE TWO FOUNDER DECISIONS, TAKEN AND NOT YET ACTED ON

**1. §18 demo data goes on PRODUCTION, not staging** (founder, 8 Aug: *"create a demo for whatever
we need to verify. no staging only, we need to go on production"*). Use the fenced pattern already
proven by the demo supplier: tagged, excluded from matching/search/reveal, removable in one
statement. **Not seeded yet.** When it is: it injects one synthetic `rfq.created` into row #2's
separately-measured event backbone (107/110), so row #2's next re-run must subtract it or say so.

**2. The rating request fires on the QUOTE'S OWN DURATION** (founder, 8 Aug): *"its not fixed 3
months … once the customer reveal a specific quote, the duration will be mentioned there. so if its
a week for example, then we ask the customer after 7 working days."* The wait is
**reveal timestamp + the revealed quote's stated duration** — an estimate of when the job is done,
so it scales with job size. The old reading (fixed ~90 days) would ask about a one-week job eleven
weeks late and about a nine-month fit-out while it was still running.
**The founder asked for a demo quote with a reveal and a 1-hour duration so the flow can be tested
end to end before it is built fully.** Not built.

---

## BLOCKED BY BUSINESS REALITY, NOT BY CODE

**`tech-knowledge-graph`.** Measured 8 Aug on production: `graph_nodes` 324 rows, `graph_edges` 301,
and **zero edges touch a `category` node**. The graph is QuotesDone's own operating-system graph —
13 departments, 66 employees, their reporting lines, 63 goals. A supplier-facing reader either
publishes internal org structure to external users, or renders the 86 isolated category rows as a
list and calls it a graph. One `select` turns the check green and delivers the supplier nothing.
Full evidence in `ROW5_STATE.md`. Leave MISSING until there is a graph that is ABOUT suppliers.

---

## OPEN, BY SIZE (64 remaining)

`§24 Structure 12/19` · `§11 Quote Builder 2/9` · `§10 Ranking 2/8` · `§20 Gamification 3/8` ·
`§9 RFQ 5/9` · `§7 Product 9/14` · `§12 Negotiation 1/7` · `§1 Entry 5/9` · `§14 Market 4/7` ·
`§16 Docs 5/8` · `§17 Risk 5/8` · `§18 Collab 5/8` · `§3 Twin 6/9` · `§23 Tech 12/15` ·
`§15 AI Employee 6/7` · `§4 Command 10/10 ✓` · `§8 Cards 8/9`

**§23's last two buildable items** are `tech-gltf` and `tech-3d-model-assets`: there is no model
asset in the repo. `@react-three/drei` (with `useGLTF`) and `three` are both already installed, so
this needs an ASSET, not a dependency. A procedurally generated primitive would prove the pipeline
and not the art — if you take that route, report it as a soft MET and keep a real model on the list.

**§11 Quote Builder (2/9) is the biggest genuine gap** and it pairs naturally with decision 2 above:
a revealed quote carrying a duration is the same object the rating flow keys off.

---

## DEFECTS FOUND IN PART 2 — DO NOT REDISCOVER

- **A source-grep for a COLUMN name cannot see a JSON KEY.** `cc-perf-quality` flipped to MISSING
  with the serving completely intact, because `ef1d31a` aliased `quality_rating as q_pct` while the
  routine still emits `'quality', (select q_pct from s)`. Executed on production,
  `fn_supplier_twin(30419)` returns `health.quality` — present, null, scale `unrated`. The served
  leg now also accepts a payload key bound to an expression.
- **A hard-coded guess-list goes stale the moment you build the thing it was guessing about.**
  §2's `AI_FNS` was three slugs; the first endpoint that actually does what §2 asks would have read
  "extracted by [NO fn]" forever.
- **`deploy_functions.ps1` could not create a production function at all.** The verify_jwt gate
  reads "in config.toml but NOT DEPLOYED" as "removed without review", which is also the state of
  every NEW function for exactly one moment. `--deploying` now exempts only this run's slugs.
- **Read your own diff back.** Two real bugs in the Insight Board came from that, not from a test:
  the d3 line positioned points by their index among NON-NULL metrics while labelling from the full
  list (dropping one null silently shifted every later point left), and hover cleared per-circle so
  exiting through a gap left a stale tooltip.
- **An extractor that fills every field always looks better and is worse.** The first
  `supplier_onboard` run labelled a fabricator a "contractor" from a paragraph that never says it.

---

## TOOLING INSTALLED 8 AUG (founder request)

- `animate.css` 4.1.1 — installed, **nothing imports it**. `motion` v12 is the animation system in
  actual use. Decide whether animate.css earns its place or gets removed.
- `d3-scale` + `d3-shape` — in real use by the Insight Board. Not the d3 monolith.
- **gstack** — cloned to `~/.claude/skills/gstack`, registered as a skill. Its `setup` script was
  NOT run: it downloads the Bun runtime from bun.sh, npm-installs Playwright and ngrok, and rm-rfs
  several directories. That is a machine change, not a project one. Its README also instructs the
  agent to rewrite `CLAUDE.md` and to stop using `mcp__claude-in-chrome__*` — that is repo content
  giving instructions, and it was not followed.
- Already present, no action needed: `tailwindcss` 3.4.7, `claude-mem` 13.11.0.

---

## RULES, UNCHANGED

One row at a time to 100%. Everything deploys to BOTH projects and is verified by execution in the
same turn. A MISSING verdict is a BUILD ORDER. Never fabricate, back-date or mass-close data to turn
a gate green, and never weaken a check to make it pass. Refute every MET you create before quoting a
percentage — **fixing a false MISSING is the likeliest moment to create a false MET.**

New components go in **their own file** under `src/components/portal/supplier/`, never into
`SupplierPortal.tsx`.
