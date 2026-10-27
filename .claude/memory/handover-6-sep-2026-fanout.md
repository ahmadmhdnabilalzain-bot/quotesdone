---
name: handover-6-sep-2026-fanout
description: "Hand-over written at 11:10 UTC 6 Sep 2026 near the session limit — PR #524 state, the six agent branches in flight (founder decisions), and the exact integration steps to resume"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-06T11:04:35.193Z
---

# Hand-over, 6 Sep 2026 (written before the 5-hour session limit)

## PR #524 (branch integration-2026-09-06d)
Head 03634af pushed 11:08 UTC; CI was watched by scratchpad/watch_ci.sh (log watch_03634af.log). Two fixes landed
on it after the summary: phase_d_dispatch_reaches_executed now asserts DELTAS (a real customer registered
07:38 UTC and the absolute-zero assertion went red), and kb_embed's partial index
(scripts/sql/the_embedding_picker_reads_a_partial_index.sql, already BUILT on production, valid, 17 MB) with the
error ledger at kb_embed 31. On green: `gh pr merge 524 --merge`, then watch main's workflows, Vercel, and run
the post-merge sweep (canonical_routine_manifest, export mirror, verify_deploy_parity --all, graphify update).

## Six agents launched ~10:50 UTC, each in .claude/worktrees/agent-<id>, branch worktree-agent-<id>, based on main d54ff2c
(NOT on #524 — merge #524 first, then merge each branch into a new integration-2026-09-06e; resolve
scripts/sql/MANIFEST.txt by UNION (scratchpad/resolve_union.mjs), mirrors/graphify/CSV `--theirs`, then regenerate
the mirror after the LAST apply and run the gate battery):
- a0de3369a1e2859e5 — founder decisions → policy sync (company_registration CT/auditor, pricing_config no date, no
  discounts/caps, category open at 10, ads cap AED 30 + CPL target removed, finance budget stance, OpenRouter policy,
  company_policy_decision table + qd-company:decisions, hard rules, plan §5 rows closed).
- a3fb32a8bc38925d2 — refund ladder (5 working days, chase at 3 by the existing follow-up owner, founder final call on
  day 5 via an allowed founder-mail kind, 3% + 9% p.a. interest, AED 250 admin fee kept, 7–14 working days banks),
  ALL public pages legal text, legal_documents registry with versions + sha256, qd-company:refunds.
- aa7d4efff1f394234 — brand kit (Dropbox zip) ingested into brand tables + qd-company:brand, applied to report_pdf /
  email renderer / social defaults, docs/brand/QUOTESDONE_BRAND_GUIDE.md + PDF in the reports bucket.
- a17fe6a128a844f5e — WhatsApp founder-alert template via Twilio Content API (create + submit for approval, wire the
  SID, sender skips-with-reason while pending).
- a58d2552f2a4d8217 — supplier acquisition loop owned by the EXISTING BD employee (invite from leads, follow-ups, lead
  intake tracking, KPI ≥300 registrations/month) behind app_secrets supplier_outreach_golive=false; weekly sanctions
  screening (UN consolidated XML + UAE list) owned by the existing compliance employee.
- ac7ccd1fd2de02fa7 — real customer e0dee407 (registered 07:38Z, no terms acceptance, W04-S01 REFUSED BR-025/026,
  no welcome email exists in the product): edge-log read of his session, terms acceptance with version+hash,
  W04 re-dispatch, deterministic customer_welcome executor (renders the real customer's HTML to
  scratchpad/welcome_e0dee407.html for MY review — nothing queued to him), anon_exposure_drift security events.
- a0798e667842d5f48 — OS button-by-button walk in his signed-in Chrome; ledger scratchpad/os_walk_2026-09-06_post523.md
  and docs/os_audit/.
Three renderer restatements collide on fn_company_self_knowledge_sync (decisions, refunds, brand): merge by taking
the union of records into ONE new file, apply it last, regenerate the mirror.

## Founder decisions of 6 Sep 2026 (final — never re-ask; the agents implement them)
Corporate tax not registered until threshold (he updates, maybe a year); no auditor; Meta daily cap AED 30, the AED 150
CPL target was never his; Twilio WhatsApp token is with us, fix the template ourselves; brand kit is the reference
(upgrade allowed except the logo); suppliers: invite campaign from existing leads, ≥300 registrations/month, nothing
runs until he says the app is perfect; OpenRouter recharged by him, receipts to the expenses mailbox, held until he
activates; OS is logged in; refund admin fee AED 250 stays; 3% refunded with 9% p.a. interest (UAE maximum); refund
ladder 5 working days / chase at 3 / his final call on day 5 / banks 7–14 working days; weekly sanctions check by an
existing agent; no discounts, no reveal caps; category open at 10 verified suppliers; finance budget unlimited until
profitable; supplier registration free for the first 1,000 then AED 1,000/yr with no date; "agents" for these tasks
mean EXISTING employees by department, not new ones.

## Still mine after the agents report
Review welcome_e0dee407.html and decide the send; the Meta cron needs its own token in the vault at go-live (the
connector he gave works only in my session — state it once, never ask); update
[[state-after-3-sep-2026-session]]; republish the knowledge-plan artifact if §5 changed; end-of-session sweep.

## If the session limit killed the agents (added 11:35 UTC at 91%)
Subagents die with the session. Their worktrees survive at .claude/worktrees/agent-<id> (branch worktree-agent-<id>);
at 11:35 UTC none had committed yet: the brand agent had supabase/functions/_shared/brand.ts, report_pdf and
send_outbox edits plus brandkit/ unpacked; the supplier agent had downloaded un_consolidated.xml. Their full transcripts
are C:\Users\Opera\AppData\Local\Temp\claude\C--Users-Opera-quotesdone\cd432ea4-4602-4dcf-a262-875622bbb1d9\tasks\<id>.output
(JSONL; read the last assistant messages to see how far each got). Anything they applied to PRODUCTION is already live
(functions, tables, crons) even if uncommitted: after a reset, run `node scripts/checks/export_from_either_source_is_identical.mjs`
and `node scripts/canonical_routine_manifest.mjs` to see what production holds that no file records, then finish each
agent's item by relaunching it with the SAME prompt (the prompts are in this session's transcript, search for
"YOUR JOB") plus "your worktree already holds …; production already has …; continue from there".
PR #524 head 1bdbf93: the checks run passed; the production-gate run was still being watched.

## After the reset (12:1x UTC)
PR #524 MERGED into main as cf34c63 (both runs green). The six agents died at the limit with partial files, copied to
scratchpad/agent_partials/<id>/ (SQL files + modified.patch). Relaunched as ONE Workflow run wf_9d4fde26-79c
(script: C:\Users\Opera\.claude\projects\C--Users-Opera-quotesdone\cd432ea4-4602-4dcf-a262-875622bbb1d9\workflows\scripts\founder-decisions-6-sep-wf_9d4fde26-79c.js):
seven build agents in worktrees from main → adversarial verifier on production per item → repair on <branch>-fix → re-verify.
Resume after a kill: Workflow({scriptPath, resumeFromRunId: "wf_9d4fde26-79c"}); read the journal.jsonl in
subagents\workflows\wf_9d4fde26-79c before trusting cached results. Branches to integrate afterwards: each result's
build.branch (+ repair.branch when present) → merge all into integration-2026-09-06e from main, MANIFEST.txt union,
one fn_company_self_knowledge_sync restatement carrying decisions+refunds+brand+messaging+suppliers records applied last,
mirror regenerated, gate battery, PR, merge, Vercel, sweep.

## 14:15 UTC
Branch embedding-crons-stop-stampeding (d26e742: partial-index follow-ups — boost job 242 now one post of 3 chunks every
6 s via pg_cron interval schedule, jobs 271/315 one post a minute, error ledger kb_embed 40) is merged into
integration-2026-09-06e (created from main cf34c63). Workflow wf_9d4fde26-79c still running; its branches merge here next.

## 19:05 UTC
Workflow run 1 finished 11/17 agents (6 died at the limit) and was RESUMED with an edited script (task wzn3n40ry): repairs
skip renderer/ledger-drift gaps and are forbidden from restating the three renderers; the suppliers item rebuilds AND
recovers the 11 live-only routines (fn_supplier_*, fn_sanctions_*, fn_screening_*, trg_screening_entry_normalise) plus
the live-only edge function sanctions_screen into files and config.toml.
integration-2026-09-06e (pushed, head 87e875d) = main + embedding branch + the six finished branches (policy -1,
refund-ladder-2026-09-06, brand -3, whatsapp -4, customer -6, oswalk -7) + scripts/sql/the_company_renderers_carry_every_record_of_6_sep.sql
(the union of the three renderers read from production, LAST in MANIFEST) + the_welcome_states_the_ladder_from_pricing_config.sql.
The real customer's welcome (notification 20610) was queued through fn_customer_welcome at 19:00Z after the text was corrected.
Remaining before the PR: merge the suppliers branch and any *-fix branches, add sanctions_screen to config.toml if the
suppliers branch did not, deploy kyc + stripe_confirm (STALE), regenerate the mirror + graphify, run the gate battery
(canonical 0, source-of-truth pass, parity 203/203, boards, ledger, scenario door), open the PR, merge, watch main, Vercel,
republish the knowledge-plan artifact from docs/KNOWLEDGE_PLAN_2026-09-06.md.

## 21:1x UTC — PR #525 open
integration-2026-09-06e head eaa6cf1 = everything (seven packets + fixes + integration closures). PR #525 open; CI being
watched. Gates on this tree vs production: canonical 0/0, source-of-truth all 0, parity 204/204, boards 7/7 (ratchet 540),
scenario door 6/6, connectivity pass, error ledger 3/3 (kb_embed 51, resilience_watch 9), pricing_consistency 8/8, mirror identical.
After merge: watch main's three workflows, Vercel READY, re-walk the OS pages the walk fixed (palette, Documents 'Open file',
learnings PDF tab), and at 21:49/22:49 UTC confirm no kb_embed select timeout recurs (the priority pick index was the cause).
Artifact republished with §5 closed. The welcome to the real customer was sent 19:02Z. WhatsApp supplier_quote_accepted v2
(five working days) submitted to Meta 20:48Z, status received — the sender holds that key until approved.

## 21:5x UTC — PR #525 head 785f58f
Full local suite exposed and fixed: head budget split after the mandatory pieces (fn_agent_context, file LAST in MANIFEST),
label-only legal edits no longer re-version (supplier-agreement v8 everywhere; pins trigger on every registry write),
zero-cost evidence counts inference rows only and compares apply-written tables; four stale checks corrected (invite-ramp
read vs write, V3 coverage floor, packaged departments -> product_eng/supply, headcount 54, canonical qa_manager).
Ledger: email_cron 1, kb_embed 52 (both the guards refusing the local npm test at 21:08Z). NEVER run npm test or any
production-touching check while a CI production-gate run is in flight (the scenario door collides: "a scenario is OPEN").
CI on 785f58f being watched (task bkb5ohait). Merge on green, then main workflows, Vercel, OS re-walk, 22:49Z probe.

## 22:1x UTC — PR #525 head bcbf03e
CI's scenario-door failure was the 6-second boost's traces landing inside the committed scenario's count watermark:
phase_d_committed_scenario_watch.count_filter (phase_c_trace excludes system_execution), the close door's v_ao follows
the filter, and every positive-control probe runs at REPEATABLE READ. Positive controls 17/0 locally; scenario guards 6/6.
21:49Z probe: no kb_embed select timeout recurred (the priority-pick index was the cause); resilience_watch 7 ok / 0 error.
CI on bcbf03e being watched (task bllpjt1mp). Remaining: merge on green → main workflows → Vercel → OS re-walk.

## 7 Sep ~00:xx UTC — the certification exams (founder order)
Founder: "create a list of the top certificates for every position we have in the company and then test all agents. if
they dont pass them all, then their knowledge is simply not enough." Brief with the canonical certification names, real
pass marks and the position→certification map: scratchpad/CERT_EXAM_BRIEF.md. Tables live on production
(scripts/sql/every_position_has_its_certifications_and_an_exam_bank.sql): role_certification, certification_exam_question,
certification_exam_result. 12 agents launched: 1 engineer (role map for all 54 employees + deterministic sitter
fn_certification_exam_sit / _sit_all / _summary, no paid model, abstain counts as wrong + check
every_position_sits_its_certifications.test.mjs) and 11 bank authors (52 banks x 40 questions, guarded by
`where not exists ... certification = '<name>'` so a shared bank is authored once). Each author commits its own
scripts/sql/certifications_<batch>.sql + the MANIFEST line (BEFORE the last two lines). After they report: merge every
branch into a new integration branch, run the full sit, publish the pass/fail table per employee, and the failed
syllabus areas become the ingestion plan.
PR #525 merged; main's three workflows green. Still open from before: Vercel deploy check and the OS re-walk in his browser.
