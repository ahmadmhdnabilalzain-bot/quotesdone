// _shared/own_request_facts.ts — A CUSTOMER IS ANSWERED FROM HIS WHOLE REQUEST, ON EVERY CHANNEL (customer_support, 16 Nov 2026).
//
// The founder (ledger 1711): a customer told the sales engineer his budget in the request chat, then asks on WhatsApp "What
// happened with my inquiry? Did you find anyone below 5,000?" — "I don't want the system to be rule-based only, like 1 + 1 = 2.
// No, it's scenarios". So the database supplies the facts and the model reasons over them: public.fn_customer_inquiry_facts
// (scripts/sql/a_customer_is_answered_from_his_whole_request_on_every_channel.sql) gives each request what he asked (`asked`,
// `changes_he_sent_after`) and each live quote what his portal shows him (`quotes`, `comparison`), and this file holds the two
// things every channel that hands those facts to a model shares:
//   OWN_REQUEST_RULE          what the model is told to do with them (WhatsApp wa_inbound/compose.ts, the widget and the
//                             signed-in site chat site_assistant/turn_facts.ts, the portal chat sales_engineer/actions/portal.ts,
//                             the e-mail reply email_triage/account_facts.ts). No intent row, no keyword route, no comparison
//                             in code: "anyone below 5,000?" is answered by the model from complete facts.
//   generaliseOwnRequestFacts the code generaliser (_shared/quote_generalise.ts: the known-brand table, model numbers, contact
//                             shapes) over a sealed quote's own short words before any model reads them. The SQL already masks
//                             the supplier's own name, its own brand and model values and contacts; this is the second layer
//                             the portal applies to the same fields (customer_api my_inquiries generaliseQuoteTerms).
// prevented by: _shared/own_request_facts.test.ts
import { generaliseText } from './quote_generalise.ts';

export const OWN_REQUEST_RULE = 'HIS OWN REQUESTS. His own record in these facts is the only source for anything about his requests. '
  + 'Each request carries `asked`: what he told us when he made it (his budget exactly as he wrote it, the date he needs it by and his words for it, '
  + 'the emirate and his site, the materials and brands he asked for, the alternatives he accepted), and `changes_he_sent_after`. Each live quote '
  + 'carries what his portal shows him: its letter, its price before VAT and with VAT as the supplier stated it, how long it is valid, its lead time and '
  + 'warranty as stated, the sales engineer\'s notes against his request, and `questions_and_answers` (what that supplier asked him and what '
  + 'he answered); `comparison` is the comparison report his portal shows. Give amounts as `price_as_shown` writes them (AED and the figure). '
  + 'Answer any question about his own request by reasoning over these: a price against his budget (say whether you compare before or with VAT, '
  + 'following how he stated his budget), who can deliver by a date (from the lead times; one that is not stated is not stated), which quote matches '
  + 'a brand he asked for (before the reveal no brand is named: say what the notes say and that the exact brand shows after the reveal), what is still '
  + 'missing, what happens next. Never ask again for what `asked` already holds. Never state a price, date, count or brand the record does not hold, '
  + 'and with no quote yet say so and when quotes are due. Quotes are in AED: a budget in US dollars converts at the fixed 3.6725 dirhams to the dollar; '
  + 'for any other currency give the AED figure and never present a conversion as exact. Before a reveal a quote is its letter and its price: never a '
  + 'supplier\'s name, contact or brand. A change he asks for (a new budget, more units, a different date) or a cancel is a change to his request: '
  + 'never say it is done or that suppliers were told unless the facts on this turn say so.';

const SEALED_WORDS = ['lead_time_as_stated', 'warranty_as_stated', 'validity_as_stated'] as const;

/** A copy of the facts in which every SEALED quote's own short words have passed the code generaliser. Revealed quotes,
 *  prices, letters and everything else are unchanged. Accepts any shape (a fact pack, an own record, a request list). */
export function generaliseOwnRequestFacts<T>(v: T): T {
  const walk = (x: unknown): unknown => {
    if (Array.isArray(x)) return x.map(walk);
    if (!x || typeof x !== 'object') return x;
    const o = x as Record<string, unknown>;
    const out: Record<string, unknown> = {};
    for (const [k, val] of Object.entries(o)) out[k] = walk(val);
    if (Array.isArray(o.quotes)) {
      out.quotes = (o.quotes as unknown[]).map((q) => {
        if (!q || typeof q !== 'object' || (q as Record<string, unknown>).revealed === true) return walk(q);
        const c = walk(q) as Record<string, unknown>;
        for (const f of SEALED_WORDS) if (typeof c[f] === 'string') c[f] = generaliseText(c[f]).text;
        if (Array.isArray(c.questions_and_answers)) {
          c.questions_and_answers = (c.questions_and_answers as Record<string, unknown>[]).map((x) =>
            x && typeof x.supplier_asked === 'string' ? { ...x, supplier_asked: generaliseText(x.supplier_asked).text } : x);
        }
        return c;
      });
    }
    return out;
  };
  return walk(v) as T;
}

/** The own record with its request list replaced by a pointer, when the same list rides in the fact pack (WhatsApp sends
 *  both; one copy is enough and the other doubled every customer's prompt). */
export function withoutDuplicateRequests(mine: Record<string, unknown>, pack: unknown): Record<string, unknown> {
  const reqs = (pack as { identity?: { requests?: unknown } } | null)?.identity?.requests;
  return Array.isArray(reqs) && Array.isArray(mine.inquiries) ? { ...mine, inquiries: 'the same requests as FACT PACK identity.requests below' } : mine;
}

/** THE PORTAL CHAT SEES WHAT THE OTHER DOORS SEE (16 Nov 2026, who-knows-what audit gap 3). The customer portal chat read only
 *  his quotes (sales_engineer/lib/own_quotes.ts), so it was blind to his refunds, the reveal fee he paid, his invoice and what
 *  was said on WhatsApp, which the widget reads for the same person (site_assistant/index.ts: fn_wa_context and
 *  fn_contact_timeline). This is that reading's text for the portal: his account and profile (fn_wa_context; the requests
 *  are left out because own_quotes already gives them with what he asked) and his case timeline (every channel and seat,
 *  newest first: requests, quotes, reveals, invoices, refunds and the CEO's decisions, messages). '' when nothing was read. */
export function customerRecordFacts(live: Record<string, unknown> | null, events: unknown): string {
  const out: string[] = [];
  if (live && live.known === true) {
    const { inquiries: _drop, ...rest } = live;
    out.push('HIS ACCOUNT (scoped in SQL to him alone; his requests and quotes are given above):\n' + JSON.stringify(rest));
  }
  if (Array.isArray(events) && events.length) {
    out.push('HIS CASE TIMELINE (newest first; every channel and every seat: reveals, invoices, refunds and their decisions, WhatsApp and '
      + 'e-mail messages; his only). Never contradict it, and never tell him something is pending that it shows as done:\n' + JSON.stringify(events).slice(0, 8000));
  }
  return out.join('\n\n');
}
