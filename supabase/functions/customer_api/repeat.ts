// REPEAT A REQUEST IN ONE CLICK (sales_engineer, founder_instruction 1028, backlog 1019 T1).
// A customer re-issues a past request with the same specs. This builds what the one posting door needs:
// a 'ready' intake carrying the original brief, and the create_inquiry body. customer_api then runs the
// SAME create_inquiry branch as a fresh request, so the account gate, rate limit, requirement check,
// anonymity gate, split guard (a03_inquiry_split_needs_the_customers_choice) and matching all apply.
// No model is called: the original brief was already reasoned when it was first posted.
//
// What carries over: summary, trade, emirate, budget, floor, project, the spec details and the customer's
// own requirement answers (materials, installation, warranty), and the sourcing choice the customer made
// (one contractor / per trade). The split stays the customer's own earlier choice; nothing is split that
// was not.
// What does not: the drawing or BOQ file (re-attach it to send a drawing again), and a "needed by" date
// that has passed - it moves forward by the same lead time the customer first gave, from today.
// ponytail: lead time is whole days between the old post and its date, floored at 7; a customer who wants
// another date edits the request after posting.

import { applyEdits, validateStored } from '../_shared/intake_requirements.ts';

export type Original = {
  id?: string; category: string | null; emirate: string | null; raw_input: string | null; summary: string | null;
  budget: string | null; scope_type: string | null; trades: string[] | null; floor: string | null;
  project_id: string | null; lang: string | null; created_at: string; spec: Record<string, unknown> | null;
};

// ONLY ALLOWLISTED SPEC KEYS ARE COPIED (release review of #1180): the trade's own checklist keys (category_specs.fields,
// passed in by the caller) plus the brief keys the intake writes for every trade. Anything else the old spec carries
// (model notes, checks, provenance, keys of a retired checklist) stays behind; the customer can add it in the edit step.
export const BRIEF_KEYS = ['quantity', 'products', 'scope', 'location', 'property_type', 'timeline', 'warranty', 'unit', 'finish', 'dimensions_qty'];
const DAY = 86400e3;
const iso = (d: Date) => d.toISOString().slice(0, 10);

/** What the customer may change before posting the copy (founder_instruction 1028: "edit it before submitting"). */
// sourcing: the customer's own answer to "No single contractor is available yet; would you like separate quotes per
// trade?" (finding c of 10 Nov 2026). 'multi' turns a turnkey request of two or more trades into separate quotes per
// trade; it is the ONLY way such a request is re-posted per trade (rulings 1021, 1025: the split is the customer's choice).
export type RepeatEdits = { summary?: unknown; budget?: unknown; emirate?: unknown; required_by?: unknown; sourcing?: unknown };
const txt = (v: unknown, n: number) => (typeof v === 'string' ? v.trim().slice(0, n) : '');

export function repeatPlan(o: Original, now = new Date(), e: RepeatEdits = {}, checklistKeys: string[] = []) {
  const spec = (o.spec && typeof o.spec === 'object') ? o.spec : {};
  const details: Record<string, unknown> = {};
  const allow = new Set([...BRIEF_KEYS, ...checklistKeys]);
  for (const [k, v] of Object.entries(spec)) if (allow.has(k) && k !== 'customer_requirements') details[k] = v;
  const reqs = (spec.customer_requirements && typeof spec.customer_requirements === 'object') ? spec.customer_requirements as Record<string, any> : null;
  const trades = Array.isArray(o.trades) ? o.trades.map(String).filter(Boolean) : [];
  const choseSeparate = e.sourcing === 'multi' && o.scope_type === 'turnkey' && trades.length > 1;
  const scope = choseSeparate ? 'multi' : o.scope_type === 'turnkey' ? 'turnkey' : (o.scope_type === 'multi' && trades.length > 1 ? 'multi' : 'single');
  const edits: Record<string, string> = {};
  const old = String(reqs?.required_by?.date || '');
  if (/^\d{4}-\d{2}-\d{2}$/.test(old) && Date.parse(old) < Date.parse(iso(now))) {
    const lead = Math.max(7, Math.round((Date.parse(old) - Date.parse(String(o.created_at).slice(0, 10))) / DAY));
    edits.required_by = iso(new Date(Date.parse(iso(now)) + lead * DAY));
  }
  const date = txt(e.required_by, 10);
  if (/^\d{4}-\d{2}-\d{2}$/.test(date)) edits.required_by = date;
  const summary = txt(e.summary, 500) || o.summary;
  const budget = e.budget === undefined ? o.budget : (txt(e.budget, 80) || null);
  const emirate = e.emirate === undefined ? o.emirate : (txt(e.emirate, 40) || null);
  // The requirements carry their own category (validateStored checks it), so a turnkey parent ('fitout')
  // keeps the category its answers were recorded under.
  const category = String(reqs?.category || o.category || 'general');
  const brief = { repeat_of: o.id ?? null, summary, emirate, budget, floor: o.floor, project_id: o.project_id, trades, details, requirements: reqs };
  return {
    category,
    raw_input: String(o.raw_input || o.summary || '').slice(0, 4000),
    brief,
    body: { category, emirate, summary, budget, raw_input: o.raw_input, scope_type: scope, trades, lang: o.lang, requirement_edits: edits, drawing: null, spec: {} },
  };
}

/** Checked BEFORE anything is written (release review of #1180): a request whose stored answers cannot be posted
 *  again is refused with a plain message and leaves no intake row behind. Also returns the needed-by date the copy
 *  will carry, for the edit form. */
export function repeatCheck(plan: ReturnType<typeof repeatPlan>, now = new Date()) {
  const reqs = plan.brief.requirements;
  const cat = String(reqs?.category || plan.category);
  let stored: unknown = reqs;
  if (Object.keys(plan.body.requirement_edits).length) {
    const ed = applyEdits(cat, reqs, plan.body.requirement_edits, now);
    if (ed.invalid.length) return { ok: false as const, missing: ed.invalid, required_by: null };
    stored = ed.stored;
  }
  const v = validateStored(cat, stored);
  const rb = (stored as any)?.required_by?.date;
  return { ok: v.ok, missing: v.missing, required_by: typeof rb === 'string' ? rb : null };
}

/** WHETHER THE CARD MAY OFFER REPEAT (11 Nov 2026, sales_engineer; nightly run 077cbbfc). The customer portal showed
 *  "Repeat" on every request, and on a request whose stored answers cannot be posted again the preview was refused with
 *  HTTP 422 nothing_to_repeat: the crawl pressed it on all four viewports (8 console errors). The door is right to refuse;
 *  the button should not be offered. This is the door's own check (repeatCheck over repeatPlan), run on the row
 *  my_inquiries already reads, so the button and the door cannot disagree. One trade of a larger request is repeated
 *  through its parent (the door answers 409 repeat_the_whole_request), so it is never offered on a child either.
 *  prevented by: customer_api/repeat.test.ts ("the card offers Repeat only when the door would build it") */
export function canRepeat(o: Original & { parent_inquiry_id?: string | null }, now = new Date()): boolean {
  if (o.parent_inquiry_id) return false;
  return repeatCheck(repeatPlan(o, now), now).ok;
}
