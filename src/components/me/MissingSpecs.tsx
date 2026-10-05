// @ts-nocheck
'use client';
// A REQUEST HELD FOR ITS SPECS IS COMPLETED BY ITS CUSTOMER (customer_support, 29 Sep 2026; founder ledger 1018).
//
// One field per required spec the hold check finds missing (customer_api missing_specs), labelled with the intake's
// own plain question in the customer's language; the field's options are offered as suggestions and anything may be
// typed. Saving (customer_api add_missing_specs) re-runs the hold check on the server; when nothing is missing the
// request is released and this panel disappears. Nothing shows on a request that is complete.
// scripts/sql/a_held_request_takes_its_missing_specs_from_the_customer_and_is_released_when_complete.sql
import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Spinner, useDelayedFlag } from '@/components/ui/busy';
import { t, errText } from './portalText';

export function MissingSpecs({ inq, token, lang, call, onChange }) {
  const [held, setHeld] = useState(null);
  const [vals, setVals] = useState({});
  const [busy, setBusy] = useState(false); const [msg, setMsg] = useState(''); const [err, setErr] = useState('');
  const spin = useDelayedFlag(busy);
  const load = () => call('customer_api', { action: 'missing_specs', inquiry_id: inq.id, lang }, token)
    .then((j) => setHeld(j && j.ok && j.held ? j : null), () => setHeld(null));
  useEffect(() => { load(); }, [inq.id, lang]);
  if (!held || !Array.isArray(held.missing) || !held.missing.length) return msg ? <p className="text-[12.5px] text-primary" role="status">{msg}</p> : null;

  const save = async () => {
    const answers = Object.fromEntries(Object.entries(vals).filter(([, v]) => String(v || '').trim()));
    if (!Object.keys(answers).length || busy) return;
    setBusy(true); setErr(''); setMsg('');
    const j = await call('customer_api', { action: 'add_missing_specs', inquiry_id: inq.id, answers }, token).catch(() => null);
    setBusy(false);
    if (j && j.ok) {
      setVals({});
      setMsg(t(lang, j.released ? 'ms_released' : 'ms_saved') + (j.held_for_english ? ' ' + (lang === 'ar' ? j.notice : j.notice_en) : ''));
      await load();
      if (j.released && onChange) onChange();
    } else setErr(errText(j, lang));
  };

  return (
    <section className="qd-panel border-warn/40 p-4 sm:p-5" onClick={(e) => e.stopPropagation()} aria-label={t(lang, 'ms_title')} data-testid="missing-specs">
      <h3 className="font-head text-[15px] font-semibold tracking-snug text-foreground">{t(lang, 'ms_title')}</h3>
      <p className="mt-1 text-small leading-relaxed text-muted-foreground">{t(lang, 'ms_sub')}</p>
      <div className="mt-3 flex flex-col gap-2.5">
        {held.missing.map((m) => {
          const id = 'qd-ms-' + inq.id + '-' + m.key;
          const opts = Array.isArray(m.options) ? m.options : [];
          return (
            <div key={m.key}>
              <label htmlFor={id} className="block text-[13px] font-semibold text-foreground">{m.ask}</label>
              <input id={id} list={opts.length ? id + '-o' : undefined} value={vals[m.key] || ''} maxLength={300}
                inputMode={m.type === 'number' ? 'decimal' : undefined}
                onChange={(e) => setVals((a) => ({ ...a, [m.key]: e.target.value }))}
                className="mt-1 w-full rounded-lg border border-input bg-transparent px-3 py-2 text-[13px] text-foreground outline-none focus-visible:ring-1 focus-visible:ring-ring" />
              {opts.length ? <datalist id={id + '-o'}>{opts.map((o) => <option key={o} value={o} />)}</datalist> : null}
            </div>
          );
        })}
      </div>
      <div className="mt-3 flex flex-wrap items-center gap-3">
        <Button size="sm" aria-busy={spin || undefined} className="gap-2" disabled={busy || !Object.values(vals).some((v) => String(v || '').trim())} onClick={save}>
          {spin ? <><Spinner />{t(lang, 'saving')}</> : t(lang, 'ms_save')}
        </Button>
        {msg ? <span className="text-[12px] text-primary" role="status">{msg}</span> : null}
      </div>
      {err ? <div className="mt-2 text-[12.5px] text-danger" role="alert">{err}</div> : null}
    </section>
  );
}
