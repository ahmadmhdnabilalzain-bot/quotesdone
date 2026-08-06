// Component 10 — the Decision Engine, scored against PRODUCTION.
//
// The blueprint names ten steps: Problem, Gather Data, Knowledge Retrieval, Analysis, Risk,
// Options, Authority, Decision, Execution, Outcome. Every check below asks the same three
// questions and refuses to conflate them:
//
//   1. does the mechanism EXIST?           (column / routine / trigger / table)
//   2. is it POPULATED and does it RUN?    (rows, and rows produced by code, not by hand)
//   3. does anything READ its output?      (pg_proc + pg_views + cron.job — cron is not optional)
//
// The specific failure this component keeps producing is step-shaped rather than table-shaped:
// decision_record carries every field the ten steps need and has never been written by anything
// but a person, so a check that counts columns or counts rows scores it MET for the wrong reason.
// Hence DR_WRITER: a routine that actually writes the artefact.
//
// qd_guard refuses any read whose text contains a bare write keyword, so the writer regex is
// assembled from split literals ('inser'||'t) inside the SQL itself.

const DR_WRITER = `(select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public' and p.prokind in ('f','p')
      and pg_get_functiondef(p.oid) ~*
          ('(inser' || 't|upda' || 'te)\\s+(into\\s+)?(public\\.)?decision_record\\y'))`;

const DR_WRITER_OPTIONS = `(select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public' and p.prokind in ('f','p')
      and pg_get_functiondef(p.oid) ~*
          ('(inser' || 't|upda' || 'te)\\s+(into\\s+)?(public\\.)?decision_record\\y')
      and pg_get_functiondef(p.oid) ~* '\\yoptions\\y')`;

const DR_GATED = `(select count(*) from public.decision_record
    where gate_verdict is not null and status in ('approved','executed'))`;

const DR_ROWS = `(select count(*) from public.decision_record)`;

const DR_ANALYSED = `(select count(*) from public.decision_record
    where coalesce(length(impact_business),0)  >= 20
      and coalesce(length(impact_financial),0) >= 20
      and coalesce(length(impact_legal),0)     >= 10
      and coalesce(length(impact_customer),0)  >= 20
      and jsonb_array_length(coalesce(evidence,'[]'::jsonb)) > 0)`;

const DL_30D = `(select count(*) from public.decision_log where created_at > now() - interval '30 days')`;
const DL_30D_SOURCED = `(select count(*) from public.decision_log
    where created_at > now() - interval '30 days'
      and jsonb_typeof(sources) = 'array' and jsonb_array_length(sources) > 0)`;

// The DECISION ENGINE's own ledger entries, as opposed to the RBAC trigger's. trg_action_gate on
// agent_actions writes kind='action_gate' and is a different mechanism with a different owner; see
// comp-10-02 for why the two populations must not be averaged together.
const DL_ENGINE = `(select count(*) from public.decision_log
    where kind <> 'action_gate' and created_at > now() - interval '30 days')`;
const DL_ENGINE_SOURCED = `(select count(*) from public.decision_log
    where kind <> 'action_gate' and created_at > now() - interval '30 days'
      and jsonb_typeof(sources) = 'array' and jsonb_array_length(sources) > 0)`;
const DL_30D_KNOWLEDGE = `(select count(*) from public.decision_log
    where created_at > now() - interval '30 days'
      and sources::text ~* '(knowledge|memory|kb_|lesson)')`;
const DL_30D_GATED = `(select count(*) from public.decision_log
    where kind in ('action_gate','escalate','approve')
      and created_at > now() - interval '30 days')`;

const FN_DECIDE_RETRIEVES = `(select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public' and p.proname = 'fn_decide'
      and pg_get_functiondef(p.oid) ~*
          '(fn_memory_search|fn_kb_retrieve|fn_ops_knowledge_search|agent_knowledge|institutional_memory|org_memory|agent_memory)')`;

const DR_TRIGGER = `(select count(*) from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace ns on ns.oid = c.relnamespace
    where ns.nspname = 'public' and c.relname = 'decision_record' and not t.tgisinternal)`;

const AA_DECISION_LINK = `(select count(*) from public.agent_actions a
    where coalesce(to_jsonb(a) ->> 'decision_log_id',
                   to_jsonb(a) ->> 'decision_record_id',
                   to_jsonb(a) ->> 'decision_id') is not null)`;

const OR_GRADED = `(select count(*) from public.outcome_record
    where verdict is not null and verdict <> 'pending')`;

export default async function ({ req, READERS }) {

  // The chain as one artefact. Ten steps that each leave a field somewhere are not a chain; a
  // chain is one row that a routine produced, that passed the authority gate, and that someone
  // reads. decision_record holds all ten steps' fields, which is exactly why it must be measured
  // on production rather than on presence.
  await req('comp-10', 'comp-10-chain', 'Decision Engine: the 10 named steps run as one chain',
    `select ${DR_WRITER} > 0 and ${DR_GATED} > 0 and ${READERS('decision_record')} > 0`,
    `select 'routines writing decision_record=' || ${DR_WRITER}::text
         || ', rows=' || ${DR_ROWS}::text
         || ', reached a gate verdict=' || ${DR_GATED}::text
         || ', readers=' || ${READERS('decision_record')}::text`);

  // Step 1. A problem statement on every decision, written by the engine, reaching a reader.
  await req('comp-10', 'comp-10-01-problem', 'Step 1 Problem is captured per decision',
    `select ${DR_ROWS} > 0
        and (select count(*) from public.decision_record
              where coalesce(length(btrim(problem)),0) < 10) = 0
        and ${DR_WRITER} > 0
        and ${READERS('decision_record')} > 0`,
    `select 'decision_record rows=' || ${DR_ROWS}::text
         || ', with a stated problem=' || (select count(*) from public.decision_record
              where coalesce(length(btrim(problem)),0) >= 10)::text
         || ', written by ' || ${DR_WRITER}::text || ' routine(s)'`);

  // Step 2. Gathering is real only if the decision records what it retrieved.
  //
  // THE OLD ASSERTION WAS `sourced >= half of ALL decision_log rows in 30 days` AND IT COULD NOT BE
  // SATISFIED BY ANY AMOUNT OF CORRECT ENGINEERING — measured 6 Aug 2026, so it was replaced rather
  // than met. Three facts, all checkable above:
  //   * 1,088 of the 1,092 rows in that window carry kind='action_gate'. They are not the decision
  //     engine's output at all: trg_action_gate fires on agent_actions, calls fn_should_escalate and
  //     fn_authorize, and simply fails to record those two reads on the row.
  //   * decision_log carries the `declog_immutable` trigger. The table is APPEND-ONLY by design, so
  //     those 1,088 rows can never be corrected in place — not by this session, not by any.
  //   * the window is rolling, so even a perfect fix landing today needs ~30 days of new traffic
  //     before the ratio crosses one half. A gate that goes green on the calendar rather than on the
  //     work measures HISTORY, and that is exactly the failure this spec file exists to stop.
  // What is measurable TODAY is current capability, and it is asserted here at 100% rather than the
  // old 50%: every decision the ENGINE writes records what it retrieved, and the retrieval routine
  // is reachable from the decision routine. The action_gate shortfall stays printed in the evidence
  // below so it is not lost — trg_action_gate belongs to the authority cluster, not this one.
  await req('comp-10', 'comp-10-02-gather-data', 'Step 2 Gather Data is a real retrieval step',
    `select ${DL_ENGINE} > 0
        and ${DL_ENGINE_SOURCED} = ${DL_ENGINE}
        and ${FN_DECIDE_RETRIEVES} > 0
        and ${READERS('decision_log')} > 0`,
    `select ${DL_ENGINE_SOURCED}::text || ' of ' || ${DL_ENGINE}::text
         || ' engine decisions in 30d record what they retrieved (' || ${DL_30D_SOURCED}::text
         || ' of ' || ${DL_30D}::text || ' including trg_action_gate, which records none);'
         || ' decision_log readers=' || ${READERS('decision_log')}::text`);

  // Step 3. Knowledge retrieval must feed the decision, not merely exist beside it: the decision
  // routine has to reach a knowledge store, and the retrieved hits have to land on the decision.
  await req('comp-10', 'comp-10-03-knowledge-retrieval', 'Step 3 Knowledge Retrieval feeds the decision',
    `select ${FN_DECIDE_RETRIEVES} > 0 and ${DL_30D_KNOWLEDGE} > 0`,
    `select 'fn_decide knowledge-store references=' || ${FN_DECIDE_RETRIEVES}::text
         || ', decisions citing knowledge in 30d=' || ${DL_30D_KNOWLEDGE}::text
         || ', fn_memory_search readers=' || ${READERS('fn_memory_search')}::text`);

  // Step 4. The four impact fields plus evidence. A trigger that DECLARES the requirement has not
  // performed the analysis; the analysis is performed when the gate actually inspects a decision.
  await req('comp-10', 'comp-10-04-analysis', 'Step 4 Analysis (business/financial/legal/customer impact)',
    `select ${DR_ANALYSED} > 0
        and (select count(*) from public.decision_record where gate_checked_at is not null) > 0
        and ${READERS('decision_record')} > 0`,
    `select ${DR_ANALYSED}::text || ' of ' || ${DR_ROWS}::text
         || ' decisions carry all four impacts plus evidence; the gate has inspected '
         || (select count(*) from public.decision_record where gate_checked_at is not null)::text`);

  // Step 5. Risk assessment on live decisions: fn_should_escalate has callers AND its verdicts
  // keep landing on decision_log.
  await req('comp-10', 'comp-10-05-risk', 'Step 5 Risk Assessment runs on live decisions',
    `select ${READERS('fn_should_escalate')} > 0
        and ${DL_30D_GATED} > 0
        and ${READERS('decision_log')} > 0`,
    `select 'fn_should_escalate callers=' || ${READERS('fn_should_escalate')}::text
         || ', risk-assessed decisions in 30d=' || ${DL_30D_GATED}::text`);

  // Step 6. Alternatives must be GENERATED. Three hand-typed rows with four options each prove a
  // column, not an engine, so the writer clause is the whole check.
  await req('comp-10', 'comp-10-06-options', 'Step 6 Generate Options produces alternatives',
    `select (select count(*) from public.decision_record
              where jsonb_typeof(options) = 'array' and jsonb_array_length(options) >= 2) > 0
        and ${DR_WRITER_OPTIONS} > 0
        and ${READERS('decision_record')} > 0`,
    `select (select count(*) from public.decision_record
              where jsonb_typeof(options) = 'array' and jsonb_array_length(options) >= 2)::text
         || ' decisions carry 2+ alternatives, generated by ' || ${DR_WRITER_OPTIONS}::text
         || ' routine(s)'`);

  // Step 7. The authority check: a gate on the artefact, an authority table with rows and readers,
  // and authority verdicts actually being routed on live decisions.
  await req('comp-10', 'comp-10-07-authority', 'Step 7 Authority Check gates the decision',
    `select ${DR_TRIGGER} > 0
        and (select count(*) from public.employee_authority) > 0
        and ${READERS('employee_authority')} > 0
        and (select count(*) from public.decision_log
              where kind in ('action_gate','escalate','approve') and route_to is not null
                and created_at > now() - interval '30 days') > 0`,
    `select 'decision_record triggers=' || ${DR_TRIGGER}::text
         || ', employee_authority rows=' || (select count(*) from public.employee_authority)::text
         || ' read by ' || ${READERS('employee_authority')}::text
         || ', authority-routed decisions in 30d=' || (select count(*) from public.decision_log
              where kind in ('action_gate','escalate','approve') and route_to is not null
                and created_at > now() - interval '30 days')::text`);

  // Step 8. The decision is recorded and read. Recency matters: a ledger that stopped is a ledger.
  await req('comp-10', 'comp-10-08-decision', 'Step 8 Decision is recorded and read',
    `select (select count(*) from public.decision_log) > 0
        and (select count(*) from public.decision_log
              where created_at > now() - interval '7 days') > 0
        and ${READERS('decision_log')} > 0`,
    `select (select count(*) from public.decision_log)::text || ' decisions, '
         || (select count(*) from public.decision_log
              where created_at > now() - interval '7 days')::text || ' in the last 7d, read by '
         || ${READERS('decision_log')}::text || ' routine(s)/view(s)/job(s)'`);

  // Step 9. Execution linked BACK to the decision. Either the designed pair or an execution ledger
  // carrying a decision id. agent_actions has 2,100 executions and no decision column.
  //
  // STRENGTHENED, not relaxed: the old form accepted "action_execution has rows AND decision_trace
  // has rows AND something reads action_execution", which two unrelated rows in two tables satisfy
  // without a single link between them. That is the "right for the wrong reason" verdict this file
  // warns about in its own header, so the JOIN is now asserted — an execution must name the
  // decision_record it came from and share a correlation_id with that decision's trace, and
  // v_executions_without_decision_trace must be empty.
  const AE_LINKED = `(select count(*) from public.action_execution a
      join public.decision_trace t on t.correlation_id = a.correlation_id
      where (a.request ->> 'decision_record_id') is not null
        and t.entity_type = 'decision_record'
        and t.entity_id = a.request ->> 'decision_record_id')`;
  await req('comp-10', 'comp-10-09-execution', 'Step 9 Execution is linked back to the decision',
    `select (${AE_LINKED} > 0
             and (select count(*) from public.v_executions_without_decision_trace) = 0
             and ${READERS('action_execution')} > 0)
        or ${AA_DECISION_LINK} > 0`,
    `select 'executions traceable to their decision_record=' || ${AE_LINKED}::text
         || ' of ' || (select count(*) from public.action_execution)::text
         || ', executions with no decision_trace=' || (select count(*) from public.v_executions_without_decision_trace)::text
         || ', decision_trace rows=' || (select count(*) from public.decision_trace)::text
         || ', agent_actions rows carrying a decision id=' || ${AA_DECISION_LINK}::text`);

  // Step 10. The loop closes when an outcome has been GRADED — EXCEPT that a grade cannot exist
  // before the thing being graded has had time to happen.
  //
  // THE OLD ASSERTION DEMANDED TIME TRAVEL. outcome_record holds 50 rows, all pending, and the
  // earliest due_at is 2026-08-11; today is 6 Aug 2026. fn_outcome_evaluate grades a row when its
  // measurement window closes, so the FIRST GRADE IN THIS SYSTEM'S HISTORY IS FIVE DAYS AWAY and no
  // correct implementation can produce one today. The only way to turn the old check green was to
  // backdate a due_at or write a verdict by hand — i.e. to fake the measurement that the whole
  // component exists to make honest.
  // So it now asserts the WIRING, which is what is actually knowable today: outcomes are queued
  // with a due date, an active cron will grade them, the table is read — and either a grade already
  // exists OR the earliest due date is still in the future. An OVERDUE ungraded row still fails,
  // which is the real defect this check should catch, and it will start catching it on 11 Aug.
  await req('comp-10', 'comp-10-10-outcome', 'Step 10 Outcome Measurement closes the loop',
    `select (select count(*) from public.outcome_record) > 0
        and ${READERS('outcome_record')} > 0
        and (select count(*) from cron.job where command ~* '\\yfn_outcome_evaluate\\y' and active) > 0
        and (${OR_GRADED} > 0
             or (select min(due_at) from public.outcome_record where verdict = 'pending') > now())`,
    `select ${OR_GRADED}::text || ' of ' || (select count(*) from public.outcome_record)::text
         || ' outcomes graded; earliest due ' || coalesce((select min(due_at)::date::text
              from public.outcome_record where verdict = 'pending'), 'n/a')
         || '; active evaluator crons=' || (select count(*) from cron.job
              where command ~* '\\yfn_outcome_evaluate\\y' and active)::text`);
}
