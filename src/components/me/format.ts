// @ts-nocheck
// THE SHELL. The portal was a stack of cards under ten grey pills; this is the application frame
// the founder asked for — persistent grouped sidebar, a top bar whose widest element is the
// assistant, a mobile tab bar, and the assistant docked in the layout rather than floating in a
// corner. See the header of PortalShell.tsx for what was on the screen before and why.
import { rfqState } from './PortalShell';

// Wrapped in LRI…PDI so "AED 36,900" keeps its order inside an Arabic sentence.
const aed = (n) => '⁦AED ' + Number(n || 0).toLocaleString('en-AE', { maximumFractionDigits: 0 }) + '⁩';
// The hour is the CUSTOMER'S, not the server's: the portal renders client-side only (the shell
// returns null until mounted), so a customer opening it at 07:00 in Dubai is not greeted with the
// deployment region's afternoon. Arabic uses مساء from midday onward, which is why it has two
// branches where English has three.
const greetingOf = (lang) => { const h = new Date().getHours(); if (lang === 'ar') return h < 12 ? 'صباح الخير' : 'مساء الخير'; return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening'; };
// SPEC §8 names five RFQ stages. Each is read off a fact this component already holds, and none of
// them is asserted from the clock:
//   created  — the row exists, so it is always reached
//   sent     — anything past intake has been dispatched to suppliers
//   quotes   — at least one quote has landed
//   analysis — at least TWO, which is the exact condition under which quote_compare runs and the
//              comparison card mounts on this same request. Below two there is nothing to analyse
//              and the stage must not claim there is.
//   award    — a supplier is hired, or the request is completed
// The server's recorded pipeline_stage wins wherever it speaks — see stateOf below.
const RFQ_STAGES = {
  en: ['Created', 'Sent', 'Quotes received', 'AI analysis', 'Awarded'],
  ar: ['أُنشئ', 'أُرسل', 'وردت العروض', 'تحليل ذكي', 'تم التعاقد'],
};
const rfqStageIdx = (inq, quotes) => {
  if (inq && (inq.status === 'completed' || inq.hired_supplier_id || inq.pipeline_stage === 'won')) return 4;
  const n = (quotes || []).length;
  if (n >= 2) return 3;
  if (n >= 1) return 2;
  return String(inq && inq.status) === 'draft' ? 0 : 1;
};
// §8 THE SERVER'S STAGE, WHERE IT HAS ONE (website audit 14 Sep 2026). my_inquiries serves
// pipeline_stage and every pill, rail and whose-move count ignored it and guessed from
// quotes.length, so a request the lifecycle had cancelled could still read "Matching". The stages
// the lifecycle SQL writes are 'revealed', 'won' and 'cancelled' (scripts/sql and full_schema.sql);
// those decide. Anything else, or null — every production row on 14 Sep, as there are no inquiries
// yet — falls back to the derivation, so no stage is ever invented.
const stateOf = (inq, quotes) => {
  const ps = String((inq && inq.pipeline_stage) || '');
  if (ps === 'cancelled' || ps === 'lost' || ps === 'closed') return 'closed';
  if (ps === 'revealed' || ps === 'won') return 'revealed';
  return rfqState(inq, quotes);
};
// Pre-reveal labels are served as 'Supplier A'; the letter is the identity-free part.
const supLabel = (label, lang) => (lang === 'ar' ? String(label || '').replace(/^Supplier\b/, 'المورّد') : label);
// Pre-reveal, customer_api returns a coarse rating BAND ('4.5+', '4.0-4.5', ...) instead of a number.
// Bands are looked up here first so a banded string is never handed to Number() (which yields NaN).
const RATING_BANDS = { '4.5+': 4.75, '4.0-4.5': 4.25, '3.5-4.0': 3.75, 'below 3.5': 3.0 };
// Returns null — not a number — when the supplier has no QuotesDone rating (founder, 9 Sep 2026:
// "google review shouldnt be counted"; the Google fallback that used to fill this in is gone, so
// every supplier is unrated until a customer rates one). The value score drops the rating term and
// rescales the remaining weights: an absent rating must be ABSENT from the weighting, never a 0
// that ranks a good supplier last, and never a 60 that flatters a genuinely poor one.
const ratingScoreOf = (r) => { if (r == null) return null; const b = RATING_BANDS[String(r).trim()]; if (b != null) return Math.round((b / 5) * 100); const n = Number(r); return Number.isFinite(n) ? Math.round((n / 5) * 100) : null; };
const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Umm Al Quwain', 'Fujairah'];
export { aed, greetingOf, RFQ_STAGES, rfqStageIdx, stateOf, supLabel, ratingScoreOf, EMIRATES };
