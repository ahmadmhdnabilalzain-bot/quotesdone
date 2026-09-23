# NEXT SESSION BRIEF — ROW #5 PART 4 (supplier portal)

**Row #5 is 212/234 (91%). The achievable ceiling is 231, not 234** — see "Permanently closed"
below. Twenty of 24 sections are at 100%.

---

## 0. FIRST, RE-MEASURE. DO NOT TRUST THIS NUMBER.

```bash
node scripts/staging/verify_supplier_blueprint.mjs --json=docs/sessions/ROW5_SCORE.json
```

~12 min, read-only, PRODUCTION. `--only=<prefix>` scopes to a section (`--only=qb`, `--only=mkt`).

Then the two proofs that catch drift:

```bash
node scripts/staging/replay_parity.mjs supabase/migrations/20260808010000_row5_supplier_portal.sql
node scripts/staging/audit_session_parity.mjs
```

`replay_parity` replays the migration on staging and compares md5 against production.
`audit_session_parity` is new and broader: it checks all 16 routines, 3 edge functions, 3 cron jobs
and every demo fixture across BOTH projects, and asserts the production fences still hold. Last run:
**clean — nothing staging-only, 16/16 routines identical.**

---

## 1. THE STANDING AUTHORIZATION — READ THIS BEFORE FLAGGING ANYTHING AS DATA-BLOCKED

Founder, 2026-08-08, verbatim: **"as i said create demo for whatever is needed."**

This is a standing instruction and it supersedes the reflex to report a requirement as blocked by
empty tables. Production has 0 real customers and 0 real trading activity; that is a reason to BUILD
A FENCED DEMO, not a reason to stop. Thirteen of the twenty-two open requirements are open only
because nothing has traded yet.

**The fence pattern, already proven twice this session** (`scripts/sql/demo_inquiry_row5.sql`,
`demo_quote_row5.sql`):

- Mark the row so it is findable and removable in one statement (`brief_source='qd_demo_fixture'`,
  `source='qd_demo_fixture'`, `place_id='qd-demo-supplier-001'`, `ZZ DEMO —` in any human-visible text).
- **Measure the triggers before inserting, never assume.** `inquiries` has twelve. Eleven are
  database-only; the one that reaches outside (`trg_autodispatch_inquiry` → `dispatch_inquiry`) is
  gated on `NEW.rfq_ready is true`, so leaving `rfq_ready` NULL is the fence. `quotes` has nine and
  `transactions` five, three of which queue notifications addressed to a CUSTOMER — with
  `customer_id` NULL there is nobody to address.
- **Never back-date.** `fn_rating_due(p_now)` takes the evaluation moment as a parameter precisely
  so a schedule can be proven against untouched rows. A question is not a forgery.
- Audit the fence afterwards with `scripts/staging/audit_demo_fence.mjs` rather than claiming it.

**The demo seeding that would unblock the most: enough quoting activity for §11 and §14.** Both need
a market — several suppliers quoting the same category so an average price and a demand trend are
computed from something rather than invented. That is the single highest-value task in this brief.

---

## 2. FOUNDER DECISIONS ALREADY TAKEN — DO NOT RE-ASK

| decision | verbatim | state |
|---|---|---|
| Demo data location | *"no staging only, we need to go on production"* | done — fixtures on both |
| Demo creation | *"create demo for whatever is needed"* | STANDING — see §1 |
| Rating clock | *"its not fixed 3 months … so if its a week … we ask after 7 working days"* | built + proven |
| **Tier and matching** | *"no cancel that totally. a tier shouldnt effect a match."* | **CLOSED — see below** |

### Permanently closed by decision — these three are NOT build orders

```
game-benefit-more-rfqs           tier affects RFQ distribution
game-benefit-preferred-status    preferred-supplier status is conferred
game-benefit-visibility          tier affects visibility
```

A tier must never affect matching. **A green verdict on any of these three is a REGRESSION SIGNAL,
not progress.** They stay in the denominator on purpose — removing them would hide the decision.
`fn_supplier_tier` returns `affects_matching:false` so a future surface reads the position rather
than re-deciding it. **Ceiling: 231/234. §20's ceiling: 5/8.**

---

## 3. THE 22 OPEN, BY WHAT ACTUALLY BLOCKS THEM

**Needs demo trading activity (13)** — the standing authorization covers all of these:
- `§11 Quote Builder` ×7 — `qb-nl-intent`, `recommend-price`, `market-position`, `delivery-estimate`,
  `risk-level`, `warranty-suggestion`, `qb-routine`. Needs comparable quotes before a recommended
  price is anything but invented.
- `§14 Market` ×3 — `mkt-demand-trend`, `mkt-most-requested`, `mkt-avg-market-price`.
- `doc-used-for-count` — how many RFQs a document unlocked; needs RFQ history.
- `struct-quote-builder`, `struct-inventory` — sections that need something real behind them.

**Genuinely buildable now (6)**:
- `tech-gltf` + `tech-3d-model-assets` — needs a model ASSET; `three` and `@react-three/drei`
  (with `useGLTF`) are already installed, so this is not a dependency problem. A procedurally
  generated primitive would prove the pipeline and not the art — if you take that route, report it
  as a soft MET and keep a real model on the list.
- `struct-settings` — a real Settings section (language, notification preferences, account).
- `cc-assistant-actionable` — not yet examined this session.
- `entry-not-form-wall` — 26 controls against a bar of 20. Two true things: the count covers the
  whole supplier surface and part-4 additions (onboarding composer, workspace reply, negotiation
  draft, catalog picker) pushed it from 21, none of which is REGISTRATION; and separately the
  registration path still leads with `ProfileForm`, so §2's conversational onboarding is a parallel
  route rather than the default. **Making it the default is the real fix and is a product decision.**

**Blocked by what the data IS, not by volume (1)**:
- `tech-knowledge-graph` — measured: `graph_nodes` 324, `graph_edges` 301, and **zero edges touch a
  `category` node**. The graph is QuotesDone's own operating-system graph: 13 departments, 66
  employees, their reporting lines, 63 goals. A supplier-facing reader either publishes internal org
  structure to external users or renders 86 isolated category rows and calls it a graph. Leave
  MISSING until there is a graph that is ABOUT suppliers.

---

## 4. THE ONE RECURRING ROOT CAUSE — CHECK THIS FIRST ON ANY MISSING

**A scan whose population excludes where the fact lives.** It appeared in SEVEN sections this
session and every time the feature was already built:

| section | what was blind |
|---|---|
| §4 | `cc-perf-quality` — grepped a routine for a COLUMN name; the fact was a JSON key (`'quality', (select q_pct …)`) |
| §18 | `collab-project-identity` — the identity is a SUB-OBJECT (`'project', jsonb_build_object('title', …)`) |
| §18 | `collab-timeline-pct` — `delivered()` demanded the path inside JSX braces; the component binds it to a local first |
| §10 §12 §9 §16 | the **rpc hop** — the field lives in the rpc'd ROUTINE, and the edge action that calls it is a four-line passthrough |
| §3 | same hop, inside the twin's own endpoint list |

`servedBy`/`servedNear` (rpc-aware) now exist in `rfq_and_quoting.mjs`, `performance_and_risk.mjs`,
`collab_map_mobile_ui.mjs` and `command_and_environment.mjs`. **`RPC_NAMES` is derived from the
`.rpc('…')` calls in reachable edge functions, so following the hop widens nothing.**

Before building anything for a MISSING: execute the routine and look at the payload. Three times
this session the "missing" feature was answering 200 on production.

---

## 5. DEFECTS FOUND IN PART 3/4 — DO NOT REDISCOVER

- **Six false METs were removed; the score went DOWN twice before it went up.**
  `game-benefit-visibility` was MET on `ai_gateway`, whose "tier" picks a language model.
  `game-tier-assignment-routine` passed on `|| tierSql > 0`, counting 39 unrelated routines.
  Four §11 legs flipped off my own §12 build because `recommended_response` sits within 300
  characters of the words price, lead_time and warranty — the negotiation assistant explicitly
  REFUSES to recommend a price. **Fixing a false MISSING is the likeliest moment to create a false
  MET, and it happened twice from my own commits.**
- **`agent_actions` requires `agent` and has NO `actor` column.** `supplier_onboard`'s telemetry used
  `actor` inside a `try/catch`, so every write raised 42703 and was swallowed. A swallowed write
  looks exactly like a feature nobody used.
- **A hand-rolled `fetch` hides an endpoint.** `SupplierCatalogUpload` called
  `fetch(FN + '/supplier_catalog_ingest')` instead of `call('supplier_catalog_ingest', …)`, so the
  slug never appeared beside `call(` or `functions/v1/` and `prod-ai-extraction` read MISSING about
  a function that had just written three rows on production. Use the `call()` helper.
- **`spec` is jsonb.** Rendering it through `::text` puts raw JSON in front of a supplier; Postgres
  refuses it with 22P02, which is the right answer for the wrong reason.
- **`trg_gate_incomplete_match` silently returns NULL** unless `rfq_ready is true`, so an
  `inquiry_matches` row for a fenced fixture vanishes with no error. Use the MESSAGES leg —
  `public.messages` has no triggers at all.
- **Read your own diff back.** Three real bugs came from that, not from a test: a d3 line positioned
  by index among NON-NULL points, hover cleared per-circle so exiting through a gap left a stale
  tooltip, and a send handler whose `inquiry_id` resolved to `undefined` either way.
- **Match scoring: the denominator is the PRODUCT, not the brief.** Scoring matched terms over all
  the brief's words made the exactly-right product read 6%. Understating is as wrong as inflating.

---

## 6. CI IS GREEN — KEEP IT THAT WAY

`checks.yml` had **never** passed: 40 of 40 runs failed on `npm ci`, long before part 3. `next` pins
`@swc/helpers` to 0.5.15; `next-intl`'s bundled `@swc/core` peer-requires ≥0.5.17; npm 11 tolerates
the unsatisfied optional peer and npm 10 demands a nested copy the lock does not carry. CI ran Node
22 (npm 10) against a lockfile written by npm 11. **CI now runs Node 24 and passes.**

`package.json` has no `engines` field. Adding one would stop this drifting again but affects Vercel
deploys — founder's call, not taken.

---

## 7. RULES, UNCHANGED

One row at a time to 100% (here: to its 231 ceiling). Everything deploys to **both** Supabase
projects and is verified **by execution in the same turn**. A MISSING verdict is a BUILD ORDER.
Never fabricate, back-date or mass-close data to turn a gate green, and never weaken a check to make
it pass. **Refute every MET you create before quoting a percentage, and attack MISSING with equal
scepticism.**

New components go in **their own file** under `src/components/portal/supplier/` — never into
`SupplierPortal.tsx`.

Report the score as a measurement with its evidence, and say plainly what is blocked by business
reality rather than by code.
