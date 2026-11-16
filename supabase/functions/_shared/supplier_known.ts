// THE SUPPLIER IS KNOWN ON EVERY CHANNEL (customer_support, 16 Nov 2026; founder ledgers 1711-1713: "in a real company
// everyone knows what the other is doing because they are colleagues").
//
// The audit of that day (who knows what, items 5-7) found three supplier doors that did not know the supplier: the supplier
// branch of fn_wa_context had no trades, services or emirates, so "why am I getting no jobs?" had no answer anywhere; the
// e-mail reply (email_triage/account_facts.ts) read leads and inquiry_matches itself and never saw his approval, licence or
// holds; and the portal quotation chat (supplier_api reviewVoice) knew the job only, so it could say a quotation was ready
// to submit while WhatsApp had told him his licence expired.
//
// ONE READING, rendered once. fn_wa_context('supplier', <his e-mail>) is what WhatsApp (wa_inbound/identify.ts) and the
// signed-in widget (site_assistant) already hand their model; since the_supplier_is_known_on_every_channel.sql it carries
// his trades, services and emirates, jobs in 30 days and why not more (matching.why_no_jobs, each an existing matcher rule).
// The e-mail reply and the quotation chat read the same row through readSupplier and word it through supplierStanding, and
// WhatsApp and the widget add the same words beside the JSON they already send. Nothing here reads another party: the row
// is scoped in SQL to the one supplier, and it names no other supplier and no customer.
// prevented by: _shared/supplier_known.test.ts, email_triage/account_facts.test.ts, supplier_api/the_supplier_is_known_in_the_quotation_chat.test.ts
// deno-lint-ignore no-explicit-any
type Db = any;
// deno-lint-ignore no-explicit-any
export type SupplierReading = Record<string, any>;

/** fn_wa_context('supplier', email): his own account as every channel reads it. null when unknown or the read fails. */
export async function readSupplier(admin: Db, email: string): Promise<SupplierReading | null> {
  const e = String(email || '').trim().toLowerCase();
  if (!e || !e.includes('@')) return null;
  try {
    const { data, error } = await admin.rpc('fn_wa_context', { p_audience: 'supplier', p_phone: e });
    if (error || !data || typeof data !== 'object' || (data as SupplierReading).known !== true) return null;
    return data as SupplierReading;
  } catch (_e) { return null; }
}

/** His collaboration rows on the shared timeline (fn_contact_timeline kind 'collaboration'), newest first. [] on failure. */
export async function readCollaborationRows(admin: Db, email: string, max = 6): Promise<{ at?: string; summary?: string }[]> {
  const e = String(email || '').trim().toLowerCase();
  if (!e) return [];
  try {
    const { data, error } = await admin.rpc('fn_contact_timeline', { p_contact: e, p_limit: 40 });
    const ev = !error && Array.isArray(data?.events) ? data.events : [];
    return ev.filter((x: { kind?: string }) => x?.kind === 'collaboration').slice(0, max);
  } catch (_e) { return []; }
}

const day = (s: unknown) => (s ? String(s).slice(0, 10) : '');
const list = (a: unknown) => (Array.isArray(a) ? a.map((x) => String(x)).filter(Boolean) : []);

export const STANDING_RULE = 'Answer his questions about his account, his licence, his trades and emirates, the requests he receives and '
  + '"why am I getting no jobs" from this, and never contradict it on any channel. If his licence has expired, his registration is not '
  + 'approved, or requests are paused, say so plainly with the step it names before anything else, and never tell him he is verified, '
  + 'ready to submit, or will receive requests while it says otherwise: a quotation can be sent only while his registration is approved. '
  + 'Never name another supplier or a customer, and never promise requests: they go to the suppliers whose confirmed services and emirates fit each request.';

/** His standing in plain words (English: the model writes the reply in his language). '' when there is no reading. */
export function supplierStanding(r: SupplierReading | null): string {
  if (!r || r.known !== true || r.scope !== 'supplier') return '';
  const p = r.profile || {}; const s = r.services; const m = r.matching;
  const out: string[] = [];
  const reg = p.approval_status === 'approved' ? 'approved' : `not approved yet (status: ${p.approval_status || 'not submitted'}${p.blocked_because ? '; held for: ' + p.blocked_because : ''})`;
  let lic = p.trade_licence_no ? `Trade licence ${p.trade_licence_no}` : 'Trade licence: none read yet';
  if (p.licence_expiry) {
    const left = Number(p.licence_days_left);
    lic += `, expiry ${day(p.licence_expiry)}` + (p.licence_expired === true ? ` - EXPIRED${Number.isFinite(left) ? ' ' + Math.abs(left) + ' day(s) ago' : ''}` : Number.isFinite(left) ? ` (${left} day(s) left)` : '');
  }
  out.push(`- Registration ${reg}; licence ${p.verified ? 'verified' : 'not verified'}. ${lic}.`);
  if (s) {
    const trades = Array.isArray(s.trades) ? s.trades.map((t: { label?: string; code?: string; open_to_customers?: boolean }) =>
      `${t.label || t.code} (${t.open_to_customers ? 'open to customers' : 'not open to customers yet'})`) : [];
    out.push(`- Trades on his profile${s.confirmed ? ' (confirmed)' : ' (NOT confirmed in the Services tab)'}: ${trades.length ? trades.join(', ') : 'none'}.`
      + (list(s.services).length ? ` Services: ${list(s.services).join(', ')}.` : '')
      + (list(s.trades_excluded).length ? ` Trades he excluded: ${list(s.trades_excluded).join(', ')}.` : ''));
    out.push(`- Emirates he covers: ${list(s.emirates_covered).length ? list(s.emirates_covered).join(', ') : 'all of the UAE (none stated)'}.`);
  }
  if (m) {
    out.push(`- Requests: ${Number(m.jobs_sent_30d || 0)} sent to him in the last 30 days; ${Number(m.requests_in_his_trades_30d || 0)} posted by customers in his trades and emirates in that time. `
      + `Receives requests now: ${m.receives_requests_now ? 'yes' : 'NO'}.`);
    const why = Array.isArray(m.why_no_jobs) ? m.why_no_jobs.map((w: { says?: string }) => String(w?.says || '')).filter(Boolean) : [];
    if (why.length) out.push('- Why not more requests:\n' + why.map((w: string) => '  * ' + w).join('\n'));
    const c = m.collaboration || {};
    if (Number(c.unanswered_in_a_row || 0) > 0 || c.on_hold) {
      out.push(`- Collaboration: ${Number(c.unanswered_in_a_row || 0)} quotation(s) in a row left unanswered at the customer's decision`
        + (c.warned_at ? `; warned ${day(c.warned_at)}` : '') + (c.on_hold ? `; requests on hold since ${day(c.held_at) || 'recently'}` : '') + '.');
    }
  } else if (r.work) {
    out.push(`- Requests received in total: ${Number(r.work.inquiries_received || 0)}; quoted: ${Number(r.work.inquiries_quoted || 0)}.`);
  }
  return `HIS OWN ACCOUNT, AS EVERY CHANNEL READS IT (the same reading WhatsApp and the website give him${r.company ? '; ' + r.company : ''}):\n`
    + out.join('\n') + '\n' + STANDING_RULE;
}

/** His recent jobs (fn_wa_context recent_jobs), each with HIS OWN quote only. null when the reading carries none. */
export function recentJobs(r: SupplierReading | null): { job: unknown; trade?: string; emirate?: string; sent_at?: string; job_status?: string; my_quote?: string | null }[] | null {
  return r && Array.isArray(r.recent_jobs) ? r.recent_jobs : null;
}

/** The quotation chat's and the e-mail reply's facts about him: the standing, then his collaboration rows. '' when unknown. */
export async function supplierKnownFacts(admin: Db, email: string): Promise<string> {
  const [r, rows] = await Promise.all([readSupplier(admin, email), readCollaborationRows(admin, email)]);
  const st = supplierStanding(r);
  if (!st) return '';
  return st + (rows.length ? '\nHIS COLLABORATION RECORD ON THE SHARED TIMELINE (newest first): ' + rows.map((x) => `${day(x.at)} ${String(x.summary || '')}`.trim()).join('; ') + '.' : '');
}

/** The quotation review's facts with his own account after them (the job first: the job number `must` is read from it). */
export function withSupplierKnown(situation: string, known: string): string {
  return known ? situation + '\n\n' + known : situation;
}
