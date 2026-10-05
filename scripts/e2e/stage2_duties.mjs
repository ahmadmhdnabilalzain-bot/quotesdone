// scripts/e2e/stage2_duties.mjs — every live duty, exercised in an ABORTED transaction.
// Assigned: it_engineer (tooling). Ledger 1119, founder 6 Oct: "everything needs to be tested".
//
// WHAT A DUTY IS, MEASURED 6 OCT 2026. cron_registry lists 109 customer-facing jobs, but cron.job
// holds 0 rows: the 7 Sep removal deleted the pg_cron jobs and left the registry as labels. Nothing
// fires them. What actually runs is (a) public.seat_duty, executed by fn_seat_duties_tick, and (b) the
// zero-argument routines resilience_ping calls on every tick. That is the inventory used here.
//
// THE PROBE. One DO block per duty: set app.e2e_run_tag, call the routine, then count every row in the
// nine marketplace tables that THIS transaction inserted or updated (age(xmin) = 0), split by demo and
// non-demo. Then raise, so nothing commits: no notification row, no pg_net request (its queue is a
// table in the same transaction) and no update survives. A delete is not seen by age(xmin); that limit
// is stated in the report.
// PASS = the routine ran without error AND it wrote no non-demo row. A duty that writes real rows
// (today it would act on the real leads pool) FAILS with the counts. That is the finding that a scope
// guard on app.e2e_run_tag is still missing (public.fn_e2e_in_scope, see the SQL file below).
import { write } from './fixtures.mjs';
import { q } from '../lib/demo_factory.mjs';

// Zero-argument routines resilience_ping calls (supabase/functions/resilience_ping/index.ts). The
// *_record, *_attach_pdf and *_write routines take arguments and are reached only through their *_due pair.
export async function liveDuties(read, repoSrc) {
  const seat = await read(`select sd.duty, sd.routine, sd.owner_seat seat, sd.enabled from public.seat_duty sd order by 1`);
  const tick = [...new Set([...repoSrc.matchAll(/rpc\('([a-z0-9_]+)'/g)].map((m) => m[1]))];
  const zeroArg = (await read(`select p.proname from pg_proc p where p.pronamespace='public'::regnamespace and p.pronargdefaults = p.pronargs
      and p.proname in (${tick.map(q).join(',') || 'null'})`)).map((r) => r.proname);
  const known = new Set(seat.map((s) => s.routine));
  return [...seat.map((s) => ({ ...s, source: 'seat_duty' })),
    ...zeroArg.filter((r) => !known.has(r) && !/^fn_(seat_duties_tick|cron_liveness|notify_founder|resilience_tick_plan)$/.test(r))
      .map((r) => ({ duty: 'tick.' + r, routine: r, seat: 'resilience_ping', enabled: true, source: 'resilience_ping' }))];
}

const DEMO = {
  leads: 'x.is_demo',
  customers: 'x.is_demo',
  inquiries: 'x.customer_id in (select id from public.customers where is_demo)',
  quotes: 'x.supplier_id in (select id from public.leads where is_demo)',
  transactions: '(x.supplier_id in (select id from public.leads where is_demo) or x.customer_id in (select id from public.customers where is_demo))',
  refunds: 'x.customer_id in (select id from public.customers where is_demo)',
  notifications: `(x.to_email like '%@example.invalid' or x.to_email like 'qd-%@example.%' or x.lead_id in (select id from public.leads where is_demo)
                   or x.inquiry_id in (select i.id from public.inquiries i join public.customers c on c.id=i.customer_id where c.is_demo))`,
  quote_spec_hold: 'x.supplier_id in (select id from public.leads where is_demo)',
  supplier_dues: 'x.supplier_id in (select id from public.leads where is_demo)',
};

export async function probeDuty(d, tag) {
  const counts = Object.entries(DEMO).map(([t, p]) =>
    `'${t}', jsonb_build_object('demo', (select count(*) from public.${t} x where age(x.xmin) = 0 and ${p}),
                               'real', (select count(*) from public.${t} x where age(x.xmin) = 0 and not coalesce(${p}, false)))`).join(',\n');
  const sql = `do $probe$ declare v_res jsonb; v_c jsonb; v_t0 timestamptz := clock_timestamp(); begin
    set local statement_timeout = '25s'; set local lock_timeout = '3s';
    perform set_config('app.e2e_run_tag', ${q(tag)}, true);
    execute format('select to_jsonb(public.%I())', ${q(d.routine)}) into v_res;
    v_c := jsonb_build_object(${counts});
    raise exception 'CHK<<%>>', jsonb_build_object('ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000), 'counts', v_c, 'result', left(coalesce(v_res::text, 'null'), 300));
  end $probe$`;
  try { await write(sql, `stage2 duty probe ${d.duty} (aborted)`); return { error: 'the probe did not raise: it may have COMMITTED' }; }
  catch (e) {
    // qd_guard cuts e.message at 300 characters; e.body is the whole API answer.
    let msg = String(e.body || e.message);
    try { msg = JSON.parse(msg).message || msg; } catch { /* not JSON */ }
    const m = msg.match(/CHK<<(.*)>>/s);
    if (!m) return { error: msg.replace(/\s+/g, ' ').slice(0, 300) };
    const o = JSON.parse(m[1]);
    const real = Object.values(o.counts).reduce((a, c) => a + Number(c.real), 0);
    const demo = Object.values(o.counts).reduce((a, c) => a + Number(c.demo), 0);
    return { ...o, real, demo };
  }
}
