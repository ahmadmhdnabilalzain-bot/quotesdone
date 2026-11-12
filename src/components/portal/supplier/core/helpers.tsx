// @ts-nocheck
'use client';
import { arDays } from '@/lib/durationLabel';
import { AR_NOUN, arCount } from '@/lib/countedNoun';
// WHAT A FAILED READ MEANS, DECIDED IN ONE PLACE (audit 22 Sep 2026, SP-C-08): only the dashboard
// read `_http === 401`. Billing, Receipts, Projects, Documents and Profile each rendered an empty
// panel on an expired session — "you have no dues / no projects / no documents" to a supplier whose
// token had simply aged out.
import { isExpired } from '../PanelState';
import { cn } from '@/lib/utils';
import { t } from './copy';

// call() lives in ./supplier/api.ts, shared with the journey, RFQ and insights components.
// Every field carries a <label> (audit 2026-09-14: three unlabeled fields, the Emirate <select> with
// no accessible name at all). Visually hidden where a placeholder already shows the same words.
// `need` ('req' | 'opt') marks a registration field Required or Optional in the page's language and makes
// the label visible (audit 15 Sep 2026: no field said which of the mandatory six it was).
// Arabic number agreement for "N days left" (review of PR #818): 1, 2, 3-10 and 11+ each take their own form.
function arDaysLeft(n) {
  return `${arDays(n)} ${n === 1 ? 'متبقٍ' : n === 2 ? 'متبقيان' : n <= 10 ? 'متبقية' : 'متبقيًا'} لمعالجة ذلك`;
}
// "We read your quotation — N line items". The Arabic said "{n} بند" for every n (audit 22 Sep 2026,
// SP-I-04); arCount is the one rule the whole estate counts by.
const lineCount = (lang, n) => (lang === 'ar' ? arCount(n, AR_NOUN.line) : `${n} line item${n === 1 ? '' : 's'}`);

function Need({ lang, req = false }) {
  return <span className={cn('ms-1.5 align-middle text-[11px] pointer-coarse:text-[13px] font-semibold', req ? 'text-danger-fg' : 'text-muted-foreground')}>{t(lang, req ? 'required' : 'optional')}</span>;
}
function Lbl({ text, children, className = '', visible = false, need = null, lang = 'en' }) {
  return <label className={cn('block min-w-0', className)}><span className={visible || need ? 'mb-1 block text-[12px] pointer-coarse:text-[14px] font-semibold text-muted-foreground' : 'sr-only'}>{text}{need ? <Need lang={lang} req={need === 'req'} /> : null}</span>{children}</label>;
}
// `aed(lang, n)` is imported from ./supplier/money — see the note at the imports.
// A SESSION THAT HAS ENDED IS NOT AN EMPTY PANEL. Every read in this file routes its failure through
// here: an expired token goes to the dashboard's own `onExpired` (refresh once, then sign in again),
// anything else stays with the panel's own message.
//
// `onErr` IS NOT OPTIONAL POLISH (review of #858). `onExpired` no longer always signs out — a
// single 401 during a GoTrue outage now leaves the session in place (see onExpired below). A caller
// that returns early on the strength of that would render a blank panel and no explanation, which
// is the very defect this helper was added to end. So every caller that HAS an error state is
// handed one here; the panel shows "your session has ended" and a retry that can actually succeed.
const wentExpired = (j, onExpired, onErr = null) => {
  if (!isExpired(j)) return false;
  if (onErr) onErr('session_expired');
  if (onExpired) onExpired();
  return true;
};
// Amounts, phone numbers, e-mails and reference codes are left-to-right runs. Inside the Arabic
// portal an unisolated "AED 12,500" or "+971 50 …" is reordered by the bidi algorithm around the
// Arabic text beside it (portal audit 14 Sep 2026); <Ltr> keeps each one whole.
// A LOCALISED DATE IS NOT ONE OF THEM. This comment used to say "dates" and that was the defect
// (17 Sep 2026): fmtDate(d, 'ar') returns Arabic — "18 سبتمبر 2026" — and forcing dir="ltr" onto it
// made the licence chip print the day AFTER the year, backwards. (Not quoted here with a year in it:
// pricing_arabic_parity.test.mjs greps this file for calendar years to keep the fee undated, and a
// comment would match.) `Ltr` now decides per string; src/lib/Ltr.tsx.
const fmtDate = (d, lang, withYear = true) => (d ? new Date(d).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', withYear ? { day: 'numeric', month: 'short', year: 'numeric' } : { day: 'numeric', month: 'short' }) : '');
// What a held (draft) quote is missing, in the codes fn_quote_structured_score returns. One table for
// the preflight panel and the held-quote notes, so the two can never describe the same gap differently.
const MISSING = {
  line_items: ['Itemised lines', 'بنود العرض'], unit_prices_on_all_items: ['A unit price on every line', 'سعر الوحدة لكل بند'],
  brand_model_per_item: ['Brand and model on every line', 'الماركة والموديل لكل بند'], specifications: ['Specifications', 'المواصفات'],
  labour_or_installation: ['Labour or installation', 'العمالة أو التركيب'], warranty: ['Warranty', 'الضمان'],
  lead_time: ['Lead time', 'مدة التنفيذ'], payment_terms: ['Payment terms', 'شروط الدفع'],
  exclusions: ['Exclusions', 'الاستثناءات'], validity: ['Quote validity', 'مدة صلاحية العرض'],
};
const missingLabel = (lang, m) => (MISSING[m] ? MISSING[m][lang === 'ar' ? 1 : 0] : (lang === 'ar' ? 'بند ناقص' : String(m).replace(/_/g, ' ')));
// Every format the quotation reader opens (supabase/functions/_shared/doc_read READERS, #591), the same
// list the customer's composer accepts. A DWG is accepted and stored; it is read once converted.
const QUOTE_ACCEPT = 'image/*,.heic,.heif,.tif,.tiff,application/pdf,.dwg,.dxf,.xlsx,.xls,.csv,.ods,.doc,.docx,.pptx,.odt,.odp,.rtf,.txt,.eml,.msg,.xml,.x83,.x84,.x86,.zip';
// REACHABLE BY KEYBOARD, AND IT SAYS WHEN IT IS WORKING (12 Nov 2026, customer_support; browser perfection walk M16 and H2). The
// file input was `hidden` (display:none), so Tab never reached any of the three "Attach file" controls (20 stops, none a picker);
// it is visually hidden now (sr-only) and the box lights up when it has focus. `busy` turns the clip into a turning ring and
// stops a second pick; `describedBy` ties the control to its own line (what was read, or what went wrong). UploadBar is the
// upload's progress bar under it, fed 0..1 by src/lib/signedUpload.ts putWithProgress.
function FilePick({ lang, accept, multiple = false, onPick, label = '', busy = false, describedBy = undefined, testId = undefined }) {
  return <label data-testid={testId} aria-busy={busy || undefined} className={cn('inline-flex min-h-11 items-center gap-2 rounded-md border border-border bg-secondary px-3 py-1.5 text-sm pointer-coarse:text-[15px] font-medium text-secondary-foreground hover:bg-secondary/80 focus-within:ring-2 focus-within:ring-ring focus-within:ring-offset-1 focus-within:ring-offset-background', busy ? 'cursor-progress opacity-80' : 'cursor-pointer')}>
    <input type="file" accept={accept} multiple={multiple ? true : undefined} disabled={busy} aria-describedby={describedBy} className="sr-only" onChange={(e) => { const fs = e.target.files; if (!fs || !fs.length) return; onPick(multiple ? Array.from(fs) : fs[0]); e.target.value = ''; }} />
    {busy ? <span aria-hidden="true" className="qd-spin" /> : <span aria-hidden="true">📎</span>} {label || t(lang, 'attach_file')}</label>;
}
function UploadBar({ progress, label }) {
  if (progress == null) return null;
  const pct = Math.max(0, Math.min(100, Math.round(progress * 100)));
  return <div className="mt-2 w-full max-w-[420px]" data-testid="upload-progress">
    <div className="h-1.5 w-full overflow-hidden rounded-full bg-secondary" role="progressbar" aria-label={label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct}>
      <div className="h-full rounded-full bg-primary transition-[width] duration-200" style={{ width: pct + '%' }} />
    </div>
  </div>;
}
export { arDaysLeft, lineCount, Need, Lbl, wentExpired, fmtDate, missingLabel, QUOTE_ACCEPT, FilePick, UploadBar };
