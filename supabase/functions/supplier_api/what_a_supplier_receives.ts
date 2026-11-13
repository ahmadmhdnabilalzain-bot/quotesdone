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
//
// EVERY DOOR A SUPPLIER'S TOKEN REACHES THAT CARRIES INQUIRY TEXT (enumerated 13 Nov 2026 from production pg_proc and views, SELECT
// only, and from the edge functions a supplier signs in to; checked again by the second review of F2):
//   GATED here: supplier_api inbox (and inquiry_pdf / inquiry_documents / the review doors, which read it), new_inquiry and
//     job_awarded_other e-mails (customer_api matching.ts), rfq_note and add_missing_specs (inquiry_lifecycle.ts), clarify_answer
//     (messages_api) and its English replay (_shared/supplier_english.ts finishEnglish), quote_extract's context (quotes.ts).
//   TRADE + EMIRATE + JOB NUMBER ONLY before a reveal: supplier_portal workspaces, opportunities, quote_recommend
//     (supplier_portal/before_reveal.ts; scripts/sql/before_a_reveal_a_supplier_portal_title_is_the_trade_and_the_emirate.sql).
//     WhatsApp new_inquiry carries its fixed subject only (send_whatsapp templates.ts varsFor).
//   NOT A SUPPLIER DOOR: of the 45 routines and 13 views that read inquiry text, none is executable or selectable by anon or
//     authenticated. Routines that ARE executable by those roles carry no inquiry text: fn_marketplace_analytics, fn_ops_metrics
//     and fn_strategy_metrics (anon; security invoker, aggregate counts) and fn_customer_document_refs (authenticated; the
//     customer's own documents, used by the documents RLS policy). fn_supplier_product_match hands its `want` text to the model
//     only and returns product ids; fn_supplier_twin / advisor / products return counts; fn_contact_timeline and fn_wa_context
//     give a supplier contact his own transactions only.

import { norm, redactBoq, seedTerms } from '../_shared/anonymise.ts';
import { isQuotationReading, quotationGate, quotationProse } from '../drawing_boq/quotation_gate.ts';
import { revealedSpec, siteSeeds, supplierSpec, tidyWithheld } from '../_shared/site_location.ts';
// the customer's notice when his words are kept from the suppliers lives with the site contract (customer-facing Arabic)
export { KEPT_FROM_SUPPLIERS, keptNotice } from '../_shared/site_location.ts';
import { inboxBoq, inboxField, scrubDeep } from './identity_scrub.ts';
import * as identityText from '../_shared/identity_text.ts';

// A SEED THAT IS ONLY A PLACE IS REDUCED, NOT PAINTED (13 Nov 2026, with the text-side branch's place reducer): a stored site
// ("al barsha 2") left to the shared reducer reads "in Dubai" instead of a gap. Read OPTIONALLY, the way the drawing branch reads
// locationBelowEmirate: when _shared/identity_text.ts exports `reducibleSeed` it is used; absent, every seed is painted as
// before. A seed it calls reducible is not painted here, so the reducer inside inboxField (scrubDeep, run first) owns it.
const REDUCIBLE = (identityText as Record<string, unknown>).reducibleSeed as ((seed: string) => boolean) | undefined;
/** The seeds this door paints: all of them, less those the shared reducer turns into the emirate. */
export function seedsToPaint(seeds: string[], reducible: ((seed: string) => boolean) | undefined = REDUCIBLE): string[] {
  if (typeof reducible !== 'function') return seeds;
  return seeds.filter((sd) => { try { return !reducible(sd); } catch (_e) { return true; } });
}
export const placeReducerPresent = typeof REDUCIBLE === 'function';

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
const tidyDeep = (v: any, em?: string | null): any => typeof v === 'string' ? tidyWithheld(v, em) : Array.isArray(v) ? v.map((x) => tidyDeep(x, em)) : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, tidyDeep(x, em)])) : v;

/** One customer-authored field (text or JSON) as a supplier receives it: the value, or null with withheld:true. With the
 *  emirate, a withheld place at the end of a phrase reads "in <emirate>" ("Renovation of two bathrooms in Dubai"). */
export function supplierField<T>(v: T | null | undefined, buyer: Buyer, seeds: string[], hits: string[] = [], emirate?: string | null): { value: T | null; withheld: boolean } {
  const g = inboxField<T>(v, buyer.name, seedsToPaint(seeds), hits);
  return { value: g.boq == null ? null : tidyDeep(g.boq, emirate) as T, withheld: g.withheld };
}

/** The brief (inquiries.spec) as a supplier receives it: customer-only keys out, the address keys reduced, then the gate. */
export function supplierBrief<T>(spec: T | null | undefined, emirate: string | null | undefined, buyer: Buyer, seeds: string[], hits: string[] = []): { value: T | null; withheld: boolean } {
  return supplierField<T>(spec == null ? spec : supplierSpec(spec, emirate), buyer, seeds, hits, emirate);
}

/** A line of free text for an e-mail or a notice: the gated text, or '' when it could not be proved clean. */
export function supplierLine(text: string | null | undefined, buyer: Buyer, seeds: string[], emirate?: string | null): string {
  if (!text) return '';
  const g = supplierField<string>(String(text), buyer, seeds, [], emirate);
  return g.withheld || !g.value ? '' : String(g.value);
}

/** WHY a text cannot be sent as written, in words the customer can act on: the parts of it the gate would remove. */
export function heldParts(text: string, buyer: Buyer, seeds: string[]): string[] {
  const r = redactBoq(scrubDeep(String(text), buyer.name, []) as string, seeds);
  const named = r.reasons.filter((x) => x.startsWith('seed:')).map((x) => x.slice(5));
  const shapes = r.reasons.filter((x) => x.startsWith('pattern:')).map((x) => x.slice(8).replace(/_/g, ' '));
  return [...new Set([...named, ...shapes])].slice(0, 6);
}

/** What a supplier reads in place of a customer's answer the gate kept back: no text of his, and why. */
export const SITE_NOTE_KEPT_FOR_SUPPLIERS = 'The customer added details about the site, which are released when the customer opens your quotation.';
export const SITE_KEPT_FOR_SUPPLIERS = 'The customer answered. The site details in the answer are released when the customer opens your quotation; price on the emirate and the request, and state any assumption.';

// deno-lint-ignore no-explicit-any
type Row = { summary?: string | null; spec?: any; budget?: string | null; boq?: any; brief_source?: string | null; emirate?: string | null };
/**
 * ONE INQUIRY ROW AS A SUPPLIER RECEIVES IT (supplier_api inbox, and through it the inquiry PDF and the review doors).
 *  * not revealed: summary, brief, budget and BOQ through the gate, with the stated site and the old supplier's terms as seeds;
 *  * revealed: the customer's own words and his site (the reveal releases the customer), but never the old supplier's terms
 *    or prices (rulings 1683/1686: the reveal does not release the competitor): forSource on the summary, the quotation gate
 *    on a quotation's BOQ, and old_supplier_terms dropped;
 *  * the owner could not be read: no customer text at all.
 */
export function supplierCopy(i: Row, o: { revealed: boolean; ownerResolved: boolean; buyer: Buyer }, hits: string[] = []) {
  const quotation = i.brief_source === 'quotation' || isQuotationReading(i.boq);
  const boq0 = i.boq && typeof i.boq === 'object' && 'customer_rates' in i.boq ? (({ customer_rates: _r, ...rest }) => rest)(i.boq) : i.boq;   // the customer's budget is his
  const boqIn = boq0 && quotation ? quotationGate(boq0, { parties: [], refs: [], prefixes: [] }) : boq0;
  if (o.revealed) return { summary: forSource(i.summary ?? null, i.brief_source) ?? null, spec: revealedSpec(i.spec ?? null), budget: i.budget ?? null, boq: boqIn ?? null, summary_withheld: false, spec_withheld: false, budget_withheld: false, boq_withheld: false };
  if (!o.ownerResolved) return { summary: null, spec: null, budget: null, boq: null, summary_withheld: false, spec_withheld: false, budget_withheld: false, boq_withheld: false };
  const seeds = requestSeeds(o.buyer, i.spec);
  const sum = supplierField<string>(forSource(i.summary ?? null, i.brief_source), o.buyer, seeds, hits, i.emirate);
  const spec = supplierBrief(i.spec ?? null, i.emirate, o.buyer, seeds, hits);
  const bud = supplierField<string>(i.budget ?? null, o.buyer, seeds, hits, i.emirate);
  const boq = inboxBoq(boqIn, o.buyer.name, seeds, hits);
  return { summary: sum.value, spec: spec.value, budget: bud.value, boq: boq.boq, summary_withheld: sum.withheld, spec_withheld: spec.withheld, budget_withheld: bud.withheld, boq_withheld: boq.withheld };
}

/**
 * The new-inquiry e-mail body (customer_api matching.ts matchAndNotify; edit_inquiry sends the same shape). Every
 * customer-authored part goes through the gate; a part that cannot be proved clean is left out and the supplier is told
 * to read the request in the portal. `resolved:false` (the owner could not be read): no customer text at all.
 */
export function newInquiryBody(o: { resolved: boolean; buyer: Buyer; spec: unknown; summary: string | null; budget: string | null; extra: string; category: string; emirate: string | null; briefSource?: string | null }): string {
  const seeds = o.resolved ? requestSeeds(o.buyer, o.spec) : [];
  const cust = (t: string | null | undefined) => (o.resolved ? supplierLine(t, o.buyer, seeds) : '');
  const headline = (o.resolved ? supplierLine(forSource(o.summary, o.briefSource), o.buyer, seeds, o.emirate) : '') || tradeWords(o.category);
  const budget = cust(o.budget);
  return 'A customer is requesting quotes for: ' + headline + (o.emirate ? ' (' + o.emirate + ')' : '') + (budget ? ' — budget ' + budget : '') + '.' + cust(o.extra) + ' Log in to your QuotesDone supplier portal to quote.';
}

/** What the supplier is told is attached, said of what it is (13 Nov 2026, anonymity audit A, L6: "A drawing with a draft bill
 *  of quantities is attached" was said of another supplier's quotation, and "A redacted drawing" of a BOQ with no drawing). */
export function attachedLine(source: string | null, hasBoq: boolean, hasDrawing: boolean): string {
  if (source === 'quotation') return (hasBoq ? ' The items of the customer’s existing quotation are listed on our inquiry: no prices, no names, no references of the old supplier.' : '') + (hasDrawing ? ' A redacted drawing is attached.' : '');
  if (source === 'boq') return hasBoq ? ' The customer’s own bill of quantities is attached (quantities as the customer wrote them, prices removed).' : '';
  if (hasBoq && hasDrawing) return ' A redacted drawing with a draft bill of quantities is attached.';
  if (hasBoq) return ' A draft bill of quantities from the customer’s drawing is attached.';
  return hasDrawing ? ' A redacted drawing is attached.' : '';
}

/** A trade slug as words, for a line that would otherwise be empty ("plumbing_sanitary" -> "Plumbing sanitary work"). */
export const tradeWords = (slug: string | null | undefined) => { const t = String(slug || 'general').replace(/[_-]+/g, ' ').trim(); return t.charAt(0).toUpperCase() + t.slice(1) + ' work'; };

// ── THE DOORS THAT READ THE OWNER THEMSELVES (13 Nov 2026, review of #F2 item 1) ────────────────────────────────────────
// rfq_note, add_missing_specs, clarify_answer and the English replay of an Arabic answer (finishEnglish) e-mailed what the
// customer wrote to every matched supplier through a name-only scrub; measured by the independent review: "Access is via the
// back gate of Villa 15, Al Barsha 2, near Mall of the Emirates; Makani 12345 67890." reached the e-mail word for word. Each
// now reads the owner here and passes the text through the same gate as the portal.
// deno-lint-ignore no-explicit-any
type Db = { from: (t: string) => any };
export type OwnerRead = { resolved: true; buyer: Buyer; spec: unknown; emirate: string | null; briefSource: string | null } | { resolved: false };
/** The request's owner as the gate needs him (name, e-mail, phone, project) and the request's own brief. Fails closed. */
export async function readOwner(db: Db, inquiryId: string): Promise<OwnerRead> {
  try {
    const { data: inq, error: e1 } = await db.from('inquiries').select('customer_id,project_id,spec,emirate,brief_source').eq('id', inquiryId).maybeSingle();
    if (e1 || !inq) return { resolved: false };
    const base = { spec: inq.spec ?? null, emirate: inq.emirate ?? null, briefSource: inq.brief_source ?? null };
    if (!inq.customer_id) return { resolved: true, buyer: { name: null }, ...base };
    const { data: c, error: e2 } = await db.from('customers').select('full_name,email,phone').eq('id', inq.customer_id).maybeSingle();
    if (e2) return { resolved: false };
    let project: string | null = null;
    if (inq.project_id) { const { data: pj, error: e3 } = await db.from('projects').select('name').eq('id', inq.project_id).maybeSingle(); if (e3) return { resolved: false }; project = pj?.name ?? null; }
    const n = String(c?.full_name || '').trim();
    return { resolved: true, buyer: { name: n.length >= 3 ? n : null, email: c?.email ?? null, phone: c?.phone ?? null, project }, ...base };
  } catch (_e) { return { resolved: false }; }
}
/** A customer's text as the matched suppliers may receive it: the gated text, or null (send nothing) when it cannot be proved clean. */
export function forSuppliers(text: string, owner: OwnerRead): string | null {
  if (!owner.resolved) return null;
  const t = supplierLine(String(text), owner.buyer, requestSeeds(owner.buyer, owner.spec), owner.emirate);
  return t.replace(/\[removed\]|█/g, '').trim().length >= 2 ? t : null;
}
/** forSuppliers with the owner read first (the replay and the doors that hold no owner of their own). */
export async function textForSuppliers(db: Db, inquiryId: string, text: string): Promise<string | null> {
  return forSuppliers(text, await readOwner(db, inquiryId));
}
/** The notice to the suppliers who were not chosen (customer_api matching.ts notifyLosers): a pre-reveal surface. */
export function awardedOtherBody(summary: string | null, owner: OwnerRead): string {
  const s = summary && summary.trim() && owner.resolved ? forSuppliers(String(forSource(summary.trim(), owner.briefSource)), owner) : null;
  const job = s ? '“' + s + '”' : 'a recent job you quoted';
  return 'Thank you for taking the time to quote on ' + job + '. On this occasion the customer has chosen to proceed with another supplier. We genuinely appreciate the effort you put into your quote, and it was great having you compete for the work. New matching opportunities come through QuotesDone regularly — please keep an eye on your supplier inbox, and we wish you the very best of luck on the next one.';
}
/** The parts of a customer's text that keep it from the suppliers, for his notice: the seeds it holds and what the residual scan found. */
export function keptPartsOf(text: string, owner: OwnerRead): string[] {
  if (!owner.resolved) return [];
  const seeds = requestSeeds(owner.buyer, owner.spec);
  const n = norm(text);
  return [...new Set([...seeds.filter((sd) => sd.length >= 4 && new RegExp('(?:^|\\s)' + sd.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '(?:\\s|$)').test(n)), ...heldParts(text, owner.buyer, seeds)])].slice(0, 4);
}
