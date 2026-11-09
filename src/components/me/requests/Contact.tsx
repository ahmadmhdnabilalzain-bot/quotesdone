// @ts-nocheck
'use client';
import { useEffect, useState } from 'react';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Seal } from '@/components/ui/sealed';
import { useBusy, BusyButton, BusyNote } from '@/components/ui/busy';
import { cn } from '@/lib/utils';
import { RevealGuarantee } from '../RevealGuarantee';
import { useConfirm } from '../ConfirmDialog';
import { t, tf, errText } from '../portalText';
import { call } from '../api';
import { aed } from '../format';
import { S } from '../styles';

// The revealed name arrives sealed and the bar slides off in gold — once, on the reveal itself.
function OpenSeal({ play, children }) {
  const [open, setOpen] = useState(!play);
  useEffect(() => { if (open) return; const id = setTimeout(() => setOpen(true), 80); return () => clearTimeout(id); }, []);
  return <Seal open={open} className="qd-revealed text-accent! max-w-full">{children}</Seal>;
}

function Contact({ c, q, token, onChange, lang, won, terms, play = false }) {
  const s = c.supplier || {};
  const [rating, setRating] = useState(0); const [rated, setRated] = useState(!!(q && q.rated)); const [done, setDone] = useState('');
  // THE WORDS ARE OPTIONAL AND COME AFTER THE STARS (operator, 17 Sep 2026). Until tonight
  // `reviews_reason_required` demanded a 10-character comment, this widget sent none, and every
  // rating since 8 Aug 2026 failed with a 500 — public.reviews held 0 rows. Stars alone are now
  // enough, so the stars still post on the press with nothing to fill in first. The box is offered
  // only once that rating is SAVED, and it upserts the same review row (UNIQUE transaction_id), so
  // a customer who writes nothing has still rated and a customer who writes something is adding to
  // a rating that is already counted. Nothing here can block a rating.
  const [note, setNote] = useState(''); const [noteSaved, setNoteSaved] = useState(false); const [noteErr, setNoteErr] = useState('');
  // PHOTOS OF THE FINISHED JOB (T2): offered once the rating is saved, up to 5, sent ONE request per
  // photo so no request carries more than one 5 MB image. The server re-checks everything
  // (customer_api/review_photos.ts); the checks here only spare the customer a wasted upload.
  const [photoUrls, setPhotoUrls] = useState<string[]>([]); const [phErr, setPhErr] = useState(''); const [phDone, setPhDone] = useState('');
  // A rated review may already carry photos from an earlier visit: show them and count them.
  useEffect(() => {
    if (!rated || !q || !q.id) return;
    let live = true;
    call('customer_api', { action: 'review_photos', quote_id: q.id }, token).then((j) => { if (live && j && j.ok) setPhotoUrls(j.photo_urls || []); }).catch(() => {});
    return () => { live = false; };
  }, [rated, q && q.id, token]);
  const addPhotos = (files: FileList | null) => act.run('photos', async () => {
    setPhErr(''); setPhDone('');
    const list = Array.from(files || []);
    if (!list.length) return;
    if (photoUrls.length + list.length > 5) { setPhErr(t(lang, 'err_photo_count')); return; }
    for (const f of list) {
      if (!/^image\/(jpeg|png|webp)$/.test(f.type)) { setPhErr(t(lang, 'err_photo_type')); return; }
      if (f.size > 5 * 1024 * 1024) { setPhErr(t(lang, 'err_photo_size')); return; }
    }
    for (const f of list) {
      const b64 = await new Promise<string>((res, rej) => { const r = new FileReader(); r.onload = () => res(String(r.result)); r.onerror = rej; r.readAsDataURL(f); }).catch(() => '');
      const j = await call('customer_api', { action: 'add_review_photos', quote_id: q.id, photos: [{ b64 }] }, token).catch(() => null);
      if (!(j && j.ok)) { setPhErr(errText(j, lang, 'err_photo_fail')); return; }
      setPhotoUrls(j.photo_urls || []);
    }
    setPhDone(t(lang, 'c_ph_done'));
  });
  const [dialog, ask] = useConfirm(lang);
  const g = terms || {};
  // The three actions on a revealed supplier are all round trips and none of them said so: the stars
  // stayed pressable during the call and showed nothing, and Hire/Refund could be pressed twice.
  // One keyed state for all three — only one of them can sensibly be running at a time.
  const act = useBusy();
  // The stars fill optimistically (the press must feel instant), so a failure has to put them BACK.
  // Leaving the attempted rating lit beside a failure message is the screen telling two stories.
  const rate = (n) => { const prev = rating; setRating(n); return act.run('rate', async () => { const j = await call('customer_api', { action: 'rate_supplier', quote_id: q.id, rating: n }, token).catch(() => null); if (j && j.ok) { setRated(true); setDone(t(lang, 'c_thanks')); } else { setRating(prev); setDone(errText(j, lang, 'c_rate_fail')); } }); };
  // Re-sends the star the customer just pressed: the upsert keys on transaction_id, so this is an
  // UPDATE of their own review, never a second one. Offered only when `rating >= 1` — i.e. they
  // rated in THIS session — because a rating carried over from a previous visit is a star value
  // this component does not hold and must not guess at.
  const saveNote = () => act.run('note', async () => {
    setNoteErr('');
    const j = await call('customer_api', { action: 'rate_supplier', quote_id: q.id, rating, comment: note }, token).catch(() => null);
    if (j && j.ok) { setNoteSaved(true); setDone(t(lang, 'c_note_done')); } else setNoteErr(errText(j, lang, 'c_rate_fail'));
  });
  const refund = async () => { if (!(await ask(tf(lang, 'c_refund_confirm', { c: g.chase_after_days, w: g.window_days, bmin: g.bank_min_days, bmax: g.bank_max_days }), { title: t(lang, 'c_refund'), confirm: t(lang, 'c_refund') }))) return; await act.run('refund', async () => { const j = await call('customer_api', { action: 'request_refund', quote_id: q.id }, token).catch(() => null); setDone(j && j.ok ? t(lang, 'c_refund_ok') + (j.refund_ref ? ' ' + tf(lang, 'c_refund_ref', { r: j.refund_ref }) : '') : (j && j.message) || errText(j, lang, 'c_refund_fail')); }); };
  // D4: the refund case and the chief executive's decision reference, from the refunds row itself.
  const gq = q.guarantee || {};
  const hire = async () => { if (!(await ask(t(lang, 'c_hire_confirm'), { title: t(lang, 'c_hire'), confirm: t(lang, 'c_hire') }))) return; await act.run('hire', async () => { const j = await call('customer_api', { action: 'complete_inquiry', quote_id: q.id }, token).catch(() => null); if (j && j.ok) { setDone(t(lang, 'c_hired')); if (onChange) onChange(); } else setDone(errText(j, lang, 'c_update_fail')); }); };
  const date = (d) => new Date(d).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  return (<div className="mt-2.5 flex flex-col gap-2.5">{dialog}
    <div className="rounded-card border border-accent/35 bg-accent/6 p-3.5">
      <div className="flex flex-wrap items-center gap-2"><Badge variant="revealed" dot className="text-accent! font-mono uppercase tracking-caps">{t(lang, 'q_unlocked')}</Badge><div className="min-w-0 font-head text-[16px] font-semibold tracking-snug"><OpenSeal play={play}>{s.company_name || t(lang, 'c_supplier')}</OpenSeal></div></div>
      {q && q.revealed_at ? <div className={cn(S.sub, 'mt-0.5')}>{tf(lang, 'c_revealed_on', { d: date(q.revealed_at) })}</div> : null}
      {won ? <div className="mt-0.5 text-[12px] font-bold text-primary">🏆 {t(lang, 'c_hired_badge')}</div> : null}
      <div className={cn(S.sub, 'mt-0.5')}>{tf(lang, 'c_paid', { fee: aed(q.total_charged ?? q.reveal_fee) })}</div>
      <div className="mt-1.5 flex flex-wrap gap-3.5">
        {s.phone && <a href={'tel:' + s.phone} className="font-semibold text-primary">📞 <bdi dir="ltr">{s.phone}</bdi></a>}
        {s.whatsapp && <a href={'https://wa.me/' + String(s.whatsapp).replace(/[^0-9]/g, '')} target="_blank" rel="noopener" className="font-semibold text-primary">WhatsApp</a>}
        {s.email && <a href={'mailto:' + s.email} className="font-semibold text-primary">✉ <bdi dir="ltr">{s.email}</bdi></a>}
        {s.website && <a href={/^https?:/.test(s.website) ? s.website : 'https://' + s.website} target="_blank" rel="noopener" className="font-semibold text-primary">{t(lang, 'c_website')}</a>}
      </div>
      <div className="mt-2.5 flex flex-wrap items-center gap-4">
        {/* A11Y (5 Aug 2026): real buttons carrying their value, in a labelled group. */}
        {/* The stars stay after a rating (audit 21 Sep 2026, item 18): rate_supplier upserts the one
            review row, so pressing another star CHANGES the rating rather than adding a second one.
            A rating from an earlier visit is a star value this component does not hold, so those
            stars show empty with "you have rated — press a star to change it" beside them. */}
        <span role="group" aria-label={t(lang, rated ? 'c_rate_change' : 'c_rate_group')} aria-busy={(act.busy && act.key === 'rate') || undefined} className="text-lg tracking-widest text-muted-foreground/50">{[1, 2, 3, 4, 5].map((n) => <button key={n} type="button" disabled={act.pending} onClick={() => rate(n)} aria-label={tf(lang, 'c_rate_n', { n })} className={cn('cursor-pointer border-0 bg-transparent p-0 leading-none disabled:cursor-progress', n <= rating && 'text-amber-400')}>★</button>)}</span>
        {rated ? <span className={S.sub}>{t(lang, rating >= 1 ? 'c_rated' : 'c_rate_change')}</span> : null}
        <BusyNote busy={act.busy && act.key === 'rate'}>{t(lang, 'q_wait')}</BusyNote>
        <BusyButton busy={act} act="hire" variant="link" className="h-auto px-0" busyLabel={t(lang, 'q_wait')} onClick={hire}>{t(lang, 'c_hire')}</BusyButton>
        <BusyButton busy={act} act="refund" variant="link" className="h-auto px-0" busyLabel={t(lang, 'q_wait')} onClick={refund}>{t(lang, 'c_refund')}</BusyButton>
      </div>
      {done && <div className={cn(S.sub, 'mt-1.5 text-primary')} role="status">{done}</div>}
      {/* Offered only after the rating is saved, and only for a star pressed in this session. An
          `Input` rather than a textarea on purpose: "a few words" is one line, and the kit has no
          textarea — a new control for one field is a control to maintain for one field. */}
      {rated && rating >= 1 && !noteSaved ? (
        <div className="mt-2.5 border-t border-accent/25 pt-2.5">
          <label className="block text-[12px] font-semibold text-muted-foreground" htmlFor={'rv-' + q.id}>{t(lang, 'c_note_h')}</label>
          <div className="mt-1.5 flex flex-wrap items-center gap-2">
            {/* rate_supplier accepts stars alone; a comment, if given, must be 10+ characters
                (review_comment_too_short). The button waits for that length so the refusal is
                never seen; the hint says why the button is waiting. */}
            <Input id={'rv-' + q.id} value={note} maxLength={500} minLength={10} aria-describedby={'rv-hint-' + q.id + (noteErr ? ' rv-err-' + q.id : '')} aria-invalid={noteErr ? true : undefined} onChange={(e) => { setNote(e.target.value); setNoteErr(''); }} placeholder={t(lang, 'c_note_ph')} className="min-w-0 flex-1" />
            <BusyButton busy={act} act="note" size="sm" variant="secondary" busyLabel={t(lang, 'q_wait')} disabled={note.trim().length < 10} onClick={saveNote}>{t(lang, 'c_note_save')}</BusyButton>
          </div>
          <div id={'rv-hint-' + q.id} className={S.hint}>{t(lang, 'c_note_min')}</div>
          {noteErr && <div id={'rv-err-' + q.id} className={S.err} role="alert">{noteErr}</div>}
        </div>
      ) : null}
      {rated ? (
        <div className="mt-2.5 border-t border-accent/25 pt-2.5">
          <label className="block text-[12px] font-semibold text-muted-foreground" htmlFor={'rp-' + q.id}>{t(lang, 'c_ph_h')}</label>
          {photoUrls.length ? <div className="mt-1.5 flex flex-wrap gap-2">{photoUrls.map((u, i) => <img key={u} src={u} alt={tf(lang, 'c_ph_alt', { n: i + 1 })} width={64} height={64} loading="lazy" className="size-16 rounded-md border border-border object-cover" />)}</div> : null}
          {photoUrls.length < 5 ? <div className="mt-1.5 flex flex-wrap items-center gap-2">
            <input id={'rp-' + q.id} type="file" accept="image/jpeg,image/png,image/webp" multiple disabled={act.pending} aria-describedby={'rp-hint-' + q.id + (phErr ? ' rp-err-' + q.id : '')} aria-invalid={phErr ? true : undefined} onChange={(e) => { addPhotos(e.target.files); e.target.value = ''; }} className="min-w-0 max-w-full text-[13px] file:me-2 file:rounded-md file:border file:border-border file:bg-background file:px-2.5 file:py-1 file:text-[13px] file:font-semibold" />
            <BusyNote busy={act.busy && act.key === 'photos'}>{t(lang, 'q_wait')}</BusyNote>
          </div> : null}
          <div id={'rp-hint-' + q.id} className={S.hint}>{t(lang, 'c_ph_hint')}</div>
          {phDone && <div className={cn(S.sub, 'mt-1 text-primary')} role="status">{phDone}</div>}
          {phErr && <div id={'rp-err-' + q.id} className={S.err} role="alert">{phErr}</div>}
        </div>
      ) : null}
      {gq.refund_ref ? <div className={cn(S.sub, 'mt-1.5')}>{tf(lang, 'c_refund_ref', { r: gq.refund_ref })}{' · '}{gq.decision_ref ? tf(lang, 'c_decision_ref', { d: gq.decision_ref }) : t(lang, 'c_decision_wait')}</div> : null}
    </div>
    {/* The clock on the customer's own reveal. Hidden once the fee can no longer be refunded
        (hired or rated), because a running clock on a promise that no longer applies misleads. */}
    {q.guarantee && !won && !rated ? <RevealGuarantee lang={lang} fee={aed(q.reveal_fee)} terms={terms} facts={q.guarantee} compact /> : null}
  </div>);
}
export { Contact };
