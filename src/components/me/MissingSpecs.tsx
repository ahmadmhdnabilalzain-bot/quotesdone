// @ts-nocheck
'use client';
// A REQUEST HELD FOR ITS SPECS IS COMPLETED BY ITS CUSTOMER, ONE PLAIN QUESTION AT A TIME
// (customer_support 29 Sep 2026, founder ledger 1018; step-by-step helper sales_engineer 5 Oct 2026, T2).
//
// Each required spec the hold check finds missing (customer_api missing_specs) is one step, asked in the intake's
// own plain words in the customer's language. A spec with options is multiple choice; "Something else" or a spec
// without options takes typed words; "Not sure" is always offered and records nothing, so a guess never reaches
// suppliers; the request stays held and a handoff to the sales engineer is opened for those specs (customer_api).
// Answer buttons show Arabic labels to an Arabic customer (./specOptionsAr.ts); the saved value stays English. On the last step the real answers are
// saved (customer_api add_missing_specs), which re-runs the hold check; when nothing is missing the request is
// released and this panel disappears. Step rules: ./specSteps.ts (checked by specSteps.test.mjs).
// scripts/sql/a_held_request_takes_its_missing_specs_from_the_customer_and_is_released_when_complete.sql
import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Spinner, useDelayedFlag } from '@/components/ui/busy';
import { t, errText } from './portalText';
import { choicesFor, needsText, stepDone, collectAnswers, notSureKeys, optionLabel, NOT_SURE, OTHER } from './specSteps';
import { SPEC_OPTION_AR } from './specOptionsAr';

export function MissingSpecs({ inq, token, lang, call, onChange }) {
  const [held, setHeld] = useState(null);
  const [step, setStep] = useState(0);
  const [picks, setPicks] = useState({}); const [texts, setTexts] = useState({});
  const [busy, setBusy] = useState(false); const [msg, setMsg] = useState(''); const [err, setErr] = useState('');
  const spin = useDelayedFlag(busy);
  const load = () => call('customer_api', { action: 'missing_specs', inquiry_id: inq.id, lang }, token)
    .then((j) => { setHeld(j && j.ok && j.held ? j : null); setStep(0); }, () => setHeld(null));
  useEffect(() => { load(); }, [inq.id, lang]);
  if (!held || !Array.isArray(held.missing) || !held.missing.length) return msg ? <p className="text-[12.5px] text-primary" role="status">{msg}</p> : null;

  const missing = held.missing;
  const i = Math.min(step, missing.length - 1);
  const m = missing[i];
  const last = i === missing.length - 1;
  const pick = picks[m.key]; const text = texts[m.key] || '';
  const done = stepDone(m, pick, text);
  const label = (c) => c === NOT_SURE ? t(lang, 'ms_not_sure') : c === OTHER ? t(lang, 'ms_other') : optionLabel(c, lang, SPEC_OPTION_AR);
  const id = 'qd-ms-' + inq.id + '-' + m.key;

  const save = async () => {
    if (busy) return;
    const answers = collectAnswers(missing, picks, texts);
    // "Not sure" is sent as keys only: it records no answer, and the server opens a handoff to the sales engineer.
    const not_sure = notSureKeys(missing, picks);
    const unsure = not_sure.length > 0;
    if (!Object.keys(answers).length && !unsure) return;
    setBusy(true); setErr(''); setMsg('');
    const j = await call('customer_api', { action: 'add_missing_specs', inquiry_id: inq.id, answers, not_sure }, token).catch(() => null);
    setBusy(false);
    if (j && j.ok) {
      setPicks({}); setTexts({});
      setMsg(t(lang, j.released ? 'ms_released' : unsure ? 'ms_not_sure_note' : 'ms_saved') + (j.held_for_english || j.kept_from_suppliers ? ' ' + (lang === 'ar' ? j.notice : j.notice_en) : ''));
      await load();
      if (j.released && onChange) onChange();
    } else setErr(errText(j, lang));
  };

  return (
    <section className="qd-panel border-warn/40 p-4 sm:p-5" onClick={(e) => e.stopPropagation()} aria-label={t(lang, 'ms_title')} data-testid="missing-specs" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <h3 className="font-head text-[15px] font-semibold tracking-snug text-foreground">{t(lang, 'ms_title')}</h3>
      <p className="mt-1 text-small leading-relaxed text-muted-foreground">{t(lang, 'ms_sub')}</p>
      <fieldset className="mt-3" data-testid="missing-specs-step">
        <legend className="text-[12px] text-muted-foreground">{t(lang, 'ms_q')} {i + 1} {t(lang, 'ms_of')} {missing.length}</legend>
        <p className="mt-1 text-[13.5px] font-semibold text-foreground" id={id + '-q'}>{m.ask}</p>
        <div className="mt-2 flex flex-wrap gap-2" role="radiogroup" aria-labelledby={id + '-q'}>
          {choicesFor(m).map((c) => (
            <button key={c} type="button" role="radio" aria-checked={pick === c}
              onClick={() => setPicks((a) => ({ ...a, [m.key]: c }))}
              className={'rounded-full border px-3 py-1.5 text-[13px] focus-visible:outline-hidden focus-visible:ring-1 focus-visible:ring-ring ' + (pick === c ? 'border-primary bg-primary/10 text-foreground' : 'border-input text-muted-foreground hover:text-foreground')}>
              {label(c)}
            </button>
          ))}
        </div>
        {needsText(m, pick) && pick !== NOT_SURE ? (
          <input id={id} aria-labelledby={id + '-q'} value={text} maxLength={300} placeholder={t(lang, 'ms_other_ph')}
            inputMode={m.type === 'number' ? 'decimal' : undefined} autoComplete="off"
            onChange={(e) => setTexts((a) => ({ ...a, [m.key]: e.target.value }))}
            className="mt-2 w-full rounded-lg border border-input bg-transparent px-3 py-2 text-[13px] text-foreground outline-hidden focus-visible:ring-1 focus-visible:ring-ring" />
        ) : null}
      </fieldset>
      <div className="mt-3 flex flex-wrap items-center gap-3">
        {i > 0 ? <Button size="sm" variant="outline" disabled={busy} onClick={() => setStep(i - 1)}>{t(lang, 'ms_back')}</Button> : null}
        {last ? (
          <Button size="sm" aria-busy={spin || undefined} className="gap-2" disabled={busy || !done} onClick={save}>
            {spin ? <><Spinner />{t(lang, 'saving')}</> : t(lang, 'ms_save')}
          </Button>
        ) : <Button size="sm" disabled={!done} onClick={() => setStep(i + 1)}>{t(lang, 'ms_next')}</Button>}
        {msg ? <span className="text-[12px] text-primary" role="status">{msg}</span> : null}
      </div>
      {err ? <div className="mt-2 text-[12.5px] text-danger" role="alert">{err}</div> : null}
    </section>
  );
}
