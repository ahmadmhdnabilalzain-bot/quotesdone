// SPEC FILE #2 — the cross-OS contract (15 requirements, ids xos-01 .. xos-15).
//
// The eleven links of the cross-OS chain: an event is created, the bus carries it, the relevant
// OSes subscribe, each assesses impact, raises internal work, executes within its authority,
// returns the result, the Chief of Staff consolidates, the CEO re-prioritises, Knowledge captures
// the lesson and Intelligence updates the KPIs — plus the three rules that make the chain a
// contract rather than a diagram: no direct cross-OS calls, standard interfaces, full auditability.
//
// Every check asks the same three questions and never conflates them:
//   1. does the mechanism EXIST?   2. is it POPULATED / does it RUN?   3. does anything READ it?
//
// REPAIRED 6 Aug 2026 after adversarial review found 15 defects here, the largest of which was
// that question 3 was never actually being asked. See rdSql below.

// ── A LIVE READER ────────────────────────────────────────────────────────────────────────────
// The previous form of this helper matched `pg_get_functiondef(p.oid) ~* '\y<table>\y'`, which is
// a MENTIONS test, not a READS test: `insert into event_assessment` satisfies it exactly as well
// as `select from event_assessment`. Measured on production before the repair: xos-04 scored MET
// on '1 live reader' and that one reader was fn_event_dispatch, the function whose only reference
// to the table is the INSERT that populates it. Same shape on event_rollup (fn_event_consolidate),
// and on company_event, where 11 of the 14 reported readers only ever wrote.
//
// A reader is therefore now: an object that SELECTS the thing (from/join) and does NOT write it.
// The write test is by pattern rather than by a hand-maintained exclusion list, because the list
// was the part that rotted — the author of the old helper saw the hazard exactly once, wrote
// ['fn_event_dispatch'] into xos-07, and never generalised it. A routine that both writes and
// selects a table is excluded: its select is part of its own write path, and that is precisely the
// evidence this spec file says does not count. The error therefore runs toward MISSING, which is
// the only direction a reader test is allowed to be wrong in.
//
// A view still counts only if the view is itself SELECTED by a routine or a cron — a view nothing
// reads is not a reader.
const RD = (t) => `'(from|join)\\s+(public\\.)?"?${t}"?\\y'`;
const WR = (t) => `('(inser'||'t\\s+into|upd'||'ate|del'||'ete\\s+from)\\s+(public\\.)?"?${t}"?\\y')`;

const rdSql = (t, excl = []) => {
  const ex = ["'" + t + "'"].concat(excl.map(e => "'" + e + "'")).join(',');
  return `(
    (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p') and p.proname not in (${ex})
        and pg_get_functiondef(p.oid) ~* ${RD(t)}
        and pg_get_functiondef(p.oid) !~* ${WR(t)})
  + (select count(*) from cron.job j where j.command ~* ${RD(t)})
  + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* ${RD(t)}
      and (exists (select 1 from pg_proc p2 join pg_namespace n2 on n2.oid=p2.pronamespace
             where n2.nspname='public' and p2.prokind in ('f','p') and p2.proname not in (${ex})
               and pg_get_functiondef(p2.oid) ~* ('(from|join)\\s+(public\\.)?"?'||v.viewname||'"?\\y')
               and pg_get_functiondef(p2.oid) !~* ${WR(t)})
        or exists (select 1 from cron.job j2
                    where j2.command ~* ('(from|join)\\s+(public\\.)?"?'||v.viewname||'"?\\y')))))`;
};

// A count over a table that may not exist, and over COLUMNS that may not exist. The old cnt()
// guarded the table with to_regclass and then named the column raw inside query_to_xml, so
// cnt('event_rollup','os_count > 1') would turn xos-08 into an ERROR — an unmeasured requirement,
// not a MISSING verdict — the day event_rollup were rebuilt without that column. query_to_xml is
// volatile, so the CASE genuinely short-circuits instead of being constant-folded.
const guarded = (t, from, cols = []) => `(case when to_regclass('public.${t}') is null${cols.map(c =>
  `\n    or not exists (select 1 from information_schema.columns
        where table_schema='public' and table_name='${t}' and column_name='${c}')`).join('')}
  then 0 else (xpath('/row/c/text()', query_to_xml(
    $q$select count(*) c from ${from}$q$, false, true, '')))[1]::text::int end)`;
const cnt = (t, w = 'true', cols = []) => guarded(t, `public.${t} where ${w}`, cols);
const cntCol = (t, c) => cnt(t, `${c} is not null`, [c]);

// (event, subscriber) PAIRS that were never delivered. Two corrections over the original form.
//
// (1) PAIRS, not events. The old expression asked `not exists (select 1 from event_delivery d
// where d.event_id = e.id)`, so an event with five active subscribers that reached one of them
// counted as fully delivered — while the requirement says the bus delivers EVERY event it
// receives, to everyone listening. fn_event_dispatch itself works pair-wise; the check did not.
//
// (2) `p_age` is the delivery SLO, and it is the whole difference between a backlog and a queue.
// The dispatcher runs on a */15 cron, so an event emitted forty seconds before this check reads is
// IN FLIGHT, not lost. 60 minutes is four consecutive dispatch ticks; anything still waiting after
// four ticks IS a backlog. (This part was added by the implementing cluster and is kept: the
// measurement behind it — 13 undelivered at 07:20, 0 at 07:35, with the 07:15 tick capped at 50 —
// is a bus draining on schedule, and a check that fails on that is unsatisfiable in principle.)
//
// An event nobody subscribes to is not undelivered, it is unsubscribed, and counting those would
// make the dispatcher look broken for obeying its contract.
const UNDELIVERED = (p_age = null) => `(select count(*) from public.company_event e
   join public.event_subscription s on s.active and s.event_type = e.event_type
     and s.agent_key <> coalesce(e.actor,'')
   where ${p_age ? `e.occurred_at < now() - interval '${p_age}' and ` : ''}not exists (
     select 1 from public.event_delivery d where d.event_id = e.id and d.agent_key = s.agent_key))`;

// Trigger functions that emit onto the bus. Kept out of the reader test by construction: an
// emitter matches `insert into company_event` and therefore fails RD/WR, which is what makes
// xos-01's third leg independent of its second instead of implied by it.
const EMITTERS = `(select count(*) from pg_trigger tg join pg_class c on c.oid=tg.tgrelid
     join pg_proc p on p.oid=tg.tgfoid
    where not tg.tgisinternal and p.prokind in ('f','p')
      and pg_get_functiondef(p.oid) ~* ('inser'||'t\\s+into\\s+(public\\.)?company_event'))`;

export default async function ({ req }) {

  // LINK 1 — an event is created. Exists: company_event + trigger emitters. Runs: rows this week.
  // Read: routines that SELECT company_event and do not write it.
  await req('xos', 'xos-01-event-created', 'Link 1 business events are published onto a bus',
    `select (select count(*) from public.company_event where occurred_at > now() - interval '7 days') > 0
        and ${EMITTERS} > 0
        and ${rdSql('company_event')} > 0`,
    `select (select count(*) from public.company_event where occurred_at > now() - interval '7 days')::text
        || ' event(s)/7d, ' || ${EMITTERS}::text || ' emitter trigger(s), '
        || ${rdSql('company_event')}::text || ' live reader(s), writers excluded'`);

  // LINK 2 — the bus runs AND delivers everything it receives, to everyone listening. A dispatcher
  // on an active cron that leaves a backlog behind its SLO is running, not delivering.
  await req('xos', 'xos-02-event-bus', 'Link 2 the bus runs and delivers every event it receives',
    `select (select count(*) from cron.job where active and command ~* '\\yfn_event_dispatch\\y') > 0
        and (select count(*) from cron.job_run_details d join cron.job j on j.jobid = d.jobid
              where j.command ~* '\\yfn_event_dispatch\\y' and d.status = 'succeeded'
                and d.end_time > now() - interval '2 days') > 0
        and ${UNDELIVERED('60 minutes')} = 0`,
    `select ${UNDELIVERED('60 minutes')}::text || ' (event,subscriber) pair(s) undelivered past the '
        || '60-minute SLO (' || ${UNDELIVERED()}::text || ' counting in-flight) of '
        || (select count(*) from public.event_delivery)::text || ' deliveries ever'`);

  // LINK 3 — the subscribers ARE Operating Systems: every subscription resolves to one, every
  // active OS holds at least one, and the DISPATCHER routes on that resolution rather than on a
  // bare agent_key that happens to sit in a department. Leg 3 is pinned to fn_event_dispatch by
  // name (xos-06 already did this and this check did not: any public routine naming both tables
  // used to satisfy it), and all three legs are now reported in the evidence — the old evidence
  // printed legs 1 and 2 only, so a leg-3 regression would have printed '0 ... 0' beside MISSING.
  const SUB_NO_OS = `(select count(*) from public.event_subscription s where s.active
              and not exists (select 1 from public.org_agents a
                                join public.os_department od on od.dept_key = a.department
                               where a.agent_key = s.agent_key))`;
  const OS_NO_SUB = `(select count(*) from public.operating_system o where o.active
              and not exists (select 1 from public.event_subscription s
                                join public.org_agents a on a.agent_key = s.agent_key
                                join public.os_department od on od.dept_key = a.department
                               where s.active and od.os_key = o.os_key))`;
  const DISPATCH_RESOLVES = `(select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname='public' and p.proname='fn_event_dispatch'
                and pg_get_functiondef(p.oid) ~* '\\yevent_subscription\\y'
                and pg_get_functiondef(p.oid) ~* '\\yos_department\\y')`;
  await req('xos', 'xos-03-oses-subscribe', 'Link 3 subscriptions resolve to Operating Systems',
    `select ${SUB_NO_OS} = 0 and ${OS_NO_SUB} = 0 and ${DISPATCH_RESOLVES} > 0`,
    `select ${SUB_NO_OS}::text || ' sub(s) resolve to no OS; ' || ${OS_NO_SUB}::text
        || ' active OS with none; dispatcher resolves OS from the department: '
        || (${DISPATCH_RESOLVES} > 0)::text`);

  // LINK 4 — impact is assessed BEFORE acting.
  //
  // This check scored MET on '78 assessment(s), 1 live reader(s)' and the one reader was
  // fn_event_dispatch, whose only reference to event_assessment is the INSERT. Three repairs:
  // the reader test now excludes writers by pattern (see rdSql); the assessment must COVER the
  // work, not merely exist somewhere (no delivery in the window may be acted on unassessed); and
  // 'BEFORE acting' is measured rather than assumed — no assessment may post-date the task raised
  // off the same event for the same OS.
  const ASSESS_UNCOVERED = guarded('event_assessment',
    `public.event_delivery d where d.delivered_at > now() - interval '7 days' and d.os_key is not null
        and not exists (select 1 from public.event_assessment a
                         where a.event_id = d.event_id and a.os_key = d.os_key)`, ['event_id', 'os_key']);
  const ASSESS_LATE = guarded('event_assessment',
    `public.event_delivery d
        join public.event_assessment a on a.event_id = d.event_id and a.os_key = d.os_key
        join public.org_tasks t on t.id = d.task_id
       where a.assessed_at > t.created_at`, ['event_id', 'os_key', 'assessed_at']);
  await req('xos', 'xos-04-assess-impact', 'Link 4 each OS assesses impact before acting',
    `select (select count(*) from information_schema.columns
              where table_schema='public' and table_name='event_assessment'
                and column_name in ('event_id','impact')) = 2
        and ${cnt('event_assessment', `assessed_at > now() - interval '7 days'`, ['assessed_at'])} > 0
        and ${ASSESS_UNCOVERED} = 0
        and ${ASSESS_LATE} = 0
        and ${rdSql('event_assessment')} > 0`,
    `select ${cnt('event_assessment')}::text || ' assessment(s) ('
        || ${cnt('event_assessment', `assessed_at > now() - interval '7 days'`, ['assessed_at'])}::text
        || ' in 7d), ' || ${ASSESS_UNCOVERED}::text || ' delivery(ies)/7d acted on unassessed, '
        || ${ASSESS_LATE}::text || ' assessed AFTER the task, '
        || ${rdSql('event_assessment')}::text || ' reader(s) that are not the writer'`);

  // LINK 5 — the event becomes internal work.
  //
  // `task_id is null = 0` was the wrong assertion and could never be satisfied. The dispatcher
  // deliberately writes a delivery with NO task when the subscription names an employee who does
  // not exist — that unroutable row, with its reason, IS the defect report. What link 5 requires is
  // that no delivery is silent: every one either carries a task or says why it does not.
  //
  // Leg 3 used to be rdSql('org_tasks'), measured at 27 routines: a constant, and about the wrong
  // object — global readership of the company task table says nothing about whether event-derived
  // work reaches anyone. It is now readership of the delivery ledger itself, which is the object
  // this link creates, with the dispatcher excluded as its writer. That number was genuinely 0
  // before v_event_backbone was consumed, so it can fail. Leg 1 is bounded to 7 days: one delivery
  // with a task from July is not evidence that the bus raises work now.
  await req('xos', 'xos-05-internal-tasks', 'Link 5 each OS creates internal tasks from the event',
    `select (select count(*) from public.event_delivery
              where task_id is not null and delivered_at > now() - interval '7 days') > 0
        and (select count(*) from public.event_delivery
              where task_id is null and unroutable_reason is null
                and delivered_at > now() - interval '24 hours') = 0
        and ${rdSql('event_delivery')} > 0`,
    `select (select count(*) from public.event_delivery where task_id is not null)::text || ' of '
        || (select count(*) from public.event_delivery)::text || ' deliveries carry a task ('
        || (select count(*) from public.event_delivery
              where task_id is not null and delivered_at > now() - interval '7 days')::text
        || ' in 7d), ' || (select count(*) from public.event_delivery
             where task_id is null and unroutable_reason is null
               and delivered_at > now() - interval '24 hours')::text
        || ' silent in 24h (no task, no reason), ' || ${rdSql('event_delivery')}::text
        || ' reader(s) of the delivery ledger, writers excluded'`);

  // LINK 6 — execution stays inside the authority model: the dispatcher resolves the tier from
  // fn_dept_authority instead of granting itself autonomy, nothing non-autonomous slipped through
  // unflagged, and event-derived work has actually completed RECENTLY (the old leg was an
  // unbounded `> 0`: one task closed in July would have carried this forever).
  //
  // The tier leg is a guard over a population that is currently violation-free — all 340
  // event-derived tasks resolve to 'autonomous' — so the population itself is now asserted
  // non-empty. A guard that passes because there is nothing to guard is not a measurement.
  const EVT_TASKS = (w) => `(select count(*) from public.org_tasks t
              join public.event_delivery d on d.task_id = t.id where ${w})`;
  await req('xos', 'xos-06-execute-authority', 'Link 6 each OS executes within its authority',
    `select (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname='public' and p.proname='fn_event_dispatch'
                and pg_get_functiondef(p.oid) ~* '\\yfn_dept_authority\\y') > 0
        and ${EVT_TASKS(`t.tier is not null`)} > 0
        and ${EVT_TASKS(`t.tier is distinct from 'autonomous' and t.needs_founder = false`)} = 0
        and ${EVT_TASKS(`t.status in ('done','closed') and t.updated_at > now() - interval '30 days'`)} > 0`,
    `select ${EVT_TASKS(`t.status in ('done','closed') and t.updated_at > now() - interval '30 days'`)}::text
        || ' event-derived task(s) closed in 30d of ' || ${EVT_TASKS(`t.tier is not null`)}::text
        || ' carrying a tier, '
        || ${EVT_TASKS(`t.tier is distinct from 'autonomous' and t.needs_founder = false`)}::text
        || ' executed above tier'`);

  // LINK 7 — the result comes back to the event that caused the work.
  //
  // The old form summed six populated surfaces, summed four reader counts, and compared each sum
  // to zero INDEPENDENTLY: one decision_trace row plus any reader of event_delivery scored MET
  // while decision_trace itself was read by nothing. Populated-and-unread is the entire subject of
  // this spec file, and that shape cannot see it. Each surface is now paired with its own reader,
  // and a surface only counts if the thing that carries the result is the thing that is read.
  const S_TASK = `(select count(*) from public.event_delivery d join public.org_tasks t on t.id = d.task_id
        where t.result is not null and t.updated_at > now() - interval '30 days')`;
  const S_DTRACE = `(select count(*) from public.decision_trace where causation_event_id is not null)`;
  const S_WFRUN = `(select count(*) from public.workflow_run where trigger_event_id is not null)`;
  const SURFACES = `((${S_TASK} > 0 and ${rdSql('org_tasks')} > 0)
        or (${cntCol('event_delivery', 'result')} > 0 and ${rdSql('event_delivery')} > 0)
        or (${S_DTRACE} > 0 and ${rdSql('decision_trace')} > 0)
        or (${S_WFRUN} > 0 and ${rdSql('workflow_run')} > 0)
        or (${cnt('event_rollup', 'outcome is not null', ['outcome'])} > 0 and ${rdSql('event_rollup')} > 0))`;
  await req('xos', 'xos-07-results-returned', 'Link 7 results returned to the originating event',
    `select ${SURFACES}`,
    `select 'task.result ' || ${S_TASK}::text || '/' || ${rdSql('org_tasks')}::text
        || ', delivery.result ' || ${cntCol('event_delivery', 'result')}::text || '/' || ${rdSql('event_delivery')}::text
        || ', decision_trace ' || ${S_DTRACE}::text || '/' || ${rdSql('decision_trace')}::text
        || ', workflow_run ' || ${S_WFRUN}::text || '/' || ${rdSql('workflow_run')}::text
        || ', rollup ' || ${cnt('event_rollup', 'outcome is not null', ['outcome'])}::text || '/'
        || ${rdSql('event_rollup')}::text || ' (populated/readers, paired)'`);

  // LINK 8 — the Chief of Staff consolidates ACROSS OSes. One rollup row per correlation touching
  // a single OS is a receipt, not a consolidation, so os_count > 1 is part of the measure.
  //
  // Three repairs: the os_count column is guarded (the old cnt named it raw inside query_to_xml,
  // so a rebuild of this nascent table without that column turned the check into an ERROR — an
  // unmeasured requirement, not a MISSING verdict); consolidation must be CURRENT, not historical;
  // and every cross-OS episode must be consolidated, not just one of them. The reader leg excludes
  // the writer, which is what it was previously counting: fn_event_consolidate was the only object
  // in the database that mentioned event_rollup, and it only inserts.
  const ROLLUP_MISSING = guarded('event_rollup',
    `(select e.correlation_id from public.company_event e
        join public.event_delivery d on d.event_id = e.id
       where e.correlation_id is not null
       group by e.correlation_id having count(distinct d.os_key) > 1) z
      where not exists (select 1 from public.event_rollup r where r.correlation_id = z.correlation_id)`,
    ['correlation_id']);
  await req('xos', 'xos-08-cos-consolidates', 'Link 8 Chief of Staff consolidates outcomes across OSes',
    `select ${cnt('event_rollup')} > 0
        and ${cnt('event_rollup', 'os_count > 1', ['os_count'])} > 0
        and ${cnt('event_rollup', `consolidated_at > now() - interval '48 hours'`, ['consolidated_at'])} > 0
        and ${ROLLUP_MISSING} = 0
        and ${rdSql('event_rollup')} > 0`,
    `select ${cnt('event_rollup')}::text || ' rollup(s), '
        || ${cnt('event_rollup', 'os_count > 1', ['os_count'])}::text || ' spanning >1 OS, '
        || ${cnt('event_rollup', `consolidated_at > now() - interval '48 hours'`, ['consolidated_at'])}::text
        || ' consolidated in 48h, ' || ${ROLLUP_MISSING}::text
        || ' cross-OS episode(s) never consolidated, ' || ${rdSql('event_rollup')}::text
        || ' reader(s) that are not the writer'`);

  // LINK 9 — the CEO re-prioritises OFF EVENT OUTCOMES, and the new priority travels as an event
  // that someone subscribes to.
  //
  // The old check asked only whether an event whose type matched the unanchored substring
  // 'priorit' existed, was subscribed to and was delivered — no leg touched an outcome, which is
  // the actual content of link 9. A priority event raised for any reason at all satisfied it. Now
  // the type is exact, and EVERY re-prioritisation must resolve to the outcome it was made off:
  // a consolidated episode that crossed an OS boundary and in which work actually closed, plus a
  // causation_id that resolves to the event that started the chain. Coverage, not existence — one
  // linked row would otherwise carry an unbounded number of unlinked ones.
  const PRIO = (w) => `(select count(*) from public.company_event e where e.event_type = 'priority.updated'${w})`;
  const PRIO_NO_OUTCOME = guarded('event_rollup',
    `public.company_event e where e.event_type = 'priority.updated'
       and not exists (select 1 from public.event_rollup r where r.correlation_id = e.correlation_id
                        and r.os_count > 1 and r.tasks_closed > 0)`, ['correlation_id', 'os_count', 'tasks_closed']);
  await req('xos', 'xos-09-ceo-priorities', 'Link 9 CEO updates company priorities off event outcomes',
    `select ${PRIO('')} > 0
        and ${PRIO_NO_OUTCOME} = 0
        and ${PRIO(` and not exists (select 1 from public.company_event c where c.id = e.causation_id)`)} = 0
        and (select count(*) from public.event_subscription where active and event_type = 'priority.updated') > 0
        and ${PRIO(` and not exists (select 1 from public.event_delivery d where d.event_id = e.id)`)} = 0`,
    `select ${PRIO('')}::text || ' priority.updated event(s), ' || ${PRIO_NO_OUTCOME}::text
        || ' not traceable to a cross-OS episode with closed work, '
        || ${PRIO(` and not exists (select 1 from public.company_event c where c.id = e.causation_id)`)}::text
        || ' with no resolvable cause, '
        || ${PRIO(` and not exists (select 1 from public.event_delivery d where d.event_id = e.id)`)}::text
        || ' undelivered, over ' || (select count(*) from public.event_subscription
              where active and event_type = 'priority.updated')::text || ' active subscription(s)'`);

  // LINK 10 — Knowledge captures the lesson from an EVENT outcome.
  //
  // Leg 2 was rdSql('institutional_memory'), measured at 11 and stated in this file's own comment
  // to be unfailable — a constant-true term. institutional_memory has four insert-only writers
  // (fn_task_lesson, fn_outcome_evaluate, fn_dispute_open, fn_ap_bill_dupe_guard) which the
  // repaired rdSql no longer counts, and the term is replaced as the load-bearing leg by the
  // regression guard the worklist asked for: no event-derived task may close, once the review
  // chain exists, without a review behind it. Vacuously true today, and it fails the moment a
  // closed event-derived task has no review — which is the way this link actually breaks.
  const IM_FROM_EVENT = `(select count(*) from public.institutional_memory m
              where exists (select 1 from public.event_delivery d
                             where d.task_id is not null and d.task_id::text = m.subject_id))`;
  const UNREVIEWED = `(select count(*) from public.org_tasks t
              join public.event_delivery d on d.task_id = t.id
             where t.status in ('done','closed')
               and t.updated_at > (select min(created_at) from public.institutional_memory
                                    where subject_type = 'org_task')
               and not exists (select 1 from public.review_chain rc
                                where rc.subject_type = 'org_task' and rc.subject_id = t.id::text))`;
  await req('xos', 'xos-10-knowledge-lessons', 'Link 10 Knowledge OS captures lessons from event outcomes',
    `select ${IM_FROM_EVENT} > 0 and ${UNREVIEWED} = 0 and ${rdSql('institutional_memory')} > 0`,
    `select ${IM_FROM_EVENT}::text || ' of '
        || (select count(*) from public.institutional_memory)::text
        || ' lesson(s) trace to a dispatched event, ' || ${UNREVIEWED}::text
        || ' closed event-derived task(s) with no review since the chain went live, '
        || ${rdSql('institutional_memory')}::text || ' reader(s) that are not writers'`);

  // LINK 11 — Intelligence updates KPIs and forecasts off events.
  //
  // The old check called any routine whose body contained the string 'kpi.missed' an emitter
  // without requiring it to emit anything, and accepted as its 'caller that actually runs' any
  // other function that merely NAMED it — a chain of dead functions satisfied that. The emitter
  // must now actually write company_event, and its caller must be an ACTIVE cron job naming it
  // directly, with no failed run behind it.
  //
  // A SUCCEEDED run is required FROM 2026-08-11, not today. Measured 6 Aug: cron emit_metric_alerts
  // ('0 3 * * 1', active) has zero rows in cron.job_run_details because the job was created after
  // its own last Monday slot; its first scheduled execution is 2026-08-10 03:00. Demanding a
  // succeeded run today is the manufactured-MISSING error — no implementation could pass it this
  // week — and demanding nothing leaves an emitter whose schedule has never executed scoring MET
  // on 18 events produced by hand. The dated leg is the honest form of both: it costs nothing
  // today and it fails on 11 Aug if that Monday run does not happen. The 18 events currently in
  // the 14-day window were emitted manually; that is stated here so the MET is not read as proof
  // the schedule works.
  const EMITTER = (extra = '') => `(select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname='public' and p.prokind in ('f','p')
                and pg_get_functiondef(p.oid) ~* 'kpi\\.missed'
                and pg_get_functiondef(p.oid) ~* ('inser'||'t\\s+into\\s+(public\\.)?company_event')
                and exists (select 1 from cron.job j
                             where j.active and j.command ~* ('\\y'||p.proname||'\\y'))${extra})`;
  const EMITTER_FAILED = `(select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              join cron.job j on j.active and j.command ~* ('\\y'||p.proname||'\\y')
              join cron.job_run_details r on r.jobid = j.jobid
             where ns.nspname='public' and p.prokind in ('f','p')
               and pg_get_functiondef(p.oid) ~* 'kpi\\.missed'
               and pg_get_functiondef(p.oid) ~* ('inser'||'t\\s+into\\s+(public\\.)?company_event')
               and r.status is distinct from 'succeeded')`;
  const EMITTER_RAN = EMITTER(`
                and exists (select 1 from cron.job j2 join cron.job_run_details r2 on r2.jobid = j2.jobid
                             where j2.active and j2.command ~* ('\\y'||p.proname||'\\y')
                               and r2.status = 'succeeded')`);
  await req('xos', 'xos-11-intelligence-kpis', 'Link 11 Intelligence OS updates KPIs off events',
    `select ${EMITTER()} > 0
        and ${EMITTER_FAILED} = 0
        and (${EMITTER_RAN} > 0 or now() < timestamptz '2026-08-11 00:00+00')
        and (select count(*) from public.company_event
              where event_type = 'kpi.missed' and occurred_at > now() - interval '14 days') > 0
        and (select count(*) from public.event_delivery d join public.company_event e on e.id = d.event_id
              where d.event_type = 'kpi.missed' and e.occurred_at > now() - interval '14 days') > 0`,
    `select ${EMITTER()}::text || ' kpi.missed emitter(s) on an active cron ('
        || ${EMITTER_RAN}::text || ' with a succeeded run, required from 2026-08-11; '
        || ${EMITTER_FAILED}::text || ' failed run(s)); ' || (select count(*) from public.company_event
              where event_type='kpi.missed' and occurred_at > now() - interval '14 days')::text
        || ' event(s) in 14d, ' || (select count(*) from public.event_delivery d
              join public.company_event e on e.id = d.event_id
             where d.event_type='kpi.missed' and e.occurred_at > now() - interval '14 days')::text
        || ' delivered'`);

  // HARD RULE — no OS reaches into another for business logic. Met either by nothing writing
  // another OS's queue outside the bus, or by a guard on org_tasks that REFUSES the cross-OS write.
  //
  // '\yraise\y' matched `raise notice`, `raise log` and the word inside a comment, so a trigger
  // that logged the violation and then permitted it scored as a guard; it is now
  // `raise\s+exception`. The trigger must also be enabled — a disabled guard is a comment. And the
  // evidence now applies the SAME predicate as the verdict: it previously dropped the raise term
  // entirely, so a trigger matching os_department but not raising could print '1 cross-OS guard(s)'
  // beside a MISSING verdict.
  const UNBUSED_WRITERS = `(select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_event_dispatch'
                and pg_get_functiondef(p.oid) ~* ('inser'||'t\\s+into\\s+(public\\.)?org_tasks'))`;
  const GUARDS = `(select count(*) from pg_trigger tg join pg_class c on c.oid = tg.tgrelid
              join pg_proc p on p.oid = tg.tgfoid
             where c.relname='org_tasks' and not tg.tgisinternal and tg.tgenabled <> 'D'
               and p.prokind in ('f','p')
               and pg_get_functiondef(p.oid) ~* '\\yos_department\\y'
               and pg_get_functiondef(p.oid) ~* 'raise\\s+exception')`;
  await req('xos', 'xos-12-no-direct-cross-os', 'Hard rule no OS calls another OS directly',
    `select ${UNBUSED_WRITERS} = 0 or ${GUARDS} > 0`,
    `select ${UNBUSED_WRITERS}::text || ' routine(s) write org_tasks outside the bus; '
        || ${GUARDS}::text || ' enabled trigger(s) on org_tasks that resolve os_department and '
        || 'raise an exception'`);

  // STANDARD INTERFACES — os_interface is the declared contract. It is only an interface if the bus
  // carries what it declares AND something at runtime consults it.
  //
  // The implementing cluster replaced 'every declared interface must have fired' with 'unless it is
  // marked planned, with a reason'. That was the right correction — seven of the declarations
  // cannot fire because production has zero customers, and the only ways to turn the old assertion
  // green were to delete the interface or to fake an event — but a flag is not traffic, and 21 of
  // 32 declarations now sit behind it. Two legs bound what the flag may excuse.
  //
  // (a) planned may not excuse an interface whose own declared KIND is already on the bus. Keyed on
  //     `kind`, not on `event_type`, deliberately: one row declares kind='campaign.published' with
  //     event_type='content.published' — the name Commercial publishes under until a campaign
  //     object exists — and keying on event_type would call that promise kept when the thing that
  //     was promised has never arrived. The applied SQL derives planned=false from exactly this
  //     rule on every run, so the check now asserts the same invariant the writer maintains.
  // (b) planned excuses TRAFFIC, never WIRING: an interface not marked planned must be structurally
  //     complete — an output needs a producer somewhere in the database, an input needs an active
  //     subscription from an agent whose department maps to that OS. That is the standardisation
  //     the requirement is actually about, and no flag can excuse it.
  const IFACE = (w) => `(select count(*) from public.os_interface i where i.active and i.event_type is not null and ${w})`;
  const IF_LIVE_NEVER = IFACE(`not coalesce(i.planned,false)
              and not exists (select 1 from public.company_event e where e.event_type = i.event_type)`);
  const IF_NO_REASON = IFACE(`coalesce(i.planned,false) and coalesce(i.planned_reason,'') = ''`);
  const IF_PLANNED_LIVE = IFACE(`coalesce(i.planned,false)
              and exists (select 1 from public.company_event e where e.event_type = i.kind)`);
  const IF_UNWIRED = IFACE(`not coalesce(i.planned,false) and (
                (i.direction = 'output' and not (
                    exists (select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                             where ns.nspname='public' and p.prokind in ('f','p')
                               and pg_get_functiondef(p.oid) like '%'''||i.event_type||'''%')
                 or exists (select 1 from cron.job j where j.command like '%'||i.event_type||'%')))
             or (i.direction = 'input' and not exists (
                    select 1 from public.event_subscription s
                      join public.org_agents a on a.agent_key = s.agent_key
                      join public.os_department od on od.dept_key = a.department
                     where s.active and s.event_type = i.event_type and od.os_key = i.os_key))) `);
  await req('xos', 'xos-13-standard-interfaces', 'OSes expose standardized interfaces the bus carries',
    `select ${IFACE('true')} > 0
        and ${IF_LIVE_NEVER} = 0
        and ${IF_NO_REASON} = 0
        and ${IF_PLANNED_LIVE} = 0
        and ${IF_UNWIRED} = 0
        and ${rdSql('os_interface')} > 0`,
    `select ${IF_LIVE_NEVER}::text || ' live interface(s) never fired, ' || ${IF_UNWIRED}::text
        || ' unwired (output with no producer / input with no subscriber), '
        || ${IFACE(`coalesce(i.planned,false)`)}::text || ' declared planned ('
        || ${IF_NO_REASON}::text || ' with no reason, ' || ${IF_PLANNED_LIVE}::text
        || ' whose declared kind already flows), of ' || ${IFACE('true')}::text || ' declared; '
        || ${rdSql('os_interface')}::text || ' live reader(s)'`);

  // AUDITABILITY — correlation ties one business episode together, causation ties an effect to its
  // cause.
  //
  // The reader leg used to grep the bare string 'correlation_id', which is a column on six objects,
  // so a routine reading action_execution.correlation_id proved 'the company_event audit chain is
  // read'. A reader must now SELECT company_event and reference the column. The correlation leg is
  // coverage rather than existence — a chain with one correlated event in it is not auditable — and
  // the causation MECHANISM is asserted alongside the count, because the count is structural: an
  // event only carries a cause when it was emitted inside another event's handling, so it measures
  // how much second-generation traffic exists, not whether the chain works.
  const CORR_READERS = `((select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
               where ns.nspname='public' and p.prokind in ('f','p')
                 and pg_get_functiondef(p.oid) ~* ${RD('company_event')}
                 and pg_get_functiondef(p.oid) ~* '\\ycorrelation_id\\y')
           + (select count(*) from pg_views v where v.schemaname='public'
                and v.definition ~* ${RD('company_event')} and v.definition ~* '\\ycorrelation_id\\y'
                and (exists (select 1 from pg_proc p2 join pg_namespace n2 on n2.oid = p2.pronamespace
                              where n2.nspname='public' and p2.prokind in ('f','p')
                                and pg_get_functiondef(p2.oid) ~* ('(from|join)\\s+(public\\.)?"?'||v.viewname||'"?\\y'))
                  or exists (select 1 from cron.job j2
                              where j2.command ~* ('(from|join)\\s+(public\\.)?"?'||v.viewname||'"?\\y')))))`;
  const CAUS_DEFAULT = `(select count(*) from information_schema.columns
             where table_schema='public' and table_name='company_event' and column_name='causation_id'
               and column_default ~ 'app\\.causation_event_id')`;
  const CAUS_SETTER = `(select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
             where ns.nspname='public' and p.prokind in ('f','p')
               and pg_get_functiondef(p.oid) ~* 'set_config\\(''app\\.causation_event_id''')`;
  await req('xos', 'xos-14-event-auditability', 'Event chain is auditable (correlation and causation)',
    `select (select count(*) from public.company_event where correlation_id is null) = 0
        and (select count(*) from public.company_event) > 0
        and ${CAUS_DEFAULT} > 0 and ${CAUS_SETTER} > 0
        and (select count(*) from public.company_event where causation_id is not null) > 0
        and ${CORR_READERS} > 0`,
    `select (select count(*) from public.company_event where correlation_id is not null)::text || '/'
        || (select count(*) from public.company_event)::text || ' correlated, '
        || (select count(*) from public.company_event where causation_id is not null)::text
        || ' caused (default wired: ' || (${CAUS_DEFAULT} > 0)::text || ', ' || ${CAUS_SETTER}::text
        || ' routine(s) set the cause), ' || ${CORR_READERS}::text
        || ' reader(s) that select company_event AND name correlation_id'`);

  // BUS OBSERVABILITY — v_event_backbone is the one surface that says which event types are live,
  // undelivered or never fired. It exists and is correct; the requirement is that somebody looks.
  // 'Somebody' is now required to be a routine on an ACTIVE cron, not merely a routine: under this
  // file's own doctrine a function nobody calls is the same as a table nobody reads.
  const BACKBONE_CRON = `(select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname='public' and p.prokind in ('f','p')
                and pg_get_functiondef(p.oid) ~* ${RD('v_event_backbone')}
                and exists (select 1 from cron.job j where j.active and j.command ~* ('\\y'||p.proname||'\\y')))`;
  await req('xos', 'xos-15-bus-observability', 'Bus health is observable: the backbone view is read',
    `select (select count(*) from pg_views where schemaname='public' and viewname='v_event_backbone') > 0
        and ${rdSql('v_event_backbone')} > 0
        and ${BACKBONE_CRON} > 0`,
    `select 'v_event_backbone: ' || ${rdSql('v_event_backbone')}::text || ' live reader(s), '
        || ${BACKBONE_CRON}::text || ' of them on an active cron, over '
        || (select count(*) from public.event_subscription where active)::text || ' active subscription(s)'`);
}
