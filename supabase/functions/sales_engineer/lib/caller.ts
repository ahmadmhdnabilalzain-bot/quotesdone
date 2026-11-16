// sales_engineer — who is calling: the credential decides the seat, a portal customer is a third kind of caller, a service
// caller a fourth and SERVICE_ACTIONS is the whole of what it may reach.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 1,214-line index.ts split into modules, a pure move).
import { requireInternal } from '../../_shared/internal_auth.ts';
import { adminCaller, type TwoStepBody } from '../../_shared/admin_session.ts';
import { admin, sec } from '../context.ts';

// THE CREDENTIAL DECIDES THE SEAT, NOT THE CALLER. Same rule as ceo_agent, and written this way from
// the first line rather than retrofitted: ceo_agent shipped on 8 Sep reading `body.as` and believing
// it, which let any holder of an in-scope credential present as the CEO. An unrecognised context is
// refused rather than defaulted.
export const SEAT_BY_CREDENTIAL: Record<string, 'sales_engineer'> = {
  'fn.sales_engineer': 'sales_engineer',
};

// A PORTAL CALLER IS A THIRD KIND OF CALLER, and it is the one the founder's 9 Sep ruling adds:
// "if its on the home page then the support replies. but if its on the customer or supplier portal
// then its the sales engineer". PortalShell already sends the customer's own session token; this
// resolves it to a customer row and NOTHING WIDER. `customer` may read its own report and ask its
// own questions; it may not name another party. Note customers.id is NOT auth.users.id (measured 9
// Sep: the one real customer's id does not exist in auth.users) — the verified JWT email is the
// join, which is the same identity rule the estate already uses: a phone may confirm, never select.
//
// A FOURTH KIND IS A SERVICE CALLER. customer_api hands this seat the matching decision on the
// create_inquiry path (the founder, 9 Sep: "match capability is the sales engineer task"). It
// presents ITS OWN credential — fn.customer_api — and must not therefore become the seat: the work
// is still performed AS sales_engineer (grant checked, agent_runs row written) but the CALLER is
// recorded as what it is. SERVICE_ACTIONS is the whole of what a service caller may reach, so a
// widened credential scope cannot quietly hand customer_api the grant ledger or the sector
// catalogue as well.
// spec_offer_sweep: resilience_ping's daily pass (founder_instruction #321). The work is sales_engineer's
// (detect, decide); every message goes out through customer_support's door (_shared/deliver.ts).
export const SERVICE_ACTIONS = new Set(['match', 'spec_offer_sweep', 'supplier_loops_sweep']);
export type Caller =
  | { kind: 'sales_engineer' | 'founder' }
  | { kind: 'service'; context: string }
  | { kind: 'customer'; customerId: string; email: string }
  | { kind: 'two_step_required'; body: TwoStepBody }
  | null;

export async function whoami(req: Request, body: Record<string, unknown>): Promise<Caller> {
  if (body?.__secret) {
    const r = await requireInternal(admin, String(body.__secret), 'sales_engineer');
    if (r.ok && SEAT_BY_CREDENTIAL[r.context]) return { kind: 'sales_engineer' };
    if (r.ok) return { kind: 'service', context: r.context };
  }
  // The JWT half goes through the one admin door (_shared/admin_session.ts): admin_emails AND an aal2 session. An
  // admin whose session has one factor is answered 403 naming the step (security audit 10 Nov 2026, item 1).
  const a = await adminCaller(admin, sec, req.headers.get('Authorization'));
  if (a.kind === 'two_step_required') return { kind: 'two_step_required', body: a.body };
  if (a.kind === 'admin') return { kind: 'founder' };
  if (a.kind !== 'not_admin') return null;
  const email = a.email;
  const { data: cust } = await admin.from('customers').select('id').ilike('email', email).maybeSingle();
  return cust?.id ? { kind: 'customer', customerId: String(cust.id), email } : null;
}
