# NEXT SESSION BRIEF — ROW #5 PART 2 (supplier portal)

**Row #5 stands at 148/234 (63%).** Spec: `docs/specs_row5_supplier_portal.txt`, 24 sections,
enumerated to 234 requirements in `docs/sessions/ROW5_REQUIREMENTS.md`.

Run the scorer first, before reading anything else:

```bash
node scripts/staging/verify_supplier_blueprint.mjs --json=docs/sessions/ROW5_SCORE.json
```

~12 minutes, read-only, PRODUCTION. 234 checks, zero errored, zero denominator warnings.
`--only=<prefix>` scopes to one section (`--only=prod`, `--only=ui`).

---

## EVERYTHING IS ON PRODUCTION. VERIFIED, NOT ASSUMED.

Re-run the parity proof at the start of the next session and after every change:

| what | state |
|---|---|
| 8 routines | md5-identical on staging **and** production |
| `supplier_score_refresh_daily` cron | active on both, 03:40 UTC |
| `supplier_portal` edge fn | staging v7 / production v20; **all 6 new actions answer 200 on both**, proven by HTTPS call |
| fenced demo supplier + 4 products + 4 variants | on both, unmatchable on two independent legs |
| `reviews` constraints + unique index | on both |
| migration | `supabase/migrations/20260808010000_row5_supplier_portal.sql`, replayed on staging |
| repo | PR #10 open, branch pushed, `main` tracks `origin/main` |

**The migration replay caught real drift** — two comments edited after promotion meant the repo and
production disagreed invisibly. Replaying the migration is how that surfaced. Do it again.

### The six actions now live
`twin` · `products` · `advisor` · `network_map` · `market` · `workspaces`

---

## SECTIONS COMPLETE (5 of 24)
§5 3D Environment 12/12 · §6 Profile 9/9 · §13 Performance 9/9 · §19 Network Map 7/7 · §21 Mobile 9/9

## OPEN, BY SIZE
`§2 Onboarding 3/11` · `§22 UI 5/13` · `§23 Tech 8/15` · `§24 Structure 11/19` · `§11 Quote Builder 2/9` ·
`§10 Ranking 2/8` · `§20 Gamification 3/8` · `§9 RFQ 5/9` · `§7 Product 9/14` · `§12 Negotiation 1/7` ·
`§1 Entry 5/9` · `§14 Market 4/7` · `§16 Docs 5/8` · `§17 Risk 5/8` · `§18 Collab 5/8` · `§3 Twin 6/9` ·
`§4 Command 9/10` · `§8 Cards 8/9` · `§15 AI Employee 6/7`

**§2 Onboarding (3/11) is the biggest single gap** and it is genuinely unbuilt: there is no
free-text → profile extraction path at all. `onb-extract-*` is 0/6.

---

## TWO THINGS WAITING ON THE FOUNDER

**1. §18 needs a demo inquiry to be proven with DATA.** The mechanism is built and deployed; the
data path is flagged, not faked. Inserting one inquiry on production fires **twelve triggers**,
including `fn_emit_event('inquiry','rfq.created')` — which injects a synthetic event into **row #2's
separately-measured event backbone (107/110)** — plus `trg_autodispatch_inquiry`. Matching would find
0 suppliers (none verified), so no real company would be contacted. **Ask before seeding.**

**2. The rating solicitation flow is specified but not built.** The founder's model (2026-08-08):
email + WhatsApp ~3 months after a job, asking for 1–5 plus a short written reason. Needs completed
jobs; production has 0 quotes. Also unbuilt: surfacing the rating in the CUSTOMER's comparison view,
which is row #4's surface.

---

## THE DEFECT CLASSES — CARRY THESE IN, DO NOT REDISCOVER THEM

Twelve refutation rounds. Rounds 1–6 removed **24 false METs**; rounds 7–12 were the mirror image.

### The single recurring root cause: *a scan whose population excludes where the fact lives*
| blind spot | cost |
|---|---|
| `importClosure` followed `from` but never `import()` | **14 requirements**; §5 read 2/12 with an R3F scene shipping |
| served-leg searched edge TypeScript; fields live in the rpc'd SQL routine | recurred in §13, §7, §15, §14, §18 |
| `setTab('literal')` missed `const TABS = [...]` | 2 destinations seen, 10 real |
| checks pointed at the WRONG RELATION (`inv_items` has no `supplier_id`) | unsatisfiable by any correct implementation |
| demanded DB column names in JSX | unsatisfiable by any component that maps its payload |

### And the counter-lesson
**Fixing a false MISSING is the likeliest moment to create a false MET.** The rpc-hop fix over-swung
twice — §14 hit 7/7 when the stated ceiling was 4/7, because the routine *names* `demand_trend`
inside the block that returns `available:false`.

### Traps that cost real time
- **`node -e` through the shell eats `\y`**, so every `READERS()` scan run that way returns 0 —
  indistinguishable from "nothing exists". **All scorer work goes in files.**
- **A write keyword inside a regex literal still looks like a write to qd_guard.** `drop` in a
  monitor pattern aborted a whole module and hid 4 checks from the denominator.
- **`Q()` splitting at char 2 is a no-op for the 2-letter keyword `do`** — an evidence query was
  refused and the check printed MET with an error where its proof should be.
- **Backticks and `$` in `node --input-type=module -e` get mangled by the shell.** Write a file.

---

## THE FOUR HONESTY RULES EVERY COMPONENT FOLLOWS
1. **Null is not zero.** A null metric renders "not rated yet" and draws no bar.
2. **Absent is not empty.** An empty list carries its POPULATION.
3. **A mention is not a delivery.** A field marked `available:false` is not "served".
4. **Estimates are labelled.** `production_capacity` returns `is_estimate:true` — and NULL for a
   real scraped lead rather than the spec's illustrative 12,000.

**Nothing on the supplier's screen is invented.** 0 inquiries means no demand trend, no loss
breakdown, no AI match percentage — each absent WITH its reason, never filled in.

---

## RULES, UNCHANGED
One row at a time to 100%. File order 1→8. Everything deploys to BOTH projects and is verified by
execution in the same turn. A MISSING verdict is a BUILD ORDER. Never fabricate, back-date or
mass-close data to turn a gate green, and never weaken a check to make it pass.

New components go in **their own file** under `src/components/portal/supplier/` — never into
`SupplierPortal.tsx` (81,811 chars, six unrelated features, cause of three refutation rounds).
