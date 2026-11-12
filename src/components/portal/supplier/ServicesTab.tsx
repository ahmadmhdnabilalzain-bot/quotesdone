'use client';
// THE SERVICES TAB — the supplier's first screen and the matching's main source (founder, 15 Sep 2026:
// "this will be our cross matching main source"). It supersedes the Scope panel (CapabilityConfirmPanel,
// removed from SupplierPortal.tsx the same day): the same confirm, the same versioned ledger in
// supplier_capability_confirmation.
//
// ADDING A SERVICE IS TYPING OR SPEAKING, NOT PICKING (founder, instruction 438): "for adding services
// its not a checkbox or drop down menu. i told you its a voice to text or text box. once filled the
// sales engineer will rewrite that professionally since he will cross match based on that." So the
// "add a trade" dropdown and the one-at-a-time extras field are GONE. What is left is:
//   * the sales engineer's PREPARED checklist — his proposal about the trades already on file, which
//     the supplier corrects. That is the only checkbox on this screen, and it is not "adding".
//   * ONE free text box (with the mic beside it) where the supplier says what it does, in its own
//     words, in either language.
//   * the SALES ENGINEER'S VERSION of those words — standard service names, the services they also
//     cover with the reason for each, and anything we could not name kept verbatim — which the
//     supplier edits and confirms before a single thing is saved.
//
// API-FIRST. Every read and write is a supplier_api action (docs/api/supplier_portal_services.md):
// services_state, services_rewrite, services_save_rewrite, transcribe_service_note. This component
// holds no matching rule and no alias of its own — what a phrase means, what it implies and why all
// come from the server, so a mobile app gets the same answers from the same actions.
//
// VOICE records here and is transcribed on the server (founder, 15 Sep 2026: "we cant use the browser
// built in"). While decision_policy supplier_voice_input_enabled is off, the mic is shown disabled with
// a note and typing works fully.
import { useEffect, useId, useRef, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { ChevronDown, Loader2 } from 'lucide-react';
import { cn } from '@/lib/utils';
import { blobToWav } from '@/lib/wavEncode';
import { call, REASONING_TIMEOUT_MS } from './api';
import { panelErrorText } from './PanelState';
import { srvMsg, vocabLabel } from './serverCopy';
import { asksWhatHeDoes, countServices, listedProfileState, profileStateOf, PROPOSED_COPY, sc, scCount, servicesSentences, VERIFY_COPY, VERIFY_COPY_NO_LIST } from './servicesCopy';
import { docStateLine, englishLines, isEnglishLine, reloadRoles, reloadSet, reloadText } from './servicesRead';

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
// Reader @5 (supplier_profile_reading.ts): the phrases kept in his own words, and the questions drafted for him (their cards are slice 4).
type ReadOwnWords = { words: string; quote: string; basis: string };
type Reading = { own_words?: ReadOwnWords[]; questions?: { kind: string; status: string }[] } | null;
type LicenceCheck = { read: boolean; activities: string[]; licence_trades: string[]; not_covered: string[] };
type State = {
  ok: boolean; confirmed: boolean; first_run: boolean;
  checklist: ChecklistTrade[]; services_by_trade: Record<string, Service[]>;
  selected_services: string[]; extra_services: string[];
  raw_text: string; implied_services: string[]; removed_services: string[]; rewritten_at: string | null;
  vocabulary: { trades: Trade[]; roles: Role[] };
  capability: { roles?: string[]; source_docs?: { docs?: Doc[] } } | null;
  trade_proposals: Proposal[]; voice: Voice;
  proposed_services?: ProposedSvc[]; licence_check?: LicenceCheck | null; reading?: Reading; reading_progress?: ReadingProgress;
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

const box = 'mt-0.5 h-5 w-5 shrink-0 rounded border-input accent-[hsl(var(--primary))] focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring';
const row = 'flex min-h-11 cursor-pointer items-start gap-2.5 rounded-md px-2 py-2.5 text-[13.5px] leading-snug text-foreground hover:bg-muted/40';
const h3 = 'text-[14.5px] font-bold tracking-[-.012em] text-foreground';
const sub = 'text-[13px] leading-[1.65] text-muted-foreground max-w-[68ch]';
const chip = 'flex flex-wrap items-center gap-2 rounded-md border border-border px-3 py-1.5 text-[13px]';

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
  // The services the documents proposed that the supplier ticked here (they may sit outside the prepared trades).
  const [propTicked, setPropTicked] = useState<Set<string>>(new Set());
  // the reading's own-words phrases he ticked: sent with his own words on Confirm (nothing is kept for him unticked)
  const [readWordsTicked, setReadWordsTicked] = useState<Set<string>>(new Set());
  // "Browse all services of my trades": null until he opens or closes it; until then open for a confirmed edit, or when nothing of his own was proposed.
  const [browseOpen, setBrowseOpen] = useState<boolean | null>(null);
  const [roles, setRoles] = useState<string[]>([]);
  const [rawText, setRawText] = useState('');
  const [rw, setRw] = useState<Rewrite | null>(null);
  // Which lines the supplier struck out. Service and implication keys go in as they are; a phrase we
  // could not name goes in under a `word:` prefix, because it is free text and nothing stops a
  // supplier typing something shaped like a service key (React review, 18 Sep 2026).
  const [dropped, setDropped] = useState<Set<string>>(new Set());
  // WHAT THE MEANING LAYER PROPOSED AND THE SUPPLIER THEN ADDED (22 Sep 2026, finding SP-F-06).
  // Kept apart from `dropped` deliberately: a word-rule hit and a curated implication are things the
  // supplier SAID, ticked until struck out; a meaning proposal is our reading of what a line probably
  // means, and it decides who receives an inquiry. It is off until the supplier says yes.
  const [kept, setKept] = useState<Set<string>>(new Set());
  const wordKey = (text: string) => 'word:' + text;
  const [rwBusy, setRwBusy] = useState(false);
  const [rwMsg, setRwMsg] = useState('');
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<{ kind: 'ok' | 'err'; text: string; review?: boolean } | null>(null);

  // Nothing async writes state after the tab is gone (review, 15 Sep 2026): a recording stopped by
  // unmount fires onstop later, and a slow services_state can land after a tab switch.
  const mounted = useRef(true);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
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
      setRoles((cur) => reloadRoles(cur, (d.capability && d.capability.roles) || [], keep));
      // A refresh because the profile finished reading must not take away what the supplier has typed meanwhile.
      setRawText((cur) => reloadText(cur, d.raw_text || '', keep));
      // `dropped` starts empty on every load and is seeded from the preview instead: the server marks
      // an implication the supplier removed before as `removed: true`, so what was struck out survives
      // without this set having to hold keys the checklist may legitimately tick.
      if (!keep) { setRw(null); setDropped(new Set()); }   // the rewrite preview the supplier is reading stays on a refresh
      setSt({ loading: false, err: '', data: d });
    } else {
      setSt((s) => ({ ...s, loading: false, err: srvMsg(lang, j, sc(lang, 'load_failed')) }));
    }
  };
  // `lang` is deliberately not a dependency: it is read only for an error string, and re-running the
  // whole load on a language toggle would throw away the supplier's unsaved edits. A retry re-renders
  // the message in the current language.
  useEffect(() => { load(); }, [token]); // oxlint-disable-line react-hooks/exhaustive-deps

  // "THIS PAGE UPDATES BY ITSELF WHEN THE READ FINISHES" (VERIFY_COPY.profile_reading) was said and never done: this tab loaded once, so a
  // supplier who opened it while the profile was being read stayed on "still reading" until it left and came back. While a profile is
  // being read, ask again every 5 seconds (at most 10 minutes, as the Documents tab does); when it has finished, reload, keeping any text typed.
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
      // STEP A HAS READ (review round 2): the summary and his services in his own words are shown the moment they are stored, while the
      // names are matched; only that part of the state moves, so nothing he ticked or typed meanwhile is touched. Asks again in 5 seconds.
      else setSt((s) => (j && j.ok && s.data ? { ...s, data: { ...s.data, reading_progress: j.reading_progress ?? s.data.reading_progress } } : { ...s }));
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

  if (st.loading && !st.data) return <Card className="qd-panel p-5" aria-busy="true">{sc(lang, 'loading')}</Card>;
  if (!st.data) return (
    <Card className="qd-panel p-5">
      <h2 className={h3}>{sc(lang, 'load_failed')}</h2>
      {/* SP-I-01: `st.err` is the server's own English — a raw code, or a DB message on a 500. */}
      {st.err ? <p className={sub}>{panelErrorText(ar ? 'ar' : 'en', st.err)}</p> : null}
      <Button className="mt-3" onClick={() => load()}>{sc(lang, 'retry')}</Button>
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
  const docs = allDocs.filter((x) => (x.trades || []).length);
  // THE COMPANY PROFILE, SUMMARISED FOR THE SUPPLIER TO CONFIRM (founder ledger 1469, 2 Nov 2026). The list above shows only documents that
  // named a trade, so a profile that was read but named none looked unread. This says what happened to the profile, and when it did name
  // trades it shows the lines they were found on (the summary) and the trade names (the keywords). Words come from the stored reading; nothing is invented.
  const profileDocs = allDocs.filter((x) => x.kind === 'profile');
  const profileHits = profileDocs.flatMap((x) => x.trades || []);
  const profileKeywords = [...new Set(profileHits.map((h) => h.code))].map(tradeName);
  // English only to a supplier (ruling 1008): an Arabic line of the profile reads its trade, but the keyword beside it is the English name and
  // the Arabic quote is not repeated here; an Arabic-only profile shows its keywords alone.
  const profileLines = englishLines([...new Set(profileHits.map((h) => (h.snippet || '').trim()))]).slice(0, 3);
  // HIS OWN STATEMENTS, CERTAIN (review of branch 2): not through a partner, not only in his projects or brand list, not "please check".
  // Only these are ticked by "Tick all"; every other row is ticked by him alone.
  const otherRow = (p: ProposedSvc) => p.delivery === 'partner' || p.basis === 'shown' || p.basis === 'brand' || !!p.check;
  const proposedOwn = (d.proposed_services || []).filter((p) => !otherRow(p));
  const profileState = asksWhatHeDoes(d.reading, proposedOwn.length) ? 'unclear' : listedProfileState(profileStateOf(profileDocs), (d.proposed_services || []).length);
  // his statements no standard name covers (stated or through a partner); shown and brand phrases are asked in slice 4, never listed
  const readOwnWords = (d.reading?.own_words || []).filter((w) => w.basis === 'stated' || w.basis === 'partner');
  // the words above the services, true for this state: is a list of his trades on screen, and is his sign-up trade on it
  const said = servicesSentences(profileState, { list: trades.some((c) => !removedTrades.has(c)), signup: d.checklist.some((c) => c.source === 'signup' && !removedTrades.has(c.code)) });
  const noPrep = !d.confirmed && d.checklist.length === 0;
  // THE REWRITE CARRIES ITS OWN LABELS and they are read first. services_by_trade only holds the
  // trades the sales engineer PREPARED, so a service recognised from a trade the supplier does not
  // have on file — the ordinary case for anything it adds — had no label there and rendered as its
  // raw key ("interior fitout decoration"). Seen in the EN desktop screenshot, 18 Sep 2026.
  const rwLabels = new Map((rw?.items || []).flatMap((i) => (i.kind === 'service' ? [[i.key, i] as const] : [])));
  const labelOfKey = (key: string) => {
    const r = rwLabels.get(key);
    if (r) return ar ? r.label_ar : r.label_en;
    const s = (d.services_by_trade[key.split('.')[0]] || []).find((x) => x.key === key);
    return s ? svcName(s) : key.replace(/[._]/g, ' ');
  };

  const toggleKey = (k: string) => setTicked((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });
  // Removing marks the card; nothing is lost until Update, and Undo puts the ticks back as they were.
  const removeTrade = (code: string, on: boolean) => setRemovedTrades((s) => { const n = new Set(s); if (on) n.add(code); else n.delete(code); return n; });
  const toggleRole = (c: string) => setRoles((rs) => (rs.includes(c) ? rs.filter((x) => x !== c) : [...rs, c]));
  const toggleDrop = (k: string) => setDropped((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });
  const toggleKeep = (k: string) => setKept((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });
  const toggleProp = (k: string) => setPropTicked((s) => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });

  // THE REWRITE. Nothing is saved here — the supplier is shown what we made of its words and either
  // confirms it below or edits the text and asks again.
  // `supplyOnly` is the supplier's own answer to "supply only?" and overrides what the words suggested. His uploaded catalogue is
  // not read here any more: the model reads it with his other documents and its services are offered above (ruling 1627).
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
      setDropped((s) => new Set([...s, ...next.implied.filter((i) => i.removed).map((i) => i.key)]));
      if (!next.service_keys.length && !next.own_words.length && !(next.meaning?.proposals || []).length) {
        setRwMsg(next.model?.state === 'off' ? (ar ? next.model.message_ar || '' : next.model.message_en || '') : sc(lang, 'rewrite_none'));
      }
    } else setRwMsg(srvMsg(lang, j, sc(lang, 'rewrite_failed')));
  };

  // What the supplier has actually agreed to: the ticked checklist plus the rewrite's services, minus
  // anything struck out. The implied half is sent kept-and-removed separately, so the server stores
  // stated / implied / removed apart and matching can subtract a removal (fn_services_effective).
  const rwStated = (rw?.service_keys || []).filter((k) => !dropped.has(k) && ofActive(k));
  // Without a rewrite on screen the STORED implications are what the supplier has — sending [] here
  // wiped services_implied on every plain Update, and the count fell from 8 to 5 (finding 11).
  const rwImplied = (rw ? rw.implied.map((i) => i.key) : d.implied_services).filter((k) => !dropped.has(k) && ofActive(k));
  // THE SUPPLIER'S OWN WORDS ALREADY SAVED (finding 9). They are stored in `services` and come back as
  // extra_services; this tab used to ignore them, so they vanished on reload and the next Update —
  // which sent only the preview's words — deleted them. They are shown, kept, and re-sent.
  const savedOwn = d.extra_services || [];
  const rwOwnWords = [...savedOwn, ...(rw?.own_words || [])].concat(readOwnWords.map((w) => w.words).filter((w) => readWordsTicked.has(w)))
    .filter((w, i, all) => all.findIndex((x) => x.toLowerCase() === w.toLowerCase()) === i)
    .filter((w) => !dropped.has(wordKey(w)));
  // A key struck out in the preview is struck out even if the prepared checklist also ticks it —
  // otherwise "Remove" reads as done and the union puts the key straight back (React review, 18 Sep).
  // A service the meaning layer proposed is a service it STATED only once the supplier adds it
  // (22 Sep 2026, finding SP-F-06). It used to be ticked by default and struck out on objection —
  // so a reading the supplier never looked at decided, silently, which inquiries reached them. The
  // word rules and the curated implications keep their default, because those are the supplier's
  // own words and a rule the sales engineer wrote; a nearest-meaning reading is neither.
  const rwMeaning = (rw?.meaning?.proposals || []).map((p) => p.key).filter((k) => kept.has(k) && !dropped.has(k));
  const proposedSvcs = d.proposed_services || [];
  const propKeys = proposedSvcs.map((p) => p.key).filter((k) => propTicked.has(k));
  const statedKeys = [...new Set([...liveTicks, ...rwStated, ...rwMeaning, ...propKeys])].filter((k) => !dropped.has(k));
  // His own words for what he confirmed: the alias queue cites them (supplier_services.recordOwnPhrases).
  const phrases = [
    ...proposedSvcs.filter((p) => propTicked.has(p.key)).map((p) => ({ phrase: p.phrase, key: p.key })),
    ...(rw?.meaning?.proposals || []).filter((p) => kept.has(p.key) && !dropped.has(p.key)).map((p) => ({ phrase: p.lines[0] || '', key: p.key })),
  ];
  // Removals travel with the save so matching can subtract them: what was already stored, plus
  // whatever was struck out in this preview, minus anything now stated or kept.
  const rwRemoved = [...new Set([...(d.removed_services || []), ...(rw ? rw.implied.map((i) => i.key) : d.implied_services).filter((k) => dropped.has(k))])]
    .filter((k) => !rwImplied.includes(k) && !statedKeys.includes(k));

  const save = async () => {
    setBusy(true); setNote(null);
    const j = await call('supplier_api', {
      // A 'refine' trade (split from one he holds, offered unticked) is his only when he ticked a service
      // in it: it is never saved because it was shown (founder instructions 895/899/900).
      // A trade his DOCUMENTS proposed is his only when he ticked a service in it (review of branch 2; the server holds the same rule,
      // supplier_services.keepTickedProposed): a trade alone receives every request that names no service. A trade already his (confirmed,
      // or ON FILE from the directory listing: 14,744 unconfirmed suppliers have one) or chosen at sign-up is sent as before (review round 2).
      action: 'services_save_rewrite', trades: activeTrades.filter((c) => ['confirmed', 'on_file', 'signup'].includes(sourceOf(c) ?? '') || statedKeys.some((k) => k.startsWith(c + '.'))), removed_trades: [...removedTrades], roles,
      services: statedKeys, implied: rwImplied, removed: rwRemoved,
      own_words: rwOwnWords, raw_text: rawText.trim(), phrases,
    // The save reasons over each own word (~37 s measured, 27 Oct): see REASONING_TIMEOUT_MS in ./api.
    }, token, { timeoutMs: REASONING_TIMEOUT_MS }).catch(() => null);
    if (!mounted.current) return;
    setBusy(false);
    if (j && j.ok) {
      const review = (j.proposed_trades || []).length > 0 || (j.new_trades_under_review || []).length > 0;
      // The verification the confirm ran (or queued) is said, not left to a badge that does not refresh.
      const gate = String(j.gate || '');
      const after = gate === 'approved' ? ' ' + sc(lang, 'gate_approved') : gate === 'queued' || gate === 'failed' ? ' ' + sc(lang, 'gate_finishing') : '';
      setNote({ kind: 'ok', text: sc(lang, 'saved') + after, review });
      load();
    } else setNote({ kind: 'err', text: srvMsg(lang, j, sc(lang, 'save_failed')) });
  };

  // The preview lists only words not already saved above, so one phrase is never shown twice.
  const rwNewOwn = (rw?.own_words || []).filter((w) => !savedOwn.some((s) => s.toLowerCase() === w.toLowerCase()));
  const svcCount = countServices([...statedKeys, ...rwImplied], rwOwnWords);
  const canSave = roles.length > 0 && (statedKeys.length > 0 || rwOwnWords.length > 0 || activeTrades.length > 0);
  const voice = d.voice;
  const micNoteId = uid + '-mic';
  const micNote = !voice.enabled ? sc(lang, 'mic_soon') : !canRecord ? sc(lang, 'mic_unsupported') : voxBusy ? sc(lang, 'mic_busy') : voxMsg;

  return (
    // scroll-pb keeps a focused control clear of the sticky confirm bar (WCAG 2.4.11).
    <Card className={cn('qd-panel p-5', !d.confirmed && '[&_input]:scroll-mb-32 [&_button]:scroll-mb-32 [&_textarea]:scroll-mb-32')}>
      <h2 className="font-head text-[19px] font-semibold tracking-snug text-foreground">{sc(lang, 'title')}</h2>
      <p className={cn(sub, 'mt-1')}>{d.confirmed ? sc(lang, 'confirmed') : said.intro ?? sc(lang, 'first_run')}</p>

      {noPrep && (
        <div className="mt-4 rounded-md border border-dashed border-border bg-muted/30 p-4">
          {/* "upload your company profile" only when none is on file: a profile read, being read or held is not asked for again */}
          <p className={sub}>{profileDocs.length ? VERIFY_COPY_NO_LIST.no_prep_profile_on_file : sc(lang, 'no_prep')}</p>
          {goTo && !profileDocs.length ? <Button variant="outline" className="mt-3 min-h-11" onClick={() => goTo('documents')}>{sc(lang, 'go_documents')}</Button> : null}
        </div>
      )}

      {!d.confirmed && <p role="status" data-testid="verify-needed" className="mt-3 rounded-md border border-border bg-muted/30 p-3 text-[13px] text-foreground">{said.verify}</p>}

      <section className="mt-4" aria-labelledby={uid + '-profile'} data-testid="profile-summary">
        <h3 id={uid + '-profile'} className={cn(sub, 'font-semibold')}>{VERIFY_COPY.profile_summary_title}</h3>
        {profileState === 'hits' ? (
          <>
            <ul className="mt-1.5 space-y-1">
              {profileLines.map((line) => <li key={line} className="text-[12.5px] text-muted-foreground"><q dir="auto">{line}</q></li>)}
            </ul>
            <p className={cn(sub, 'mt-2 font-semibold')}>{VERIFY_COPY.profile_keywords}</p>
            <div className="mt-1 flex flex-wrap gap-1.5">
              {profileKeywords.map((k) => <Badge key={k} variant="secondary" dir="auto">{k}</Badge>)}
            </div>
          </>
        ) : profileState === 'reading' && d.reading_progress?.summary ? (
          // AS SOON AS STEP A HAS READ (review of branch 2, "not laggy"): what we understood, in his words, while the names are matched
          <div data-testid="reading-progress">
            <p className={cn(sub, 'mt-1')}>{d.reading_progress.summary}</p>
            <p className={cn(sub, 'mt-2 font-semibold')}>{PROPOSED_COPY.progress_title}</p>
            <ul className="mt-1 flex flex-wrap gap-1.5">{(d.reading_progress.claims || []).slice(0, 24).map((c) => <li key={c.words}><Badge variant="secondary" dir="auto">{c.words}</Badge></li>)}</ul>
            <p className={cn(sub, 'mt-2 flex items-start gap-2')} role="status">
              <Loader2 aria-hidden="true" className="mt-0.5 h-4 w-4 shrink-0 animate-spin motion-reduce:animate-none" />
              <span>{PROPOSED_COPY.progress_help}</span>
            </p>
          </div>
        ) : profileState === 'reading' ? (
          // a moving mark beside honest words, never a bare spinner: what is happening, how long, and that he can carry on
          <p className={cn(sub, 'mt-1 flex items-start gap-2')} role="status" data-testid="profile-reading">
            <Loader2 aria-hidden="true" className="mt-0.5 h-4 w-4 shrink-0 animate-spin motion-reduce:animate-none" />
            <span>{said.profile}</span>
          </p>
        ) : <p className={cn(sub, 'mt-1')}>{said.profile}</p>}
      </section>

      {/* THE SERVICES HIS OWN DOCUMENTS STATE (ledger 1573), each with the line it came from and whether his licence covers it.
          Offered, never pre-ticked (founder 862); one button ticks them all for him to review before Confirm. */}
      {(proposedSvcs.length > 0 || readOwnWords.length > 0) && (() => {
        // "Tick all" ticks his own statements only: a partner row is ticked one by one, by him (ruling 1647)
        const allProp = proposedOwn.length > 0 && proposedOwn.every((p) => propTicked.has(p.key));
        const lic = d.licence_check;
        return (
          <section className="mt-4 rounded-md border border-border p-3" aria-labelledby={uid + '-proposed'} data-testid="proposed-services">
            <h3 id={uid + '-proposed'} className={h3}>{PROPOSED_COPY.title}</h3>
            <p className={cn(sub, 'mt-0.5')}>{PROPOSED_COPY.help}</p>
            {lic && lic.read && lic.activities.length > 0 ? <p className={cn(sub, 'mt-1')}>{PROPOSED_COPY.licence_lists} <span dir="auto">{englishLines(lic.activities).join('; ') || lic.licence_trades.map(tradeName).join(', ')}</span></p>
              : lic && !lic.read ? <p className={cn(sub, 'mt-1')}>{PROPOSED_COPY.licence_unread}</p> : null}
            <ul className="mt-2 space-y-1">
              {proposedSvcs.map((p) => (
                <li key={p.key}>
                  <label className={row} htmlFor={uid + '-p-' + p.key}>
                    <input id={uid + '-p-' + p.key} type="checkbox" className={box} checked={propTicked.has(p.key)} onChange={() => toggleProp(p.key)} />
                    <span className="flex flex-col gap-0.5">
                      <span className="font-medium">{p.label_en}{p.delivery === 'partner' ? <Badge variant="secondary" className="ms-2">{PROPOSED_COPY.through_partner}</Badge> : null}
                        {p.basis === 'shown' ? <Badge variant="secondary" className="ms-2">{PROPOSED_COPY.from_projects}</Badge> : p.basis === 'brand' ? <Badge variant="secondary" className="ms-2">{PROPOSED_COPY.from_brands}</Badge> : null}
                        {p.check && !otherRow({ ...p, check: false }) ? <Badge variant="secondary" className="ms-2">{PROPOSED_COPY.please_check}</Badge> : null}
                        {p.licence === 'not_covered' ? <Badge variant="secondary" className="ms-2">{PROPOSED_COPY.not_on_licence}</Badge> : null}</span>
                      {p.delivery === 'partner' ? <span className="text-[12.5px] text-muted-foreground">{PROPOSED_COPY.through_partner_help}</span>
                        : p.basis === 'shown' || p.basis === 'brand' ? <span className="text-[12.5px] text-muted-foreground">{PROPOSED_COPY.from_projects_help}</span>
                        : p.check ? <span className="text-[12.5px] text-muted-foreground">{PROPOSED_COPY.please_check_help}</span> : null}
                      {isEnglishLine(p.snippet) ? <span className="text-[12.5px] text-muted-foreground">{PROPOSED_COPY.from_line} <q dir="auto">{p.snippet}</q></span> : null}
                      {p.licence === 'not_covered' ? <span className="text-[12.5px] text-muted-foreground">{PROPOSED_COPY.not_on_licence_help}</span> : null}
                    </span>
                  </label>
                </li>
              ))}
            </ul>
            {readOwnWords.length > 0 && (
              <>
                <h4 className={cn(sub, 'mt-3 font-semibold')}>{PROPOSED_COPY.own_words_title}</h4>
                <p className={cn(sub, 'mt-0.5')}>{PROPOSED_COPY.own_words_help}</p>
                <ul className="mt-1 space-y-1">
                  {readOwnWords.map((w) => (
                    <li key={w.words}>
                      <label className={row} htmlFor={uid + '-w-' + w.words}>
                        <input id={uid + '-w-' + w.words} type="checkbox" className={box} checked={readWordsTicked.has(w.words)}
                               onChange={() => setReadWordsTicked((s) => { const n = new Set(s); if (n.has(w.words)) n.delete(w.words); else n.add(w.words); return n; })} />
                        <span className="flex flex-col gap-0.5">
                          <span className="font-medium" dir="auto">{w.words}{w.basis === 'partner' ? <Badge variant="secondary" className="ms-2">{PROPOSED_COPY.through_partner}</Badge> : null}</span>
                          {isEnglishLine(w.quote) ? <span className="text-[12.5px] text-muted-foreground">{PROPOSED_COPY.from_line} <q dir="auto">{w.quote}</q></span> : null}
                        </span>
                      </label>
                    </li>
                  ))}
                </ul>
              </>
            )}
            {proposedOwn.length > 0 && (
            <Button type="button" variant="link" className="min-h-11 px-2" onClick={() => setPropTicked((cur) => { const n = new Set([...cur].filter((k) => !proposedOwn.some((p) => p.key === k))); if (!allProp) for (const p of proposedOwn) n.add(p.key); return n; })}>
              {allProp ? PROPOSED_COPY.untick_all : PROPOSED_COPY.tick_all}
            </Button>
            )}
          </section>
        );
      })()}

      {docs.length === 0 && allDocs.length > 0 && (
        <ul className="mt-2 space-y-1">
          {allDocs.map((doc) => <li key={doc.path} className="text-[12.5px] text-muted-foreground"><span className="font-medium text-foreground break-all" dir="auto">{doc.name}</span>{' — '}{docStateLine(doc)}</li>)}
        </ul>
      )}

      {docs.length > 0 && (
        <section className="mt-4" aria-labelledby={uid + '-docs'}>
          <h3 id={uid + '-docs'} className={cn(sub, 'font-semibold')}>{sc(lang, 'found_in')}</h3>
          <ul className="mt-1.5 space-y-1.5">
            {docs.map((doc) => (
              <li key={doc.path} className="text-[12.5px] text-muted-foreground">
                <span className="font-medium text-foreground break-all" dir="auto">{doc.name}</span>
                {' — '}{(doc.trades || []).map((h) => tradeName(h.code)).join(ar ? '، ' : ', ')}
                {/* English only (review of #1796): a line read off an Arabic picture is not repeated; the trade names beside it say it */}
                {doc.trades && doc.trades[0] && isEnglishLine(doc.trades[0].snippet) ? <q className="ms-1.5 opacity-80" dir="auto">{doc.trades[0].snippet}</q> : null}
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* THE SALES ENGINEER'S PREPARED CHECKLIST. His proposal about what we already hold — the one
          checkbox on this screen, and the supplier is correcting it, not adding to it.
          BROWSED, NOT TICKED BY THE TRADE (12 Nov 2026, ruling 1647): no "Select all" on a trade, and the list sits under
          "Browse all services of my trades", open by itself for a supplier editing what he already confirmed and whenever his documents
          proposed nothing to tick (review of 12 Nov 2026: closed, those suppliers' only boxes were hidden), with a chevron and a 48 px title.
          scripts/checks/a_supplier_is_asked_never_assumed.test.mjs. */}
      {trades.length > 0 && (
      <details className="group mt-4 rounded-md border border-border" open={browseOpen ?? (!!d.confirmed || proposedOwn.length === 0)} onToggle={(e) => setBrowseOpen(e.currentTarget.open)} data-testid="browse-trades">
        <summary className={cn(h3, 'flex min-h-12 cursor-pointer list-none items-center justify-between gap-3 px-3 py-2 hover:bg-muted/40 [&::-webkit-details-marker]:hidden')}>
          <span>{VERIFY_COPY.browse_trades}</span>
          <ChevronDown aria-hidden="true" className="h-5 w-5 shrink-0 text-muted-foreground transition-transform group-open:rotate-180" />
        </summary>
        <p className={cn(sub, 'px-3')}>{VERIFY_COPY.browse_trades_help}</p>
      <div className="flex flex-col gap-3 p-3">
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
                  : src === 'on_file' ? <Badge variant="secondary" className="ms-2">{sc(lang, 'on_file')}</Badge>
                  : src === 'signup' ? <Badge variant="secondary" className="ms-2">{VERIFY_COPY.signup_trade}</Badge>
                  : src === 'refine' ? <Badge variant="secondary" className="ms-2">{sc(lang, 'refine_badge')}</Badge>
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
                <Button type="button" variant="link" className="min-h-11 px-2 text-muted-foreground" onClick={() => removeTrade(code, true)}>
                  {sc(lang, 'remove_trade')}<span className="sr-only">: {tradeName(code)}</span>
                </Button>
              </div>
            </fieldset>
          );
        })}
      </div>
      </details>
      )}

      {/* ADDING: ONE TEXT BOX AND THE MIC. Instruction 438. */}
      <section className="mt-5" aria-labelledby={uid + '-describe'}>
        <h3 id={uid + '-describe'} className={h3}>{sc(lang, 'describe_title')}</h3>
        <p className={cn(sub, 'mt-0.5')} id={uid + '-describe-help'}>{sc(lang, 'describe_help')}</p>
        <form className="mt-2" onSubmit={(e) => { e.preventDefault(); rewrite(); }}>
          <label className="sr-only" htmlFor={uid + '-raw'}>{sc(lang, 'describe_label')}</label>
          <textarea id={uid + '-raw'} dir="auto" rows={5} maxLength={2000} value={rawText}
                    onChange={(e) => { setRawText(e.target.value); setRwMsg(''); }}
                    aria-describedby={uid + '-describe-help'} placeholder={sc(lang, 'describe_ph')}
                    className="w-full rounded-md border border-input bg-transparent px-3 py-2.5 text-sm leading-relaxed text-foreground placeholder:text-muted-foreground focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring" />
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <Button type="submit" className="min-h-11" disabled={rwBusy || rawText.trim().length < 2}>
              {rwBusy ? sc(lang, 'rewriting') : sc(lang, 'rewrite')}
            </Button>
            <Button type="button" variant="outline" className="min-h-11 min-w-11"
                    disabled={!voice.enabled || !canRecord || voxBusy}
                    aria-pressed={recording}
                    aria-describedby={micNote ? micNoteId : undefined}
                    onClick={() => (recording ? stopRec() : startRec(voice))}>
              <span aria-hidden>{recording ? '■' : '🎙'}</span>
              <span className="ms-1.5">{recording ? sc(lang, 'mic_stop') : sc(lang, 'mic_start')}</span>
            </Button>
          </div>
        </form>
        <p id={micNoteId} role="status" className={cn('mt-1.5 text-[12.5px] text-muted-foreground', !micNote && 'sr-only')}>{micNote}</p>
        {rwMsg ? <p role="alert" className="mt-1.5 text-[12.5px] text-warn-fg">{rwMsg}</p> : null}
      </section>

      {/* SAVED IN THE SUPPLIER'S OWN WORDS, UNDER REVIEW (finding 9). Stored, re-sent on every Update,
          and removable only by the supplier. */}
      {savedOwn.length > 0 && (
        <section className="mt-5" aria-labelledby={uid + '-saved-own'}>
          <h3 id={uid + '-saved-own'} className={h3}>{sc(lang, 'own_words_title')}</h3>
          <p className={cn(sub, 'mt-0.5')}>{sc(lang, 'own_words_help')}</p>
          <ul className="mt-1.5 flex flex-col gap-1.5">
            {savedOwn.map((wtext, i) => (
              <li key={i + ':' + wtext} className={cn(chip, dropped.has(wordKey(wtext)) && 'opacity-60')}>
                <span className="font-medium text-foreground" dir="auto">{wtext}</span>
                <Badge variant="secondary">{dropped.has(wordKey(wtext)) ? sc(lang, 'removed_badge') : sc(lang, 'under_review')}</Badge>
                <Button type="button" variant="link" className="ms-auto min-h-11 px-2" onClick={() => toggleDrop(wordKey(wtext))}>
                  {dropped.has(wordKey(wtext)) ? sc(lang, 'restore') : sc(lang, 'remove')}<span className="sr-only">: {wtext}</span>
                </Button>
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* THE SALES ENGINEER'S VERSION — shown before anything is saved. */}
      {rw && (rw.service_keys.length > 0 || rw.own_words.length > 0 || rw.implied.length > 0 || (rw.meaning?.proposals || []).length > 0) && (
        <section className="mt-5 rounded-md border border-border bg-muted/20 p-4" aria-labelledby={uid + '-rw'}>
          <h3 id={uid + '-rw'} className={h3}>{sc(lang, 'rewrite_title')}</h3>
          <p className={cn(sub, 'mt-0.5')}>{sc(lang, 'rewrite_help')}</p>

          {/* SUPPLY ONLY — proposed by the words, confirmed or corrected by the supplier. */}
          {rw.supply_only && (rw.supply_only.proposed || rw.supply_only.applied !== rw.supply_only.proposed) && (
            <div className="mt-3 flex flex-wrap items-center gap-2" role="status">
              <p className={cn(sub, 'min-w-0 flex-1')}>{sc(lang, rw.supply_only.applied ? 'supply_only_note' : 'supply_install_note')}</p>
              <Button type="button" variant="outline" className="min-h-11" disabled={rwBusy}
                      onClick={() => rewrite({ supplyOnly: !rw.supply_only!.applied })}>
                {sc(lang, rw.supply_only.applied ? 'we_also_install' : 'we_only_supply')}
              </Button>
            </div>
          )}

          {/* UNDERSTOOD, NOT WORD-MATCHED — with the line that supports each. */}
          {(rw.meaning?.proposals || []).length > 0 && (
            <div className="mt-3">
              <h4 className={cn(sub, 'font-semibold')}>{sc(lang, 'meaning_title')}</h4>
              <p className={cn(sub, 'mt-0.5')}>{sc(lang, 'meaning_help')}</p>
              <ul className="mt-1.5 flex flex-col gap-1.5">
                {rw.meaning!.proposals.map((p) => (
                  // OFF UNTIL THE SUPPLIER ADDS IT. Dimmed and offered, not ticked and withdrawable.
                  <li key={p.key} className={cn(chip, 'items-start', !kept.has(p.key) && 'opacity-60')}>
                    <div className="flex min-w-0 flex-col">
                      <span className="font-medium text-foreground" dir="auto">{ar ? p.label_ar : p.label_en}</span>
                      <span className="text-[12px] text-muted-foreground" dir="auto">{sc(lang, 'meaning_because')} “{p.lines[0]}”</span>
                    </div>
                    <Button type="button" variant="link" className="ms-auto min-h-11 px-2" onClick={() => toggleKeep(p.key)}>
                      {/* "Add", not "Add back": the proposal starts off and was never on the list. */}
                      {kept.has(p.key) ? sc(lang, 'remove') : sc(lang, 'add')}
                      <span className="sr-only">: {ar ? p.label_ar : p.label_en}</span>
                    </Button>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {rw.service_keys.length > 0 && (
            <div className="mt-3">
              <h4 className={cn(sub, 'font-semibold')}>{sc(lang, 'stated_title')}</h4>
              <ul className="mt-1.5 flex flex-col gap-1.5">
                {rw.service_keys.map((k) => (
                  <li key={k} className={cn(chip, dropped.has(k) && 'opacity-60')}>
                    <span className="font-medium text-foreground" dir="auto">{labelOfKey(k)}</span>
                    {dropped.has(k) ? <Badge variant="secondary">{sc(lang, 'removed_badge')}</Badge> : null}
                    <Button type="button" variant="link" className="ms-auto min-h-11 px-2" onClick={() => toggleDrop(k)}>
                      {dropped.has(k) ? sc(lang, 'restore') : sc(lang, 'remove')}<span className="sr-only">: {labelOfKey(k)}</span>
                    </Button>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {/* PRE-INCLUDED, WITH THE REASON. Instruction 439. */}
          {rw.implied.length > 0 && (
            <div className="mt-3">
              <h4 className={cn(sub, 'font-semibold')}>{sc(lang, 'implied_title')}</h4>
              <p className={cn(sub, 'mt-0.5')}>{sc(lang, 'implied_help')}</p>
              <ul className="mt-1.5 flex flex-col gap-1.5">
                {rw.implied.map((i) => (
                  <li key={i.key} className={cn(chip, 'items-start', dropped.has(i.key) && 'opacity-60')}>
                    <div className="flex min-w-0 flex-col">
                      <span className="font-medium text-foreground" dir="auto">{ar ? i.label_ar : i.label_en}</span>
                      <span className="text-[12px] text-muted-foreground" dir="auto">
                        {sc(lang, 'implied_because')} {ar ? i.because[0]?.ar : i.because[0]?.en}
                      </span>
                    </div>
                    {dropped.has(i.key) ? <Badge variant="secondary">{sc(lang, 'removed_badge')}</Badge> : null}
                    <Button type="button" variant="link" className="ms-auto min-h-11 px-2" onClick={() => toggleDrop(i.key)}>
                      {dropped.has(i.key) ? sc(lang, 'restore') : sc(lang, 'remove')}
                      <span className="sr-only">: {ar ? i.label_ar : i.label_en}</span>
                    </Button>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {/* WE NEVER DROP THESE AND NEVER GUESS THEM: the supplier's own words, straight to the sales
              engineer. The supplier may strike one out — that is its own correction, not ours. */}
          {rwNewOwn.length > 0 && (
            <div className="mt-3">
              <h4 className={cn(sub, 'font-semibold')}>{sc(lang, 'own_words_title')}</h4>
              <p className={cn(sub, 'mt-0.5')}>{sc(lang, 'own_words_help')}</p>
              <ul className="mt-1.5 flex flex-col gap-1.5">
                {rwNewOwn.map((wtext, i) => (
                  <li key={i + ':' + wtext} className={cn(chip, dropped.has(wordKey(wtext)) && 'opacity-60')}>
                    <span className="font-medium text-foreground" dir="auto">{wtext}</span>
                    {dropped.has(wordKey(wtext)) ? <Badge variant="secondary">{sc(lang, 'removed_badge')}</Badge> : null}
                    <Button type="button" variant="link" className="ms-auto min-h-11 px-2" onClick={() => toggleDrop(wordKey(wtext))}>
                      {dropped.has(wordKey(wtext)) ? sc(lang, 'restore') : sc(lang, 'remove')}<span className="sr-only">: {wtext}</span>
                    </Button>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </section>
      )}

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

      {!canSave && <p className="mt-4 text-[13px] text-warn-fg">{sc(lang, 'need_trade_role')}</p>}
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
