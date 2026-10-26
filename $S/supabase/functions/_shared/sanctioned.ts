// A SANCTIONED PARTY IS INERT ON EVERY SURFACE (founder instruction 516, 18 Sep 2026).
//
// His words were "if any of them is in the sanctions delete that record totally", and then, once it
// was put to him that deleting destroys the proof we screened and frees the name to sign up again:
// "better banned i believe". So the record stays and the party stops — never matched, never
// invited, never messaged, never shown to a customer or another supplier, never able to sign in or
// act.
//
// WHY THIS IS NOT `leads.banned`. leads.banned is also set by fn_ban_overdue_dues and
// fn_fraud_resolve, and those bans are ordinary and reversible: a supplier banned for unpaid dues
// must still be able to sign in and PAY them, which is exactly what supplier_pay is for. Gating
// sign-in on `banned` would lock that supplier out of the only screen that can clear the ban.
// public.sanctions_ban is the narrower fact — permanent, total — and it is what these helpers ask.
//
// The database is the enforcement (public.sanctions_ban, its triggers on leads and notifications).
// These helpers exist so a surface can REFUSE POLITELY and in the right language instead of
// surfacing a 23514 to a stranger, and so sign-in can stop before a session is ever minted.
type Admin = { from: (t: string) => any };

export const SANCTIONED_REFUSAL = {
  error: 'This account is permanently closed and cannot be used.',
  code: 'account_sanctioned',
  message: 'This account is permanently closed. If you believe this is an error, write to management@quotesdone.com.',
};

// A DIFFERENT SENTENCE FOR A DIFFERENT FACT (security review, 18 Sep 2026). The re-registration
// guard matches on a NORMALISED company name, and fn_screening_normalise strips LLC / FZE /
// Trading / Contracting and all punctuation — so two genuinely unrelated companies can collide on
// it. Telling that applicant "this account is permanently closed" is false twice over: they have no
// account, and they did nothing. This copy says only what is true, and names the way out.
export const SANCTIONED_REGISTRATION_REFUSAL = {
  error: 'We cannot create this account automatically.',
  code: 'registration_refused',
  message: 'We could not complete this registration. Please write to management@quotesdone.com and we will finish it with you.',
};

// FAIL CLOSED, LOUDLY (security review, 18 Sep 2026). PostgREST does not THROW on a failed query —
// it resolves { data: null, error }. Reading only `data` therefore turns a connection timeout into
// the answer "not sanctioned", and every gate in the estate opens at once for as long as the read
// keeps failing. Every caller of these helpers already sits inside a try/catch that answers 500, so
// throwing here converts a silent fail-open into a refused request.
function must<T>(r: { data: T | null; error: unknown }, what: string): T {
  if (r.error) throw new Error('sanctions_ban lookup failed (' + what + '): ' + JSON.stringify(r.error));
  return (r.data ?? ([] as unknown as T));
}

/** true when this lead id carries a confirmed sanctions ban. */
export async function sanctionedLead(admin: Admin, leadId: number | string | null | undefined): Promise<boolean> {
  if (leadId == null) return false;
  const r = await admin.from('sanctions_ban').select('lead_id').eq('lead_id', leadId).limit(1);
  return must<Array<unknown>>(r, 'by lead ' + leadId).length > 0;
}

/** the subset of these lead ids that carry a confirmed sanctions ban. */
export async function sanctionedLeads(admin: Admin, ids: Array<number | string>): Promise<Set<string>> {
  if (!ids.length) return new Set();
  const r = await admin.from('sanctions_ban').select('lead_id').in('lead_id', ids);
  return new Set(must<Array<{ lead_id: number }>>(r, 'by lead list').map((x) => String(x.lead_id)));
}

/**
 * true when this e-mail address belongs to a sanctioned party — the account it signed in with, or
 * the contact address on the record. Asked at sign-in, before a session exists, so it cannot go
 * through a lead id.
 */
export async function sanctionedEmail(admin: Admin, email: string | null | undefined): Promise<boolean> {
  const e = String(email || '').trim().toLowerCase();
  if (!e) return false;
  // Two plain equality reads rather than one .or() string: an address is interpolated into a
  // PostgREST filter expression there, and a filter grammar that takes a stranger's input as
  // syntax is the shape of an injection, not a shortcut.
  // Issued together (28 Sep 2026): every supplier_api request waited on the two in turn. Both are
  // still must()-checked, so an unreadable table refuses exactly as before.
  const [a, c] = await Promise.all([
    admin.from('sanctions_ban').select('lead_id').eq('account_email', e).limit(1),
    admin.from('sanctions_ban').select('lead_id').eq('contact_email', e).limit(1),
  ]);
  if (must<Array<unknown>>(a, 'by account e-mail').length) return true;
  return must<Array<unknown>>(c, 'by contact e-mail').length > 0;
}
