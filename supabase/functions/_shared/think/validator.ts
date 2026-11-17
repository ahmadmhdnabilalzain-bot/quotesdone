// think/validator.ts — the guard on OUR draft, and the reader of the model's JSON reply (moved whole from _shared/think.ts).
import { BRIEF_SOURCE_ID } from './tunables.ts';
import type { DecisionSpec, Fact } from './types.ts';

// ── the validator: a guard on OUR draft, never on the asker's words ──────────────────────────────
// Deferral and refusal as the founder heard them from us (903). EN and AR. Only the shape of an
// evasion is listed; a draft that ALSO carries substance (enough words beyond the deferral) passes
// the phrase test, and is then judged by the other rules.
export const EVASION = [
  /\b(get|come) back to you\b/i, /\bi (will|'ll|need to|have to|must) (check|confirm|verify|find out|look into)\b/i,
  /\b(can ?not|can't|unable to|not able to|won't be able to) (answer|help|advise|say|provide|share|give)\b/i,
  /\bi (do not|don't) (know|have (that|this|the) information)\b/i, /\bno information (is )?available\b/i,
  /\bplease contact (our|the) (team|support|office)\b/i, /\boutside (of )?(my|our) (scope|expertise)\b/i,
  /\b(will|shall|'ll) (contact|call|revert to|reach out to|follow up with) you\b/i, /\blet me (confirm|check) with\b/i, /\brevert (shortly|soon|back)\b/i,
  /سأعود إليك/, /سنعود إليك/, /لا (أستطيع|يمكنني|نستطيع) (الإجابة|المساعدة|تقديم)/, /لا (أعرف|أعلم)/, /(سأتحقق|سنتحقق|سأتأكد) و/,
];
export function substanceWords(text: string): number {
  let t = String(text || '');
  for (const re of EVASION) t = t.replace(new RegExp(re.source, re.flags.includes('g') ? re.flags : re.flags + 'g'), ' ');
  return t.split(/\s+/).filter((w) => /[\p{L}\p{N}]/u.test(w)).length;
}
export interface Draft {
  answer: string; reasoning?: string[]; cited?: string[]; confidence?: number; asked_back?: string | null; route?: string | null;
  declined?: 'injection' | 'out_of_scope' | null;   // the reply refuses a manipulation or an out-of-scope ask, on purpose
  decision?: { choice?: string | null; fields?: Record<string, { value?: string; evidence?: string }> } | null;
}
/** Why a draft is refused, or null when it may go out. Pure: think.test.ts pins every rule. */
/** The evidence test of refuse(), for one field: null when the field is proven by the person's own words. */
function fieldProblem(k: string, f: { value?: unknown; evidence?: unknown } | undefined, hay: string, minEvidence: number): string | null {
  const ev = String(f?.evidence ?? '').trim().toLowerCase();
  // Format guard: the evidence must be the asker's own words, copied - a value with no quote is invented.
  if (ev.length < minEvidence || !hay.includes(ev)) return `field ${k} has no evidence copied verbatim from the conversation`;
  // ...and the value must be what those words say, not a value merely placed next to them.
  const val = String(f?.value ?? '').trim().toLowerCase();
  if (!val || !valueInEvidence(val, ev)) return `field ${k}: the value "${val}" is not in the evidence quoted for it`;
  return null;
}
export const READER_MIN_EVIDENCE = 4;
/** A reader keeps the fields its evidence proves and drops the rest (returned), instead of losing all of them. */
export function keepProvenFields(d: Draft, decision: DecisionSpec | undefined, conversationText: string): string[] {
  const fields = (d as { decision?: { fields?: Record<string, { value?: unknown; evidence?: unknown }> } }).decision?.fields;
  if (!decision?.fields?.length || !fields) return [];
  const hay = conversationText.toLowerCase(); const dropped: string[] = [];
  for (const k of Object.keys(fields)) {
    if (!decision.fields.some((x) => x.key === k) || fieldProblem(k, fields[k], hay, READER_MIN_EVIDENCE)) { dropped.push(k); delete fields[k]; }
  }
  return dropped;
}
export function refuse(d: Draft | null, o: { allowDecline?: boolean; missing: Fact[]; sourceIds: Set<string>; decision?: DecisionSpec; conversationText: string; requireTrail?: boolean; minEvidence?: number }): string | null {
  if (!d || typeof d !== 'object') return 'the reply is not one JSON object';
  const answer = String(d.answer ?? '').trim();
  if (!answer) return 'the answer is empty';
  const evasive = EVASION.some((re) => re.test(answer));
  // A CLEAR, POLITE REFUSAL OF A MANIPULATION OR AN OUT-OF-SCOPE ASK IS AN ANSWER (781, 28 Sep 2026). "I cannot share
  // another supplier's number" is the right reply to a prompt injection, and forcing it past 25 words sent it to the
  // canned fallback. The model says why it declines (declined); the refusal still has to say something (6+ words).
  // ONLY WHEN THE CALLER OPTS IN (allowDecline: support_reply.ts alone) and only for these two classes: every other
  // importer of think() keeps the evasion check exactly as before (review of #1043).
  const declined = o.allowDecline === true && (d.declined === 'injection' || d.declined === 'out_of_scope');
  if (declined && !o.decision && answer.split(/\s+/).length >= 6) { /* a refusal is the answer */ }
  else if (evasive && substanceWords(answer) < 25) {
    return 'the draft defers or declines without content — the answer standard (903) forbids "I will check / get back to you / cannot answer"; give everything that can already be said';
  }
  // A CHOICE AMONG OPTIONS ASKS NOBODY ANYTHING (customer_support, 19 Oct 2026): its caller reads decision.choice and
  // nothing else, so a question the model added beside a valid choice is never sent. Refusing it cost a whole second
  // pass (measured: wa_inbound.needs_a_person 27 s instead of 12 s; intent_table held twice over it on 18-19 Oct).
  if (d.asked_back && String(d.asked_back).trim() && !o.decision?.options?.length) {
    if (!o.missing.some((f) => f.changes_answer)) return 'a question was asked back, but no missing fact changes the answer; answer instead of asking';
    if (substanceWords(answer) < 12) return 'a question was asked back with nothing said alongside it; give what can already be said for each possibility, then ask';
  }
  // An answer (not a decision) states its trail: a draft with no reasoning steps is an assertion, not reasoning.
  if (o.requireTrail && !o.decision && !(Array.isArray(d.reasoning) && d.reasoning.some((x) => String(x).trim()))) return 'the answer carries no reasoning steps; show the steps it stands on';
  for (const c of d.cited ?? []) if (!o.sourceIds.has(String(c))) return `the draft cites ${c}, which is not among the sources it was given`;
  if (o.decision?.options?.length) {
    const ids = new Set(o.decision.options.map((x) => x.id));
    if (!d.decision || !ids.has(String(d.decision.choice ?? ''))) return `the decision must be exactly one of: ${[...ids].join(', ')}`;
  }
  if (o.decision?.fields?.length) {
    const hay = o.conversationText.toLowerCase();
    for (const [k, f] of Object.entries(d.decision?.fields ?? {})) {
      if (!o.decision.fields.some((x) => x.key === k)) return `field ${k} was not asked for`;
      // the seat's own writing (an order turn) quotes nobody; its content is checked by code after the answer
      if (o.decision.authored) continue;
      const bad = fieldProblem(k, f, hay, o.minEvidence ?? 8); if (bad) return bad;
    }
  }
  return null;
}

/**
 * THE SETTLED FACTS ARE A SOURCE (ceo, ledger 1003 stage 2, 19 Oct 2026). The brief and the seat's card ride in every
 * prompt, and the seat's card names each fact's pack entry (e.g. accountant:non-response-charge-accounting) and the
 * terms by clause (CT§8). Measured on the real-model seat exam: 5 answers were HELD because they cited exactly those
 * (customer_support-exam-32 'CT§8(f)', accountant-exam-14, accountant-exam-85 'PP§7', marketing-exam-08): a fact the
 * seat was given, refused as "a source it was not given". So a citation is valid when it is a retrieved source, the
 * id 'brief', or an id the settled facts THIS audience was given carry verbatim (a clause cited with a sub-letter, CT§8(f),
 * counts as CT§8). An id from anywhere else is still refused, so an invented source still is.
 * prevented by: _shared/think_states_what_it_knows.test.ts
 */
export function citable(sourceIds: Set<string>, settled: string, d: Draft | null): Set<string> {
  const ok = new Set(sourceIds); ok.add(BRIEF_SOURCE_ID);
  // Only the two shapes the brief carries (release review of #1584: any 3-character substring let "fee" or "VAT" pass):
  // a clause token CT§n / SA§n / PP§n / DIS§n with an optional (x), or a seat:entry-id, and either one present in it.
  for (const c of d?.cited ?? []) {
    const id = String(c).trim(); const base = id.replace(/\([a-z0-9]{1,4}\)$/i, '');
    const shaped = /^(CT|SA|PP|DIS)§\d+$/.test(base) || (base === id && /^[a-z_]+:[a-z0-9][a-z0-9._-]*$/.test(id));
    if (shaped && new RegExp('(^|[^A-Za-z0-9_§.:-])' + base.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '(?![0-9A-Za-z_-])').test(settled)) ok.add(id);
  }
  return ok;
}
/**
 * A QUESTION THAT CHANGES NOTHING IS DROPPED, NOT THE ANSWER (ceo, ledger 1003 stage 2, 19 Oct 2026). refuse() turns
 * away a draft that asks back when no missing fact changes the answer; the rewrite asked again and the question was
 * held (5 on the seat exam: ceo-exam-80, customer_support-exam-73, accountant-exam-22/52, marketing-exam-64), though
 * each draft had already answered. When the answer has substance (25+ words besides any deferral), the question is
 * removed and the answer stands; a thin answer that only asks is still refused and rewritten.
 */
export function groundDraft(d: Draft | null, missing: Fact[]): void {
  if (!d || typeof d !== 'object' || !d.asked_back || !String(d.asked_back).trim()) return;
  if (!missing.some((f) => f.changes_answer) && substanceWords(String(d.answer ?? '')) >= 25) d.asked_back = null;
}

/**
 * A VALUE IS WHAT ITS EVIDENCE SAYS, NUMBER FOR NUMBER (review of #1444, 18 Oct 2026). Substring containment let "3"
 * pass for "Validity: 30 days", "2" for "25 m2" and "0.5" for "10.5 mm". The value must still sit inside its evidence,
 * and every number in it must match a WHOLE number in the evidence: no digit, decimal point or separator-and-digit may
 * touch it on either side ("9,000.00" is one number; "1,5" stays as written).
 * prevented by: _shared/think_value_in_evidence.test.ts
 */
/** The numbers of a text, in any script (\p{Nd}: "٣٠" is one number, never "٣"): digits with an optional thousands
 *  separator ("," or the Arabic "٬") before exactly three digits, and an optional decimal part ("." or "٫"). "9,000.00" is
 *  one number; "450,m2,20.00" is three. A number is CODE-LIKE when one or two letters that START a token sit right before
 *  it ("C25", "L1", the "2" of "m2" written apart): part of a name, not a quantity. A unit or currency glued to it
 *  ("AED9,000", "450m2", "10mm", "30days") does not make it code-like. */
const NUMBER = /\p{Nd}+(?:[,\u066C]\p{Nd}{3})*(?:[.\u066B]\p{Nd}+)?/gu;
function numbersOf(t: string): { n: string; code: boolean }[] {
  const out: { n: string; code: boolean }[] = [];
  for (const m of t.matchAll(NUMBER)) {
    const before = t.slice(Math.max(0, m.index! - 3), m.index!);
    out.push({ n: m[0], code: /(?:^|[^\p{L}\p{Nd}])\p{L}{1,2}$/u.test(before) || (m.index! <= 2 && /^\p{L}{1,2}$/u.test(before)) });
  }
  return out;
}
export function valueInEvidence(val: string, ev: string): boolean {
  if (!ev.includes(val)) return false;
  const evNums = numbersOf(ev);
  // A quantity in the value must be a whole quantity of the evidence; a code-like number ("C25") may match the same code.
  return numbersOf(val).every((v) => evNums.some((e) => e.n === v.n && (v.code || !e.code)));
}

// One JSON object out of a model reply, or null: the whole reply (inside a ```json fence), else the outermost object.
// A REASONING MODEL WRITES A SENTENCE AROUND ITS JSON (exam run b2f80d4d, 19 Oct 2026: GPT-6 Luna Pro since matrix v3;
// 5 of 30 seat answers held as 'the reply is not one JSON object'). The 16 Nov audit named this reader the owner; it moved,
// unchanged in behaviour, to _shared/model_json.ts on 17 Nov 2026 so every function reads a reply one way.
export { parseJson } from '../model_json.ts';
