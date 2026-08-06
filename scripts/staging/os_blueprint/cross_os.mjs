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

// COUNTED BY NAME, NOT BY ROW. pg_proc holds one row per OVERLOAD, so a helper with two signatures
// was counted twice in every reader total it appeared in and a table read by one function could
// report two readers. count(distinct p.proname) is the object being asked about.
//
// `col` NARROWS A READER TO THE COLUMN THAT CARRIES THE THING. A table-level reader test proves
// only that somebody selects the table: 13 routines select org_tasks and 9 of them never name
// `result`, so pairing 'the result came back' with 'org_tasks is read' pairs a fact with an
// unrelated one. Where a check is about a specific column, the reader must name that column.
const rdSql = (t, excl = [], col = null) => {
  const ex = ["'" + t + "'"].concat(excl.map(e => "'" + e + "'")).join(',');
  const pc = col ? `\n        and pg_get_functiondef(p.oid) ~* '\\y${col}\\y'` : '';
  const p2c = col ? `\n               and pg_get_functiondef(p2.oid) ~* '\\y${col}\\y'` : '';
  const vc = col ? ` and v.definition ~* '\\y${col}\\y'` : '';
  const jc = col ? ` and j.command ~* '\\y${col}\\y'` : '';
  return `(
    (select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p') and p.proname not in (${ex})
        and pg_get_functiondef(p.oid) ~* ${RD(t)}
        and pg_get_functiondef(p.oid) !~* ${WR(t)}${pc})
  + (select count(*) from cron.job j where j.command ~* ${RD(t)}${jc})
  + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* ${RD(t)}${vc}
      and (exists (select 1 from pg_proc p2 join pg_namespace n2 on n2.oid=p2.pronamespace
             where n2.nspname='public' and p2.prokind in ('f','p') and p2.proname not in (${ex})
               and pg_get_functiondef(p2.oid) ~* ('(from|join)\\s+(public\\.)?"?'||v.viewname||'"?\\y')
               and pg_get_functiondef(p2.oid) !~* ${WR(t)}${p2c})
        or exists (select 1 from cron.job j2
                    where j2.command ~* ('(from|join)\\s+(public\\.)?"?'||v.viewname||'"?\\y')))))`;
};

// A READER THAT HAS ACTUALLY RUN. cron.job.active is a boolean a hand flips; only
// cron.job_run_details makes a schedule a fact. Used wherever a check's whole claim is 'somebody
// looks at this', because a job that has never fired looks at nothing.
const rdCronOk = (t, col = null) => `(select count(distinct p.proname)
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname='public' and p.prokind in ('f','p')
       and pg_get_functiondef(p.oid) ~* ${RD(t)}
       and pg_get_functiondef(p.oid) !~* ${WR(t)}${col ? `\n       and pg_get_functiondef(p.oid) ~* '\\y${col}\\y'` : ''}
       and exists (select 1 from cron.job j join cron.job_run_details r on r.jobid = j.jobid
                    where j.active and j.command ~* ('\\y'||p.proname||'\\y') and r.status = 'succeeded'))`;

// THE POSITIVE FORM OF guarded()'s COLUMN GUARD. guarded() returns 0 when a named column is
// missing, which is the safe direction for a `> 0` leg and the WRONG one for a `= 0` coverage leg:
// dropping the column turns 'no row violates this' into an unconditional pass. Every check that
// guards a column inside a `= 0` leg now also asserts that column exists, so the schema change
// fails the requirement instead of silently satisfying it.
const hasCols = (t, cols) => `(select count(*) from information_schema.columns
      where table_schema='public' and table_name='${t}'
        and column_name in (${cols.map(c => `'${c}'`).join(',')}))`;

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
  //
  // The evidence used to print the undelivered counts ONLY, so a dropped cron or a failing
  // dispatcher would have printed '0 pair(s) undelivered ... of 522 deliveries ever' — healthy
  // numbers — beside a MISSING verdict. That is the exact fault this file states it repaired in
  // xos-03 and left standing here. Every leg of the verdict is now in the evidence.
  const DISPATCH_CRON = `(select count(*) from cron.job where active and command ~* '\\yfn_event_dispatch\\y')`;
  const DISPATCH_RAN = `(select count(*) from cron.job_run_details d join cron.job j on j.jobid = d.jobid
              where j.command ~* '\\yfn_event_dispatch\\y' and d.status = 'succeeded'
                and d.end_time > now() - interval '2 days')`;
  await req('xos', 'xos-02-event-bus', 'Link 2 the bus runs and delivers every event it receives',
    `select ${DISPATCH_CRON} > 0 and ${DISPATCH_RAN} > 0 and ${UNDELIVERED('60 minutes')} = 0`,
    `select ${DISPATCH_CRON}::text || ' active dispatcher cron(s), ' || ${DISPATCH_RAN}::text
        || ' succeeded run(s) in 2d; ' || ${UNDELIVERED('60 minutes')}::text
        || ' (event,subscriber) pair(s) undelivered past the '
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
  // Leg 1 asserts EVERY column the two coverage legs guard on, not just event_id and impact.
  // ASSESS_UNCOVERED and ASSESS_LATE are `= 0` legs built on guarded(), which returns 0 — a PASS —
  // when a guarded column is missing; os_key and assessed_at were guarded there and asserted
  // nowhere, so renaming either one silently reduced this check to population plus one reader.
  await req('xos', 'xos-04-assess-impact', 'Link 4 each OS assesses impact before acting',
    `select ${hasCols('event_assessment', ['event_id', 'impact', 'os_key', 'assessed_at'])} = 4
        and ${cnt('event_assessment', `assessed_at > now() - interval '7 days'`, ['assessed_at'])} > 0
        and ${ASSESS_UNCOVERED} = 0
        and ${ASSESS_LATE} = 0
        and ${rdSql('event_assessment')} > 0`,
    `select ${hasCols('event_assessment', ['event_id', 'impact', 'os_key', 'assessed_at'])}::text
        || '/4 required column(s), ' || ${cnt('event_assessment')}::text || ' assessment(s) ('
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
  // Two further repairs. (a) `needs_founder = false` made the tier leg satisfiable by a single
  // boolean write: any task executed above its tier was excused by flipping the flag, and nothing
  // asserted a founder ever saw it. The excuse is now a RECORD — a review_chain row for that task —
  // so the escape hatch costs an approval instead of an UPDATE. (b) the check had no reader leg at
  // all, in a file whose subject is populated-and-unread assets: tier was written on 340 tasks and
  // nothing here asked whether the authority decision is ever read back. Both legs are non-empty
  // populations today (340 tiered tasks, 2 readers that name tier), so neither is vacuous.
  const EVT_TASKS = (w) => `(select count(*) from public.org_tasks t
              join public.event_delivery d on d.task_id = t.id where ${w})`;
  const DEPT_AUTH = `(select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname='public' and p.proname='fn_event_dispatch'
                and pg_get_functiondef(p.oid) ~* '\\yfn_dept_authority\\y')`;
  const ABOVE_TIER = EVT_TASKS(`t.tier is distinct from 'autonomous'
                and not exists (select 1 from public.review_chain rc
                                 where rc.subject_type = 'org_task' and rc.subject_id = t.id::text)`);
  const CLOSED_30 = EVT_TASKS(`t.status in ('done','closed') and t.updated_at > now() - interval '30 days'`);
  await req('xos', 'xos-06-execute-authority', 'Link 6 each OS executes within its authority',
    `select ${DEPT_AUTH} > 0
        and ${EVT_TASKS(`t.tier is not null`)} > 0
        and ${ABOVE_TIER} = 0
        and ${CLOSED_30} > 0
        and ${rdSql('org_tasks', [], 'tier')} > 0`,
    `select 'dispatcher resolves fn_dept_authority: ' || (${DEPT_AUTH} > 0)::text || '; '
        || ${CLOSED_30}::text
        || ' event-derived task(s) closed in 30d of ' || ${EVT_TASKS(`t.tier is not null`)}::text
        || ' carrying a tier, ' || ${ABOVE_TIER}::text
        || ' above tier with no review behind it, ' || ${rdSql('org_tasks', [], 'tier')}::text
        || ' reader(s) of org_tasks that name tier, writers excluded'`);

  // LINK 7 — the result comes back to the event that caused the work.
  //
  // The old form summed six populated surfaces, summed four reader counts, and compared each sum
  // to zero INDEPENDENTLY: one decision_trace row plus any reader of event_delivery scored MET
  // while decision_trace itself was read by nothing. Populated-and-unread is the entire subject of
  // this spec file, and that shape cannot see it. Each surface is now paired with its own reader,
  // and a surface only counts if the thing that carries the result is the thing that is read.
  // TWO FURTHER REPAIRS, both of which the pairing above only LOOKED like it made.
  //
  // (a) The pairing was table-level while the claim is column-level. The disjunct that fired was
  //     `task.result 58/13`, and rdSql('org_tasks') = 13 is the same global-readership constant
  //     this file deleted from xos-05 four comments earlier for being 'about the wrong object':
  //     9 of those 13 routines never name `result` at all. Disjunct 2 was worse — its single
  //     reader was v_event_backbone, which counts event_delivery rows by event_type and never
  //     touches the `result` column. Each surface is now paired with a reader of ITS COLUMN.
  // (b) Four of the five surfaces had no recency bound, so one historical row plus any reader
  //     carried link 7 forever. Every surface is now bounded to 30 days, and the three that are
  //     bounded through a column this file does not otherwise assert go through guarded(), which
  //     scores 0 — no surface — if that column is gone.
  const S_TASK = `(select count(*) from public.event_delivery d join public.org_tasks t on t.id = d.task_id
        where t.result is not null and t.updated_at > now() - interval '30 days')`;
  const S_DELIV = guarded('event_delivery',
    `public.event_delivery where result is not null and delivered_at > now() - interval '30 days'`,
    ['result', 'delivered_at']);
  const S_DTRACE = guarded('decision_trace',
    `public.decision_trace where causation_event_id is not null and created_at > now() - interval '30 days'`,
    ['causation_event_id', 'created_at']);
  const S_WFRUN = guarded('workflow_run',
    `public.workflow_run where trigger_event_id is not null and created_at > now() - interval '30 days'`,
    ['trigger_event_id', 'created_at']);
  const S_ROLLUP = cnt('event_rollup',
    `outcome is not null and consolidated_at > now() - interval '30 days'`, ['outcome', 'consolidated_at']);
  const SURFACES = `((${S_TASK} > 0 and ${rdSql('org_tasks', [], 'result')} > 0)
        or (${S_DELIV} > 0 and ${rdSql('event_delivery', [], 'result')} > 0)
        or (${S_DTRACE} > 0 and ${rdSql('decision_trace', [], 'causation_event_id')} > 0)
        or (${S_WFRUN} > 0 and ${rdSql('workflow_run', [], 'trigger_event_id')} > 0)
        or (${S_ROLLUP} > 0 and ${rdSql('event_rollup', [], 'outcome')} > 0))`;
  await req('xos', 'xos-07-results-returned', 'Link 7 results returned to the originating event',
    `select ${SURFACES}`,
    `select 'task.result ' || ${S_TASK}::text || '/' || ${rdSql('org_tasks', [], 'result')}::text
        || ', delivery.result ' || ${S_DELIV}::text || '/' || ${rdSql('event_delivery', [], 'result')}::text
        || ', decision_trace ' || ${S_DTRACE}::text || '/' || ${rdSql('decision_trace', [], 'causation_event_id')}::text
        || ', workflow_run ' || ${S_WFRUN}::text || '/' || ${rdSql('workflow_run', [], 'trigger_event_id')}::text
        || ', rollup ' || ${S_ROLLUP}::text || '/' || ${rdSql('event_rollup', [], 'outcome')}::text
        || ' (populated in 30d / readers of THAT column, paired)'`);

  // LINK 8 — the Chief of Staff consolidates ACROSS OSes. One rollup row per correlation touching
  // a single OS is a receipt, not a consolidation, so os_count > 1 is part of the measure.
  //
  // Three repairs: the os_count column is guarded (the old cnt named it raw inside query_to_xml,
  // so a rebuild of this nascent table without that column turned the check into an ERROR — an
  // unmeasured requirement, not a MISSING verdict); consolidation must be CURRENT, not historical;
  // and every cross-OS episode must be consolidated, not just one of them. The reader leg excludes
  // the writer, which is what it was previously counting: fn_event_consolidate was the only object
  // in the database that mentioned event_rollup, and it only inserts.
  // FOURTH REPAIR, and it is xos-02's `p_age` argument one link further along: ROLLUP_MISSING had
  // no age bound, so an episode whose second OS was delivered four minutes before this check reads
  // counted as NEVER consolidated. fn_event_consolidate runs on a '25 * * * *' cron; an episode
  // that closed at 08:31 is IN FLIGHT until 09:25, not lost. Measured while writing this: 3
  // episodes were reported unconsolidated and all three post-dated the last successful run. Two
  // hours is two consecutive consolidation ticks — one missed tick still passes, two do not — and
  // the unbounded figure stays in the evidence so a real backlog is still visible.
  const ROLLUP_MISSING = (age = null) => guarded('event_rollup',
    `(select e.correlation_id from public.company_event e
        join public.event_delivery d on d.event_id = e.id
       where e.correlation_id is not null
       group by e.correlation_id
      having count(distinct d.os_key) > 1${age ? `
         and max(d.delivered_at) < now() - interval '${age}'` : ''}) z
      where not exists (select 1 from public.event_rollup r where r.correlation_id = z.correlation_id)`,
    ['correlation_id']);
  await req('xos', 'xos-08-cos-consolidates', 'Link 8 Chief of Staff consolidates outcomes across OSes',
    `select ${cnt('event_rollup')} > 0
        and ${cnt('event_rollup', 'os_count > 1', ['os_count'])} > 0
        and ${cnt('event_rollup', `consolidated_at > now() - interval '48 hours'`, ['consolidated_at'])} > 0
        and ${ROLLUP_MISSING('2 hours')} = 0
        and ${rdSql('event_rollup')} > 0`,
    `select ${cnt('event_rollup')}::text || ' rollup(s), '
        || ${cnt('event_rollup', 'os_count > 1', ['os_count'])}::text || ' spanning >1 OS, '
        || ${cnt('event_rollup', `consolidated_at > now() - interval '48 hours'`, ['consolidated_at'])}::text
        || ' consolidated in 48h, ' || ${ROLLUP_MISSING('2 hours')}::text
        || ' cross-OS episode(s) unconsolidated past the 2-hour SLO ('
        || ${ROLLUP_MISSING()}::text || ' counting in-flight), ' || ${rdSql('event_rollup')}::text
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
  // Two more repairs. (a) Leg 1 was `PRIO('') > 0` — every priority.updated event EVER. All nine
  // rows share one timestamp: a single batch. Once that batch exists, every other leg is a `= 0`
  // coverage leg which only gets easier as the population stops growing, so the requirement was
  // permanently MET even if the CEO never re-prioritised again. Every neighbouring link bounds its
  // liveness leg (xos-01 7d, xos-06 30d, xos-08 48h, xos-11 14d); this one now does too.
  // (b) PRIO_NO_OUTCOME is a `= 0` leg built on guarded(), and guarded() returns 0 when a named
  //     column is missing — so dropping event_rollup.tasks_closed, a column no other check in this
  //     file asserts, turned 'every re-prioritisation traces to a cross-OS episode with closed
  //     work' into an unconditional pass. The columns are now asserted positively.
  const PRIO = (w) => `(select count(*) from public.company_event e where e.event_type = 'priority.updated'${w})`;
  const PRIO_30D = PRIO(` and e.occurred_at > now() - interval '30 days'`);
  const PRIO_NO_OUTCOME = guarded('event_rollup',
    `public.company_event e where e.event_type = 'priority.updated'
       and not exists (select 1 from public.event_rollup r where r.correlation_id = e.correlation_id
                        and r.os_count > 1 and r.tasks_closed > 0)`, ['correlation_id', 'os_count', 'tasks_closed']);
  await req('xos', 'xos-09-ceo-priorities', 'Link 9 CEO updates company priorities off event outcomes',
    `select ${PRIO_30D} > 0
        and ${hasCols('event_rollup', ['correlation_id', 'os_count', 'tasks_closed'])} = 3
        and ${PRIO_NO_OUTCOME} = 0
        and ${PRIO(` and not exists (select 1 from public.company_event c where c.id = e.causation_id)`)} = 0
        and (select count(*) from public.event_subscription where active and event_type = 'priority.updated') > 0
        and ${PRIO(` and not exists (select 1 from public.event_delivery d where d.event_id = e.id)`)} = 0`,
    `select ${PRIO_30D}::text || ' priority.updated event(s) in 30d of ' || ${PRIO('')}::text
        || ' ever, ' || ${PRIO_NO_OUTCOME}::text
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
  // EMITTER_FAILED WAS UNSATISFIABLE IN TWO DIRECTIONS AND IS NOW BOUNDED IN BOTH. It counted
  // every run row whose status `is distinct from 'succeeded'` over all history: (a) a run in
  // progress has status 'running', so a verifier reading while the Monday job executed reported
  // MISSING; (b) cron keeps its history, so one failed run at any point in the future pinned this
  // requirement to MISSING permanently, with no remedy except deleting audit rows. A run still
  // executing has no end_time, and a failure older than 30 days has been superseded by the
  // succeeded runs after it.
  const EMITTER_FAILED = `(select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              join cron.job j on j.active and j.command ~* ('\\y'||p.proname||'\\y')
              join cron.job_run_details r on r.jobid = j.jobid
             where ns.nspname='public' and p.prokind in ('f','p')
               and pg_get_functiondef(p.oid) ~* 'kpi\\.missed'
               and pg_get_functiondef(p.oid) ~* ('inser'||'t\\s+into\\s+(public\\.)?company_event')
               and r.status is distinct from 'succeeded'
               and r.end_time is not null and r.end_time > now() - interval '30 days')`;
  const EMITTER_RAN = EMITTER(`
                and exists (select 1 from cron.job j2 join cron.job_run_details r2 on r2.jobid = j2.jobid
                             where j2.active and j2.command ~* ('\\y'||p.proname||'\\y')
                               and r2.status = 'succeeded')`);
  // NO LEG OF THIS CHECK USED TO TOUCH A KPI. The requirement is 'Intelligence OS updates KPIs and
  // forecasts off events'; the check asserted an emitter, an event count and a delivery count, and
  // production holds 28 KPI objects none of which it looked at. Two legs close that, and finding
  // the first one is what found the system defect below.
  //
  // KPI_FRESH — the figures must have MOVED. public.fn_bi_snapshot() is the only writer of
  // metric_snapshot and therefore the only thing that moves v_bi_scorecard, and on 6 Aug 2026 it
  // had ZERO callers in pg_proc and ZERO rows in cron.job: max(taken_at) was 2026-07-27, ten days
  // stale, nothing in seven. Every OFF_TARGET alert this link emitted was a verdict on a frozen
  // number and every ON_TARGET metric was unfalsifiable — a KPI that stops being measured can
  // never be missed. Fixed by making fn_emit_metric_alerts take the measurement before judging it
  // (scripts/sql/fn_emit_metric_alerts.sql), deployed to both projects and executed: 14 fresh
  // measurements, max(taken_at) 2026-08-06 09:09. The window is 8 days because the emitter's cron
  // is weekly ('0 3 * * 1'), so this fails if that job stops rather than flapping between runs.
  //
  // KPI_READ — and somebody other than the emitter must look at the scorecard, or this is another
  // populated-and-unread surface. fn_bi_snapshot (its writer) and fn_emit_metric_alerts (the
  // routine under test) are both excluded, leaving fn_company_situation and fn_evolution_scan.
  const KPI_FRESH = cnt('metric_snapshot', `taken_at > now() - interval '8 days'`, ['taken_at']);
  const KPI_READ = rdSql('v_bi_scorecard', ['fn_bi_snapshot', 'fn_emit_metric_alerts']);
  const KPI_SOURCED = `(select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname='public' and p.prokind in ('f','p')
                and pg_get_functiondef(p.oid) ~* 'kpi\\.missed'
                and pg_get_functiondef(p.oid) ~* ${RD('v_bi_scorecard')})`;
  const KPI_EVENTS = `(select count(*) from public.company_event
              where event_type = 'kpi.missed' and occurred_at > now() - interval '14 days')`;
  const KPI_DELIVERED = `(select count(*) from public.event_delivery d join public.company_event e on e.id = d.event_id
              where d.event_type = 'kpi.missed' and e.occurred_at > now() - interval '14 days')`;
  await req('xos', 'xos-11-intelligence-kpis', 'Link 11 Intelligence OS updates KPIs off events',
    `select ${EMITTER()} > 0
        and ${EMITTER_FAILED} = 0
        and (${EMITTER_RAN} > 0 or now() < timestamptz '2026-08-11 00:00+00')
        and ${KPI_SOURCED} > 0
        and ${KPI_FRESH} > 0
        and ${KPI_READ} > 0
        and ${KPI_EVENTS} > 0
        and ${KPI_DELIVERED} > 0`,
    `select ${EMITTER()}::text || ' kpi.missed emitter(s) on an active cron ('
        || ${EMITTER_RAN}::text || ' with a succeeded run, required from 2026-08-11; '
        || ${EMITTER_FAILED}::text || ' failed run(s) in 30d), ' || ${KPI_SOURCED}::text
        || ' of them sourced from the scorecard; ' || ${KPI_FRESH}::text
        || ' KPI measurement(s) taken in 8d of ' || ${cnt('metric_snapshot')}::text
        || ' ever, ' || ${KPI_READ}::text || ' reader(s) of the scorecard other than its writer; '
        || ${KPI_EVENTS}::text || ' event(s) in 14d, ' || ${KPI_DELIVERED}::text || ' delivered'`);

  // HARD RULE — no OS reaches into another for business logic. Met either by nothing writing
  // another OS's queue outside the bus, or by a guard on org_tasks that REFUSES the cross-OS write.
  //
  // '\yraise\y' matched `raise notice`, `raise log` and the word inside a comment, so a trigger
  // that logged the violation and then permitted it scored as a guard; it is now
  // `raise\s+exception`. The trigger must also be enabled — a disabled guard is a comment. And the
  // evidence now applies the SAME predicate as the verdict: it previously dropped the raise term
  // entirely, so a trigger matching os_department but not raising could print '1 cross-OS guard(s)'
  // beside a MISSING verdict.
  // MEASURED ON THE ROWS, NOT ON A GREP. The old verdict was `UNBUSED_WRITERS = 0 or GUARDS > 0`.
  // UNBUSED_WRITERS counts every routine that inserts into org_tasks except the dispatcher — an
  // intra-OS insert by a department's own planner is counted identically to a cross-OS one, so the
  // number is 13 and the disjunct is dead. That left the whole hard rule on GUARDS, a text grep;
  // and the one trigger it matches, fn_org_task_cross_os_guard, returns `new` unconditionally when
  // the author resolves to no OS, which is exactly the case for those 13 routine writers. The
  // check was met by a guard that by construction does not refuse the writers the other disjunct
  // flagged.
  //
  // CROSS_OS_UNBUSED asks the question the requirement actually asks, of the data: a task assigned
  // by an agent of one OS into a department belonging to a different OS, past the proposal stage,
  // with no event_delivery behind it. That is 'an OS reached into another OS without the bus', and
  // it is 0 today. The guard stays as a required conjunct rather than an alternative, because the
  // rule has to hold for rows not yet written; its bypasses are deliberate and named (the bus
  // itself, and status='proposed', which is an offer the receiving OS can decline). The evidence
  // no longer claims the 13 routine writers are cross-OS, which the SQL never computed.
  // AND THE ZERO IS REPORTED WITH ITS REASON, because the reason is not the one it looks like.
  // Measured: org_tasks.decided_by is NEVER an agent_key. All 566 non-proposed rows name a routine
  // — fn_event_dispatch 325, cos 116, approval_path 111, dept_plan 5 — or nothing at all (9). So
  // the OS-attributed population is empty, which means CROSS_OS_UNBUSED alone would be a guard
  // over nothing, and fn_org_task_cross_os_guard's `v_author_os is null` branch returns `new` on
  // every row production has ever written: the trigger has never refused anything and structurally
  // cannot until an agent decides a task directly.
  //
  // That is still compliance with the hard rule rather than a hole in the check — no OS writes
  // another OS's queue because no OS writes org_tasks at all; the bus and three company-level
  // routines write all of it — but the difference between 'zero violations' and 'zero attributed
  // actors' is exactly the kind of thing this spec file exists to stop a scorer from blurring. So
  // WRITES_TOTAL asserts the population is non-empty, and the evidence prints the split. Demanding
  // that decided_by BE an agent_key would be demanding a different architecture, which is the
  // over-hardening this file is equally forbidden to do.
  const OS_ATTRIBUTED = `(select count(*) from public.org_tasks t
             where coalesce(t.status,'proposed') <> 'proposed'
               and exists (select 1 from public.org_agents a
                             join public.os_department od on od.dept_key = a.department
                            where a.agent_key = t.decided_by))`;
  const WRITES_TOTAL = `(select count(*) from public.org_tasks t
             where coalesce(t.status,'proposed') <> 'proposed')`;
  const BUS_BACKED = `(select count(*) from public.org_tasks t
             where coalesce(t.status,'proposed') <> 'proposed'
               and exists (select 1 from public.event_delivery d where d.task_id = t.id))`;
  const CROSS_OS_UNBUSED = `(select count(*) from public.org_tasks t
              join public.org_agents a on a.agent_key = t.decided_by
              join public.os_department oda on oda.dept_key = a.department
              join public.os_department odt on odt.dept_key = t.dept_key
             where oda.os_key <> odt.os_key and coalesce(t.status,'proposed') <> 'proposed'
               and not exists (select 1 from public.event_delivery d where d.task_id = t.id))`;
  const ORG_TASK_WRITERS = `(select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_event_dispatch'
                and pg_get_functiondef(p.oid) ~* ('inser'||'t\\s+into\\s+(public\\.)?org_tasks'))`;
  const GUARDS = `(select count(*) from pg_trigger tg join pg_class c on c.oid = tg.tgrelid
              join pg_proc p on p.oid = tg.tgfoid
             where c.relname='org_tasks' and not tg.tgisinternal and tg.tgenabled <> 'D'
               and p.prokind in ('f','p')
               and pg_get_functiondef(p.oid) ~* '\\yos_department\\y'
               and pg_get_functiondef(p.oid) ~* '\\yorg_agents\\y'
               and pg_get_functiondef(p.oid) ~* 'raise\\s+exception')`;
  await req('xos', 'xos-12-no-direct-cross-os', 'Hard rule no OS calls another OS directly',
    `select ${WRITES_TOTAL} > 0 and ${CROSS_OS_UNBUSED} = 0 and ${GUARDS} > 0`,
    `select ${CROSS_OS_UNBUSED}::text || ' task(s) assigned across an OS boundary by a named agent '
        || 'without an event behind them, of ' || ${OS_ATTRIBUTED}::text
        || ' write(s) attributable to an OS-scoped agent at all — out of ' || ${WRITES_TOTAL}::text
        || ' non-proposed write(s), ' || ${BUS_BACKED}::text
        || ' of them raised by the bus, the rest by company-level routines; ' || ${GUARDS}::text
        || ' enabled trigger(s) on org_tasks that resolve BOTH the author and the target OS and '
        || 'raise an exception; ' || ${ORG_TASK_WRITERS}::text
        || ' routine(s) write org_tasks outside the dispatcher (intra-OS writes included, which '
        || 'the rule permits)'`);

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
  // THREE MORE REPAIRS, ALL OF THEM IN THE PRODUCER TEST OR AROUND IT.
  //
  // (c) 'has a producer' was `pg_get_functiondef(p.oid) like '%''<event_type>''%'` — a grep for the
  //     quoted string in ANY body, which a CONSUMER matches exactly as well as an emitter. It
  //     printed '0 unwired' at a moment when four of the five declared outputs had no emitter at
  //     all: priority.updated and knowledge.updated matched fn_event_consolidate, supply.gap
  //     matched fn_company_reflect, improvement.proposed matched fn_os_improve, and none of those
  //     matches emitted anything. A producer must now EMIT: the type must appear as the first
  //     argument of an fn_emit call, or inside an insert into company_event, or in a trigger's
  //     argument list. (Since re-measured: all five now have real emitters — the routines above
  //     acquired fn_emit calls — so this leg passes on the fact rather than on the grep.)
  // (d) That grep was also the file's only LIKE, and it interpolated table content into the
  //     pattern with no ESCAPE clause, so a '_' or '%' inside an event_type became a wildcard —
  //     and it failed OPEN, since an over-matching pattern makes the exists true and the interface
  //     not unwired. IF_BADTYPE now VALIDATES the content before it is interpolated: every
  //     declared type must be a dotted lower-case identifier, which is what makes escaping the
  //     single '.' sufficient and provably complete.
  // (e) 'has fired' was unbounded — three of the five declared outputs had exactly one event each,
  //     all at one seeding timestamp, and that carried 'the bus carries what it declares' forever.
  //     It is bounded to 30 days, in line with the rest of this file.
  //
  // The `planned` flag keeps its two existing bounds and gains a third. It cannot hide a live
  // interface: IF_PLANNED_LIVE keys on `kind`, and kind = event_type on 31 of the 32 declarations,
  // so flipping the flag on anything that flows is caught. IF_PLANNED_OUT_FLOWS closes the case
  // that keying on kind leaves open in the other direction — an OS may not call its own output
  // 'planned' once that output is actually being emitted. What planned still excuses, and should,
  // is an interface that is wired and whose situation has not occurred: production has no
  // customers, so budget.exceeded and invoice.received cannot fire, and demanding traffic from
  // them would be the unsatisfiable form of this requirement.
  const IFACE = (w) => `(select count(*) from public.os_interface i where i.active and i.event_type is not null and ${w})`;
  const ETY = `replace(i.event_type,'.','\\.')`;   // safe only because IF_BADTYPE is asserted 0
  const IF_BADTYPE = IFACE(`i.event_type !~ '^[a-z_]+\\.[a-z_]+$'`);
  const IF_LIVE_NEVER = IFACE(`not coalesce(i.planned,false)
              and not exists (select 1 from public.company_event e where e.event_type = i.event_type
                               and e.occurred_at > now() - interval '30 days')`);
  const IF_NO_REASON = IFACE(`coalesce(i.planned,false) and coalesce(i.planned_reason,'') = ''`);
  const IF_PLANNED_LIVE = IFACE(`coalesce(i.planned,false)
              and exists (select 1 from public.company_event e where e.event_type = i.kind)`);
  const IF_PLANNED_OUT_FLOWS = IFACE(`coalesce(i.planned,false) and i.direction = 'output'
              and exists (select 1 from public.company_event e where e.event_type = i.event_type)`);
  const IF_UNWIRED = IFACE(`not coalesce(i.planned,false) and (
                (i.direction = 'output' and not (
                    exists (select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                             where ns.nspname='public' and p.prokind in ('f','p')
                               and pg_get_functiondef(p.oid) ~ ('fn_emit\\s*\\(\\s*'''||${ETY}||''''))
                 or exists (select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                             where ns.nspname='public' and p.prokind in ('f','p')
                               and pg_get_functiondef(p.oid) ~
                                   ('inser'||'t\\s+into\\s+(public\\.)?company_event[^;]*'''||${ETY}||''''))
                 or exists (select 1 from pg_trigger tg where not tg.tgisinternal
                             and strpos(encode(tg.tgargs,'escape'), i.event_type) > 0)))
             or (i.direction = 'input' and not exists (
                    select 1 from public.event_subscription s
                      join public.org_agents a on a.agent_key = s.agent_key
                      join public.os_department od on od.dept_key = a.department
                     where s.active and s.event_type = i.event_type and od.os_key = i.os_key))) `);
  await req('xos', 'xos-13-standard-interfaces', 'OSes expose standardized interfaces the bus carries',
    `select ${IFACE('true')} > 0
        and ${IF_BADTYPE} = 0
        and ${IF_LIVE_NEVER} = 0
        and ${IF_NO_REASON} = 0
        and ${IF_PLANNED_LIVE} = 0
        and ${IF_PLANNED_OUT_FLOWS} = 0
        and ${IF_UNWIRED} = 0
        and ${rdSql('os_interface')} > 0`,
    `select ${IF_LIVE_NEVER}::text || ' live interface(s) with no traffic in 30d, ' || ${IF_UNWIRED}::text
        || ' unwired (output whose type no routine emits / input with no subscriber in that OS), '
        || ${IF_BADTYPE}::text || ' malformed type(s); '
        || ${IFACE(`coalesce(i.planned,false)`)}::text || ' declared planned ('
        || ${IF_NO_REASON}::text || ' with no reason, ' || ${IF_PLANNED_LIVE}::text
        || ' whose declared kind already flows, ' || ${IF_PLANNED_OUT_FLOWS}::text
        || ' output(s) already emitting), of ' || ${IFACE('true')}::text || ' declared; '
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
  // CORR_READERS was the one reader test in this file that omitted the writer-exclusion term the
  // header defines a reader by, and it counted pg_proc rows rather than routines. Both are fixed by
  // routing it through rdSql, which is what the term existed for; the count is unchanged at 3,
  // because none of the three writes company_event — they write event_delivery, event_rollup and
  // workflow_run off it. That is a genuine read of the chain, but a passive one, so the load is
  // moved onto CORR_LIVE: at least one of those readers must sit on an active cron that has
  // actually succeeded. A correlation chain read only by code nobody runs is not audited.
  const CORR_READERS = rdSql('company_event', [], 'correlation_id');
  const CORR_LIVE = rdCronOk('company_event', 'correlation_id');
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
        and (select count(*) from public.company_event
              where causation_id is not null and occurred_at > now() - interval '30 days') > 0
        and ${CORR_READERS} > 0
        and ${CORR_LIVE} > 0`,
    `select (select count(*) from public.company_event where correlation_id is not null)::text || '/'
        || (select count(*) from public.company_event)::text || ' correlated, '
        || (select count(*) from public.company_event
              where causation_id is not null and occurred_at > now() - interval '30 days')::text
        || ' caused in 30d of '
        || (select count(*) from public.company_event where causation_id is not null)::text
        || ' ever (default wired: ' || (${CAUS_DEFAULT} > 0)::text || ', ' || ${CAUS_SETTER}::text
        || ' routine(s) set the cause), ' || ${CORR_READERS}::text
        || ' reader(s) that select company_event AND name correlation_id, writers excluded, '
        || ${CORR_LIVE}::text || ' of them on a cron that has succeeded'`);

  // BUS OBSERVABILITY — v_event_backbone is the one surface that says which event types are live,
  // undelivered or never fired. It exists and is correct; the requirement is that somebody looks.
  // 'Somebody' is now required to be a routine on an ACTIVE cron, not merely a routine: under this
  // file's own doctrine a function nobody calls is the same as a table nobody reads.
  // And 'on an active cron' is a schedule flag, which this repo's own rule calls a claim rather
  // than a fact: only cron.job_run_details makes it one. A job created but never fired reads the
  // backbone exactly as often as no job at all, so the reader must have SUCCEEDED at least once.
  const BACKBONE_CRON = rdCronOk('v_event_backbone');
  await req('xos', 'xos-15-bus-observability', 'Bus health is observable: the backbone view is read',
    `select (select count(*) from pg_views where schemaname='public' and viewname='v_event_backbone') > 0
        and ${rdSql('v_event_backbone')} > 0
        and ${BACKBONE_CRON} > 0`,
    `select 'v_event_backbone: ' || ${rdSql('v_event_backbone')}::text || ' live reader(s), '
        || ${BACKBONE_CRON}::text || ' of them on an active cron, over '
        || (select count(*) from public.event_subscription where active)::text || ' active subscription(s)'`);
}
