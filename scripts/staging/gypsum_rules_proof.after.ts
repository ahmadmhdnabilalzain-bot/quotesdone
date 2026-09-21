// gypsum_rules_proof.after.ts — the AFTER half of scripts/staging/gypsum_rules_proof.mjs.
//
// Runs the wired engine (line_specs/compare.ts + rules.ts, the code quote_compare imports) over the
// exact fixture rows the proof stood up in the sandbox, with the rules file the SQL seeds. Used
// until the coordinator applies the SQL and deploys quote_compare, after which the deployed function
// produces the same object through fn_trade_rules. Reads one JSON object on stdin:
//   { category, emirate, request_text, request_lines, requirements, quotes: [{quote_id,label_en,label_ar,supplier_letter,option_no,lines,terms}] }
// Prints { en: {...}, ar: {...} } — the rule findings rendered in both languages.
import { rankable, technicalComparison } from '../../supabase/functions/_shared/line_specs/compare.ts';
import { ruleLine, rulesFromJson } from '../../supabase/functions/_shared/line_specs/rules.ts';

const input = JSON.parse(await new Response(Deno.stdin.readable).text());
const rules = rulesFromJson(JSON.parse(await Deno.readTextFile(new URL('../../supabase/functions/_shared/rules/gypsum.json', import.meta.url))))!;
const r = rankable(input.quotes, input.category, input.requirements, rules, input.request_text);
const t = technicalComparison({ category: input.category, request_lines: input.request_lines, requirements: input.requirements, quotes: input.quotes, on_hold: r.held, now: new Date(), rules, request_text: input.request_text, emirate: input.emirate });
const labelOf = (id: string, lang: 'en' | 'ar') => input.quotes.find((q: { quote_id: string }) => q.quote_id === id)?.[lang === 'ar' ? 'label_ar' : 'label_en'] ?? id;
const render = (lang: 'en' | 'ar') => ({
  rules_applied: t.rules_applied,
  held_by_rule: r.held_by_rule.map((h) => ({ quote: labelOf(h.quote.quote_id, lang), lines: h.lines.map((l) => ruleLine(l, lang)) })),
  rankable: r.rankable.map((q) => labelOf(q.quote_id, lang)),
  substitutions: t.lines.flatMap((ln) => ln.attributes.flatMap((at) => at.cells.filter((c) => c.flag === 'differs' && c.note_en).map((c) => ({ quote: labelOf(c.quote_id, lang), line: ln.item, attribute: lang === 'ar' ? at.label_ar : at.label_en, quoted: c.value, requested: at.requested, marker: c.marker, why: lang === 'ar' ? c.note_ar : c.note_en, rule: c.rule })))),
  not_comparable: t.lines.filter((ln) => ln.comparable === false).map((ln) => ({ line: ln.item, marker: '≁', missing: ln.comparability!.missing.map((m) => ({ quote: labelOf(m.quote_id, lang), attrs: m.attrs })), why: lang === 'ar' ? ln.comparability!.rule_ar : ln.comparability!.rule_en })),
  missing_from_request: (t.omissions ?? []).map((o) => ({ quote: labelOf(o.quote_id, lang), lines: o.lines.map((l) => ruleLine(l, lang)) })),
  price_red_flags: (t.prices ?? []).filter((p) => p.verdict !== 'within').map((p) => ({ quote: labelOf(p.quote_id, lang), line: p.item, rate: p.rate, unit: p.unit, verdict: p.verdict, band: `${p.low}-${p.high}`, benchmark: p.benchmark_item, why: lang === 'ar' ? p.rule_ar : p.rule_en })),
  prices_within_band: (t.prices ?? []).filter((p) => p.verdict === 'within').map((p) => ({ quote: labelOf(p.quote_id, lang), line: p.item, rate: p.rate, unit: p.unit, band: `${p.low}-${p.high}` })),
  watch_outs: (t.approvals ?? []).map((a) => ruleLine(a, lang)),
});
console.log(JSON.stringify({ en: render('en'), ar: render('ar') }, null, 2));
