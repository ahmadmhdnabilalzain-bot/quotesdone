// THE QUESTION CARDS, AS PURE LOGIC (12 Nov 2026, sales_engineer; built by it_engineer). Founder rulings 1647 (ask where the
// documents are vague, broad or name a partner), 1628 (he confirms; nothing is ticked for him) and 1645 ("every tap answers ...
// I am looking for perfection"). Report docs/reports/2026-11-12-supplier-service-profiling.md 3.9, Screen 2; slice 4.
//
// The cards (ServiceQuestions.tsx) answer a tap at once and write behind it: this file is what they do, with no React, so
// serviceQuestions.test.mjs proves advance, back, resume and retry without a browser. The server's half (one answer, checked,
// one write) is supabase/functions/_shared/supplier_service_questions.ts; the shapes here are its rows and its Answer.

export type QOption = { key: string | null; label_en: string; own_words: boolean };
export type Answer = { picked?: number[]; none?: boolean; only_inside?: boolean; other?: string; per?: Record<string, 'own' | 'partner' | 'no'> };
export type Question = {
  id: number; kind: string; prompt_en: string; options: QOption[]; multi: boolean; status: string; answer: Answer | null;
  about?: { quote?: string | null; doc?: string | null; trade?: string | null; words?: string[]; partner_name?: string | null } | null;
};
/** A write behind a card: 'pending' while services_answer is on its way, 'failed' when it did not land (kept, retried). */
export type SaveState = 'pending' | 'saved' | 'failed';
export type Cards = { ids: number[]; index: number; answers: Record<number, Answer>; saving: Record<number, SaveState> };

/** The cards of this sitting: every question open now, and every one he already answered (so Back shows his answer), in the
 *  server's order. 'later', 'skipped' and 'expired' are not cards. */
export function cardsOf(questions: readonly Question[]): Question[] {
  return questions.filter((q) => q.status === 'open' || q.status === 'answered');
}

/** Where he resumes: the first card with no answer, local or stored; past the last when every card is answered. */
export function resumeIndex(cards: readonly Question[], answers: Record<number, Answer>): number {
  const i = cards.findIndex((q) => !answers[q.id] && !q.answer);
  return i < 0 ? cards.length : i;
}

/** The state the cards open in: his stored answers, plus any taps a reload interrupted (`kept`, from this browser). */
export function openCards(questions: readonly Question[], kept: Record<number, Answer> = {}): Cards {
  const cards = cardsOf(questions);
  const answers: Record<number, Answer> = {};
  const saving: Record<number, SaveState> = {};
  for (const q of cards) {
    if (kept[q.id] && JSON.stringify(kept[q.id]) !== JSON.stringify(q.answer)) { answers[q.id] = kept[q.id]; saving[q.id] = 'failed'; }
    else if (q.answer) { answers[q.id] = q.answer; saving[q.id] = 'saved'; }
  }
  return { ids: cards.map((q) => q.id), index: resumeIndex(cards, answers), answers, saving };
}

/** Next is enabled when the card has an answer it can send: a partner card needs every service answered; the nothing card his words. */
export function canSend(q: Pick<Question, 'kind' | 'options'>, a: Answer | undefined): boolean {
  if (!a) return false;
  if (q.kind === 'partner') return q.options.every((_, i) => !!a.per?.[String(i)]);
  if (q.kind === 'nothing') return (a.other ?? '').trim().length >= 2;
  return !!(a.none || a.only_inside || a.picked?.length || (a.other ?? '').trim().length >= 2);
}

/** One tap on a chip: toggled (several on a multi card, one otherwise); "None of these" goes when a chip is picked. */
export function togglePick(q: Pick<Question, 'multi'>, a: Answer | undefined, i: number): Answer {
  const cur = new Set(a?.picked ?? []);
  if (cur.has(i)) cur.delete(i); else { if (!q.multi) cur.clear(); cur.add(i); }
  const { none: _n, only_inside: _o, ...rest } = a ?? {};
  return { ...rest, picked: [...cur].sort((x, y) => x - y) };
}

/** The answer sent: the "Something else" text only when he opened it and wrote something. */
export function finalAnswer(a: Answer): Answer {
  const out: Answer = { ...a };
  const other = (a.other ?? '').replace(/\s+/g, ' ').trim();
  if (other.length >= 2) out.other = other; else delete out.other;
  if (out.picked && !out.picked.length) delete out.picked;
  return out;
}

/** He answered the card on screen: the answer is his at once and the next card is shown at once; the write is 'pending'. */
export function advance(c: Cards, id: number, a: Answer): Cards {
  const index = Math.max(c.index, c.ids.indexOf(id) + 1);
  return { ...c, answers: { ...c.answers, [id]: finalAnswer(a) }, saving: { ...c.saving, [id]: 'pending' }, index: Math.min(index, c.ids.length) };
}
export const back = (c: Cards): Cards => ({ ...c, index: Math.max(0, c.index - 1) });
export const goTo = (c: Cards, id: number): Cards => ({ ...c, index: Math.max(0, c.ids.indexOf(id)) });
/** The write landed, or did not. A failed write keeps his answer; a retry sends it again. */
export const settled = (c: Cards, id: number, ok: boolean): Cards => ({ ...c, saving: { ...c.saving, [id]: ok ? 'saved' : 'failed' } });
export const failedIds = (c: Cards): number[] => c.ids.filter((id) => c.saving[id] === 'failed');
export const unsavedIds = (c: Cards): number[] => c.ids.filter((id) => c.saving[id] === 'failed' || c.saving[id] === 'pending');
export const progress = (c: Cards): string => `${Math.min(c.index + 1, c.ids.length)} of ${c.ids.length}`;

/**
 * WHAT HIS ANSWERS SAY HE DOES, for the check screen and the confirm. Only what he tapped: a chip he picked is his own team; a
 * partner card's 'own' is his own team, 'partner' through the partner, 'no' declined; "None of these" and "Only inside our own
 * projects" decline the card's keys; "Something else" and a picked option with no key are kept in his own words. A licence
 * answer is about his business, not a service.
 */
export function outcome(questions: readonly Question[], answers: Record<number, Answer>): { own: string[]; partner: string[]; ownWords: string[]; partnerWords: string[]; declined: string[] } {
  const own = new Set<string>(), partner = new Set<string>(), words: string[] = [], pWords: string[] = [], declined = new Set<string>();
  const put = (list: string[], w: string) => { const t = w.replace(/\s+/g, ' ').trim(); if (t.length >= 2 && !list.some((x) => x.toLowerCase() === t.toLowerCase())) list.push(t); };
  const word = (w: string) => put(words, w);
  for (const q of questions) {
    const a = answers[q.id] ?? q.answer;
    if (!a || q.kind === 'licence') continue;
    if (q.kind === 'partner') {
      q.options.forEach((o, i) => {
        const v = a.per?.[String(i)];
        if (!v) return;
        if (v === 'no') { if (o.key) declined.add(o.key); return; }
        // his words for work through a partner keep that basis (review of slice 4, finding 12: "Jacuzzi" was listed as his own)
        if (o.key) (v === 'own' ? own : partner).add(o.key); else if (v === 'partner') put(pWords, o.label_en); else word(o.label_en);
      });
      continue;
    }
    const picked = new Set(a.picked ?? []);
    q.options.forEach((o, i) => {
      if (picked.has(i)) { if (o.key) own.add(o.key); else word(o.label_en); }
      else if ((a.none || a.only_inside) && o.key) declined.add(o.key);
    });
    if (a.other) word(a.other);
  }
  for (const k of own) partner.delete(k);
  return { own: [...own], partner: [...partner], ownWords: words, partnerWords: pWords, declined: [...declined].filter((k) => !own.has(k) && !partner.has(k)) };
}

// THE TAPS A RELOAD MUST NOT LOSE: an answer whose write failed is kept in this browser until it lands. Per-viewer convenience
// only (the stored answers are the record); every read and write is guarded, so a private window simply keeps nothing.
const KEPT = 'qd-svc-answers';
export function readKept(): Record<number, Answer> {
  try { const v = JSON.parse(globalThis.localStorage?.getItem(KEPT) ?? '{}'); return v && typeof v === 'object' ? v : {}; } catch { return {}; }
}
export function writeKept(c: Cards): void {
  try {
    const keep: Record<number, Answer> = {};
    for (const id of unsavedIds(c)) keep[id] = c.answers[id];
    if (Object.keys(keep).length) globalThis.localStorage?.setItem(KEPT, JSON.stringify(keep)); else globalThis.localStorage?.removeItem(KEPT);
  } catch { /* storage blocked: the stored answers are the record */ }
}

// ── WHAT HE CONFIRMS (review of slice 4, finding 13: this lived in the tab, where only a regex over its source could test it, and it filed
// a "Please check" row he ticked as partner work, finding 1). One pure function, tested in serviceQuestions.test.mjs.
export type ListedRow = { key: string; delivery?: 'own' | 'partner'; basis?: string; check?: boolean };
export type Selection = { stated: string[]; partner: string[]; own: string[]; words: string[]; partnerWords: string[]; ownWords: string[] };
export function selection(i: {
  rows: readonly ListedRow[]; ticked: ReadonlySet<string>;                         // screen 1's rows and the ones he ticked
  readWords: readonly { words: string; basis: string }[]; wordsTicked: ReadonlySet<string>;   // the reading's phrases in his words
  questions: readonly Question[]; answers: Record<number, Answer>;
  more?: readonly string[];          // his other own ticks: the checklist, the rewrite he kept, a meaning proposal he added
  storedPartner?: readonly string[]; savedWords?: readonly string[]; rewriteWords?: readonly string[]; dropped?: ReadonlySet<string>;
}): Selection {
  const dropped = i.dropped ?? new Set<string>();
  const a = outcome(i.questions, i.answers);
  const rowKeys = i.rows.filter((r) => i.ticked.has(r.key)).map((r) => r.key);
  const stated = [...new Set([...(i.more ?? []), ...rowKeys, ...a.own, ...a.partner])].filter((k) => !dropped.has(k));
  // THROUGH A PARTNER: only a row whose documents say so (delivery 'partner'), his partner answers, and what he confirmed so before
  // unless he now says own team. A "Please check", project or brand row he ticks is HIS OWN work.
  const partner = [...new Set([...a.partner, ...[...i.rows.filter((r) => r.delivery === 'partner' && i.ticked.has(r.key)).map((r) => r.key),
    ...(i.storedPartner ?? [])].filter((k) => !a.own.includes(k))])].filter((k) => stated.includes(k));
  const all: string[] = [];
  const add = (w: string) => { const t = w.replace(/\s+/g, ' ').trim(); if (t.length >= 2 && !all.some((x) => x.toLowerCase() === t.toLowerCase()) && !dropped.has('word:' + t)) all.push(t); };
  for (const w of [...(i.savedWords ?? []), ...(i.rewriteWords ?? []), ...i.readWords.filter((w) => i.wordsTicked.has(w.words)).map((w) => w.words), ...a.ownWords, ...a.partnerWords]) add(w);
  const isP = (w: string) => [...a.partnerWords, ...i.readWords.filter((x) => x.basis === 'partner').map((x) => x.words), ...(i.storedPartner ?? [])].some((x) => x.toLowerCase() === w.toLowerCase());
  const partnerWords = all.filter(isP);
  return { stated, partner, own: stated.filter((k) => !partner.includes(k)), words: all, partnerWords, ownWords: all.filter((w) => !isP(w)) };
}

/** A prompt the reading wrote as `Your profile says: "<his sentence>" <the question>`, split at HIS sentence (q.about.quote), never at the
 *  first inner quote mark (review of slice 4, finding 7: `We do 24" ducts` cut the sentence at the inch mark). proposalOf's own quoting. */
export function splitPrompt(prompt: string, quote: string | null | undefined): { quote: string | null; ask: string } {
  if (!quote) return { quote: null, ask: prompt };
  const q = quote.replace(/\s+/g, ' ').slice(0, 160);
  for (const head of [`Your profile says: "${q}" `, `Your profile says these are delivered "${q}". `]) if (prompt.startsWith(head)) return { quote: q, ask: prompt.slice(head.length) };
  return { quote: null, ask: prompt };
}

/** A tap that lands within this long of a new card is the second tap of a double tap meant for the card before (review of slice 4,
 *  finding 6: a double tap on a single-choice chip ticked the first chip of the next card). */
export const TAP_GUARD_MS = 350;
export const tapAllowed = (shownAt: number, now: number): boolean => now - shownAt >= TAP_GUARD_MS;

// SCREEN 1's TICKS SURVIVE A RELOAD (review of slice 4, finding 2: an iPhone back from WhatsApp reloads; the step was kept and the ticks
// lost). Kept with the step, for one reading (its read_at); per-viewer convenience, guarded, a private window simply keeps nothing.
export type Flow = { at: string; step: string; ticked?: string[]; words?: string[] };
const FLOW = 'qd-svc-step';
export function readFlow(at: string): Flow | null {
  try { const v = JSON.parse(globalThis.localStorage?.getItem(FLOW) ?? 'null'); return v && v.at === at ? v : null; } catch { return null; }
}
export function writeFlow(f: Flow): void {
  try { globalThis.localStorage?.setItem(FLOW, JSON.stringify(f)); } catch { /* storage blocked */ }
}
