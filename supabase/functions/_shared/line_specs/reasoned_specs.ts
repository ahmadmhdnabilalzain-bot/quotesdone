// reasoned_specs — exact specs for the trades that have no line reader, judged by reasoning.
// Seat: sales_engineer (the quote hold desk); engine: it_engineer. 23 Sep 2026.
//
// THE RULE: "exact specs or the quote is held" (founder). model.ts carries hand-written readers for the
// trades it knows; PR #881 added 153 trades and 123 of them have none, so for those a quote line was
// never asked anything and could not be held. Writing 123 more regex readers would be the word matching
// the founder ruled out (founder_instruction 886-903). Instead:
//   * WHAT is required comes from the trade's knowledge pack: its spec_checklist entries' required_specs,
//     loaded into public.trade_spec_checklist and read by fn_trade_spec_checklist(category);
//   * WHETHER a line states each one is judged by think(): for every material line and every required
//     spec, the value the supplier gave, with the supplier's own words as evidence (the validator refuses
//     a value it cannot find verbatim in the line). What the reasoning finds is written onto the line as
//     spec_source 'reasoned'; what it does not find stays missing, and assessQuote holds the quote.
//   * Under the model hold nothing is judged, so nothing is pre-filled: every required spec is asked of
//     the supplier and the QUOTE IS HELD until he states them (or the reasoning runs). Never a guess.
// A trade with no checklist is not held on an empty list; the gate logs it so the knowledge gap is seen.
import type { Attr } from './model.ts';
import { lineText, type Line } from './assess.ts';
import { think, type ThinkDeps } from '../think.ts';

export type ChecklistRow = { code: string; label_en: string; label_ar?: string | null };
/** One spec checklist of a trade pack (a trade has several: glazing has a facade IGU list, a balustrade list ...). */
export type Checklist = { topic_id: string; topic: string; specs: ChecklistRow[] };

/**
 * Which of the trade's checklists this quote is priced against — REASONED from the supplier's lines, never
 * matched on words. One checklist: that one. Held or failed: every checklist's specs together, so the quote
 * is held and the supplier states them (asking more is safe; guessing which list applies is not).
 */
export async function chooseChecklist(deps: ThinkDeps, o: { checklists: Checklist[]; lines: Line[]; trade: string; quoteId: string }): Promise<{ rows: ChecklistRow[]; topic: string | null; reasoned: boolean }> {
  const lists = o.checklists.filter((c) => c.specs?.length);
  if (!lists.length) return { rows: [], topic: null, reasoned: false };
  if (lists.length === 1) return { rows: lists[0].specs, topic: lists[0].topic_id, reasoned: false };
  const text = o.lines.map((l) => `LINE ${l.line_no}: ${lineText(l)}`).join('\n').slice(0, 7000);
  const r = await think(deps, {
    seat: 'sales_engineer', surface: 'quote.spec_checklist', question: text, dedupeKey: 'quote_checklist:' + o.quoteId, subject: { quote_id: o.quoteId },
    context: { audience: 'supplier', trade: o.trade },
    decision: { name: 'spec_checklist', options: lists.map((c) => ({ id: c.topic_id, meaning: c.topic })) },
  });
  const chosen = r.status === 'answered' ? lists.find((c) => c.topic_id === r.decision?.choice) : undefined;
  if (chosen) return { rows: chosen.specs, topic: chosen.topic_id, reasoned: true };
  const seen = new Set<string>();
  return { rows: lists.flatMap((c) => c.specs).filter((s) => !seen.has(s.code) && seen.add(s.code)), topic: null, reasoned: false };
}

/** The trade's required specs as line attributes. They read nothing themselves: reasoning fills them. */
export function checklistAttrs(rows: ChecklistRow[]): Attr[] {
  return rows.filter((r) => r?.code && r?.label_en).map((r) => ({
    code: r.code, en: r.label_en, ar: r.label_ar || r.label_en, type: 'text', mandatory: true, find: () => null,
  }));
}

/** A stable attribute code for a checklist sentence: "cavity width and gas fill (air/argon %)" -> spec_cavity_width_and_gas_fill. */
export function specCode(label: string): string {
  return 'spec_' + String(label).toLowerCase().split(/[(:,;]/)[0].replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 40);
}

const lineWords = (l: Line) => lineText(l);

/**
 * Which required specs each line states, in the supplier's own words. Returns line_no -> {code: value},
 * or null when the reasoning is held (the model hold, a failure) — the caller then pre-fills nothing.
 */
export async function reasonLineSpecs(deps: ThinkDeps, o: { lines: Line[]; checklist: Attr[]; trade: string; quoteId: string }): Promise<Record<number, Record<string, string>> | null> {
  const material = o.lines.filter((l) => lineWords(l).trim());
  if (!material.length || !o.checklist.length) return {};
  const conversation = material.map((l) => `LINE ${l.line_no}: ${lineWords(l)}`).join('\n');
  const fields = material.flatMap((l) => o.checklist.map((a) => ({ key: `L${l.line_no}__${a.code}`, question: `line ${l.line_no}: ${a.en}` })));
  const r = await think(deps, {
    seat: 'sales_engineer', surface: 'quote.line_specs', question: conversation.slice(0, 7000),
    dedupeKey: 'quote_specs:' + o.quoteId, subject: { quote_id: o.quoteId },
    context: { audience: 'supplier', trade: o.trade, conversation: [{ role: 'supplier', text: conversation.slice(0, 7000) }] },
    decision: { name: 'stated_specs', fields },
  });
  if (r.status !== 'answered') return null;
  const out: Record<number, Record<string, string>> = {};
  for (const [k, v] of Object.entries(r.decision?.fields ?? {})) {
    const m = k.match(/^L(\d+)__(.+)$/);   // our own key format, parsed
    if (!m || !v?.value) continue;
    (out[Number(m[1])] ??= {})[m[2]] = v.value;
  }
  return out;
}

/** The lines with what the reasoning found written in as their spec, marked 'reasoned'. */
export function withReasoned(lines: Line[], found: Record<number, Record<string, string>> | null): Line[] {
  if (!found) return lines;
  return lines.map((l) => found[l.line_no]
    ? { ...l, spec: { ...(l.spec ?? {}), ...found[l.line_no] }, spec_source: { ...(l.spec_source ?? {}), ...Object.fromEntries(Object.keys(found[l.line_no]).map((k) => [k, 'reasoned' as const])) } }
    : l);
}
