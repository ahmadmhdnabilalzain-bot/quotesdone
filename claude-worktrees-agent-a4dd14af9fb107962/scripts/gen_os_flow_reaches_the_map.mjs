// ROW #3 mission-control-flow-animation — the ten operating systems talk to each other 932 times a
// week and no surface has ever drawn one of those connections.
//
// ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
//   mission-control-flow-animation  MISSING  3 component(s) draw connections [AreaSpark AgentsApp
//                                            MiniLine], 0 of those animate, 0 bound to a flow
//
// The check's second leg — a browser-reachable reader of os_interface or event_delivery — already
// passes (fn_event_dispatch, fn_task_lesson, fn_ws_live_company). The drawing is the whole gap.
//
// ── FINDING THE FLOW WITHOUT INVENTING IT ───────────────────────────────────────────────────────
// The obvious source is os_interface, and it does not work. The ten systems declare 16 outputs and
// 17 inputs and the two sets are DISJOINT except for `supply.gap`, which marketplace both emits
// and consumes. Joining outputs to inputs on event_type yields exactly ZERO cross-OS edges.
// Writing interface rows to make that graph connect would be inventing the company's own contract
// table to fill a picture, so it is not done here — and it is worth the founder knowing that the
// declared interface graph does not connect, because that is a real finding about the architecture.
//
// graph_edges does not help either: 608 edges across 8 relations, none of them operating_system to
// operating_system.
//
// What DOES record real flow is event_delivery — 932 deliveries in 7 days, every one of the ten
// systems represented. It carries the CONSUMER (os_key) and the event, and company_event carries
// the ACTOR that emitted it. Resolving the actor through org_agents.department and os_department
// gives the producer:
//
//     event_delivery.os_key                                    -> the receiving OS
//     company_event.actor -> org_agents.department             -> the sending OS
//                         -> os_department.dept_key (fallback: the actor IS a department)
//
// 690 of 932 resolve. knowledge->commercial 78, marketplace->commercial 66, operations->commercial
// 58, marketplace->knowledge 51, commercial->knowledge 48. Live, dated, and none of it composed.
//
// The 242 that do not resolve are emitted by `system`, `fn_os_review` and `brief` — machinery
// rather than an operating system. They are counted and reported as unattributed rather than
// assigned to an OS, because guessing which system a cron belongs to is the same fabrication in a
// smaller coat.
//
// ── WHY fn_ws_company_os AND NOT A NEW ROUTINE ──────────────────────────────────────────────────
// The map screen already exists and is fed by this routine. A new routine would need a new os_api
// action, a new classification entry and a new module for a picture that belongs on the map that
// is already there. One key on an existing payload is the whole change.
//
// The routine is 14,475 characters of SQL. It is read from the live database and patched at one
// asserted anchor, so every other key stays byte-identical.
import { readFileSync, writeFileSync } from 'node:fs';
import { mgmtRead } from './staging/qd_guard.mjs';
import { REF as STAGE } from './staging/demo_factory.mjs';

const OUT = 'scripts/sql/os_flow_reaches_the_map.sql';
const one = async (sql) => { const r = await mgmtRead(STAGE, sql); return r[0] ? Object.values(r[0])[0] : null; };

const def = await one(`select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.proname='fn_ws_company_os' limit 1`);
if (!def) { console.error('fn_ws_company_os not found'); process.exit(1); }
if (/'flow',/.test(def)) { console.error('REFUSING: fn_ws_company_os already carries a flow key.'); process.exit(1); }

const ANCHOR = `    'generated_at', now()`;
if (def.split(ANCHOR).length - 1 !== 1) {
  console.error('REFUSING: the generated_at anchor did not match exactly once. Re-read the routine first.');
  process.exit(1);
}

const BLOCK = `    -- ── INFORMATION FLOWING BETWEEN THE TEN SYSTEMS ─────────────────────────────────────────
    -- Derived from what was actually DELIVERED, not from what os_interface declares: the declared
    -- outputs and inputs are disjoint sets and join to zero cross-OS edges. The consumer is
    -- event_delivery.os_key; the producer is company_event.actor resolved through its department,
    -- or the actor itself when the actor IS a department. Deliveries whose actor is machinery
    -- (system, a cron, the brief) are counted as unattributed rather than assigned to a system.
    'flow', (with res as (
        select d.os_key as to_os, d.event_type, d.delivered_at,
               coalesce((select od.os_key from public.org_agents a
                          join public.os_department od on od.dept_key = a.department
                         where a.agent_key = e.actor limit 1),
                        (select od2.os_key from public.os_department od2
                          where od2.dept_key = e.actor limit 1)) as from_os
          from public.event_delivery d
          join public.company_event e on e.id = d.event_id
         where d.os_key is not null and d.delivered_at > now() - interval '7 days')
      select jsonb_build_object(
        'window_days', 7,
        'deliveries', (select count(*) from res),
        'attributed', (select count(*) from res where from_os is not null),
        'unattributed', (select count(*) from res where from_os is null),
        'unroutable', (select count(*) from public.event_delivery
                        where unroutable_reason is not null
                          and delivered_at > now() - interval '7 days'),
        'nodes', coalesce((select jsonb_agg(jsonb_build_object(
            'os_key', o.os_key, 'num', o.num, 'name', o.name,
            'received', (select count(*) from res where res.to_os = o.os_key),
            'sent', (select count(*) from res where res.from_os = o.os_key)) order by o.num)
          from public.operating_system o where o.active), '[]'::jsonb),
        'edges', coalesce((select jsonb_agg(x) from (
            select from_os, to_os, count(*) as n,
                   count(distinct event_type) as event_types,
                   max(delivered_at) as newest,
                   (array_agg(distinct event_type))[1:3] as kinds
              from res where from_os is not null
             group by from_os, to_os order by count(*) desc limit 40) x), '[]'::jsonb))),

${ANCHOR}`;

const out = def.replace(ANCHOR, BLOCK);
if (out === def) { console.error('replacement produced no change'); process.exit(1); }

const selfLines = readFileSync(new URL(import.meta.url).pathname.replace(/^\//, ''), 'utf8').split('\n');
const end = selfLines.findIndex((l) => !l.startsWith('//'));
const HEADER = selfLines.slice(0, end < 0 ? selfLines.length : end)
  .map((l) => l.replace(/^\/\/ ?/, '-- ').replace(/^\/\//, '--')).join('\n');

writeFileSync(OUT, `${HEADER}\n\n${out};\n`);
console.log(`wrote ${OUT}`);
console.log(`  fn_ws_company_os ${def.length} -> ${out.length} chars`);
