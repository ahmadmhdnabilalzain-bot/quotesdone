// confirm — ONE vision-model check of the coded BOQ draft, per drawing. It CONFIRMS; it never becomes
// the source of a quantity silently.
//
// THE RULING (founder, 14 Sep 2026, ledger id 216): "in the case of the boq and drawing, i dont mind
// using LLM to confirm the result". Scope set with it: the coded extraction stays primary; the model
// sees the drawing and our draft and answers, per line, agree / disagree (with its value) /
// cannot_tell, plus anything the code missed. Then:
//   agree                      -> the line is confirmed (qty_status 'check_confirmed'), no question
//   disagree, or model-only    -> the line stays open, the second reading is written into its basis,
//                                 and the sales engineer asks the customer (boq_open_lines)
//   model unavailable/refused  -> the coded result stands; open lines say "not confirmed by a second
//                                 reading"
//
// OFF BY DEFAULT. drawing_boq calls it only when app_secrets.drawing_boq_confirm_enabled is 'on' AND
// the route 'drawing_boq_confirm' is enabled in public.paid_route_exception — the one named exception
// to the founder's OpenRouter hold, with a per-call token cap and a daily spend cap
// (scripts/sql/the_drawing_confirm_check_is_the_one_named_exception_to_the_hold.sql). Both ship OFF.
// Nothing here calls a model; drawing_boq does, through ai_gateway, so every call is logged and priced.
import { parseJson } from '../_shared/model_json.ts';
import type { Line, OpenLine } from '../_shared/boq_open_lines.ts';
import { isOpen, lineKey } from '../_shared/boq_open_lines.ts';
import { scrubIdentity } from './boq_from_text.ts';

// ── WHAT THE MODEL MAY SEE (independent review of #642, 14 Sep 2026) ──────────────────────────────────
// The first version sent the ORIGINAL page from the request to the vision model, in parallel with
// redaction: the customer's client name, site and logo would have left for a third-party provider.
// The check now receives only a page that drawing_redact PRODUCED and RECORDED as fully cleaned
// (public.drawing_redaction_runs: status 'complete', every page out that went in), fetched from
// storage by its recorded path. No run, a partial or failed run, or a path of any other shape: no
// page, no call, and the lines are marked unconfirmed. confirm_redacted_only.test.ts holds this.
export type RedactionRun = { id: string; status: string; pages_in: number; pages_out: number; output_paths: string[] | null };
export type RedactedPage = { path: string; job_id: string };
const REDACTED_PATH = /^redacted\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/page_p\d+\.jpg$/;
export function redactedPageFor(run: RedactionRun | null | undefined): RedactedPage | null {
  if (!run || run.status !== 'complete' || !(Number(run.pages_in) > 0) || Number(run.pages_out) !== Number(run.pages_in)) return null;
  const p = Array.isArray(run.output_paths) ? String(run.output_paths[0] || '') : '';
  return REDACTED_PATH.test(p) ? { path: p, job_id: run.id } : null;
}

export const CONFIRM_ROUTE = 'drawing_boq_confirm';
export const CONFIRM_MAX_TOKENS = 900;

export type Verdict = { key: string; verdict: 'agree' | 'disagree' | 'cannot_tell'; value: number | null };
export type Missed = { description: string; qty: number | null; unit: string };
export type Box = { x: number; y: number; w: number; h: number };
export type ConfirmReply = { lines: Verdict[]; missed: Missed[]; title_block: Box[] };

export const CONFIRM_SYS = `You check a DRAFT bill of quantities that software read from a construction drawing. You are shown the drawing and the draft. For EACH draft line, look at the drawing and answer:
- "agree" if the drawing supports the draft quantity exactly,
- "disagree" with your own integer "value" if you count a different number,
- "cannot_tell" if the drawing does not let you count it.
Then list anything a supplier must price that the draft MISSED (a device type or item with its count, or null if you cannot count it).
Also give the boxes (fractions 0..1 of the page: x,y top-left, w,h) that cover the TITLE BLOCK and any company logo, client, site, project or drawing-reference text, so software can blank them.
PRIVACY: never write any name, company, address, project name or reference in your answer. Describe items generically.
Return STRICT JSON ONLY:
{"lines":[{"key":"<draft key>","verdict":"agree"|"disagree"|"cannot_tell","value":<integer or null>}],"missed":[{"description":"<generic item>","qty":<integer or null>,"unit":"nos"|"m"}],"title_block":[{"x":0.8,"y":0.5,"w":0.2,"h":0.5}]}`;

/** The user message: our draft, one line per key, with our number (or "not counted"). */
export function confirmUserText(lines: Line[]): string {
  const rows = lines.filter((l) => l.type || isOpen(l)).map((l) => `${lineKey(l)} | ${l.description} | ${l.estimate ?? l.qty ?? 'not counted'} ${l.unit}`);
  return `Draft lines (key | item | our quantity):\n${rows.join('\n')}\n\nCheck each against the drawing and return the JSON.`;
}

const int = (v: unknown, max = 100000) => { const n = Number(v); return v !== null && v !== '' && Number.isInteger(n) && n >= 0 && n <= max ? n : null; };
const frac = (v: unknown) => { const n = Number(v); return Number.isFinite(n) && n >= 0 && n <= 1 ? n : null; };

/** Strict: anything outside the contract is dropped; a reply with no valid part is null. */
export function parseConfirm(raw: string, keys: Set<string>): ConfirmReply | null {
  const j = parseJson(raw, { wholeDecides: true });
  if (!j) return null;
  const o = j as Record<string, unknown>;
  const lines: Verdict[] = [];
  for (const v of Array.isArray(o.lines) ? o.lines.slice(0, 80) : []) {
    const r = v as Record<string, unknown>;
    const key = String(r?.key || ''); const verdict = String(r?.verdict || '');
    if (!keys.has(key) || !['agree', 'disagree', 'cannot_tell'].includes(verdict)) continue;
    const value = int(r.value);
    if (verdict === 'disagree' && value == null) continue;
    lines.push({ key, verdict: verdict as Verdict['verdict'], value: verdict === 'disagree' ? value : null });
  }
  const missed: Missed[] = [];
  for (const v of Array.isArray(o.missed) ? o.missed.slice(0, 20) : []) {
    const r = v as Record<string, unknown>;
    const d = scrubIdentity(String(r?.description || '')).slice(0, 120);
    if (d.length < 3) continue;
    missed.push({ description: d, qty: int(r.qty), unit: r?.unit === 'm' ? 'm' : 'nos' });
  }
  const title_block: Box[] = [];
  for (const v of Array.isArray(o.title_block) ? o.title_block.slice(0, 10) : []) {
    const r = v as Record<string, unknown>;
    const x = frac(r?.x), y = frac(r?.y), w = frac(r?.w), h = frac(r?.h);
    if (x != null && y != null && w && h) title_block.push({ x, y, w, h });
  }
  return lines.length || missed.length || title_block.length ? { lines, missed, title_block } : null;
}

/** Apply the check. `reply` null means the model was unavailable: the coded result stands, marked. */
export function mergeConfirm(lines: Line[], reply: ConfirmReply | null): { lines: Line[]; status: 'confirmed_all' | 'partly_confirmed' | 'unconfirmed'; disagreements: number; model_only: number } {
  if (!reply) {
    return { lines: lines.map((l) => isOpen(l) ? { ...l, basis: `${l.basis ? l.basis + '; ' : ''}not confirmed by a second reading` } : l), status: 'unconfirmed', disagreements: 0, model_only: 0 };
  }
  const byKey = new Map(reply.lines.map((v) => [v.key, v]));
  let dis = 0;
  const out: Line[] = lines.map((l) => {
    const v = byKey.get(lineKey(l));
    if (!v || !isOpen(l)) return l;
    const est = l.estimate ?? l.qty;
    if (v.verdict === 'agree' && est != null) return { ...l, qty: est, qty_status: 'check_confirmed', basis: `${l.basis ? l.basis + '; ' : ''}confirmed by a second, independent reading of the drawing` };
    if (v.verdict === 'disagree') { dis++; return { ...l, basis: `${l.basis ? l.basis + '; ' : ''}a second reading counted ${v.value}, not ${est ?? 'our count'}: the customer is asked` }; }
    return { ...l, basis: `${l.basis ? l.basis + '; ' : ''}a second reading could not count this either` };
  });
  for (const m of reply.missed) {
    out.push({ section: 'Found by the second reading', description: m.description, item: m.description, qty: null, estimate: m.qty, unit: m.unit, qty_status: 'to_confirm', basis: 'found only by the second reading, not by our rules: the customer is asked', confidence: 'low' });
  }
  const stillOpen = out.filter(isOpen).length;
  return { lines: out, status: stillOpen === 0 ? 'confirmed_all' : 'partly_confirmed', disagreements: dis, model_only: reply.missed.length };
}

export type { OpenLine };
