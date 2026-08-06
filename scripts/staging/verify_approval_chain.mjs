// verify_approval_chain.mjs — exercise §12 (Purchase Approval System) and the §22 Orders link
// END TO END on staging, with a tagged fixture that is torn down on the way out of a throw.
//
// THE TRAP THIS FILE IS WRITTEN AROUND: a single SQL statement shares ONE SNAPSHOT. Award the
// quote and read procurement_approval_request in the same statement and you read the PRE-award
// state — which reports "the trigger did nothing" for a trigger that worked. Every effect below
// is therefore read back in a SEPARATE statement from the one that caused it.
//
//   node scripts/staging/verify_approval_chain.mjs
//
// Exit 0 only if every assertion holds. Production is refused by qd_guard: this writes.
import { randomUUID } from 'node:crypto';
import { mgmtRead, mgmtWrite } from './qd_guard.mjs';
import { REF as STAGE, BASE, q, jb, call, keys, mkAuthUser } from './demo_factory.mjs';

const tag = 'appr' + Date.now().toString(36);
const W = (sql) => mgmtWrite(STAGE, sql, tag);
const R = (sql) => mgmtRead(STAGE, sql, tag);
const one = async (sql) => { const r = await R(sql); return r?.[0] ? Object.values(r[0])[0] : null; };

let pass = 0; const fails = [];
const ok = (name, cond, detail = '') => {
  if (cond) { pass++; console.log(`  PASS  ${name}${detail ? ' — ' + detail : ''}`); }
  else { fails.push(name); console.log(`  FAIL  ${name}${detail ? ' — ' + detail : ''}`); }
};
const eq = (name, got, want) => ok(name, JSON.stringify(got) === JSON.stringify(want), `got ${JSON.stringify(got)} want ${JSON.stringify(want)}`);

const STEPS = [
  { key: 'engineer', label: 'Engineer', role: 'engineer' },
  { key: 'pm', label: 'Project Manager', role: 'project_manager' },
  { key: 'finance', label: 'Finance', role: 'finance' },
  { key: 'ceo', label: 'CEO', role: 'ceo' },
];
const actors = { engineer: randomUUID(), project_manager: randomUUID(), finance: randomUUID(), ceo: randomUUID() };

// WHAT A LEAK CHECK CAN HONESTLY ASSERT ON SHARED STAGING: that no row carrying THIS file's tag
// survives. Global row counts cannot be the assertion — three other agents write to the same
// project concurrently, so a before/after count moves for reasons that have nothing to do with
// this run and reports a leak that is somebody else's fixture.
const SURVIVORS = `select 'customers' t, count(*) c from public.customers where email like 'qd-appr%'
  union all select 'leads', count(*) from public.leads where company_name like 'QD appr%'
  union all select 'inquiries', count(*) from public.inquiries where raw_input like 'QD appr%'
  union all select 'customer_organization', count(*) from public.customer_organization where name like 'QD appr%'
  union all select 'po_vendors', count(*) from public.po_vendors where name like 'QD appr%'
  union all select 'procurement_approval_request', count(*) from public.procurement_approval_request
             where organization_id in (select id from public.customer_organization where name like 'QD appr%')`;
const survivors = async () => (await R(SURVIVORS)).filter((r) => Number(r.c) > 0).map((r) => `${r.t}=${r.c}`);

const ids = {};
try {
  // ── FIXTURE ────────────────────────────────────────────────────────────────────────────────
  // A REAL auth identity, because the last leg of this file calls the customer-authed endpoint the
  // portal will call, and that endpoint resolves the customer from the JWT's email.
  const user = await mkAuthUser({ authUsers: [] }, `qd-${tag}-owner@example.com`);
  ids.cust = user.id;
  await W(`insert into public.customers(id,full_name,email,email_verified)
      values (${q(user.id)}, 'QD ${tag} owner', 'qd-${tag}-owner@example.com', true)`);
  ids.lead = (await W(`insert into public.leads(company_name)
      values ('QD ${tag} supplier') returning id`))[0].id;
  ids.org = (await W(`insert into public.customer_organization(name, owner_customer_id)
      values ('QD ${tag} org', ${q(ids.cust)}) returning id`))[0].id;
  await W(`insert into public.customer_organization_member(organization_id,user_id,role,active) values
      ${Object.entries(actors).map(([role, uid]) => `(${q(ids.org)}, ${q(uid)}, ${q(role)}, true)`).join(',')}`);

  // TWO policies, so "respecting procurement_approval_policy.steps" is a measured choice and not a
  // coincidence: the 1,000,000 chain must NOT be the one a 250,000 award selects.
  ids.policy = (await W(`insert into public.procurement_approval_policy(organization_id,name,conditions,steps)
      values (${q(ids.org)}, 'QD ${tag} standard',
              ${jb({ entity_type: 'inquiry', min_amount: 50000 })}, ${jb(STEPS)}) returning id`))[0].id;
  ids.bigPolicy = (await W(`insert into public.procurement_approval_policy(organization_id,name,conditions,steps)
      values (${q(ids.org)}, 'QD ${tag} board',
              ${jb({ entity_type: 'inquiry', min_amount: 1000000 })},
              ${jb([{ key: 'board', label: 'Board', role: 'ceo' }])}) returning id`))[0].id;

  const mkAward = async (amount) => {
    const inq = (await W(`insert into public.inquiries(customer_id,category,emirate,raw_input,status)
        values (${q(ids.cust)}, 'marble', 'Dubai', 'QD ${tag} fixture RFQ', 'open') returning id`))[0].id;
    // customer_price is GENERATED (quote_amount + app_fee), so it is never inserted.
    const quote = (await W(`insert into public.quotes(inquiry_id,supplier_id,quote_amount,status)
        values (${q(inq)}, ${ids.lead}, ${amount}, 'submitted') returning id`))[0].id;
    // THE AWARD. Its effect is read in the NEXT statement, never this one.
    await W(`update public.inquiries set status='completed', outcome='hired',
               hired_supplier_id=${ids.lead}, completed_at=now() where id=${q(inq)}`);
    return { inq, quote };
  };

  // ── 1. RAISE ───────────────────────────────────────────────────────────────────────────────
  const a = await mkAward(250000);
  ids.inq = a.inq; ids.quote = a.quote;
  const req = (await R(`select id, status, current_step, policy_id, organization_id, jsonb_array_length(decisions) nd
      from public.procurement_approval_request where entity_type='inquiry' and entity_id=${q(ids.inq)}`))[0];
  ok('award raises an approval request', !!req, req ? `request ${req.id}` : 'no request raised');
  if (!req) throw new Error('nothing to advance');
  ids.req = req.id;
  eq('raised request starts pending at step 1', [req.status, Number(req.current_step), Number(req.nd)], ['pending', 1, 0]);
  ok('the matching policy was chosen, not the 1,000,000 board chain',
    req.policy_id === ids.policy, `policy_id ${req.policy_id}`);

  const trace = async () => (await R(`select step, step_label, step_status, decided_by
      from public.v_approval_trace where request_id=${q(ids.req)} order by step`));
  eq('trace projects four named steps, first pending, rest waiting',
    (await trace()).map((r) => `${r.step_label}:${r.step_status}`),
    ['Engineer:pending', 'Project Manager:waiting', 'Finance:waiting', 'CEO:waiting']);

  // ── 2. ADVANCE ─────────────────────────────────────────────────────────────────────────────
  const decide = (actor, decision, note = null) => W(`select public.fn_approval_decide(
      ${q(ids.req)}, ${q(actor)}, ${q(decision)}, ${note ? q(note) : 'null'}) r`);

  await decide(actors.engineer, 'approved', 'spec checked');
  const afterStep1 = (await R(`select status, current_step, decisions->0->>'by' who, decisions->0->>'by_role' role
      from public.procurement_approval_request where id=${q(ids.req)}`))[0];
  eq('an approval advances current_step and records who decided',
    [afterStep1.status, Number(afterStep1.current_step), afterStep1.who, afterStep1.role],
    ['pending', 2, actors.engineer, 'engineer']);

  let refused = '';
  try { await decide(actors.engineer, 'approved'); } catch (e) { refused = String(e.message); }
  ok('the wrong role cannot decide the next step', /decided by project_manager/.test(refused),
    refused.slice(0, 120) || 'NOT REFUSED');
  eq('a refused decision leaves the chain where it was',
    Number(await one(`select current_step from public.procurement_approval_request where id=${q(ids.req)}`)), 2);

  let stranger = '';
  try { await decide(randomUUID(), 'approved'); } catch (e) { stranger = String(e.message); }
  ok('a non-member cannot decide at all', /not an active member/.test(stranger), stranger.slice(0, 120) || 'NOT REFUSED');

  await decide(actors.project_manager, 'approved');
  // THE SPEC'S OWN EXAMPLE: Engineer approved, Project Manager approved, Finance pending, CEO waiting.
  eq('spec §12 example state reached',
    (await trace()).map((r) => `${r.step_label}:${r.step_status}`),
    ['Engineer:approved', 'Project Manager:approved', 'Finance:pending', 'CEO:waiting']);

  // STEP 3 THROUGH THE ENDPOINT THE PORTAL WILL CALL, as the organization owner.
  const epDecide = await call('procurement_api', user.jwt, { action: 'decide', request_id: ids.req, decision: 'approved', note: 'via endpoint' });
  eq('procurement_api action=decide advances the chain',
    [epDecide.status, epDecide.json?.ok, epDecide.json?.decided_step, epDecide.json?.current_step], [200, true, 3, 4]);
  await decide(actors.ceo, 'approved');
  const done = (await R(`select status, current_step, jsonb_array_length(decisions) nd
      from public.procurement_approval_request where id=${q(ids.req)}`))[0];
  eq('the last step closes the request', [done.status, Number(done.nd)], ['approved', 4]);
  eq('every step reads approved', [...new Set((await trace()).map((r) => r.step_status))], ['approved']);

  const again = (await W(`select public.fn_approval_decide(${q(ids.req)}, ${q(actors.ceo)}, 'approved', null) r`))[0].r;
  eq('a decided request refuses a second decision', [again.ok, again.error], [false, 'already_approved']);

  // ── 3. REJECTION ───────────────────────────────────────────────────────────────────────────
  const b = await mkAward(300000);
  ids.inq2 = b.inq; ids.quote2 = b.quote;
  ids.req2 = await one(`select id from public.procurement_approval_request
      where entity_type='inquiry' and entity_id=${q(ids.inq2)}`);
  ok('a second award raises its own request', !!ids.req2, String(ids.req2));
  await W(`select public.fn_approval_decide(${q(ids.req2)}, ${q(actors.engineer)}, 'rejected', 'over budget') r`);
  const rej = (await R(`select status, current_step from public.procurement_approval_request where id=${q(ids.req2)}`))[0];
  eq('a rejection stops the chain', [rej.status, Number(rej.current_step)], ['rejected', 1]);
  eq('a rejected chain shows the rejected step and blocks the rest',
    (await R(`select step_status from public.v_approval_trace where request_id=${q(ids.req2)} order by step`)).map((r) => r.step_status),
    ['rejected', 'blocked', 'blocked', 'blocked']);

  // ── 4. WHAT THE ENDPOINT READS ─────────────────────────────────────────────────────────────
  const list = await one(`select public.fn_approval_list(${q(ids.cust)})`);
  eq('fn_approval_list returns the org, both policies and both requests',
    [list.organizations.length, list.policies.length, list.requests.length], [1, 2, 2]);
  eq('every request carries its four projected steps',
    list.requests.map((r) => r.steps.length), [4, 4]);
  ok('a request carries the label and per-step state the portal renders',
    list.requests.every((r) => r.steps.every((s) => s.label && s.status)),
    JSON.stringify(list.requests[0].steps.map((s) => `${s.label}:${s.status}`)));

  const stranger2 = await one(`select public.fn_approval_list(${q(randomUUID())})`);
  eq('a customer with no organization gets empty arrays, not an implied chain',
    [stranger2.organizations.length, stranger2.policies.length, stranger2.requests.length], [0, 0, 0]);

  // ── 5. §22 ORDERS: the link, populated by derivation ───────────────────────────────────────
  ids.vendor = (await W(`insert into public.po_vendors(name) values ('QD ${tag} vendor') returning id`))[0].id;
  ids.po = (await W(`insert into public.po_orders(vendor_id, quote_id, subtotal)
      values (${ids.vendor}, ${q(ids.quote)}, 250000) returning id`))[0].id;
  const po = (await R(`select customer_id, inquiry_id, quote_id, project_id
      from public.po_orders where id=${ids.po}`))[0];
  eq('an order naming only a quote is linked to the customer and the inquiry',
    [po.customer_id, po.inquiry_id], [ids.cust, ids.inq]);
  const orders = await one(`select public.fn_customer_orders(${q(ids.cust)})`);
  eq('the customer sees exactly their own order', [orders.length, orders[0]?.inquiry_id], [1, ids.inq]);
  ok('the order payload carries no AP vendor id', !('vendor_id' in (orders[0] || {})), JSON.stringify(Object.keys(orders[0] || {})));
  const none = await one(`select public.fn_customer_orders(${q(randomUUID())})`);
  eq('a customer with no orders gets an empty list', none, []);

  // ── 6. THE ENDPOINT, END TO END ────────────────────────────────────────────────────────────
  const epAppr = await call('procurement_api', user.jwt, { action: 'approvals' });
  eq('procurement_api action=approvals returns this customer chain',
    [epAppr.status, epAppr.json?.organizations?.length, epAppr.json?.policies?.length, epAppr.json?.requests?.length],
    [200, 1, 2, 2]);
  const epTrace = await call('procurement_api', user.jwt, { action: 'trace', request_id: ids.req });
  eq('procurement_api action=trace returns the four named steps',
    [epTrace.status, epTrace.json?.steps?.map((s) => `${s.step_label}:${s.step_status}`)],
    [200, ['Engineer:approved', 'Project Manager:approved', 'Finance:approved', 'CEO:approved']]);
  const epOrders = await call('procurement_api', user.jwt, { action: 'orders' });
  eq('procurement_api action=orders returns this customer own order',
    [epOrders.status, epOrders.json?.orders?.length, epOrders.json?.orders?.[0]?.inquiry_id], [200, 1, ids.inq]);
  const epNoAuth = await call('procurement_api', null, { action: 'approvals' });
  eq('procurement_api refuses a caller with no customer identity', [epNoAuth.status, epNoAuth.json?.error], [401, 'unauthorized']);
  const epStranger = await call('procurement_api', user.jwt, { action: 'trace', request_id: randomUUID() });
  eq("procurement_api refuses another organization's request", [epStranger.status, epStranger.json?.error], [403, 'not your approval request']);
} finally {
  // ── TEARDOWN BY TAG, NOT BY CAPTURED ID ────────────────────────────────────────────────────
  // Three early runs of this file were killed between creating a row and recording its id, and
  // every one of them leaked. Deleting by the tag PATTERN cleans this run and any orphan an
  // earlier one left, which is the only teardown that survives a hard kill.
  const LIKE = "'QD appr%'";
  const MYINQ = `(select id from public.inquiries where raw_input like ${LIKE})`;
  const MYORG = `(select id from public.customer_organization where name like ${LIKE})`;
  const del = [
    ids.po ? `delete from public.po_orders where id=${ids.po}` : `select 1`,
    `delete from public.po_orders where inquiry_id in ${MYINQ}`,
    `delete from public.po_vendors where name like ${LIKE}`,
    `delete from public.procurement_approval_request where organization_id in ${MYORG}`,
    `delete from public.procurement_approval_policy where organization_id in ${MYORG}`,
    `delete from public.customer_organization_member where organization_id in ${MYORG}`,
    `delete from public.customer_organization where name like ${LIKE}`,
    `delete from public.quotes where inquiry_id in ${MYINQ}`,
    `delete from public.company_event where entity_type='inquiry' and entity_id in (select id::text from public.inquiries where raw_input like ${LIKE})`,
    `delete from public.customer_preference where customer_id in (select id from public.customers where email like 'qd-appr%')`,
    `delete from public.inquiries where raw_input like ${LIKE}`,
    `delete from public.customers where email like 'qd-appr%'`,
    `delete from public.leads where company_name like ${LIKE}`,
  ];
  for (const d of del) {
    try { await W(d); } catch (e) { console.log(`  !! teardown step failed: ${d.slice(0, 70)} — ${e.message.slice(0, 160)}`); }
  }
  // The auth identity is not a public table, so it needs its own delete or it becomes one more
  // orphaned auth user of the fifteen this project already has.
  try {
    const { SERVICE } = await keys();
    for (const u of await mgmtRead(STAGE, `select id from auth.users where email like 'qd-appr%@example.com'`, tag)) {
      await fetch(`${BASE}/auth/v1/admin/users/${u.id}`, { method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE } });
    }
  } catch (e) { console.log(`  !! auth teardown failed — ${String(e.message).slice(0, 160)}`); }

  const leaked = await survivors();
  ok('no fixture row survives teardown', leaked.length === 0, leaked.join(', ') || 'clean');
}

console.log(`\n${pass} passed, ${fails.length} failed${fails.length ? ': ' + fails.join('; ') : ''}`);
process.exit(fails.length ? 1 : 0);
