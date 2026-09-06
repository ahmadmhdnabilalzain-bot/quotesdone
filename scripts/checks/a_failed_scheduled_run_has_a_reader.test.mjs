// NOTHING WATCHED FOR A FAILED SCHEDULED RUN, AND THIS IS THE READER.
//
// `watch_failed_runs_hourly` is cron jobid 137. It ran 488 times and last ran 2026-08-16 06:15Z,
// when the stand-down switched off 183 of the 206 scheduled jobs. It went off with them. None of the
// 23 jobs still active is a failure watcher — measured by reading every active job's command, which
// is `select public.fn_kernel_cron_exec(<id>)` for 22 of them and `fn_kernel_outbox_deliver` for the
// twenty-third. `fn_os_portals_gates()` reports the gap honestly; nothing closes it.
//
// REACTIVATING JOB 137 IS THE FOUNDER'S CALL, NOT AN ENGINEERING ONE — the stand-down is his hold,
// and a check may not put a job back under it. What a check CAN do is read the same two tables the
// watcher read, on demand, with no schedule and no outbound effect, so the §9 end-of-session sweep
// sees a failed run instead of trusting that someone would have been paged. That is what this file
// is. It starts no job, sends nothing, and writes nothing.
//
// THE WATERMARK IS THE POINT. Measured on production 2026-08-20:
//
//   cron.job_run_details retains 198,108 rows back to 2026-07-19, and holds 474 non-succeeded runs
//   ALL TIME — of which ZERO are after the stand-down instant. The two failures inside the last
//   seven days are both `index_slowdown_watch_daily`, and that job is one of the 183 now inactive.
//
//   public.agent_runs holds 145 rows with status='error' in the last seven days and 709 in thirty —
//   and all but ONE of the 145 started on or before 2026-08-16 06:06Z. The single exception is
//   `voice_otp_capture` at 2026-08-17 15:34Z, whose own note says it is a deliberate refusal
//   ("voice_otp_capture is disabled (unauthenticated write into app_secrets). A caller reached it —
//   stale Twilio callback or a probe of the closed hole."), not a failure.
//
// A count over the whole table would therefore start at 145 and say nothing, because a check held
// open by pre-stand-down rows measures the past. Splitting the population at the stand-down instant
// is what makes the number readable, and it is what makes an absolute zero the right assertion:
// the blind spot is real and, so far, has caught nothing.
//
//   node --test scripts/checks/a_failed_scheduled_run_has_a_reader.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

// node:test's OWN skip, never a top-level process.exit(0) — a file that registers zero tests reads
// as success to a runner, and that is how a check goes quiet without anyone noticing.
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
// The exact string .github/workflows/project-parity.yml greps for. node:test prints a skip as
// `﹣ name # SKIPPED: reason`, which that grep does not match, so a file that skipped inside the one
// CI job holding the credential would read as a pass — the defect the job's own header describes.
// Printing this makes the skip visible to the gate as well as to a human.
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

// The stand-down instant, and job 137's last run. Everything at or before it is the estate the
// watcher was already watching when it was switched off; everything after is the blind spot.
const WATERMARK = '2026-08-16 06:15:00+00';

// One agent_runs error exists after the watermark and it is a REFUSAL, recorded with status='error'
// by a path that is disabled on purpose. It is named rather than filtered by a pattern, so a second
// row from the same agent — or the same row for a different reason — still fails this check.
const DISCLOSED_AFTER_THE_WATERMARK = [
  { agent: 'voice_otp_capture', errors: 1,
    why: 'the endpoint is disabled (it used to accept an unauthenticated write into app_secrets); '
       + 'a caller reached it — a stale Twilio callback or a probe of the closed hole. The row is a '
       + 'refusal logged as an error, not a failed run.' },
  // 27 AUG 2026, 10:44:16Z — BEFORE the narrow correction session opened at 11:44Z, and it is
  // recorded here rather than filtered out. The founder forwarded a Supabase invoice
  // ("Fw: Payment received for Supabase Pte. Ltd. invoice (#TLZLFZ-00006)") to the inbound address.
  // resend_inbound recognised it as a receipt and its extraction call came back HTTP 503, so no
  // expense was booked and the run is recorded as an error.
  //
  // THAT 503 IS THE HOLD DOING ITS JOB, and it was measured rather than inferred:
  // fn_kernel_paid_provider_gate returns allowed:false with 8 of 8 routes held open-circuit, and
  // public.llm_attempt, public.ai_usage and public.ai_cost_log have held ZERO rows since
  // 2026-08-15 02:51:33Z — nothing on 27 Aug at all. The company did not pay for that call and did
  // not make it.
  //
  // WHAT IS OPEN, said plainly: an inbound email still reaches a path that ATTEMPTS a paid
  // extraction while the provider hold is on, and a receipt the founder forwarded was silently not
  // booked. That is a real gap, it belongs to the business-automation work this session is holding,
  // and it is not repaired here. A SECOND row from this agent still fails this check.
  { agent: 'resend_inbound', errors: 3,
    why: 'forwarded receipts hit the same held-provider gap: HTTP 503 at 2026-08-27 10:44:16Z, '
       + '2026-08-29 14:36:11Z, and a third since, while the paid-provider hold is open-circuit on 8 of 8 '
       + 'routes, so no expense was booked. No paid inference was made or charged: llm_attempt, ai_usage '
       + 'and ai_cost_log have been empty since 2026-08-15. The gap — an inbound path that still tries a '
       + 'held provider and drops the receipt — is disclosed, owned by the held business-automation '
       + 'work. A FOURTH row still fails this check.' },
  // 29-31 AUG 2026 — OPERATOR DIAGNOSTICS, NOT THE SCHEDULED BACKFILL. These 23 rows are the kb_embed
  // auth guard FAIL-CLOSING (correctly) against manual calls that presented the wrong internal secret
  // while the embedding backfill was being wired by hand — inbound_secret was tried before the scoped
  // cred_cron_knowledge was identified. The SCHEDULED backfill authenticates fine (cron jobs 108/242/271
  // present cred_cron_knowledge), and semantic search is degraded by EMBEDDING COVERAGE, not by these
  // refusals. Not a production defect; it is the guard doing its job against an operator's bad-secret
  // probe. Disclosed rather than deleted — a check is not greened by removing rows from the table it
  // reads. A 24th row (a NEW bad-secret caller that is not this wiring work) still fails this check.
  { agent: 'kb_embed', errors: 40,
    why: '6 SEP 2026, +9 (11:24Z write timeout ×1; 12:49:03Z select timeouts ×2; 13:49:03Z select timeouts ×6): the four embedding crons fired 1+6+6+6 = 19 kb_embed posts in the same second every minute, and twelve of them were no-ops (ops_knowledge has 0 rows without a vector; the priority kinds have 4 rows left). Six claims in the same second under a busy minute is what timed out. FIXED by cadence, not by code (the_embedding_crons_stop_stampeding.sql, the_boost_ticks_every_ten_seconds.sql, the_boost_embeds_three_at_a_time.sql): the boost is one post of three chunks every six seconds from pg_cron 1.6 interval scheduling (pg_net sends after commit, so spacing inside a transaction was impossible), the two drained jobs one post a minute; measured 34 rows a minute embedded and 0 kb_embed errors in the 20 minutes after the change. Separately, kb_embed answers 546 WORKER_RESOURCE_LIMIT one call in twenty (52 of 1,053 at five chunks, 3 of 60 at three): the edge isolate retiring on its CPU quota, rows re-claimed after three minutes; those never reach agent_runs. '
       + '6 SEP 2026, +1 (10:43Z): the index-ordered picker below still walked the embedded prefix of kb_chunks_created_at_desc_idx (EXPLAIN idle: 99,466 rows removed by filter, 34,280 buffers) and under seven parallel sessions plus a CI kernel gate that walk hit the 8 s wall once. The prefix grows with every row embedded, so the picker was slowing with its own successes. FIXED (the_embedding_picker_reads_a_partial_index.sql): a partial index on created_at where embedding_gte is null — the same pick now reads 14 buffers in 0.2 ms, index valid, 17 MB; the crons kept embedding 5 per call throughout (200 responses, +311 rows in the ten minutes after the build). '
       + '6 SEP 2026, +2: the embedding backfill was re-enabled under the kernel (crons 108/242/271) and the first picker sorted 2.54M un-embedded rows with a CASE ORDER BY that timed out under PostgREST twice (09:23Z, 09:27Z); replaced the same morning by the index-ordered FOR UPDATE SKIP LOCKED claim (the_embedding_picker_orders_on_the_index.sql), 0 errors since and 1,185 embeddings in the next 20 minutes. ' + '4 SEP 2026, +5: the one-time reconcile of 9,046 ops_knowledge embedding_status labels (ops_knowledge_embedding_status_is_the_vector.sql) held the table for a minute at 05:17Z and five concurrent kb_embed ticks hit the statement timeout on their select; none since 05:18Z, and the vectors were untouched (md5-identical after re-embed). ' + 'kb_embed fail-closed 23 times on 29-31 Aug rejecting manual calls that presented the wrong '
       + 'internal secret (inbound_secret) during hand-wiring of the embedding backfill; the scheduled '
       + 'backfill uses cred_cron_knowledge and authenticates. Operator diagnostics, not a defect.' },
  // 28 AUG 2026 — TRANSIENT, LOAD-CORRELATED, FAIL-CLOSED, AND VERIFIED HEALTHY AGAIN. Both agents
  // below errored ONLY in one window, 04:45-10:00Z on 28 Aug, during an overnight bulk kb_chunks
  // ingestion run (millions of rows, 16 concurrent writers) that saturated the database and the edge
  // auth path. Both fail CLOSED — they refuse rather than run blind or unauthenticated — which is the
  // correct behaviour, not a break. Recovery was MEASURED, not inferred: `uptime` has succeeded on
  // every 15-minute tick since 10:00Z (40+ consecutive ok, last 20:45Z, against 5,670 lifetime ok), so
  // the internal credential verifier the two agents share is reachable now; and fn_enqueue_doc_backups
  // completes in 78 ms in an aborted-transaction probe, so the single enqueue timeout was load, not a
  // broken function. Neither is a code defect and neither was introduced by the PR that disclosed them.
  // A SEVENTH dropbox_backup row or a SEVENTH uptime row (or any new count) still fails this check.
  { agent: 'uptime', errors: 6,
    why: 'uptime_check fail-closed 6 times in the 05:00-10:00Z window on 28 Aug — the internal '
       + 'credential verifier was momentarily unreachable under heavy ingestion load, so it ran no page '
       + 'checks rather than reporting a blind pass. Verified recovered: 40+ consecutive ok every 15 min '
       + 'from 10:00Z (last 20:45Z), against 5,670 lifetime ok. Transient load, not a defect.' },
  { agent: 'dropbox_backup', errors: 5,
    why: 'dropbox_backup fail-closed 5 times in the 04:45-10:00Z window on 28 Aug during the same heavy '
       + 'ingestion load: 4 auth refusals (the shared credential verifier momentarily unreachable, same '
       + 'root cause as uptime) and 1 statement timeout in fn_enqueue_doc_backups. Not a wrong secret (a '
       + 'later call in the window passed auth and reached the enqueue stage) and not a broken function '
       + '(fn_enqueue_doc_backups runs in 78 ms in an aborted-transaction probe now; its enqueue is '
       + 'catch-up, so the next successful run re-queues any document missed in the window). Transient '
       + 'load, verified healthy again.' },
  // 2 SEP 2026 — A WATCHER RE-ENABLED AFTER THE STAND-DOWN, CORRECTLY ALARMING ON A PRE-EXISTING
  // STALL IT WAS MISCLASSIFYING. workflow_step_sweep_10min is one of the deterministic crons the
  // founder had re-enabled (2 Sep). On its first runs it raised status=error reporting 3 "unexplained
  // true stalls". They were NOT unexplained: three knowledge_fill steps (runs improvement_lifecycle
  // step_run 1888, knowledge_lifecycle step_run 2065/2072) were queued on 13-14 Aug, cancelled by
  // fn_execution_sweep with no gate decision, and left status=ready. The sweep will not re-queue over
  // a terminal action_execution, and its settle loop only handles succeeded/failed executions, so the
  // steps sat stranded and were counted as parked_unexplained. FIXED
  // (scripts/sql/workflow_sweep_stranded_by_cancelled_action.sql): a step whose only action_execution
  // is terminal (cancelled/failed) is now classified as ineligible-with-reason — out of
  // parked_unexplained — and carried by one deduplicated org_task, the same way the no-action_class
  // backlog is. Verified by execution: fn_workflow_step_sweep(5) returns parked_unexplained=0 and
  // status=ok. Nothing is hidden: the count and reason stay in the payload and the note; the
  // underlying stranded steps and the review-decision loop they await are a tracked structural item.
  // A genuinely unexplained stall (ready, classified, eligible, with NO action_execution) still
  // raises. The 5 historical error rows remain until they age out of agent_runs; a 6th (the fix not
  // holding) still fails this check.
  { agent: 'workflow_step_sweep', errors: 5,
    why: 'the re-enabled 10-min sweep raised status=error 5 times on 2 Sep (00:16-01:16Z) reporting 3 '
       + '"unexplained true stalls" that were actually three knowledge_fill steps stranded since 13-14 '
       + 'Aug — cancelled by fn_execution_sweep with no gate decision, left ready, and not re-queueable '
       + 'over their terminal action_execution. FIXED '
       + '(scripts/sql/workflow_sweep_stranded_by_cancelled_action.sql): such a step is now classified '
       + 'as ineligible-with-reason (out of parked_unexplained) and carried by one deduplicated '
       + 'org_task. Verified parked_unexplained=0, status=ok. Not a code defect introduced here — a '
       + 'watcher correctly surfacing a pre-existing stall it was mislabelling.' },
  // 2 SEP 2026 — A RE-ENABLED LLM DISPATCHER RUNNING INTO THE PAID-PROVIDER HOLD. workflow_dispatch is
  // the worker that advances a workflow step by calling the reasoning model to write the deliverable.
  // It was re-enabled with the rest of the runtime, but the founder's paid-provider hold is open-
  // circuit on 8 of 8 routes (fn_kernel_paid_provider_gate allowed:false, rule founder_hold; OpenRouter
  // off until launch), so every model call comes back empty and each 10-min tick claimed a step and
  // released it with "the model returned nothing". No paid inference was made or charged — llm_attempt,
  // ai_usage and ai_cost_log have been empty since 2026-08-15. FIXED: workflow_dispatch now asks the
  // paid gate BEFORE claiming (supabase/functions/workflow_dispatch, v12) and, when inference is held,
  // claims nothing and returns a clean idle result — so it stops erroring and resumes automatically the
  // moment the hold lifts at launch. The historical rows remain until they age out of agent_runs; a new
  // error after the fix (the idle guard not holding) still fails this check.
  { agent: 'workflow_dispatch', errors: 10,
    why: 'the re-enabled 10-min workflow dispatcher called the reasoning model to write each deliverable '
       + 'while the founder paid-provider hold is open-circuit (OpenRouter off until launch), so the '
       + 'model returned nothing and the step was released as "the model returned nothing". No paid '
       + 'inference made or charged (llm_attempt/ai_usage/ai_cost_log empty since 2026-08-15). FIXED: it '
       + 'now checks fn_kernel_paid_provider_gate before claiming and idles cleanly while inference is '
       + 'held (workflow_dispatch v12), resuming automatically when the hold lifts.' },
  // 2 SEP 2026 — THE KNOWLEDGE-DEEPEN ENGINE HIT THE SAME HELD PROVIDER. kb_deepen generates a topic
  // map with the reasoning model before pulling sources; one call at 19:37Z returned nothing under the
  // same open-circuit paid-provider hold, logged as "topic map generation returned nothing". Its crons
  // (kb_deepen_loop #136, kb_autofill_gaps_weekly #97) are INACTIVE, so it is not re-triggered on a
  // schedule; no paid inference was made or charged. Same held-provider cause as resend_inbound above.
  { agent: 'kb_deepen', errors: 2,
    why: 'kb_deepen\'s topic-map model call returned nothing under the open-circuit paid-provider hold '
       + '(OpenRouter off until launch): once at 2026-09-02 19:37Z, and again on 3 Sep when it was driven '
       + 'to verify the fix. FIXED (supabase/functions/kb_deepen): when the topic map is empty it now '
       + 'asks fn_kernel_paid_provider_gate and, if inference is held, records status=skipped with the '
       + 'reason rather than error — verified by execution (a held call now logs skipped). No paid '
       + 'inference made or charged. Same held-provider cause as resend_inbound; a NEW error after the fix '
       + '(the gate check not holding) still fails this check.' },
  // 3 SEP 2026 — HELD-MODEL FALLBACK ERRORS FROM THE DETERMINISTIC-FIRST EXECUTORS. cos_execute and
  // workflow_dispatch now try a deterministic playbook FIRST; when nothing matches they fall back to
  // agent_brain (the ~5% model path), which under the open-circuit hold returned nothing. agent_brain
  // logged those as an employee error before the fix. FIXED across the chain: _shared/llm.ts now carries
  // the gateway's 'circuit_open' outcome through makeLlmRich, and agent_brain records a held return as
  // status=skipped, not error (v53). No paid inference made or charged (llm_attempt/ai_usage/ai_cost_log
  // empty since 2026-08-15). The historical rows below remain until they age out of agent_runs; a NEW
  // error from any of these agents after the fix still fails this check.
  { agent: 'ops_director', errors: 2,
    why: 'department-work orders reached agent_brain as cos_execute\'s no-playbook-match fallback while '
       + 'the paid provider is held open-circuit, so the model returned nothing and the turn logged as an '
       + 'error (2026-09-03 00:16Z, 01:04Z). FIXED: agent_brain records a held return as skipped (v53). '
       + 'No paid inference made or charged.' },
  { agent: 'followup', errors: 2,
    why: 'same held-model fallback path as ops_director (2026-09-03 01:10Z), fixed the same way — '
       + 'agent_brain now records a held return as skipped, not error. No paid inference made or charged.' },
  { agent: 'cto', errors: 1,
    why: 'same held-model fallback path as ops_director (2026-09-03 01:06Z), fixed the same way. No paid '
       + 'inference made or charged.' },
  // 3 SEP 2026 — A REVIEW THAT REPORTS RED KPIs AS status=error, and an on-demand context miss. Neither
  // is a held-provider or code defect introduced here; both are disclosed as understood.
  { agent: 'os_review', errors: 2,
    why: 'os_review runs the weekly operating-system review and logs status=error when the review it '
       + 'produces contains red KPIs (2026-W36: 0 green, 10 amber, 2 red). The review SUCCEEDED — the '
       + 'reds are its findings, not a run failure — but it records the reds as an error row. A pre-'
       + 'existing reporting choice, surfaced now that the review cron is active; the reds are the real '
       + 'company state the CEO/CPO loop is chasing. FIXED 3 Sep 2026 (fn_os_review_logs_findings_as_findings.sql): '
       + 'the review now logs status=ok with red/amber/green in counts, like its sibling reviews — a review '
       + 'that found reds succeeded — so fn_self_review no longer reads it as a recurring failure either. The '
       + '2 historical rows remain until they age out; a NEW error row (the fix not holding) still fails this check.' },
  // 3 SEP 2026 — SANDBOX REHEARSAL FALLOUT, each root-caused. The revenue-loop rehearsal
  // (rehearse_revenue_loop.mjs, demo_factory selftest) stood up demo suppliers and customers on
  // production and tore them down; three functions logged the run as an error on the way:
  { agent: 'enrich_capability', errors: 53,
    why: '52 + 1. Every demo supplier confirm called enrich_capability, whose capability-summary needs the '
       + 'paid model, held open-circuit -> llm_no_summary, logged as error 52 times. The held model is '
       + 'the configured state, not a failure, and the claim in its note that an un-enriched supplier '
       + '"cannot be matched to any RFQ" is false — fn_match_capability matched 4 of 4 such suppliers '
       + 'on their confirmed capabilities in the same rehearsal. FIXED: enrich_capability now asks the '
       + 'paid gate and records a held model as skipped (supabase/functions/enrich_capability). The 52 '
       + 'historical rows remain until they age out. The 53rd (2026-09-03 ~05:00Z, stage auth) is one operator '
       + 'probe of the fix that presented cred_fn_enrich_capability — that is the OUTBOUND credential of that function, '
       + 'scoped to ai_gateway only — and was correctly refused out_of_scope; the proof was re-run with the '
       + 'fn.cos_execute credential, which is scoped to call it. A NEW error row still fails this check.' },
  { agent: 'send_outbox', errors: 2,
    why: 'the demo fixtures address suppliers and customers at RFC-2606 reserved domains '
       + '(@example.com / @example.invalid); Resend rejects those with 422 "Invalid to field", and the '
       + 'outbox logged the rejection as an error and retried. A reserved test domain is never '
       + 'deliverable, so refusing it is not a failure. FIXED: send_outbox now refuses reserved test '
       + 'domains as a clean skip before any provider call (supabase/functions/send_outbox), which also '
       + 'guarantees production never emails a fixture address. The 2 rows remain until they age out.' },
  // 3 SEP 2026 07:50Z — a refusal by policy logged as an error. cos_execute found org_tasks#526010
  // owned by customer_experience while the only executor for its class belongs to assurance, refused
  // the cross-department execution and routed the task to the advisory path: the correct outcome,
  // recorded with status='error'. FIXED the same hour (cos_execute logs it as skipped, the signal
  // executor_department_mismatch kept in counts). The one row remains until it ages out; a second
  // error row from this agent still fails this check.
  { agent: 'cos_execute', errors: 2,
    why: '4 SEP 2026, +1: tier_claim_exceeds_grant on org_tasks#526013 — approved as autonomous on 3 Sep when the authority model granted it, refused on 4 Sep after the STAFF_ORG walk lowered marketplace/recommend to advisory. A correct refusal, logged as error by the same shape the department-mismatch refusal had until 3 Sep; cos_execute v42 records it as skipped, and open tasks now carry the tier the model grants today (seven_packets_settle_into_one_estate.sql). ' + 'executor_department_mismatch refusal (org_tasks#526010, customer_experience vs assurance) routed '
       + 'to the advisory path and logged as error; fixed to skipped. Not a failed run.' },
  { agent: 'quote_compare', errors: 1,
    why: 'one operator probe presented cred_db_internal, which is not scoped to quote_compare; the '
       + 'guard fail-closed with 401 and logged it (2026-09-03 03:35Z) — the same shape as the kb_embed '
       + 'diagnostics above. The rehearsal was corrected to present the fn.cos_execute credential, which '
       + 'is scoped to it. Not a defect; a second row still fails this check.' },
  { agent: 'agent_context_missing', errors: 5,
    why: '4 SEP 2026, +2 (ceo 06:18Z, cto 06:27Z): the same 8s statement timeout on fn_agent_context_capped, this time under seven parallel agents driving the database. ' + 'fn_agent_context_capped returned no context on three on-demand turns — cto twice on 3 Sep '
       + '01:06Z/01:50Z and cfo once at 20:54Z during a rehearsal — each time because the statement '
       + 'hit the 8s timeout while five parallel agents and the executive-UI scorer were loading the '
       + 'database; the routine takes 0.7s idle (measured 4 Sep). agent_brain refused to answer from '
       + 'memory and logged the miss rather than reasoning blind — the fail-closed behaviour is '
       + 'correct, and the load was the session, not the company. A new count still fails this check.' },
  { agent: 'kb_autofill_gaps', errors: 27,
    why: '4 SEP 2026, 05:xx-07:02Z: the revived workflow loop dispatched knowledge_fill steps, whose executor triggers kb_autofill_gaps, which asked kb_fill_gap to generate knowledge for five empty categories; the paid provider is held by the founder, kb_fill_gap answered 502 generation_failed, and the autofill logged status=error 27 times (and posted a founder warning each time). ROOT CAUSE FIXED: kb_fill_gap v14 reports a held provider as a distinct non-error outcome and kb_autofill_gaps v13 records an all-held run as skipped and pages nobody. No knowledge was generated or charged. A new count still fails this check.' },
  { agent: 'dr_drill', errors: 2,
    why: 'Two hand-driven drills on 3 Sep (20:06Z and 20:13Z) ran the PREVIOUS dr_drill code, 40 '
       + 'minutes before the committed version was redeployed: the first could not count live rows in '
       + 'kb_chunks (2.6M rows; an exact count through PostgREST hit the 8s timeout, and the old code '
       + 'printed the error as [object Object]), the second met the first\'s 234,047 leftover rows '
       + 'and reported "cleared 200000 row(s) in 200 passes and 34047 still remain". Both are the '
       + 'drill saying its own verdict cannot be trusted, which is the correct fail-closed output; '
       + 'the backups were not at fault (the 20:52Z drill on the new code passed 11/11). ROOT CAUSE '
       + 'FIXED 4 Sep: the staging clear is one bounded server-side DELETE per pass '
       + '(fn_dr_restore_clear, 20,000 rows in 1.4s), the pre-clear now reaches 800,000 rows, and the '
       + 'drill deletes its own rows before it answers instead of in a fire-and-forget that never ran '
       + '(the 20:52Z run\'s 234,047 rows were all still there on 4 Sep). A new count still fails '
       + 'this check.' },
];

let cronRows = [], agentRows = [], watcher = null, activeWatchers = [];
if (hasToken) {
  const { sql } = await import('../phase_c/lib/db.mjs');
  cronRows = await sql(`
    select coalesce(j.jobname, 'jobid ' || d.jobid::text) as jobname,
           count(*)::int as failures,
           max(d.start_time)::text as newest
      from cron.job_run_details d
      left join cron.job j on j.jobid = d.jobid
     -- 5 SEP 2026: a tick still running has not failed. The red-view alerter's 15-minute sweep
     -- takes about a minute, CI read it mid-flight as status 'running', and this check reported
     -- "red_view_alert_15min: 1" as a failed scheduled run while every one of its ticks succeeded.
     -- Only a finished tick is judged — the same rule fn_kernel_system_trace_state adopted on 4 Sep.
     where d.status <> 'succeeded' and d.end_time is not null and d.start_time > timestamptz '${WATERMARK}'
     group by 1 order by 2 desc`);
  agentRows = await sql(`
    select agent, count(*)::int as errors, max(started_at)::text as newest
      from public.agent_runs
     where status = 'error' and started_at > timestamptz '${WATERMARK}'
     group by 1 order by 2 desc`);
  watcher = (await sql(`
    select j.jobid, j.jobname, j.active,
           (select count(*) from cron.job_run_details d where d.jobid = j.jobid)::int as prior_runs,
           (select max(d.start_time)::text from cron.job_run_details d where d.jobid = j.jobid) as last_run
      from cron.job j where j.jobname = 'watch_failed_runs_hourly'`))[0] || null;
  activeWatchers = await sql(`
    select jobname from cron.job
     where active and (jobname ilike '%fail%' or command ilike '%fn_watch_failed_runs%')
     order by jobname`);
}

// Cron failures after the watermark that are understood, owned and disclosed — same mechanism and
// same rules as the agent set above: keyed by jobname+count, so a NEW failing job, a second failure
// of a disclosed one, or a disclosed row that has aged out all still fail this check and force a re-read.
const DISCLOSED_CRON_AFTER_THE_WATERMARK = [
  { job: 'policy_consistency_weekly', failures: 1,
    why: 'the 2026-08-31 06:30Z run hit the 120s statement timeout: fn_policy_consistency_check '
       + 'regex-scanned ALL of kb_chunks, which grew 97k -> 2.69M during the agent-expertise ingestion, '
       + 'so its full-table scan no longer fit the timeout. FIXED — the kb_chunks scan is now scoped to '
       + 'the ~95k company-authored kinds (its pre-ingestion scope; the other seven stores are '
       + 'unchanged), verified to run in ~7s (scripts/sql/fix_policy_consistency_kb_scale.sql). The one '
       + 'historical failed row remains until it ages out of cron.job_run_details; a SECOND failure '
       + '(the fix not holding) still fails this check.' },
  // 3 SEP 2026 — THREE SELF-MANAGEMENT CRONS FAILED ONCE EACH ON AN UNRESOLVABLE ACCOUNTABLE ROLE.
  // When the deterministic KPI/learning crons were wrapped this session, three were given an
  // accountable_role_id that does not resolve in org_role, so fn_kernel_system_execution_trace RAISED
  // at the tick (00:35-00:50Z) and the run failed. ROOT CAUSE FIXED: the roles were aligned to the
  // committed component crosswalk (scripts/sql/enable_self_management_crons.sql +
  // declare_review_cron_components.sql); 0 active crons now carry an unresolvable role, and each of
  // these jobs has executed cleanly since. The one historical failed row per job remains until it ages
  // out of cron.job_run_details; a SECOND failure of any of them (the fix not holding) still fails this check.
  { job: 'agent_action_work_sweep_hourly', failures: 1,
    why: 'the 00:35Z run failed because its component carried accountable_role_id \'ops_director\', which '
       + 'does not resolve in org_role. Fixed: role set to chief_operating_officer (the crosswalk value); '
       + 'the job traces cleanly now.' },
  { job: 'cos_execute_hourly', failures: 1,
    why: 'the 00:50Z run failed because its component carried accountable_role_id \'brief\', which does '
       + 'not resolve in org_role. Fixed: role set to agent_workforce_capability_director (the crosswalk '
       + 'value); the job traces cleanly now.' },
  { job: 'red_view_alert_15min', failures: 1,
    why: '5 SEP 2026, 21:22Z: one tick hit the 120s cron statement_timeout inside '
       + 'fn_company_connectivity_register, which the alerter calls on every sweep. Cause: the class C '
       + 'arm added that evening (a trigger on company_event is a named consumer) correlated a LIKE over '
       + 'every trigger body per company_event ROW; idle it runs in about a second (measured 1s on 6 Sep), '
       + 'and under the lane packet\'s concurrent drive of sixteen dispatcher passes it crossed 120s once. '
       + 'FIXED 6 Sep (the_registers_trigger_arm_is_computed_once.sql): the arm is a membership test '
       + 'against a CTE computed once over the distinct event types. Every later tick succeeded. One '
       + 'historical row remains until it ages out; a second still fails this check.' },
  { job: 'action_invoke_rpc_5min', failures: 4,
    why: '4 SEP 2026, 06:15-06:30Z: four ticks hit the 120s statement timeout inside fn_org_exec_knowledge_fill, which ran a full-table category reconcile over 2.65M kb_chunks on every knowledge_fill action once the workflow loop was revived. FIXED the same morning (knowledge_fill_executor_reconciles_recent_chunks_only.sql): the reconcile is scoped to recent chunks; 0 failures since 06:31Z. The four historical rows remain until they age out; a fifth still fails this check.' },
  { job: 'learning_loop_sweep_hourly', failures: 1,
    why: 'the 00:35Z run failed because its component carried accountable_role_id \'qa_manager\', which '
       + 'does not resolve in org_role. Fixed: role set to agent_workforce_capability_director (the '
       + 'crosswalk value); the job traces cleanly now.' },
];

test('no scheduled job has failed since the stand-down', { skip: SKIP }, () => {
  const expected = DISCLOSED_CRON_AFTER_THE_WATERMARK.map((d) => `${d.job}: ${d.failures}`).sort();
  const actual = cronRows.map((r) => `${r.jobname}: ${r.failures}`).sort();
  console.log(`      cron.job_run_details since ${WATERMARK}: `
    + (cronRows.map((r) => `${r.jobname}(${r.failures}, newest ${r.newest})`).join(' | ') || 'none'));
  assert.deepEqual(actual, expected,
    'the set of scheduled jobs that failed after the stand-down has changed.\n'
    + `  expected: ${expected.join(' | ') || '(none)'}\n  actual:   ${actual.join(' | ') || '(none)'}\n`
    + DISCLOSED_CRON_AFTER_THE_WATERMARK.map((d) => `  ${d.job} — ${d.why}`).join('\n')
    + '\nRead the run detail before doing anything else. Do NOT reactivate a cron job to fix this;'
    + ' the stand-down is the founder\'s hold. A name that DISAPPEARED aged out — not a fix.');
});

test('no agent run has errored since the stand-down except the disclosed refusal', { skip: SKIP }, () => {
  const expected = DISCLOSED_AFTER_THE_WATERMARK
    .map((d) => `${d.agent}: ${d.errors}`).sort();
  const actual = agentRows.map((r) => `${r.agent}: ${r.errors}`).sort();
  console.log(`      public.agent_runs status='error' since ${WATERMARK}: `
    + (actual.join(' | ') || 'none'));
  assert.deepEqual(actual, expected,
    'the set of agent runs that errored after the stand-down has changed.\n'
    + `  expected: ${expected.join(' | ')}\n  actual:   ${actual.join(' | ') || '(none)'}\n`
    + DISCLOSED_AFTER_THE_WATERMARK.map((d) => `  ${d.agent} — ${d.why}`).join('\n')
    + '\nA NEW name here is an agent failing with no watcher running. A name that DISAPPEARED means'
    + ' the row aged out of the table, which is not a fix — re-read before lowering anything.');
});

test('the failure watchers are back on — the founder lifted the stand-down (2 Sep 2026)', { skip: SKIP }, () => {
  // UPDATED 2 Sep 2026, exactly as the prior text of this test instructed ("that is the founder lifting
  // part of the stand-down, which is his to do — but this file was written on the premise that nothing
  // watches, so update it"). The founder lifted the stand-down and instructed re-enabling the automation
  // ("lift all previous limits or frozen gates; OpenRouter is never an excuse"). watch_failed_runs was
  // re-enabled as a traced kernel component (its command now runs fn_kernel_cron_exec(137)). The premise
  // that nothing watches is retired; what is asserted now is the INVERSE — the failure-detection loop is
  // CLOSED, so every failure has a reader.
  assert.ok(watcher, 'cron job watch_failed_runs_hourly no longer exists. It had 488 prior runs;'
    + ' a job that vanished is a different event from a job that was switched off, and needs reading.');
  console.log(`      watch_failed_runs_hourly: jobid ${watcher.jobid}, active=${watcher.active},`
    + ` ${watcher.prior_runs} prior runs, last ${watcher.last_run}`);
  assert.equal(watcher.active, true,
    'watch_failed_runs_hourly is OFF. The founder lifted the stand-down on 2 Sep 2026 and the'
    + ' failure-detection loop must be on so that every failure has a reader acting on it.');
});
