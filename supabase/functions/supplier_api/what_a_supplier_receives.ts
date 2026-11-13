// what_a_supplier_receives — ONE gate for every door through which a customer's request reaches a supplier before a
// reveal: the portal inbox (and the inquiry PDF, which prints the inbox's own row), the new-inquiry e-mail, the edited-
// inquiry e-mail (13 Nov 2026, sales_engineer; founder ruling 1683).
//
// WHY ONE. MEASURED (anonymity audit A, 13 Nov 2026, REPORT_A L3): the new-inquiry e-mail (customer_api/lib/matching.ts)
// ran scrubIdentity with the buyer's NAME only, while the portal ran inboxField with the seed list and the residual
// withhold. Leaked in the e-mail but caught in the portal: the project name ("ZZ DEMO Barsha Garden Villa",
// "re:BarshaGardenVilla"), "Haddad Family Office", "Plot No. 373-4512", "Makani 12345 67890", "Apartment 1204". Two doors
// with two scrubbers is how one of them drifts; every door now calls this.
//
// WHAT IT IS. supplier_api/identity_scrub.ts inboxField (the shared shapes of _shared/identity_text.ts, the buyer's name,
// the seeds, then the residual scan that WITHHOLDS what it cannot prove clean), with two additions:
//  * the customer's stated SITE is a seed (_shared/site_location.ts siteSeeds): "Al Barsha 2" stated in spec.location is
//    removed from the summary, the brief, the BOQ and the e-mail, so an older row is safe on read;
//  * the brief loses its customer-only keys and its address key keeps the emirate (supplierSpec).
// The location-below-the-emirate reducer of the shared text backstop runs inside inboxField, so whatever that list learns
// every door here learns with it.
// prevented by: supplier_api/nothing_below_the_emirate_reaches_a_supplier.test.ts

import { norm, seedTerms } from '../_shared/anonymise.ts';
import { quotationProse } from '../drawing_boq/quotation_gate.ts';
import { siteSeeds, supplierSpec, tidyWithheld } from '../_shared/site_location.ts';
import { inboxField } from './identity_scrub.ts';

/** Who the request belongs to, as the gate needs it. Read under the service role; never placed on a response. */
export type Buyer = { name: string | null; email?: string | null; phone?: string | null; project?: string | null };

/** The seed list of one request: the buyer's name, e-mail, phone and project, and every place word of the stated site. */
export function requestSeeds(buyer: Buyer, spec: unknown): string[] {
  const base = seedTerms({ name: buyer.name || '', email: buyer.email || '', phone: buyer.phone || '', project: buyer.project || '' });
  // the old supplier's names and references a customer's quotation carried (customer-only key, quotation_gate termsToKeep)
  const old = spec && typeof spec === 'object' && Array.isArray((spec as Record<string, unknown>).old_supplier_terms) ? ((spec as Record<string, unknown>).old_supplier_terms as unknown[]).map((t) => norm(String(t ?? ''))).filter((t) => t.length >= 4) : [];
  return [...new Set([...base, ...siteSeeds(spec), ...old])].sort((a, b) => b.length - a.length);
}

/** A request built from a customer's existing quotation: its prose loses money and commercial-terms sentences first. */
export const forSource = (text: string | null | undefined, briefSource: string | null | undefined) => (text != null && briefSource === 'quotation' ? quotationProse(text) : text);

// deno-lint-ignore no-explicit-any
const tidyDeep = (v: any): any => typeof v === 'string' ? tidyWithheld(v) : Array.isArray(v) ? v.map(tidyDeep) : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, tidyDeep(x)])) : v;

/** One customer-authored field (text or JSON) as a supplier receives it: the value, or null with withheld:true. */
export function supplierField<T>(v: T | null | undefined, buyer: Buyer, seeds: string[], hits: string[] = []): { value: T | null; withheld: boolean } {
  const g = inboxField<T>(v, buyer.name, seeds, hits);
  return { value: g.boq == null ? null : tidyDeep(g.boq) as T, withheld: g.withheld };
}

/** The brief (inquiries.spec) as a supplier receives it: customer-only keys out, the address key at the emirate, then the gate. */
export function supplierBrief<T>(spec: T | null | undefined, emirate: string | null | undefined, buyer: Buyer, seeds: string[], hits: string[] = []): { value: T | null; withheld: boolean } {
  return supplierField<T>(spec == null ? spec : supplierSpec(spec, emirate), buyer, seeds, hits);
}

/** A line of free text for an e-mail or a notice: the gated text, or '' when it could not be proved clean. */
export function supplierLine(text: string | null | undefined, buyer: Buyer, seeds: string[]): string {
  if (!text) return '';
  const g = supplierField<string>(String(text), buyer, seeds);
  return g.withheld || !g.value ? '' : String(g.value);
}

/**
 * The new-inquiry e-mail body (customer_api matching.ts matchAndNotify; edit_inquiry sends the same shape). Every
 * customer-authored part goes through the gate; a part that cannot be proved clean is left out and the supplier is told
 * to read the request in the portal. `resolved:false` (the owner could not be read): no customer text at all.
 */
export function newInquiryBody(o: { resolved: boolean; buyer: Buyer; spec: unknown; summary: string | null; budget: string | null; extra: string; category: string; emirate: string | null; briefSource?: string | null }): string {
  const seeds = o.resolved ? requestSeeds(o.buyer, o.spec) : [];
  const cust = (t: string | null | undefined) => (o.resolved ? supplierLine(t, o.buyer, seeds) : '');
  const headline = cust(forSource(o.summary, o.briefSource)) || o.category;
  const budget = cust(o.budget);
  return 'A customer is requesting quotes for: ' + headline + (o.emirate ? ' (' + o.emirate + ')' : '') + (budget ? ' — budget ' + budget : '') + '.' + cust(o.extra) + ' Log in to your QuotesDone supplier portal to quote.';
}

/** What the supplier is told is attached, said of what it is (13 Nov 2026, anonymity audit A, L6: "A drawing with a draft bill
 *  of quantities is attached" was said of another supplier's quotation, and "A redacted drawing" of a BOQ with no drawing). */
export function attachedLine(source: string | null, hasBoq: boolean, hasDrawing: boolean): string {
  if (source === 'quotation') return hasBoq ? ' The items of the customer’s existing quotation are listed on our inquiry: no prices, no names, no references of the old supplier.' : '';
  if (source === 'boq') return hasBoq ? ' The customer’s own bill of quantities is attached (quantities as the customer wrote them, prices removed).' : '';
  if (hasBoq && hasDrawing) return ' A redacted drawing with a draft bill of quantities is attached.';
  if (hasBoq) return ' A draft bill of quantities from the customer’s drawing is attached.';
  return hasDrawing ? ' A redacted drawing is attached.' : '';
}
