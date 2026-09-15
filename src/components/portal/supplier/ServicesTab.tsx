'use client';
// THE SERVICES TAB — the supplier's first screen and the matching's main source (founder, 15 Sep 2026:
// "this will be our cross matching main source"). It supersedes the Scope panel (CapabilityConfirmPanel,
// removed from SupplierPortal.tsx the same day): the same confirm, the same versioned ledger in
// supplier_capability_confirmation, but the supplier now ticks SERVICES inside each trade from a list
// the sales engineer prepared, instead of 40 bare trade names.
//
// API-FIRST. Every read and write is a supplier_api action (docs/api/supplier_portal_services.md):
// services_state, services_resolve, services_save, transcribe_service_note. This component holds no
// matching rule of its own — what is pre-ticked, how free text resolves to a trade, and whether voice
// is on all come from the server, so a mobile app gets the same answers.
//
// VOICE records here and is transcribed on the server (founder, 15 Sep 2026: "we cant use the browser
// built in"). While decision_policy supplier_voice_input_enabled is off, the mic is shown disabled with
// a note and typing works fully.
import { useEffect, useId, useRef, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { blobToWav } from '@/lib/wavEncode';
import { call } from './api';
import { srvMsg, vocabLabel } from './serverCopy';
import { sc, scCount } from './servicesCopy';

type Service = { key: string; label_en: string; label_ar: string };
type Trade = { code: string; label: string; label_ar?: string | null };
type Role = { code: string; label: string };
type ChecklistTrade = { code: string; source: 'confirmed' | 'on_file' | 'documents' };
type Proposal = { code: string; label_en?: string | null; label_ar?: string | null; status: string; mapped_to?: string | null };
type DocHit = { code: string; snippet?: string };
type Doc = { path: string; name: string; status?: string; trades?: DocHit[] };
type Voice = { enabled: boolean; max_seconds: number; max_bytes: number };
type State = {
  ok: boolean; confirmed: boolean; first_run: boolean;
  checklist: ChecklistTrade[]; services_by_trade: Record<string, Service[]>;
  selected_services: string[]; extra_services: string[];
  vocabulary: { trades: Trade[]; roles: Role[] };
  capability: { roles?: string[]; source_docs?: { docs?: Doc[] } } | null;
  trade_proposals: Proposal[]; voice: Voice;
};
type Extra = { text: string; trades: string[] | null };

const box = 'mt-0.5 h-5 w-5 shrink-0 rounded border-input accent-[hsl(var(--primary))] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring';
const row = 'flex min-h-11 cursor-pointer items-start gap-2.5 rounded-md px-2 py-2.5 text-[13.5px] leading-snug text-foreground hover:bg-muted/40';
const h3 = 'text-[14.5px] font-bold tracking-[-.012em] text-foreground';
const sub = 'text-[13px] leading-[1.65] text-muted-foreground max-w-[68ch]';

export default function ServicesTab({ token, lang, goTo }: { token: string; lang: string; goTo?: (k: string) => void }) {
  const ar = lang === 'ar';
  const uid = useId();
  const [st, setSt] = useState<{ loading: boolean; err: string; data: State | null }>({ loading: true, err: '', data: null });
  const [trades, setTrades] = useState<string[]>([]);
  const [ticked, setTicked] = useState<Set<string>>(new Set());
  const [extras, setExtras] = useState<Extra[]>([]);
  const [roles, setRoles] = useState<string[]>([]);
  const [extraInput, setExtraInput] = useState('');
  const [addPick, setAddPick] = useState('');
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<{ kind: 'ok' | 'err'; text: string; review?: boolean } | null>(null);

  const load = async () => {
    setSt((s) => ({ ...s, loading: true, err: '' }));
    const j = await call('supplier_api', { action: 'services_state' }, token).catch(() => null);
    if (j && j.ok) {
      const d = j as State;
      setTrades(d.checklist.map((c) => c.code));
      setTicked(new Set(d.selected_services));
      setExtras(d.extra_services.map((text) => ({ text, trades: null })));
      setRoles((d.capability && d.capability.roles) || []);
      setSt({ loading: false, err: '', data: d });
    } else {
      setSt((s) => ({ ...s, loading: false, err: srvMsg(lang, j, sc(lang, 'load_failed')) }));
    }
  };
  useEffect(() => { load(); }, [token]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── voice ──────────────────────────────────────────────────────────────────────────────────────
  const rec = useRef<{ mr: MediaRecorder; chunks: Blob[]; stream: MediaStream; timer: number } | null>(null);
  const [recording, setRecording] = useState(false);
  const [voxBusy, setVoxBusy] = useState(false);
  const [voxMsg, setVoxMsg] = useState('');
  const canRecord = typeof window !== 'undefined' && !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia) && typeof window.MediaRecorder !== 'undefined';
  const stopTracks = () => { try { rec.current?.stream.getTracks().forEach((t) => t.stop()); } catch (_e) { /* already stopped */ } };
  useEffect(() => () => { if (rec.current) { window.clearTimeout(rec.current.timer); try { rec.current.mr.stop(); } catch (_e) { /* idle */ } stopTracks(); } }, []);
  const stopRec = () => { const r = rec.current; if (!r) return; window.clearTimeout(r.timer); try { r.mr.stop(); } catch (_e) { /* idle */ } setRecording(false); };
  const startRec = async (voice: Voice) => {
    setVoxMsg('');
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mr = new MediaRecorder(stream);
      const r = { mr, chunks: [] as Blob[], stream, timer: 0 };
      rec.current = r;
      mr.ondataavailable = (e) => { if (e.data && e.data.size) r.chunks.push(e.data); };
      mr.onstop = async () => {
        stopTracks(); setVoxBusy(true);
        try {
          const blob = new Blob(r.chunks, { type: (r.chunks[0] && r.chunks[0].type) || 'audio/webm' });
          const wav = await blobToWav(blob);
          if (wav.bytes > voice.max_bytes) { setVoxMsg(sc(lang, 'mic_failed')); return; }
          const j = await call('supplier_api', { action: 'transcribe_service_note', audio_b64: wav.b64, mime: 'audio/wav', duration_ms: wav.durationMs }, token);
          if (j && j.ok) { if (j.text) setExtraInput((x) => (x ? x + ' ' : '') + String(j.text).trim()); }
          else setVoxMsg(sc(lang, j && j.code === 'voice_rate_limited' ? 'mic_limited' : j && j.code === 'voice_input_off' ? 'mic_soon' : 'mic_failed'));
        } catch (_e) { setVoxMsg(sc(lang, 'mic_failed')); }
        finally { setVoxBusy(false); rec.current = null; }
      };
      mr.start();
      r.timer = window.setTimeout(() => stopRec(), voice.max_seconds * 1000);
      setRecording(true);
    } catch (_e) { setVoxMsg(sc(lang, 'mic_denied')); stopTracks(); rec.current = null; }
  };

  if (st.loading && !st.data) return <Card className="qd-panel p-5" aria-busy="true">{sc(lang, 'loading')}</Card>;
  if (!st.data) return (
    <Card className="qd-panel p-5">
      <h2 className={h3}>{sc(lang, 'load_failed')}</h2>
      {st.err ? <p className={sub}>{st.err}</p> : null}
      <Button className="mt-3" onClick={load}>{sc(lang, 'retry')}</Button>
    </Card>
  );
  const d = st.data;
  const vocab = d.vocabulary.trades;
  const tradeName = (code: string) => {
    const t = vocab.find((x) => x.code === code);
    return vocabLabel(lang, 'trade', code, t ? (ar ? t.label_ar || t.label : t.label) : code.replace(/_/g, ' '));
  };
  const svcName = (s: Service) => (ar ? s.label_ar : s.label_en);
  const sourceOf = (code: string) => d.checklist.find((c) => c.code === code)?.source;
  const keysOf = (code: string) => (d.services_by_trade[code] || []).map((s) => s.key);
  const liveTicks = [...ticked].filter((k) => trades.includes(k.split('.')[0]));
  const docs = (d.capability?.source_docs?.docs || []).filter((x) => (x.trades || []).length);
  const noPrep = !d.confirmed && d.checklist.length === 0;

  const toggleKey = (k: string) => setTicked((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });
  const setAll = (code: string, on: boolean) => setTicked((s) => { const n = new Set(s); for (const k of keysOf(code)) { if (on) n.add(k); else n.delete(k); } return n; });
  const removeTrade = (code: string) => { setTrades((ts) => ts.filter((c) => c !== code)); setAll(code, false); };
  const addTrade = () => { if (addPick && !trades.includes(addPick)) setTrades((ts) => [...ts, addPick]); setAddPick(''); };
  const toggleRole = (c: string) => setRoles((rs) => (rs.includes(c) ? rs.filter((x) => x !== c) : [...rs, c]));

  const addExtra = async () => {
    const text = extraInput.replace(/\s+/g, ' ').trim().slice(0, 120);
    if (text.length < 2 || extras.some((e) => e.text.toLowerCase() === text.toLowerCase())) { setExtraInput(''); return; }
    setExtraInput('');
    setExtras((xs) => [...xs, { text, trades: null }]);
    const j = await call('supplier_api', { action: 'services_resolve', text }, token).catch(() => null);
    if (j && j.ok) setExtras((xs) => xs.map((e) => (e.text === text ? { text, trades: j.trades || [] } : e)));
  };

  const save = async () => {
    setBusy(true); setNote(null);
    const j = await call('supplier_api', {
      action: 'services_save', trades, roles, services: liveTicks, extra_services: extras.map((e) => e.text),
    }, token).catch(() => null);
    setBusy(false);
    if (j && j.ok) {
      const review = (j.proposed_trades || []).length > 0 || (j.new_trades_under_review || []).length > 0;
      setNote({ kind: 'ok', text: sc(lang, 'saved'), review });
      load();
    } else setNote({ kind: 'err', text: srvMsg(lang, j, sc(lang, 'save_failed')) });
  };

  const svcCount = liveTicks.length + extras.length;
  const canSave = roles.length > 0 && (trades.length > 0 || extras.length > 0);
  const voice = d.voice;
  const micNoteId = uid + '-mic';
  const micNote = !voice.enabled ? sc(lang, 'mic_soon') : !canRecord ? sc(lang, 'mic_unsupported') : voxBusy ? sc(lang, 'mic_busy') : voxMsg;
  const addable = vocab.filter((t) => !trades.includes(t.code))
    .sort((a, b) => tradeName(a.code).localeCompare(tradeName(b.code), lang));

  return (
    <Card className="qd-panel p-5">
      <h2 className="font-head text-[19px] font-semibold tracking-snug text-foreground">{sc(lang, 'title')}</h2>
      <p className={cn(sub, 'mt-1')}>{d.confirmed ? sc(lang, 'confirmed') : sc(lang, 'first_run')}</p>

      {noPrep && (
        <div className="mt-4 rounded-md border border-dashed border-border bg-muted/30 p-4">
          <p className={sub}>{sc(lang, 'no_prep')}</p>
          {goTo ? <Button variant="outline" className="mt-3 min-h-11" onClick={() => goTo('documents')}>{sc(lang, 'go_documents')}</Button> : null}
        </div>
      )}

      {docs.length > 0 && (
        <section className="mt-4" aria-labelledby={uid + '-docs'}>
          <h3 id={uid + '-docs'} className={cn(sub, 'font-semibold')}>{sc(lang, 'found_in')}</h3>
          <ul className="mt-1.5 space-y-1.5">
            {docs.map((doc) => (
              <li key={doc.path} className="text-[12.5px] text-muted-foreground">
                <span className="font-medium text-foreground break-all" dir="auto">{doc.name}</span>
                {' — '}{(doc.trades || []).map((h) => tradeName(h.code)).join(ar ? '، ' : ', ')}
                {doc.trades && doc.trades[0] && doc.trades[0].snippet ? <q className="ms-1.5 opacity-80" dir="auto">{doc.trades[0].snippet}</q> : null}
              </li>
            ))}
          </ul>
        </section>
      )}

      <div className="mt-4 flex flex-col gap-3">
        {trades.map((code) => {
          const svcs = d.services_by_trade[code] || [];
          const src = sourceOf(code);
          const allOn = svcs.length > 0 && svcs.every((s) => ticked.has(s.key));
          return (
            <fieldset key={code} className="rounded-md border border-border p-3">
              <legend className="px-1">
                <span className={h3}>{tradeName(code)}</span>
                {src === 'documents' ? <Badge variant="secondary" className="ms-2">{sc(lang, 'from_docs')}</Badge>
                  : src === 'on_file' ? <Badge variant="secondary" className="ms-2">{sc(lang, 'on_file')}</Badge>
                  : src === 'confirmed' ? <Badge variant="ok" className="ms-2">{sc(lang, 'confirmed_badge')}</Badge> : null}
              </legend>
              {svcs.length ? (
                <div className="grid grid-cols-1 gap-x-3 sm:grid-cols-2">
                  {svcs.map((s) => (
                    <label key={s.key} className={row} htmlFor={uid + s.key}>
                      <input id={uid + s.key} type="checkbox" className={box} checked={ticked.has(s.key)} onChange={() => toggleKey(s.key)} />
                      <span>{svcName(s)}</span>
                    </label>
                  ))}
                </div>
              ) : <p className={cn(sub, 'px-2 py-1')}>{sc(lang, 'no_services_listed')}</p>}
              <div className="mt-1 flex flex-wrap gap-x-4">
                {svcs.length > 0 && (
                  <Button type="button" variant="link" className="min-h-11 px-2" onClick={() => setAll(code, !allOn)}>
                    {allOn ? sc(lang, 'clear_all') : sc(lang, 'select_all')}
                  </Button>
                )}
                <Button type="button" variant="link" className="min-h-11 px-2 text-muted-foreground" onClick={() => removeTrade(code)}>
                  {sc(lang, 'remove_trade')}<span className="sr-only">: {tradeName(code)}</span>
                </Button>
              </div>
            </fieldset>
          );
        })}
      </div>

      <div className="mt-4 flex flex-wrap items-end gap-2">
        <label className="flex min-w-[220px] flex-1 flex-col gap-1 text-[13px] font-semibold text-muted-foreground" htmlFor={uid + '-add'}>
          {sc(lang, 'add_trade')}
          <select id={uid + '-add'} className="h-11 w-full rounded-md border border-input bg-card px-3 text-sm font-normal text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                  value={addPick} onChange={(e) => setAddPick(e.target.value)}>
            <option value="">{sc(lang, 'add_trade_ph')}</option>
            {addable.map((t) => <option key={t.code} value={t.code}>{tradeName(t.code)}</option>)}
          </select>
        </label>
        <Button type="button" variant="outline" className="min-h-11" disabled={!addPick} onClick={addTrade}>{sc(lang, 'add')}</Button>
      </div>

      <section className="mt-5" aria-labelledby={uid + '-extra'}>
        <h3 id={uid + '-extra'} className={h3}>{sc(lang, 'extras_title')}</h3>
        <p className={cn(sub, 'mt-0.5')} id={uid + '-extra-help'}>{sc(lang, 'extras_help')}</p>
        <form className="mt-2 flex flex-wrap items-center gap-2" onSubmit={(e) => { e.preventDefault(); addExtra(); }}>
          <label className="sr-only" htmlFor={uid + '-extra-in'}>{sc(lang, 'extras_label')}</label>
          <input id={uid + '-extra-in'} dir="auto" maxLength={120} value={extraInput} onChange={(e) => setExtraInput(e.target.value)}
                 aria-describedby={uid + '-extra-help'} placeholder={sc(lang, 'extras_ph')}
                 className="h-11 min-w-[200px] flex-1 rounded-md border border-input bg-transparent px-3 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" />
          <Button type="button" variant="outline" className="min-h-11 min-w-11"
                  disabled={!voice.enabled || !canRecord || voxBusy}
                  aria-pressed={recording}
                  aria-describedby={micNote ? micNoteId : undefined}
                  onClick={() => (recording ? stopRec() : startRec(voice))}>
            <span aria-hidden>{recording ? '■' : '🎙'}</span>
            <span className="ms-1.5">{recording ? sc(lang, 'mic_stop') : sc(lang, 'mic_start')}</span>
          </Button>
          <Button type="submit" className="min-h-11" disabled={extraInput.trim().length < 2}>{sc(lang, 'add')}</Button>
        </form>
        <p id={micNoteId} role="status" className={cn('mt-1.5 text-[12.5px] text-muted-foreground', !micNote && 'sr-only')}>{micNote}</p>
        {extras.length > 0 && (
          <ul className="mt-2 flex flex-col gap-1.5">
            {extras.map((e) => (
              <li key={e.text} className="flex flex-wrap items-center gap-2 rounded-md border border-border px-3 py-1.5 text-[13px]">
                <span className="font-medium text-foreground" dir="auto">{e.text}</span>
                {e.trades && (e.trades.length
                  ? <span className="text-muted-foreground">{sc(lang, 'resolves_to')}: {e.trades.map(tradeName).join(ar ? '، ' : ', ')}</span>
                  : <span className="text-muted-foreground">{sc(lang, 'new_for_review')}</span>)}
                <Button type="button" variant="link" className="ms-auto min-h-11 px-2" onClick={() => setExtras((xs) => xs.filter((x) => x.text !== e.text))}>
                  {sc(lang, 'remove')}<span className="sr-only">: {e.text}</span>
                </Button>
              </li>
            ))}
          </ul>
        )}
      </section>

      <fieldset className="mt-5">
        <legend className={h3}>{sc(lang, 'roles_title')}</legend>
        <div className="mt-1.5 grid grid-cols-1 gap-x-3 sm:grid-cols-2">
          {d.vocabulary.roles.map((r) => (
            <label key={r.code} className={row} htmlFor={uid + '-role-' + r.code}>
              <input id={uid + '-role-' + r.code} type="checkbox" className={box} checked={roles.includes(r.code)} onChange={() => toggleRole(r.code)} />
              <span>{vocabLabel(lang, 'role', r.code, r.label)}</span>
            </label>
          ))}
        </div>
      </fieldset>

      {d.trade_proposals.length > 0 && (
        <section className="mt-4" aria-labelledby={uid + '-prop'}>
          <h3 id={uid + '-prop'} className={cn(sub, 'font-semibold')}>{sc(lang, 'proposals_title')}</h3>
          <ul className="mt-1 space-y-1 text-[12.5px] text-muted-foreground">
            {d.trade_proposals.map((p) => (
              <li key={p.code}>
                <span className="font-medium text-foreground" dir="auto">{(ar ? p.label_ar || p.label_en : p.label_en || p.label_ar) || p.code.replace(/_/g, ' ')}</span>{' — '}
                {p.status === 'pending' && sc(lang, 'p_pending')}
                {p.status === 'added' && sc(lang, 'p_added')}
                {p.status === 'rejected' && sc(lang, 'p_rejected')}
                {p.status === 'mapped' && sc(lang, 'p_mapped')}
                {p.status === 'map_offered' && p.mapped_to && (
                  <>{sc(lang, 'p_offer')} <b>{tradeName(p.mapped_to)}</b>
                    <Button type="button" variant="outline" className="ms-2 min-h-11 px-3 text-xs"
                            onClick={() => { const to = p.mapped_to as string; setTrades((ts) => [...ts.filter((c) => c !== p.code), ...(ts.includes(to) ? [] : [to])]); }}>
                      {sc(lang, 'p_use')}
                    </Button></>
                )}
              </li>
            ))}
          </ul>
        </section>
      )}

      {(!roles.length || (!trades.length && !extras.length)) && <p className="mt-4 text-[13px] text-warn-fg">{sc(lang, 'need_trade_role')}</p>}
      <div role="status" aria-live="polite">
        {note && note.kind === 'ok' ? <p className="mt-3 text-[13px] font-semibold text-primary">{note.text}{note.review ? ' ' + sc(lang, 'review_sent') : ''}</p> : null}
      </div>
      {note && note.kind === 'err' ? <p role="alert" className="mt-3 text-[13px] text-danger-fg">{note.text}</p> : null}

      {/* Sticky until the first confirm: the one action that opens every inquiry travels with the thumb.
          pe-16 on phones keeps it clear of the docked assistant bubble (measured 29px overlap, 14 Sep). */}
      <div className={cn('mt-4', !d.confirmed && 'sticky bottom-0 -mx-5 -mb-5 border-t border-border bg-card/85 px-5 pb-5 pe-16 pt-3 backdrop-blur-md sm:pe-5')}>
        <p className={cn(sub, 'mb-2')}>{scCount(lang, svcCount, roles.length)}</p>
        <Button className="min-h-11 w-full sm:w-auto" disabled={busy || !canSave} onClick={save}>
          {busy ? sc(lang, 'saving') : d.confirmed ? sc(lang, 'update') : sc(lang, 'confirm')}
        </Button>
      </div>
    </Card>
  );
}
