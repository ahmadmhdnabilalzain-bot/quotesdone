'use client';
// WhatsAppChoice — "Is this number on WhatsApp?", asked once the mobile is verified. One component for
// BOTH portals (customer /me and supplier /portal), so the two can never ask it differently.
//
// FOUNDER, 14 Sep 2026: "what if the customer has whatsapp on another phone number, maybe we should
// confirm this point through the sign up". Three answers; a different number is verified by a code
// sent over WhatsApp itself and is never used until it is; email stays the identity.
//
// Three placements, one behaviour each:
//   signup   — inside registration, after the mobile is verified. The step ends when an answer is saved,
//              or when WhatsApp verification is unavailable (said plainly; signup continues on email+SMS).
//   prompt   — a one-time card on the dashboard for accounts that were never asked. It never blocks:
//              "Ask me later" records that the question was asked (kyc whatsapp_later) and closes.
//   settings — shows the current state and lets them change it. A new number must be verified again,
//              and the old verified one stays in use until then (the server keeps it; this says so).
//
// Every word and every decision lives in whatsappChoiceText.ts, where node --test can reach them.
import { useEffect, useId, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';
import { call } from './supplier/api';
import { waText, waErrorText, waUnavailable, waSentBySms, waCurrentKey, type WaKey, type WaLang, type WaMode, type WaOpt, type WaState } from './whatsappChoiceText';

type Props = {
  token: string | null | undefined;
  lang: WaLang;
  mode: WaMode;
  current?: WaState | null;
  // The verified mobile, shown so "this number" names a number. Optional: the question still reads without it.
  mobile?: string | null;
  onDone: () => void;
  /** Told at the press of Continue, before the answer is saved, so the sign-up form can close the question at once (registration
   * walk M15, 12 Nov 2026); onChooseFailed then reopens it with the reason. */
  onChoose?: (opt: string) => void;
  onChooseFailed?: (message: string) => void;
};

const OPTS: [WaOpt, WaKey][] = [['same', 'opt_same'], ['other', 'opt_other'], ['none', 'opt_none']];

export function WhatsAppChoice({ token, lang, mode, current, mobile, onDone, onChoose, onChooseFailed }: Props) {
  const tx = (k: WaKey) => waText(lang, k);
  const [editing, setEditing] = useState(mode !== 'settings');
  const [opt, setOpt] = useState<WaOpt | ''>('');
  const [phone, setPhone] = useState('');
  // false, or the channel that carried the code ('whatsapp' | 'sms') so the screen says which.
  const [sent, setSent] = useState<false | string>(false);
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState<'' | 'choose' | 'send' | 'verify' | 'later'>('');
  const [err, setErr] = useState('');
  const [unavailable, setUnavailable] = useState(false);
  const [saved, setSaved] = useState(false);
  const id = useId();
  const phoneRef = useRef<HTMLInputElement>(null);
  const codeRef = useRef<HTMLInputElement>(null);
  const changeRef = useRef<HTMLButtonElement>(null);

  // Focus follows the step: the number field when "different number" is picked, the code field once a
  // code is on its way — so a keyboard or screen-reader user is never left on a control that vanished.
  useEffect(() => { if (opt === 'other' && !sent) phoneRef.current?.focus(); }, [opt, sent]);
  useEffect(() => { if (sent) codeRef.current?.focus(); }, [sent]);

  const reset = () => { setOpt(''); setPhone(''); setSent(false); setCode(''); setErr(''); setUnavailable(false); };
  const finish = () => {
    setSaved(true);
    if (mode === 'settings') { reset(); setEditing(false); requestAnimationFrame(() => changeRef.current?.focus()); }
    onDone();
  };
  const kyc = (body: Record<string, unknown>): Promise<any> => call('kyc', body, token).catch(() => null);

  const choose = async () => {
    if (!opt) { setErr(tx('err_bad_opt')); return; }
    if (opt === 'other') return;
    setBusy('choose'); setErr(''); onChoose?.(opt);
    const j = await kyc({ action: 'whatsapp_choose', opt });
    setBusy('');
    if (j && j.ok) finish(); else { setErr(waErrorText(lang, j)); onChooseFailed?.(waErrorText(lang, j)); }
  };
  const sendCode = async () => {
    if (!phone.trim()) { setErr(tx('err_bad_phone')); phoneRef.current?.focus(); return; }
    setBusy('send'); setErr('');
    const j = await kyc({ action: 'whatsapp_send_code', phone: phone.trim() });
    setBusy('');
    if (waUnavailable(j)) { setUnavailable(true); return; }
    if (j && j.ok) setSent(waSentBySms(j) ? 'sms' : 'whatsapp'); else setErr(waErrorText(lang, j));
  };
  const verify = async () => {
    if (!code.trim()) { setErr(tx('err_wrong_code')); codeRef.current?.focus(); return; }
    setBusy('verify'); setErr('');
    const j = await kyc({ action: 'whatsapp_verify', phone: phone.trim(), code: code.trim() });
    setBusy('');
    if (j && j.ok) finish(); else setErr(waErrorText(lang, j));
  };
  // Records that the question was asked, then gets out of the way whatever the server answers: a
  // prompt that could trap someone on the dashboard would be worse than asking again next time.
  const later = async () => { setBusy('later'); await kyc({ action: 'whatsapp_later' }); setBusy(''); onDone(); };

  const chooser = (
    <>
      <fieldset className="mt-3">
        {/* Native radios in a fieldset ARE the radio group: arrow keys, one tab stop, legend announced. */}
        <legend className="sr-only">{tx('q_title')}</legend>
        <div className="flex flex-col gap-2">
          {OPTS.map(([v, k]) => (
            <label key={v} className={cn('flex min-h-11 cursor-pointer items-center gap-2.5 rounded-md border px-3 py-2 text-[13.5px] text-foreground transition-colors',
              opt === v ? 'border-primary/60 bg-primary/10' : 'border-border hover:bg-secondary/40')}>
              <input type="radio" name={id + '-opt'} value={v} checked={opt === v} className="h-4 w-4 shrink-0 accent-primary"
                onChange={() => { setOpt(v); setErr(''); setUnavailable(false); setSent(false); setCode(''); }} />
              {tx(k)}
            </label>
          ))}
        </div>
      </fieldset>

      {opt === 'other' && !unavailable && <div className="mt-3">
        <label htmlFor={id + '-phone'} className="mb-1 block text-[12px] font-semibold text-muted-foreground">{tx('other_label')}</label>
        <div className="flex flex-wrap gap-2.5">
          <Input ref={phoneRef} id={id + '-phone'} type="tel" dir="ltr" inputMode="tel" autoComplete="tel" className="min-w-[200px] flex-1"
            placeholder={tx('other_ph')} value={phone} disabled={!!sent}
            onChange={(e) => setPhone(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && !sent && sendCode()} />
          {!sent && <Button type="button" size="sm" className="min-h-10" busy={busy === 'send'} disabled={busy === 'send'} onClick={sendCode}>{busy === 'send' ? tx('sending') : tx('send_code')}</Button>}
        </div>
        {sent && <>
          <p role="status" className="my-2 text-xs leading-relaxed text-muted-foreground">{tx(sent === 'sms' ? 'code_sent_sms' : 'code_sent')}</p>
          <label htmlFor={id + '-code'} className="mb-1 block text-[12px] font-semibold text-muted-foreground">{tx('code_label')}</label>
          <div className="flex flex-wrap gap-2.5">
            <Input ref={codeRef} id={id + '-code'} dir="ltr" inputMode="numeric" autoComplete="one-time-code" className="min-w-[140px] flex-1 font-mono tracking-[0.2em]"
              value={code} onChange={(e) => setCode(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && verify()} />
            <Button type="button" size="sm" className="min-h-10" busy={busy === 'verify'} disabled={busy === 'verify'} onClick={verify}>{busy === 'verify' ? tx('verifying') : tx('verify')}</Button>
          </div>
          <Button type="button" variant="link" className="mt-1 h-auto px-0" onClick={() => { setSent(false); setCode(''); setErr(''); }}>{tx('change_number')}</Button>
        </>}
      </div>}

      {unavailable && <div role="status" className="mt-3 rounded-md border border-border bg-secondary/30 px-3 py-2.5">
        <div className="text-[13px] font-semibold text-foreground">{tx('unavailable_h')}</div>
        <div className="mt-0.5 text-[12.5px] leading-relaxed text-muted-foreground">{tx('unavailable_body')}</div>
      </div>}

      {err && <div role="alert" className="mt-2 text-[13px] text-danger-fg">{err}</div>}

      <div className="mt-3 flex flex-wrap items-center gap-2.5">
        {opt !== 'other' && <Button type="button" size="sm" busy={busy === 'choose'} disabled={busy === 'choose' || !opt} onClick={choose}>{busy === 'choose' ? tx('saving') : tx('continue')}</Button>}
        {/* Unavailable (no Twilio credentials at all) ends only the dashboard card. Sign-up has no skip
            (founder, 15 Sep 2026): the person answers Yes or "I do not use WhatsApp" instead. */}
        {unavailable && mode === 'prompt' && <Button type="button" size="sm" busy={busy === 'later'} disabled={busy === 'later'} onClick={later}>{tx('continue')}</Button>}
        {mode === 'prompt' && <Button type="button" variant="ghost" size="sm" className="text-muted-foreground" disabled={busy === 'later'} onClick={later}>{tx('later')}</Button>}
        {mode === 'settings' && <Button type="button" variant="ghost" size="sm" onClick={() => { reset(); setEditing(false); requestAnimationFrame(() => changeRef.current?.focus()); }}>{tx('cancel')}</Button>}
      </div>
    </>
  );

  if (mode === 'settings') {
    const curKey = waCurrentKey(current);
    return (
      <div dir={lang === 'ar' ? 'rtl' : 'ltr'} className="min-w-0">
        <div id={id + '-q'} className="text-[13px] text-foreground">
          {tx(curKey)}{curKey === 'cur_other' && current && current.phone ? <> · <bdi dir="ltr">{current.phone}</bdi></> : null}
        </div>
        {saved && !editing && <p role="status" className="mt-1 text-[11.5px] text-ok-fg">{tx('saved')}</p>}
        {!editing
          ? <Button ref={changeRef} type="button" variant="outline" size="sm" className="mt-2" onClick={() => { setSaved(false); setEditing(true); }}>{tx('change')}</Button>
          : <>{current && current.opt === 'other' && current.verified ? <p className="mt-1 text-[11.5px] text-muted-foreground">{tx('keep_note')}</p> : null}{chooser}</>}
      </div>
    );
  }

  return (
    <section dir={lang === 'ar' ? 'rtl' : 'ltr'} aria-labelledby={id + '-q'}
      className={cn('rounded-lg border p-4', mode === 'prompt' ? 'border-primary/35 bg-card' : 'border-border bg-secondary/20')}>
      <h2 id={id + '-q'} className="text-[15px] font-bold text-foreground">
        {mobile ? <>{tx('q_mobile_pre')}<bdi dir="ltr">{mobile}</bdi>{tx('q_mobile_post')}</> : tx('q_title')}
      </h2>
      <p className="mt-1 max-w-[62ch] text-[13px] leading-relaxed text-muted-foreground">{tx('q_sub')}</p>
      {chooser}
    </section>
  );
}
