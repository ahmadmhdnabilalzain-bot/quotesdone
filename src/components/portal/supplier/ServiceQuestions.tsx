'use client';
// SCREEN 2, "A FEW QUICK QUESTIONS" (12 Nov 2026, sales_engineer; built by it_engineer). Founder rulings 1647 (the agent asks where
// his documents are vague, broad or name a partner: "what sort of staff"; pools "through a subcontractor"), 1628 (he confirms,
// nothing is ticked for him) and 1645 ("some buttons are not clickable, there is no loading animation ... I am looking for
// perfection"). Report 3.9 Screen 2: at most 5 cards, one at a time, "2 of 4", chips, None of these, Something else, and per
// service own team / through a partner / not offered.
//
// EVERY TAP ANSWERS AT ONCE. A card's answer is his the moment he taps, the next card is shown in the same render, and the write
// (supplier_api services_answer: no model, one write) happens behind it; a write that fails says so in one line and is retried
// with his taps intact. The logic is serviceQuestions.ts, proved by serviceQuestions.test.mjs; this file only draws it.
import { useEffect, useId, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/busy';
import { Check } from 'lucide-react';
import { cn } from '@/lib/utils';
import { FLOW_COPY as F } from './servicesCopy';
import { advance, back, canSend, failedIds, togglePick, type Answer, type Cards, type Question } from './serviceQuestions';

// a chip: a 44 px target that shows it is pressed (scale and colour) and shows it is chosen (tick and teal)
export const chipCls = (on: boolean) => cn(
  'inline-flex min-h-11 select-none items-center gap-1.5 rounded-full border px-4 py-2 text-left text-[15px] leading-snug transition-[transform,background-color,border-color] duration-100 active:scale-[.96] motion-reduce:active:scale-100 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring',
  on ? 'border-primary bg-primary/15 font-medium text-foreground' : 'border-line2 bg-transparent text-foreground hover:border-teal');
const segCls = (on: boolean) => cn(
  'min-h-11 flex-1 select-none rounded-md border px-2 text-[14px] transition-[transform,background-color,border-color] duration-100 active:scale-[.96] motion-reduce:active:scale-100 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring',
  on ? 'border-primary bg-primary/15 font-semibold text-foreground' : 'border-line2 text-foreground hover:border-teal');
const inputCls = 'w-full rounded-md border border-input bg-transparent px-3 py-2.5 text-base leading-relaxed text-foreground placeholder:text-muted-foreground focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring';

/** A prompt the reading wrote as `Your profile says: "<his sentence>" <the question>`, split so his words read as his. */
export function splitPrompt(p: string): { quote: string | null; ask: string } {
  const m = /^Your profile says(?: these are delivered)?:?\s*"([^"]+)"\.?\s*(.+)$/s.exec(p);
  return m ? { quote: m[1], ask: m[2] } : { quote: null, ask: p };
}

export default function ServiceQuestions({ questions, cards, setCards, send, retry, retrying, onDone, onBackFirst, onChooseTrade }: {
  questions: Question[]; cards: Cards; setCards: (f: (c: Cards) => Cards) => void;
  send: (id: number, a: Answer) => void; retry: () => void; retrying: boolean;
  onDone: () => void; onBackFirst?: () => void; onChooseTrade?: () => void;
}) {
  const uid = useId();
  const byId = new Map(questions.map((q) => [q.id, q]));
  const q = byId.get(cards.ids[cards.index]);
  // the answer being built on this card (chips toggled, words typed) before Next; seeded from his saved answer when he comes Back
  const [draft, setDraft] = useState<Answer | undefined>(q ? cards.answers[q.id] : undefined);
  const [otherOpen, setOtherOpen] = useState(!!(q && cards.answers[q.id]?.other));
  const head = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    const a = q ? cards.answers[q.id] : undefined;
    setDraft(a); setOtherOpen(!!a?.other);
    // the new card's question is where the eye and a screen reader go, without scrolling the page under his thumb
    head.current?.focus({ preventScroll: true });
  }, [q?.id]); // oxlint-disable-line react-hooks/exhaustive-deps
  if (!q) return null;

  const commit = (a: Answer) => {
    const last = cards.index >= cards.ids.length - 1;
    setCards((c) => advance(c, q.id, a));
    send(q.id, a);
    if (last) onDone();
  };
  const goBack = () => { if (cards.index === 0) onBackFirst?.(); else setCards(back); };
  const failed = failedIds(cards);
  const { quote, ask } = splitPrompt(q.prompt_en);
  const partner = q.kind === 'partner';
  const single = !q.multi && q.kind !== 'nothing';

  return (
    <section aria-labelledby={uid + '-q'} data-testid="question-cards" data-kind={q.kind}>
      <div className="flex items-center justify-between gap-3">
        <h2 className="font-head text-[19px] font-semibold tracking-snug text-foreground">{F.questions_title}</h2>
        <span className="shrink-0 text-[14px] tabular-nums text-muted-foreground" data-testid="progress">{F.progress(cards.index + 1, cards.ids.length)}</span>
      </div>
      <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-muted" aria-hidden>
        <div className="h-full rounded-full bg-primary transition-[width] duration-200" style={{ width: `${((cards.index + 1) / cards.ids.length) * 100}%` }} />
      </div>

      {failed.length > 0 && (
        <div role="alert" className="mt-3 flex flex-wrap items-center gap-2 rounded-md border border-danger/40 bg-danger/10 px-3 py-2 text-[14px] text-foreground">
          <span className="min-w-0 flex-1">{F.answer_failed}</span>
          <Button type="button" variant="outline" className="min-h-11" disabled={retrying} aria-busy={retrying} onClick={retry}>
            {retrying ? <><Spinner />{F.retrying}</> : F.retry}
          </Button>
        </div>
      )}

      <div className="mt-4 rounded-lg border border-border p-4">
        {quote && <p className="text-[14px] leading-relaxed text-muted-foreground">{F.your_profile_says} <q dir="auto" className="italic">{quote}</q></p>}
        <h3 ref={head} tabIndex={-1} id={uid + '-q'} className={cn('text-[17px] font-semibold leading-snug text-foreground focus:outline-hidden', quote && 'mt-2')}>{ask}</h3>
        {q.multi && !partner && q.kind !== 'nothing' && <p className="mt-1 text-[14px] text-muted-foreground">{F.tap_all}</p>}

        {partner ? (
          <div className="mt-3 flex flex-col gap-3">
            {q.options.map((o, i) => (
              <fieldset key={i} className="min-w-0">
                <legend className="mb-1.5 text-[15px] font-medium text-foreground">{o.label_en}</legend>
                <div className="flex gap-2">
                  {(['own', 'partner', 'no'] as const).map((v) => {
                    const on = draft?.per?.[String(i)] === v;
                    return <button key={v} type="button" aria-pressed={on} className={segCls(on)}
                      onClick={() => setDraft((d) => ({ per: { ...(d?.per ?? {}), [String(i)]: v } }))}>
                      {v === 'own' ? F.partner_own : v === 'partner' ? F.partner_partner : F.partner_no}</button>;
                  })}
                </div>
              </fieldset>
            ))}
            <Button type="button" variant="outline" className="min-h-11 self-start"
              onClick={() => commit({ per: Object.fromEntries(q.options.map((_, i) => [String(i), 'partner' as const])) })}>{F.partner_all}</Button>
            <p className="text-[13px] text-muted-foreground">{F.partner_note}</p>
          </div>
        ) : q.kind === 'nothing' ? (
          <div className="mt-3">
            <label className="sr-only" htmlFor={uid + '-nothing'}>{F.nothing_label}</label>
            <textarea id={uid + '-nothing'} dir="auto" rows={3} maxLength={500} className={inputCls} placeholder={F.nothing_ph}
              value={draft?.other ?? ''} onChange={(e) => setDraft({ other: e.target.value })}
              onFocus={(e) => e.currentTarget.scrollIntoView({ block: 'center', behavior: 'smooth' })} />
            {onChooseTrade && <Button type="button" variant="link" className="mt-1 min-h-11 px-0" onClick={onChooseTrade}>{F.nothing_trade}</Button>}
          </div>
        ) : (
          <div className="mt-3 flex flex-wrap gap-2">
            {q.options.map((o, i) => {
              const on = !!draft?.picked?.includes(i);
              return <button key={i} type="button" role={single ? 'radio' : 'checkbox'} aria-checked={on} className={chipCls(on)}
                onClick={() => (single ? commit({ picked: [i] }) : setDraft((d) => togglePick(q, d, i)))}>
                {on ? <Check aria-hidden className="h-4 w-4 shrink-0 text-primary" /> : null}<span dir="auto">{o.label_en}</span></button>;
            })}
          </div>
        )}

        {!partner && q.kind !== 'nothing' && !single && (
          <div className="mt-3 flex flex-wrap gap-2 border-t border-border pt-3">
            {q.kind === 'shown'
              ? <button type="button" className={chipCls(!!draft?.only_inside)} onClick={() => commit({ only_inside: true })}>{F.only_inside}</button>
              : <button type="button" className={chipCls(!!draft?.none)} onClick={() => commit({ none: true })}>{F.none}</button>}
            {q.kind !== 'umbrella' && q.kind !== 'shown' && q.kind !== 'new_key' && (
              <button type="button" aria-expanded={otherOpen} className={chipCls(otherOpen)} onClick={() => setOtherOpen((x) => !x)}>{F.other}</button>
            )}
          </div>
        )}
        {otherOpen && !partner && q.kind !== 'nothing' && (
          <div className="mt-3">
            <label htmlFor={uid + '-other'} className="text-[14px] font-medium text-foreground">{F.other_label}</label>
            <input id={uid + '-other'} dir="auto" autoFocus maxLength={120} className={cn(inputCls, 'mt-1')} placeholder={F.other_ph}
              value={draft?.other ?? ''} onChange={(e) => setDraft((d) => ({ ...(d ?? {}), none: undefined, other: e.target.value }))}
              onFocus={(e) => e.currentTarget.scrollIntoView({ block: 'center', behavior: 'smooth' })}
              onKeyDown={(e) => { if (e.key === 'Enter' && draft && canSend(q, draft)) { e.preventDefault(); commit(draft); } }} />
          </div>
        )}
        {q.kind === 'licence' && <p className="mt-3 text-[13px] text-muted-foreground">{F.licence_note}</p>}
      </div>

      <div className="mt-4 flex items-center justify-between gap-3">
        {cards.index > 0 || onBackFirst ? <Button type="button" variant="outline" className="min-h-11 min-w-24" onClick={goBack}>{F.back}</Button> : <span />}
        {!single && <Button type="button" className="min-h-11 min-w-32" disabled={!canSend(q, draft)} onClick={() => draft && commit(draft)}>{F.next}</Button>}
      </div>
    </section>
  );
}
