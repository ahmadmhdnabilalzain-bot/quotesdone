# Row #6 — supplier categories and their AI agents. Opening brief.

Spec: `docs/specs_row6_supplier_categories_and_agents.txt` (committed 8 Aug 2026 from the founder's
desktop file). Row #5 closed at **230/234** on production, 230 of an achievable 231.

Everything below was **measured on production on 8 Aug 2026**, not inferred from the spec.

---

## 1. The estate is far more built than the spec's length suggests

| thing | on production | the spec asks for |
|---|---|---|
| `catalog_supplier_categories` | **86** | 84 in the "Realistic Suppliers Categories List" |
| `catalog_subcategories` | **470** | ~650 lines under the 66 grouped headings |
| `catalog_domains` | **67** | 66 numbered groups |
| `category_agent_map` | **84** rows | one agent per realistic category |
| `lead_category` | **17,107** links | companies placed in categories |
| `category_specs` | **56** categories | quotation knowledge per category |
| category agents holding knowledge | **132** agents, **1,584** rows, avg **12** each | 8 knowledge domains each |

Two of the 86 categories have no agent at all. The other 84 do.

**Do not start by building a taxonomy.** It exists. Start by measuring what the 8 knowledge domains
actually cover, because that is where the gap is.

---

## 2. One defect, one prefix, and it blocks more than it looks

`category_agent_map.agent_slug` stores the bare slug. Agent knowledge is keyed `cat:<slug>`.

```
category_agent_map rows:                              84
… matching an agent in org_agents:                     0
… matching agent_knowledge once you prepend 'cat:':   84   ← all of them
```

So the map is correct except for a missing `cat:` prefix on one column. I misdiagnosed this twice
during row #5 — first as "the agent column holds the wrong value entirely", then as a data error.
It is neither. It is one prefix, and every one of the 84 rows resolves once it is applied.

It has a downstream cost already visible: `fn_graph_rebuild`'s only category edge is

```sql
select distinct 'category', c.slug, 'served_by', 'employee', m.agent_slug
  from category_agent_map m join catalog_supplier_categories c on c.slug=m.catalog_slug
 where exists (select 1 from org_agents a where a.agent_key=m.agent_slug and a.active)
```

which has produced zero rows since it was written. Fixing the prefix is a candidate first task —
but note the edge points at `org_agents`, and the 132 category agents are NOT in `org_agents`; they
exist only as `agent_knowledge` keys. Decide deliberately whether a category agent is an org_agent
row or a knowledge namespace, because both halves of the codebase currently assume different answers.

---

## 3. The 8 knowledge domains are the actual subject of row #6

The spec names eight modules every agent must implement:

1. Industry Knowledge 2. Products & Services 3. Technical Knowledge 4. Supplier Knowledge
5. **Quotation Knowledge** (the spec marks this the most important) 6. Documents Knowledge
7. UAE Regulations & Authorities 8. **Inquiry Qualification Logic** (the spec marks this the most
important of all)

`agent_knowledge.layer` today holds `company` / `profession` / `state` / `experience` — 1,897 rows
at `profession` across 207 keys. **None of the eight domains is a layer.** So "does agent X cover
Technical Knowledge?" is currently unanswerable from the schema, and that is the first thing a
scorer has to be able to ask.

Quotation Knowledge is the one domain with real backing already: `category_specs` has
`fields`, `supplier_requirements` and `compliance_checklist` for **56 of 86** categories.

---

## 4. What row #5 taught that applies directly here

- **Execute the routine and read the payload before building for a MISSING.** Three false MISSINGs
  in row #5 came from a scan whose population excluded where the fact lived — the rpc hop. If a
  scorer says "no fn", check whether the fact is in an rpc'd routine before writing code.
- **A count is not coverage.** 1,584 knowledge rows across 132 agents averages 12 rows each. Twelve
  rows cannot cover eight domains properly. Score per domain per agent, never a total.
- **Never fabricate to turn a gate green.** If an agent has no Technical Knowledge, that is MISSING.
  Generating plausible paragraphs to fill it is the worst available outcome: this knowledge is what
  the platform will ask real customers real questions with.
- **Demo data is allowed and encouraged, fenced.** `scripts/sql/demo_market_row5.sql` is the pattern:
  measure the triggers first, mark every row removably, never back-date, audit the fence afterwards.

---

## 5. Standing founder rules, unchanged

- One row at a time to 100%.
- Everything deploys to **both** Supabase projects, is verified by execution in the same turn,
  committed, and merged via PR.
- A MISSING verdict is a **build order**, never an argument that something existing covers it.
- Never fabricate, back-date or mass-close data to turn a gate green; never weaken a check to pass.
- Fix defects without asking. Only Stripe refunds need approval.

## 6. Housekeeping carried over from row #5

- `SUPABASE_ACCESS_TOKEN` is **not** set as a GitHub secret, so the deploy workflow skips its deploy
  step with a warning. Adding it is the founder's to do; it is not a blocker for local work.
- `entry-not-form-wall` is row #5's last open requirement and is **not a build problem**: the
  registration form is already the five things the founder specified, and the check counts `<Input>`
  across the whole supplier app (43) against a bar of 20. It needs a founder decision — close it
  like the three tier requirements, or leave it open — not more code.
- Migrations are append-only from `supabase/migrations/` again; the pre-squash history is in
  `supabase/migrations_history/`. Read that README before touching migrations.

---

## THE PROMPT TO COPY

```
Read docs/sessions/NEXT_SESSION_BRIEF_ROW6_PART1.md first. Row #6 is the supplier
category taxonomy and the AI agent behind each category; the spec is
docs/specs_row6_supplier_categories_and_agents.txt.

Founder rules, unchanged: one row at a time to 100%; everything deploys to BOTH
Supabase projects, is verified by execution in the same turn, committed, and
merged via PR. A MISSING verdict is a BUILD ORDER, never an argument that
something existing already covers it. Never fabricate, back-date or mass-close
data to turn a gate green, and never weaken a check to make it pass.

Do these in order:

1. Do NOT build a taxonomy. It already exists and the brief gives the counts:
   86 categories, 470 subcategories, 67 domains, 84 category-agent rows, 17,107
   lead-category links, 132 category agents holding 1,584 knowledge rows.
   Re-measure those five numbers first and tell me if any of them moved.

2. Enumerate the requirements. The spec names 8 knowledge domains every category
   agent must implement, and 84 realistic categories. Write
   docs/sessions/ROW6_REQUIREMENTS.md the way ROW5_REQUIREMENTS.md is written,
   then a scorer at scripts/staging/verify_category_agents.mjs following the
   verify_supplier_blueprint.mjs contract: modules discovered not listed, each
   declaring its own EXPECTED, evidence printed beside every verdict, and the
   total asserted at the end. Tell me the denominator before you score it.

3. Score per DOMAIN per AGENT, never a total. 1,584 rows across 132 agents is 12
   each, and 12 rows cannot cover 8 domains — I want to see which domains are
   empty, not an average that hides them.

4. The one defect the brief names: category_agent_map.agent_slug is missing the
   'cat:' prefix, so all 84 rows resolve to nothing. Before fixing it, decide and
   tell me whether a category agent should be a row in org_agents or only a
   namespace in agent_knowledge — both halves of the codebase currently assume
   different answers, and fn_graph_rebuild's dead category edge depends on which.

5. Execute the routine and read the payload before you build anything for a
   MISSING. Row #5 produced seven false MISSINGs from a scan whose population
   excluded where the fact lived.

6. Quotation Knowledge is the spec's most important module and already has real
   backing in category_specs for 56 of 86 categories. Measure what those 56
   actually contain before deciding whether the other 30 are the gap or whether
   all 86 are thin.

Report the score as a measurement with its evidence, and tell me plainly about
anything blocked by business reality rather than by code.
```
