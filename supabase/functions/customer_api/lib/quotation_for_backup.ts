// customer_api — the quotation PDF for the Dropbox backup (it_engineer, 13 Nov 2026; founder ruling 1680). The door in index.ts
// authenticates the caller with the door-only scope DOOR_SCOPES.quotation_for_backup; this renders ONE live quote with buildQuotePdf
// (the portal's own quotation code) into backups/generated/.
//   side 'customer': his request folder's copy, exactly as he is shown it (his own words).
//   side 'supplier': the supplier's Job folder copy. Before a paid reveal the supplier never learns who the customer is, so the request
//     text on it (summary, structured brief, BOQ) goes through the SUPPLIER INBOX'S OWN GATE (supplier_api/identity_scrub.ts inboxField
//     with _shared/anonymise.ts seedTerms of the buyer's name, e-mail, phone and project name): what the supplier portal shows him before
//     the reveal; a field it cannot prove clean is withheld. After the reveal (a transactions row) it is as the customer sees it.
import { isLiveQuote } from '../../_shared/quote_live.ts';
import { seedTerms } from '../../_shared/anonymise.ts';
import { inboxField } from '../../supplier_api/identity_scrub.ts';

/** The scope each internal door of customer_api checks (review of #1997, D2): the backup credential holds only the first. */
export const DOOR_SCOPES = {
  quotation_for_backup: 'customer_api.quotation_for_backup',
  compare_arabic_finish: 'customer_api',
  rematch_waiting: 'customer_api',
} as const;
/** fn_internal_auth's rule, restated for the tests: a credential opens a door when its scope holds '*' or the door's scope exactly. */
export const scopeOpens = (scope: string[], door: keyof typeof DOOR_SCOPES) => scope.includes('*') || scope.includes(DOOR_SCOPES[door]);

export type Buyer = { full_name?: string | null; email?: string | null; phone?: string | null; project?: string | null };
// deno-lint-ignore no-explicit-any
type Inq = Record<string, any>;
export type RequestText = { summary: unknown; spec: unknown; boq: unknown };

/** The request as the supplier inbox serves it before the reveal. */
export function supplierSafeRequest(inq: Inq, buyer: Buyer | null): { inq: Inq; request: RequestText; withheld: string[] } {
  // the buyer could not be read: none of his text goes out (the inbox's rule: withheld rather than emitted unscrubbed)
  if (!buyer) return { inq: { ...inq, summary: null, spec: null, boq: null }, request: { summary: null, spec: null, boq: null }, withheld: ['summary', 'spec', 'boq'] };
  const hits: string[] = [];
  const name = buyer.full_name || null;
  const seeds = seedTerms({ name: name || '', email: buyer.email || '', phone: buyer.phone || '', project: buyer.project || '' });
  const withheld: string[] = [];
  const gate = (k: string) => { const g = inboxField(inq[k] ?? null, name, seeds, hits); if (g.withheld) withheld.push(k); return g.boq; };
  const summary = gate('summary'), spec = gate('spec'), boq = gate('boq');
  return { inq: { ...inq, summary, spec, boq }, request: { summary, spec, boq }, withheld };
}

export type BackupQuoteDeps = {
  // deno-lint-ignore no-explicit-any
  load: (id: string) => Promise<{ q: any; inq: any; buyer: Buyer | null; revealed: boolean } | null>;
  // deno-lint-ignore no-explicit-any
  build: (q: any, inq: any, lang: 'en' | 'ar', target: { bucket: string; folder: string; request?: RequestText }) => Promise<{ j: any; ref: string }>;
};

export async function quotationForBackup(quoteId: string, lang: 'en' | 'ar', deps: BackupQuoteDeps, side: 'supplier' | 'customer' = 'supplier'): Promise<{ status: number; body: Record<string, unknown> }> {
  if (!/^[0-9a-f-]{36}$/i.test(quoteId)) return { status: 400, body: { error: 'bad_request' } };
  const got = await deps.load(quoteId);
  if (!got) return { status: 404, body: { error: 'quote_not_found' } };
  if (!isLiveQuote(got.q.status)) return { status: 409, body: { error: 'not_a_live_quote' } };
  let inq = got.inq;
  let target: { bucket: string; folder: string; request?: RequestText } = { bucket: 'backups', folder: 'generated' };
  if (side === 'supplier' && !got.revealed) {
    const safe = supplierSafeRequest(got.inq, got.buyer);
    inq = safe.inq; target = { ...target, request: safe.request };
  }
  const { j, ref } = await deps.build(got.q, inq, lang, target);
  // an Arabic copy held for translation, or an unread reveal rate: no file, the row retries
  if (!j?.ok || !j.path) return { status: 503, body: { error: String(j?.error || (j?.held ? 'held' : 'pdf_failed')) } };
  return { status: 200, body: { ok: true, bucket: String(j.bucket || 'backups'), path: String(j.path), ref, side } };
}
