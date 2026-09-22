# P2-C1 — the eleven-subcategory MEP review matrix

**Stage A deliverable. Required before Stage B. Nothing here is approved — every row is a question.**
Live source: `public.mep_subcategory_review`. Generated 2 August 2026 from the imported corpus.

---

## 1. The trade taxonomy answered itself

Open question 1 of the Stage A design asked which subcategories belong to which trade, and expected
it to be decided by hand. It did not need to be. Route 8's eleven subcategories map onto routes
9, 10 and 11 exactly — **2 + 6 + 3 = 11** — and **zero subcategories map to two trades**:

```sql
-- returns no rows
select subcategory_slug from kb_operational_route_map
 where catalog_num in (9,10,11,12,13,14)
 group by subcategory_slug having count(distinct trade) > 1;
```

**Fire and ELV have no route-8 subcategory at all.** They are real trades (routes 12/13 and 14)
that join an MEP group only when a drawing or the customer puts them there. The model supports
five trades; the corpus supports three. That gap is the point of "the ability to add a trade
detected in drawings but absent from the customer's text".

## 2. The matrix

`shared` / `technical` are **field identities** — what the customer is actually asked once shared
fields collapse to one. `m` / `o` are raw corpus question rows.

| # | Subcategory | Primary trade | Secondary (question) | m | o | shared ids | technical ids | shared mand. | tech. mand. | Authorities named |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | HVAC equipment (chillers, AHUs, FCUs, VRV/VRF) | hvac | — | 11 | 95 | 8 | 36 | 4 | 7 | Civil Defence, DEWA, DoE, du |
| 2 | Ducting, grilles, diffusers & accessories | hvac | fire | 13 | 90 | 8 | 35 | 4 | 9 | Civil Defence, DCD, DEWA, DoE, du |
| 3 | Plumbing fixtures, fittings & sanitaryware | plumbing | — | 12 | 89 | 8 | 34 | 4 | 8 | Civil Defence, DEWA, DoE, du |
| 4 | Pipes & fittings (all types) | plumbing | fire | 13 | 92 | 8 | 36 | 4 | 9 | Civil Defence, DEWA, DoE, du, SEWA |
| 5 | Drainage, sewage & water treatment | plumbing | — | 10 | 99 | 8 | 38 | 4 | 6 | Civil Defence, DEWA, DoE, du, SEWA |
| 6 | Electrical cables, wiring & accessories | electrical | fire, elv | 15 | 88 | 8 | 35 | 4 | 11 | Civil Defence, DCD, DEWA, DoE, du |
| 7 | Switchgear, panels, distribution boards | electrical | fire | 15 | 90 | 8 | 36 | 4 | 11 | Civil Defence, DEWA, DoE, du |
| 8 | Generators, UPS & power systems | electrical | fire | 13 | 94 | 8 | 37 | 4 | 9 | Civil Defence, DCD, DEWA, DoE, du |
| 9 | Transformers & power quality equipment | electrical | — | 12 | 89 | 8 | 34 | 4 | 8 | Civil Defence, DCD, DEWA, DoE, du |
| 10 | Lighting (general, emergency, architectural) | electrical | fire | 12 | 93 | 8 | 36 | 4 | 8 | Civil Defence, DCD, DEWA, DoE, du |
| 11 | Earthing & lightning protection | electrical | — | 11 | 90 | 8 | 34 | 4 | 7 | Civil Defence, DEWA, DoE, du |
| | **Total** | | | **137** | **1,009** | | | | | |

**Question ownership, uniformly:** MEP (route 8) owns the shared project fields only. Every
technical field on every row is owned by its trade workstream and may not satisfy another trade —
enforced by `fn_inquiry_answer_set`, proved by Stage A test 2.

## 3. What this does to the 1,146-question problem

A full MEP package (HVAC + electrical + plumbing) asks:

| | Before | After |
|---|---|---|
| Mandatory question rows | **137** | **73** |
| — of which shared, asked once | 0 | 4 |
| — of which trade-specific | 137 | 69 |

**64 duplicate mandatory questions removed**, structurally: `inquiry_workstream_requirement` is
unique on `(workstream_id, field_id)`, so eleven subcategories each asking for the project emirate
collapse to one row. There is no de-duplication pass that anyone can forget to run.

## 4. Secondary applicability — six open questions

Never automatic, never many-to-many. Each is recorded with its reason and stays unapproved:

| Subcategory | Secondary | The question |
|---|---|---|
| 2 Ducting | fire | Fire and smoke dampers sit in the duct but are certified under Civil Defence. HVAC or fire? |
| 4 Pipes & fittings | fire | Sprinkler pipework is pipework, but route 12 owns fire pumps/sprinklers/valves/fittings. |
| 6 Cables & wiring | fire, elv | Fire-rated cable and ELV containment are electrical products with fire and ELV acceptance criteria. |
| 7 Switchgear | fire | Fireman switch and life-safety circuit segregation have a fire acceptance path. |
| 8 Generators & UPS | fire | Life-safety power to fire systems is a Civil Defence requirement, not only an electrical one. |
| 10 Lighting | fire | Emergency lighting and exit signage is a *separate* subcategory under routes 12 and 13. The same product is described in two places; one owner must be chosen. |

Row 10 is the sharpest: the corpus already describes emergency lighting twice, in two routes.
Whichever way it is decided, it should be decided once and written down.

## 5. Field identity — decided by test, not by opinion

Open question 2 is closed by the approved amendment. This session mechanised it: a candidate is
promoted to `shared` **only if every subcategory asking for it asks the same question with the same
answer type**. Result: **8 shared, 543 trade-specific, 13 carrying an open question.**

Three findings from the corpus that the test caught:

- **`required_date` = `required_completion_date`.** Identical question text, identical
  `date_or_period` answer type, different spelling in routes 8 vs 12/13/14. Safely one identity.
  This is exactly why raw `field_key` cannot be the identity.
- **`installation_environment` ≠ `environmental_conditions`.** One asks "buried, concealed, exposed,
  shaft, roof or plant-room" (`multi_select`); the other asks "ambient and environmental
  conditions" (`text`). Similar names, different questions. **Not merged.** Merging them would have
  been a wrong-sharing failure reaching dispatch.
- **`quantity_and_unit` carries two answer types** in the corpus (`quantity_with_unit` and
  `structured_number`). Trade-specific on evidence, not judgement.

### Questions for the founder on field identity

| Field | Why it is a question |
|---|---|
| `brand_policy` | Split **only** because the corpus says "brand **and** approved-equal policy" in routes 9/10/11 and "brand **or** approved-equal policy" in 12/13/14, with an identical answer type. Probably one shared field. Merging is a one-line change to the candidate table. |
| `project_type` | Two texts ("project type and occupancy" vs "project or facility type") and two answer types. *Occupancy* is a life-safety concept — this may be genuinely two fields. |
| `governing_documents` | Two texts and two answer types (`document_list` vs `documents_or_text`). The validation differs, so it fails the identical-validation condition as written. |
| `scope_mode` | Two texts ("required scope" vs "required commercial scope"). Split defensively: a shared supply-only answer satisfying an install-inclusive trade is a wrong dispatch. |
| `warranty_maintenance` | Warranty terms differ by equipment class. Split defensively. |
| `design_responsibility` | Design and calculation responsibility is usually per package, not per project. Split defensively. |

Every one of these defaults to **split**, because the amendment says wrongly sharing costs a wrong
dispatch and wrongly splitting costs one extra question.

## 6. What is NOT settled by this matrix

Stage A design open questions 3, 4 and 5 remain open and are unchanged by this work:

3. **Reactivation window** — Stage A restores a reactivated trade's answers at original precedence.
   `stale_since` is not implemented; if a trade returns after six weeks its old answers are trusted.
4. **RFQ mode timing** — `rfq_mode` sits on the group and defaults to `coordinated`. Whether the
   customer chooses it, it is inferred from trade count, or it is decided at dispatch, is undecided.
5. **Document-vs-document conflicts** — two sheets of the same drawing set disagreeing currently
   takes the same path as drawing-vs-text. It may want a different one.
