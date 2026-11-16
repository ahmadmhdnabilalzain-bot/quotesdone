// deno test --no-lock --node-modules-dir=none supabase/functions/supplier_api/team.test.ts
//
// THE COMPANY'S PEOPLE AND ITS ACCOUNT IN THE PORTAL (16 Nov 2026, SUPPLIER holes 4, 6, 10; agent SUPPLIER_W2). Each action is one
// routine, called with the company the door resolved and the SIGNED-IN address, never an id or an address from the client.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import type { CompanyReading } from '../_shared/supplier_company.ts';
// actions/team.ts sits beside the function's client (context.ts), which needs these at load; nothing here reaches it
Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');
const { TEAM_ACTIONS, teamAction } = await import('./actions/team.ts');

function db(answers: Record<string, unknown> = {}) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return { calls, rpc: (fn: string, args: Record<string, unknown>) => { calls.push({ fn, args }); return Promise.resolve({ data: answers[fn] ?? { ok: true }, error: null }); },
    from: () => ({ select: () => ({ eq: () => ({ order: () => ({ limit: () => ({ maybeSingle: () => Promise.resolve({ data: { state: 'closed' } }) }) }) }) }) }) };
}
const OWNER: CompanyReading = { company: { role: 'owner', lead_id: 5, company_email: 'zz-demo-o@example.invalid', member_email: 'zz-demo-o@example.invalid' }, invitation: null, held: null };
const EST: CompanyReading = { company: { role: 'estimator', lead_id: 5, company_email: 'zz-demo-o@example.invalid', member_email: 'zz-demo-e@example.invalid' }, invitation: null, held: null };
const INVITED: CompanyReading = { company: null, invitation: { member_id: 3, lead_id: 5, company_name: 'ZZ DEMO Co', role: 'estimator', invited_by: 'zz-demo-o@example.invalid', invited_at: '' }, held: null };
const run = (d: ReturnType<typeof db>, action: string, body: Record<string, unknown>, reading: CompanyReading, signedIn = 'zz-demo-o@example.invalid') =>
  teamAction(d, { action, body, signedIn, reading });

Deno.test('the owner invites by the company the door resolved and his own signed-in address; the client cannot name the company', async () => {
  const d = db();
  await run(d, 'member_invite', { email: 'zz-demo-e@example.invalid', role: 'estimator', name: 'ZZ DEMO E', lead_id: 999 }, OWNER);
  assertEquals(d.calls[0].fn, 'fn_supplier_member_invite');
  assertEquals([d.calls[0].args.p_lead, d.calls[0].args.p_actor], [5, 'zz-demo-o@example.invalid']);
});

Deno.test('the invited person accepts with HIS signed-in address; with no invitation he is told so', async () => {
  const d = db();
  await run(d, 'member_accept', {}, INVITED, 'zz-demo-e@example.invalid');
  assertEquals(d.calls[0].args.p_email, 'zz-demo-e@example.invalid');
  const [st, out] = await run(db(), 'member_accept', {}, OWNER);
  assertEquals([st, out.code], [404, 'no_invitation']);
});

Deno.test('the ownership transfer: start names the member, confirm takes the code; both act as the signed-in owner', async () => {
  const d = db();
  await run(d, 'transfer_start', { to: 'zz-demo-e@example.invalid' }, OWNER);
  await run(d, 'transfer_confirm', { code: '123456' }, OWNER);
  assertEquals(d.calls.map((c) => c.fn), ['fn_supplier_transfer_start', 'fn_supplier_transfer_confirm']);
  assertEquals(d.calls[1].args.p_code, '123456');
});

Deno.test('close: he must choose keep or withdraw; without confirm it is a proposal with the law, with confirm it closes', async () => {
  const [st, out] = await run(db(), 'close_account', {}, OWNER);
  assertEquals([st, out.code], [400, 'choose_quotes']);
  const d = db();
  await run(d, 'close_account', { quotes: 'withdraw', reason: 'ZZ DEMO retiring' }, OWNER);
  await run(d, 'close_account', { quotes: 'withdraw', confirm: true }, OWNER);
  assertEquals(d.calls.map((c) => c.fn), ['fn_supplier_close_propose', 'fn_supplier_close_account']);
  assertEquals(d.calls[1].args.p_channel, 'portal');
});

Deno.test('a routine\'s refusal is the supplier\'s sentence with a 400; the estimator acts as himself (the routine refuses an owner step)', async () => {
  const d = db({ fn_supplier_close_account: { ok: false, code: 'owner_only', error: 'Only the company\'s owner can close its account.' } });
  const [st, out] = await run(d, 'close_account', { quotes: 'keep', confirm: true }, EST, 'zz-demo-e@example.invalid');
  assertEquals(st, 400);
  assertMatch(String(out.error), /Only the company's owner/);
  assertEquals(d.calls[0].args.p_actor, 'zz-demo-e@example.invalid');
});

Deno.test('customer not answering: a request id is required, then one routine scoped to the company', async () => {
  assertEquals((await run(db(), 'customer_not_answering', { inquiry_id: 'nope' }, EST))[1].code, 'bad_request');
  const d = db();
  await run(d, 'customer_not_answering', { inquiry_id: '11111111-1111-4111-8111-111111111101', note: 'ZZ DEMO called twice' }, EST, 'zz-demo-e@example.invalid');
  assertEquals([d.calls[0].fn, d.calls[0].args.p_lead, d.calls[0].args.p_channel], ['fn_supplier_customer_not_answering', 5, 'portal']);
});

Deno.test('every team action is listed for the door, and the door no longer offers a false promise on the invitation screen', async () => {
  for (const a of ['team', 'member_invite', 'member_accept', 'transfer_start', 'close_account', 'reopen_account', 'customer_not_answering']) assert((TEAM_ACTIONS as readonly string[]).includes(a));
  const login = await Deno.readTextFile(new URL('../../../src/components/portal/supplier/core/Login.tsx', import.meta.url));
  assert(!/ask them to add you/.test(login) || /Settings, Team/.test(login), 'the screen names where the owner adds him');
});

// W3_PEOPLE, 16 Nov 2026 (wave-3 items 2 and 4): the company's referral link, and a member whose owner has left.
Deno.test('the referral link is the company\'s, read by the company the door resolved; any member may read it', async () => {
  const d = db({ fn_supplier_referral_link: { ok: true, referral_code: 'qdabc123def4', url: 'https://quotesdone.com/en/supplier?utm_content=qdabc123def4' } });
  const [st, out] = await run(d, 'referral_link', { lead_id: 999 }, EST, 'zz-demo-e@example.invalid');
  assertEquals([st, d.calls[0].fn, d.calls[0].args], [200, 'fn_supplier_referral_link', { p_lead: 5 }]);
  assertEquals(out.referral_code, 'qdabc123def4');
  const { VIEWER_MAY } = await import('../_shared/supplier_company.ts');
  assert(VIEWER_MAY.has('referral_link') && VIEWER_MAY.has('ownership_claim'));
});

Deno.test('"our owner has left": the member asks in his own name with his words; the owner keeps it with one press', async () => {
  const d = db({ fn_supplier_ownership_claim_open: { ok: true, claim_id: 9, state: 'open' } });
  const [st] = await run(d, 'ownership_claim', { reason: 'ZZ DEMO the owner left in October', actor: 'zz-demo-o@example.invalid' }, EST, 'zz-demo-e@example.invalid');
  assertEquals(st, 200);
  assertEquals(d.calls[0].args, { p_lead: 5, p_actor: 'zz-demo-e@example.invalid', p_reason: 'ZZ DEMO the owner left in October', p_channel: 'portal' });
  const o = db({ fn_supplier_ownership_claim_object: { ok: true, claim_id: 9, state: 'objected' } });
  await run(o, 'ownership_claim_object', {}, OWNER);
  assertEquals([o.calls[0].fn, o.calls[0].args], ['fn_supplier_ownership_claim_object', { p_lead: 5, p_actor: 'zz-demo-o@example.invalid' }]);
  const { OWNER_ONLY } = await import('../_shared/supplier_company.ts');
  assert(OWNER_ONLY.has('ownership_claim_object'));
  for (const a of ['referral_link', 'ownership_claim', 'ownership_claim_object']) assert((TEAM_ACTIONS as readonly string[]).includes(a), a);
});

Deno.test('the team view says whether a claim on the company is waiting, so the owner sees it and the member sees its state', async () => {
  const d = db({ fn_supplier_team: { owner: null, members: [] } });
  const [, out] = await run(d, 'team', {}, OWNER);
  assert('claim' in out, 'team answers the waiting claim (or null)');
});
