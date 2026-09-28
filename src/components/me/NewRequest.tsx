// @ts-nocheck
'use client';
// THE INTAKE COMPOSER — the one screen the product exists for.
//
// What the website audit found here on 14 Sep 2026, and what each part below answers:
//   * BLOCKS CONVERSION: inquiry_intake returns questions[] (and, from the intake rebuild,
//     next_question and readiness {filled,required}) but the portal rendered assistant_message only,
//     so under the model hold the customer read "A few details will help" and was never told which.
//     -> QuestionChips + ReadinessBar. Items may be strings or {key, text|question|label}.
//   * The intelligence the intake already returns was thrown away -> specialist badge (agent_name),
//     urgency tag, classifier_override as "I read this as X, not Y", and the BOQ as a table with
//     confidence, assumptions and missing information BEFORE Send.
//   * English only -> every string comes from portalText (EN + AR); the panel carries its own dir.
//   * Voice failed AFTER recording while the model routes were held (transcribe is a model call), so
//     PR #596 hid the mic behind llmAvailable. The founder then noticed the customer had no voice at
//     all -> speech.ts: the browser's own speech recognition types into the box (text only, no audio
//     leaves through us); the transcribe path stays behind the same hold flag, off. Drawings
//     and BOQs are NOT gated: since PR #591 they are read and anonymised server-side without a model,
//     so the old "drawing reading is paused" line was false and is gone (founder walk, 14 Sep 2026).
//   * A drawing could not reach suppliers under the hold, because drawing_redact verified nothing
//     -> RedactionEditor: the customer boxes what must be hidden, and customer_api forwards
//     manual_boxes (normalised 0..1 per page) to drawing_redact, which applies them without a model.
//   * pdf.js came from cdnjs at runtime -> pdfRaster.ts, bundled.
//   * The homepage draft handoff -> initialText is sent as the first message, once.
import { useEffect, useRef, useState } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { Paperclip, Mic, Square, SendHorizontal, Sparkles, AlertTriangle, Siren, UserRound, ChevronLeft, ChevronRight, Eraser, FileSpreadsheet } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { categoryLabel } from '@/lib/categoryLabel';
import { mergeAttachment } from '@/lib/requestAttachments';
import { supaClient } from '@/lib/supaClient';
import { specGuideText } from '@/lib/specGuide';
import { boqNote, confidenceWord } from '@/lib/boqNotes';
import { t, tf, errText, emirateName } from './portalText';
import { countPhrase } from '@/lib/countedNoun';
import { markupSvg } from './markup';
import { DEVICE_TYPES } from '../../../supabase/functions/drawing_boq/legend_vocabulary';
import { recognitionLangs, getRecognition, speechErrorKey } from './speech';

const DICT_NAME = { en: { en: 'English', ar: 'Arabic' }, ar: { en: 'الإنجليزية', ar: 'العربية' } };

const fileB64 = (f) => new Promise((res) => { const rd = new FileReader(); rd.onloadend = () => res(String(rd.result).split(',')[1] || ''); rd.readAsDataURL(f); });
async function fileToImages(file) {
  const b64 = await fileB64(file);
  // Photos (incl. HEIC and multi-page TIFF) become JPEG pages in this browser; ocrClient throws
  // HEIC_UNSUPPORTED where the browser cannot decode HEIC, which onFile tells the customer.
  if ((file.type && file.type.startsWith('image/')) || /\.(heic|heif|tiff?)$/i.test(file.name || '')) {
    const { toJpegPages } = await import('./ocrClient');
    const images = await toJpegPages(file);
    return { images, b64: (images[0] && images[0].data) || b64, mime: (images[0] && images[0].mime) || 'image/jpeg' };
  }
  if (file.type === 'application/pdf') {
    try {
      const { rasterisePdf } = await import('./pdfRaster');
      const raw = atob(b64); const arr = new Uint8Array(raw.length); for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
      return { images: await rasterisePdf(arr), b64, mime: 'application/pdf' };
    } catch (_e) { return { images: [], b64, mime: 'application/pdf' }; }
  }
  return { images: [], b64, mime: file.type || 'application/octet-stream' };
}
// The recorder's WAV encoder is shared with the supplier Services tab (15 Sep 2026).
import { blobToWavB64 } from '@/lib/wavEncode';

// ATTACH A BOQ (founder, 14 Sep 2026). A spreadsheet goes to analyze_boq (cells read with no model);
// a PDF BOQ is read like a drawing, from its text layer. BOQ_ERR maps the server's refusal to words.
// 14 Sep 2026 ("the sales agent need to be extremely capable of reading all types of document"): every
// document drawing_boq's 'document' mode reads goes to analyze_document; PDFs, photos and DWG keep the
// drawing path (redacted pages for suppliers).
const DOC_RE = /\.(xlsx|xlsm|xls|csv|ods|docx?|pptx|odt|odp|rtf|txt|eml|msg|xml|x8[1-6]|zip|dxf)$/i;
// Founder ruling 28 Sep 2026: a drawing is PDF or CAD (DWG/DXF) only. The server refuses the rest the same way
// (supabase/functions/_shared/drawing_format.ts); refused here first so nothing is uploaded.
const REFUSED_DRAWING_RE = /\.(rvt|rfa|rte|rft|ifc|ifczip|ifcxml|dgn|dgnlib|dwf|dwfx|skp|3dm|nwd|nwc|nwf|step|stp|pln)$/i;
const BOQ_ERR = { file_too_large: 'nr_boq_err_too_large', unsafe_file_content: 'nr_boq_err_macro', encrypted: 'nr_boq_err_encrypted', file_type_not_allowed: 'nr_boq_err_type', unsafe_file_type: 'nr_boq_err_type', drawing_format_not_accepted: 'nr_drawing_format' };

// A question may arrive as a sentence or as {key, text|question|label}; the chip needs text.
const qText = (q) => (q == null ? '' : typeof q === 'string' ? q : String(q.text || q.question || q.label || q.key || ''));
// readiness is {filled, required} from the rebuilt intake or a 0-100 number from the old one.
const readinessPct = (r) => {
  if (r && typeof r === 'object') { const req = Number(r.required); return req > 0 ? Math.round((Math.min(Number(r.filled) || 0, req) / req) * 100) : null; }
  const n = Number(r); return Number.isFinite(n) ? Math.max(0, Math.min(100, Math.round(n))) : null;
};

export function NewRequest({ token, lang, call, llmAvailable, initialText, pickFile, onDone, onCancel }) {
  const ar = lang === 'ar';
  const reduce = useReducedMotion();
  const [messages, setMessages] = useState([{ role: 'assistant', text: t(lang, 'nr_greeting') }]);
  const [input, setInput] = useState('');
  const [intakeId, setIntakeId] = useState(null);
  const [drawing, setDrawing] = useState(null); const drawingRef = useRef(null);
  const [marks, setMarks] = useState(null); // { image, width, height, matches } from the symbol counter
  const [pages, setPages] = useState(null); // { images, b64, mime, name } kept for the redaction editor
  const [editor, setEditor] = useState(false);
  const [thinking, setThinking] = useState(false);
  const [analyzing, setAnalyzing] = useState(false);
  const [schedPct, setSchedPct] = useState(null); // 0-100 while ocrSchedules reads a PDF's schedules
  const readingText = schedPct != null ? tf(lang, 'nr_reading_schedules', { pct: schedPct }) : t(lang, 'nr_reading');
  const [brief, setBrief] = useState(null);
  const [ready, setReady] = useState(false);
  const [meta, setMeta] = useState({}); // what the last intake turn said about itself
  const [combineMode, setCombineMode] = useState('multi');
  const [edits, setEdits] = useState({}); // requirement key -> label the customer tapped on the summary card
  const [posted, setPosted] = useState(null); // set when create_inquiry answered ok and reached no supplier
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');
  // The trade's published "how to specify" guide (scripts/sql/customer_spec_guide.sql); none -> nothing shown.
  const guideTrade = (brief && brief.category) || meta.category || '';
  const [guide, setGuide] = useState(null);
  useEffect(() => {
    let live = true;
    setGuide(null);
    if (!guideTrade) return;
    supaClient('qd-cust-auth').rpc('fn_customer_spec_guide', { p_trade: guideTrade }).maybeSingle()
      .then(({ data }) => { if (live) setGuide(data ? { ...data, status: 'published' } : null); }, () => {});
    return () => { live = false; };
  }, [guideTrade]);
  const guideText = specGuideText(guide, lang);
  const [rec, setRec] = useState(false); const [voxBusy, setVoxBusy] = useState(false); const recRef = useRef(null);
  const fileRef = useRef(null); const boqRef = useRef(null); const endRef = useRef(null); const inputRef = useRef(null); const sentDraft = useRef(false);
  const modelHeld = llmAvailable === false;
  // 'speech' = browser recognition; 'model' = the held transcribe path (only when the hold is lifted);
  // 'none' = the mic is shown with the phone-keyboard note. Decided after mount: SSR has no window.
  const [voice, setVoice] = useState(null);
  const [dict, setDict] = useState(ar ? 'ar' : 'en');
  useEffect(() => {
    const v = getRecognition() ? 'speech' : !modelHeld ? 'model' : 'none';
    setVoice(v);
    // The greeting mentions voice only where the mic actually works in this browser.
    if (v !== 'none') setMessages((a) => a.map((m, i) => (i === 0 && m.text === t(lang, 'nr_greeting') ? { ...m, text: m.text + t(lang, 'nr_greeting_voice') } : m)));
    return () => { try { recRef.current && recRef.current.sr && recRef.current.sr.abort(); } catch (_e) {} };
  }, [modelHeld]);
  const push = (m) => setMessages((a) => [...a, m]);
  useEffect(() => { try { endRef.current && endRef.current.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'end' }); } catch (_e) {} }, [messages, thinking, analyzing, ready, editor]);

  // drawingNow: the drawing just adopted, passed directly because setDrawing has not landed yet.
  const runIntake = async (message, drawingNow = null) => {
    setThinking(true); setMsg('');
    const dr = drawingNow || drawing;
    const r = await call('inquiry_intake', { intake_id: intakeId, text: message, drawing_boq: (dr && dr.boq) || null, lang }, token).catch(() => null);
    setThinking(false);
    if (!r || r.error) { push({ role: 'assistant', text: errText(r, lang, 'nr_err_generic') }); return; }
    if (r.intake_id) setIntakeId(r.intake_id);
    // remaining_questions (14 Sep 2026): every question still open, the category's and the sales
    // engineer's alike, so the customer sees exactly what is left instead of one question with no end.
    const questions = (Array.isArray(r.remaining_questions) && r.remaining_questions.length ? r.remaining_questions : (Array.isArray(r.questions) ? r.questions : [])).map(qText).filter(Boolean);
    const next = r.next_question ? qText(r.next_question) : '';
    // next_question.options, when the intake offers them, are complete answers: one tap sends one.
    const options = (r.next_question && Array.isArray(r.next_question.options) ? r.next_question.options : []).map(qText).filter(Boolean).slice(0, 8);
    setMeta({ agent_name: r.agent_name || null, urgency: r.urgency || null, override: r.classifier_override || null, readiness: readinessPct(r.readiness ?? r.readiness_score), category: r.category || null });
    // suggested is highlighted and labelled, never pre-selected: the customer still taps it to confirm.
    const suggested = r.next_question && r.next_question.suggested ? String(r.next_question.suggested) : null;
    push({ role: 'assistant', text: r.assistant_message || '', questions: next ? [next, ...questions.filter((q) => q !== next)] : questions, next, options, suggested, left: r.status === 'ready' ? 0 : questions.length });
    if (r.status === 'ready') { setBrief(r.brief || null); setReady(true); setEdits({}); } else setReady(false);
  };
  const sendText = async (text) => { const v = String(text || '').trim(); if (!v) return; push({ role: 'user', text: v }); setInput(''); await runIntake(v); };
  const send = () => sendText(input);
  // THE HOMEPAGE HANDOFF. The draft is sent as the first message exactly once; the parent deletes the
  // localStorage key before mounting this, so a reload cannot send it twice.
  // "Upload a drawing" (Quick actions) opens the composer WITH the picker open. It opened the
  // composer alone, which left the customer looking for the paperclip the button was named after.
  // Runs in the effect flush of that same click, so the browser still counts it as user-initiated.
  useEffect(() => { if (pickFile && fileRef.current) fileRef.current.click(); }, [pickFile]);
  useEffect(() => { if (initialText && !sentDraft.current) { sentDraft.current = true; push({ role: 'assistant', text: t(lang, 'nr_draft_picked') }); sendText(initialText); } }, [initialText]);
  const onKey = (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); } };
  const answerChip = (q) => { setInput(q + (ar ? ' — ' : ' — ')); setTimeout(() => { try { inputRef.current.focus(); } catch (_e) {} }, 20); };

  // ocr: plain text (a scan) or the drawing read {text, lines, width, symbols} from ocrDrawing.
  const analyze = async (p, manual_boxes, ocr) => {
    const hint = messages.filter((m) => m.role === 'user').map((m) => m.text).join(' ').slice(0, 400);
    const o = typeof ocr === 'string' ? { ocr_text: ocr } : ocr ? { ocr_text: ocr.text, ocr_lines: ocr.lines, ocr_width: ocr.width, ...(ocr.symbols ? { symbol_counts: { counts: ocr.symbols.counts } } : {}) } : {};
    const sched = p.schedule_tables && p.schedule_tables.length ? { schedule_tables: p.schedule_tables } : {};
    return call('customer_api', { action: 'analyze_drawing', images: p.images, original_b64: p.b64, mime: p.mime, drawing_file_name: p.name, hint, ...(manual_boxes ? { manual_boxes } : {}), ...(o.ocr_text || o.ocr_lines ? o : {}), ...sched }, token);
  };
  // SCHEDULES (21 Sep 2026, founder instruction 580). A PDF drawing set's schedules are read table by
  // table, cell by cell (ocrClient.ocrSchedules) and sent as schedule_tables with the drawing. Measured
  // on a desktop Chromium: 57 s for a real 8 + 5 sheet pair of 36x24 sets (13 tables, ~1,100 cells),
  // with a 35 MB page buffer and a 64 MB render tile. NOT run on a screen under 700 px wide: a phone's
  // CPU is several times slower and its tab is the first killed for memory, and a customer on a phone
  // still gets the drawing read by the server path. Any failure returns [] — the schedules are extra
  // evidence, never a reason the upload fails.
  const readSchedules = async (b64) => {
    if (typeof window === 'undefined' || window.innerWidth < 700) return [];
    try {
      const raw = atob(b64); const bytes = new Uint8Array(raw.length); for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
      const { ocrSchedules } = await import('./ocrClient');
      setSchedPct(0);
      const r = await ocrSchedules(bytes, { onProgress: (f) => setSchedPct(Math.min(99, Math.round(f * 100))) });
      return r.schedule_tables;
    } catch (_e) { return []; } finally { setSchedPct(null); }
  };
  // A DRAWING photo is read with the drawing plan (ocrPlan.ts) and its symbols counted, in the
  // browser. Falls back to the plain read on any failure, so a drawing never gets less than before.
  const ocrDraw = async (img) => { try { const { ocrDrawing } = await import('./ocrClient'); return await ocrDrawing(img, { lite: typeof window !== 'undefined' && window.innerWidth < 700 }); } catch (_e) { return null; } };
  // FREE OCR (14 Sep 2026). The vision model is held and an edge function has ~2 s of CPU, so a photo's
  // or a scan's words are read HERE, by tesseract.js in the customer's browser (ocrClient.ts). The text
  // is untrusted input: the server parses it, strips prices, and scrubs identity like any other text.
  const ocr = async (images) => { try { const { ocrImages } = await import('./ocrClient'); return (await ocrImages(images)).text || ''; } catch (_e) { return ''; } };
  // source 'boq' when the customer attached a BOQ (sheet or PDF): create_inquiry tells suppliers so.
  const adopt = (res, name, source = 'drawing') => {
    // A HELD DRAWING (audit 21 Sep 2026, finding 9). customer_api says drawing_held when not every page
    // came back verified; nothing of the drawing is then offered for suppliers (no paths, and
    // share_redacted:false, which create_inquiry honours), and the card above Send says so.
    const held = !!(res && res.drawing_file_path && res.drawing_held === true);
    const dr = { drawing_file_path: (res && res.drawing_file_path) || null, drawing_file_name: (res && res.drawing_file_name) || name, drawing_redacted_paths: held ? null : ((res && res.drawing_redacted_paths) || null), boq: (res && res.boq) || null, brief_source: source, ...(held ? { held: true, share_redacted: false } : {}) };
    // A second file ADDS to the request (walk of 22 Sep 2026: a drawing after a BOQ discarded the BOQ).
    // The ref, not the state, because an upload's handler outlives the render that started it.
    const merged = mergeAttachment(drawingRef.current, dr);
    drawingRef.current = merged;
    setDrawing(merged);
    return merged;
  };
  // The queued CAD read, polled every 15 s for up to 12 minutes (the worker is dispatched at once; a
  // GitHub runner starts in ~20-60 s and reads a multi-MB DWG in seconds). Not awaited: the chat stays usable.
  const pollCad = async (res, name, source, lengths = false) => {
    for (let i = 0; i < 48; i++) {
      await new Promise((r) => setTimeout(r, 15000));
      const s = await call('customer_api', { action: 'cad_read_status', job_id: res.cad_job_id }, token).catch(() => null);
      if (s && s.ok && s.status === 'done') {
        const n = s.boq && Array.isArray(s.boq.boq) ? s.boq.boq.length : 0;
        if (!n) { push({ role: 'assistant', text: t(lang, 'nr_cad_failed') }); return; }
        // A CAD file the edge could not open is drawn by the CAD worker too: its redacted page replaces the hold.
        const drawn = Array.isArray(s.drawing_redacted_paths) && s.drawing_redacted_paths.length ? { drawing_redacted_paths: s.drawing_redacted_paths, drawing_held: false } : {};
        const adopted = adopt({ ...res, boq: s.boq, ...drawn }, name, source);
        push({ role: 'assistant', text: lengths ? t(lang, 'nr_lengths_ready') : tf(lang, n === 1 ? 'nr_boq_read_one' : 'nr_boq_read_many', { n, c: countPhrase(lang, n, 'line', { oblique: true }), cat: s.boq.category ? ' (' + s.boq.category + ')' : '' }) + t(lang, 'nr_add_or_send') });
        await runIntake('', adopted);
        return;
      }
      if (s && s.ok && s.status === 'failed') { if (!lengths) push({ role: 'assistant', text: t(lang, 'nr_cad_failed') }); return; }
      if (s && !s.ok && s.error === 'not_found') return;
    }
    if (!lengths) push({ role: 'assistant', text: t(lang, 'nr_cad_slow') });
  };
  // A SCANNED DRAWING OR A PHOTO (24 Sep 2026): it has no text layer, so the edge holds it and customer_api queues
  // its pages for the CAD worker's OCR redaction (_shared/scan_redact.ts). When the worker proves a page clean,
  // its redacted page replaces the hold; when it cannot, the drawing simply stays held, as the card already says.
  const pollScan = async (res, name, source) => {
    for (let i = 0; i < 48; i++) {
      await new Promise((r) => setTimeout(r, 15000));
      const s = await call('customer_api', { action: 'cad_read_status', job_id: res.cad_job_id }, token).catch(() => null);
      if (s && s.ok && s.status === 'done') {
        const pages = Array.isArray(s.drawing_redacted_paths) ? s.drawing_redacted_paths : [];
        if (!pages.length) return;
        adopt({ ...res, drawing_redacted_paths: pages, drawing_held: false }, name, source);
        push({ role: 'assistant', text: tf(lang, 'nr_scan_pages_ready', { n: pages.length, c: countPhrase(lang, pages.length, 'page', { oblique: true }) }) });
        return;
      }
      if (s && s.ok && s.status === 'failed') return;
      if (s && !s.ok && s.error === 'not_found') return;
    }
  };
  const MAX_UPLOAD_BYTES = 20 * 1024 * 1024; // customer_api analyze_document refuses more
  // Returns true when it has already told the customer and cleared the pickers.
  const tooBig = (file) => {
    if (!file || file.size <= MAX_UPLOAD_BYTES) return false;
    push({ role: 'assistant', text: t(lang, 'nr_boq_err_too_large') });
    try { if (fileRef.current) fileRef.current.value = ''; if (boqRef.current) boqRef.current.value = ''; } catch (_e) {}
    return true;
  };
  const onFile = async (file, source = 'drawing') => {
    if (!file) return; setMsg('');
    if (REFUSED_DRAWING_RE.test(file.name)) return refuseDrawing();
    push({ role: 'user', text: '', chip: file.name });
    if (tooBig(file)) return;
    setAnalyzing(true); setEditor(false);
    try {
      const p = { ...(await fileToImages(file)), name: file.name, source };
      if (p.mime === 'application/pdf' && p.images.length) p.schedule_tables = await readSchedules(p.b64);
      setPages(p);
      const isPhoto = /^image\//.test(p.mime) && p.images.length > 0;
      const read = isPhoto && source === 'drawing' ? await ocrDraw(p.images[0]) : null;
      if (read && read.symbols && read.symbols.matches.length) setMarks({ image: p.images[0], width: read.width, height: read.height, matches: read.symbols.matches });
      let res = await analyze(p, undefined, read || (isPhoto ? await ocr(p.images) : ''));
      // A LARGE CAD DRAWING (22 Sep 2026): customer_api queued it for the CAD worker (it could not be read
      // inside the edge's caps). The customer is told, and the take-off is fetched when it is ready.
      if (res && res.note === 'cad_queued' && res.cad_job_id) {
        adopt(res, file.name, source);
        push({ role: 'assistant', text: t(lang, 'nr_cad_queued') });
        pollCad(res, file.name, source);
        setAnalyzing(false); try { if (fileRef.current) fileRef.current.value = ''; } catch (_e) {}
        return;
      }
      // A scanned PDF has pages but no text layer: OCR its rendered pages and read that text instead.
      if (!(res && res.boq && res.boq.boq && res.boq.boq.length) && p.mime === 'application/pdf' && p.images.length) {
        const text = await ocr(p.images);
        if (text.trim()) {
          const d = await call('customer_api', { action: 'analyze_document', file_b64: p.b64, mime: p.mime, file_name: p.name, ocr_text: text }, token).catch(() => null);
          if (d && d.ok && d.boq && d.boq.boq && d.boq.boq.length) res = { ...(res || {}), boq: d.boq };
        }
      }
      const adopted = adopt(res, file.name, source);
      const n = res && res.boq && res.boq.boq ? res.boq.boq.length : 0;
      // A line we did not READ (qty null, or our own count to confirm) is never waved through: the
      // sales engineer shows our count and asks (inquiry_intake, _shared/boq_open_lines.ts).
      const open = n ? res.boq.boq.some((l) => l && (l.qty == null || l.qty_status === 'to_confirm' || l.qty_status === 'estimated')) : false;
      // TELL THE TRUTH ABOUT THE DRAWING. A drawing that is not fully redacted is NOT sent to
      // suppliers (customer_api drops the paths, create_inquiry refuses unrecorded ones), so this
      // never says "attached" unless redaction_complete says every page came back.
      // A partial run shares nothing either (customer_api drawing_hold): held is all-or-nothing.
      const pagesIn = Number((res && res.redaction_pages_in) || 0);
      const attached = pagesIn > 0 && res.redaction_complete === true;
      const partial = pagesIn > 0 && !attached;
      let text;
      if (n >= 1) {
        const cat = res.boq.category ? ' (' + res.boq.category + ')' : '';
        text = tf(lang, n === 1 ? 'nr_boq_read_one' : 'nr_boq_read_many', { n, c: countPhrase(lang, n, 'line', { oblique: true }), cat })
          + (partial ? t(lang, 'nr_partial_none') : '')
          + t(lang, 'nr_add_or_send');
      } else if (res && res.advice && !p.images.length) {
        text = res.advice; // customer_api names the real reason (CAD not converted, archive, unreadable)
      } else if (attached) {
        text = tf(lang, 'nr_pages_ready', { n: pagesIn, c: countPhrase(lang, pagesIn, 'page', { oblique: true }) });
      } else {
        text = t(lang, 'nr_not_prepared');
      }
      push({ role: 'assistant', text });
      // drawing_redact's contract (intake engine, 14 Sep): needs_manual_boxes is the one signal that
      // automatic detection could not run, so the editor opens on exactly that and nothing else.
      if (res && res.needs_manual_boxes === true && p.images.length) setEditor(true);
      // SEND IS THE INTAKE'S WORD (walk of 22 Sep 2026: Send was offered after a BOQ and answered 428
      // intake_required). A read BOQ goes to inquiry_intake, which asks what is still open and says
      // ready itself; the button appears only then (runIntake is the one place that sets ready).
      if (n >= 1) await runIntake('', adopted);
      // A big PDF set's lengths are measured by the CAD worker; the take-off above updates when they arrive.
      if (res && res.note === 'lengths_queued' && res.cad_job_id) pollCad(res, file.name, source, true);
      if (res && res.note === 'scan_queued' && res.cad_job_id) pollScan(res, file.name, source);
    } catch (e) { push({ role: 'assistant', text: t(lang, String(e && e.message).includes('HEIC') ? 'nr_heic_unsupported' : 'nr_file_unreadable') }); }
    setAnalyzing(false); try { if (fileRef.current) fileRef.current.value = ''; } catch (_e) {}
  };
  // The parsed BOQ lands in `drawing.boq` exactly as a drawing's does, so inquiry_intake receives it as
  // drawing_boq and create_inquiry stores it on the RFQ suppliers read.
  const onBoq = async (file) => {
    if (!file) return;
    if (REFUSED_DRAWING_RE.test(file.name)) return refuseDrawing();
    if (!DOC_RE.test(file.name)) return onFile(file, 'boq');
    setMsg(''); push({ role: 'user', text: '', chip: file.name });
    const reset = () => { try { if (boqRef.current) boqRef.current.value = ''; if (fileRef.current) fileRef.current.value = ''; } catch (_e) {} };
    if (tooBig(file)) { reset(); return; }
    setAnalyzing(true);
    try {
      const hint = messages.filter((m) => m.role === 'user').map((m) => m.text).join(' ').slice(0, 400);
      const res = await call('customer_api', { action: 'analyze_document', file_b64: await fileB64(file), mime: file.type || '', file_name: file.name, hint }, token).catch(() => null);
      const rows = (res && res.ok && res.boq && res.boq.boq) || [];
      if (!res || !res.ok) push({ role: 'assistant', text: t(lang, BOQ_ERR[res && res.error] || 'nr_boq_err_generic') });
      else if (res.note === 'cad_queued' && res.cad_job_id) { adopt(res, file.name, 'drawing'); push({ role: 'assistant', text: t(lang, 'nr_cad_queued') }); pollCad(res, file.name, 'drawing'); }
      // A read that says what it needs (a photo's OCR, a DWG past the edge ceiling): the reader's own
      // notes, shown in the customer's language through boqNotes.
      else if (!rows.length && res.needs && res.boq && Array.isArray(res.boq.missing_info) && res.boq.missing_info.length) {
        adopt(res, file.name, 'drawing');
        push({ role: 'assistant', text: res.boq.missing_info.map((s) => boqNote(s, lang)).join(' ') });
      }
      else if (!rows.length) push({ role: 'assistant', text: t(lang, 'nr_boq_sheet_empty') });
      else {
        const adopted = adopt(res, file.name, 'boq');
        push({ role: 'assistant', text: tf(lang, rows.length === 1 ? 'nr_boq_sheet_one' : 'nr_boq_sheet_many', { n: rows.length, c: countPhrase(lang, rows.length, 'line', { oblique: true }) }) + t(lang, 'nr_add_or_send') });
        await runIntake('', adopted);
      }
    } catch (_e) { push({ role: 'assistant', text: t(lang, 'nr_boq_err_generic') }); }
    setAnalyzing(false); reset();
  };
  const onAny = (f) => (f && REFUSED_DRAWING_RE.test(f.name) ? refuseDrawing() : f && DOC_RE.test(f.name) ? onBoq(f) : onFile(f));
  const refuseDrawing = () => { push({ role: 'assistant', text: t(lang, 'nr_drawing_format') }); try { if (fileRef.current) fileRef.current.value = ''; if (boqRef.current) boqRef.current.value = ''; } catch (_e) {} };
  const applyBoxes = async (boxes) => {
    if (!pages) return false;
    const res = await analyze(pages, boxes).catch(() => null);
    const ok = !!(res && res.redaction_complete === true && Number(res.redaction_pages_in) > 0);
    const dr = adopt(res, pages.name, pages.source);
    push({ role: 'assistant', text: ok ? tf(lang, 'rd_done', { c: countPhrase(lang, ((res && res.drawing_redacted_paths) || []).length || Number(res.redaction_pages_out), 'page') }) : t(lang, 'rd_failed') });
    if (ok) setEditor(false);
    if (res && res.boq && res.boq.boq && res.boq.boq.length && !ready) await runIntake('', dr);
    return ok;
  };

  // BROWSER DICTATION. Live text lands in the box after what was already typed; the customer edits it
  // and presses Send, and it goes through inquiry_intake's identity scrubbing exactly as typed text does.
  // Nothing is sent automatically and no audio is kept: the engine hands back words, not a recording.
  const startSpeech = (langs = recognitionLangs(dict)) => {
    const SR = getRecognition(); if (!SR) return;
    const sr = new SR(); sr.lang = langs[0]; sr.interimResults = true; sr.continuous = true; sr.maxAlternatives = 1;
    const base = input ? input.replace(/\s*$/, ' ') : '';
    recRef.current = { sr, retried: false };
    sr.onresult = (e) => {
      let said = '';
      for (let i = 0; i < e.results.length; i++) said += e.results[i][0].transcript;
      setInput(base + said.replace(/^\s+/, ''));
    };
    sr.onerror = (e) => {
      const k = speechErrorKey(e && e.error);
      if (k === null && langs.length > 1) { recRef.current.retried = true; return; }
      if (k !== '') setMsg(t(lang, k || 'nr_voice_failed'));
    };
    sr.onend = () => {
      if (recRef.current && recRef.current.sr === sr && recRef.current.retried) { startSpeech(langs.slice(1)); return; }
      setRec(false); try { inputRef.current && inputRef.current.focus(); } catch (_e) {}
    };
    try { sr.start(); setRec(true); setMsg(''); } catch (_e) { setMsg(t(lang, 'nr_voice_failed')); }
  };
  const onMic = () => {
    if (rec) return stopRec();
    if (voice === 'speech') return startSpeech();
    if (voice === 'model') return startRec(); // the held transcribe path; unreachable while the hold lasts
    setMsg(t(lang, 'nr_voice_unsupported'));
  };
  const startRec = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true }); const mr = new MediaRecorder(stream); recRef.current = { mr, chunks: [], stream };
      mr.ondataavailable = (e) => { if (e.data && e.data.size) recRef.current.chunks.push(e.data); };
      mr.onstop = async () => {
        setVoxBusy(true);
        try {
          const blob = new Blob(recRef.current.chunks, { type: (recRef.current.chunks[0] && recRef.current.chunks[0].type) || 'audio/webm' });
          const j = await call('transcribe', { audio_b64: await blobToWavB64(blob), mime: 'audio/wav' }, token);
          if (j && j.ok && j.text) setInput((tx) => (tx ? tx + ' ' : '') + j.text); else setMsg(t(lang, 'nr_transcribe_fail'));
        } catch (_e) { setMsg(t(lang, 'nr_rec_fail')); }
        setVoxBusy(false); try { recRef.current.stream.getTracks().forEach((tr) => tr.stop()); } catch (_e) {}
      };
      mr.start(); setRec(true);
    } catch (_e) { setMsg(t(lang, 'nr_mic_denied')); }
  };
  const stopRec = () => { const r = recRef.current; try { if (r && r.sr) r.sr.stop(); else if (r && r.mr) r.mr.stop(); } catch (_e) {} setRec(false); };

  const submit = async () => {
    setBusy(true); setMsg('');
    const category = (brief && brief.category) || (drawing && drawing.boq && drawing.boq.category) || '';
    const firstUser = messages.find((m) => m.role === 'user' && m.text);
    const summary = (brief && brief.summary) || (firstUser ? firstUser.text.slice(0, 180) : category);
    const r = await call('customer_api', { action: 'create_inquiry', intake_id: intakeId || null, category: category || null, emirate: (brief && brief.emirate) || null, raw_input: messages.filter((m) => m.role === 'user' && m.text).map((m) => m.text).join('\n'), spec: { plausibility: (brief && brief.plausibility) || null, provenance: (brief && brief.provenance) || null }, summary, budget: (brief && brief.budget) || null, scope_type: (brief && Array.isArray(brief.trades) && brief.trades.length > 1) ? combineMode : 'single', trades: (brief && Array.isArray(brief.trades)) ? brief.trades : [], drawing, requirement_edits: edits }, token).catch(() => null);
    setBusy(false);
    // THE HONEST AFTER-POST (14 Sep 2026). A request no registered supplier covers is still posted and
    // flagged to the team (customer_api flagCoverageGap), but the composer used to close with nothing
    // said. The customer is now told, in their language, that quotes may take longer and why.
    if (r && r.ok) {
      // One answer shape (customer_api, _shared/inquiry_posted.ts): matches is already summed over a
      // split's children, and inquiry_id is the request the customer made (the combined parent).
      const reached = Number(r.matches) || 0;
      if (reached > 0) onDone(r); else setPosted({ none: true, id: r.inquiry_id || null });
    }
    // Never a dead end: when the server says something is still open, the next question is fetched at
    // once instead of leaving the customer to guess what "more details" means.
    else if (r && (r.error === 'intake_required' || r.error === 'requirements_incomplete')) { setReady(false); push({ role: 'assistant', text: t(lang, 'nr_more_details') }); await runIntake(''); }
    else if (r && r.error === 'requirements_invalid') setMsg(t(lang, 'nr_req_invalid'));
    // All or nothing (customer_api, _shared/inquiry_split.ts): the customer is told exactly which trades
    // could not go out, and that nothing was sent, so pressing Send again is safe.
    else if (r && r.error === 'split_failed') setMsg(tf(lang, 'nr_split_failed', { list: (Array.isArray(r.failed_trades) ? r.failed_trades : []).map((c) => categoryLabel(c, lang)).join(ar ? '، ' : ', ') }));
    else setMsg(errText(r, lang, 'nr_could_not_send'));
  };

  const trades = (brief && Array.isArray(brief.trades)) ? brief.trades : [];
  const boq = drawing && drawing.boq;
  const lastAssistant = [...messages].reverse().find((m) => m.role === 'assistant');
  const urgencyIcon = meta.urgency === 'emergency' ? Siren : AlertTriangle;
  if (posted) return (
    <section dir={ar ? 'rtl' : 'ltr'} className="qd-panel mb-3.5 p-5 shadow-e2" aria-live="polite">
      <h2 className="font-head text-[17px] font-semibold tracking-snug text-foreground">{t(lang, 'nr_posted')}</h2>
      <p className="mt-2 text-copy leading-relaxed text-foreground">{t(lang, 'nr_posted_none')}</p>
      <Button size="lg" className="mt-4" onClick={onDone}>{t(lang, 'nr_posted_view')}</Button>
    </section>
  );
  return (
    <section dir={ar ? 'rtl' : 'ltr'} className="qd-panel qd-grain mb-3.5 flex flex-col overflow-hidden shadow-e2" style={{ height: 'min(78vh, 720px)' }} aria-label={t(lang, 'nr_title')}>
      {/* The command-surface status bar: window dots, the surface's name, and what it is doing now. */}
      <div className="flex h-10 shrink-0 items-center gap-2.5 border-b border-border bg-secondary/40 px-4">
        <span className="flex gap-1.5" aria-hidden><i className="h-2 w-2 rounded-full bg-primary/25" /><i className="h-2 w-2 rounded-full bg-primary/25" /><i className="h-2 w-2 rounded-full bg-primary/25" /></span>
        <span className="min-w-0 truncate font-mono text-label uppercase tracking-caps text-muted-foreground">{t(lang, 'nr_kicker')}</span>
        <span className="ms-auto flex shrink-0 items-center gap-1.5 font-mono text-label text-primary" aria-hidden>
          <span className={cn('h-1.5 w-1.5 rounded-full bg-primary', (thinking || analyzing) && 'motion-safe:animate-pulse')} />
          {thinking || analyzing ? (analyzing ? readingText : t(lang, 'nr_typing')) : meta.readiness != null ? <span className="tabular">{meta.readiness}%</span> : null}
        </span>
      </div>
      <div className="flex items-center justify-between gap-2.5 border-b border-border px-5 py-3">
        <div className="flex min-w-0 flex-wrap items-center gap-2">
          <h2 className="font-head text-[17px] font-semibold tracking-snug text-foreground">{t(lang, 'nr_title')}</h2>
          {meta.agent_name ? <span className="inline-flex items-center gap-1 rounded-full border border-primary/35 bg-primary/10 px-2 py-0.5 text-[11px] font-semibold text-primary"><UserRound className="h-3 w-3" aria-hidden />{tf(lang, 'nr_handled_by', { name: meta.agent_name })}</span> : null}
          {meta.urgency && meta.urgency !== 'normal' ? <span className={cn('inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-semibold', meta.urgency === 'emergency' ? 'border-danger/40 bg-danger/10 text-danger-fg' : 'border-warn/40 bg-warn/10 text-warn-fg')}>{(() => { const I = urgencyIcon; return <I className="h-3 w-3" aria-hidden />; })()}{t(lang, 'nr_urgency_' + meta.urgency)}</span> : null}
        </div>
        <Button variant="link" className="h-auto px-0" onClick={onCancel}>{t(lang, 'nr_cancel')}</Button>
      </div>
      {meta.readiness != null && <ReadinessBar pct={meta.readiness} lang={lang} reduce={reduce} />}
      {guideText ? (
        <details className="mx-4 mt-2 rounded-xl border border-border bg-muted/40 px-3 py-2 text-[12.5px]" data-testid="spec-guide">
          <summary className="cursor-pointer font-semibold text-foreground">{t(lang, 'nr_spec_guide')}</summary>
          <div className="mt-1.5 whitespace-pre-line text-muted-foreground">{guideText}</div>
        </details>
      ) : null}

      <div className="flex-1 space-y-2.5 overflow-y-auto px-4 py-3" aria-live="polite">
        {messages.map((m, i) => (
          <motion.div key={i} initial={reduce ? false : { opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: reduce ? 0 : 0.22 }}>
            {m.chip !== undefined
              ? <div className="flex justify-end"><div className="flex items-center gap-1.5 rounded-2xl border border-primary/30 bg-primary/15 px-3 py-2 text-[13px] text-foreground"><Paperclip className="h-3.5 w-3.5" aria-hidden /><bdi>{m.chip}</bdi></div></div>
              : <div className={cn('flex', m.role === 'user' ? 'justify-end' : 'justify-start')}>
                  <div className={cn('max-w-[85%] whitespace-pre-wrap rounded-card px-3.5 py-2.5 text-copy leading-relaxed', m.role === 'user' ? 'bg-primary text-primary-foreground shadow-e1' : 'border border-border bg-secondary/40 text-foreground')}>{m.text}</div>
                </div>}
            {m === lastAssistant && Array.isArray(m.questions) && m.questions.length > 0 && (
              <QuestionChips questions={m.questions} next={m.next} left={m.left} lang={lang} onPick={answerChip} reduce={reduce} />
            )}
            {m === lastAssistant && Array.isArray(m.options) && m.options.length > 0 && !thinking && (
              <div className="mt-1.5 flex flex-wrap gap-1.5 ps-1" role="group" aria-label={m.next || t(lang, 'nr_chips_hint')}>
                {m.options.map((o) => (
                  <button key={o} type="button" onClick={() => sendText(o)} className={cn('rounded-full border px-3 py-1.5 text-[12.5px] font-semibold text-primary hover:bg-primary/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring', o === m.suggested ? 'border-primary bg-primary/20 ring-1 ring-primary/40' : 'border-primary/45 bg-primary/10')}>{o}{o === m.suggested ? <span className="ms-1.5 text-[10.5px] font-normal uppercase tracking-wide opacity-80">{t(lang, 'nr_suggested')}</span> : null}</button>
                ))}
              </div>
            )}
          </motion.div>
        ))}
        {meta.override && meta.override.kept && meta.override.model ? (
          <div className="flex justify-start"><button type="button" onClick={() => answerChip(tf(lang, 'nr_override', { kept: meta.override.kept, model: meta.override.model }).split(' — ')[0])}
            className="rounded-xl border border-warn/35 bg-warn/10 px-3 py-2 text-start text-[12.5px] text-warn-fg hover:border-warn/60">
            {tf(lang, 'nr_override', { kept: String(meta.override.kept).replace(/[-_]/g, ' '), model: String(meta.override.model).replace(/[-_]/g, ' ') })}
          </button></div>
        ) : null}
        {(thinking || analyzing) && (
          <div className="flex justify-start"><div className="flex items-center gap-2 rounded-2xl border border-border bg-secondary/60 px-3.5 py-2 text-[13px] text-muted-foreground">
            <span className="redact redact-bar" style={{ width: 54 }} aria-hidden />{analyzing ? readingText : t(lang, 'nr_typing')}
          </div></div>
        )}
        {editor && pages && pages.images.length > 0 && (
          <RedactionEditor lang={lang} images={pages.images} onApply={applyBoxes} onSkip={() => setEditor(false)} reduce={reduce} />
        )}
        {boq && Array.isArray(boq.boq) && boq.boq.length > 0 && <BoqTable boq={boq} lang={lang} />}
        {marks && marks.matches.length > 0 && (
          <figure className="rounded-card border border-border bg-background p-2">
            <div className="relative w-full overflow-hidden">
              <img src={`data:${marks.image.mime};base64,${marks.image.data}`} alt={t(lang, 'nr_markup_caption')} className="block h-auto w-full" />
              {/* markupSvg emits only numbers, shapes and escaped device labels. */}
              <div className="pointer-events-none absolute inset-0" aria-hidden
                dangerouslySetInnerHTML={{ __html: markupSvg(marks.width, marks.height, marks.matches, Object.fromEntries(DEVICE_TYPES.map((d) => [d.type, ar ? d.ar : d.en]))).replace('<svg ', '<svg style="width:100%;height:100%" ') }} />
            </div>
            <figcaption className="mt-1.5 text-[12px] text-muted-foreground">{t(lang, 'nr_markup_caption')}</figcaption>
          </figure>
        )}
        <AnimatePresence>
          {ready && brief && (
            <motion.div initial={reduce ? false : { opacity: 0, y: 10, scale: 0.99 }} animate={{ opacity: 1, y: 0, scale: 1 }} exit={{ opacity: 0 }} transition={{ duration: reduce ? 0 : 0.28, ease: [0.2, 0.8, 0.2, 1] }}
              className="rounded-2xl border border-primary/35 bg-primary/[0.06] p-4 shadow-[0_18px_50px_-30px_rgba(20,184,166,.55)]">
              <div className="flex items-center gap-2"><Sparkles className="h-4 w-4 text-primary" aria-hidden /><div className="text-[13.5px] font-bold text-foreground">{brief.category ? categoryLabel(brief.category, lang) : t(lang, 'rc_request')}{brief.emirate ? ' — ' + emirateName(brief.emirate, lang) : ''}</div></div>
              {brief.summary ? <div className="mt-1 text-[13px] text-muted-foreground">{brief.summary}</div> : null}
              <dl className="mt-2 grid grid-cols-1 gap-x-4 gap-y-1 text-[12.5px] sm:grid-cols-2">
                {brief.scope ? <Fact k={t(lang, 'nr_scope')} v={brief.scope} /> : null}
                {brief.quantity ? <Fact k={t(lang, 'nr_quantity')} v={<>{brief.quantity}{brief.provenance && brief.provenance.quantity === 'inferred' ? <span className="text-muted-foreground"> {t(lang, 'nr_qty_inferred')}</span> : null}</>} /> : null}
                {brief.timeline ? <Fact k={t(lang, 'nr_timeline')} v={brief.timeline} /> : null}
                {brief.budget ? <Fact k={t(lang, 'nr_budget')} v={brief.budget} /> : null}
              </dl>
              {Array.isArray(brief.requirement_questions) && brief.requirement_questions.length ? <RequirementsCard items={brief.requirement_questions} edits={edits} onEdit={(k, v) => setEdits((e) => ({ ...e, [k]: v }))} lang={lang} /> : null}
              {Array.isArray(brief.required_documents) && brief.required_documents.length ? (
                <div className="mt-2.5">
                  <div className="text-[12.5px] font-semibold text-foreground">{t(lang, 'nr_req_docs')}</div>
                  <ul className="mt-0.5 space-y-0.5">{brief.required_documents.map((d, i) => <li key={i} className="text-[12.5px] text-muted-foreground">✓ {d.item}{d.authority ? <span className="text-muted-foreground/80"> — {d.authority}</span> : null}</li>)}</ul>
                </div>
              ) : null}
              {brief.supplier_count != null ? (
                <div className={cn('mt-2.5 text-[12.5px] font-semibold', Number(brief.supplier_count) > 0 ? 'text-foreground' : 'text-muted-foreground')}>
                  {Number(brief.supplier_count) > 0 ? (Number(brief.supplier_count) === 1 ? t(lang, 'nr_sup_one') : tf(lang, 'nr_sup_many', { n: brief.supplier_count })) : t(lang, 'nr_sup_zero')}
                </div>
              ) : null}
              {trades.length > 1 ? (
                <fieldset className="mt-3 rounded-xl border border-primary/30 bg-primary/5 p-3">
                  <legend className="px-1 text-[12.5px] font-semibold text-primary">{tf(lang, 'nr_multi_h', { list: trades.join(ar ? '، ' : ', ') })}</legend>
                  <div className="mb-2 text-[12.5px] text-muted-foreground">{t(lang, 'nr_multi_q')}</div>
                  {[['multi', 'nr_multi_sep_h', 'nr_multi_sep_b'], ['turnkey', 'nr_multi_tk_h', 'nr_multi_tk_b']].map(([v, h, b]) => (
                    <label key={v} className="flex cursor-pointer items-start gap-2 rounded-md p-2 hover:bg-secondary/50">
                      <input type="radio" name="combine" className="mt-1" checked={combineMode === v} onChange={() => setCombineMode(v)} />
                      <span className="text-[12.5px] text-muted-foreground"><span className="font-semibold text-foreground">{t(lang, h)}</span> — {t(lang, b)}</span>
                    </label>
                  ))}
                </fieldset>
              ) : null}
              {brief.plausibility && brief.plausibility.note ? <div className="mt-2 text-[12.5px] text-warn-fg">{t(lang, 'nr_note')} {brief.plausibility.note}</div> : null}
              {drawing && drawing.held ? <div className="mt-2 text-[12.5px] font-semibold text-warn-fg" role="status">{tf(lang, drawing.boq && Array.isArray(drawing.boq.boq) && drawing.boq.boq.length ? 'nr_drawing_held_boq' : 'nr_drawing_held', { name: drawing.held_name || drawing.drawing_file_name || '' })}</div> : null}
              <Button size="lg" className="mt-3.5 w-full" disabled={busy} onClick={submit}>{busy ? t(lang, 'nr_sending') : t(lang, 'nr_send_suppliers')}</Button>
              <div className="mt-1.5 text-center text-[12px] text-muted-foreground">{t(lang, 'nr_keep_typing')}</div>
            </motion.div>
          )}
        </AnimatePresence>
        <div ref={endRef} />
      </div>

      <div className="shrink-0 border-t border-border bg-secondary/20 px-3 py-3 sm:px-4">
        {!drawing ? <div className="mb-1.5 text-[11.5px] text-muted-foreground">{t(lang, 'nr_attach_privacy')}</div> : null}
        {msg && <div className="mb-1.5 text-[12.5px] text-danger-fg" role="alert">{msg}</div>}
        {rec && voice === 'speech' && (
          <div className="mb-1.5 flex items-center gap-2 text-[12.5px] font-semibold text-danger" role="status">
            <span className="h-2 w-2 rounded-full bg-danger motion-safe:animate-pulse" aria-hidden />
            {tf(lang, 'nr_voice_on', { l: DICT_NAME[lang === 'ar' ? 'ar' : 'en'][dict] })}
          </div>
        )}
        {/* The drawing surface: the same file picker as the paperclip, and it takes a dropped file
            through the same onFile. Hidden once a drawing is attached, so it never crowds the input. */}
        {!drawing && (
          <button type="button" disabled={analyzing || thinking} onClick={() => fileRef.current && fileRef.current.click()}
            onDragOver={(e) => e.preventDefault()} onDrop={(e) => { e.preventDefault(); if (!analyzing && !thinking) onAny(e.dataTransfer.files && e.dataTransfer.files[0]); }}
            className="mb-2.5 flex h-10 w-full items-center gap-2.5 rounded-btn border border-dashed border-primary/35 bg-[repeating-linear-gradient(135deg,transparent_0_8px,hsl(var(--primary)/0.05)_8px_9px)] px-3 text-start transition-colors hover:border-primary/60 hover:bg-primary/[0.06] disabled:opacity-40">
            <Paperclip className="h-4 w-4 shrink-0 text-primary" aria-hidden />
            <span className="min-w-0 truncate font-mono text-label text-muted-foreground">{t(lang, 'nr_drop')}</span>
          </button>
        )}
        <div className="flex items-end gap-2">
          {/* .dwg/.dxf listed as extensions too: some browsers send an empty MIME for CAD files. */}
          {/* Sheets are accepted here too, because the drop surface above advertises Excel and CSV; onAny routes them. */}
          <input ref={fileRef} type="file" accept="image/*,.heic,.heif,.tif,.tiff,application/pdf,.dwg,.dxf,image/vnd.dwg,image/vnd.dxf,.xlsx,.xls,.csv,.ods,.doc,.docx,.pptx,.odt,.odp,.rtf,.txt,.eml,.msg,.xml,.x83,.x84,.x86,.zip" className="hidden" aria-label={t(lang, 'nr_attach')} onChange={(e) => onAny(e.target.files[0])} />
          <button type="button" title={t(lang, 'nr_attach')} aria-label={t(lang, 'nr_attach')} className="grid h-10 w-10 place-items-center rounded-xl text-primary hover:bg-primary/10 disabled:opacity-40" disabled={analyzing || thinking} onClick={() => fileRef.current && fileRef.current.click()}><Paperclip className="h-5 w-5" aria-hidden /></button>
          {/* Founder, 14 Sep 2026: "boq can be anything: a photo, pdf, png, jpg, excel". Photos and PDFs take the
              drawing path (onFile, source 'boq'). HEIC is deliberately NOT listed: storage and the redactor cannot
              decode it, and when it is absent iOS Safari converts a HEIC photo to JPEG before handing it over. */}
          <input ref={boqRef} type="file" accept=".xlsx,.xls,.csv,.ods,.pdf,application/pdf,text/csv,application/vnd.ms-excel,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,.png,.jpg,.jpeg,.webp,image/png,image/jpeg,image/webp,.tif,.tiff,.doc,.docx,.odt,.rtf,.txt,.xml,.x83,.x84,.x86,.zip" className="hidden" aria-label={t(lang, 'nr_attach_boq')} onChange={(e) => onBoq(e.target.files[0])} />
          <button type="button" title={t(lang, 'nr_attach_boq')} aria-label={t(lang, 'nr_attach_boq')} className="flex h-10 shrink-0 items-center gap-1.5 rounded-xl px-2 text-primary hover:bg-primary/10 disabled:opacity-40" disabled={analyzing || thinking} onClick={() => boqRef.current && boqRef.current.click()}><FileSpreadsheet className="h-5 w-5" aria-hidden /><span className="hidden text-[12.5px] font-semibold sm:inline">{t(lang, 'nr_attach_boq_short')}</span></button>
          {/* The mic is always shown once the browser is known: where it cannot dictate, pressing it says
              why and points at the phone keyboard's own dictation instead of failing after the fact. */}
          {voice && (
            <button type="button" title={t(lang, rec ? 'nr_mic_stop' : 'nr_mic')} aria-label={t(lang, rec ? 'nr_mic_stop' : 'nr_mic')} aria-pressed={rec}
              className={cn('grid h-10 w-10 shrink-0 place-items-center rounded-xl hover:bg-primary/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40', rec ? 'bg-danger/10 text-danger' : 'text-primary')}
              disabled={voxBusy} onClick={onMic}>
              {voxBusy ? <span className="redact redact-sq" style={{ width: 16, height: 16 }} aria-hidden /> : rec ? <Square className="h-5 w-5" aria-hidden /> : <Mic className="h-5 w-5" aria-hidden />}
            </button>
          )}
          {voice === 'speech' && (
            <button type="button" disabled={rec} onClick={() => setDict((d) => (d === 'ar' ? 'en' : 'ar'))}
              title={tf(lang, 'nr_voice_dict', { l: DICT_NAME[lang === 'ar' ? 'ar' : 'en'][dict] })} aria-label={tf(lang, 'nr_voice_dict', { l: DICT_NAME[lang === 'ar' ? 'ar' : 'en'][dict] })}
              className="grid h-10 w-9 shrink-0 place-items-center rounded-xl font-mono text-[12px] font-semibold text-primary hover:bg-primary/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40">
              <span lang={dict}>{dict === 'ar' ? 'ع' : 'EN'}</span>
            </button>
          )}
          <label htmlFor="qd-intake-input" className="sr-only">{t(lang, 'nr_input_label')}</label>
          <textarea id="qd-intake-input" ref={inputRef} className="min-h-[48px] min-w-0 flex-1 resize-none rounded-btn border border-input bg-background px-3.5 py-3 text-copy text-foreground shadow-e1 outline-none transition-[border-color,box-shadow] placeholder:text-muted-foreground focus:border-primary/60 focus:shadow-ring" rows={2}
            placeholder={rec ? t(lang, 'nr_listening') : t(lang, 'nr_ph')} value={input} onChange={(e) => setInput(e.target.value)} onKeyDown={onKey} />
          <Button size="lg" className="px-4" disabled={thinking || analyzing || !input.trim()} onClick={send} aria-label={t(lang, 'nr_send')}><SendHorizontal className="h-4 w-4 rtl:-scale-x-100" aria-hidden /><span className="ms-1.5 hidden sm:inline">{t(lang, 'nr_send')}</span></Button>
        </div>
      </div>
    </section>
  );
}

const Fact = ({ k, v }) => <div className="flex gap-1.5"><dt className="text-muted-foreground">{k}:</dt><dd className="text-foreground">{v}</dd></div>;

// WHAT THE CUSTOMER TOLD THE SALES ENGINEER, editable before Send: one row per question (materials,
// installation, warranty, the date). "Change" offers the same options the question did; the tapped
// label goes to create_inquiry as requirement_edits and the server reads it again
// (_shared/intake_requirements.ts applyEdits), so nothing the browser sends is trusted as parsed.
function RequirementsCard({ items, edits, onEdit, lang }) {
  const [open, setOpen] = useState(null);
  return (
    <div className="mt-3 rounded-xl border border-border bg-card/60 p-3">
      <div className="text-[12.5px] font-semibold text-foreground">{t(lang, 'nr_req_title')}</div>
      <dl className="mt-1 space-y-1.5">
        {items.map((it) => {
          const shown = edits[it.key] || it.answer;
          return (
            <div key={it.key}>
              <div className="flex flex-wrap items-baseline gap-x-1.5 text-[12.5px]">
                <dt className="text-muted-foreground">{it.label}:</dt>
                <dd className="text-foreground">{shown}</dd>
                <button type="button" className="ms-auto text-[12px] font-semibold text-primary underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                  aria-expanded={open === it.key} onClick={() => setOpen(open === it.key ? null : it.key)}>{t(lang, open === it.key ? 'nr_req_keep' : 'nr_req_change')}</button>
              </div>
              {open === it.key ? (
                <div className="mt-1 flex flex-wrap gap-1.5" role="group" aria-label={it.question}>
                  {it.options.map((o) => (
                    <button key={o} type="button" onClick={() => { onEdit(it.key, o); setOpen(null); }}
                      className={cn('rounded-full border px-2.5 py-1 text-[12px] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring', shown === o ? 'border-primary/55 bg-primary/15 font-semibold text-primary' : 'border-border bg-card/60 text-foreground hover:border-primary/40')}>{o}</button>
                  ))}
                </div>
              ) : null}
            </div>
          );
        })}
      </dl>
    </div>
  );
}

function ReadinessBar({ pct, lang, reduce }) {
  return (
    <div className="border-b border-border px-5 py-2">
      <div className="flex items-center justify-between"><span className="font-mono text-label uppercase tracking-caps text-muted-foreground">{t(lang, 'nr_readiness')}</span><span className="tabular font-mono text-label text-foreground">{pct}%</span></div>
      <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-secondary/70" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct} aria-label={t(lang, 'nr_readiness')}>
        <motion.div className="h-full rounded-full bg-gradient-to-r from-primary/60 to-primary" initial={reduce ? false : { width: 0 }} animate={{ width: pct + '%' }} transition={{ duration: reduce ? 0 : 0.7, ease: [0.2, 0.8, 0.2, 1] }} />
      </div>
    </div>
  );
}

function QuestionChips({ questions, next, left, lang, onPick, reduce }) {
  return (
    <div className="mt-2 ps-1">
      <div className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{left > 0 ? tf(lang, 'nr_left', { n: left }) : t(lang, 'nr_chips_hint')}</div>
      <div className="flex flex-wrap gap-1.5">
        {questions.slice(0, 8).map((q, i) => (
          <motion.button key={q + i} type="button" onClick={() => onPick(q)}
            initial={reduce ? false : { opacity: 0, y: 4 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: reduce ? 0 : 0.2, delay: reduce ? 0 : 0.05 * i }}
            className={cn('rounded-full border px-3 py-1.5 text-start text-[12.5px] transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
              q === next ? 'border-primary/55 bg-primary/15 font-semibold text-primary' : 'border-border bg-card/60 text-foreground hover:border-primary/40')}>
            {q}
          </motion.button>
        ))}
      </div>
    </div>
  );
}

// The BOQ the reader pulled off the drawing, before Send. The customer is the only person who can
// say it was read wrong, and they were shown a line count and nothing else.
function BoqTable({ boq, lang }) {
  const rows = boq.boq.slice(0, 40);
  const conf = (c) => confidenceWord(c, lang);
  const list = (x) => (Array.isArray(x) ? x : x ? [x] : []).map((v) => (typeof v === 'string' ? v : v && (v.text || v.item || v.note || JSON.stringify(v)))).filter(Boolean);
  const assumptions = list(boq.assumptions).map((s) => boqNote(s, lang)), missing = list(boq.missing_info).map((s) => boqNote(s, lang));
  return (
    <div className="rounded-2xl border border-border bg-card/60 p-3.5">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="text-[13px] font-bold text-foreground">{t(lang, 'nr_boq_title')}</h3>
        {boq.confidence != null ? <span className="text-[11.5px] text-muted-foreground">{tf(lang, 'nr_boq_overall', { c: conf(boq.confidence) })}</span> : null}
      </div>
      <div className="mt-2 max-h-[240px] overflow-auto rounded-lg border border-border">
        <table className="w-full text-[12px]">
          <thead className="sticky top-0 bg-secondary font-mono text-label uppercase tracking-caps text-muted-foreground"><tr>
            <th scope="col" className="px-2.5 py-1.5 text-start font-semibold">{t(lang, 'nr_boq_item')}</th>
            <th scope="col" className="px-2.5 py-1.5 text-end font-semibold">{t(lang, 'nr_boq_qty')}</th>
            <th scope="col" className="px-2.5 py-1.5 text-start font-semibold">{t(lang, 'nr_boq_unit')}</th>
            <th scope="col" className="px-2.5 py-1.5 text-end font-semibold">{t(lang, 'nr_boq_conf')}</th>
          </tr></thead>
          <tbody>{rows.map((r, i) => (
            <tr key={i} className="border-t border-border/60">
              <td className="px-2.5 py-1.5 text-foreground">{r.description || r.item || r.name || '—'}</td>
              <td className="tabular px-2.5 py-1.5 text-end font-mono text-foreground">{r.qty ?? r.quantity ?? '—'}</td>
              <td className="px-2.5 py-1.5 text-muted-foreground">{r.unit || '—'}</td>
              <td className="px-2.5 py-1.5 text-end tabular-nums text-muted-foreground">{conf(r.confidence)}</td>
            </tr>
          ))}</tbody>
        </table>
      </div>
      {assumptions.length ? <div className="mt-2 text-[12px] text-muted-foreground"><b className="text-foreground">{t(lang, 'nr_boq_assumptions')}: </b>{assumptions.join(' · ')}</div> : null}
      {missing.length ? <div className="mt-1 text-[12px] text-warn-fg"><b>{t(lang, 'nr_boq_missing')}: </b>{missing.join(' · ')}</div> : null}
    </div>
  );
}

// THE CUSTOMER-DRAWN REDACTION. Boxes are stored normalised to the page (0..1), so they mean the
// same thing at the 1600px width drawing_redact works at as they do on this screen.
function RedactionEditor({ lang, images, onApply, onSkip, reduce }) {
  const [page, setPage] = useState(0);
  const [boxes, setBoxes] = useState(() => images.map(() => []));
  const [drag, setDrag] = useState(null);
  const [busy, setBusy] = useState(false);
  const surf = useRef(null);
  const pt = (e) => { const r = surf.current.getBoundingClientRect(); return { x: Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)), y: Math.min(1, Math.max(0, (e.clientY - r.top) / r.height)) }; };
  const down = (e) => { e.preventDefault(); try { e.currentTarget.setPointerCapture(e.pointerId); } catch (_e) {} const p = pt(e); setDrag({ x0: p.x, y0: p.y, x1: p.x, y1: p.y }); };
  const move = (e) => { if (!drag) return; const p = pt(e); setDrag((d) => ({ ...d, x1: p.x, y1: p.y })); };
  const up = () => {
    if (!drag) return;
    const b = { x: Math.min(drag.x0, drag.x1), y: Math.min(drag.y0, drag.y1), w: Math.abs(drag.x1 - drag.x0), h: Math.abs(drag.y1 - drag.y0) };
    if (b.w > 0.005 && b.h > 0.005) setBoxes((all) => all.map((l, i) => (i === page ? [...l, b] : l)));
    setDrag(null);
  };
  const total = boxes.reduce((n, l) => n + l.length, 0);
  const apply = async () => { setBusy(true); await onApply(boxes); setBusy(false); };
  const live = drag ? { x: Math.min(drag.x0, drag.x1), y: Math.min(drag.y0, drag.y1), w: Math.abs(drag.x1 - drag.x0), h: Math.abs(drag.y1 - drag.y0) } : null;
  const pct = (v) => (v * 100) + '%';
  return (
    <motion.div initial={reduce ? false : { opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} className="rounded-2xl border border-primary/35 bg-card/70 p-3.5">
      <h3 className="text-[13.5px] font-bold text-foreground">{t(lang, 'rd_title')}</h3>
      <p className="mt-0.5 text-[12.5px] leading-relaxed text-muted-foreground">{t(lang, 'rd_body')}</p>
      <div className="mt-2.5 flex items-center justify-between gap-2 text-[12px] text-muted-foreground" dir="ltr">
        <button type="button" className="grid h-8 w-8 place-items-center rounded-lg border border-border disabled:opacity-40" disabled={page === 0} onClick={() => setPage((p) => p - 1)} aria-label={t(lang, 'rd_prev')}><ChevronLeft className="h-4 w-4" aria-hidden /></button>
        <span>{tf(lang, 'rd_page', { n: page + 1, total: images.length })} · {tf(lang, 'rd_boxes', { n: total, c: countPhrase(lang, total, 'area') })}</span>
        <button type="button" className="grid h-8 w-8 place-items-center rounded-lg border border-border disabled:opacity-40" disabled={page >= images.length - 1} onClick={() => setPage((p) => p + 1)} aria-label={t(lang, 'rd_next')}><ChevronRight className="h-4 w-4" aria-hidden /></button>
      </div>
      <div ref={surf} className="relative mt-2 cursor-crosshair touch-none select-none overflow-hidden rounded-lg border border-border bg-white" dir="ltr"
        role="img" aria-label={tf(lang, 'rd_canvas', { n: page + 1 })}
        onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerLeave={up}>
        <img src={'data:' + images[page].mime + ';base64,' + images[page].data} alt="" draggable={false} className="block h-auto w-full" />
        {boxes[page].map((b, i) => <span key={i} className="redact absolute !rounded-[1px] !bg-black/90" style={{ left: pct(b.x), top: pct(b.y), width: pct(b.w), height: pct(b.h) }} />)}
        {live ? <span className="absolute border-2 border-dashed border-primary bg-primary/20" style={{ left: pct(live.x), top: pct(live.y), width: pct(live.w), height: pct(live.h) }} /> : null}
      </div>
      <div className="mt-2.5 flex flex-wrap items-center gap-2">
        <Button size="sm" disabled={busy || total === 0} onClick={apply}>{busy ? t(lang, 'rd_applying') : t(lang, 'rd_apply')}</Button>
        <Button size="sm" variant="outline" disabled={busy || !boxes[page].length} onClick={() => setBoxes((all) => all.map((l, i) => (i === page ? [] : l)))}><Eraser className="me-1 h-3.5 w-3.5" aria-hidden />{t(lang, 'rd_clear')}</Button>
        <Button size="sm" variant="link" className="h-auto px-0" disabled={busy} onClick={onSkip}>{t(lang, 'rd_skip')}</Button>
      </div>
    </motion.div>
  );
}
