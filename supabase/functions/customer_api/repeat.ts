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

export type Original = {
  category: string | null; emirate: string | null; raw_input: string | null; summary: string | null;
  budget: string | null; scope_type: string | null; trades: string[] | null; floor: string | null;
  project_id: string | null; lang: string | null; created_at: string; spec: Record<string, unknown> | null;
};

const DROP = new Set(['customer_requirements', 'boq_check', 'plausibility', 'provenance']);
const DAY = 86400e3;
const iso = (d: Date) => d.toISOString().slice(0, 10);

export function repeatPlan(o: Original, now = new Date()) {
  const spec = (o.spec && typeof o.spec === 'object') ? o.spec : {};
  const details: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(spec)) if (!DROP.has(k)) details[k] = v;
  const reqs = (spec.customer_requirements && typeof spec.customer_requirements === 'object') ? spec.customer_requirements as Record<string, any> : null;
  const trades = Array.isArray(o.trades) ? o.trades.map(String).filter(Boolean) : [];
  const scope = o.scope_type === 'turnkey' ? 'turnkey' : (o.scope_type === 'multi' && trades.length > 1 ? 'multi' : 'single');
  const edits: Record<string, string> = {};
  const old = String(reqs?.required_by?.date || '');
  if (/^\d{4}-\d{2}-\d{2}$/.test(old) && Date.parse(old) < Date.parse(iso(now))) {
    const lead = Math.max(7, Math.round((Date.parse(old) - Date.parse(String(o.created_at).slice(0, 10))) / DAY));
    edits.required_by = iso(new Date(Date.parse(iso(now)) + lead * DAY));
  }
  // The requirements carry their own category (validateStored checks it), so a turnkey parent ('fitout')
  // keeps the category its answers were recorded under.
  const category = String(reqs?.category || o.category || 'general');
  const brief = { summary: o.summary, emirate: o.emirate, budget: o.budget, floor: o.floor, project_id: o.project_id, trades, details, requirements: reqs };
  return {
    category,
    raw_input: String(o.raw_input || o.summary || '').slice(0, 4000),
    brief,
    body: { category, emirate: o.emirate, summary: o.summary, budget: o.budget, raw_input: o.raw_input, scope_type: scope, trades, lang: o.lang, requirement_edits: edits, drawing: null, spec: {} },
  };
}
