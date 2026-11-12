'use client';
// THE SERVICES TAB — the supplier's first screen and the matching's main source (founder, 15 Sep 2026:
// "this will be our cross matching main source"). It supersedes the Scope panel (CapabilityConfirmPanel,
// removed from SupplierPortal.tsx the same day): the same confirm, the same versioned ledger in
// supplier_capability_confirmation.
//
// THREE SCREENS (12 Nov 2026, slice 4; founder rulings 1647, 1628 and 1645; report docs/reports/2026-11-12-supplier-service-profiling.md 3.9):
//   1. "Here is what we understood your company does": the reading's two-sentence summary and the services his documents state,
//      each with his own sentence, unticked, with one tap "Yes, we do all of these";
//   2. "A few quick questions" (ServiceQuestions.tsx): at most five cards, one at a time, where his documents were vague, broad,
//      or name a partner; every tap answers at once and is written behind it (supplier_api services_answer, no model);
//   3. "Check and confirm": with your own team, through a partner, in your own words, where you work, your role, and Confirm.
//      Below it, closed unless nothing is listed: "Add a service we missed" (the free-text box) and "Browse all services of my
//      trades" (the checklist, never a whole trade in one tap).
// The founder's standard (1645): a general manager on a phone finishes in about two minutes. One short sentence per screen, every
// control 44 px with a pressed state, inputs at 16 px, a loading state on every submit, and a reload or Back resumes where he was.
//
// ADDING A SERVICE IS TYPING OR SPEAKING, NOT PICKING (founder, instruction 438). Voice records here and is transcribed on the
// server; the microphone is shown only while decision_policy supplier_voice_input_enabled is on and the device can record (12 Nov
// 2026: a disabled button and "coming soon" looked unfinished, so the feature is hidden until it works).
//
// API-FIRST. Every read and write is a supplier_api action (docs/api/supplier_portal_services.md): services_state,
// services_answer, services_rewrite, services_save_rewrite, transcribe_service_note. This component holds no matching rule.
import { useEffect, useId, useRef, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Spinner } from '@/components/ui/busy';
import { Skeleton } from '@/components/ui/skeleton';
import { ChevronDown, Loader2, X } from 'lucide-react';
import { cn } from '@/lib/utils';
import { blobToWav } from '@/lib/wavEncode';
import { call, REASONING_TIMEOUT_MS } from './api';
import { panelErrorText } from './PanelState';
import { srvMsg, vocabLabel, emirateLabel } from './serverCopy';
import { asksWhatHeDoes, countServices, FLOW_COPY as F, listedProfileState, profileStateOf, PROPOSED_COPY, sc, scCount, stateLine, VERIFY_COPY } from './servicesCopy';
import { reloadRoles, reloadSet, reloadText } from './servicesRead';
import { profileReading, sameProgress, startReadingPoll, stepALanded } from './servicesPoll';
import EmirateCheckboxes from './EmirateCheckboxes';
import ServiceQuestions, { chipCls } from './ServiceQuestions';
import { cardsOf, goTo as cardGoTo, liveQuestions, openCards, outcome, readFlow, readKept, selection, settled, unsavedIds, writeFlow, writeKept, type Answer, type Cards, type Question } from './serviceQuestions';

type Service = { key: string; label_en: string; label_ar: string };
type Trade = { code: string; label: string; label_ar?: string | null };
type Role = { code: string; label: string };
type ChecklistTrade = { code: string; source: 'confirmed' | 'on_file' | 'signup' | 'documents' | 'refine' };
type Proposal = { code: string; label_en?: string | null; label_ar?: string | null; status: string; mapped_to?: string | null };
type DocHit = { code: string; snippet?: string };
type Doc = { path: string; name: string; kind?: string; status?: string; source?: string; choice?: string; reason?: string; vision_held?: DocHit[]; trades?: DocHit[] };
type Voice = { enabled: boolean; max_seconds: number; max_bytes: number };
// Read off the supplier's own documents (supplier_services.servicesState, ledger 1573): offered, never pre-ticked (founder 862).
type ProposedSvc = { key: string; trade: string; label_en: string; label_ar: string; phrase: string; snippet: string; via: string; licence: 'supported' | 'not_covered' | 'unclear'; doc: string; stated: boolean;
  delivery?: 'own' | 'partner'; partner_name?: string | null; basis?: 'stated' | 'shown' | 'brand' | 'partner'; check?: boolean };
type ReadingProgress = { stage?: string; summary?: string; claims?: { words: string; basis: string }[] } | null;
// Reader @5 (supplier_profile_reading.ts): the summary, the phrases kept in his own words, the roles read off his documents.
type ReadOwnWords = { words: string; quote: string; basis: string };
type Reading = { read_at?: string | null; summary?: string; own_words?: ReadOwnWords[]; roles?: string[]; questions?: { kind: string; status: string }[] } | null;
type State = {
  ok: boolean; confirmed: boolean; first_run: boolean;
  checklist: ChecklistTrade[]; services_by_trade: Record<string, Service[]>;
  selected_services: string[]; extra_services: string[];
  raw_text: string; implied_services: string[]; removed_services: string[]; rewritten_at: string | null;
  vocabulary: { trades: Trade[]; roles: Role[] };
  capability: { roles?: string[]; coverage_emirates?: string[]; confirmed_at?: string | null; source_docs?: { docs?: Doc[] } } | null;
  trade_proposals: Proposal[]; voice: Voice;
  proposed_services?: ProposedSvc[]; reading?: Reading; reading_progress?: ReadingProgress;
  questions?: Question[]; services_partner?: string[]; declared_emirates?: string[];
};
// What the sales engineer made of the supplier's words. `items` carries the per-phrase reading; the
// three lists below are what the supplier actually edits.
type Because = { from: string; from_label_en: string; from_label_ar: string; en: string; ar: string };
type Implied = { key: string; label_en: string; label_ar: string; trade: string; removed: boolean; because: Because[] };
type RewriteItem =
  | { kind: 'service'; key: string; trade: string; label_en: string; label_ar: string; from: string }
  | { kind: 'trade'; trades: string[]; text: string; from: string }
  | { kind: 'unmatched'; text: string; from: string };
type MeaningProposal = { key: string; label_en: string; label_ar: string; similarity: number; because: string; word: string | null; lines: string[] };
type Rewrite = {
  raw_text: string; service_keys: string[]; own_words: string[]; items: RewriteItem[];
  summary_en: string; summary_ar: string; implied: Implied[]; pending_taxonomy: string[];
  supply_only?: { proposed: boolean; applied: boolean };
  meaning?: { state: string; proposals: MeaningProposal[] };
  source?: { kind: 'typed'; name?: string };
  model?: { state: string; message_en?: string; message_ar?: string };
};
type Step = 'understood' | 'questions' | 'check';

const box = 'mt-0.5 h-5 w-5 shrink-0 rounded border-input accent-[hsl(var(--primary))] focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring';
const row = 'flex min-h-11 cursor-pointer items-start gap-3 rounded-md px-2 py-2.5 text-[15px] leading-snug text-foreground transition-colors hover:bg-muted/40 active:bg-muted/60';
const h2 = 'font-head text-[19px] font-semibold tracking-snug text-foreground';
const h3 = 'text-[15px] font-bold tracking-[-.012em] text-foreground';
const sub = 'text-[14px] leading-[1.6] text-muted-foreground max-w-[68ch]';
const chip = 'flex flex-wrap items-center gap-2 rounded-md border border-border px-3 py-1.5 text-[14px]';
const summaryCls = cn(h3, 'flex min-h-12 cursor-pointer list-none items-center justify-between gap-3 px-3 py-2 hover:bg-muted/40 active:bg-muted/60 [&::-webkit-details-marker]:hidden');
// where this browser last was in the flow, and screen 1's ticks, for one reading (serviceQuestions.readFlow / writeFlow)
const readStep = (readAt: string): Step | null => { const f = readFlow(readAt); return f && (f.step === 'understood' || f.step === 'questions' || f.step === 'check') ? f.step : null; };

// WHAT THE TAB KNOWS, TOLD TO THE WORKSPACE (12 Nov 2026, customer_support; founder ruling 1645, paid certification J9/J10): the
// "Registration received" card above said "Nothing is needed from you" while three services waited here to be ticked, because the
// dashboard's own read predates the reading. `onStatus` says whether he has confirmed, whether his documents are still being
// read, and whether services or questions wait for him; `confirmedAt` counts the Confirms, so the workspace reads its status
// again (Dashboard.tsx).
export type ServicesStatus = { confirmed: boolean; reading: boolean; waiting: boolean; confirmedAt: number };
export default function ServicesTab({ token, lang, goTo, onStatus }: { token: string; lang: string; goTo?: (k: string) => void; onStatus?: (s: ServicesStatus) => void }) {
  const ar = lang === 'ar';
  const uid = useId();
  const [st, setSt] = useState<{ loading: boolean; err: string; data: State | null }>({ loading: true, err: '', data: null });
  const [trades, setTrades] = useState<string[]>([]);
  // A trade the supplier removed, held until Update so it can be undone (audit 21 Sep 2026, finding
  // 10: the card vanished instantly and came back after Update + reload). The save sends it as
  // removed_trades and the server drops it from the confirmed trades.
  const [removedTrades, setRemovedTrades] = useState<Set<string>>(new Set());
  const [ticked, setTicked] = useState<Set<string>>(new Set());
  // The services the documents proposed that the supplier ticked on screen 1 (they may sit outside the prepared trades).
  const [propTicked, setPropTicked] = useState<Set<string>>(new Set());
  // the reading's own-words phrases he ticked: sent with his own words on Confirm (nothing is kept for him unticked)
  const [readWordsTicked, setReadWordsTicked] = useState<Set<string>>(new Set());
  // "Browse all services of my trades" and "Add a service we missed": null until he opens or closes them
  const [browseOpen, setBrowseOpen] = useState<boolean | null>(null);
  const browseRef = useRef<HTMLDetailsElement | null>(null);
  const [addOpen, setAddOpen] = useState<boolean | null>(null);
  const [roles, setRoles] = useState<string[]>([]);
  const [roleEdit, setRoleEdit] = useState(false);
  const [coverage, setCoverage] = useState<string[]>([]);
  const [whereEdit, setWhereEdit] = useState(false);
  const [rawText, setRawText] = useState('');
  const [rw, setRw] = useState<Rewrite | null>(null);
  // Which lines the supplier struck out. Service and implication keys go in as they are; a phrase we
  // could not name goes in under a `word:` prefix, because it is free text and nothing stops a
  // supplier typing something shaped like a service key (React review, 18 Sep 2026).
  const [dropped, setDropped] = useState<Set<string>>(new Set());
  // WHAT THE MEANING LAYER PROPOSED AND THE SUPPLIER THEN ADDED (22 Sep 2026, finding SP-F-06): off until he says yes.
  const [kept, setKept] = useState<Set<string>>(new Set());
  const wordKey = (text: string) => 'word:' + text;
  const [rwBusy, setRwBusy] = useState(false);
  const [rwMsg, setRwMsg] = useState('');
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<{ kind: 'ok' | 'err'; text: string; review?: boolean } | null>(null);
  // THE FLOW: which screen, and the question cards' answers (lifted here: the check screen and the confirm read them)
  const [step, setStepRaw] = useState<Step>('check');
  const [cards, setCards] = useState<Cards>({ ids: [], index: 0, answers: {}, saving: {} });
  const [retrying, setRetrying] = useState(false);
  // the on-screen keyboard is up: the Confirm bar stops being sticky so it never sits over the field he is typing in
  const [typing, setTyping] = useState(false);
  const readAt = useRef('');
  const top = useRef<HTMLDivElement>(null);

  // Nothing async writes state after the tab is gone (review, 15 Sep 2026): a recording stopped by
  // unmount fires onstop later, and a slow services_state can land after a tab switch.
  const mounted = useRef(true);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);

  // BACK GOES BACK A SCREEN (1645: "a reload, the Back button or coming back tomorrow resumes exactly where he was"): each screen
  // he moves to is a history entry, so the phone's Back button returns to the screen before instead of leaving the portal.
  // BACK OR EDIT FROM THE CHECK SCREEN REOPENS THE LAST CARD when every card is answered (round-2 review of slice 4, finding A: Back stayed
  // on the check screen, so a chip picked by mistake on the last card could not be changed there)
  const toLastCard = () => setCards((c) => (c.ids.length && c.index >= c.ids.length ? { ...c, index: c.ids.length - 1 } : c));
  const setStep = (s: Step, o: { push?: boolean } = {}) => {
    if (s === 'questions') toLastCard();
    setStepRaw(s);
    try { if (o.push !== false) window.history.pushState({ ...window.history.state, qdSvc: s }, ''); } catch { /* history blocked */ }
    top.current?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  };
  // SCREEN 1's TICKS AND THE STEP, KEPT FOR THIS READING (review of slice 4, finding 2: an iPhone back from WhatsApp reloads the page)
  useEffect(() => {
    if (readAt.current && st.data) writeFlow({ at: readAt.current, step, ticked: [...propTicked], words: [...readWordsTicked], dropped: [...dropped] });
  }, [step, propTicked, readWordsTicked, dropped, st.data]);
  useEffect(() => {
    const onPop = (e: PopStateEvent) => { const s = e.state?.qdSvc; if (s === 'questions') toLastCard(); if (s === 'understood' || s === 'questions' || s === 'check') setStepRaw(s); };
    window.addEventListener('popstate', onPop);
    return () => window.removeEventListener('popstate', onPop);
  }, []);

  // ONE services_state ANSWER ON SCREEN. `load` asks for it; the reading poll below hands over the answer it already has.
  const show = (d: State, o: { keepText?: boolean } = {}) => {
    setTrades(d.checklist.map((c) => c.code));
    // keepText = a refresh because the profile finished reading: everything the supplier did meanwhile stays (review of #1796).
    const keep = !!o.keepText;
    setRemovedTrades((cur) => reloadSet(cur, [], keep));
    setTicked((cur) => reloadSet(cur, d.selected_services, keep));
    // what he ticked on screen 1 before a reload comes back for the same reading (finding 2), with what he confirmed before
    // ...before his first confirm only: after it, his confirmed list is the record (round-2 review: a ticked row came back after Update)
    const flow = d.reading?.read_at && !d.confirmed ? readFlow(String(d.reading.read_at)) : null;
    setPropTicked((cur) => reloadSet(cur, [...(d.proposed_services || []).filter((p) => p.stated).map((p) => p.key), ...(flow?.ticked ?? [])], keep));
    setReadWordsTicked((cur) => (keep ? cur : new Set(flow?.words ?? [])));
    // his role as he confirmed it; before a confirm, the roles his documents name (he confirms them on the check screen)
    const vocabRoles = new Set(d.vocabulary.roles.map((r) => r.code));
    const storedRoles = (d.capability && d.capability.roles) || [];
    setRoles((cur) => reloadRoles(cur, storedRoles.length ? storedRoles : (d.reading?.roles || []).filter((r) => vocabRoles.has(r)), keep));
    setCoverage((cur) => (keep && cur.length ? cur : (d.capability?.coverage_emirates?.length ? d.capability.coverage_emirates : d.declared_emirates || [])));
    // A refresh because the profile finished reading must not take away what the supplier has typed meanwhile.
    setRawText((cur) => reloadText(cur, d.raw_text || '', keep));
    // `dropped` starts empty on every load and is seeded from the preview instead: the server marks
    // an implication the supplier removed before as `removed: true`, so what was struck out survives
    // without this set having to hold keys the checklist may legitimately tick.
    // what he took out comes back with a reload of the same reading before his confirm (round-2 review, finding A); after it, his
    // confirmed list is the record and nothing is kept struck out
    if (!keep) { setRw(null); setDropped(new Set(!d.confirmed ? flow?.dropped ?? [] : [])); }   // the rewrite preview the supplier is reading stays on a refresh
    const qs = d.questions || [];
    const c = openCards(qs, readKept());
    setCards((cur) => (keep ? { ...c, answers: { ...c.answers, ...cur.answers }, saving: { ...c.saving, ...cur.saving } } : c));
    readAt.current = String(d.reading?.read_at || '');
    const first = firstStep(d, c);
    setStepRaw(first);
    // the screen he lands on is the current history entry, so Back from the next screen returns to it
    if (!keep) { try { window.history.replaceState({ ...window.history.state, qdSvc: first }, ''); } catch { /* history blocked */ } }
    setSt({ loading: false, err: '', data: d });
  };
  const load = async (o: { keepText?: boolean } = {}) => {
    setSt((s) => ({ ...s, loading: true, err: '' }));
    const j = await call('supplier_api', { action: 'services_state' }, token).catch(() => null);
    if (!mounted.current) return;
    if (j && j.ok) show(j as State, o);
    else setSt((s) => ({ ...s, loading: false, err: srvMsg(lang, j, sc(lang, 'load_failed')) }));
  };
  // `lang` is deliberately not a dependency: it is read only for an error string, and re-running the
  // whole load on a language toggle would throw away the supplier's unsaved edits.
  useEffect(() => { load(); }, [token]); // oxlint-disable-line react-hooks/exhaustive-deps

  // WHILE A PROFILE IS BEING READ, ask again (servicesPoll.ts): every 5 s while step A reads, every 2 s once its summary is stored and
  // only the mapping is left, for at most 10 minutes. The answer that says the reading has finished IS the state, drawn as it is
  // (keeping what he ticked or typed meanwhile, review of #1796): one request, not a second full load. Measured on J9 after #1973:
  // stored 117.1 s, on screen 130.3 s; the 13 s were the 5 s wait, the poll and then a second services_state.
  // STEP A HAS READ (slice 3, review round 2): the summary and his services in his own words are shown the moment they are stored,
  // while the names are matched; only that part of the state moves, and only when it changed, so nothing he ticked or typed is
  // touched and the dashboard is not told the same status every 2 s.
  const readingNow = profileReading(st.data);
  const mappingOnly = useRef(false);
  mappingOnly.current = stepALanded(st.data);
  useEffect(() => {
    if (!readingNow) return;
    return startReadingPoll({
      fetchState: () => call('supplier_api', { action: 'services_state' }, token),
      mappingOnly: () => mappingOnly.current,
      onProgress: (p) => { if (mounted.current) setSt((s) => (s.data && !sameProgress(s.data.reading_progress, p) ? { ...s, data: { ...s.data, reading_progress: p as ReadingProgress } } : s)); },
      onFinished: (j) => { if (mounted.current) show(j as State, { keepText: true }); },
    });
  }, [readingNow, token]); // oxlint-disable-line react-hooks/exhaustive-deps

  const confirmedAt = useRef(0);
  const lastStatus = useRef<ServicesStatus | null>(null);
  useEffect(() => {
    const d = st.data;
    if (!d || !onStatus) return;
    const reading = profileReading(d);
    const waiting = !d.confirmed && ((d.proposed_services || []).length > 0 || cards.ids.length > 0 || (d.checklist || []).length > 0);
    const next = { confirmed: !!d.confirmed, reading, waiting, confirmedAt: confirmedAt.current };
    // the workspace re-renders on every status it is told: only a change is told
    const was = lastStatus.current; lastStatus.current = next;
    if (!was || was.confirmed !== next.confirmed || was.reading !== next.reading || was.waiting !== next.waiting || was.confirmedAt !== next.confirmedAt) onStatus(next);
  }, [st.data, cards.ids.length]); // oxlint-disable-line react-hooks/exhaustive-deps

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
        stopTracks();
        if (!mounted.current) { rec.current = null; return; }
        setVoxBusy(true);
        try {
          const blob = new Blob(r.chunks, { type: (r.chunks[0] && r.chunks[0].type) || 'audio/webm' });
          const wav = await blobToWav(blob);
          if (wav.bytes > voice.max_bytes) { setVoxMsg(sc(lang, 'mic_failed')); return; }
          const j = await call('supplier_api', { action: 'transcribe_service_note', audio_b64: wav.b64, mime: 'audio/wav', duration_ms: wav.durationMs }, token);
          if (!mounted.current) return;
          // The dictation lands in the SAME box the supplier types in — one description, one rewrite.
          if (j && j.ok) { if (j.text) setRawText((x) => (x ? x.trimEnd() + '\n' : '') + String(j.text).trim()); }
          else setVoxMsg(sc(lang, j && j.code === 'voice_rate_limited' ? 'mic_limited' : j && j.code === 'voice_input_off' ? 'mic_soon' : 'mic_failed'));
        } catch (_e) { if (mounted.current) setVoxMsg(sc(lang, 'mic_failed')); }
        finally { if (mounted.current) setVoxBusy(false); rec.current = null; }
      };
      mr.start();
      r.timer = window.setTimeout(() => stopRec(), voice.max_seconds * 1000);
      setRecording(true);
    } catch (_e) { setVoxMsg(sc(lang, 'mic_denied')); stopTracks(); rec.current = null; }
  };

  // ── the answers, written behind the cards ─────────────────────────────────────────────────────
  // services_answer is one read and one write on the server (no model). The card has already moved on; this only records
  // whether the write landed. A failed write is kept (memory and this browser) and sent again by "Try again" or by Confirm.
  const sendAnswer = async (id: number, a: Answer): Promise<boolean> => {
    const j = await call('supplier_api', { action: 'services_answer', id, answer: a }, token).catch(() => null);
    if (!mounted.current) return false;
    // a question his new documents no longer raise is gone: it is dropped, not shown as failed for ever
    const ok = !!(j && (j.ok || j.code === 'question_expired' || j.code === 'question_not_found'));
    setCards((c) => { const n = settled(c, id, ok); writeKept(n); return n; });
    return ok;
  };
  const send = (id: number, a: Answer) => { setCards((c) => { writeKept(c); return c; }); void sendAnswer(id, a); };
  const retryFailed = async (c: Cards = cards) => {
    const ids = unsavedIds(c).filter((id) => c.saving[id] === 'failed');
    if (!ids.length) return true;
    setRetrying(true);
    const ok = (await Promise.all(ids.map((id) => sendAnswer(id, c.answers[id])))).every(Boolean);
    if (mounted.current) setRetrying(false);
    return ok;
  };

  if (st.loading && !st.data) return <Card className="qd-panel p-5" aria-busy="true"><span className="inline-flex items-center gap-2 text-[15px]"><Spinner />{sc(lang, 'loading')}</span></Card>;
  if (!st.data) return (
    <Card className="qd-panel p-5">
      <h2 className={h3}>{sc(lang, 'load_failed')}</h2>
      {/* SP-I-01: `st.err` is the server's own English — a raw code, or a DB message on a 500. */}
      {st.err ? <p className={sub}>{panelErrorText(ar ? 'ar' : 'en', st.err)}</p> : null}
      <Button className="mt-3 min-h-11" onClick={() => load()}>{sc(lang, 'retry')}</Button>
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
  const activeTrades = trades.filter((c) => !removedTrades.has(c));
  const ofActive = (k: string) => !removedTrades.has(k.split('.')[0]);
  const liveTicks = [...ticked].filter((k) => activeTrades.includes(k.split('.')[0]));
  const allDocs = d.capability?.source_docs?.docs || [];
  const profileDocs = allDocs.filter((x) => x.kind === 'profile');
  const proposedSvcs = d.proposed_services || [];
  // HIS OWN STATEMENTS, CERTAIN (review of branch 2): not through a partner, not only in his projects or brand list, not "please check".
  // Only these are ticked by "Yes, we do all of these"; every other row is ticked by him alone (or asked on its card, slice 4).
  const otherRow = (p: ProposedSvc) => p.delivery === 'partner' || p.basis === 'shown' || p.basis === 'brand' || !!p.check;
  const proposedOwn = (d.proposed_services || []).filter((p) => !otherRow(p));
  // "found no service" only when nothing is listed (slice 3, review round 2, H09: said above 35 listed services)
  const profileState = asksWhatHeDoes(d.reading, proposedOwn.length) ? 'unclear' : listedProfileState(profileStateOf(profileDocs), (d.proposed_services || []).length);
  const questions = d.questions || [];
  const cardList = cardsOf(questions);
  const savedOwn = d.extra_services || [];
  // SCREEN 1's rows: his documents' own services he does not already hold (after a confirm: only what a new document adds), the
  // partner services no card asks about, and his statements no standard name covers. Shown and brand phrases are asked, never listed.
  const held = new Set(d.confirmed ? d.selected_services : []);
  // after a confirm, screen 1 shows only what a reading NEWER than that confirm adds (review of slice 4, finding 4: the rows he had left
  // unticked came back as "Your new document shows these" with no new document)
  const fresh = isFresh(d);
  const s1Own = fresh ? proposedOwn.filter((p) => !held.has(p.key)) : [];
  const askedKeys = new Set(questions.flatMap((q) => q.options.map((o) => o.key).filter((k): k is string => !!k)));
  // the other rows the reading listed (partner, projects, brands, "please check"), unless a card asks them: his to tick one by one
  const s1Partner = fresh ? proposedSvcs.filter((p) => otherRow(p) && !askedKeys.has(p.key) && !held.has(p.key)) : [];
  // a partner phrase is asked on the partner card when there is one (12 Nov 2026 walk: "Jacuzzi" was offered on both screens)
  const partnerCardOn = questions.some((q) => q.kind === 'partner');
  const readOwnWords = fresh ? (d.reading?.own_words || []).filter((w) => (w.basis === 'stated' || (w.basis === 'partner' && !partnerCardOn)) && !savedOwn.some((s) => s.toLowerCase() === w.words.toLowerCase())) : [];
  const s1Count = s1Own.length + s1Partner.length + readOwnWords.length;
  const unanswered = cardList.filter((q) => !cards.answers[q.id] && !q.answer).length;
  // THE REWRITE CARRIES ITS OWN LABELS and they are read first, then the cards' options, the documents' proposals, the checklist.
  const labels = new Map<string, string>();
  for (const s of Object.values(d.services_by_trade).flat()) labels.set(s.key, svcName(s));
  for (const p of proposedSvcs) labels.set(p.key, p.label_en);
  for (const q of questions) for (const o of q.options) if (o.key) labels.set(o.key, o.label_en);
  for (const i of rw?.items || []) if (i.kind === 'service') labels.set(i.key, ar ? i.label_ar : i.label_en);
  for (const p of rw?.meaning?.proposals || []) labels.set(p.key, ar ? p.label_ar : p.label_en);
  // a key's name; his own words (partner phrases listed beside keys) are shown as written
  const isKey = (k: string) => /^[a-z0-9_]+\.[a-z0-9_]+$/.test(k);
  const labelOfKey = (key: string) => labels.get(key) ?? (isKey(key) ? key.replace(/[._]/g, ' ') : `“${key}”`);

  // BROWSE AND THE LIST ALWAYS AGREE (round-2 review, finding A): a box shows whether the key is on his list, whatever put it there (a
  // tick here, screen 1, a card answer); unticking takes it out (dropped), ticking puts it back
  const toggleKey = (k: string) => {
    const on = statedSet.has(k);
    setTicked((s) => { const n = new Set(s); if (on) n.delete(k); else n.add(k); return n; });
    setDropped((s) => { const n = new Set(s); if (on) n.add(k); else n.delete(k); return n; });
  };
  // Removing marks the card; nothing is lost until Update, and Undo puts the ticks back as they were.
  const removeTrade = (code: string, on: boolean) => setRemovedTrades((s) => { const n = new Set(s); if (on) n.add(code); else n.delete(code); return n; });
  const toggleRole = (c: string) => setRoles((rs) => (rs.includes(c) ? rs.filter((x) => x !== c) : [...rs, c]));
  const toggleDrop = (k: string) => setDropped((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });
  const toggleKeep = (k: string) => setKept((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });
  const toggleProp = (k: string) => setPropTicked((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });
  const toggleReadWord = (w: string) => setReadWordsTicked((s) => { const n = new Set(s); if (n.has(w)) n.delete(w); else n.add(w); return n; });

  // THE REWRITE. Nothing is saved here — the supplier is shown what we made of its words and either
  // confirms it below or edits the text and asks again.
  const rewrite = async (o: { supplyOnly?: boolean } = {}) => {
    const text = rawText.trim();
    if (text.length < 2) return;
    setRwBusy(true); setRwMsg(''); setNote(null);
    const j = await call('supplier_api', {
      action: 'services_rewrite', removed: [...dropped],
      text,
      ...(o.supplyOnly !== undefined ? { supply_only: o.supplyOnly } : {}),
    }, token, { timeoutMs: REASONING_TIMEOUT_MS }).catch(() => null);
    if (!mounted.current) return;
    setRwBusy(false);
    if (j && j.ok) {
      const next = j as Rewrite;
      setRw(next);
      // ASKED, NEVER ASSUMED (decision 4 of the design): for a supplier profiled by the reading, what his words "also cover" starts
      // off, like every other candidate he has not said yes to; before, it starts included with Remove (ruling 439).
      setDropped((s) => new Set([...s, ...next.implied.filter((i) => i.removed || !!d.reading).map((i) => i.key)]));
      if (!next.service_keys.length && !next.own_words.length && !(next.meaning?.proposals || []).length) {
        setRwMsg(next.model?.state === 'off' ? (ar ? next.model.message_ar || '' : next.model.message_en || '') : sc(lang, 'rewrite_none'));
      }
    } else setRwMsg(srvMsg(lang, j, sc(lang, 'rewrite_failed')));
  };

  // WHAT HE HAS AGREED TO: the ticks on screen 1, his answers, the checklist, the rewrite's services, minus anything struck out.
  // The implied half is sent kept-and-removed separately, so matching can subtract a removal (fn_services_effective).
  const rwStated = (rw?.service_keys || []).filter((k) => !dropped.has(k) && ofActive(k));
  // Without a rewrite on screen the STORED implications are what the supplier has — sending [] here
  // wiped services_implied on every plain Update, and the count fell from 8 to 5 (finding 11).
  const rwImplied = (rw ? rw.implied.map((i) => i.key) : d.implied_services).filter((k) => !dropped.has(k) && ofActive(k));
  const rwMeaning = (rw?.meaning?.proposals || []).map((p) => p.key).filter((k) => kept.has(k) && !dropped.has(k));
  const ans = outcome(questions, cards.answers);
  // WHAT HE CONFIRMS, OWN TEAM OR THROUGH A PARTNER, AND HIS WORDS: serviceQuestions.selection (pure, tested; review of slice 4, findings
  // 1, 12, 13). His saved words (finding 9 of 21 Sep) are kept and re-sent; a partner row or answer is partner work, any other tick his own.
  // after a confirm only cards answered since count: his confirmed list is the record of the older answers (finding A)
  const sel = selection({ rows: proposedSvcs, ticked: propTicked, readWords: readOwnWords, wordsTicked: readWordsTicked, questions: liveQuestions(questions, cards.answers, d.capability?.confirmed_at), answers: cards.answers,
    more: [...liveTicks, ...rwStated, ...rwMeaning], storedPartner: d.services_partner || [], savedWords: savedOwn, rewriteWords: rw?.own_words || [],
    dropped });
  const statedKeys = sel.stated, partnerKeys = sel.partner, ownKeys = sel.own;
  const statedSet = new Set(statedKeys);
  const rwOwnWords = sel.words;
  // His own words for what he confirmed: the alias queue cites them (supplier_services.recordOwnPhrases).
  const phrases = [
    ...proposedSvcs.filter((p) => propTicked.has(p.key)).map((p) => ({ phrase: p.phrase, key: p.key })),
    ...(rw?.meaning?.proposals || []).filter((p) => kept.has(p.key) && !dropped.has(p.key)).map((p) => ({ phrase: p.lines[0] || '', key: p.key })),
  ];
  // Removals travel with the save so matching can subtract them: what was already stored, plus
  // whatever was struck out in this preview, plus what he declined on a card, minus anything now stated or kept.
  const rwRemoved = [...new Set([...(d.removed_services || []), ...(rw ? rw.implied.map((i) => i.key) : d.implied_services).filter((k) => dropped.has(k)), ...ans.declined, ...sel.removed])]
    .filter((k) => !rwImplied.includes(k) && !statedKeys.includes(k));

  const save = async () => {
    if (busy) return;
    setBusy(true); setNote(null);
    // an answer whose write failed is sent first, so the ledger the confirm writes holds every answer he gave
    await retryFailed();
    if (!mounted.current) return;
    const j = await call('supplier_api', {
      // A 'refine' trade (split from one he holds, offered unticked) is his only when he ticked a service
      // in it: it is never saved because it was shown (founder instructions 895/899/900).
      // A trade is his only when he ticked a service in it, or confirmed it before, or chose it at sign-up (review of branch 2; the
      // server holds the same rule, supplier_services.keepTickedProposed): a trade alone receives every request that names no service.
      // ...and a trade already his (confirmed, or ON FILE from the directory listing: 14,744 unconfirmed suppliers have one) is sent as before.
      action: 'services_save_rewrite', trades: activeTrades.filter((c) => ['confirmed', 'on_file', 'signup'].includes(sourceOf(c) ?? '') || statedKeys.some((k) => k.startsWith(c + '.'))), removed_trades: [...removedTrades], roles,
      services: statedKeys, partner: [...partnerKeys, ...sel.partnerWords], implied: rwImplied, removed: rwRemoved,
      own_words: rwOwnWords, raw_text: rawText.trim(), phrases,
      // a supplier confirmed BEFORE this build keeps his implied services (review of slice 4, finding 10; the server holds it too)
      asked: !!d.reading && !d.confirmed, coverage_emirates: coverage,
    // The save reasons over each own word (~37 s measured, 27 Oct): see REASONING_TIMEOUT_MS in ./api.
    }, token, { timeoutMs: REASONING_TIMEOUT_MS }).catch(() => null);
    if (!mounted.current) return;
    setBusy(false);
    if (j && j.ok) {
      const review = (j.proposed_trades || []).length > 0 || (j.new_trades_under_review || []).length > 0;
      // The verification the confirm ran (or queued) is said, not left to a badge that does not refresh.
      const gate = String(j.gate || '');
      // two short lines in the bar (round-2 review, finding F: 290 px of a 844 px screen): done, and the verification only while it runs
      const after = gate === 'queued' || gate === 'failed' ? ' ' + F.verify_finishing : '';
      setNote({ kind: 'ok', text: F.confirmed_done + after, review });
      confirmedAt.current += 1;
      load();
    } else setNote({ kind: 'err', text: srvMsg(lang, j, sc(lang, 'save_failed')) });
  };

  const rwNewOwn = (rw?.own_words || []).filter((w) => !savedOwn.some((s) => s.toLowerCase() === w.toLowerCase()));
  const svcCount = countServices([...statedKeys, ...rwImplied], rwOwnWords);
  const canSave = roles.length > 0 && (statedKeys.length > 0 || rwOwnWords.length > 0);
  const voice = d.voice;
  const micNoteId = uid + '-mic';
  // the microphone is offered only when it works (switch on and a device that records); its own outcomes are still said
  const micOn = voice.enabled && canRecord;
  const micNote = !micOn ? '' : voxBusy ? sc(lang, 'mic_busy') : voxMsg;
  // nothing of his is listed yet: the two ways to add are open by themselves
  const nothingListed = statedKeys.length === 0 && rwOwnWords.length === 0;
  const roleName = (c: string) => vocabLabel(lang, 'role', c, d.vocabulary.roles.find((r) => r.code === c)?.label ?? c);
  const typingOn = (e: React.FocusEvent) => { const t = e.target as HTMLElement; if (/^(INPUT|TEXTAREA)$/.test(t.tagName) && (t as HTMLInputElement).type !== 'checkbox') setTyping(true); };
  const typingOff = (e: React.FocusEvent) => { const t = e.target as HTMLElement; if (/^(INPUT|TEXTAREA)$/.test(t.tagName)) setTyping(false); };

  // ── SCREEN 1 ──────────────────────────────────────────────────────────────────────────────────
  if (step === 'understood' && s1Count > 0) {
    const ownStated = readOwnWords.filter((w) => w.basis === 'stated').map((w) => w.words);
    const allProp = (s1Own.length + ownStated.length) > 0 && s1Own.every((p) => propTicked.has(p.key)) && ownStated.every((w) => readWordsTicked.has(w));
    type Row1 = { id: string; label: string; badge: string | null; licence: boolean; on: boolean; toggle: () => void };
    const groups: { quote: string; rows: Row1[] }[] = [];
    const put = (quote: string, r: Row1) => { const g = groups.find((x) => x.quote === quote); if (g) g.rows.push(r); else groups.push({ quote, rows: [r] }); };
    const badgeOf = (p: ProposedSvc) => p.delivery === 'partner' ? PROPOSED_COPY.through_partner : p.basis === 'shown' ? PROPOSED_COPY.from_projects
      : p.basis === 'brand' ? PROPOSED_COPY.from_brands : p.check ? PROPOSED_COPY.please_check : null;
    for (const p of [...s1Own, ...s1Partner]) put(p.snippet || '', { id: p.key, label: p.label_en, badge: badgeOf(p), licence: p.licence === 'not_covered', on: propTicked.has(p.key), toggle: () => toggleProp(p.key) });
    for (const w of readOwnWords) put(w.quote || '', { id: 'w:' + w.words, label: w.words, badge: F.own_words_badge, licence: false, on: readWordsTicked.has(w.words), toggle: () => toggleReadWord(w.words) });
    const next = () => setStep(unanswered > 0 ? 'questions' : 'check');
    return (
      <Card className="qd-panel p-5" ref={top}>
        <section aria-labelledby={uid + '-understood'} data-testid="proposed-services">
          <h2 id={uid + '-understood'} className={h2}>{F.understood_title}</h2>
          {d.reading?.summary && !d.confirmed ? <p className="mt-2 text-[15px] leading-relaxed text-foreground" data-testid="reading-summary">{d.reading.summary}</p> : null}
          {/* the one sentence that says why this matters: body size and contrast, never the grey of small print (coordinator review, 12 Nov) */}
          <p className="mt-2 text-[15px] font-medium leading-relaxed text-foreground" data-testid="understood-lead">{d.confirmed ? F.understood_new : F.understood_lead}</p>
          <h3 className={cn(h3, 'mt-4')}>{F.understood_list(s1Count)}</h3>
          {/* GROUPED UNDER HIS SENTENCE (12 Nov 2026 walk, decoration company: 27 rows, the same line printed under up to three of them).
              Each sentence of his documents is shown once, in his language, with the services read from it ticked one by one. */}
          <ul className="mt-1 divide-y divide-border pb-2">
            {groups.map((g) => (
              <li key={g.quote} className="py-1.5">
                {g.rows.map((r) => (
                  <label key={r.id} className={row} htmlFor={uid + '-p-' + r.id}>
                    <input id={uid + '-p-' + r.id} type="checkbox" className={box} checked={r.on} onChange={r.toggle} />
                    <span className="min-w-0 font-medium" dir="auto">{r.label}{r.badge ? <Badge variant="secondary" className="ms-2">{r.badge}</Badge> : null}{r.licence ? <Badge variant="secondary" className="ms-2">{PROPOSED_COPY.not_on_licence}</Badge> : null}</span>
                  </label>
                ))}
                {/* HIS SENTENCE, IN HIS LANGUAGE (report 3.9): he is confirming his own words; an Arabic line is shown as his words */}
                {g.quote ? <p className="ps-10 pb-1 text-[13.5px] leading-snug text-muted-foreground"><q dir="auto">{g.quote}</q></p> : null}
              </li>
            ))}
          </ul>
          {/* the one tap travels with the thumb: a long list (26 rows for the decoration company) never hides it */}
          {/* the footer sits AFTER the list in the flow, so at the bottom the last row and its quote are fully above it; while the list
              scrolls under it, a soft fade (not a hard edge) shows there is more, and the card is opaque so no text shows through half-cut */}
          <div className="sticky bottom-0 -mx-5 -mb-5 mt-2 flex flex-col gap-2 bg-card px-5 pb-5 pt-3 shadow-[0_-18px_18px_-6px_hsl(var(--card))] pe-16 sm:flex-row sm:pe-5" data-testid="understood-bar">
            {(s1Own.length + ownStated.length) > 0 && !allProp && (
              <Button type="button" className="min-h-12 text-[16px]" onClick={() => { setPropTicked((cur) => { const n = new Set(cur); if (!allProp) for (const p of proposedOwn) n.add(p.key); return n; }); setReadWordsTicked((cur) => new Set([...cur, ...ownStated])); next(); }}>
                {F.all_of_these}
              </Button>
            )}
            <Button type="button" variant={(s1Own.length + ownStated.length) > 0 && !allProp ? 'outline' : 'default'} className="min-h-12 text-[16px]" onClick={next}>{F.next}</Button>
          </div>
        </section>
      </Card>
    );
  }

  // ── SCREEN 2 ──────────────────────────────────────────────────────────────────────────────────
  // the cards also when he lands on screen 1 with nothing on it (a profile whose work is all in captions, H09: review finding 5)
  if ((step === 'questions' || (step === 'understood' && s1Count === 0)) && cards.ids.length > 0 && cards.index < cards.ids.length) {
    return (
      <Card className="qd-panel p-5" ref={top} onFocusCapture={typingOn} onBlurCapture={typingOff}>
        <ServiceQuestions questions={cardList} cards={cards} setCards={setCards} send={send} retry={() => void retryFailed()} retrying={retrying}
          onDone={() => setStep('check')} onBackFirst={s1Count > 0 ? () => setStep('understood') : undefined}
          onChooseTrade={trades.length ? () => { setBrowseOpen(true); setStep('check'); } : undefined} />
      </Card>
    );
  }

  // ── SCREEN 3 ──────────────────────────────────────────────────────────────────────────────────
  const failed = cards.ids.filter((id) => cards.saving[id] === 'failed');
  const lead = d.confirmed ? F.confirmed_lead : !d.reading || (s1Count === 0 && cardList.length === 0) ? stateLine(profileState) : F.check_lead;
  const listed = (title: string, keys: string[], edit?: () => void) => keys.length > 0 && (
    <div className="border-t border-border py-3">
      <div className="flex items-center justify-between gap-3"><h3 className={h3}>{title}</h3>
        {edit ? <Button type="button" variant="link" className="min-h-11 min-w-11 px-2" onClick={edit}>{F.edit}</Button> : null}</div>
      {/* every service on his list can be taken out here, whatever put it there (round-2 review, finding A) */}
      <ul className="mt-1 flex flex-wrap gap-1.5">{keys.map((k) => (
        <li key={k} className="inline-flex items-center rounded-full border border-primary/30 bg-primary/10 ps-3 text-[14px] text-foreground">
          <span dir="auto">{labelOfKey(k)}</span>
          <button type="button" className="inline-flex h-11 w-11 items-center justify-center rounded-full active:bg-muted-foreground/20" onClick={() => toggleDrop(isKey(k) ? k : wordKey(k))}>
            <X aria-hidden className="h-4 w-4" /><span className="sr-only">{sc(lang, 'remove')}: {labelOfKey(k)}</span>
          </button>
        </li>))}</ul>
    </div>
  );
  // what he took out on this screen, offered back until he confirms
  const takenOut = [...sel.removed, ...sel.removedWords];
  // Edit reopens what put them there: his cards (the last one), else screen 1, else the list of his trades' services. Once he has
  // confirmed, his cards are answered and Edit opens Browse (round-3 review of slice 4, finding 2)
  // the list opens where he can see it: below his lists, it was opened off-screen on a phone (round-3 walk at 390 px)
  const openBrowse = () => { setBrowseOpen(true); requestAnimationFrame(() => browseRef.current?.scrollIntoView({ block: 'start', behavior: 'smooth' })); };
  const editOwn = !d.confirmed && cardList.length ? () => setStep('questions') : !d.confirmed && s1Count > 0 ? () => setStep('understood') : openBrowse;
  const partnerCard = cardList.find((q) => q.kind === 'partner');
  const editPartner = partnerCard ? () => { setCards((c) => cardGoTo(c, partnerCard.id)); setStep('questions'); } : undefined;
  return (
    // scroll-pb keeps a focused control clear of the sticky confirm bar (WCAG 2.4.11).
    <Card ref={top} className="qd-panel p-5 [&_input]:scroll-mb-36 [&_button]:scroll-mb-36 [&_textarea]:scroll-mb-36" onFocusCapture={typingOn} onBlurCapture={typingOff}>
      <h2 className={h2}>{d.confirmed ? F.confirmed_title : F.check_title}</h2>
      <p className={cn(sub, 'mt-1 flex items-start gap-2')} role={profileState === 'reading' ? 'status' : undefined} data-testid={profileState === 'reading' ? 'profile-reading' : 'check-lead'}>
        {profileState === 'reading' && !d.reading ? <Loader2 aria-hidden="true" className="mt-0.5 h-4 w-4 shrink-0 animate-spin motion-reduce:animate-none" /> : null}<span>{lead}</span>
      </p>
      {/* ITS PLACE IS HELD WHILE STEP A READS (12 Nov 2026, stub walk at 390x844): the summary and his phrases were inserted above the
          check lists, which dropped 237 px under his finger (one shift of 0.0945). The bars hold about that height; the block keeps it. */}
      {profileState === 'reading' && !d.reading_progress?.summary ? (
        <div className="mt-3 min-h-56" aria-hidden="true" data-testid="reading-progress-held"><Skeleton /><Skeleton className="mt-2" /><Skeleton className="mt-2 w-2/3" /></div>
      ) : null}
      {profileState === 'reading' && d.reading_progress?.summary ? (
        // AS SOON AS STEP A HAS READ (review of branch 2, "not laggy"): what we understood, in his words, while the names are matched
        <div className="mt-3 min-h-56" data-testid="reading-progress">
          <p className="text-[15px] leading-relaxed text-foreground">{d.reading_progress.summary}</p>
          <ul className="mt-2 flex flex-wrap gap-1.5">{(d.reading_progress.claims || []).slice(0, 24).map((c) => <li key={c.words} className="rounded-full border border-primary/30 bg-primary/10 px-3 py-1 text-[14px] text-foreground" dir="auto">{c.words}</li>)}</ul>
          <p className={cn(sub, 'mt-2 flex items-start gap-2')} role="status">
            <Loader2 aria-hidden="true" className="mt-0.5 h-4 w-4 shrink-0 animate-spin motion-reduce:animate-none" />
            <span>{PROPOSED_COPY.progress_help}</span>
          </p>
        </div>
      ) : null}
      {goTo && !profileDocs.length && !d.confirmed ? <Button variant="outline" className="mt-3 min-h-11" onClick={() => goTo('documents')}>{sc(lang, 'go_documents')}</Button> : null}

      {/* a confirmed supplier whose new document adds services, or who has questions still open: one line and one button */}
      {(d.confirmed && s1Count > 0) || unanswered > 0 ? (
        <div className="mt-3 flex flex-wrap items-center gap-2 rounded-md border border-primary/40 bg-primary/10 px-3 py-2">
          <span className="min-w-0 flex-1 text-[14px] text-foreground">{unanswered > 0 ? F.more_questions(unanswered) : F.understood_new}</span>
          <Button type="button" className="min-h-11" onClick={() => setStep(d.confirmed && s1Count > 0 ? 'understood' : 'questions')}>{unanswered > 0 ? F.answer_them : F.review_new}</Button>
        </div>
      ) : null}
      {failed.length > 0 && (
        <div role="alert" className="mt-3 flex flex-wrap items-center gap-2 rounded-md border border-danger/40 bg-danger/10 px-3 py-2 text-[14px]">
          <span className="min-w-0 flex-1">{F.answer_failed}</span>
          <Button type="button" variant="outline" className="min-h-11" disabled={retrying} onClick={() => void retryFailed()}>{retrying ? <><Spinner />{F.retrying}</> : F.retry}</Button>
        </div>
      )}

      <div className="mt-4" data-testid="check-lists">
        {listed(F.own_team(ownKeys.length), ownKeys, editOwn)}
        {/* through a partner: the keys, and his own words for partner work ("Jacuzzi"), quoted as his (review of slice 4, finding 12) */}
        {listed(F.through_partner(partnerKeys.length + sel.partnerWords.length), [...partnerKeys, ...sel.partnerWords], editPartner)}
        {sel.ownWords.length > 0 && (
          <div className="border-t border-border py-3">
            <h3 className={h3}>{F.in_own_words(sel.ownWords.length)}</h3>
            <p className={cn(sub, 'mt-0.5')}>{F.own_words_note}</p>
            <ul className="mt-1.5 flex flex-wrap gap-1.5">
              {sel.ownWords.map((wtext) => (
                <li key={wtext} className="inline-flex items-center rounded-full border border-primary/30 bg-primary/10 ps-3 text-[14px] text-foreground">
                  <span dir="auto">“{wtext}”</span>
                  <button type="button" className="inline-flex h-11 w-11 items-center justify-center rounded-full active:bg-muted-foreground/20" onClick={() => toggleDrop(wordKey(wtext))}>
                    <X aria-hidden className="h-4 w-4" /><span className="sr-only">{sc(lang, 'remove')}: {wtext}</span>
                  </button>
                </li>
              ))}
            </ul>
          </div>
        )}
        {nothingListed ? <p className={cn(sub, 'border-t border-border py-3')}>{F.nothing_yet}</p> : null}
        {/* what he took out stays offered back until Confirm (finding 9 of 21 Sep: removable only by him, and undoable; round-2 review of
            slice 4, finding A: a service from a card answer or screen 1 too) */}
        {takenOut.length > 0 && (
          <div className="border-t border-border py-3" data-testid="taken-out">
            <h3 className={cn(sub, 'font-semibold')}>{F.removed_title}</h3>
            {takenOut.map((k) => (
              <div key={'d:' + k} className={cn(chip, 'mt-1 opacity-80')}>
                <span className="line-through" dir="auto">{isKey(k) ? labelOfKey(k) : k}</span>
                <Button type="button" variant="link" className="ms-auto min-h-11 px-2" onClick={() => toggleDrop(isKey(k) ? k : wordKey(k))}>{F.add_back}<span className="sr-only">: {isKey(k) ? labelOfKey(k) : k}</span></Button>
              </div>
            ))}
          </div>
        )}

        <div className="border-t border-border py-3">
          <div className="flex items-center justify-between gap-3"><h3 className={h3}>{F.where}</h3>
            <Button type="button" variant="link" className="min-h-11 px-2" aria-expanded={whereEdit} onClick={() => setWhereEdit((x) => !x)}>{whereEdit ? F.done : F.change}</Button></div>
          {whereEdit ? <EmirateCheckboxes lang={lang} value={coverage} onChange={setCoverage} legend={<span className="sr-only">{F.where}</span>} />
            : <p className="mt-1 text-[15px] text-foreground">{coverage.length ? coverage.map((e) => emirateLabel(lang, e)).join(', ') : F.where_all}</p>}
        </div>
        <div role="group" aria-labelledby={uid + '-role'} className="border-t border-border py-3">
          <div className="flex items-center justify-between gap-3"><h3 id={uid + '-role'} className={h3}>{F.role}</h3>
            {roles.length > 0 ? <Button type="button" variant="link" className="min-h-11 px-2" aria-expanded={roleEdit} onClick={() => setRoleEdit((x) => !x)}>{roleEdit ? F.done : F.change}</Button> : null}</div>
          {roles.length > 0 && !roleEdit ? <p className="mt-1 text-[15px] text-foreground">{roles.map(roleName).join(', ')}</p> : (
            <div className="mt-2 flex flex-wrap gap-2">
              {d.vocabulary.roles.map((r) => (
                <button key={r.code} type="button" role="checkbox" aria-checked={roles.includes(r.code)} className={chipCls(roles.includes(r.code))} onClick={() => toggleRole(r.code)}>{roleName(r.code)}</button>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* ADDING: ONE TEXT BOX AND THE MIC. Instruction 438. Closed unless nothing of his is listed yet. */}
      <details className="group mt-2 rounded-md border border-border" open={addOpen ?? nothingListed} onToggle={(e) => setAddOpen(e.currentTarget.open)} data-testid="add-missed">
        <summary className={summaryCls}>
          <span>{F.add_missed}</span>
          <ChevronDown aria-hidden="true" className="h-5 w-5 shrink-0 text-muted-foreground transition-transform group-open:rotate-180" />
        </summary>
        <div className="px-3 pb-3">
          <p className={sub} id={uid + '-describe-help'}>{F.add_missed_help}</p>
          <form className="mt-2" onSubmit={(e) => { e.preventDefault(); rewrite(); }}>
            <label className="sr-only" htmlFor={uid + '-raw'}>{sc(lang, 'describe_label')}</label>
            <textarea id={uid + '-raw'} dir="auto" rows={4} maxLength={2000} value={rawText}
                      onChange={(e) => { setRawText(e.target.value); setRwMsg(''); }}
                      onFocus={(e) => e.currentTarget.scrollIntoView({ block: 'center', behavior: 'smooth' })}
                      aria-describedby={uid + '-describe-help'} placeholder={sc(lang, 'describe_ph')}
                      className="w-full rounded-md border border-input bg-transparent px-3 py-2.5 text-base leading-relaxed text-foreground placeholder:text-muted-foreground focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring" />
            <div className="mt-2 flex flex-wrap items-center gap-2">
              <Button type="submit" className="min-h-11" disabled={rwBusy || rawText.trim().length < 2} aria-busy={rwBusy}>
                {rwBusy ? <><Spinner />{sc(lang, 'rewriting')}</> : sc(lang, 'rewrite')}
              </Button>
              {micOn && (
                <Button type="button" variant="outline" className="min-h-11 min-w-11" disabled={voxBusy}
                        aria-pressed={recording} aria-describedby={micNote ? micNoteId : undefined}
                        onClick={() => (recording ? stopRec() : startRec(voice))}>
                  <span aria-hidden>{recording ? '■' : '🎙'}</span>
                  <span className="ms-1.5">{recording ? sc(lang, 'mic_stop') : sc(lang, 'mic_start')}</span>
                </Button>
              )}
            </div>
          </form>
          {micNote ? <p id={micNoteId} role="status" className="mt-1.5 text-[13px] text-muted-foreground">{micNote}</p> : null}
          {rwMsg ? <p role="alert" className="mt-1.5 text-[13px] text-warn-fg">{rwMsg}</p> : null}

          {/* THE SALES ENGINEER'S VERSION — shown before anything is saved. */}
          {rw && (rw.service_keys.length > 0 || rw.own_words.length > 0 || rw.implied.length > 0 || (rw.meaning?.proposals || []).length > 0) && (
            <div className="mt-3 rounded-md border border-border bg-muted/20 p-3" aria-labelledby={uid + '-rw'}>
              <h4 id={uid + '-rw'} className={h3}>{sc(lang, 'rewrite_title')}</h4>
              {/* SUPPLY ONLY — proposed by the words, confirmed or corrected by the supplier. */}
              {rw.supply_only && (rw.supply_only.proposed || rw.supply_only.applied !== rw.supply_only.proposed) && (
                <div className="mt-2 flex flex-wrap items-center gap-2" role="status">
                  <p className={cn(sub, 'min-w-0 flex-1')}>{sc(lang, rw.supply_only.applied ? 'supply_only_note' : 'supply_install_note')}</p>
                  <Button type="button" variant="outline" className="min-h-11" disabled={rwBusy} onClick={() => rewrite({ supplyOnly: !rw.supply_only!.applied })}>
                    {sc(lang, rw.supply_only.applied ? 'we_also_install' : 'we_only_supply')}
                  </Button>
                </div>
              )}
              <ul className="mt-2 flex flex-col gap-1.5">
                {rw.service_keys.map((k) => (
                  <li key={k} className={cn(chip, dropped.has(k) && 'opacity-60')}>
                    <span className="font-medium text-foreground" dir="auto">{labelOfKey(k)}</span>
                    <Button type="button" variant="link" className="ms-auto min-h-11 px-2" onClick={() => toggleDrop(k)}>
                      {dropped.has(k) ? sc(lang, 'restore') : sc(lang, 'remove')}<span className="sr-only">: {labelOfKey(k)}</span>
                    </Button>
                  </li>
                ))}
                {/* UNDERSTOOD, NOT WORD-MATCHED — off until he adds it (finding SP-F-06) */}
                {(rw.meaning?.proposals || []).map((p) => (
                  <li key={'m:' + p.key} className={cn(chip, !kept.has(p.key) && 'opacity-70')}>
                    <span className="flex min-w-0 flex-col"><span className="font-medium text-foreground" dir="auto">{ar ? p.label_ar : p.label_en}</span>
                      <span className="text-[13px] text-muted-foreground" dir="auto">{sc(lang, 'meaning_because')} “{p.lines[0]}”</span></span>
                    <Button type="button" variant="link" className="ms-auto min-h-11 px-2" onClick={() => toggleKeep(p.key)}>
                      {kept.has(p.key) ? sc(lang, 'remove') : sc(lang, 'add')}<span className="sr-only">: {ar ? p.label_ar : p.label_en}</span>
                    </Button>
                  </li>
                ))}
                {/* WHAT HIS WORDS ALSO COVER (instruction 439), with the reason; for a supplier the reading profiled, off until he adds it */}
                {rw.implied.map((i) => (
                  <li key={'i:' + i.key} className={cn(chip, dropped.has(i.key) && 'opacity-70')}>
                    <span className="flex min-w-0 flex-col"><span className="font-medium text-foreground" dir="auto">{ar ? i.label_ar : i.label_en}</span>
                      <span className="text-[13px] text-muted-foreground" dir="auto">{sc(lang, 'implied_because')} {ar ? i.because[0]?.ar : i.because[0]?.en}</span></span>
                    <Button type="button" variant="link" className="ms-auto min-h-11 px-2" onClick={() => toggleDrop(i.key)}>
                      {dropped.has(i.key) ? (d.reading ? sc(lang, 'add') : sc(lang, 'restore')) : sc(lang, 'remove')}<span className="sr-only">: {ar ? i.label_ar : i.label_en}</span>
                    </Button>
                  </li>
                ))}
                {/* WE NEVER DROP THESE AND NEVER GUESS THEM: his own words, kept as written (listed above once added) */}
                {rwNewOwn.map((wtext) => (
                  <li key={'o:' + wtext} className={cn(chip, dropped.has(wordKey(wtext)) && 'opacity-60')}>
                    <span className="font-medium text-foreground" dir="auto">“{wtext}”</span>
                    <Badge variant="secondary">{F.own_words_badge}</Badge>
                    <Button type="button" variant="link" className="ms-auto min-h-11 px-2" onClick={() => toggleDrop(wordKey(wtext))}>
                      {dropped.has(wordKey(wtext)) ? sc(lang, 'restore') : sc(lang, 'remove')}<span className="sr-only">: {wtext}</span>
                    </Button>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      </details>

      {/* THE SALES ENGINEER'S PREPARED CHECKLIST. His proposal about what we already hold, the supplier correcting it.
          BROWSED, NOT TICKED BY THE TRADE (12 Nov 2026, ruling 1647): no "Select all" on a trade, and the list sits under
          "Browse all services of my trades", with a chevron and a 48 px title. Open by itself whenever nothing of his is listed (review of
          12 Nov 2026: closed, those suppliers' only boxes were hidden); since the check screen lists what he holds with Edit (slice 4),
          a confirmed supplier's edit opens it from Edit instead of facing every service of every trade (walk: 470 words on one screen).
          scripts/checks/a_supplier_is_asked_never_assumed.test.mjs. */}
      {trades.length > 0 && (
      <details ref={browseRef} className="group mt-2 scroll-mt-4 rounded-md border border-border" open={browseOpen ?? nothingListed} onToggle={(e) => setBrowseOpen(e.currentTarget.open)} data-testid="browse-trades">
        <summary className={summaryCls}>
          <span>{VERIFY_COPY.browse_trades}</span>
          <ChevronDown aria-hidden="true" className="h-5 w-5 shrink-0 text-muted-foreground transition-transform group-open:rotate-180" />
        </summary>
      {/* drawn only while open: closed, its boxes cost the move to this screen 120-190 ms on a phone-sized walk (12 Nov 2026) */}
      {(browseOpen ?? nothingListed) && <div className="flex flex-col gap-3 p-3">
        {trades.map((code) => {
          const svcs = d.services_by_trade[code] || [];
          const src = sourceOf(code);
          if (removedTrades.has(code)) return (
            <div key={code} className={cn(chip, 'border-dashed')} role="status">
              <span className="font-medium text-foreground line-through" dir="auto">{tradeName(code)}</span>
              <span className="text-muted-foreground">{sc(lang, 'trade_removed')}</span>
              <Button type="button" variant="link" className="ms-auto min-h-11 px-2" onClick={() => removeTrade(code, false)}>
                {sc(lang, 'undo')}<span className="sr-only">: {tradeName(code)}</span>
              </Button>
            </div>
          );
          return (
            <fieldset key={code} className="rounded-md border border-border p-3">
              <legend className="px-1">
                <span className={h3}>{tradeName(code)}</span>
                {src === 'documents' ? <Badge variant="secondary" className="ms-2">{sc(lang, 'from_docs')}</Badge>
                  : src === 'signup' ? <Badge variant="secondary" className="ms-2">{VERIFY_COPY.signup_trade}</Badge>
                  : src === 'refine' ? <Badge variant="secondary" className="ms-2">{sc(lang, 'refine_badge')}</Badge> : null}
              </legend>
              {svcs.length ? (
                <div className="grid grid-cols-1 gap-x-3 sm:grid-cols-2">
                  {svcs.map((s) => (
                    <label key={s.key} className={row} htmlFor={uid + s.key}>
                      <input id={uid + s.key} type="checkbox" className={box} checked={statedSet.has(s.key)} onChange={() => toggleKey(s.key)} />
                      <span>{svcName(s)}</span>
                    </label>
                  ))}
                </div>
              ) : <p className={cn(sub, 'px-2 py-1')}>{sc(lang, 'no_services_listed')}</p>}
              <Button type="button" variant="link" className="mt-1 min-h-11 px-2 text-muted-foreground" onClick={() => removeTrade(code, true)}>
                {sc(lang, 'remove_trade')}<span className="sr-only">: {tradeName(code)}</span>
              </Button>
            </fieldset>
          );
        })}
      </div>}
      </details>
      )}

      {d.trade_proposals.length > 0 && (
        <section className="mt-4" aria-labelledby={uid + '-prop'}>
          <h3 id={uid + '-prop'} className={cn(sub, 'font-semibold')}>{sc(lang, 'proposals_title')}</h3>
          <ul className="mt-1 space-y-1 text-[13px] text-muted-foreground">
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


      {/* The Confirm bar travels with the thumb (sticky) except while the keyboard is up, so it never covers the field being typed in;
          it is the last thing in the card, so at the bottom it sits below the last control. pe-16 on phones keeps it clear of the
          docked assistant bubble (measured 29px overlap, 14 Sep). */}
      <div className={cn('mt-4 border-t border-border bg-card/90 px-5 pb-5 pt-3 backdrop-blur-md -mx-5 -mb-5', !typing && 'sticky bottom-0 pe-16 sm:pe-5')} data-testid="confirm-bar">
        {/* THE ANSWER TO HIS PRESS, WHERE HIS THUMB IS (review of slice 4, finding 4: "Done" was drawn 490 px below a 844 px screen) */}
        <div role="status" aria-live="polite">
          {note && note.kind === 'ok' ? <p className="mb-2 rounded-md border border-primary/40 bg-primary/10 px-3 py-1.5 text-[14px] font-semibold leading-snug text-foreground" data-testid="confirm-done">{note.text}{note.review ? ' ' + sc(lang, 'review_sent') : ''}</p> : null}
        </div>
        {note && note.kind === 'err' ? <p role="alert" className="mb-2 text-[14px] text-danger-fg">{note.text}</p> : null}
        {!canSave ? <p className="mb-2 text-[14px] text-warn-fg">{roles.length ? F.need_service : nothingListed ? F.need_service + ' ' + F.need_role : F.need_role}</p>
          : note?.kind === 'ok' ? null : <p className={cn(sub, 'mb-2')}>{scCount(lang, svcCount, roles.length)}</p>}
        <Button className="min-h-12 w-full text-[16px] sm:w-auto" disabled={busy || !canSave} aria-busy={busy} onClick={save} data-testid="confirm">
          {busy ? <><Spinner />{F.confirming}</> : d.confirmed ? F.update : F.confirm}
        </Button>
      </div>
    </Card>
  );
}

/** The screen he opens on: where this browser last was for this reading, else the first screen with something for him to do. */
/** After a confirm, only a reading newer than it has anything new for screen 1 (review of slice 4, finding 4). */
function isFresh(d: State): boolean {
  if (!d.confirmed) return true;
  const read = Date.parse(String(d.reading?.read_at ?? '')), conf = Date.parse(String(d.capability?.confirmed_at ?? ''));
  return Number.isFinite(read) && Number.isFinite(conf) && read > conf;
}
function firstStep(d: State, c: Cards): Step {
  // a row the reading listed that no card asks and he does not already hold, or his words (review finding 5: rows the cards ask, as on a
  // profile whose work is all in captions, are not screen 1's; it opens on the cards)
  const asked = new Set((d.questions || []).flatMap((q) => q.options.map((o) => o.key).filter(Boolean)));
  const fresh = isFresh(d);
  const own = fresh ? (d.proposed_services || []).filter((p) => !asked.has(p.key) && !(d.confirmed && d.selected_services.includes(p.key))) : [];
  const hasS1 = own.length > 0 || (fresh && (d.reading?.own_words || []).some((w) => w.basis === 'stated' || w.basis === 'partner'));
  const open = c.index < c.ids.length;
  const saved = d.reading?.read_at ? readStep(String(d.reading.read_at)) : null;
  if (saved && (saved !== 'questions' || open) && (saved !== 'understood' || hasS1)) return saved;
  if (d.confirmed) return 'check';
  if (hasS1) return 'understood';
  return open ? 'questions' : 'check';
}
