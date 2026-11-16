// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/supplier_company.test.ts
//
// A SUPPLIER COMPANY HAS MEMBERS (16 Nov 2026, SUPPLIER hole 4; agent SUPPLIER_W2). Before: one e-mail per company; the estimator's
// e-mailed quotation was "unverified", WhatsApp knew one number, the portal promised "ask them to add you" with no way to do it.
// This proves the one reading every door uses (companyOf), what each role may do, and that each door resolves a member.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { companyOf, memberMay, memberMayInstruct, OWNER_ONLY, VIEWER_MAY, waSenderRole } from './supplier_company.ts';
import { verifiedSender } from '../resend_inbound/quote_by_email.ts';

const rpcAnswer = (data: unknown, error: unknown = null) => ({ rpc: () => Promise.resolve({ data, error }) });

Deno.test('companyOf: owner, member, invitation, held, and nothing when the routine is missing (the address reads as itself)', async () => {
  const owner = await companyOf(rpcAnswer({ role: 'owner', lead_id: 5, company_email: 'zz-demo-o@example.invalid', member_email: 'zz-demo-o@example.invalid' }), 'ZZ-DEMO-O@example.invalid');
  assertEquals(owner.company?.role, 'owner');
  const est = await companyOf(rpcAnswer({ role: 'estimator', lead_id: 5, company_email: 'zz-demo-o@example.invalid', member_email: 'zz-demo-e@example.invalid' }), 'zz-demo-e@example.invalid');
  assertEquals([est.company?.role, est.company?.company_email], ['estimator', 'zz-demo-o@example.invalid']);
  const inv = await companyOf(rpcAnswer({ invitation: { member_id: 3, lead_id: 5, company_name: 'ZZ DEMO Co', role: 'viewer' } }), 'zz-demo-v@example.invalid');
  assertEquals([inv.company, inv.invitation?.role], [null, 'viewer']);
  const held = await companyOf(rpcAnswer({ held: { company_name: 'ZZ DEMO Co', why: 'screening' } }), 'zz-demo-h@example.invalid');
  assertEquals([held.company, held.held?.why], [null, 'screening']);
  const missing = await companyOf(rpcAnswer(null, { message: 'function does not exist' }), 'zz-demo-x@example.invalid');
  assertEquals(missing, { company: null, invitation: null, held: null });
});

Deno.test('roles: the owner does all; an estimator quotes but never changes the company, its team or its account; a viewer reads', () => {
  for (const a of ['submit_quote', 'review_message', 'decline_request', 'customer_not_answering', 'inbox']) assert(memberMay('estimator', a).ok, a);
  for (const a of ['save_profile', 'member_invite', 'transfer_start', 'close_account', 'set_availability', 'pay_registration', 'remove_work', 'upload_url', 'process_docs']) {
    const m = memberMay('estimator', a); assertEquals(m.ok ? null : m.code, 'owner_only', a);
  }
  for (const a of ['inbox', 'inquiry_detail', 'team', 'member_phone_code']) assert(memberMay('viewer', a).ok, a);
  for (const a of ['submit_quote', 'decline_request', 'customer_not_answering', 'review_message']) { const m = memberMay('viewer', a); assertEquals(m.ok ? null : m.code, 'read_only', a); }
  for (const a of [...OWNER_ONLY, 'submit_quote']) assert(memberMay('owner', a).ok);
  for (const a of OWNER_ONLY) assert(!VIEWER_MAY.has(a), 'a viewer may never take an owner-only action: ' + a);
});

Deno.test('instructions by e-mail or WhatsApp follow the same roles', () => {
  assert(memberMayInstruct('estimator', 'job_question') && memberMayInstruct('estimator', 'customer_silent') && memberMayInstruct('estimator', 'not_for_me'));
  assert(!memberMayInstruct('estimator', 'close_account') && !memberMayInstruct('estimator', 'remove_work') && !memberMayInstruct('estimator', 'answer_yes'));
  assert(!memberMayInstruct('viewer', 'job_question') && memberMayInstruct('viewer', 'paid_leads'));
  assert(memberMayInstruct('owner', 'close_confirm'));
});

Deno.test('the e-mail door: an estimator\'s own authenticated address may send the company\'s quotation; a viewer\'s or a spoofed one may not', () => {
  const lead = { id: 5, claimed_by: 'zz-demo-o@example.invalid', email: 'info@example.invalid', company_name: 'ZZ DEMO Co' } as never;
  assertEquals(verifiedSender(lead, 'zz-demo-e@example.invalid', true, false), false, 'before: a colleague\'s address was unverified');
  assertEquals(verifiedSender(lead, 'zz-demo-e@example.invalid', true, false, true), true);
  assertEquals(verifiedSender(lead, 'zz-demo-e@example.invalid', false, false, true), false, 'never without the receiving server\'s authentication');
  assertEquals(verifiedSender(lead, 'zz-demo-o@example.invalid', true, false), true);
});

Deno.test('the WhatsApp door: a member\'s confirmed number carries his role; otherwise the number is the owner\'s', async () => {
  assertEquals((await waSenderRole(rpcAnswer({ role: 'estimator', email: 'zz-demo-e@example.invalid', name: 'ZZ DEMO E' }), '+971500000881')).role, 'estimator');
  assertEquals((await waSenderRole(rpcAnswer(null), '+971500000882')).role, 'owner');
});
