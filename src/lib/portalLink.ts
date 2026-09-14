// The portal's deep link to one request and one quote: /me?request=<inquiry_id>&quote=<quote_id>
// (or /ar/me?... for Arabic). 14 Sep 2026, agent: ceo.
//
// The comparison report and the quotation PDF link each quote to this URL. Before, every row in
// "All quotes received" linked to /me and nothing more, because the portal had no URL that opens
// one quote. The link carries ids only. The portal looks for them inside the customer's own
// my_inquiries answer, and customer_api filters that by the signed-in customer, so an id from
// another account resolves to nothing and the portal says the quote is not on this account.
//
// No imports and erasable-only TypeScript, so `node --test` runs it directly. The edge functions
// build the same URL in supabase/functions/_shared/site_origins.ts (portalLink); both are checked
// against the same literal in their tests.

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** The portal URL for a request and, optionally, one of its quotes. */
export function quoteLink(origin: string, lang: string, requestId: string, quoteId?: string): string {
  const qs = new URLSearchParams({ request: String(requestId) });
  if (quoteId) qs.set('quote', String(quoteId));
  return String(origin).replace(/\/+$/, '') + (lang === 'ar' ? '/ar/me' : '/me') + '?' + qs.toString();
}

export type DeepLink = { request: string; quote: string };

/**
 * Reads request/quote from a query string. null when neither is present. A value that is not a
 * uuid comes back as '' so the caller can show "not on your account" and never look it up.
 */
export function parseQuoteLink(search: string): DeepLink | null {
  const qs = new URLSearchParams(search || '');
  const r = qs.get('request'), q = qs.get('quote');
  if (r == null && q == null) return null;
  const ok = (v: string | null) => (v && UUID.test(v.trim()) ? v.trim().toLowerCase() : '');
  return { request: ok(r), quote: ok(q) };
}

type Inq = { id: unknown; quotes?: Array<{ id: unknown }> | null; children?: Inq[] | null };

/**
 * Finds the linked quote in the customer's own requests (combined projects included).
 * The request must hold the quote; a request link with no quote opens the request.
 */
export function resolveQuoteLink(inquiries: Inq[] | null | undefined, link: DeepLink): { inquiryId: string; quoteId: string } | null {
  if (!link.request && !link.quote) return null;
  const all: Inq[] = [];
  const walk = (xs: Inq[] | null | undefined) => { for (const i of xs || []) { all.push(i); walk(i.children); } };
  walk(inquiries);
  for (const i of all) {
    const iid = String(i.id).toLowerCase();
    if (link.request && iid !== link.request) continue;
    if (!link.quote) return { inquiryId: String(i.id), quoteId: '' };
    const q = (i.quotes || []).find((x) => String(x.id).toLowerCase() === link.quote);
    if (q) return { inquiryId: String(i.id), quoteId: String(q.id) };
  }
  return null;
}
