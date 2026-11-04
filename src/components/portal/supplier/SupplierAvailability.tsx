'use client';
// AVAILABILITY (29 Sep 2026, sales_engineer, founder ledger 1033). A supplier says whether new requests should
// reach it: available, busy until a date, or paused. Matching (public.fn_match_capability) skips a busy or paused
// supplier; a busy date expires on its own day, with nothing for the supplier to do. English only: everything the
// platform writes to a supplier is English (founder, 28 Sep 2026).
//
// The state shown is the one matching reads (supplier_api settings -> fn_supplier_availability_of), and the only
// writer is supplier_api set_availability -> fn_supplier_set_availability, which refuses a busy date that is not
// after today. The date input is the browser's own; the server is what decides.
import React, { useState } from 'react';
import { call } from './api';

export type Availability = { state: 'available' | 'busy' | 'paused'; busy_until: string | null; set_at?: string | null };
type State = Availability['state'];

const COPY = {
  title: 'Availability',
  lead: 'Tell us whether new customer requests should reach you. Requests you have already received stay open.',
  available: 'Available', availableHelp: 'New requests in your trades reach you.',
  busy: 'Busy until a date', busyHelp: 'No new requests until the date you choose. From that date you are available again automatically.',
  paused: 'Paused', pausedHelp: 'No new requests until you set yourself available again.',
  until: 'Available again on',
  save: 'Save availability', saving: 'Saving…', saved: 'Saved.',
  err: 'We could not save your availability. Please try again.',
  now: 'Now:', nowAvailable: 'available', nowBusy: (d: string) => `busy, available again on ${d}`, nowPaused: 'paused',
};

const REFUSALS = new Set(['busy_date_not_future', 'busy_date_too_far', 'bad_state']);

// The server decides "today" in Dubai; this only sets the picker's floor so a past date is not offered.
const tomorrow = () => { const d = new Date(Date.now() + 4 * 3600e3 + 864e5); return d.toISOString().slice(0, 10); };
const fmt = (d: string) => new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });

export default function SupplierAvailability({ token, initial }: { token?: string | null; initial: Availability | null }) {
  const [cur, setCur] = useState<Availability>(initial ?? { state: 'available', busy_until: null });
  const [state, setState] = useState<State>(cur.state);
  const [until, setUntil] = useState<string>(cur.busy_until ?? '');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');
  const [err, setErr] = useState('');

  const save = async () => {
    setBusy(true); setMsg(''); setErr('');
    const j = await call('supplier_api', { action: 'set_availability', state, busy_until: state === 'busy' ? until : null }, token);
    setBusy(false);
    // The writer's own refusals are plain English sentences meant for the supplier; anything else is generic.
    if (!(j && j.ok && j.availability)) { setErr(REFUSALS.has(j?.code) && j?.error ? j.error : COPY.err); return; }
    setCur(j.availability); setMsg(COPY.saved);
  };

  const now = cur.state === 'busy' && cur.busy_until ? COPY.nowBusy(fmt(cur.busy_until)) : cur.state === 'paused' ? COPY.nowPaused : COPY.nowAvailable;
  const options: [State, string, string][] = [['available', COPY.available, COPY.availableHelp], ['busy', COPY.busy, COPY.busyHelp], ['paused', COPY.paused, COPY.pausedHelp]];

  return (
    <section className="qd-panel p-5" dir="ltr" lang="en" aria-labelledby="qd-avail-title">
      <h3 id="qd-avail-title" className="text-xs uppercase tracking-wide text-muted-foreground mb-1">{COPY.title}</h3>
      <p className="text-[12px] text-muted-foreground mb-2">{COPY.lead}</p>
      <p role="status" className="text-[12.5px] text-foreground mb-3">{COPY.now} <strong>{now}</strong></p>
      <fieldset className="space-y-1">
        <legend className="sr-only">{COPY.title}</legend>
        {options.map(([v, label, help]) => (
          <label key={v} className="flex items-start gap-3 cursor-pointer py-1.5">
            <input type="radio" name="qd-avail" value={v} checked={state === v} onChange={() => setState(v)} className="mt-0.5 h-4 w-4 shrink-0 accent-primary" />
            <span className="min-w-0">
              <span className="block text-[13px] text-foreground">{label}</span>
              <span className="block text-[11.5px] text-muted-foreground leading-snug mt-0.5">{help}</span>
            </span>
          </label>
        ))}
      </fieldset>
      {state === 'busy' && (
        <div className="mt-2">
          <label className="block text-[13px] mb-1.5 text-foreground" htmlFor="qd-avail-until">{COPY.until}</label>
          <input id="qd-avail-until" type="date" required min={tomorrow()} value={until} onChange={(e) => setUntil(e.target.value)}
            className="w-full rounded-md border border-input bg-card text-foreground px-3 py-2 text-sm outline-hidden focus-visible:ring-1 focus-visible:ring-ring" />
        </div>
      )}
      <button type="button" onClick={save} disabled={busy || (state === 'busy' && !until)}
        className="w-full min-h-11 mt-3 rounded-md bg-primary px-4 py-2.5 text-sm font-semibold text-primary-foreground hover:bg-primary/90 disabled:opacity-50">
        {busy ? COPY.saving : COPY.save}
      </button>
      {msg && <p role="status" className="text-[12px] text-ok-fg mt-2">{msg}</p>}
      {err && <p role="alert" className="text-[12px] text-warn-fg mt-2">{err}</p>}
    </section>
  );
}
