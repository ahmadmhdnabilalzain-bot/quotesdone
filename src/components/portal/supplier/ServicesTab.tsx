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
import { ChevronDown, X } from 'lucide-react';
import { cn } from '@/lib/utils';
import { blobToWav } from '@/lib/wavEncode';
import { call, REASONING_TIMEOUT_MS } from './api';
import { panelErrorText } from './PanelState';
import { srvMsg, vocabLabel, emirateLabel } from './serverCopy';
import { asksWhatHeDoes, countServices, FLOW_COPY as F, profileStateOf, PROPOSED_COPY, sc, scCount, stateLine, VERIFY_COPY } from './servicesCopy';
import { reloadRoles, reloadSet, reloadText } from './servicesRead';
import EmirateCheckboxes from './EmirateCheckboxes';
import ServiceQuestions, { chipCls } from './ServiceQuestions';
import { cardsOf, goTo as cardGoTo, openCards, outcome, readKept, settled, unsavedIds, writeKept, type Answer, type Cards, type Question } from './serviceQuestions';

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
  capability: { roles?: string[]; coverage_emirates?: string[]; source_docs?: { docs?: Doc[] } } | null;
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
const uniq = (a: string[]) => [...new Set(a)];
// where this browser last was in the flow, for one reading (a reload, Back, or tomorrow resumes there); per-viewer convenience only
const STEP_KEY = 'qd-svc-step';
const readStep = (readAt: string): Step | null => { try { const v = JSON.parse(localStorage.getItem(STEP_KEY) || 'null'); return v && v.at === readAt ? v.step : null; } catch { return null; } };
const writeStep = (readAt: string, step: Step) => { try { localStorage.setItem(STEP_KEY, JSON.stringify({ at: readAt, step })); } catch { /* storage blocked */ } };

export default function ServicesTab({ token, lang, goTo }: { token: string; lang: string; goTo?: (k: string) => void }) {
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
  const setStep = (s: Step, o: { push?: boolean } = {}) => {
    setStepRaw(s);
    if (readAt.current) writeStep(readAt.current, s);
    try { if (o.push !== false) window.history.pushState({ ...window.history.state, qdSvc: s }, ''); } catch { /* history blocked */ }
    top.current?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  };
  useEffect(() => {
    const onPop = (e: PopStateEvent) => { const s = e.state?.qdSvc; if (s === 'understood' || s === 'questions' || s === 'check') setStepRaw(s); };
    window.addEventListener('popstate', onPop);
    return () => window.removeEventListener('popstate', onPop);
  }, []);

  const load = async (o: { keepText?: boolean } = {}) => {
    setSt((s) => ({ ...s, loading: true, err: '' }));
    const j = await call('supplier_api', { action: 'services_state' }, token).catch(() => null);
    if (!mounted.current) return;
    if (j && j.ok) {
      const d = j as State;
      setTrades(d.checklist.map((c) => c.code));
      // keepText = a refresh because the profile finished reading: everything the supplier did meanwhile stays (review of #1796).
      const keep = !!o.keepText;
      setRemovedTrades((cur) => reloadSet(cur, [], keep));
      setTicked((cur) => reloadSet(cur, d.selected_services, keep));
      setPropTicked((cur) => reloadSet(cur, (d.proposed_services || []).filter((p) => p.stated).map((p) => p.key), keep));
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
      if (!keep) { setRw(null); setDropped(new Set()); }   // the rewrite preview the supplier is reading stays on a refresh
      const qs = d.questions || [];
      const c = openCards(qs, readKept());
      setCards((cur) => (keep ? { ...c, answers: { ...c.answers, ...cur.answers }, saving: { ...c.saving, ...cur.saving } } : c));
      readAt.current = String(d.reading?.read_at || '');
      const first = firstStep(d, c);
      setStepRaw(first);
      // the screen he lands on is the current history entry, so Back from the next screen returns to it
      if (!keep) { try { window.history.replaceState({ ...window.history.state, qdSvc: first }, ''); } catch { /* history blocked */ } }
      setSt({ loading: false, err: '', data: d });
    } else {
      setSt((s) => ({ ...s, loading: false, err: srvMsg(lang, j, sc(lang, 'load_failed')) }));
    }
  };
  // `lang` is deliberately not a dependency: it is read only for an error string, and re-running the
  // whole load on a language toggle would throw away the supplier's unsaved edits.
  useEffect(() => { load(); }, [token]); // oxlint-disable-line react-hooks/exhaustive-deps

  // WHILE A PROFILE IS BEING READ, ask again every 5 seconds (at most 10 minutes, as the Documents tab does); when it has finished,
  // reload, keeping any text typed, and the reading's screens appear by themselves.
  const readingNow = !!st.data?.capability?.source_docs?.docs?.some((x) => x.kind === 'profile' && x.status === 'reading');
  const polls = useRef(0);
  useEffect(() => {
    if (!readingNow) { polls.current = 0; return; }
    if (polls.current >= 120) return;
    const id = window.setTimeout(async () => {
      polls.current += 1;
      const j = await call('supplier_api', { action: 'services_state' }, token).catch(() => null);
      if (!mounted.current) return;
      const going = !!j?.capability?.source_docs?.docs?.some((x: Doc) => x.kind === 'profile' && x.status === 'reading');
      if (j && j.ok && !going) load({ keepText: true });
      else setSt((s) => ({ ...s }));   // asks again in 5 seconds
    }, 5000);
    return () => window.clearTimeout(id);
  }, [readingNow, st, token]); // oxlint-disable-line react-hooks/exhaustive-deps

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
  const profileState = asksWhatHeDoes(d.reading, proposedOwn.length) ? 'unclear' : profileStateOf(profileDocs);
  const questions = d.questions || [];
  const cardList = cardsOf(questions);
  const savedOwn = d.extra_services || [];
  // SCREEN 1's rows: his documents' own services he does not already hold (after a confirm: only what a new document adds), the
  // partner services no card asks about, and his statements no standard name covers. Shown and brand phrases are asked, never listed.
  const held = new Set(d.confirmed ? d.selected_services : []);
  const s1Own = proposedOwn.filter((p) => !held.has(p.key));
  const askedKeys = new Set(questions.flatMap((q) => q.options.map((o) => o.key).filter((k): k is string => !!k)));
  // the other rows the reading listed (partner, projects, brands, "please check"), unless a card asks them: his to tick one by one
  const s1Partner = proposedSvcs.filter((p) => otherRow(p) && !askedKeys.has(p.key) && !held.has(p.key));
  // a partner phrase is asked on the partner card when there is one (12 Nov 2026 walk: "Jacuzzi" was offered on both screens)
  const partnerCardOn = questions.some((q) => q.kind === 'partner');
  const readOwnWords = (d.reading?.own_words || []).filter((w) => (w.basis === 'stated' || (w.basis === 'partner' && !partnerCardOn)) && !savedOwn.some((s) => s.toLowerCase() === w.words.toLowerCase()));
  const s1Count = s1Own.length + s1Partner.length + readOwnWords.length;
  const unanswered = cardList.filter((q) => !cards.answers[q.id] && !q.answer).length;
  // THE REWRITE CARRIES ITS OWN LABELS and they are read first, then the cards' options, the documents' proposals, the checklist.
  const labels = new Map<string, string>();
  for (const s of Object.values(d.services_by_trade).flat()) labels.set(s.key, svcName(s));
  for (const p of proposedSvcs) labels.set(p.key, p.label_en);
  for (const q of questions) for (const o of q.options) if (o.key) labels.set(o.key, o.label_en);
  for (const i of rw?.items || []) if (i.kind === 'service') labels.set(i.key, ar ? i.label_ar : i.label_en);
  for (const p of rw?.meaning?.proposals || []) labels.set(p.key, ar ? p.label_ar : p.label_en);
  const labelOfKey = (key: string) => labels.get(key) ?? key.replace(/[._]/g, ' ');

  const toggleKey = (k: string) => setTicked((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });
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
  const propKeys = proposedSvcs.map((p) => p.key).filter((k) => propTicked.has(k));
  const ans = outcome(questions, cards.answers);
  const statedKeys = [...new Set([...liveTicks, ...rwStated, ...rwMeaning, ...propKeys, ...ans.own, ...ans.partner])].filter((k) => !dropped.has(k));
  // THROUGH A PARTNER: his answers, a partner row he ticked on screen 1, and what he confirmed so before unless he now says own team
  const partnerKeys = uniq([...ans.partner, ...s1Partner.filter((p) => propTicked.has(p.key)).map((p) => p.key),
    ...(d.services_partner || []).filter((k) => !ans.own.includes(k))]).filter((k) => statedKeys.includes(k));
  const ownKeys = statedKeys.filter((k) => !partnerKeys.includes(k));
  // THE SUPPLIER'S OWN WORDS ALREADY SAVED (finding 9): shown, kept, and re-sent; with his answers' words and the reading's he ticked.
  const rwOwnWords = [...savedOwn, ...(rw?.own_words || [])].concat(readOwnWords.map((w) => w.words).filter((w) => readWordsTicked.has(w)), ans.ownWords)
    .filter((w, i, all) => all.findIndex((x) => x.toLowerCase() === w.toLowerCase()) === i)
    .filter((w) => !dropped.has(wordKey(w)));
  // His own words for what he confirmed: the alias queue cites them (supplier_services.recordOwnPhrases).
  const phrases = [
    ...proposedSvcs.filter((p) => propTicked.has(p.key)).map((p) => ({ phrase: p.phrase, key: p.key })),
    ...(rw?.meaning?.proposals || []).filter((p) => kept.has(p.key) && !dropped.has(p.key)).map((p) => ({ phrase: p.lines[0] || '', key: p.key })),
  ];
  // Removals travel with the save so matching can subtract them: what was already stored, plus
  // whatever was struck out in this preview, plus what he declined on a card, minus anything now stated or kept.
  const rwRemoved = [...new Set([...(d.removed_services || []), ...(rw ? rw.implied.map((i) => i.key) : d.implied_services).filter((k) => dropped.has(k)), ...ans.declined])]
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
      action: 'services_save_rewrite', trades: activeTrades.filter((c) => sourceOf(c) === 'confirmed' || sourceOf(c) === 'signup' || statedKeys.some((k) => k.startsWith(c + '.'))), removed_trades: [...removedTrades], roles,
      services: statedKeys, partner: partnerKeys, implied: rwImplied, removed: rwRemoved,
      own_words: rwOwnWords, raw_text: rawText.trim(), phrases,
      asked: !!d.reading, coverage_emirates: coverage,
    // The save reasons over each own word (~37 s measured, 27 Oct): see REASONING_TIMEOUT_MS in ./api.
    }, token, { timeoutMs: REASONING_TIMEOUT_MS }).catch(() => null);
    if (!mounted.current) return;
    setBusy(false);
    if (j && j.ok) {
      const review = (j.proposed_trades || []).length > 0 || (j.new_trades_under_review || []).length > 0;
      // The verification the confirm ran (or queued) is said, not left to a badge that does not refresh.
      const gate = String(j.gate || '');
      const after = gate === 'approved' ? ' ' + sc(lang, 'gate_approved') : gate === 'queued' || gate === 'failed' ? ' ' + sc(lang, 'gate_finishing') : '';
      setNote({ kind: 'ok', text: F.confirmed_done + after, review });
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
          <div className="sticky bottom-0 -mx-5 -mb-5 mt-2 flex flex-col gap-2 bg-card px-5 pb-5 pt-3 shadow-[0_-18px_18px_-6px_hsl(var(--card))] sm:flex-row" data-testid="understood-bar">
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
  if (step === 'questions' && cards.ids.length > 0 && cards.index < cards.ids.length) {
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
      <ul className="mt-1 flex flex-wrap gap-1.5">{keys.map((k) => <li key={k} className="rounded-full border border-primary/30 bg-primary/10 px-3 py-1 text-[14px] text-foreground" dir="auto">{labelOfKey(k)}</li>)}</ul>
    </div>
  );
  const editOwn = s1Count > 0 ? () => setStep('understood') : () => setBrowseOpen(true);
  const partnerCard = cardList.find((q) => q.kind === 'partner');
  const editPartner = partnerCard ? () => { setCards((c) => cardGoTo(c, partnerCard.id)); setStep('questions'); } : undefined;
  return (
    // scroll-pb keeps a focused control clear of the sticky confirm bar (WCAG 2.4.11).
    <Card ref={top} className="qd-panel p-5 [&_input]:scroll-mb-36 [&_button]:scroll-mb-36 [&_textarea]:scroll-mb-36" onFocusCapture={typingOn} onBlurCapture={typingOff}>
      <h2 className={h2}>{d.confirmed ? F.confirmed_title : F.check_title}</h2>
      <p className={cn(sub, 'mt-1 flex items-start gap-2')} role={profileState === 'reading' ? 'status' : undefined} data-testid="check-lead">
        {profileState === 'reading' && !d.reading ? <Spinner className="mt-1 shrink-0" /> : null}<span>{lead}</span>
      </p>
      {profileState === 'reading' && d.reading_progress?.summary ? (
        // AS SOON AS STEP A HAS READ (review of branch 2, "not laggy"): what we understood, in his words, while the names are matched
        <div className="mt-3" data-testid="reading-progress">
          <p className="text-[15px] leading-relaxed text-foreground">{d.reading_progress.summary}</p>
          <ul className="mt-2 flex flex-wrap gap-1.5">{(d.reading_progress.claims || []).slice(0, 24).map((c) => <li key={c.words} className="rounded-full border border-primary/30 bg-primary/10 px-3 py-1 text-[14px] text-foreground" dir="auto">{c.words}</li>)}</ul>
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
        {listed(F.through_partner(partnerKeys.length), partnerKeys, editPartner)}
        {rwOwnWords.length > 0 && (
          <div className="border-t border-border py-3">
            <h3 className={h3}>{F.in_own_words(rwOwnWords.length)}</h3>
            <p className={cn(sub, 'mt-0.5')}>{F.own_words_note}</p>
            <ul className="mt-1.5 flex flex-wrap gap-1.5">
              {rwOwnWords.map((wtext) => (
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
        {/* removed own words stay offered back until Confirm (finding 9: removable only by the supplier, and undoable) */}
        {savedOwn.filter((w) => dropped.has(wordKey(w))).map((wtext) => (
          <div key={'d:' + wtext} className={cn(chip, 'mt-1 opacity-70')}>
            <span className="line-through" dir="auto">{wtext}</span>
            <Button type="button" variant="link" className="ms-auto min-h-11 px-2" onClick={() => toggleDrop(wordKey(wtext))}>{sc(lang, 'restore')}<span className="sr-only">: {wtext}</span></Button>
          </div>
        ))}

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
      <details className="group mt-2 rounded-md border border-border" open={browseOpen ?? nothingListed} onToggle={(e) => setBrowseOpen(e.currentTarget.open)} data-testid="browse-trades">
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
                      <input id={uid + s.key} type="checkbox" className={box} checked={ticked.has(s.key)} onChange={() => toggleKey(s.key)} />
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

      <div role="status" aria-live="polite">
        {note && note.kind === 'ok' ? <p className="mt-3 text-[14px] font-semibold text-primary" data-testid="confirm-done">{note.text}{note.review ? ' ' + sc(lang, 'review_sent') : ''}</p> : null}
      </div>
      {note && note.kind === 'err' ? <p role="alert" className="mt-3 text-[14px] text-danger-fg">{note.text}</p> : null}

      {/* The Confirm bar travels with the thumb (sticky) except while the keyboard is up, so it never covers the field being typed in;
          it is the last thing in the card, so at the bottom it sits below the last control. pe-16 on phones keeps it clear of the
          docked assistant bubble (measured 29px overlap, 14 Sep). */}
      <div className={cn('mt-4 border-t border-border bg-card/90 px-5 pb-5 pt-3 backdrop-blur-md -mx-5 -mb-5', !typing && 'sticky bottom-0 pe-16 sm:pe-5')} data-testid="confirm-bar">
        {!canSave ? <p className="mb-2 text-[14px] text-warn-fg">{roles.length ? F.need_service : nothingListed ? F.need_service + ' ' + F.need_role : F.need_role}</p>
          : <p className={cn(sub, 'mb-2')}>{scCount(lang, svcCount, roles.length)}</p>}
        <Button className="min-h-12 w-full text-[16px] sm:w-auto" disabled={busy || !canSave} aria-busy={busy} onClick={save} data-testid="confirm">
          {busy ? <><Spinner />{F.confirming}</> : d.confirmed ? F.update : F.confirm}
        </Button>
      </div>
    </Card>
  );
}

/** The screen he opens on: where this browser last was for this reading, else the first screen with something for him to do. */
function firstStep(d: State, c: Cards): Step {
  // any row the reading listed that he does not already hold (his own, partner, projects, brands, "please check"), or his words
  const own = (d.proposed_services || []).filter((p) => !(d.confirmed && d.selected_services.includes(p.key)));
  const hasS1 = own.length > 0 || (d.reading?.own_words || []).some((w) => w.basis === 'stated' || w.basis === 'partner');
  const open = c.index < c.ids.length;
  const saved = d.reading?.read_at ? readStep(String(d.reading.read_at)) : null;
  if (saved && (saved !== 'questions' || open) && (saved !== 'understood' || hasS1)) return saved;
  if (d.confirmed) return 'check';
  if (hasS1) return 'understood';
  return open ? 'questions' : 'check';
}
