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
// ── WHAT THE SECOND ADVERSARIAL ROUND (6 Aug, later) CHANGED HERE ────────────────────────────
// Nine defects were raised against the hardened file. Every repair is recorded at the clause it
// changed; the four that changed the SHAPE of a test rather than one predicate are:
//
//   * A PRODUCER IS NOT A READER — BUT A CONSUMER THAT MARKS WHAT IT CONSUMED IS. TABLE_READS used
//     to disqualify any routine matching insert|update|delete. That made the reader test on
//     action_execution and decision_trace unsatisfiable BY THE VERY FIX its own comment prescribed:
//     a queue drainer must set action_execution.status, and a trace evaluator must set
//     decision_trace.outcome_status, so both would have been excluded the moment they were built.
//     The exclusion is now INSERT-only plus the table's own trigger functions: whoever creates the
//     artefact cannot be its reader; whoever settles an artefact someone else created must have
//     read it to settle it. Verified this changes nothing for decision_record, decision_log or
//     employee_authority — every producer there inserts.
//   * LIVE_READS' cron terms were unguarded: no `j.active`, no writer exclusion. A retention job of
//     the shape "dele||te from action_execution where created_at < ..." made the table its own
//     reader, and any one of production's 19 INACTIVE jobs counted as a live consumer. Both terms
//     now require the job to be active and to not be writing the object.
//   * pg_proc OVERLOADS were double-counted. fn_agent_context has two rows on production, so every
//     reader count containing it was inflated by one. Reader counts are now count(distinct proname).
//   * Where the requirement says EVERY, the check is now a per-row coverage count rather than a
//     bare existence test: comp-10-chain, -05, -07 and -09 all gained one.

// ── writer / reader primitives ───────────────────────────────────────────────────────────────
// Does this routine WRITE the object at all? Used to find producers of an artefact.
const WRITES = (t, a = 'p') => `pg_get_functiondef(${a}.oid) ~*
      ('(inser' || 't|upda' || 'te|dele' || 'te)\\s+(into\\s+|from\\s+)?("?public"?\\s*\\.\\s*)?"?${t}\\y')`;

// Does this routine PRODUCE the object's rows? This — not WRITES — is what disqualifies a routine
// from counting as the object's reader. The distinction is the whole point: fn_decide INSERTs
// action_execution and decision_trace, so it can never be their reader; fn_execution_sweep only
// UPDATEs rows fn_decide created, which it cannot do without reading them, so it is one.
const PRODUCES = (t, a = 'p') => `pg_get_functiondef(${a}.oid) ~*
      ('(inser' || 't)\\s+into\\s+("?public"?\\s*\\.\\s*)?"?${t}\\y')`;

// The same question asked of a cron job's command text, so a scheduled retention or backfill
// statement cannot make a table its own reader.
const CMD_WRITES = (t, c) => `${c} ~*
      ('(inser' || 't|upda' || 'te|dele' || 'te)\\s+(into\\s+|from\\s+)?("?public"?\\s*\\.\\s*)?"?${t}\\y')`;

// Is this routine a trigger function ON the object? A BEFORE trigger is part of writing the row,
// never a consumer of it.
const TRIGFN = (t, a = 'p') => `exists (select 1 from pg_trigger tg join pg_class tc on tc.oid = tg.tgrelid
      join pg_namespace tn on tn.oid = tc.relnamespace
      where tn.nspname = 'public' and tc.relname = '${t}'
        and not tg.tgisinternal and tg.tgfoid = ${a}.oid)`;

// Does anything READ this object? `notReader(alias)` marks a routine that must not count.
// Three terms, and each one has to earn its place:
//   * pg_proc, counted DISTINCT BY NAME so an overloaded routine is one reader, not two.
//   * cron.job, but only ACTIVE jobs whose command does not itself write the object.
//   * views, and only when the view is itself consumed by a routine, an active cron job or another
//     view outside the excluded set: an audit view nothing opens is a second unread artefact.
const LIVE_READS = (obj, notReader = () => 'false') => `(
    (select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public' and p.prokind in ('f','p') and p.proname <> '${obj}'
        and not (${notReader('p')})
        and pg_get_functiondef(p.oid) ~* '\\y${obj}\\y')
  + (select count(*) from cron.job j where j.active and j.command ~* '\\y${obj}\\y'
        and not (${CMD_WRITES(obj, 'j.command')}))
  + (select count(*) from pg_views v where v.schemaname = 'public' and v.definition ~* '\\y${obj}\\y'
      and (exists (select 1 from pg_proc p2 join pg_namespace n2 on n2.oid = p2.pronamespace
                    where n2.nspname = 'public' and p2.prokind in ('f','p') and p2.proname <> '${obj}'
                      and not (${notReader('p2')})
                      and pg_get_functiondef(p2.oid) ~* ('\\y' || v.viewname || '\\y'))
        or exists (select 1 from cron.job j2 where j2.active
                      and j2.command ~* ('\\y' || v.viewname || '\\y')
                      and not (${CMD_WRITES(obj, 'j2.command')}))
        or exists (select 1 from pg_views v2 where v2.schemaname = 'public'
                      and v2.viewname <> v.viewname and v2.definition ~* ('\\y' || v.viewname || '\\y')))))`;

// For a TABLE, neither its producers nor its own trigger functions are readers. decision_log's
// trg_declog_immutable is the case in point: it exists to refuse UPDATE and DELETE on the ledger,
// so it inspects OLD and NEW as part of writing and consumes nothing.
const TABLE_READS = (t) => LIVE_READS(t, a => `${PRODUCES(t, a)} or ${TRIGFN(t, a)}`);

const DR_READS = TABLE_READS('decision_record');
const DL_READS = TABLE_READS('decision_log');
const AE_READS = TABLE_READS('action_execution');
const DT_READS = TABLE_READS('decision_trace');
const OR_READS = TABLE_READS('outcome_record');
const EA_READS = TABLE_READS('employee_authority');

// fn_should_escalate is a routine, so its "readers" are its CALLERS — and a caller is a call, not
// a mention. The pre-repair form matched '\yfn_should_escalate\y' anywhere in a body, which a dead
// comment ("-- superseded by fn_should_escalate") or a string literal satisfies, while the evidence
// line printed the number as "callers=". The `\s*\(` form is the one this file already uses for
// FN_DECIDE_CALLS_SEARCH; both forms return the same 3 on production today, for different reasons.
const ESC_CALLERS = `(select count(distinct p.proname) from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public' and p.prokind in ('f','p') and p.proname <> 'fn_should_escalate'
      and pg_get_functiondef(p.oid) ~* '\\yfn_should_escalate\\s*\\(')`;

// ── decision_record ──────────────────────────────────────────────────────────────────────────
// The old pattern was `(public\.)?decision_record` and silently missed `INSERT INTO
// "public"."decision_record"`. It gated three checks at once, so one blind spot could flip three
// verdicts. A trigger function assigning NEW is deliberately NOT a producer.
const DR_WRITER = `(select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public' and p.prokind in ('f','p')
      and ${WRITES('decision_record')}
      and not ${TRIGFN('decision_record')})`;

// Step 6's producer clause used to be `and definitiontext ~* '\yoptions\y'`, which a parameter
// named p_options, a local variable or a comment satisfies. It now has to appear in the COLUMN
// LIST of an insert into decision_record, i.e. the routine writes that column.
const DR_WRITER_OPTIONS = `(select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
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
const DR_7D = `(select count(*) from public.decision_record where created_at > now() - interval '7 days')`;

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

// COVERAGE, because "the ten steps run as one chain" is a claim about every decision, not about
// one. DR_CHAIN_7D > 0 alone was MET on production with 3 complete chains out of 6 recent rows.
// The population splits honestly in two, and both halves are per-row NOT EXISTS:
//   * steps 1-6 and 8 are unconditional — every decision states a problem, scores two options,
//     carries the four impacts and its retrieved evidence, whether it escalates or not;
//   * steps 7 and 9 apply only where the gate PASSED. A decision the engine escalated is
//     deliberately left at 'proposed' with no execution, and demanding one would be demanding
//     that the engine act outside its authority.
const DR_INCOMPLETE_7D = `(select count(*) from public.decision_record d
    where d.created_at > now() - interval '7 days'
      and not (coalesce(length(btrim(d.problem)),0) >= 10
           and jsonb_typeof(d.options) = 'array' and jsonb_array_length(d.options) >= 2
           and coalesce(length(d.impact_business),0)  >= 20
           and coalesce(length(d.impact_financial),0) >= 20
           and coalesce(length(d.impact_legal),0)     >= 10
           and coalesce(length(d.impact_customer),0)  >= 20
           and jsonb_array_length(coalesce(d.evidence,'[]'::jsonb)) > 0))`;
const DR_PASSED_7D = `(select count(*) from public.decision_record
    where created_at > now() - interval '7 days' and gate_verdict = 'passed')`;
const DR_PASSED_UNEXECUTED_7D = `(select count(*) from public.decision_record d
    where d.created_at > now() - interval '7 days' and d.gate_verdict = 'passed'
      and not exists (select 1 from public.action_execution a
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
// THE RISK-ASSESSED POPULATION, NAMED. fn_should_escalate is the risk assessor, and the kinds that
// pass through it are exactly these three: trg_action_gate calls it for every 'action_gate' row,
// fn_decide calls it on 'escalate' and 'approve'. 'price', 'invite' and 'route_category' never
// reach it and are correctly outside the denominator — that is the justification the loose form
// owed and never gave. Every row that WAS risk-assessed must carry the routing the assessment
// produced; the old `> 0` scored the step MET on one row in seven days.
const DL_7D_RISK = `(select count(*) from public.decision_log
    where kind in ('action_gate','escalate','approve') and created_at > now() - interval '7 days')`;
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

// THE RETRIEVAL MARKER, AS STRUCTURE RATHER THAN AS A SUBSTRING. The pre-repair form was
// `evidence::text ~* 'memory_search'`, which the string ["memory_search: no hits"] satisfies and
// which a routine name appearing anywhere in the blob satisfies too. fn_decide writes a real
// element — {"kind":"memory_search","q":<query>,"hits":<n>} — so the marker is asserted as that
// object. The hits count is deliberately allowed to be 0 on an individual decision ("we searched
// and found nothing" is a different claim from "we never searched"), but DR_EVIDENCE_HITS_7D
// requires the search to have actually returned something for at least one decision in the window,
// so a permanently broken index cannot score the step MET.
const DR_EV_ELEMENTS = (d) => `jsonb_array_elements(
      case when jsonb_typeof(${d}.evidence) = 'array' then ${d}.evidence else '[]'::jsonb end)`;
const DR_EVIDENCE_RETRIEVED_7D = `(select count(*) from public.decision_record d
    where d.created_at > now() - interval '7 days'
      and exists (select 1 from ${DR_EV_ELEMENTS('d')} e
                   where e ->> 'kind' = 'memory_search' and (e -> 'hits') is not null))`;
const DR_EVIDENCE_HITS_7D = `(select count(*) from public.decision_record d
    where d.created_at > now() - interval '7 days'
      and exists (select 1 from ${DR_EV_ELEMENTS('d')} e
                   where e ->> 'kind' = 'memory_search'
                     and coalesce(nullif(e ->> 'hits','')::int, 0) > 0))`;

// DOES THE DECISION REACH THE EMPLOYEE? The header of comp-10-03 claimed the retrieval "lands on
// the artefact fn_agent_context hands to an employee" and no conjunct went anywhere near
// fn_agent_context. This one does, and it does it the way this suite requires elsewhere: by taking
// the STORED text and looking for it in the rendered prompt, not by matching a hard-coded heading
// that would print with every field null. fn_agent_context emits left(recommendation,150) under
// '# DECISIONS ALREADY ON RECORD FOR YOUR DEPARTMENT' for the two newest rows whose dept_key is
// the agent's or null, so those are exactly the rows tested.
const DR_REACHES_PROMPT = `(select count(*) from
    (select public.fn_agent_context('cfo', 22000) t) c,
    lateral (select d.recommendation r from public.decision_record d
              where d.dept_key is null
                 or d.dept_key = (select a.department from public.org_agents a where a.agent_key = 'cfo')
              order by d.id desc limit 2) x
    where coalesce(btrim(x.r),'') <> '' and position(left(x.r, 150) in c.t) > 0)`;

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

// THE COVERAGE THE AUTHORITY REGISTER ACTUALLY OWES. `(count from employee_authority) > 0` is one
// seed row making the register permanently satisfactory, and it never asks the only question step 7
// is about: did the actor whose decision the gate PASSED have any authority on file at all?
// Measured on production before the fix: 3 of 3 passed decisions were approved by 'operations_ai',
// which has no employee_authority row and no org_agents row — fn_decision_gate consults
// employee_authority only when financial_aed > 0, so a zero-value decision by an unknown actor was
// stamped 'passed' with nothing checked. fn_decide now escalates an actor with no authority record
// (scripts/sql/fn_decide_producer.sql), and 'founder' resolves because the gate itself treats it as
// top authority. The window is the same 7 days DR_GATED_7D uses, so the denominator is exactly the
// population the sibling leg already requires to be non-empty — this cannot pass vacuously, and the
// rows written before the fix age out rather than condemning the requirement forever.
const DR_PASSED_UNAUTHORISED_7D = `(select count(*) from public.decision_record d
    where d.created_at > now() - interval '7 days' and d.gate_verdict = 'passed'
      and coalesce(nullif(btrim(d.approved_by),''), d.decided_by, '') <> 'founder'
      and not exists (select 1 from public.employee_authority ea
                       where ea.agent_key = coalesce(nullif(btrim(d.approved_by),''), d.decided_by)))`;

// ── step 9, execution ────────────────────────────────────────────────────────────────────────
// The execution must name the decision_record it came from, that id must RESOLVE to a real row,
// and it must share a correlation_id with that decision's trace.
//
// COUNT(DISTINCT a.id), NOT COUNT(*). decision_trace.correlation_id carries only a non-unique index
// and a trace table is expected to hold several rows per correlation: the moment fn_decide writes a
// second trace row for one correlation the join fans out, AE_LINKED exceeds AE_ROWS, and
// `AE_LINKED = AE_ROWS` goes false with every execution perfectly linked. It read 3 = 3 by luck.
const AE_ROWS = `(select count(*) from public.action_execution)`;
const AE_LINKED = `(select count(distinct a.id) from public.action_execution a
    join public.decision_trace t on t.correlation_id = a.correlation_id
    join public.decision_record d on d.id::text = a.request ->> 'decision_record_id'
    where t.entity_type = 'decision_record'
      and t.entity_id = a.request ->> 'decision_record_id')`;
// Every other step in this file bounds recency; step 9 bounded nothing, so three frozen rows kept
// it true forever once execution stopped.
const AE_7D = `(select count(*) from public.action_execution where created_at > now() - interval '7 days')`;
const AE_NO_TRACE = `(select count(*) from public.v_executions_without_decision_trace)`;

// ── step 10, outcome ─────────────────────────────────────────────────────────────────────────
const OR_ROWS = `(select count(*) from public.outcome_record)`;
// 'unmeasurable' IS NOT GRADED. fn_outcome_evaluate wraps `execute r.measure_sql` in
// `exception when others then v_now := null` and writes verdict 'unmeasurable' on failure. Under
// the old `verdict <> 'pending'` form, a sweep in which every single measure_sql threw would set
// OR_GRADED above zero, drop OR_PENDING to zero (making `OR_GRADEABLE = OR_PENDING` vacuously
// 0 = 0), drop OR_OVERDUE to zero (an unmeasurable row is no longer pending, so it can never go
// overdue) and leave both cron clauses true — the whole check permanently green with 51 of 51
// outcomes ungraded in substance. Three repairs close it: 'unmeasurable' is excluded from graded,
// asserted at zero in its own right, and the gradeable clause is required to be non-vacuous.
const OR_GRADED = `(select count(*) from public.outcome_record
    where verdict is not null and verdict not in ('pending','unmeasurable'))`;
const OR_UNMEASURABLE = `(select count(*) from public.outcome_record where verdict = 'unmeasurable')`;
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
  // points back at it, and something other than the writer reads it — including the two artefacts
  // step 9 leaves behind. Citing action_execution as chain evidence while asking the reader
  // question only about decision_record was how this check scored MET beside a step-9 artefact that
  // comp-10-09 was simultaneously scoring as written-and-unread.
  await req('comp-10', 'comp-10-chain', 'Decision Engine: the 10 named steps run as one chain',
    `select ${DR_WRITER} > 0
        and ${DR_7D} > 0
        and ${DR_CHAIN_7D} > 0
        and ${DR_INCOMPLETE_7D} = 0
        and ${DR_PASSED_7D} > 0
        and ${DR_PASSED_UNEXECUTED_7D} = 0
        and ${DR_APPROVED_UNGATED} = 0
        and ${DR_READS} > 0
        and ${AE_READS} > 0
        and ${DT_READS} > 0`,
    `select 'routines writing decision_record=' || ${DR_WRITER}::text
         || ', rows=' || ${DR_ROWS}::text
         || ', in 7d=' || ${DR_7D}::text
         || ' of which incomplete on steps 1-6=' || ${DR_INCOMPLETE_7D}::text
         || ', complete ten-step rows in 7d=' || ${DR_CHAIN_7D}::text
         || ', gate-passed in 7d=' || ${DR_PASSED_7D}::text
         || ' of which unexecuted=' || ${DR_PASSED_UNEXECUTED_7D}::text
         || ', approved rows the gate never stamped=' || ${DR_APPROVED_UNGATED}::text
         || ', readers excluding producer+trigger: decision_record=' || ${DR_READS}::text
         || ' action_execution=' || ${AE_READS}::text
         || ' decision_trace=' || ${DT_READS}::text`);

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
         || '; 7d ' || ${DL_7D}::text || ' rows; decision_log readers excluding its producers='
         || ${DL_READS}::text`);

  // Step 3. Knowledge retrieval must feed the decision, not merely exist beside it. Four things:
  // the decision routine calls the search, EVERY decision it took recently carries the retrieval as
  // a structured marker, the search actually returned hits for at least one of them, and the
  // decision reaches the artefact fn_agent_context hands to an employee.
  //
  // Reachability of the engine itself is asserted by execution, not by a name scan.
  // READERS('fn_decide') is 0 on production and would be 0 for a perfectly healthy engine driven
  // from an Edge Function, which the pg_proc/pg_views/cron helper structurally cannot see; whereas
  // rows written in the last seven days cannot exist unless something called it.
  await req('comp-10', 'comp-10-03-knowledge-retrieval', 'Step 3 Knowledge Retrieval feeds the decision',
    `select ${FN_DECIDE_RETRIEVES} > 0
        and ${FN_DECIDE_CALLS_SEARCH} > 0
        and ${DL_ENGINE_7D} > 0
        and ${DL_ENGINE_7D_KNOWLEDGE} = ${DL_ENGINE_7D}
        and ${DR_7D} > 0
        and ${DR_EVIDENCE_RETRIEVED_7D} = ${DR_7D}
        and ${DR_EVIDENCE_HITS_7D} > 0
        and ${DR_REACHES_PROMPT} > 0
        and ${DR_READS} > 0`,
    `select ${DL_ENGINE_7D_KNOWLEDGE}::text || ' of ' || ${DL_ENGINE_7D}::text
         || ' engine decisions in 7d cite a retrieval; ' || ${DR_EVIDENCE_RETRIEVED_7D}::text
         || ' of ' || ${DR_7D}::text || ' decision_record rows in 7d carry a memory_search marker, '
         || ${DR_EVIDENCE_HITS_7D}::text || ' of them with a non-empty hit;'
         || ' fn_decide calls fn_memory_search=' || (${FN_DECIDE_CALLS_SEARCH} > 0)::text
         || '; decision recommendations found verbatim in an employee prompt=' || ${DR_REACHES_PROMPT}::text
         || ' of 2; decision_record readers=' || ${DR_READS}::text`);

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
         || ' routine(s), read by ' || ${DR_READS}::text || ' object(s) that are not the producer'`);

  // Step 5. Risk assessment on live decisions. Three claims, and none of them is a bare existence
  // test any more: fn_should_escalate is CALLED (not merely named), the risk-assessed population is
  // non-empty inside the same 7-day window step 8 uses, and EVERY row in that population carries
  // the routing the assessment produced. The denominator is named rather than assumed — the three
  // kinds listed in DL_7D_RISK are exactly the ones that pass through fn_should_escalate.
  await req('comp-10', 'comp-10-05-risk', 'Step 5 Risk Assessment runs on live decisions',
    `select ${ESC_CALLERS} > 0
        and ${DL_7D_RISK} > 0
        and ${DL_7D_ROUTED} = ${DL_7D_RISK}
        and ${DL_READS} > 0`,
    // qd_guard's read-only gate refuses any statement containing the bare word "call", so the
    // evidence says "invoked from" rather than "call sites".
    `select 'fn_should_escalate invoked from=' || ${ESC_CALLERS}::text
         || ', risk-assessed decisions in 7d=' || ${DL_7D_RISK}::text
         || ' of which routed=' || ${DL_7D_ROUTED}::text
         || ' (whole ledger in 7d ' || ${DL_7D}::text || ')'
         || ', decision_log readers excluding its producers=' || ${DL_READS}::text`);

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
  // calls "the decision". The trigger's function must consult employee_authority and stamp the
  // verdict, it must have stamped one recently, no approved row may lack the stamp, and — the leg
  // this check was missing entirely — every decision it PASSED must have been approved by someone
  // with authority on file.
  //
  // DL_7D_ROUTED IS GONE FROM HERE. Those rows are 100% kind='action_gate', written by
  // trg_action_gate against agent_actions; this file's own comment calls that "an unrelated
  // artefact" when criticising the pre-review form of this very check, and then imported it back as
  // a conjunct. Step 5 owns them, with a coverage ratio; step 7 is about decision_record.
  await req('comp-10', 'comp-10-07-authority', 'Step 7 Authority Check gates the decision',
    `select ${DR_AUTH_TRIGGER} > 0
        and ${DR_GATED_7D} > 0
        and ${DR_APPROVED_UNGATED} = 0
        and ${DR_PASSED_UNAUTHORISED_7D} = 0
        and ${EA_READS} > 0`,
    `select 'authority triggers on decision_record=' || ${DR_AUTH_TRIGGER}::text
         || ', decisions the gate stamped in 7d=' || ${DR_GATED_7D}::text
         || ' (all time ' || ${DR_GATED}::text || '), approved-but-unstamped='
         || ${DR_APPROVED_UNGATED}::text
         || ', gate-passed in 7d whose approver has no employee_authority row='
         || ${DR_PASSED_UNAUTHORISED_7D}::text || ' of ' || ${DR_PASSED_7D}::text
         || ' (offenders: ' || coalesce((select string_agg(distinct coalesce(nullif(btrim(d.approved_by),''), d.decided_by), ', ')
              from public.decision_record d
              where d.created_at > now() - interval '7 days' and d.gate_verdict = 'passed'
                and coalesce(nullif(btrim(d.approved_by),''), d.decided_by, '') <> 'founder'
                and not exists (select 1 from public.employee_authority ea
                                 where ea.agent_key = coalesce(nullif(btrim(d.approved_by),''), d.decided_by))), 'none')
         || '), employee_authority readers=' || ${EA_READS}::text`);

  // Step 8. The decision is recorded and read. Recency matters: a ledger that stopped is a ledger.
  await req('comp-10', 'comp-10-08-decision', 'Step 8 Decision is recorded and read',
    `select (select count(*) from public.decision_log) > 0
        and ${DL_7D} > 0
        and ${DL_READS} > 0`,
    `select (select count(*) from public.decision_log)::text || ' decisions, '
         || ${DL_7D}::text || ' in the last 7d, read by ' || ${DL_READS}::text
         || ' object(s) other than its own producers'`);

  // Step 9. Execution linked BACK to the decision, and drained by something.
  //
  // The `or agent_actions carries a decision id` disjunct is GONE. It could never return true —
  // agent_actions' 17 columns hold no decision id, measured 0 of 2,106 — and it carried no reader
  // clause at all, so adding the column would have scored the requirement MET on row count alone.
  // What stands is the designed pair, asserted as a join at full coverage with count(distinct) so
  // a second trace row on one correlation cannot make it unpassable, plus a recency bound so three
  // frozen rows cannot carry it forever, plus the reader question about BOTH artefacts.
  //
  // Those two reader clauses were the whole verdict this file existed to produce: action_execution
  // and decision_trace were named by exactly one routine, fn_decide, which writes them, and by one
  // view whose own only mention anywhere is inside a COMMENT in fn_decide. The fix was a consumer,
  // not a looser check — public.fn_execution_sweep (scripts/sql/fn_execution_sweep.sql, cron
  // execution_sweep_hourly) drains the queue and mirrors the observed status onto the trace's
  // outcome_status/outcome/evaluated_at columns, which nothing had ever written. It is counted as a
  // reader because it UPDATEs rows fn_decide created rather than creating them itself; the old
  // insert|update|delete exclusion would have disqualified the only fix that could work.
  await req('comp-10', 'comp-10-09-execution', 'Step 9 Execution is linked back to the decision',
    `select ${AE_ROWS} > 0
        and ${AE_LINKED} = ${AE_ROWS}
        and ${AE_7D} > 0
        and ${AE_NO_TRACE} = 0
        and ${AE_READS} > 0
        and ${DT_READS} > 0`,
    `select 'executions resolving to their decision_record=' || ${AE_LINKED}::text
         || ' of ' || ${AE_ROWS}::text || ' (' || ${AE_7D}::text || ' written in 7d)'
         || ', executions with no decision_trace=' || ${AE_NO_TRACE}::text
         || ', decision_trace rows=' || (select count(*) from public.decision_trace)::text
         || ', queue: ' || coalesce((select string_agg(status || '=' || n::text, ', ' order by status)
              from (select status, count(*) n from public.action_execution group by 1) z), 'empty')
         || ', readers excluding the producer: action_execution=' || ${AE_READS}::text
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
  // So it asserts what IS knowable, strictly: nothing is overdue and ungraded, NOTHING HAS BEEN
  // WRITTEN OFF AS UNMEASURABLE, every pending row joins a KPI with a measure, the gradeable clause
  // is applied to a non-empty population so it cannot pass by evaporating, the evaluator cron is
  // active AND its last run actually succeeded inside 48h, the table has readers that are not its
  // producers, and either a grade exists or nothing has come due. The overdue clause is a standalone
  // conjunct, not a disjunct — once the first grade lands it must keep holding, so a stalled
  // evaluator fails this check from 2026-08-12 onward instead of being masked by history.
  await req('comp-10', 'comp-10-10-outcome', 'Step 10 Outcome Measurement closes the loop',
    `select ${OR_ROWS} > 0
        and ${OR_OVERDUE} = 0
        and ${OR_UNMEASURABLE} = 0
        and (${OR_PENDING} > 0 or ${OR_GRADED} > 0)
        and ${OR_GRADEABLE} = ${OR_PENDING}
        and ${OR_CRON_ACTIVE} > 0
        and ${OR_CRON_OK_48H} > 0
        and ${OR_READS} > 0
        and (${OR_GRADED} > 0 or ${OR_DUE} = 0)`,
    `select ${OR_GRADED}::text || ' of ' || ${OR_ROWS}::text
         || ' outcomes graded, ' || ${OR_UNMEASURABLE}::text || ' written off unmeasurable, '
         || ${OR_DUE}::text || ' due now, ' || ${OR_OVERDUE}::text
         || ' overdue by more than a day; ' || ${OR_GRADEABLE}::text || ' of ' || ${OR_PENDING}::text
         || ' pending rows join a KPI with a measure; earliest due '
         || coalesce((select min(due_at)::date::text from public.outcome_record where verdict = 'pending'), 'n/a')
         || '; evaluator cron active=' || ${OR_CRON_ACTIVE}::text
         || ' succeeded in 48h=' || ${OR_CRON_OK_48H}::text
         || '; readers excluding fn_outcome_open=' || ${OR_READS}::text`);
}
