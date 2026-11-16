// verify_rfq_trace.mjs — the Observability requirement, measured against a real RFQ.
//
// AGENTS_AND_KNOWLEDGE_BLUEPRINT.txt asks for one thing under Observability and gives a worked
// example: "RFQ #4582 → Created → Document AI analyzed BOQ → HVAC Agent qualified inquiry →
// Supplier Matching Agent selected 12 suppliers → Notification Agent sent invitations → 7
// quotations received → Comparison AI ranked quotations → Award recommendation generated. Every
// step should be logged with timestamps AND REASONS."
//
// fn_entity_activity is already reachable — os_api exposes it as the `activity` action — and it had
// exactly one specialised branch, `if p_entity = 'supplier'`. For an inquiry it returned comments
// and os_audit_log rows only, and the RFQ lifecycle is written to neither. The supplier had a
// ten-step timeline; the thing the business actually runs on had nothing.
//
// This gate builds ONE real RFQ through the factory, dispatches it, quotes it twice, and asserts
// the trace by KIND — not by length, because a trace that grew is not a trace that is right.
// The assertion that matters is `reasons`: inquiry_matches.match_reason is the only place the
// system records WHY a given supplier was contacted, and a timestamp log cannot produce it.
//
// Costs one rfq_routing model call (~0.01 AED) for the real dispatch. Tears itself down in a
// finally, like every other factory fixture.
//
//     node scripts/archive/staging/verify_rfq_trace.mjs
import { mgmtRead, PROD_REF } from '../../lib/qd_guard.mjs';
import { withRun, makeCustomer, makeSupplier, makeInquiry, makeQuote, internalCred, call, REF } from '../../lib/demo_factory.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(52)} ${detail}`);
};
const one = async (ref, sql) => (await mgmtRead(ref, sql))[0];
const lit = (s) => `'${String(s).replace(/'/g, "''")}'`;

// The marker is checked first: without it every assertion below would be measuring the old
// function and reporting an empty trace as a data problem.
for (const [env, ref] of [['staging', REF], ['production', PROD_REF]]) {
  const n = (await one(ref, `select count(*)::int n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
     where ns.nspname='public' and p.proname='fn_entity_activity' and p.prosrc like '%QD_RFQ_TRACE%'`)).n;
  step(`the rfq branch is deployed on ${env}`, n === 1, `${n} matching definition`);
}

await withRun(async (run) => {
  const cust = await makeCustomer(run);
  const supA = await makeSupplier(run, { trade: 'aluminium' });
  const supB = await makeSupplier(run, { trade: 'aluminium', variant: 1 });
  const inq = await makeInquiry(run, { customer: cust });

  const cred = await internalCred();
  const d = await call('dispatch_inquiry', null, { __secret: cred, inquiry_id: inq.id });
  step('the fixture RFQ was really dispatched', d.status === 200 && Number(d.json?.notified || 0) > 0,
    `HTTP ${d.status} notified=${d.json?.notified} outcome=${d.json?.outcome}`);

  await makeQuote(run, { inquiry: inq, supplier: supA, amount: 125000 });
  await makeQuote(run, { inquiry: inq, supplier: supB, amount: 131750 });

  const trace = await one(REF, `
    with t as (select public.fn_entity_activity('rfq', ${lit(inq.id)}) j)
    select jsonb_array_length(j) n,
           (select string_agg(distinct e->>'kind', ',' order by e->>'kind') from t, jsonb_array_elements(j) e) kinds,
           (select count(*) from t, jsonb_array_elements(j) e where e->>'at' is null) undated,
           (select count(*) from t, jsonb_array_elements(j) e
              where e->>'kind'='match' and coalesce(e->>'body','') <> '') matches_with_reason,
           (select count(*) from t, jsonb_array_elements(j) e where e->>'kind'='match') matches,
           (select count(*) from t, jsonb_array_elements(j) e where e->>'kind'='quote') quotes,
           (select e->>'body' from t, jsonb_array_elements(j) e where e->>'kind'='match' limit 1) reason
      from t`);

  const kinds = String(trace.kinds || '').split(',').filter(Boolean);
  step('the RFQ has a trace at all', Number(trace.n) > 0, `${trace.n} entr(ies): ${trace.kinds}`);
  step('it carries the lifecycle, not just an audit log',
    ['milestone', 'decision', 'match', 'quote'].every((k) => kinds.includes(k)),
    `kinds present: ${kinds.join(', ')}`);
  step('every supplier contacted is named with the REASON it was chosen',
    Number(trace.matches) > 0 && Number(trace.matches_with_reason) === Number(trace.matches),
    `${trace.matches_with_reason}/${trace.matches} — "${String(trace.reason || '').slice(0, 60)}"`);
  step('both quotations appear', Number(trace.quotes) === 2, `${trace.quotes} quote entr(ies)`);
  step('nothing undated reaches the caller', Number(trace.undated) === 0,
    `${trace.undated} entr(ies) without a timestamp`);

  // REGRESSION: the supplier branch is the one that already worked. A patch that inserts a new
  // branch before the shared return is exactly the shape that can strand the old one.
  const sup = await one(REF, `
    with t as (select public.fn_entity_activity('supplier', ${lit(String(supA.leadId))}) j)
    select jsonb_array_length(j) n,
           (select count(*) from t, jsonb_array_elements(j) e where e->>'kind'='milestone') milestones from t`);
  step('the supplier branch still works', Number(sup.milestones) > 0,
    `${sup.n} entr(ies), ${sup.milestones} milestone(s)`);

  // p_id is text. The uuid cast would throw 22P02 on a supplier id and take the comments and
  // audit rows down with it, so the branch is guarded rather than trusted.
  const guard = await one(REF, `select jsonb_array_length(public.fn_entity_activity('rfq','not-a-uuid')) n`);
  step('a non-uuid id is refused, not thrown', Number(guard.n) === 0, `${guard.n} entr(ies), no exception`);
});

const bad = checks.filter((c) => !c.ok).length;
console.log(`\nRFQ TRACE ${checks.length - bad}/${checks.length} on ${REF}`);
if (bad) process.exitCode = 1;
