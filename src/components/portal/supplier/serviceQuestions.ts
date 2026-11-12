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
export function outcome(questions: readonly Question[], answers: Record<number, Answer>): { own: string[]; partner: string[]; ownWords: string[]; declined: string[] } {
  const own = new Set<string>(), partner = new Set<string>(), words: string[] = [], declined = new Set<string>();
  const word = (w: string) => { const t = w.replace(/\s+/g, ' ').trim(); if (t.length >= 2 && !words.some((x) => x.toLowerCase() === t.toLowerCase())) words.push(t); };
  for (const q of questions) {
    const a = answers[q.id] ?? q.answer;
    if (!a || q.kind === 'licence') continue;
    if (q.kind === 'partner') {
      q.options.forEach((o, i) => {
        const v = a.per?.[String(i)];
        if (!v) return;
        if (v === 'no') { if (o.key) declined.add(o.key); return; }
        if (o.key) (v === 'own' ? own : partner).add(o.key); else word(o.label_en);
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
  return { own: [...own], partner: [...partner], ownWords: words, declined: [...declined].filter((k) => !own.has(k) && !partner.has(k)) };
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
