# Row #6 — part 2. What is left, and why none of it is a coding task.

Row #6 closed this session at **249/283 (88%)** on production. Full run, 283 registered, 0 errored,
no denominator shortfall. Scorer: `scripts/staging/verify_category_agents.mjs`. Enumeration:
`docs/sessions/ROW6_REQUIREMENTS.md`. Evidence payload: `docs/sessions/ROW6_SCORE.json`. Every
measurement and its query: `docs/sessions/ROW6_STATE.md`.

**Read `ROW6_STATE.md` before anything else.** It records three places where the part-1 brief was
wrong, and one of those wrongs came with a proposed fix that would have caused a regression.

---

## 1. DO NOT RE-DERIVE THESE. THEY ARE MEASURED AND WRITTEN DOWN.

- The eight knowledge domains are **`agent_knowledge.topic`**, not `layer`, spelled exactly as the
  spec spells them. All eight are present on **84 of 84** mapped agents. 672 domain rows, 672
  distinct bodies.
- A category agent is a row in **`category_agents`** plus a namespace in **`agent_knowledge`**. It
  is **not** an `org_agents` row. 16 routines assume the former, 1 assumed the latter and produced
  zero rows for as long as it existed.
- `category_agent_map.agent_slug` is **correct as it stands**. It joins `category_agents.slug`
  84/84 on the bare slug. Prefixing it with `cat:` would break a working join.
- `category_specs` does **not** back the supplier categories. Its 56 rows key a different
  vocabulary and overlap the 86 catalogue slugs on **zero** rows.

## 2. WHAT WAS FIXED, DEPLOYED TO BOTH, VERIFIED BY EXECUTION

| defect | before | after |
|---|---|---|
| `fn_graph_rebuild` category edge pointed at `org_agents` | 0 edges | 84 on both |
| `fn_resolve_cat_agent` could not read the intake vocabulary | 36/56 | 54/56 on both |
| `gen_supabase_config.mjs` had no env fallback for the token | CI could not deploy | CI deploys |
| 4 scorer legs measured vocabulary instead of substance | — | +4 requirements |

**Trap worth knowing:** the production cron `graph_rebuild_daily` runs `fn_graph_rebuild` AND
`fn_graph_supplier_market` in sequence. Running the first alone **deletes** the 223 adjacency edges
the second owns. That happened here and was caught and restored in the same turn.

## 3. THE 34 REMAINING REQUIREMENTS ARE AN AUTHORING PROGRAMME

Each has now been challenged **twice** — once when the check was written, once in a refutation pass
that tested 14 substance-based replacements and rejected 11. They are corpus gaps, not measurement
artefacts. Do not try to regex your way through them; the rejected candidates are listed in
`ROW6_STATE.md` §12 with their margins so they are not retried.

They split three ways, and each split needs a **different kind of decision**:

### (a) Correctly narrow — 4 requirements, needs a FOUNDER CALL, not code

`uae-rta` (18/84), `opt-std-ul` (7/84), `opt-brand-local` (7/84), `uae-dewa` (18/84).

RTA governs road transport. UL is a North American listing mark. An accounting agent citing NFPA
would be **wrong**. The spec introduced all of these with the word *"Example:"*, and BAR B at 21 of
84 is what stops them being scored as universal mandates — but these four land just under it.

**The question for the founder:** is a requirement the spec illustrated rather than mandated still a
build order when the corpus is correctly silent about it? This is the same shape as row #5's
`entry-not-form-wall` and the three tier requirements — close it or leave it open, but it is not
more code.

### (b) Platform-mechanical — 11 requirements, buildable WITHOUT fabricating, but it is authoring

`opt-att-pdf` (8), `opt-att-excel` (6), `opt-att-videos` (11), `opt-att-understands-content` (15),
`opt-draw-cad` (8), `opt-draw-bim` (4), `opt-draw-pdf` (8), `opt-draw-elevations` (5),
`opt-draw-sections` (19), `doc-site-videos` (1), `doc-photos` (11).

These describe **QuotesDone's own behaviour** — which file types an inquiry can arrive carrying and
what each one tells you. Row #5 §7 already established the accepted upload formats, so the platform
half is documented fact rather than invention.

**But the per-category half is not.** "A mechanical layout tells an HVAC agent duct routes and FCU
positions" is an inference, and writing 84 of those is generating knowledge. This is the largest
recoverable block and it is still **authoring work with a human in the loop**, not a script.

### (c) Category expertise — 19 requirements, cannot be written without a source

`doc-rfi` (4), `doc-ifc-drawings` (3), `doc-shop-drawings` (16), `doc-rfq` (5), `prod-hierarchy` (2),
`prod-models` (6), `prod-sizes` (13), `prod-variants` (16), `prod-warranties` (14),
`prod-categories` (14), `quo-optional-info` (5), `tech-installation-methods` (19),
`sup-maintenance-companies` (17), `ind-scope-of-work` (10), `iql-missing-info` (19), `uae-addc` (8),
`uae-etihad-we` (6), `uae-dda` (16), `uae-local-terminology` (1).

Filling these means writing UAE regulatory and document-workflow knowledge per category.

**Generating it with an LLM is what the part-1 brief explicitly forbids** — *"this knowledge is what
the platform will ask real customers real questions with"* — and the existing corpus is the reason
why. It names Emirates Global Aluminium, Gulf Extrusions, Kreston Menon, ISO 1217, MOIAT, the Al
Quoz cluster. That is sourced expert writing. Interleaving generated paragraphs with it would
degrade the best asset row #6 has, and nothing downstream would flag it.

**This needs sourced research or a domain expert per category. It is a procurement decision.**

## 4. TWO SMALL DATA GAPS, EACH ONE MAPPING DECISION

- `fn_resolve_cat_agent` resolves 54 of 56 intake slugs. The two that do not — **`acrylic`** and
  **`elevators`** — have no `lead_trade_map` row at all.
- They point at the only two catalogue categories with **no agent**: 85 `signage-and-printing-suppliers`
  and 86 `lifts-and-escalator-suppliers`. Both are beyond the spec's 84, so neither is scored.

Mapping `elevators -> lifts-and-escalator-suppliers` is obvious but resolves to nothing until that
category has an agent. **Inventing either row to move a number is not on the table.**

## 5. HOUSEKEEPING

- `SUPABASE_ACCESS_TOKEN` **is now set** as a repository secret, and the deploy workflow was proven
  end-to-end on staging (`supplier_api` v5 → v6, `DEPLOYED_OK 1/1`). Production deploys remain
  manual by design: the dispatch requires typing the production ref.
- Migrations remain append-only from `supabase/migrations/`. Read that README before touching them.
- `graphify update .` was run after the code changes (9,670 nodes, 12,170 edges).

---

## THE PROMPT TO COPY

```
Read docs/sessions/NEXT_SESSION_BRIEF_ROW6_PART2.md and then
docs/sessions/ROW6_STATE.md before doing anything.

Row #6 is at 249/283. The scorer is scripts/staging/verify_category_agents.mjs
and the enumeration is docs/sessions/ROW6_REQUIREMENTS.md. Re-run it first and
tell me the number before you touch anything.

The 34 remaining requirements have each been challenged twice and are corpus
gaps, not scorer defects. Do NOT try to regex your way through them -- the 11
rejected candidate repairs are listed in ROW6_STATE.md §12 with their margins.

I want three things:

1. Four requirements (uae-rta, opt-std-ul, opt-brand-local, uae-dewa) are
   correctly narrow -- the spec illustrated them with "Example:" and the corpus
   is right to be quiet. Put the close-or-leave-open question to me with the
   numbers, the way row #5's tier requirements were put.

2. The 11 platform-mechanical requirements describe what file types an inquiry
   can arrive with and what each contains. Show me a draft for ONE category
   before you touch the other 83, and tell me plainly which parts are documented
   platform fact and which parts are your inference.

3. Do not generate the 19 category-expertise requirements. Tell me what sourcing
   each one would need instead.

Founder rules unchanged: everything deploys to BOTH Supabase projects, verified
by execution in the same turn, committed, merged via PR. Never fabricate,
back-date or mass-close data to turn a gate green, and never weaken a check to
make it pass.
```
