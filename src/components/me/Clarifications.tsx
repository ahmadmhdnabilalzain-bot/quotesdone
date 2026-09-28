// @ts-nocheck
'use client';
// QUESTIONS AND ADDITIONS ON A LIVE REQUEST — replaces RfqAssistant.
//
// RfqAssistant posted the customer's follow-up to inquiry_intake, which ignores inquiry_id, so every
// message became an orphan intake draft that no supplier ever saw (website audit 14 Sep 2026,
// BROKEN). And a supplier's question before the reveal had no channel at all (ABSENT). Both now
// meet on public.rfq_clarification:
//   add detail          -> customer_api rfq_note      (reaches every matched supplier)
//   supplier questions  -> messages_api clarify_list  (suppliers shown as Supplier A, B...)
//   answer one          -> messages_api clarify_answer (visible to every matched supplier)
// Contact details are stripped server-side; the panel only reports that it happened.
import { useEffect, useState } from 'react';
import * as m from 'motion/react-m';
import { AnimatePresence, useReducedMotion } from 'motion/react';
import { MessageCircleQuestion, CornerDownRight } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { Spinner, useDelayedFlag } from '@/components/ui/busy';
import { t, tf, errText } from './portalText';

export function Clarifications({ inq, token, lang, call }) {
  const reduce = useReducedMotion();
  const [open, setOpen] = useState(false);
  const [items, setItems] = useState(null);
  const [note, setNote] = useState(''); const [busy, setBusy] = useState(''); const [msg, setMsg] = useState(''); const [err, setErr] = useState('');
  const [answers, setAnswers] = useState({});
  const ansSpin = useDelayedFlag(!!busy);
  const closed = ['completed', 'closed', 'cancelled'].includes(String(inq.status));
  const load = () => call('messages_api', { action: 'clarify_list', inquiry_id: inq.id }, token)
    .then((j) => { if (j && j.ok) setItems(j.items || []); else { setItems([]); setErr(errText(j, lang)); } })
    .catch(() => { setItems([]); setErr(t(lang, 'err_generic')); });
  // Loaded once on mount so an unanswered supplier question can pull the panel open by itself: a
  // question the customer has to go looking for is a question that goes unanswered.
  useEffect(() => { load(); }, [inq.id]);
  const pending = (items || []).filter((i) => i.kind === 'question' && !i.answered_at).length;
  useEffect(() => { if (pending > 0) setOpen(true); }, [pending]);

  const addNote = async () => {
    const text = note.trim(); if (!text || busy) return;
    setBusy('note'); setErr(''); setMsg('');
    const j = await call('customer_api', { action: 'rfq_note', inquiry_id: inq.id, text }, token).catch(() => null);
    setBusy('');
    if (j && j.ok) { setNote(''); setMsg((j.notified ? tf(lang, 'cl_note_sent', { n: j.notified }) : t(lang, 'cl_note_sent0')) + (j.removed ? ' ' + t(lang, 'cl_removed') : '')); load(); }
    else setErr(errText(j, lang));
  };
  const answer = async (id) => {
    const text = String(answers[id] || '').trim(); if (!text || busy) return;
    setBusy('a' + id); setErr('');
    const j = await call('messages_api', { action: 'clarify_answer', id, text }, token).catch(() => null);
    setBusy('');
    if (j && j.ok) { setAnswers((a) => ({ ...a, [id]: '' })); load(); } else setErr(errText(j, lang));
  };

  if (!open) {
    return (
      <Button variant="link" className="h-auto self-start px-0" onClick={(e) => { e.stopPropagation(); setOpen(true); }}>
        <MessageCircleQuestion className="me-1.5 h-4 w-4" aria-hidden />{t(lang, 'cl_open')}
      </Button>
    );
  }
  return (
    <section className="qd-panel p-4 sm:p-5" onClick={(e) => e.stopPropagation()} aria-label={t(lang, 'cl_title')}>
      <h3 className="flex items-center gap-2 font-head text-[15px] font-semibold tracking-snug text-foreground"><MessageCircleQuestion className="h-4 w-4 text-primary" aria-hidden />{t(lang, 'cl_title')}</h3>
      <p className="mt-1 text-small leading-relaxed text-muted-foreground">{t(lang, 'cl_sub')}</p>

      <div className="mt-3 flex flex-col gap-2.5">
        {items == null ? (
          <div className="flex flex-col gap-2" aria-label={t(lang, 'cl_loading')}><span className="redact redact-bar w-2/3" /><span className="redact redact-bar w-1/2" /></div>
        ) : !items.length ? (
          <p className="text-[12.5px] text-muted-foreground">{t(lang, 'cl_none')}</p>
        ) : (
          <AnimatePresence initial={false}>
            {items.map((it) => (
              <m.div key={it.id} layout={!reduce} initial={reduce ? false : { opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }}
                className={cn('rounded-card border bg-secondary/20 p-3', it.kind === 'question' && !it.answered_at ? 'border-warn/40' : 'border-border')}>
                {it.kind === 'question' ? (
                  <>
                    <div className="font-mono text-label uppercase tracking-caps text-primary">{tf(lang, 'cl_asked', { label: lang === 'ar' ? String(it.supplier_label || '').replace('Supplier', 'المورّد') : it.supplier_label })}</div>
                    <p className="mt-0.5 text-[13px] text-foreground">{it.question}</p>
                    {it.answered_at ? (
                      <p className="mt-2 flex gap-1.5 text-[13px] text-muted-foreground"><CornerDownRight className="mt-0.5 h-3.5 w-3.5 shrink-0 rtl:-scale-x-100" aria-hidden /><span><b className="text-foreground">{t(lang, 'cl_answered')}: </b>{it.answer}</span></p>
                    ) : !closed ? (
                      <div className="mt-2 flex items-end gap-2">
                        <label className="sr-only" htmlFor={'qd-ans-' + it.id}>{t(lang, 'cl_answer_ph')}</label>
                        <textarea id={'qd-ans-' + it.id} rows={2} className="flex-1 resize-y rounded-lg border border-input bg-transparent px-3 py-2 text-[13px] text-foreground outline-none focus-visible:ring-1 focus-visible:ring-ring"
                          placeholder={t(lang, 'cl_answer_ph')} value={answers[it.id] || ''} onChange={(e) => setAnswers((a) => ({ ...a, [it.id]: e.target.value }))} />
                        {/* The button was disabled while sending but said nothing — the one thing
                            the founder's 18 Sep instruction names. Ring + label, shared rules. */}
                        <Button size="sm" aria-busy={ansSpin && busy === 'a' + it.id || undefined} className="gap-2" disabled={busy === 'a' + it.id || !String(answers[it.id] || '').trim()} onClick={() => answer(it.id)}>
                          {ansSpin && busy === 'a' + it.id ? <><Spinner />{t(lang, 'sending')}</> : t(lang, 'cl_answer')}
                        </Button>
                      </div>
                    ) : null}
                  </>
                ) : (
                  <>
                    <div className="font-mono text-label uppercase tracking-caps text-muted-foreground">{t(lang, 'cl_you_added')}</div>
                    <p className="mt-0.5 text-[13px] text-foreground">{it.answer}</p>
                  </>
                )}
              </m.div>
            ))}
          </AnimatePresence>
        )}
      </div>

      {!closed && (
        <div className="mt-3">
          <label className="sr-only" htmlFor={'qd-note-' + inq.id}>{t(lang, 'cl_note_label')}</label>
          <textarea id={'qd-note-' + inq.id} rows={2} className="w-full resize-y rounded-lg border border-input bg-transparent px-3 py-2 text-[13px] text-foreground outline-none focus-visible:ring-1 focus-visible:ring-ring"
            placeholder={t(lang, 'cl_note_ph')} value={note} onChange={(e) => setNote(e.target.value)} />
          <div className="mt-2 flex flex-wrap items-center gap-3">
            <Button size="sm" disabled={busy === 'note' || !note.trim()} onClick={addNote}>{busy === 'note' ? t(lang, 'nr_sending') : t(lang, 'cl_note_send')}</Button>
            {msg ? <span className="text-[12px] text-primary">{msg}</span> : null}
          </div>
        </div>
      )}
      {err ? <div className={cn('mt-2 text-[12.5px] text-danger')} role="alert">{err}</div> : null}
    </section>
  );
}
