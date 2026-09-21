// line_specs/rules.ts — the codified trade rules the comparison engine executes.
//
// docs/KNOWLEDGE_DOCTRINE.md section 7 (founder instructions 520-523, 18 Sep 2026): the sales
// engineer's "brain of combined technical directors" is five families of RULES, one row each, in
// English and Arabic, with a citation, an effective date and a law/practice/manufacturer_data label,
// executed here by code. Nothing in this file calls a model; nothing here guesses. A rule that does
// not match says nothing.
//
// The rows come from public.fn_trade_rules(p_trade_code) (live rows of the five tables, seeded from
// supabase/functions/_shared/rules/<trade>.json) or, in tests and in the sandbox proof, from that JSON
// file directly through rulesFromJson(). Pure: no I/O.
import { normText } from './model.ts';

export type RuleBase = {
  decision: string; label: 'law' | 'practice' | 'manufacturer_data'; jurisdiction: string; citation: string;
  effective_date: string; expires_on: string | null; licence: string; rule_en: string; rule_ar: string; source_ref: string | null;
};
export type ScopeLineRule = RuleBase & { line_key: string; job_type: string | null; line_en: string; line_ar: string; kind: 'mandatory' | 'commonly_omitted'; proof_regex_en: string; proof_regex_ar: string; applies_regex: string | null };
export type EquivalenceRule = RuleBase & { attr_code: string; class_key: string; value: string; equivalent: boolean; evidence_kind: string; approval_ref: string | null; approval_expires: string | null };
export type PriceFlagRule = RuleBase & { benchmark_id: number; item: string; unit: string; low: number; high: number; line_regex: string | null };
export type ComparabilityRule = RuleBase & { line_type: string; line_regex: string; required_attrs: string[] };
export type ApprovalRule = RuleBase & { emirate: string; authority: string; approval_en: string; approval_ar: string; stage: 'before_works' | 'on_completion' | 'supplier_licence'; evidence_doc: string | null; cost_bearer: 'supplier' | 'customer' | 'either'; applies_regex: string | null };
export type TradeRules = { trade_code: string; scope_lines: ScopeLineRule[]; equivalence: EquivalenceRule[]; price_flags: PriceFlagRule[]; comparability: ComparabilityRule[]; approvals: ApprovalRule[] };

// A regex from a table row is data: a malformed one is skipped, never thrown.
const re = (s: string | null | undefined, flags = 'iu'): RegExp | null => { if (!s) return null; try { return new RegExp(s, flags); } catch { return null; } };
const canon = (s: string) => normText(s).toLowerCase().replace(/[^\p{L}\p{N}.]+/gu, '');
const firstNum = (s: string) => { const m = normText(s).match(/(\d+(?:\.\d+)?)/); return m ? Number(m[1]) : null; };
const sameToken = (a: string, b: string) => {
  const p = canon(a), q = canon(b);
  if (!p || !q) return false;
  if (p === q) return true;
  const x = firstNum(a), y = firstNum(b);
  // Two values that both carry a number compare by that number: "12.5" is "12.5 mm" and "0.6 mm" is
  // "0.6mm GI stud"; "9.5" is not "12.5" and "15" is not "150". Otherwise by containment ("Knauf" in "Knauf FireShield").
  if (x != null && y != null) return x === y;
  return p.length >= 3 && q.length >= 3 && (p.includes(q) || q.includes(p));
};

/** Reads the JSON shape (the file or fn_trade_rules' answer). Rows with active === false are dropped. */
export function rulesFromJson(j: unknown): TradeRules | null {
  if (!j || typeof j !== 'object') return null;
  const o = j as Record<string, unknown>;
  const list = <T>(k: string): T[] => (Array.isArray(o[k]) ? (o[k] as T[]).filter((r) => r && typeof r === 'object' && (r as { active?: unknown }).active !== false) : []);
  const trade_code = String(o.trade_code ?? '');
  if (!trade_code) return null;
  return {
    trade_code,
    scope_lines: list<ScopeLineRule>('scope_lines').map((r) => ({ ...r, job_type: r.job_type || null })),
    equivalence: list<EquivalenceRule>('equivalence'),
    price_flags: list<PriceFlagRule>('price_flags').map((r) => ({ ...r, low: Number(r.low), high: Number(r.high) })),
    comparability: list<ComparabilityRule>('comparability').map((r) => ({ ...r, required_attrs: Array.isArray(r.required_attrs) ? r.required_attrs.map(String) : [] })),
    approvals: list<ApprovalRule>('approvals'),
  };
}

// ---------------------------------------------------------------------------------------------
// Family 1 + 2: mandatory scope lines (hold) and commonly omitted lines (missing_from_request).
// ---------------------------------------------------------------------------------------------
/** Does the request ask for something this rule applies to? A rule with no applies_regex applies to every job. */
const applies = (r: { applies_regex: string | null }, requestText: string) => { const x = re(r.applies_regex); return !x || x.test(requestText); };
const proven = (r: ScopeLineRule, quoteText: string) => { const en = re(r.proof_regex_en), ar = re(r.proof_regex_ar); return !!((en && en.test(quoteText)) || (ar && ar.test(quoteText))); };

export function scopeCheck(rules: TradeRules | null | undefined, requestText: string, quoteText: string): { missing_mandatory: ScopeLineRule[]; omitted: ScopeLineRule[] } {
  const out = { missing_mandatory: [] as ScopeLineRule[], omitted: [] as ScopeLineRule[] };
  if (!rules) return out;
  const rq = normText(requestText), qt = normText(quoteText);
  for (const r of rules.scope_lines) {
    if (!applies(r, rq) || proven(r, qt)) continue;
    (r.kind === 'mandatory' ? out.missing_mandatory : out.omitted).push(r);
  }
  return out;
}

// ---------------------------------------------------------------------------------------------
// Family 3: equivalence classes, consulted BEFORE sameValue().
// ---------------------------------------------------------------------------------------------
export type EquivalenceVerdict = { flag: 'match' | 'differs' | 'unclassified'; rule: EquivalenceRule | null; class_key: string };
/**
 * The requested value names one or more classes (rows with equivalent=true whose value is the
 * requested value). The quoted value is then judged inside those classes: an explicit
 * equivalent=false row is `differs` with its rule; an equivalent=true row is `match`; a value in no
 * row of the class is `unclassified` (the caller decides: a brand stays 'stated', never 'match'; any
 * other attribute falls through to sameValue). Null when the rules say nothing about the requested value.
 */
export function equivalenceOf(rules: TradeRules | null | undefined, attr: string, value: string, requested: string): EquivalenceVerdict | null {
  if (!rules || !value || !requested) return null;
  const rows = rules.equivalence.filter((r) => r.attr_code === attr);
  const classes = [...new Set(rows.filter((r) => r.equivalent && sameToken(r.value, requested)).map((r) => r.class_key))];
  if (!classes.length) return null;
  let unclassified: EquivalenceVerdict | null = null;
  for (const c of classes) {
    const inClass = rows.filter((r) => r.class_key === c);
    const hit = inClass.find((r) => sameToken(r.value, value));
    if (hit) return { flag: hit.equivalent ? 'match' : 'differs', rule: hit, class_key: c };
    unclassified ??= { flag: 'unclassified', rule: null, class_key: c };
  }
  return unclassified;
}

// ---------------------------------------------------------------------------------------------
// Family 4: price red flags, per itemised line, against the band the trade's rules annotate.
// ---------------------------------------------------------------------------------------------
export function normUnit(u: string | null | undefined): string | null {
  const s = normText(String(u ?? '')).toLowerCase();
  if (!s) return null;
  if (/^(m2|m²|sqm|sq\.?\s*m|square\s*met(?:er|re)s?|متر\s*مربع|م2|م²)$/.test(s)) return 'sqm';
  if (/^(sqft|sq\.?\s*ft|ft2|square\s*f(?:ee|oo)t|قدم\s*مربع)$/.test(s)) return 'sqft';
  if (/^(m|lm|rm|mtr|meter|metre|linear\s*met(?:er|re)|متر\s*طولي|متر|م\.?ط|م)$/.test(s)) return 'm';
  if (/^(each|ea|nos?|no\.|pcs?|pc|piece|pieces|unit|units|عدد|قطعة|قطع|وحدة)$/.test(s)) return 'each';
  return s;
}
export type PriceVerdict = { rule: PriceFlagRule; rate: number; unit: string; verdict: 'below' | 'within' | 'above' };
/** The first annotated band whose line_regex and unit fit the line. Below = under 80% of low; above = over 125% of high (a band is a range of typical prices, not a tolerance). */
export function priceFlag(rules: TradeRules | null | undefined, lineText: string, qty: number | string | null | undefined, unit: string | null | undefined, amount: number | null | undefined, unitPrice?: number | null): PriceVerdict | null {
  if (!rules) return null;
  const q = Number(qty); const u = normUnit(unit);
  const rate = Number(unitPrice) > 0 ? Number(unitPrice) : (Number(amount) > 0 && q > 0 ? Number(amount) / q : null);
  if (rate == null || !u) return null;
  const t = normText(lineText);
  for (const r of rules.price_flags) {
    if (normUnit(r.unit) !== u) continue;
    const x = re(r.line_regex); if (x && !x.test(t)) continue;
    const verdict = rate < r.low * 0.8 ? 'below' : rate > r.high * 1.25 ? 'above' : 'within';
    return { rule: r, rate: Math.round(rate * 100) / 100, unit: u, verdict };
  }
  return null;
}

// ---------------------------------------------------------------------------------------------
// Family 5: comparability keys.
// ---------------------------------------------------------------------------------------------
export function comparabilityFor(rules: TradeRules | null | undefined, lineText: string): ComparabilityRule | null {
  if (!rules) return null;
  const t = normText(lineText);
  for (const r of rules.comparability) { const x = re(r.line_regex); if (x && x.test(t)) return r; }
  return null;
}

// ---------------------------------------------------------------------------------------------
// Family 6: approvals for the inquiry's emirate (or the whole UAE) that the request triggers.
// ---------------------------------------------------------------------------------------------
export function approvalsFor(rules: TradeRules | null | undefined, emirate: string | null | undefined, requestText: string): ApprovalRule[] {
  if (!rules) return [];
  const e = normText(String(emirate ?? '')).toLowerCase();
  const rq = normText(requestText);
  return rules.approvals.filter((r) => { const re_ = normText(r.emirate).toLowerCase(); return (re_ === 'uae' || (e && re_ === e)) && applies(r, rq); });
}

/** One sentence the report prints for a rule, in the customer's language, with its label and citation. */
export function ruleLine(r: RuleBase & { line_en?: string; line_ar?: string; approval_en?: string; approval_ar?: string; authority?: string }, lang: 'en' | 'ar'): string {
  const ar = lang === 'ar';
  const head = ar ? (r.approval_ar ?? r.line_ar ?? '') : (r.approval_en ?? r.line_en ?? '');
  const labelWord = ar ? ({ law: 'قانون', practice: 'ممارسة مهنية', manufacturer_data: 'بيانات المصنّع' } as const)[r.label] : r.label.replace('_', ' ');
  const who = r.authority ? (ar ? ` — ${r.authority}` : ` — ${r.authority}`) : '';
  return `${head ? head + who + ': ' : ''}${ar ? r.rule_ar : r.rule_en} [${labelWord}; ${r.citation}]`;
}
