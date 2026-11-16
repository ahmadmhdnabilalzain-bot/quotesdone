// supplier_api — the company's people and its account: team, member_invite, member_accept, member_remove, member_phone_code,
// transfer_start, transfer_confirm, close_account, reopen_account, account_closure, customer_not_answering, invitation
// (customer_support + sales_engineer, 16 Nov 2026; agent SUPPLIER_W2; SUPPLIER holes 4, 6 and 10).
//
// Every write is a routine of a_supplier_company_has_members_asks_on_any_channel_and_can_leave.sql, scoped by the company the
// door resolved (never an id from the client) and by the SIGNED-IN address that acts (the owner, or the member himself). The door
// (index.ts) already refused what the role may not do (_shared/supplier_company.ts memberMay); the routines check again.
// prevented by: supplier_api/team.test.ts
import type { Company, CompanyReading } from '../../_shared/supplier_company.ts';
import { type ActionCtx, J, admin } from '../context.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;
export const TEAM_ACTIONS = ['team', 'invitation', 'member_invite', 'member_accept', 'member_remove', 'member_phone_code', 'transfer_start',
  'transfer_confirm', 'close_account', 'reopen_account', 'account_closure', 'customer_not_answering'] as const;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const s = (v: unknown, n = 300) => String(v ?? '').trim().slice(0, n);

export type TeamInput = { action: string; body: Record<string, unknown>; signedIn: string; reading: CompanyReading };

/** One team or account action. [status, answer]; the answer's `error` is a sentence meant for the supplier. */
export async function teamAction(db: Admin, i: TeamInput): Promise<[number, Record<string, unknown>]> {
  const { action, body, signedIn, reading } = i;
  const co: Company | null = reading.company;
  const rpc = async (fn: string, args: Record<string, unknown>) => {
    const { data, error } = await db.rpc(fn, args);
    if (error) throw new Error(fn + ': ' + String(error.message ?? error));
    return (data ?? {}) as Record<string, unknown>;
  };
  const answer = (d: Record<string, unknown>, bad = 400): [number, Record<string, unknown>] => [d.ok ? 200 : bad, d];

  if (action === 'invitation') return [200, { ok: true, invitation: reading.invitation, held: reading.held }];
  if (action === 'member_accept') {
    if (!reading.invitation) return [404, { ok: false, code: 'no_invitation', error: 'There is no invitation waiting for this address.' }];
    return answer(await rpc('fn_supplier_member_accept', { p_email: signedIn, p_phone: body.phone ? s(body.phone, 30) : null }));
  }
  if (!co) return [400, { ok: false, code: 'no_company', error: 'claim your company first' }];
  const lead = co.lead_id;
  if (action === 'team') return [200, { ok: true, me: { role: co.role, email: signedIn }, ...(await rpc('fn_supplier_team', { p_lead: lead })) }];
  if (action === 'member_invite') {
    return answer(await rpc('fn_supplier_member_invite', { p_lead: lead, p_actor: signedIn, p_email: s(body.email, 200), p_role: s(body.role, 20),
      p_name: s(body.name, 120), p_phone: body.phone ? s(body.phone, 30) : null }));
  }
  if (action === 'member_remove') return answer(await rpc('fn_supplier_member_remove', { p_lead: lead, p_actor: signedIn, p_email: s(body.email, 200) }));
  if (action === 'member_phone_code') {
    if (co.role === 'owner') return [400, { ok: false, code: 'owner_number', error: 'The owner\'s WhatsApp number is set in Settings.' }];
    return answer(await rpc('fn_supplier_member_phone_code', { p_email: signedIn }));
  }
  if (action === 'transfer_start') return answer(await rpc('fn_supplier_transfer_start', { p_lead: lead, p_actor: signedIn, p_to: s(body.to, 200) }));
  if (action === 'transfer_confirm') return answer(await rpc('fn_supplier_transfer_confirm', { p_lead: lead, p_actor: signedIn, p_code: s(body.code, 6) }));
  if (action === 'close_account') {
    if (body.quotes !== 'keep' && body.quotes !== 'withdraw') return [400, { ok: false, code: 'choose_quotes', error: 'Choose whether your quotations with customers are withdrawn or kept.' }];
    if (body.confirm !== true) return answer(await rpc('fn_supplier_close_propose', { p_lead: lead, p_actor: signedIn, p_channel: 'portal', p_quotes: body.quotes, p_reason: body.reason ? s(body.reason, 1000) : null }));
    return answer(await rpc('fn_supplier_close_account', { p_lead: lead, p_actor: signedIn, p_channel: 'portal', p_quotes: body.quotes, p_reason: body.reason ? s(body.reason, 1000) : null }));
  }
  if (action === 'reopen_account') return answer(await rpc('fn_supplier_reopen_account', { p_lead: lead, p_actor: signedIn }));
  if (action === 'account_closure') {
    const { data } = await db.from('supplier_account_closure').select('state,quotes,closed_at,outcome').eq('lead_id', lead).order('proposed_at', { ascending: false }).limit(1).maybeSingle();
    const law = await rpc('fn_supplier_what_the_law_keeps', { p_lead: lead });
    return [200, { ok: true, closure: data ?? null, law }];
  }
  if (action === 'customer_not_answering') {
    const inq = s(body.inquiry_id, 40);
    if (!UUID.test(inq)) return [400, { ok: false, code: 'bad_request', error: 'Which request?' }];
    return answer(await rpc('fn_supplier_customer_not_answering', { p_lead: lead, p_actor: signedIn, p_inquiry: inq, p_channel: 'portal', p_note: body.note ? s(body.note, 500) : null }));
  }
  return [400, { ok: false, code: 'unknown_action' }];
}

export async function teamActions(c: ActionCtx): Promise<Response | undefined> {
  if (!(TEAM_ACTIONS as readonly string[]).includes(String(c.action))) return undefined;
  const [status, out] = await teamAction(admin, { action: String(c.action), body: c.body ?? {}, signedIn: c.signedIn ?? c.email, reading: c.reading ?? { company: null, invitation: null, held: null } });
  return J(out, status);
}
