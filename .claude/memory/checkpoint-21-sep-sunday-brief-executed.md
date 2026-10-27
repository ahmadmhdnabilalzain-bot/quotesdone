---
name: checkpoint-21-sep-sunday-brief-executed
description: "CHECKPOINT 21 Sep 2026 ~14:10 Dubai: Sunday brief executed on Monday; 9 PRs merged, 5 open, 7 agents stopped mid-work by the session limit"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-21T14:17:12.358Z
---

READ FIRST on resume. Supersedes [[sunday-plan-deep-portal-audit]] for status; that file still holds the founder's wording.

**Founder instructions recorded today:** 529 (resume), 530 (new week), 531 (IT failures 18-21 Sep).

## Merged and live (all applied + deployed + mirror regenerated)
- **#760** incremental backups by SIZE (64 MB threshold), deletes recorded, restore replays base + increments. resilience_ping deployed.
- **#761** rating works (stars alone; comment optional, 10+ chars if given; readable 400, never 500), Arabic dates read forwards (one `src/lib/Ltr.tsx`), supplier ranking reads real quotes. customer_api deployed. Browser-verified: star press 200.
- **#762** apply-discipline §4 + organised-skill say a probe returns a verdict ROW, never `raise notice`.
- **#763** `docs/SECTORS_WE_COVER.md` (40 trades sold, all EN+AR; F&B not sold, nor professional services) + `docs/KNOWLEDGE_DOCTRINE.md` (5 admission tests, 4 bodies, rule-table schema §7, purge rule §6, purge preview §8).
- **#764** every document offers View / Download / Replace / Remove; expiry read by code from the PDF, supplier confirms; AI path flag `document_expiry_ai` OFF. supplier_portal deployed.
- **#765** inquiry sheet PDF on our template (EN+AR) + supplier sees its own quotation; cache table `supplier_document_cache`. supplier_api deployed.
- **#766** removed 3D environment, network map, negotiations (both portals, `negotiation_assistant` DELETED from the project — had to delete twice, first DELETE did not stick), IBAN/bank (0 values existed; 3 columns dropped). Bundle −274 KB.
- **#767** IT failures 18-21 Sep: 25 emails = 11 causes (`docs/it/IT_FAILURES_18_21_SEP_2026.md`). Five SQL fixes applied (detector bounded 11 s→4 s, liveness reads the scheduler, CEO deciders, orphan backups abandoned, operator-session statements excluded). send_whatsapp + resilience_ping deployed.
- Main's "deploy edge functions" run failed at 10:12Z on the stale negotiation_assistant drift; rerun started (run 35587504395) — CHECK IT.

## Open PRs
- **#769 knowledge purge** — routines + ledger APPLIED, pushed, CI not yet read. NOTHING DELETED YET. Next: merge once green, then `node scripts/kb/purge_kb_bulk.mjs` (plan/census) — the first census attempt died on HTTP 524 (management API timeout on the 2 M-row `standard` kind); it cleaned its ledger row, so just re-run; then `--run` (≈49 batches), then `scripts/checks/the_knowledge_library_holds_no_foreign_bulk.mjs`. Reviewer: APPLY. Expected delete ≈2.44 M of 2.62 M; 45,169 UNSURE rows go to the founder; clause 2 ledger = `sales_decision_log.cited` (3 cited chunks saved). Restorable copy: 18 Sep full export, 4,177 pages verified.
- **#770** four gap trades authored as seed JSON (electrical, steel, fire_fighting, hvac) + `rule_seeds_carry_the_doctrine_columns` check. No SQL. Inert until the rule tables land. Not reviewed yet.
- **#771** customer portal UI/AR/copy fixes (name field, theme, 404, deep links, rating comment box, hours Sun–Thu, sign-up refuses reserved domains). Vercel-only. Not reviewed yet. Finding 30 (two roles bounce) NOT reproduced in code — needs a browser re-check.
- **#768** `it-engineer/dependency-patch-2026-09-21` — opened by the IT seat itself, not by me; review before merging.

## Agents STOPPED by the session limit — work BACKED UP 21 Sep
Each worktree below was committed as-is (WIP, do not merge as is) and pushed to GitHub branch `wip/<worktree-name>`; 0 files left unsaved. Exception: `agent-a1caaaa8bd871cbab` (chat) stopped MID-MERGE with 2 conflict-marker files, so it was NOT committed; its full diff is `C:\Users\Opera\quotesdone-wip-backups\chat_agent_midmerge_21sep.patch` (includes main's incoming changes) and its base commit is pushed as `wip/agent-a1caaaa8bd871cbab-base`. Resume each by checking out its wip branch, merging origin/main, and finishing.
- `.claude/worktrees/agent-acbc332a79f790b53` — customer intake/docs fixer. Done in tree, not committed: create_inquiry 500 fix (#2), quote_pdf lang (#4), intake reads answers + utility by emirate (#8), unredacted drawing held (#9), quote PDF layout/specs/commas/footer quotesdone.ae (#12), vault lists quote PDF + warranty (#11, SQL `the_customer_vault_lists_the_quote_pdf_and_reads_the_quotes_warranty.sql`), post-reveal names/pipeline/overview (#17/#19). Invoice-PAID (#5) helper died mid-work. Deploys needed: customer_api, customer_portal, project_api, inquiry_intake, drawing_boq, pdf_native, quote_extract, customer_documents.
- `agent-a24eb4aa15239bd89` — quotation review reader (supplier findings 1,2,4,12-15,28,29,33,35). The founder's "most important part".
- `agent-a1caaaa8bd871cbab` — chat answers + messages compose (customer 6,7,13,21); was resolving a MANIFEST conflict.
- `agent-a1beff2582ef98f64` — supplier services/docs/insights/bell (supplier 5,6,8-11,16-24,31-49).
- `agent-a0f7c06fe672e1acf` — blank redacted drawing, one job number across portals, emirate matching, bilingual inquiry content.
- `agent-af9f1632335f7f1bc` — rule tables + quote_compare wiring + GYPSUM seed + before/after proof. Was adding MANIFEST/PENDING lines.

## The audits (full lists — the source for the fixers)
Scratchpad copies: `audit_customer_21sep.md` (31 findings; BLOCKERS: pre-reveal name leak via negotiations — removed by #766; create_inquiry 500) and `audit_supplier_21sep.md` (50 findings; BLOCKERS: review cannot read a text PDF, typed prices never match, redacted drawing blank, generated quotation contradicts approval). Screenshots: `Downloads\QuotesDone audit 21 Sep\{customer,supplier,public}`. The founder's claim "supplier cannot see the generated quotation" was REFUTED — it can; the content is wrong.

## Rules re-learned today
- A merge can silently DROP a PR's MANIFEST line (happened on #769): after every merge of main, grep the PR's file in MANIFEST.txt before pushing.
- Deleting an edge function via the management API can return 200 and leave it ACTIVE; read it back (GET must 404).
- A file may not sit in both MANIFEST and PENDING — move the line at apply time.
- `deno check` on this machine fails on a missing npm dep (`@supabase/realtime-js`); use `--node-modules-dir=auto`.
- Still open for the founder: catalogue keep-or-cut; backup retention (52 Friday full copies = 592 GB); 45,169 UNSURE knowledge rows; demo cull (12 records + 3 rehearsal windows + the audit's uploaded demo files).

## UPDATE 21 Sep ~21:10 Dubai — the 48-hour push to the supplier campaign
Founder: supplier REGISTRATION email campaign in ~2 days (instr 584); "not stopping for the next two days"; agent limit lifted (581, now on Opus); knowledge authoring stays LAST (578) unless he changes it; demo records kept, never ask (571); website design accepted (572); every fix needs a recurrence check (573, now in apply-discipline); LLM allowed where genuinely needed — say so honestly (574); agents must understand/reason, not word-match (575); photos understood (576); model answers only from our base, never the internet (577); drawing reading is priority (579/580).
Merged today after the first checkpoint: #767 #769 #770 #771 #772 #773 (quotation review) #774 #775 (template invoices, PAID only when settled) #776 (deps + org_task consumer + Vercel author fix) #777 (IBAN/negotiations traces) #779 (14 recurrence guards, backup-recheck alias fix). Closed: #768 (superseded), #778 (superseded by #779).
Knowledge purge: rule = UAE-related only (instr 535/570: US codes/laws deleted unless UAE-cited; EU pharma/RFCs deleted; Eurocodes/BS EN/IEC/ISO kept; DIFC/ADGM/ADNOC count as UAE). Census gate (purge_census.mjs) refuses unless per-kind counts equal the table; a clean census was running at ~21:00 Dubai; then `node scripts/kb/purge_kb_bulk.mjs --run` from a main checkout (worktree pr779 detached on main). NEVER run two censuses; a stopped process can commit one more slice — check pg_stat_activity then clear `batch_no is null` rows.
Drawing baseline (scratchpad drawing_baseline/result.md): 0/49 found on two Weld County public bid sets (Downloads\QuotesDone audit 21 Sep\drawing_test — copyrighted, local only; the CUI-marked ANG set was binned).
Agents running at 21:10: customer requests (wip acbc…), chat (patch in C:\Users\Opera\quotesdone-wip-backups), supplier panels (wip a1beff…), IT 40 findings (a560891…, helpers done: region pinning, 401→503 auth helper, detector sets, doc_backups index), catalogue (+meaning layer gte-small, OCR photos, flag-off vision), drawing reading (target 49/49), job number + emirate + AR inquiry (wip a0f7c…), account facts (WhatsApp name, provider caps, .ae renewal), nightly journey steps + customer 29/30/31, tracker page (scratchpad/tracker), supplier registration walk, campaign pipeline, surge limits, seat task audit + marketing scope (→ Downloads\QuotesDone agents — tasks and gaps.md).
Go/no-go for the campaign promised by 22 Sep evening with evidence.
