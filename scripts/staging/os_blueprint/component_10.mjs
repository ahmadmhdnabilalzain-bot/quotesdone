// Component 10 — the Decision Engine, scored against PRODUCTION.
//
// The blueprint names ten steps: Problem, Gather Data, Knowledge Retrieval, Analysis, Risk,
// Options, Authority, Decision, Execution, Outcome. Every check below asks the same three
// questions and refuses to conflate them:
//
//   1. does the mechanism EXIST?           (column / routine / trigger / table)
//   2. is it POPULATED and does it RUN?    (rows, and rows produced by code, not by hand)
//   3. does anything READ its output?      (pg_proc + cron.job + views that are themselves read)
//
// The specific failure this component keeps producing is step-shaped rather than table-shaped:
// decision_record carries every field the ten steps need and was for months written by nothing but
// a person, so a check that counts columns or counts rows scores it MET for the wrong reason.
// Hence DR_WRITER: a routine that actually writes the artefact.
//
// qd_guard refuses any read whose text contains a bare write keyword, so every writer regex is
// assembled from split literals ('inser'||'t) inside the SQL itself.
//
// ── WHAT THE 6 Aug ADVERSARIAL REVIEW CHANGED HERE ───────────────────────────────────────────
// Eleven defects were raised against this file and every one of them was one of two shapes:
// a reader test that counted the writer, or an existence test standing in for a mechanism test.
// The repairs, all in the strict direction:
//   * LIVE_READS replaces the harness READERS() everywhere. It names and excludes the object's own
//     writers (derived from the write regex, not a hand list that rots) and the table's own trigger
//     functions, and it counts a VIEW only when something outside that set consumes the view. Under
//     the old helper, fn_decide — which writes decision_record, decision_trace and action_execution
//     — counted as their reader, and fn_decision_gate, the BEFORE trigger ON decision_record,
//     counted as a reader of the row it is in the middle of writing.
//   * comp-10-02 measures the WHOLE decision ledger again. The population had been narrowed to
//     kind <> 'action_gate', which removed 1,088 of 1,098 rows — while comp-10-05 and comp-10-07
//     go on citing those same action_gate rows as proof that the risk and authority steps run. A
//     row cannot be a decision in step 5 and not a decision in step 2. The window is 24h rather
//     than the old 30 days precisely so the check measures current writer behaviour instead of
//     unamendable history: decision_log carries declog_immutable and is append-only.
//   * comp-10-09 lost its dead disjunct (agent_actions still has no decision column: 0 of 2,106)
//     and gained coverage plus a real reader test.
//   * comp-10-04 no longer requires the step-7 gate to have inspected the row.
//   * comp-10-06's writer clause now has to name the options COLUMN in the insert, not the word.
//   * DR_WRITER tolerates quoted identifiers, which the old regex silently missed.

// ── writer / reader primitives ───────────────────────────────────────────────────────────────
// Does this routine WRITE the object? Used both to find producers and to disqualify a producer
// from being counted as its own reader.
const WRITES = (t, a = 'p') => `pg_get_functiondef(${a}.oid) ~*
      ('(inser' || 't|upda' || 'te|dele' || 'te)\\s+(into\\s+|from\\s+)?("?public"?\\s*\\.\\s*)?"?${t}\\y')`;

// Is this routine a trigger function ON the object? A BEFORE trigger is part of writing the row,
// never a consumer of it.
const TRIGFN = (t, a = 'p') => `exists (select 1 from pg_trigger tg join pg_class tc on tc.oid = tg.tgrelid
      join pg_namespace tn on tn.oid = tc.relnamespace
      where tn.nspname = 'public' and tc.relname = '${t}'
        and not tg.tgisinternal and tg.tgfoid = ${a}.oid)`;

// Does anything READ this object? `notReader(alias)` is a predicate marking a routine that must not
// count — the writers and the table's own triggers. Views count only when the view is itself
// consumed by a routine, a cron job or another view outside that set: an audit view that nothing
// opens is not a reader, it is a second unread artefact.
const LIVE_READS = (obj, notReader = () => 'false') => `(
    (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public' and p.prokind in ('f','p') and p.proname <> '${obj}'
        and not (${notReader('p')})
        and pg_get_functiondef(p.oid) ~* '\\y${obj}\\y')
  + (select count(*) from cron.job j where j.command ~* '\\y${obj}\\y')
  + (select count(*) from pg_views v where v.schemaname = 'public' and v.definition ~* '\\y${obj}\\y'
      and (exists (select 1 from pg_proc p2 join pg_namespace n2 on n2.oid = p2.pronamespace
                    where n2.nspname = 'public' and p2.prokind in ('f','p') and p2.proname <> '${obj}'
                      and not (${notReader('p2')})
                      and pg_get_functiondef(p2.oid) ~* ('\\y' || v.viewname || '\\y'))
        or exists (select 1 from cron.job j2 where j2.command ~* ('\\y' || v.viewname || '\\y'))
        or exists (select 1 from pg_views v2 where v2.schemaname = 'public'
                      and v2.viewname <> v.viewname and v2.definition ~* ('\\y' || v.viewname || '\\y')))))`;

// For a TABLE, neither its writers nor its own trigger functions are readers. decision_log's
// trg_declog_immutable is the case in point: it exists to refuse UPDATE and DELETE on the ledger,
// so it inspects OLD and NEW as part of writing and consumes nothing.
const TABLE_READS = (t) => LIVE_READS(t, a => `${WRITES(t, a)} or ${TRIGFN(t, a)}`);

const DR_READS = TABLE_READS('decision_record');
const DL_READS = TABLE_READS('decision_log');
const AE_READS = TABLE_READS('action_execution');
const DT_READS = TABLE_READS('decision_trace');
const OR_READS = TABLE_READS('outcome_record');
const EA_READS = TABLE_READS('employee_authority');
// fn_should_escalate is a routine, not a table: its "readers" are its callers and there is no
// writer to exclude, only the self-reference the helper already drops.
const ESC_CALLERS = LIVE_READS('fn_should_escalate');

// ── decision_record ──────────────────────────────────────────────────────────────────────────
// The old pattern was `(public\.)?decision_record` and silently missed `INSERT INTO
// "public"."decision_record"`. It gated three checks at once, so one blind spot could flip three
// verdicts. A trigger function assigning NEW is deliberately NOT a producer.
const DR_WRITER = `(select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public' and p.prokind in ('f','p')
      and pg_get_functiondef(p.oid) ~*
          ('(inser' || 't|upda' || 'te)\\s+(into\\s+)?("?public"?\\s*\\.\\s*)?"?decision_record\\y')
      and not ${TRIGFN('decision_record')})`;

// Step 6's producer clause used to be `and definitiontext ~* '\yoptions\y'`, which a parameter
// named p_options, a local variable or a comment satisfies. It now has to appear in the COLUMN
// LIST of an insert into decision_record, i.e. the routine writes that column.
const DR_WRITER_OPTIONS = `(select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public' and p.prokind in ('f','p')
      and pg_get_functiondef(p.oid) ~*
          ('(inser' || 't)\\s+into\\s+("?public"?\\s*\\.\\s*)?"?decision_record"?\\s*\\([^)]*\\yoptions\\y'))`;

const DR_ROWS = `(select count(*) from public.decision_record)`;
const DR_GATED = `(select count(*) from public.decision_record
    where gate_verdict is not null and gate_checked_at is not null and status in ('approved','executed'))`;
const DR_GATED_7D = `(select count(*) from public.decision_record
    where gate_verdict is not null and gate_checked_at is not null
      and gate_checked_at > now() - interval '7 days')`;
// Every row that claims to be approved/executed must carry the gate's stamp. A row that reached
// 'approved' with no verdict is a gate that was bypassed, which is the failure step 7 is about.
const DR_APPROVED_UNGATED = `(select count(*) from public.decision_record
    where status in ('approved','executed') and (gate_verdict is null or gate_checked_at is null))`;

const DR_ANALYSED = `(select count(*) from public.decision_record
    where coalesce(length(impact_business),0)  >= 20
      and coalesce(length(impact_financial),0) >= 20
      and coalesce(length(impact_legal),0)     >= 10
      and coalesce(length(impact_customer),0)  >= 20
      and jsonb_array_length(coalesce(evidence,'[]'::jsonb)) > 0)`;
const DR_OPTIONED = `(select count(*) from public.decision_record
    where jsonb_typeof(options) = 'array' and jsonb_array_length(options) >= 2)`;
const DR_PROBLEMED = `(select count(*) from public.decision_record
    where coalesce(length(btrim(problem)),0) >= 10)`;
const DR_FRESH = `(select coalesce(max(created_at), '-infinity'::timestamptz) from public.decision_record)`;

// One row carrying the WHOLE chain: a stated problem, scored alternatives, the four impacts,
// retrieved evidence, the authority gate's stamp, and an execution that names it. Ten steps that
// each leave a field on a different row are not a chain.
const DR_CHAIN_7D = `(select count(*) from public.decision_record d
    where d.created_at > now() - interval '7 days'
      and coalesce(length(btrim(d.problem)),0) >= 10
      and jsonb_typeof(d.options) = 'array' and jsonb_array_length(d.options) >= 2
      and coalesce(length(d.impact_business),0)  >= 20
      and coalesce(length(d.impact_financial),0) >= 20
      and coalesce(length(d.impact_legal),0)     >= 10
      and coalesce(length(d.impact_customer),0)  >= 20
      and jsonb_array_length(coalesce(d.evidence,'[]'::jsonb)) > 0
      and d.gate_verdict is not null and d.gate_checked_at is not null
      and exists (select 1 from public.action_execution a
                   where a.request ->> 'decision_record_id' = d.id::text))`;

// ── decision_log ─────────────────────────────────────────────────────────────────────────────
// THE POPULATION IS THE WHOLE LEDGER. Every routine that writes decision_log is a decision writer:
// fn_decide, fn_ai_gate and trg_action_gate. Excluding the last two removes 99% of the company's
// decisions from step 2 while steps 5 and 7 keep citing them, and a check may not have it both ways.
const DL_24H = `(select count(*) from public.decision_log where created_at > now() - interval '24 hours')`;
const DL_24H_SOURCED = `(select count(*) from public.decision_log
    where created_at > now() - interval '24 hours'
      and jsonb_typeof(sources) = 'array' and jsonb_array_length(sources) > 0)`;
const DL_UNSOURCED_KINDS = `(select coalesce(string_agg(kind || '=' || n::text, ', '), 'none') from (
      select kind, count(*) n from public.decision_log
      where created_at > now() - interval '24 hours'
        and coalesce(jsonb_array_length(case when jsonb_typeof(sources) = 'array' then sources end), 0) = 0
      group by 1 order by 2 desc) z)`;

const DL_7D = `(select count(*) from public.decision_log where created_at > now() - interval '7 days')`;
const DL_ENGINE_7D = `(select count(*) from public.decision_log
    where kind <> 'action_gate' and created_at > now() - interval '7 days')`;
const DL_ENGINE_7D_KNOWLEDGE = `(select count(*) from public.decision_log
    where kind <> 'action_gate' and created_at > now() - interval '7 days'
      and sources::text ~* '(knowledge|memory_search|kb_|lesson)')`;
const DL_7D_ROUTED = `(select count(*) from public.decision_log
    where kind in ('action_gate','escalate','approve') and route_to is not null
      and created_at > now() - interval '7 days')`;

// fn_decide must reach a knowledge store by name, and fn_memory_search must be reached BY fn_decide
// specifically — "some routine somewhere mentions it" is the loose form this file was caught using.
const FN_DECIDE_RETRIEVES = `(select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public' and p.proname = 'fn_decide'
      and pg_get_functiondef(p.oid) ~*
          '(fn_memory_search|fn_kb_retrieve|fn_ops_knowledge_search|agent_knowledge|institutional_memory|org_memory|agent_memory)')`;
const FN_DECIDE_CALLS_SEARCH = `(select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public' and p.proname = 'fn_decide'
      and pg_get_functiondef(p.oid) ~* '\\yfn_memory_search\\s*\\(')`;
// The retrieved hits have to LAND on the artefact an employee is handed, not merely be fetched.
const DR_EVIDENCE_RETRIEVED_7D = `(select count(*) from public.decision_record
    where created_at > now() - interval '7 days' and evidence::text ~* 'memory_search')`;
const DR_7D = `(select count(*) from public.decision_record where created_at > now() - interval '7 days')`;

// ── step 7, the authority gate ───────────────────────────────────────────────────────────────
// Not "any non-internal trigger exists" — an updated_at stamper satisfies that. The trigger's
// function must be the authority gate: it consults employee_authority and it stamps the verdict.
const DR_AUTH_TRIGGER = `(select count(*) from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace ns on ns.oid = c.relnamespace
    join pg_proc fp on fp.oid = t.tgfoid
    where ns.nspname = 'public' and c.relname = 'decision_record' and not t.tgisinternal
      and pg_get_functiondef(fp.oid) ~* '\\yemployee_authority\\y'
      and pg_get_functiondef(fp.oid) ~* '\\ygate_verdict\\y')`;

// ── step 9, execution ────────────────────────────────────────────────────────────────────────
// The execution must name the decision_record it came from, that id must RESOLVE to a real row,
// and it must share a correlation_id with that decision's trace. Two unrelated rows in two tables
// are not a link, which is what the pre-review form accepted.
const AE_ROWS = `(select count(*) from public.action_execution)`;
const AE_LINKED = `(select count(*) from public.action_execution a
    join public.decision_trace t on t.correlation_id = a.correlation_id
    join public.decision_record d on d.id::text = a.request ->> 'decision_record_id'
    where t.entity_type = 'decision_record'
      and t.entity_id = a.request ->> 'decision_record_id')`;

// ── step 10, outcome ─────────────────────────────────────────────────────────────────────────
const OR_ROWS = `(select count(*) from public.outcome_record)`;
const OR_GRADED = `(select count(*) from public.outcome_record
    where verdict is not null and verdict <> 'pending')`;
// The real defect this check must catch: a row whose window closed and which nobody graded. The
// evaluator cron runs 03:30 daily, so one day of grace is the gap between due and next run.
const OR_OVERDUE = `(select count(*) from public.outcome_record
    where verdict = 'pending' and due_at < now() - interval '1 day')`;
const OR_DUE = `(select count(*) from public.outcome_record where verdict = 'pending' and due_at <= now())`;
// A pending row that cannot be measured when it comes due is a queued no-op, not a closed loop.
const OR_GRADEABLE = `(select count(*) from public.outcome_record o
    join public.employee_kpi k on k.id = o.expected_kpi_id
    where o.verdict = 'pending' and k.measure_sql is not null)`;
const OR_PENDING = `(select count(*) from public.outcome_record where verdict = 'pending')`;
const OR_CRON_ACTIVE = `(select count(*) from cron.job where command ~* '\\yfn_outcome_evaluate\\y' and active)`;
const OR_CRON_OK_48H = `(select count(*) from cron.job j join cron.job_run_details d on d.jobid = j.jobid
    where j.command ~* '\\yfn_outcome_evaluate\\y' and j.active
      and d.status = 'succeeded' and d.start_time > now() - interval '48 hours')`;

export default async function ({ req }) {

  // The chain as one artefact. A routine writes it, the authority gate stamps it, an execution
  // points back at it, and something other than the writer reads it.
  await req('comp-10', 'comp-10-chain', 'Decision Engine: the 10 named steps run as one chain',
    `select ${DR_WRITER} > 0
        and ${DR_CHAIN_7D} > 0
        and ${DR_APPROVED_UNGATED} = 0
        and ${DR_READS} > 0`,
    `select 'routines writing decision_record=' || ${DR_WRITER}::text
         || ', rows=' || ${DR_ROWS}::text
         || ', complete ten-step rows in 7d=' || ${DR_CHAIN_7D}::text
         || ', approved rows the gate never stamped=' || ${DR_APPROVED_UNGATED}::text
         || ', readers excluding writer+trigger=' || ${DR_READS}::text`);

  // Step 1. A problem statement on every decision, written by the engine, reaching a reader.
  await req('comp-10', 'comp-10-01-problem', 'Step 1 Problem is captured per decision',
    `select ${DR_ROWS} > 0
        and ${DR_PROBLEMED} = ${DR_ROWS}
        and ${DR_WRITER} > 0
        and ${DR_FRESH} > now() - interval '7 days'
        and ${DR_READS} > 0`,
    `select ${DR_PROBLEMED}::text || ' of ' || ${DR_ROWS}::text
         || ' decision_record rows state a problem, written by ' || ${DR_WRITER}::text
         || ' routine(s), newest ' || ${DR_FRESH}::date::text
         || ', readers=' || ${DR_READS}::text`);

  // Step 2. Gathering is real only if the decision records what it retrieved.
  //
  // THE POPULATION IS EVERY DECISION, and the window is 24 hours. Both of those are deliberate.
  //   * Every routine that writes decision_log is a decision writer — fn_decide, fn_ai_gate and
  //     trg_action_gate. The version of this check written on 6 Aug narrowed the population to
  //     kind <> 'action_gate' and so scored 10 of 10 while 1,088 decisions in the same ledger
  //     recorded nothing; comp-10-05 and comp-10-07 below count those very rows as evidence that
  //     the risk and authority steps run. A row is a decision in every step or in none.
  //   * decision_log carries declog_immutable and is APPEND-ONLY, so the rows already written can
  //     never be corrected. A 30-day window therefore measures history and cannot go green on the
  //     work; a 24-hour window measures what the writers are doing NOW and clears one day after
  //     they are fixed. Production writes ~26-36 decisions a day, so it is never vacuous.
  // The failing writer is named in the evidence rather than excluded from the population.
  await req('comp-10', 'comp-10-02-gather-data', 'Step 2 Gather Data is a real retrieval step',
    `select ${DL_24H} > 0
        and ${DL_24H_SOURCED} = ${DL_24H}
        and ${FN_DECIDE_RETRIEVES} > 0
        and ${DL_READS} > 0`,
    `select ${DL_24H_SOURCED}::text || ' of ' || ${DL_24H}::text
         || ' decisions in the last 24h record what they retrieved; recording none: '
         || ${DL_UNSOURCED_KINDS}
         || '; 7d ' || ${DL_7D}::text || ' rows; decision_log readers excluding its writers='
         || ${DL_READS}::text`);

  // Step 3. Knowledge retrieval must feed the decision, not merely exist beside it. Three things:
  // the decision routine calls the search, EVERY decision it took recently records the retrieval,
  // and the hits land on the artefact fn_agent_context hands to an employee.
  //
  // Reachability is asserted by execution, not by a name scan. READERS('fn_decide') is 0 on
  // production and would be 0 for a perfectly healthy engine driven from an Edge Function, which
  // the pg_proc/pg_views/cron helper structurally cannot see; whereas rows written in the last
  // seven days cannot exist unless something called it. That is the stronger claim, not the softer.
  await req('comp-10', 'comp-10-03-knowledge-retrieval', 'Step 3 Knowledge Retrieval feeds the decision',
    `select ${FN_DECIDE_RETRIEVES} > 0
        and ${FN_DECIDE_CALLS_SEARCH} > 0
        and ${DL_ENGINE_7D} > 0
        and ${DL_ENGINE_7D_KNOWLEDGE} = ${DL_ENGINE_7D}
        and ${DR_7D} > 0
        and ${DR_EVIDENCE_RETRIEVED_7D} = ${DR_7D}
        and ${DR_READS} > 0`,
    `select ${DL_ENGINE_7D_KNOWLEDGE}::text || ' of ' || ${DL_ENGINE_7D}::text
         || ' engine decisions in 7d cite a retrieval; ' || ${DR_EVIDENCE_RETRIEVED_7D}::text
         || ' of ' || ${DR_7D}::text || ' decision_record rows in 7d carry the retrieved evidence;'
         || ' fn_decide calls fn_memory_search=' || (${FN_DECIDE_CALLS_SEARCH} > 0)::text
         || ', decision_record readers=' || ${DR_READS}::text`);

  // Step 4. The four impact fields plus evidence, on EVERY decision, written by a routine.
  //
  // The gate_checked_at clause that used to sit here has been removed: gate_checked_at is stamped
  // only by fn_decision_gate on a transition into approved/executed, which is step 7's authority
  // question, not step 4's. A decision can be fully analysed and never submitted for approval.
  // What replaces it is coverage — analysis on some rows is a column, analysis on all of them is
  // a step — plus DR_WRITER, so a person cannot satisfy step 4 by typing four paragraphs.
  await req('comp-10', 'comp-10-04-analysis', 'Step 4 Analysis (business/financial/legal/customer impact)',
    `select ${DR_ROWS} > 0
        and ${DR_ANALYSED} = ${DR_ROWS}
        and ${DR_WRITER} > 0
        and ${DR_READS} > 0`,
    `select ${DR_ANALYSED}::text || ' of ' || ${DR_ROWS}::text
         || ' decisions carry all four impacts plus evidence, written by ' || ${DR_WRITER}::text
         || ' routine(s), read by ' || ${DR_READS}::text || ' object(s) that are not the writer'`);

  // Step 5. Risk assessment on live decisions: fn_should_escalate has callers AND its verdicts
  // keep landing on decision_log inside the same 7-day window step 8 uses.
  await req('comp-10', 'comp-10-05-risk', 'Step 5 Risk Assessment runs on live decisions',
    `select ${ESC_CALLERS} > 0
        and ${DL_7D_ROUTED} > 0
        and ${DL_READS} > 0`,
    `select 'fn_should_escalate callers=' || ${ESC_CALLERS}::text
         || ', risk-assessed and routed decisions in 7d=' || ${DL_7D_ROUTED}::text
         || ' of ' || ${DL_7D}::text
         || ', decision_log readers excluding its writers=' || ${DL_READS}::text`);

  // Step 6. Alternatives must be GENERATED, and generated into the options COLUMN. The old clause
  // matched the bare word 'options' anywhere in a routine's text — a parameter, a local, a comment.
  await req('comp-10', 'comp-10-06-options', 'Step 6 Generate Options produces alternatives',
    `select ${DR_ROWS} > 0
        and ${DR_OPTIONED} = ${DR_ROWS}
        and ${DR_WRITER_OPTIONS} > 0
        and ${DR_READS} > 0`,
    `select ${DR_OPTIONED}::text || ' of ' || ${DR_ROWS}::text
         || ' decisions carry 2+ scored alternatives, written into the options column by '
         || ${DR_WRITER_OPTIONS}::text || ' routine(s), read by ' || ${DR_READS}::text`);

  // Step 7. The authority check ON THE DECISION — decision_record, which is what this component
  // calls "the decision". The pre-review form proved this with decision_log rows written by
  // trg_action_gate against agent_actions, an unrelated artefact, while decision_record's own gate
  // had inspected nothing; and its trigger clause counted ANY non-internal trigger, which an
  // updated_at stamper satisfies. Now: the trigger's function must consult employee_authority and
  // stamp the verdict, it must have stamped one recently, and no approved row may lack the stamp.
  await req('comp-10', 'comp-10-07-authority', 'Step 7 Authority Check gates the decision',
    `select ${DR_AUTH_TRIGGER} > 0
        and ${DR_GATED_7D} > 0
        and ${DR_APPROVED_UNGATED} = 0
        and (select count(*) from public.employee_authority) > 0
        and ${EA_READS} > 0
        and ${DL_7D_ROUTED} > 0`,
    `select 'authority triggers on decision_record=' || ${DR_AUTH_TRIGGER}::text
         || ', decisions the gate stamped in 7d=' || ${DR_GATED_7D}::text
         || ' (all time ' || ${DR_GATED}::text || '), approved-but-unstamped='
         || ${DR_APPROVED_UNGATED}::text
         || ', employee_authority rows=' || (select count(*) from public.employee_authority)::text
         || ' read by ' || ${EA_READS}::text
         || ', authority-routed decisions in 7d=' || ${DL_7D_ROUTED}::text`);

  // Step 8. The decision is recorded and read. Recency matters: a ledger that stopped is a ledger.
  await req('comp-10', 'comp-10-08-decision', 'Step 8 Decision is recorded and read',
    `select (select count(*) from public.decision_log) > 0
        and ${DL_7D} > 0
        and ${DL_READS} > 0`,
    `select (select count(*) from public.decision_log)::text || ' decisions, '
         || ${DL_7D}::text || ' in the last 7d, read by ' || ${DL_READS}::text
         || ' object(s) other than its own producers'`);

  // Step 9. Execution linked BACK to the decision.
  //
  // The `or agent_actions carries a decision id` disjunct is GONE. It could never return true —
  // agent_actions' 17 columns hold no decision id, measured 0 of 2,106 — and it carried no reader
  // clause at all, so adding the column would have scored the requirement MET on row count alone.
  // What stands is the designed pair, asserted as a join and at full coverage: every execution
  // names a decision_record that RESOLVES, and shares a correlation_id with that decision's trace.
  //
  // The reader clause is the one that costs. action_execution and decision_trace are referenced by
  // exactly one routine — fn_decide, which writes both — and by one view,
  // v_executions_without_decision_trace, whose own only mention anywhere is inside a COMMENT in
  // fn_decide. Excluding the writer and requiring the view to be consumed leaves zero readers. That
  // is the built-populated-unread verdict this whole spec file exists to produce, and the fix is a
  // consumer for the execution queue (nothing drains action_execution: all rows sit at 'queued'),
  // not a looser check.
  await req('comp-10', 'comp-10-09-execution', 'Step 9 Execution is linked back to the decision',
    `select ${AE_ROWS} > 0
        and ${AE_LINKED} = ${AE_ROWS}
        and (select count(*) from public.v_executions_without_decision_trace) = 0
        and ${AE_READS} > 0
        and ${DT_READS} > 0`,
    `select 'executions resolving to their decision_record=' || ${AE_LINKED}::text
         || ' of ' || ${AE_ROWS}::text
         || ', executions with no decision_trace=' || (select count(*) from public.v_executions_without_decision_trace)::text
         || ', decision_trace rows=' || (select count(*) from public.decision_trace)::text
         || ', readers excluding the writer: action_execution=' || ${AE_READS}::text
         || ' decision_trace=' || ${DT_READS}::text`);

  // Step 10. The loop closes when an outcome has been GRADED — except that a grade cannot exist
  // before the thing being graded has had time to happen.
  //
  // outcome_record holds 51 rows, all pending, earliest due 2026-08-11; today is 6 Aug 2026.
  // fn_outcome_evaluate grades `where verdict='pending' and due_at <= now()`, so the first grade in
  // this system's history is five days away and no correct implementation can produce one today.
  // The only way to turn an unconditional graded>0 green was to backdate a due_at or write a
  // verdict by hand — faking the measurement the component exists to make honest.
  //
  // So it asserts what IS knowable, strictly: nothing is overdue and ungraded, every pending row
  // joins a KPI with a measure so grading will be real rather than 'unmeasurable', the evaluator
  // cron is active AND its last run actually succeeded inside 48h, the table has readers that are
  // not its two writers, and either a grade exists or nothing has come due. The overdue clause is
  // a standalone conjunct, not a disjunct — once the first grade lands it must keep holding, so a
  // stalled evaluator fails this check from 2026-08-12 onward instead of being masked by history.
  await req('comp-10', 'comp-10-10-outcome', 'Step 10 Outcome Measurement closes the loop',
    `select ${OR_ROWS} > 0
        and ${OR_OVERDUE} = 0
        and ${OR_GRADEABLE} = ${OR_PENDING}
        and ${OR_CRON_ACTIVE} > 0
        and ${OR_CRON_OK_48H} > 0
        and ${OR_READS} > 0
        and (${OR_GRADED} > 0 or ${OR_DUE} = 0)`,
    `select ${OR_GRADED}::text || ' of ' || ${OR_ROWS}::text
         || ' outcomes graded, ' || ${OR_DUE}::text || ' due now, ' || ${OR_OVERDUE}::text
         || ' overdue by more than a day; ' || ${OR_GRADEABLE}::text || ' of ' || ${OR_PENDING}::text
         || ' pending rows join a KPI with a measure; earliest due '
         || coalesce((select min(due_at)::date::text from public.outcome_record where verdict = 'pending'), 'n/a')
         || '; evaluator cron active=' || ${OR_CRON_ACTIVE}::text
         || ' succeeded in 48h=' || ${OR_CRON_OK_48H}::text
         || '; readers excluding fn_outcome_open/evaluate=' || ${OR_READS}::text`);
}
