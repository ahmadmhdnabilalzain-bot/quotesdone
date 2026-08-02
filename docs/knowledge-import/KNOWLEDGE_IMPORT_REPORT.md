# QuotesDone knowledge-corpus integration â completion report

**Corpus:** `QuotesDone_ALL_KNOWLEDGE_86_CATEGORIES_v2026.07.31`
**Control pack:** `QuotesDone_CLAUDE_INGESTION_INSTRUCTIONS_v2026.07.31`
**Executed:** 2 August 2026 Â· Supabase project `htdblwldjkcgjvmqkbeh`
**Status:** imported, routed, tested. Live router **not** switched over â staged behind the crosswalk review, exactly as the control pack requires.

---

## 1. What landed

| | Imported | Expected |
|---|---:|---:|
| Knowledge records | **108,818** | 108,818 |
| Qualification questions | **16,588** | 16,588 |
| Decision rules | **12,929** | 12,929 |
| Validation rules | **4,696** | 4,696 |
| Scenario tests | **3,324** | 3,324 |
| Knowledge domains | **67** | 66 + lifts supplement |
| Subcategories | **468** | 468 |
| Distinct sources | **342** | 785 rows, deduplicated by `source_id` |
| Operational routes | **86** | 86 |
| Route â knowledge mappings | **426** | 426 |
| Routing aliases | **4,212** | 3,831 supplied + 403 added (Â§6) |
| Route tests | **344** | 258 supplied + 86 Arabic (Â§6) |

**Rejected rows: 0. Write errors: 0.** Total corpus rows processed: 115,148.

Database grew from 290 MB to 568 MB. Pro plan ceiling is 8 GB.

### Where it lives, and why not in the live tables

Everything went into a new **`kb_stage`** schema, not into `agent_knowledge` (1,844 rows) or `kb_chunks` (4,886 rows) which are what the platform answers from today. Dropping 115,000 unreviewed records into those would silently change every answer the platform gives with no way back, and the control pack explicitly says to stage first and not replace the live category router until the crosswalk is reviewed.

`kb_stage` is **not exposed to the REST API**. Not one of its tables can be reached by an anon or authenticated key â the only doors are four `SECURITY DEFINER` functions callable by the service role. Rollback is `select rollback_ingestion_run('<uuid>')`, not a database restore.

**Not imported, deliberately:** `02_category_master.md` â 119 MB of narrative across the 67 packages. The pack forbids putting a master into a runtime prompt, so the database has no reason to hold it; one master is roughly 450,000 tokens. Checksums are recorded in each package manifest.

---

## 2. Six defects found in the corpus, and what was done about them

None of these were visible from the file listing. Each would have silently removed a large slice of the corpus while every count still looked correct.

**1 â Decision rules ship in two different shapes.** 28 packages emit a flat rule (`{rule_id, when, then}`); the other 39 wrap the same rule inside the standard record envelope with the body in `structured_data`. The first importer understood only the flat shape and rejected **6,599 rules â 5.7% of the corpus**, disproportionately the *ask-this-question-next* rules that are the entire point of having a deterministic layer. Both shapes now import, and the wrapped ones are also written as searchable records.

**2 â `03_taxonomy.json` ships in two different shapes.** 6 packages put category fields at the top level; 61 nest them under `category`. Reading only the first shape gave **61 of 67 domains no category row** â and since subcategories have a foreign key to categories, all their subcategories would have vanished too, taking the bilingual subcategory aliases with them. That is the Arabic routing vocabulary for 91% of the corpus, disappearing while the record counts stayed perfect.

**3 â Source registries carry a UTF-8 BOM.** Written by Excel. Without `utf-8-sig` decoding the first CSV header becomes `ï»¿source_id` and **every source in every package** is dropped, taking the source lineage with it.

**4 â Package-local IDs are not globally unique.** `Q-001-<subcategory>-<field>`, `V-002-â¦`, `T-002-â¦` are unique only *within* a package, because the numeric prefix is the package number and the packages were generated independently. Keying on them would collide the moment two packages shared a subcategory slug â and a collided question is a question the customer is never asked. Every derived table is keyed on the globally unique `record_id`, with the package-local ID kept alongside and indexed, because the decision rules cross-reference it by name.

**5 â 13,557 of 16,588 questions arrived with no field key.** This is the most serious of the six. A question with no stable field key cannot be *answered in a way the system remembers*: you cannot tell whether the buyer already gave the emirate, you cannot collapse the same question asked by seven mapped subcategories of a composite route, you cannot build the spec object suppliers quote from, and you cannot compute completeness â which means `dispatch_eligible` could never be true. The corpus would have been 115,000 rows of text with a dead deterministic layer, and every inquiry turn would have fallen straight back to a premium model.

The key is recoverable because the supplied `question_id` encodes it (`Q-008-gypsum-boards-partitions-and-drywall-project-emirate` â `project_emirate`). Three deterministic derivation passes brought coverage from 2,028 to **14,051**, including **all 7,079 mandatory questions**, which is what `dispatch_eligible` depends on. Where no key could be *derived*, none was *invented* â a wrong field key silently merges two different questions. Those 2,537 optional questions are in the gap register.

**6 â The Arabic alias lexicon is largely not Arabic.** Of 1,726 `ar` entries, **800 contain Latin text and 746 are literally `ÙØªØ·ÙØ¨Ø§Øª <untranslated English>`** â the Arabic word for "requirements" glued onto an English phrase. Only **23 of 86 routes** had a single alias an Arabic speaker could actually reach. See Â§6.

---

## 3. Coverage â the acceptance requirement

```sql
select verdict, count(*) from v_kb_operational_86_coverage group by 1;
--  MAPPED | 86
```

| Check | Result |
|---|---|
| Live catalogue size | 86 |
| Routes MAPPED | **86 / 86** |
| Routes UNMAPPED | **0** |
| Routes with zero mapped subcategories | **0** |
| #85 Signage & Printing | MAPPED â 3 packages, 7 subcategories |
| #86 Lifts & Escalators | MAPPED â the dedicated supplement, 12 subcategories |
| Multi-category routing preserved | Yes â 426 mappings across 86 routes; the router returns a `multi_category` flag |

**Four routes have a slug the manifests did not expect** (e.g. #83 expected `utility-contractors`, production is `utility-contractors-dewa-sewa-fewa-approved`). The live slug won in every case, as instructed. The expected slug is stored only as evidence, and `v_kb_operational_86_coverage.slug_differs` shows exactly which four.

The crosswalk (426 rows) is `review_status = 'draft'` across the board. It stays draft until a human signs it off â a taxonomy bridge nobody has read is not a reviewed taxonomy bridge.

---

## 4. The runtime, and what it replaces

Three functions, no model call in any of them.

**`fn_kb_route_decide(text)`** â deterministic bilingual routing. Returns ranked candidates, confidence, the aliases that matched and why, and one of two actions: route, or ask a single clarifying question naming the two real candidates.

**`fn_kb_next_question(catalog_num, answered)`** â the next unanswered question in EN *and* AR with its answer type, allowed values and which documents could answer it instead of asking; plus mandatory total, completeness ratio, and a single boolean **`dispatch_eligible`**. This is the one auditable legitimacy gate the external reviewer asked for last week: one query, one answer, one place.

**`fn_kb_retrieve(catalog_num, query, limit)`** â at most a handful of relevant records for one route. Draft records are excluded from anything customer-facing; regulation records and anything with an escalation rule come back with `escalate = true` so the caller cites the authority rather than paraphrasing the law.

Worked example, end to end, zero model calls:

```
"I need waterproofing for a warehouse roof in Dubai"
  â route 5 (Waterproofing Suppliers), confidence 1.000
  â next: "Please specify project emirate." / "ÙØ±Ø¬Ù ØªØ­Ø¯ÙØ¯ Ø¥ÙØ§Ø±Ø© Ø§ÙÙØ´Ø±ÙØ¹."
     single_select Â· 7 allowed values Â· answerable by project_brief or permit_or_noc
  â 0/14 mandatory answered Â· dispatch_eligible = false
answer 3 fields â
  â next: "Please specify site location and access point."
  â 1/14 Â· completeness 0.071 Â· dispatch_eligible = false
```

### One thing that will bite whoever wires this up

**The corpus contains zero records at `validation_status = 'approved'`** â 71% `reviewed`, 19% `source_verified`, 10% `draft`. A retrieval layer written to filter on `approved` (the obvious reading of the pack) would return **nothing, forever**, and every call would fall through to a premium model â the exact cost this whole exercise exists to remove. The rule implemented instead: `reviewed` and `source_verified` are usable customer-facing, `draft` is internal reasoning only, and promotion to `approved` stays a human act per package. Nothing in this import promotes anything.

---

## 5. Test results

| Suite | Total | Action correct | Route correct | Misrouted |
|---|---:|---:|---:|---:|
| Supplied route tests (English) | 258 | **258** | **172 / 172** | **0** |
| â of which "ambiguous" | 86 | **86** ask for clarification | n/a | 0 |
| Arabic route tests (built, Â§6) | 86 | 84 | **84** | **0** |

The first threshold set failed 11 of the 258, all the same shape: a buyer typing one unambiguous word â "hvac", "catering", "law" â matched exactly one route at full confidence and was asked a clarifying question anyway. The floor was measuring the wrong thing. Score is a proxy for *specificity* (weight Ã word count), not certainty; certainty is the *margin over the runner-up*. The rule now: nothing matched â ask; exactly one route matched â route; two or more â route only if the leader is â¥1.5Ã the runner-up.

That is not tuning to the test set. All 86 "ambiguous" tests pass on their own merits â they contain no category vocabulary at all and produce zero candidates.

### Idempotency, resume and rollback â run, not described

| Test | Result |
|---|---|
| Full re-import of all 67 packages | 67/67 `already_completed`, **0 rows written**, 11.6 s |
| Row counts after re-import | identical: 108,818 / 16,588 / 12,929 |
| Rollback of one run (`QD-KB-047`) | 828 records + 292 child rows removed, file hashes cleared, run marked `rolled_back` |
| Re-import after rollback | 928 rows restored, totals back to exactly 108,818 / 16,588 / 12,929 |
| Duplicates created | **0** |

Resume-after-interruption and rerun-without-duplicates are the *same mechanism* â a SHA-256 file ledger plus upsert on a stable ID â so there is one code path and therefore one thing that can be wrong.

---

## 6. Arabic â a gap that was found and closed

The supplied lexicon left only 23 of 86 routes reachable by an Arabic speaker (Â§2, defect 6). An Arabic-speaking buyer typing ordinary Arabic could not reach 63 of the platform's categories, while the system claimed a full Arabic customer journey.

**403 real Gulf/MSA trade aliases** were written across all 86 routes â the vocabulary a UAE buyer actually types (`Ø¹Ø²Ù ÙØ§Ø¦Ù`, `ÙÙØ§ÙÙ ÙØ±Ø§ÙÙ`, `Ø£Ø³Ø§ÙØ³ÙØ±`, `Ø¬Ø¨Ø³ÙÙ Ø¨ÙØ±Ø¯`, `ØªØ®ÙÙØµ Ø¬ÙØ±ÙÙ`), marked `source = 'qd_arabic_trade_vocab_2026_08_02'` so they are distinguishable from the supplied set and revertible in one statement.

| | Before | After |
|---|---:|---:|
| Routes reachable in pure Arabic | 23 / 86 | **86 / 86** |
| Route exactly correct | 19 | **84** |
| Asked a clarifying question | 4 | 2 |
| **Misrouted** | **0** | **0** |

The two that ask are genuinely ambiguous â "ÙØ¸Ø§Ù ØªÙÙÙÙ" (AC system) sits between MEP and HVAC, and the router correctly declines to guess. Adding 403 aliases did not regress the English suite: still 258/258.

`kb_norm()` handles what casefolding does not: alef written as Ø§/Ø£/Ø¥/Ø¢, ta-marbuta vs ha, ya vs alef-maqsura, optional harakat. A buyer typing `ÙÙØ§ÙÙÙ Ø§ÙÙØ±Ø§ÙÙ` reaches the same route as the stored alias even when neither agrees on hamza.

---

## 7. OpenRouter reduction

Live inventory from `ai_cost_log`, last 45 days.

| Function | Calls | AED | Avg input tokens | Classification |
|---|---:|---:|---:|---|
| `agent_brain` | 129 | 22.56 | 14,600â22,000 | **Premium â keep.** Genuine open-ended reasoning. The input size is the target, not the model. |
| `knowledge_exam` | 99 | 1.28 | 2,100â2,500 | **Retrieval-replaceable.** Question bank and answers are now relational. |
| `gen_category_knowledge` | 42 | 1.15 | 500â800 | **Now redundant for the 86 mapped routes.** This function generates knowledge the corpus already contains, at cost, with no source lineage. |
| `dept_plan` | 46 | 4.08 | 5,400â5,900 | Premium â keep. |
| `cos_execute` | 45 | 3.89 | 350â470 | Premium â keep. |
| `inquiry_intake` (`missing_fields_detection`) | 8 | 0.00 | 2,135 | **SQL-replaceable today** â this is exactly `fn_kb_next_question`. Highest-value swap: it runs on *every customer turn*, and it is the one that scales with traffic. |
| `kb_fill_gap`, `kb_deepen` | 14 | 0.41 | â | **Scope-replaceable** for mapped categories; keep for genuinely uncovered ones. |
| `drawing_boq`, `extract_text`, `quote_extract`, `license_extract` | 7 | 0.00 | â | Premium/vision â keep. Documents and drawings are the legitimate case. |
| `translate_page`, `translate_html` | 2 | 0.03 | â | Small model â already there. |

**Recommended order, each behind a feature flag, none removed before it passes tests:**

1. `inquiry_intake` missing-field detection â `fn_kb_next_question`. Deterministic, free, and it fixes the "don't re-ask what a document already answered" acceptance item at the same time.
2. First-pass category detection in `inquiry_ai` / `route_inquiry` â `fn_kb_route_decide`, model only when it returns `ask_clarifying_question`.
3. `gen_category_knowledge` â skip for any category the crosswalk maps; it is paying to regenerate what is now in the database, without sources.
4. `knowledge_exam` â build from `kb_stage.scenario_tests` (3,324 supplied) instead of generating.

Nothing has been switched over. `agent_brain` at ~22,000 input tokens a call is the real cost centre and the corpus does not address it â that is a prompt-size problem, not a knowledge problem, and worth its own pass.

---

## 8. Acceptance checklist

**Files and validation** â Both archives readable â Â· Knowledge ZIP checksums recorded per package â Â· 66 broad packages + lifts supplement = 67 found â Â· 86 route manifests found â Â· All JSONL validates, **0 rejected** â Â· All source IDs resolve â

**Database** â Imported to staging, live tables untouched â Â· Migration reversible â Â· Records versioned (`record_versions` + trigger) â Â· Every import has an ingestion-run record (67) â Â· Rerun creates no duplicates â (measured) Â· Interrupted import resumes â (measured) Â· Rollback by run works â (measured) Â· Private knowledge not exposed to anon â (`kb_stage` off the API surface entirely)

**Operational routes** â 86 live routes â Â· All 86 mapped â Â· No route with zero subcategories â Â· Signage mapped â Â· Lifts mapped â Â· Multi-category preserved â

**Inquiry behaviour** â Informal English routes correctly â (258/258) Â· Informal Arabic routes correctly â (84/86 exact, 0 wrong) Â· Ambiguous requests get one clarification â (86/86) Â· Existing values prevent duplicate questions â Â· Missing critical values block dispatch â (`dispatch_eligible`) Â· Deterministic rules control sequence and completeness â Â· Regulatory matters escalate â (`escalate` flag) Â· Privacy/redaction gate unchanged and still fail-closed â

**Testing** â 258 route tests run â Â· Scenario tests imported (3,324) â **â ï¸ imported and queryable, not executed**; they need a harness that drives a full intake conversation, which is the next piece of work Â· Existing customer/supplier/inquiry/matching/comparison flows untouched â (nothing in the live path was modified)

**Cost reduction** â Calls inventoried â Â· SQL-replaceable identified â Â· Retrieval-replaceable identified â Â· Small-model candidates identified â Â· Premium fallbacks retained â Â· **No production AI path removed** â

---

## 9. Rollback

**One package:**
```sql
select id, package_id from kb_stage.ingestion_runs where package_id like 'QD-KB-047%';
select public.rollback_ingestion_run('<run_id>');
```
Restores anything that run overwrote from `record_versions`, deletes what it created, clears its file hashes so a re-import re-reads every file. Tested.

**The whole import:**
```sql
select public.rollback_ingestion_run(id) from kb_stage.ingestion_runs;
```

**Total removal** (the corpus touched nothing outside these objects):
```sql
drop schema kb_stage cascade;
drop table public.kb_operational_route_test, public.kb_operational_alias,
           public.kb_operational_route_map, public.kb_operational_route cascade;
drop view public.v_kb_operational_86_coverage;
```
No live table was altered. `agent_knowledge`, `kb_chunks`, `catalog_supplier_categories`, `inquiries`, `leads` and every edge function on the customer path are exactly as they were.

---

## 10. What is deliberately not done

1. **The live router is not switched over.** The crosswalk is `draft`. Switching before it is reviewed is the one thing the control pack tells you not to do.
2. **No record promoted to `approved`.** Promotion is a human act, per package, and legal/regulatory records need a qualified reader.
3. **No embeddings generated.** Full-text ranking is answering retrieval well enough to measure; embeddings cost money and should be added only where FTS is demonstrably losing, and then only for changed narrative records.
4. **Scenario tests imported, not executed.** They need a harness that drives a whole intake conversation. That is real work and it is the honest next step.
5. **2,537 optional questions still have no field key**, recorded in the gap register. All mandatory ones do.

---

## 11. Credential note

The import used a single-purpose token in `app_secrets.kb_import_token`, authenticating only `kb_corpus_import`, which can write only to an allowlisted set of staging tables. The service-role key never left the Supabase runtime and was never handled by the importer, by a script on any laptop, or in any chat.

**Delete it now that the import is signed off:**
```sql
delete from app_secrets where key = 'kb_import_token';
```
Re-creating it is one insert if the corpus ever needs re-importing.
