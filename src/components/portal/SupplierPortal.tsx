// @ts-nocheck
'use client';
import { useDeferredValue, useEffect, useRef, useState } from 'react';
import { urlLocale, applyDocumentLocale, applyShellChrome, adoptLocale } from '@/lib/documentLocale';
import { supaClient } from '@/lib/supaClient';
import { takeAuthFragment } from '@/lib/authFragment';
import { signupEmailProblem } from '@/lib/signupEmail';
// 14 Sep 2026: the row-#5 intelligence panels are no longer top-level tabs; ./supplier/Insights loads
// the ones whose routine has something to show, each on demand.
import SupplierSettings from './supplier/SupplierSettings';
import SupplierDocumentImpact from './supplier/SupplierDocumentImpact';
import SupplierEntryHero from './supplier/SupplierEntryHero';
import SupplierCommandPalette from './supplier/SupplierCommandPalette';
import GetMatched from './supplier/GetMatched';
import Insights, { INSIGHT_PANELS } from './supplier/Insights';
// Inquiries received and Quotations submitted (founder, 15 Sep 2026) — the conversation with the sales engineer.
import { InquiriesTab } from './supplier/InquiriesTab';
import { QuotationsTab } from './supplier/QuotationsTab';
import SupplierMailbox from './supplier/SupplierMailbox';
import SupplierSupportingDocuments from './supplier/SupplierSupportingDocuments';
import DocActions from './DocActions';
import { ws } from './supplier/workspaceCopy';
import ServicesTab from './supplier/ServicesTab';
import EmirateCheckboxes from './supplier/EmirateCheckboxes';
import { Kicker } from '@/components/ui/sealed';
import { srvMsg, srvText, itemCopy, emirateLabel, vocabLabel, TRADE_CODES, tradeLabel } from './supplier/serverCopy';
import { call } from './supplier/api';
import { openDocument } from '@/lib/openDocument';
import { Bell } from 'lucide-react';
// THE DASHBOARD'S FIRST READ STARTS WITH THE TOKEN (15 Sep 2026), the way the customer portal's does
// (me/prefetch.ts): the moment a token is known the combined `dashboard` call is started, and Dashboard's
// first load takes that promise instead of asking again. Every later load asks the server fresh.
import { warm, take, drop } from '@/components/me/prefetch';
const DASH_KEY = 'sup_dash';
const fetchDashboard = (tk) => call('supplier_portal', { action: 'dashboard' }, tk);
const warmSupplier = (tk) => warm(tk, DASH_KEY, () => fetchDashboard(tk));
import { uaeMobile } from './supplier/uaeMobile';
import { WhatsAppChoice } from './WhatsAppChoice';
import { waSignupSettled, waNeedsPrompt } from './whatsappChoiceText';
import { categoryLabel } from '@/lib/categoryLabel';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
// The one loading system (src/components/ui/busy.tsx): 150ms before anything shows, 300ms once it does.
import { Spinner, useBusy, useDelayedFlag } from '@/components/ui/busy';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import { BrandMark } from '@/components/BrandMark';

// Same as the customer portal: an inline production fallback meant an unconfigured preview let
// suppliers upload trade licences into the LIVE database. See supaEnv.
import { SUPA_ANON as ANON, SUPA_FN as FN } from '@/lib/supaEnv';
import { Ltr } from '@/lib/Ltr';
const SB = () => supaClient('qd-portal-auth');

// call() lives in ./supplier/api.ts, shared with the journey, RFQ and insights components.
// Every field carries a <label> (audit 2026-09-14: three unlabeled fields, the Emirate <select> with
// no accessible name at all). Visually hidden where a placeholder already shows the same words.
// `need` ('req' | 'opt') marks a registration field Required or Optional in the page's language and makes
// the label visible (audit 15 Sep 2026: no field said which of the mandatory six it was).
function Need({ lang, req = false }) {
  return <span className={cn('ms-1.5 align-middle text-[11px] font-semibold', req ? 'text-danger-fg' : 'text-muted-foreground')}>{t(lang, req ? 'required' : 'optional')}</span>;
}
function Lbl({ text, children, className = '', visible = false, need = null, lang = 'en' }) {
  return <label className={cn('block min-w-0', className)}><span className={visible || need ? 'mb-1 block text-[12px] font-semibold text-muted-foreground' : 'sr-only'}>{text}{need ? <Need lang={lang} req={need === 'req'} /> : null}</span>{children}</label>;
}
const aed = (n) => 'AED ' + Number(n || 0).toLocaleString('en-AE', { maximumFractionDigits: 0 });
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
const QUOTE_ACCEPT = 'image/*,.heic,.heif,.tif,.tiff,application/pdf,.dwg,.dxf,.xlsx,.xls,.csv,.ods,.doc,.docx,.pptx,.odt,.odp,.rtf,.txt,.eml,.msg,.ifc,.xml,.x83,.x84,.x86,.zip';
const fileToB64 = (f) => new Promise((res) => { const rd = new FileReader(); rd.onload = () => res(String(rd.result).split(',')[1]); rd.readAsDataURL(f); });
// STRIPE CAME BACK AND THE PAGE SAID NOTHING (audit 2026-09-14). supplier_pay and pay_registration
// return the supplier to /portal?dues_paid=… or ?registration_paid=…, and nothing read either query
// string — the only confirmation was an email. Dashboard now reads them once, strips them from the URL,
// opens Billing and shows this receipt. It says what is true at that moment: Stripe has the payment;
// the balance changes only when stripe_webhook confirms it, which is the one writer of "paid".
function ReceiptBanner({ receipt, lang }) {
  const ar = lang === 'ar';
  const reg = receipt.kind === 'registration';
  return (
    <div role="status" className="qd-panel flex items-start gap-3 border-primary/40 p-4">
      <span aria-hidden className="mt-0.5 grid h-7 w-7 shrink-0 place-items-center rounded-full bg-primary text-primary-foreground text-sm font-bold">✓</span>
      <div>
        <div className="text-[14px] font-bold text-foreground">{ar ? (reg ? 'تم استلام رسوم التسجيل' : 'تم استلام الدفعة') : (reg ? 'Registration payment received' : 'Payment received')}</div>
        <div className={S.sub}>{ar
          ? 'استلمت Stripe دفعتكم وسترسل إليكم الفاتورة بالبريد الإلكتروني، ويُحدَّث رصيدكم هنا فور تأكيد Stripe لنا، وعادةً خلال دقيقة.'
          : 'Stripe has your payment and will email you the invoice. Your balance here updates as soon as Stripe confirms it to us, usually within a minute.'}</div>
        <div className="mt-1 text-[11px] text-muted-foreground" dir="ltr">{(ar ? 'مرجع ' : 'Ref ') + '…' + String(receipt.ref || '').slice(-8)}</div>
      </div>
    </div>
  );
}
// The onboarding copy promises "free for the first 1,000 suppliers, then AED 1,000 per year" (the
// founder's 6 Sep ruling: the fee starts with the registration after the free count, no calendar
// date). pay_registration already answers from fn_supplier_registration_state and creates a Stripe
// Checkout only when a fee is actually due — and had NO caller in src/, so the promise had no button.
// This is that button. For an exempt or not-yet-due supplier it only reads, and says why.
function RegistrationFeeCard({ token, lang, base }) {
  const ar = lang === 'ar';
  const [busy, setBusy] = useState(false); const [res, setRes] = useState(null);
  const check = async () => {
    setBusy(true); setRes(null);
    // Payments are the accountant's (founder, 14 Sep 2026): the registration checkout lives in supplier_pay.
    const j = await call('supplier_pay', { action: 'registration', return_url: base() }, token);
    if (j && j.ok && j.url) { window.location.href = j.url; return; }
    setBusy(false);
    setRes({ ok: !!(j && j.ok), text: srvMsg(lang, j, t(lang, 'err_generic')) });
  };
  return (
    <Card className="qd-panel p-5">
      <div className={S.h2}>{ar ? 'رسوم التسجيل السنوية' : 'Yearly registration fee'}</div>
      <div className={cn(S.sub, 'mt-1')}>{ar
        ? 'التسجيل مجاني بصفة دائمة لأول 1,000 مورّد، واعتبارًا من التسجيل رقم 1,001 تكون الرسوم 1,000 درهم سنويًا. إن كانت عليكم رسوم مستحقة فستنتقلون مباشرة إلى صفحة الدفع الآمنة في Stripe، وإلا فسنوضح لكم السبب.'
        : 'Registration is permanently free for the first 1,000 suppliers; from the 1,001st registration it is AED 1,000 per year. If a fee is due you go straight to Stripe’s secure checkout; if not, we tell you why.'}</div>
      <Button className="mt-3" variant="outline" disabled={busy} onClick={check}>{busy ? (ar ? 'جارٍ التحقق…' : 'Checking…') : (ar ? 'التحقق من رسوم التسجيل' : 'Check my registration fee')}</Button>
      {res && <div role="status" className={cn('mt-2 text-[13px]', res.ok ? 'text-primary' : 'text-danger-fg')}>{res.text}</div>}
    </Card>
  );
}
function BillingPanel({ token, lang, receipt }) {
  const [st, setSt] = useState({ loading: true, dues: [], total: 0, err: '' });
  const [busy, setBusy] = useState(false);
  // Stripe returns to base + '/portal', so an Arabic supplier comes back to /ar/portal.
  const base = () => window.location.origin + (lang === 'ar' ? '/ar' : '');
  const load = async () => {
    setSt((s) => ({ ...s, loading: true, err: '' }));
    const j = await call('supplier_pay', { action: 'list' }, token);
    if (j && j.ok) setSt({ loading: false, dues: j.dues || [], total: Number(j.total_owed || 0), err: '' });
    else setSt({ loading: false, dues: [], total: 0, err: (j && j.error) || 'load_err' });
  };
  useEffect(() => { load(); }, [token]);
  // A disputed charge goes to the sales engineer, who has the accountant check it against the payment
  // record; the answer arrives by email from customer_support.
  // It said NOTHING between the prompt and the alert (18 Sep 2026) — on a slow line the supplier had
  // no way to tell a sent dispute from an ignored press, and could send the same one twice. useBusy
  // closes the double-press window from ms 0 and carries the ring after 150ms.
  const disp = useBusy();
  const dispute = async (dueId) => {
    const reason = window.prompt(lang === 'ar' ? 'ما سبب اعتراضكم على هذه الرسوم؟' : 'What is wrong with this charge?');
    if (!reason) return;
    const j = await disp.run('d' + dueId, () => call('supplier_api', { action: 'dispute_charge', due_id: dueId, reason }, token));
    window.alert(j && j.ok
      ? (lang === 'ar' ? 'استلمنا اعتراضكم، ونراجع الرسوم الآن مقابل سجل الدفع وسنوافيكم بالرد.' : 'We have your query. We are checking the charge against the payment record and will write back to you.')
      : t(lang, 'err_generic'));
  };
  const pay = async () => {
    setBusy(true);
    const j = await call('supplier_pay', { action: 'checkout', return_url: base() }, token);
    if (j && j.ok && j.url) { window.location.href = j.url; return; }
    setBusy(false);
    setSt((s) => ({ ...s, err: 'checkout_err' }));
  };
  let dues;
  if (st.loading) dues = <Card className="qd-panel p-5">{t(lang, 'loading_dash')}</Card>;
  else if (st.err) dues = <Card className="qd-panel p-5"><div className={S.h2}>{t(lang, 'something_wrong')}</div><div className={S.sub}>{t(lang, 'bill_err')}</div><Button className="mt-3" onClick={load}>{t(lang, 'bill_retry')}</Button></Card>;
  else if (!st.dues.length) dues = <Card className="qd-panel p-5"><div className={S.h2}>{t(lang, 'bill_title')}</div><div className={S.sub}>{t(lang, 'bill_none')}</div></Card>;
  else dues = (
    <Card className="qd-panel p-5">
      <div className={S.h2}>{t(lang, 'bill_title')}</div>
      <div className="flex flex-col gap-2 my-3">
        {st.dues.map((d) => (
          <div key={d.id} className="flex justify-between items-center border-b border-border pb-2 text-[13.5px]">
            <div>
              <div className="font-semibold tabular-nums"><Ltr>{aed(d.amount)}</Ltr></div>
              <div className={S.sub}>{t(lang, 'bill_commission')} <Ltr>{aed(d.commission)}</Ltr>{d.fine ? <> · {t(lang, 'bill_fine')} <Ltr>{aed(d.fine)}</Ltr></> : null}</div>
            </div>
            <div className="text-right">
              <div className={S.sub}>{d.due_date ? <>{t(lang, 'bill_due')} <Ltr>{fmtDate(d.due_date, lang)}</Ltr></> : ''}</div>
              <button type="button" disabled={disp.pending} aria-busy={(disp.busy && disp.key === 'd' + d.id) || undefined}
                className="inline-flex items-center gap-1.5 text-[12px] underline text-muted-foreground disabled:opacity-60" onClick={() => dispute(d.id)}>
                {disp.busy && disp.key === 'd' + d.id
                  ? <><Spinner />{lang === 'ar' ? 'جارٍ إرسال اعتراضكم…' : 'Sending your query…'}</>
                  : (lang === 'ar' ? 'الاعتراض على هذه الرسوم' : 'Dispute this charge')}
              </button>
            </div>
          </div>
        ))}
      </div>
      <div className="flex justify-between items-center mt-3 flex-wrap gap-3">
        <div>
          <div className={S.sub}>{t(lang, 'bill_total')}</div>
          <div className="text-[20px] font-extrabold text-foreground tabular-nums"><Ltr>{aed(st.total)}</Ltr></div>
        </div>
        <Button onClick={pay} disabled={busy}>{busy ? t(lang, 'bill_paying') : t(lang, 'bill_pay')}</Button>
      </div>
      <div className={cn(S.sub, 'mt-3')}>{t(lang, 'bill_secure')}</div>
    </Card>
  );
  return <div className={S.list}>{receipt ? <ReceiptBanner receipt={receipt} lang={lang} /> : null}{dues}<Receipts token={token} lang={lang} /><RegistrationFeeCard token={token} lang={lang} base={base} /></div>;
}
// A supplier's own document as PDF (supplier_api quote_pdf / receipt_pdf, 15 Sep 2026): the portal's
// language first and the other language one click away, through the same popup-safe door the customer's
// quotation uses (src/lib/openDocument.ts).
function PdfLinks({ lang, fetchPdf, otherOnly = false }) {
  const [busy, setBusy] = useState(''); const [msg, setMsg] = useState('');
  const mine = lang === 'ar' ? 'ar' : 'en'; const other = mine === 'ar' ? 'en' : 'ar';
  const open = (docLang) => async (e) => {
    e.stopPropagation(); setBusy(docLang); setMsg('');
    const ok = await openDocument(lang, async () => { const j = await fetchPdf(docLang); return j && j.ok && j.url ? j.url : null; });
    setBusy(''); if (!ok) setMsg(lang === 'ar' ? 'تعذّر تجهيز المستند. يُرجى المحاولة مرة أخرى.' : 'The document could not be prepared. Please try again.');
  };
  const prep = lang === 'ar' ? 'جارٍ التحضير…' : 'Preparing…';
  return (<span className="inline-flex flex-wrap items-center gap-x-3 gap-y-1">
    {/* otherOnly: the four-action row (DocActions) already offers the reader's own language. */}
    {!otherOnly && <button type="button" className="inline-flex min-h-11 items-center text-primary font-semibold text-[12.5px] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" disabled={!!busy} onClick={open(mine)}>{busy === mine ? prep : (mine === 'ar' ? 'تنزيل PDF' : 'Download PDF')}</button>}
    <button type="button" lang={other} className="inline-flex min-h-11 items-center text-muted-foreground underline underline-offset-2 text-[11.5px] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" disabled={!!busy} onClick={open(other)}>{busy === other ? prep : (other === 'ar' ? 'النسخة العربية' : 'English version')}</button>
    {msg ? <span role="alert" className="text-[12px] text-danger-fg">{msg}</span> : null}
  </span>);
}
// Receipts for the dues this supplier has paid (supplier_api receipts). Nothing paid, nothing shown.
function Receipts({ token, lang }) {
  const ar = lang === 'ar';
  const [list, setList] = useState([]);
  useEffect(() => { let live = true; call('supplier_api', { action: 'receipts' }, token).then((j) => { if (live) setList((j && j.ok && j.receipts) || []); }).catch(() => {}); return () => { live = false; }; }, [token]);
  if (!list.length) return null;
  return (
    <Card className="qd-panel p-5">
      <div className={S.h2}>{ar ? 'إيصالات الدفع' : 'Payment receipts'}</div>
      <ul className="mt-3 flex flex-col gap-2">{list.map((r) => (
        <li key={r.id} className="flex flex-wrap items-center justify-between gap-2 border-b border-border pb-2 text-[13.5px]">
          <span><Ltr className="font-semibold tabular-nums">{aed(r.total)}</Ltr> · <Ltr>{fmtDate(r.paid_at, lang)}</Ltr></span>
          {/* A paid receipt is sealed: View / Download work, Replace / Remove say why not (instruction 524).
              The other-language copy stays one click away beside them. */}
          <span className="inline-flex flex-wrap items-center gap-3">
            <DocActions lang={lang} name={'receipt-' + r.id + '.pdf'} sealed="paid_invoice"
              getUrl={async () => { const j = await call('supplier_api', { action: 'receipt_pdf', due_id: r.id, lang: lang === 'ar' ? 'ar' : 'en' }, token); return j && j.ok && j.url ? j.url : null; }} />
            <PdfLinks lang={lang} otherOnly fetchPdf={(l) => call('supplier_api', { action: 'receipt_pdf', due_id: r.id, lang: l }, token)} />
          </span>
        </li>))}</ul>
    </Card>
  );
}

// pdf.js is the bundled pdfjs-dist the customer portal uses (me/pdfRaster.ts), not a runtime script
// from cdnjs: a network that blocks cdnjs made every PDF "unreadable", and the CSP can now drop it.
async function fileToImages(file) {
  const b64 = await fileToB64(file);
  if (file.type && file.type.startsWith('image/')) return { images: [{ mime: file.type, data: b64 }], b64, mime: file.type };
  if (file.type === 'application/pdf') {
    try { const raw = atob(b64); const arr = new Uint8Array(raw.length); for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
      const { rasterisePdf } = await import('@/components/me/pdfRaster');
      return { images: await rasterisePdf(arr), b64, mime: 'application/pdf' };
    } catch (_e) { return { images: [], b64, mime: 'application/pdf' }; }
  }
  return { images: [], b64, mime: file.type || 'application/octet-stream' };
}

const T = {
  en: { brand_sub:'Supplier Portal', home:'Home', signout:'Sign out', loading:'Loading…', loading_dash:'Loading your dashboard…', claiming_listing:'Attaching your company listing to your account…',
    tab_signin:'Sign in', tab_signup:'Create account', welcome_back:'Welcome back', register_title:'Register as a supplier',
    signup_sub:"Enter your work email and we'll create your account — then you'll register your company and verify your mobile.",
    signin_sub:'Sign in with the email or mobile you registered with.', work_email:'Work email', email_or_mobile:'Email or mobile',
    create_my_account:'Create my account', send_code:'Send me a code', sending:'Sending…', code_placeholder:'6-digit code',
    verify_continue:'Verify & continue', verify_signin:'Verify & sign in', verifying:'Verifying…', use_diff:'Use a different email/number',
    junk_note:'The code can take a minute — please check your spam/junk folder too.', err_code_send:'Could not send a code.', err_incorrect:'Incorrect code.',
    signup_email_only:"Please sign up with your work email — you'll register your company and verify your mobile next.",
    signup_email_reserved:'That email domain is reserved for examples and testing and cannot receive mail, so no code can reach it. Please use your real work email.', err_need_email:'Please enter your work email first.', err_need_id:'Please enter your email or mobile number first.',
    conflict_customer:'This email is registered as a customer. Please use the customer app to sign in.',
    setup_title:'Set up your supplier account', setup_sub_company:'Register your company, then complete your profile.', setup_sub_profile:'Complete your profile to start receiving RFQs and submitting quotes.',
    onboard_title:'Register your company', onboard_sub:'Enter your company name and your main trade. Registration is free for the first 1,000 suppliers to register, permanently; from the 1,001st registration it is AED 1,000 per year.', company_name:'Company name', emirate:'Emirate', create_company:'Create company', enter_company:'Enter your company name.', err_generic:'Something went wrong.', something_wrong:'Something went wrong',
    bill_title:'Amounts due', bill_none:'Nothing to pay. You are not charged commission on the work you win.', bill_total:'Total outstanding', bill_pay:'Pay now', bill_paying:'Opening secure checkout…', bill_err:'We could not load your balance. Please try again.', bill_commission:'Refunded amount recovered', bill_fine:'Late fee', bill_due:'Due', bill_retry:'Try again', bill_secure:'You will be redirected to Stripe to pay securely. QuotesDone never sees your card details. These charges arise only when a customer is refunded because we could not reach you \u2014 there is no commission on won work.', t_rfqs:'RFQs', approved:'Approved', pending:'Pending',
    
    
    
    pf_company:'Company', pf_emirates:'Emirates you serve', pf_contact:'Contact & owner', contact_name:'Contact name', mobile:'Mobile',
    mobile_verified:'Mobile verified', verify_my_mobile:'Verify my mobile →', sms_code:'6-digit SMS code', verify:'Verify',
    email_verified:'E-mail verified', email_unverified:'e-mail not yet verified',
    reg_rest_optional:'Attach these two and you are done. Everything else is optional and can wait until you are inside.', verify_first:'Please verify your mobile number first.',
    accept_pre:'I accept the QuotesDone ', terms_link:'supplier terms', accept_post:'.', submit_approval:'Submit for approval', submitting:'Submitting…', must_accept:'Please accept the supplier terms.', loading_rfqs:'Loading RFQs…', no_rfqs_h:'No open RFQs right now', no_rfqs_sub:'When a customer posts a request that matches your capabilities, it appears here.', request_w:'Request', you_won:' · You won', concluded:' · Concluded', quoted:'Quoted ', close:'Close', quote:'Quote', boq_prefix:'BOQ: ', boq_items:'line items', confidence:' confidence', drawing_p:'Drawing p', upload_quote:"Upload your quotation — PDF, photo, Excel, Word, e-mail, CAD or ZIP — and we'll read it:", reading:'Reading…', total_aed:'Total amount (AED)', lead_time:'Lead time (e.g. 10 days)', scope_work:'Scope of work', notes_customer:'Notes for the customer', submit_quote:'Submit quote', enter_valid_amount:'Enter a valid amount.', could_not_read:'Could not read the file — please fill the form.', could_not_submit:'Could not submit.', draft_saved:'Saved as draft — add the missing details to send it.', read_quote_pre:'Read your quotation', line_items:'line items', read_quote_post:'. Review and submit.', loading_docs:'Loading documents…', docs_h:'Documents & certificates', docs_sub:'Upload renewals before they expire — we will remind you here and pause matching if a required document lapses.', st_expired:'Expired', st_expiring:'Expiring soon', st_valid:'Valid', expires_pre:'Expires ', on_file:'On file', not_uploaded:'Not uploaded yet', view:'view', uploading:'Uploading…', upload:'Upload', no_projects_h:'No won projects yet', no_projects_sub:'When a customer reveals and hires you, the project appears here.', project_w:'Project', back:'← Back', send:'Send', ask_placeholder:"Ask a question — our assistant answers instantly, or opens a direct chat if it's really needed.", ask_request:'Ask / request a chat', assistant_pre:'Assistant: ', sent_review:'Sent for review — you will be notified if a chat opens.', sent:'Sent.', registering_pre:'Registering ', registering_post:'. Registration is free for the first 1,000 suppliers to register, permanently; from the 1,001st registration it is AED 1,000 per year.', corrected:' (corrected from your licence)', signatory:'Authorized signatory', owner_dob:'Owner date of birth', h_trade:'Trade licence', trade_sub:'Upload your licence and we read the number, authority, expiry and TRN automatically.', reading_lic:'Reading licence…', lic_no:'Trade licence no.', authority:'Authority (DED / free zone)', lic_expiry:'Licence expiry', vat_trn:'VAT no. (TRN)', h_egr:'Establishment (EGR)', egr_no:'Economic Register (EGR) no.', egr_cert:'EGR / establishment certificate:', h_offer:'What you offer', products_ph:'Products you supply (comma separated)', services_ph:'Services you offer', desc_ph:'Short company description / capabilities', company_profile_pdf:'Company profile (PDF):', catalogs_ph:'Product catalogs (up to 5):', add_contact_phone:'Add your contact name and phone.', add_license:'Add your trade licence number (or upload your licence to auto-fill it).', could_not_save:'Could not save your profile.', save_error:'Something went wrong saving your profile. Please try again.', lic_on_file:'Trade licence on file.', could_not_sms:'Could not send SMS.', wrong_code:'Wrong code.', read_lic:'Read your licence', expires_comma:', expires ', lic_uploaded:'Licence uploaded.', lic_uploaded_noread:'Uploaded (could not auto-read).', attach_file:'Attach file', selected:'selected', lic_expires:'Licence expires', lic_expired:'Licence expired', action_required:'Action required', ar_days_left:'days left to fix this', ar_overdue:'Overdue - your account can be suspended', ar_why:'Why', catalogues:'Catalogues', doc_profile:'Company profile', doc_iso:'ISO certification', add_profile:'Please attach your company profile (required).',
    lic_uploaded_type:'Licence uploaded. If the number did not fill in, type it below — automatic reading is optional.', lic_upload_failed:'We could not store your licence file. Please try again with a PDF or a clear photo.',
    verify_my_email:'Verify my e-mail →', email_code:'6-digit e-mail code', email_sent:'We emailed you a 6-digit code.', could_not_email:'Could not send the e-mail code.',
    trade_label:'Your main trade', trade_ph:'Choose your trade', trade_not_listed:'My trade isn’t listed', trade_other_ph:'Type your trade', trade_help:'Every trade is welcome. If yours isn’t listed, choose “My trade isn’t listed” and type it — we review it and add it.',
    required:'Required', optional:'Optional', mobile_format:'Enter a UAE mobile number, e.g. 050 123 4567 or +971 50 123 4567.', change_mobile:'Use a different number',
    terms_cert_failed:'Your details were saved, but we could not issue your signed acceptance certificate. Please press the button again to retry.',
    catalogs_limit:'Up to 5 catalogues here; add more later from Documents.', catalogs_cut:'Only the first 5 catalogues were kept. Add the rest from Documents after you register.',
    doc_insurance:'Insurance', doc_manufacturer:'Manufacturer authorisation letter', doc_egr:'Establishment card (EGR)',
    
    le_too_many:'Too many code requests. Please try again later.', le_bad_id:'Enter a valid email address or UAE mobile number.', le_suppressed:'We cannot email this address — mail to it bounced or was unsubscribed. Please contact info@quotesdone.com and we will restore it.',
    le_ambiguous:'More than one account uses this mobile number. Please sign in with your email address instead.', le_signup_email:'Please sign up with your email address; you can add your mobile straight afterwards.',
    le_no_account:'This mobile number isn’t linked to a QuotesDone account yet. Sign in with your email, or create your account first.', le_sms_off:'SMS codes are not available for this number. Please sign in with your email.',
    le_enter_code:'Enter the code you received.', le_attempts:'Too many attempts. Please request a new code.', le_expired:'That code has expired. Please request a new one.', le_session:'Could not start your session. Please try again.', le_generic:'Something went wrong. Please try again.',
    main_nav:'Supplier portal sections', account:'Account' },
  ar: { brand_sub:'بوابة المورّدين', home:'الرئيسية', signout:'تسجيل الخروج', loading:'جارٍ التحميل…', loading_dash:'جارٍ تحميل لوحة التحكم…', claiming_listing:'جارٍ ربط سجلّ شركتكم بحسابكم…',
    tab_signin:'تسجيل الدخول', tab_signup:'إنشاء حساب', welcome_back:'أهلًا بعودتكم', register_title:'التسجيل كمورّد',
    signup_sub:'أدخلوا بريدكم الإلكتروني للعمل وسننشئ حسابكم، ثم تسجّلون شركتكم وتؤكّدون رقم جوالكم.',
    signin_sub:'سجّلوا الدخول بالبريد الإلكتروني أو برقم الجوال المسجّل.', work_email:'البريد الإلكتروني للعمل', email_or_mobile:'البريد الإلكتروني أو الجوال',
    create_my_account:'إنشاء حسابي', send_code:'إرسال الرمز', sending:'جارٍ الإرسال…', code_placeholder:'رمز من 6 أرقام',
    verify_continue:'تأكيد ومتابعة', verify_signin:'تأكيد وتسجيل الدخول', verifying:'جارٍ التحقق…', use_diff:'استخدام بريد أو رقم آخر',
    junk_note:'قد يستغرق وصول الرمز دقيقة — يُرجى التحقق من مجلد الرسائل غير المرغوب فيها (Spam) أيضًا.', err_code_send:'تعذّر إرسال الرمز.', err_incorrect:'رمز غير صحيح.',
    signup_email_only:'يُرجى التسجيل ببريدكم الإلكتروني للعمل، ثم تسجيل شركتكم وتأكيد رقم جوالكم في الخطوة التالية.',
    signup_email_reserved:'نطاق هذا البريد محجوز للأمثلة والاختبار ولا يستقبل الرسائل، فلن يصله أي رمز. يُرجى استخدام بريد العمل الحقيقي.', err_need_email:'يُرجى إدخال بريد العمل أولًا.', err_need_id:'يُرجى إدخال بريدكم الإلكتروني أو رقم جوالكم أولًا.',
    conflict_customer:'هذا البريد مسجّل كعميل. يُرجى استخدام تطبيق العملاء لتسجيل الدخول.',
    setup_title:'إنشاء حساب المورّد', setup_sub_company:'سجّلوا شركتكم ثم أكملوا ملف الشركة.', setup_sub_profile:'أكملوا ملف الشركة لتبدأوا استقبال طلبات التسعير وتقديم عروض الأسعار.',
    onboard_title:'تسجيل الشركة', onboard_sub:'أدخلوا اسم شركتكم وتخصصها الرئيسي. التسجيل مجاني لأول 1,000 مورّد يسجّلون، إعفاءً دائمًا؛ واعتبارًا من التسجيل رقم 1,001 تكون الرسوم 1,000 درهم إماراتي سنويًا.', company_name:'اسم الشركة', emirate:'الإمارة', create_company:'إنشاء الشركة', enter_company:'يُرجى إدخال اسم الشركة.', err_generic:'حدث خطأ ما.', something_wrong:'حدث خطأ ما',
    bill_title:'المبالغ المستحقة', bill_none:'لا توجد مبالغ مستحقة، ولا نتقاضى أي عمولة على الأعمال التي تفوزون بها.', bill_total:'إجمالي المستحق', bill_pay:'الدفع الآن', bill_paying:'جارٍ فتح صفحة الدفع الآمنة…', bill_err:'تعذّر تحميل رصيدكم. يُرجى المحاولة مرة أخرى.', bill_commission:'استرداد المبلغ المردود للعميل', bill_fine:'رسوم التأخير', bill_due:'تاريخ الاستحقاق', bill_retry:'إعادة المحاولة', bill_secure:'ستنتقلون إلى صفحة الدفع الآمنة في Stripe، ولا تطّلع QuotesDone على بيانات بطاقتكم. ولا تنشأ هذه المبالغ إلا عند ردّ مبلغ إلى العميل لتعذّر التواصل معكم \u2014 ولا عمولة على الأعمال المنجزة.', t_rfqs:'طلبات التسعير', approved:'معتمد', pending:'قيد المراجعة',
    
    
    
    pf_company:'الشركة', pf_emirates:'الإمارات التي تخدمونها', pf_contact:'جهة الاتصال والمالك', contact_name:'اسم جهة الاتصال', mobile:'الجوال',
    mobile_verified:'تم التحقق من الجوال', verify_my_mobile:'تأكيد رقم الجوال ←', sms_code:'رمز الرسالة (6 أرقام)', verify:'تأكيد',
    email_verified:'تم التحقق من البريد', email_unverified:'لم يتم التحقق من البريد بعد',
    reg_rest_optional:'بإرفاق هذين الملفين يكتمل التسجيل، وكل ما عدا ذلك اختياري ويمكن إكماله بعد الدخول.', verify_first:'يُرجى تأكيد رقم جوالكم أولًا.',
    accept_pre:'أوافق على ', terms_link:'شروط المورّد', accept_post:' في منصة QuotesDone.', submit_approval:'إرسال للموافقة', submitting:'جارٍ الإرسال…', must_accept:'يُرجى الموافقة على شروط المورّد.', loading_rfqs:'جارٍ تحميل طلبات التسعير…', no_rfqs_h:'لا توجد طلبات تسعير مفتوحة حاليًا', no_rfqs_sub:'عندما ينشر عميل طلبًا يطابق إمكانياتكم، يظهر هنا.', request_w:'طلب', you_won:' · فزتم بالطلب', concluded:' · مُغلق', quoted:'قدّمتم عرضًا: ', close:'إغلاق', quote:'تقديم عرض', boq_prefix:'جدول الكميات: ', boq_items:'بند', confidence:' ثقة', drawing_p:'المخطط ص', upload_quote:'حمّلوا عرض السعر (PDF أو صورة أو Excel أو Word أو بريد إلكتروني أو ملف CAD أو ZIP) وسنتولّى قراءته:', reading:'جارٍ القراءة…', total_aed:'المبلغ الإجمالي (درهم)', lead_time:'مدة التنفيذ (مثال: 10 أيام)', scope_work:'نطاق العمل', notes_customer:'ملاحظات للعميل', submit_quote:'إرسال العرض', enter_valid_amount:'يُرجى إدخال مبلغ صحيح.', could_not_read:'تعذّرت قراءة الملف — يُرجى تعبئة النموذج.', could_not_submit:'تعذّر الإرسال.', draft_saved:'حُفظ العرض كمسودة، ويُرجى إضافة التفاصيل الناقصة لإرساله.', read_quote_pre:'قرأنا عرضكم', line_items:'بند', read_quote_post:'. يُرجى مراجعته ثم إرساله.', loading_docs:'جارٍ تحميل المستندات…', docs_h:'المستندات والشهادات', docs_sub:'يُرجى رفع المستندات المجدَّدة قبل انتهاء صلاحيتها؛ سنذكّركم هنا، وتتوقف المطابقة إذا انتهت صلاحية مستند مطلوب.', st_expired:'منتهٍ', st_expiring:'ينتهي قريبًا', st_valid:'سارٍ', expires_pre:'ينتهي في ', on_file:'محفوظ', not_uploaded:'لم يُرفع بعد', view:'عرض', uploading:'جارٍ الرفع…', upload:'رفع', no_projects_h:'لا توجد مشاريع فائزة بعد', no_projects_sub:'عندما يكشف العميل عن عرضكم ويتعاقد معكم، يظهر المشروع هنا.', project_w:'مشروع', back:'→ رجوع', send:'إرسال', ask_placeholder:'اكتبوا سؤالكم، وسيجيب مساعدنا فورًا أو يفتح محادثة مباشرة عند الحاجة.', ask_request:'سؤال أو طلب محادثة', assistant_pre:'المساعد: ', sent_review:'أُرسل للمراجعة، وسنُعلمكم إذا فُتحت محادثة.', sent:'أُرسل.', registering_pre:'تسجيل ', registering_post:'. التسجيل مجاني لأول 1,000 مورّد يسجّلون، إعفاءً دائمًا؛ واعتبارًا من التسجيل رقم 1,001 تكون الرسوم 1,000 درهم إماراتي سنويًا.', corrected:' (مُصحَّح وفق رخصتكم)', signatory:'المفوّض بالتوقيع', owner_dob:'تاريخ ميلاد المالك', h_trade:'الرخصة التجارية', trade_sub:'حمّلوا الرخصة التجارية وسنقرأ منها تلقائيًا رقمها والجهة المُصدِرة وتاريخ الانتهاء والرقم الضريبي.', reading_lic:'جارٍ قراءة الرخصة…', lic_no:'رقم الرخصة التجارية', authority:'الجهة (دائرة التنمية الاقتصادية / منطقة حرة)', lic_expiry:'انتهاء الرخصة', vat_trn:'الرقم الضريبي (TRN)', h_egr:'المنشأة (السجل الاقتصادي)', egr_no:'رقم السجل الاقتصادي (EGR)', egr_cert:'شهادة السجل الاقتصادي / المنشأة:', h_offer:'ما تقدّمونه', products_ph:'المنتجات التي تورّدونها (افصلوا بينها بفاصلة)', services_ph:'الخدمات التي تقدّمونها', desc_ph:'وصف مختصر للشركة / القدرات', company_profile_pdf:'الملف التعريفي للشركة (PDF):', catalogs_ph:'كتالوجات المنتجات (حتى 5):', add_contact_phone:'يُرجى إضافة اسم جهة الاتصال ورقم الهاتف.', add_license:'يُرجى إضافة رقم الرخصة التجارية، أو تحميل الرخصة لتعبئته تلقائيًا.', could_not_save:'تعذّر حفظ ملف الشركة.', save_error:'حدث خطأ أثناء حفظ ملف الشركة. يُرجى المحاولة مرة أخرى.', lic_on_file:'الرخصة التجارية محفوظة.', could_not_sms:'تعذّر إرسال الرسالة.', wrong_code:'رمز خاطئ.', read_lic:'قرأنا رخصتكم', expires_comma:'، تنتهي في ', lic_uploaded:'تم رفع الرخصة.', lic_uploaded_noread:'تم الرفع (تعذّرت القراءة التلقائية).', attach_file:'إرفاق ملف', selected:'محدد', lic_expires:'تنتهي الرخصة', lic_expired:'انتهت الرخصة', action_required:'إجراء مطلوب', ar_days_left:'يوم متبقٍ لمعالجة ذلك', ar_overdue:'تجاوز الموعد — قد يُعلَّق حسابكم', ar_why:'السبب', catalogues:'الكتالوجات', doc_profile:'الملف التعريفي للشركة', doc_iso:'شهادة ISO', add_profile:'يُرجى إرفاق الملف التعريفي للشركة (مطلوب).',
    lic_uploaded_type:'تم رفع الرخصة. إن لم يظهر الرقم تلقائيًا فيُرجى كتابته أدناه، فالقراءة التلقائية اختيارية.', lic_upload_failed:'تعذّر حفظ ملف الرخصة. يُرجى المحاولة مرة أخرى بملف PDF أو صورة واضحة.',
    verify_my_email:'تأكيد البريد الإلكتروني ←', email_code:'رمز البريد (6 أرقام)', email_sent:'أرسلنا إليكم رمزًا من 6 أرقام بالبريد الإلكتروني.', could_not_email:'تعذّر إرسال رمز البريد.',
    trade_label:'التخصص الرئيسي', trade_ph:'اختاروا التخصص', trade_not_listed:'تخصصنا غير مدرج', trade_other_ph:'اكتبوا التخصص', trade_help:'نرحّب بجميع التخصصات. إن لم يكن تخصصكم مدرجًا فاختاروا «تخصصنا غير مدرج» واكتبوه، وسنراجعه ونضيفه.',
    required:'مطلوب', optional:'اختياري', mobile_format:'يُرجى إدخال رقم جوال إماراتي، مثل 050 123 4567 أو ‎+971 50 123 4567.', change_mobile:'استخدام رقم آخر',
    terms_cert_failed:'حُفظت بياناتكم، لكن تعذّر إصدار شهادة القبول الموقّعة. يُرجى الضغط على الزر مرة أخرى لإعادة المحاولة.',
    catalogs_limit:'حتى 5 كتالوجات هنا، ويمكنكم إضافة المزيد لاحقًا من تبويب المستندات.', catalogs_cut:'احتفظنا بأول 5 كتالوجات فقط، ويمكنكم إضافة الباقي من تبويب المستندات بعد التسجيل.',
    doc_insurance:'التأمين', doc_manufacturer:'خطاب تفويض الشركة المصنّعة', doc_egr:'بطاقة المنشأة (EGR)',
    
    le_too_many:'تجاوزتم الحد المسموح من طلبات الرموز. يُرجى المحاولة لاحقًا.', le_bad_id:'يُرجى إدخال بريد إلكتروني صحيح أو رقم جوال إماراتي.', le_suppressed:'لا يمكننا مراسلة هذا البريد، فقد ارتدّت الرسائل المرسلة إليه أو أُلغي اشتراكه. يُرجى التواصل مع info@quotesdone.com لإعادة تفعيله.',
    le_ambiguous:'رقم الجوال هذا مرتبط بأكثر من حساب. يُرجى تسجيل الدخول ببريدكم الإلكتروني.', le_signup_email:'يُرجى التسجيل ببريدكم الإلكتروني، ويمكنكم إضافة رقم الجوال مباشرة بعد ذلك.',
    le_no_account:'رقم الجوال هذا غير مرتبط بعد بحساب في QuotesDone. يُرجى تسجيل الدخول ببريدكم الإلكتروني أو إنشاء حسابكم أولًا.', le_sms_off:'رموز الرسائل النصية غير متاحة لهذا الرقم. يُرجى تسجيل الدخول ببريدكم الإلكتروني.',
    le_enter_code:'يُرجى إدخال الرمز الذي وصلكم.', le_attempts:'تجاوزتم عدد المحاولات المسموح. يُرجى طلب رمز جديد.', le_expired:'انتهت صلاحية الرمز. يُرجى طلب رمز جديد.', le_session:'تعذّر بدء الجلسة. يُرجى المحاولة مرة أخرى.', le_generic:'حدث خطأ. يُرجى المحاولة مرة أخرى.',
    main_nav:'أقسام بوابة المورّدين', account:'الحساب' }
};
const t = (lang, k) => (T[lang] && T[lang][k]) || T.en[k] || k;
// The URL decides the language (14 Sep 2026). /ar/portal must render Arabic and /portal English, the
// same as every other page and the same as the page's own <title>; a remembered localStorage choice
// used to override the URL, so a shared /ar/portal link could open in English.
function initLang(){ try{ if(typeof window==='undefined') return 'en'; return urlLocale(window.location.pathname); }catch(_e){} return 'en'; }
// Typography and chrome carry the platform's voice: display weights are optically
// tightened, body copy keeps a readable measure, and the tab bar is an inset well
// with a RAISED active pill rather than a tinted one — so the current tab reads as
// nearer to the viewer, which is how the rest of the product signals state.
const S = {
  center: 'grid place-items-center min-h-[70vh] p-5',
  h1: 'text-[22px] font-extrabold tracking-[-.03em] text-foreground',
  h2: 'text-[15.5px] font-bold tracking-[-.018em] text-foreground',
  sub: 'text-[13px] leading-[1.65] text-muted-foreground max-w-[68ch]',
  anon: 'ms-1.5 text-[11px] font-semibold text-muted-foreground/80',
  hint: 'text-xs text-muted-foreground my-2 leading-relaxed max-w-[68ch]',
  err: 'text-[13px] text-danger-fg mt-2',
  wrap: 'max-w-[1040px] mx-auto px-[22px] py-7',
  frow: 'flex gap-2.5 flex-wrap mt-2.5',
  tabsWrap: 'qd-tabs inline-flex flex-wrap gap-1 p-1.5',
  tab: 'qd-tab px-3.5 py-2 text-[13px] font-semibold text-muted-foreground cursor-pointer border-0 bg-transparent',
  tabOn: 'qd-tab-on',
  list: 'flex flex-col gap-3',
  section: 'qd-section',
  figure: 'qd-figure',
  field: 'mt-3 flex h-[42px] w-full rounded-md border border-input bg-transparent px-3 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring',
  area: 'mt-3 flex w-full rounded-md border border-input bg-transparent px-3 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring resize-y',
  chip: 'rounded-full border border-border bg-secondary/40 px-3 py-1.5 text-[12.5px] font-semibold text-muted-foreground cursor-pointer',
  chipOn: 'bg-primary/15 border-primary/60 text-primary',
  fileInput: 'text-sm text-muted-foreground file:mr-3 file:rounded-md file:border-0 file:bg-secondary file:px-3 file:py-1.5 file:text-sm file:font-medium file:text-secondary-foreground hover:file:bg-secondary/80',
};

// WHAT THIS COMPANY CAN QUOTE FOR is the Services tab now (15 Sep 2026, sales_engineer):
// ./supplier/ServicesTab.tsx, over supplier_api services_* (docs/api/supplier_portal_services.md). It
// supersedes CapabilityConfirmPanel, which lived here: same confirm, same ledger, services inside trades.

const LANG_NOTE = { en: 'The portal follows your account language. Switching here updates it (EN/AR).', ar: 'تتبع البوابة لغة حسابكم، والتبديل هنا يغيّر لغة الحساب.' };
export function SupplierPortal() {
  const [lang, setLang] = useState('en');
  const [token, setToken] = useState('');
  const switchSupplierLang = (l) => {
    adoptLocale(l, setLang);
    if (token) call('supplier_api', { action: 'save_settings', locale: l }, token)
      .then((j) => { if (!j || !j.ok) console.error('save_settings refused - leads.locale unchanged', j); })
      .catch((e) => console.error('save_settings failed - leads.locale unchanged', e));
  };
  const [phase, setPhase] = useState('login');
  const [mounted, setMounted] = useState(false);
  const [invite, setInvite] = useState(null);
  // THE INVITATION'S TOKEN HAD NOWHERE TO LAND (12 Aug 2026).
  //
  // supplier_api's `claim` action is complete and hardened - it takes body.t, looks the lead up by
  // the unguessable claim_token, refuses a company already claimed by someone else, refuses an
  // account that already manages another company, and sets claimed/claimed_by/portal_updated_at.
  // claim_lookup exists beside it for the "is this your company?" check. NEITHER HAS A SINGLE
  // CALLER: grep for 'claim' across src/components returns nothing, and this portal never read
  // location.search at all.
  //
  // So an invited supplier arriving from their invitation signed up as a stranger. Their directory
  // row - company name, emirate, categories, trades, and now a derived supplier_capabilities record
  // - stayed unclaimed while they retyped it into an empty form. On a cold B2B invite that is the
  // difference between "confirm what we already know about you" and "fill in this form", and
  // leads.claimed is also what stops us inviting the same company again.
  //
  // sessionStorage, not state: the sign-up flow is email -> OTP -> back, and the URL that carried
  // the token is not necessarily the one we return to. Cleared as soon as it is used or refused, so
  // a stale token cannot attach a later, unrelated sign-in to someone else's company.
  const CLAIM_KEY = 'qd-claim-token';
  const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  // THE DASHBOARD RACED THE CLAIM AND SHOWED AN INVITED SUPPLIER A BLANK FORM (21 Sep 2026, walk of
  // the campaign registration). The dashboard was warmed and mounted in the same tick the claim was
  // sent, and the claim takes ~5.8 s (measured on production, lead 126711). The dashboard answered
  // no_company, Onboarding read `me` before the claim landed, and the supplier who had just been told
  // "this listing is reserved for your company" was shown an empty "Register your company" form —
  // nothing re-read once the claim completed. Both mount paths (stored token AND getSession) also
  // sent the claim, so it went twice. Now: one claim per page, the dashboard waits for it, and the
  // warm-up it discarded is started again with the claimed company in place.
  // Prevented by scripts/checks/an_invited_supplier_can_finish_registering.test.mjs.
  const [claiming, setClaiming] = useState(false);
  const claimRun = useRef(null);
  const claimIfInvited = (access) => {
    let t = '';
    try { t = sessionStorage.getItem(CLAIM_KEY) || ''; } catch (_e) {}
    if (!UUID_RE.test(t) || !access) return null;
    if (claimRun.current) return claimRun.current;
    setClaiming(true);
    claimRun.current = (async () => {
      try {
        // A failure here must never block the portal: the supplier can still register manually, which
        // is exactly what everyone has had to do until now.
        await call('supplier_api', { action: 'claim', t }, access);
      } catch (_e) { /* claim is an improvement on the flow, not a gate into it */ }
      try { sessionStorage.removeItem(CLAIM_KEY); } catch (_e) {}
      drop(); warmSupplier(access);   // what was warmed was asked before the company was claimed
      setClaiming(false);
    })();
    return claimRun.current;
  };
  // THE SUPPLIER'S REGISTERED LANGUAGE WINS ONCE SIGNED IN (founder, 14 Sep 2026). The portal took its
  // language from the URL alone, so a supplier registered in Arabic who opened an English link worked
  // in English while every notice reached them in Arabic. leads.locale decides; Settings changes it.
  useEffect(() => {
    if (phase !== 'app' || !token) return;
    call('supplier_api', { action: 'settings' }, token).then((j) => {
      const l = j && j.ok && j.settings ? j.settings.locale : null;
      if (l === 'ar' || l === 'en') adoptLocale(l, setLang);   // leads.locale, as the customer portal applies customers.locale
      else if (!(j && j.ok)) console.error('supplier settings unavailable - portal language left as the URL gives it', j);
    }).catch((e) => console.error('supplier settings failed - portal language left as the URL gives it', e));
  }, [phase, token]);
  useEffect(() => {
    setMounted(true);
    try { setLang(initLang()); } catch (_e) {}
    // Capture ?t= before anything else can navigate away from it.
    //
    // AND RESOLVE IT TO A COMPANY NAME (13 Aug 2026). The invitation is addressed "Dear Al Ain Glass
    // & Mirrors Factory L.L.C." and the page it links to opened on a generic marketing hero with a
    // sign-in box headed "Welcome back" — to someone who by definition has no account. claim_lookup
    // exists for exactly this check, is public by design, takes only the unguessable token, and had
    // no caller anywhere in src/. 81 invitations sent, 0 registrations. The token is already in the
    // URL; naming the company costs one request and turns "who are you and why should I sign up"
    // into "this is your listing, claim it".
    try {
      const t = new URLSearchParams(window.location.search).get('t') || '';
      if (UUID_RE.test(t)) {
        sessionStorage.setItem(CLAIM_KEY, t);
        call('claim_lookup', { t }).then((j) => { if (j && j.ok) setInvite(j); }).catch(() => {});
      }
    } catch (_e) {}
    try { const th = localStorage.getItem('qd-theme'); if (th === 'light' || th === 'dark') setTheme(th); } catch (_e) {}
    // A magic-link session in the URL is taken out of it in place and signs in (audit 21 Sep, item 29).
    const urlSession = takeAuthFragment();
    if (urlSession) onAuth(urlSession.access_token, urlSession.refresh_token);
    else try { const tk = localStorage.getItem('qd-sup-token'); if (tk) { warmSupplier(tk); setToken(tk); setPhase('app'); claimIfInvited(tk); } } catch (_e) {}
    if (!urlSession) try { SB().auth.getSession().then(({ data }) => { const ss = data.session; if (ss && ss.access_token) { setToken(ss.access_token); try { localStorage.setItem('qd-sup-token', ss.access_token); if (ss.refresh_token) localStorage.setItem('qd-sup-refresh', ss.refresh_token); } catch (_e) {} warmSupplier(ss.access_token); setPhase('app'); claimIfInvited(ss.access_token); } }).catch(() => {}); } catch (_e) {}
    // THE HOUR MARK (14 Sep 2026). supabase-js refreshes the access token on schedule, and nothing here
    // listened — the customer portal learned this on 13 Aug; the supplier portal still sent the token
    // captured at mount, so after 60 minutes every tab answered "Something went wrong". One listener,
    // moving forward only: SIGNED_OUT carries no token and is not a refresh failure.
    let sub;
    try { sub = SB().auth.onAuthStateChange((_evt, ss) => { const at = ss && ss.access_token; if (!at) return; setToken(at); try { localStorage.setItem('qd-sup-token', at); if (ss.refresh_token) localStorage.setItem('qd-sup-refresh', ss.refresh_token); } catch (_e) {} }); } catch (_e) {}
    return () => { try { sub && sub.data && sub.data.subscription && sub.data.subscription.unsubscribe(); } catch (_e) {} };
  }, []);
  // The root element, not only this div, carries the language: it is what a screen reader reads.
  // Audit 21 Sep 2026, finding 41: the <title> and skip link are written once by the server layout,
  // so a client-side switch left an English tab title over an Arabic portal until a reload.
  useEffect(() => { applyDocumentLocale(lang); applyShellChrome(lang, 'portal'); }, [lang]);
  // Light/dark is a per-device choice, the same key and the same .osx[data-theme] palette as the
  // customer portal (globals.css). The supplier portal had no control for it at all.
  const [theme, setTheme] = useState('dark');
  const swapTheme = () => { const next = theme === 'dark' ? 'light' : 'dark'; try { localStorage.setItem('qd-theme', next); } catch (_e) {} setTheme(next); };
  const onAuth = (access, refresh, locale) => { adoptLocale(locale, setLang); try { localStorage.setItem('qd-sup-token', access || ''); if (refresh) localStorage.setItem('qd-sup-refresh', refresh); } catch (_e) {} setToken(access || ''); if (access) warmSupplier(access); setPhase('app'); if (access) { try { SB().auth.setSession({ access_token: access, refresh_token: refresh || '' }).catch(() => {}); } catch (_e) {} claimIfInvited(access); } };
  const doSignOut = () => { try { localStorage.removeItem('qd-sup-token'); localStorage.removeItem('qd-sup-refresh'); } catch (_e) {} setToken(''); setPhase('login'); try { SB().auth.signOut().catch(() => {}); } catch (_e) {} };
  // A 401 from the dashboard: try the stored refresh token once, and only if that fails send the
  // supplier back to sign-in — never leave them on a retry button that cannot succeed.
  const onExpired = async () => {
    try { const { data } = await SB().auth.refreshSession(); const ss = data && data.session; if (ss && ss.access_token) { onAuth(ss.access_token, ss.refresh_token); return; } } catch (_e) {}
    doSignOut();
  };
  const rtl = lang === 'ar';
  if (!mounted) return null;
  return (
    // No inline font (14 Sep 2026). The root set fontFamily 'Inter, system-ui, sans-serif'; Inter is
    // not loaded anywhere (public/fonts holds 11 woff2, none Inter; document.fonts showed 0 faces on
    // /supplier), so the portal rendered in the OS fallback and the Arabic portal lost Tajawal. It now
    // inherits the layout's var(--font-body) / var(--font-head), the same faces as the homepage.
    <div dir={rtl ? 'rtl' : 'ltr'} lang={lang} data-theme={theme} className="osx min-h-screen bg-background text-foreground">
      <header className="qd-topbar sticky top-0 z-10 flex items-center justify-between gap-2 px-4 sm:px-5 py-3 bg-card/70 backdrop-blur-xl border-b border-border">
        {/* whitespace-nowrap + the sub-label hidden below sm: at 375px "QuotesDone / SUPPLIER / PORTAL"
            wrapped to three lines beside the buttons (audit mobile screenshot). */}
        <a className="group flex min-w-0 items-center gap-2.5 whitespace-nowrap text-[15px] font-extrabold text-foreground no-underline font-[family-name:var(--font-head)]" href={rtl ? '/ar' : '/'}>
          <BrandMark className="h-7 w-7 shrink-0 transition-transform duration-500 group-hover:rotate-[8deg]" />
          <span>QuotesDone <span className="hidden sm:inline font-mono text-[10.5px] font-semibold uppercase tracking-[0.18em] text-primary align-middle">{t(lang, 'brand_sub')}</span></span>
        </a>
        <div className="flex gap-2 items-center shrink-0">
          <Button variant="outline" size="sm" lang={lang === 'ar' ? 'en' : 'ar'} title={token ? LANG_NOTE[lang === 'ar' ? 'ar' : 'en'] : undefined} onClick={() => switchSupplierLang(lang === 'ar' ? 'en' : 'ar')}>{lang === 'ar' ? 'EN' : 'عربي'}</Button>
          <Button variant="outline" size="sm" onClick={swapTheme} aria-pressed={theme === 'light'} aria-label={theme === 'dark' ? (rtl ? 'الوضع الفاتح' : 'Light mode') : (rtl ? 'الوضع الداكن' : 'Dark mode')} title={theme === 'dark' ? (rtl ? 'الوضع الفاتح' : 'Light mode') : (rtl ? 'الوضع الداكن' : 'Dark mode')}><span aria-hidden>{theme === 'dark' ? '☀' : '☾'}</span></Button>
          <Button asChild variant="outline" size="sm" className="hidden sm:inline-flex"><a href={rtl ? '/ar' : '/'}>{t(lang, 'home')}</a></Button>
          {phase === 'app' && <Button variant="outline" size="sm" onClick={doSignOut}>{t(lang, 'signout')}</Button>}
        </div>
      </header>
      {/* id="main", not "qd-portal-main": the skip link the layout renders before the header points
          at #main (app/[locale]/layout.tsx), and on 18 Sep 2026 it pointed at nothing here — the id
          it had was referenced by no CSS, no script and no test, so the first focusable element on
          the supplier portal did nothing at all. */}
      <main id="main">
      {!mounted ? <div className={S.center}>{t(lang, 'loading')}</div> : (<>
        {/* An invited supplier is told whose listing this is, before anything else on the page. */}
        {phase === 'login' && invite && <InviteBanner invite={invite} lang={lang} onStart={() => { try { document.getElementById('qd-supplier-signin')?.scrollIntoView({ behavior: 'smooth', block: 'center' }); } catch (_e) {} }} />}
        {/* §1 — the supplier meets the product before the sign-in box, not after it. */}
        {phase === 'login' && <SupplierEntryHero lang={lang} onStart={() => { try { document.getElementById('qd-supplier-signin')?.scrollIntoView({ behavior: 'smooth', block: 'center' }); } catch (_e) {} }} />}
        {phase === 'login' && <div id="qd-supplier-signin"><Login onAuth={onAuth} lang={lang} startMode={invite && invite.claimable ? 'signup' : 'signin'} /></div>}
        {phase === 'app' && (claiming
          ? <div className={S.center} aria-busy="true" role="status">{t(lang, 'claiming_listing')}</div>
          : <Dashboard token={token} lang={lang} onExpired={onExpired} />)}
      </>)}
      </main>
    </div>
  );
}
// WHOSE LISTING THIS IS. Rendered only when the URL carried a valid invitation token that
// claim_lookup resolved. `already_claimed` is a real outcome, not an error: a colleague at the same
// company may have registered first, and telling them that is better than a sign-up form that fails
// at the end with "This company is already claimed by another account."
function InviteBanner({ invite, lang, onStart }) {
  const ar = lang === 'ar';
  const name = invite.company_name || (ar ? 'شركتكم' : 'your company');
  const taken = !invite.claimable;
  return (
    <section className="mx-auto w-full max-w-3xl px-4 pt-6" dir={ar ? 'rtl' : 'ltr'}>
      <Card className="qd-panel p-5">
        <div className="text-[11px] uppercase tracking-[0.18em] text-primary">
          {ar ? 'دعوة شخصية' : 'Your invitation'}
        </div>
        {/* dir="auto" — a Latin company name inside an RTL page otherwise renders its trailing
            "L.L.C." punctuation on the wrong side. */}
        <div dir="auto" className="mt-1.5 text-[19px] font-extrabold leading-tight text-foreground">{name}</div>
        {invite.emirate ? <div className={cn(S.sub, 'mt-0.5')}>{invite.emirate}</div> : null}
        <div className={cn(S.sub, 'mt-3 max-w-[62ch]')}>
          {taken
            ? (ar ? 'هذه الشركة مسجّلة مسبقًا في QuotesDone. إن كان أحد زملائكم قد سجّلها فيُرجى أن تطلبوا منه إضافتكم، أو سجّلوا الدخول بالبريد الذي استُخدم في التسجيل.'
                  : 'This company is already registered on QuotesDone. If a colleague claimed it, ask them to add you — or sign in with the email they used.')
            : (ar ? 'هذا السجل محجوز لشركتكم، فبياناتكم متوفرة لدينا من السجل التجاري العام. لن تملؤوا نموذجًا فارغًا، بل تصحّحون ما لدينا وتؤكّدونه. أنشئوا حسابكم للمطالبة به.'
                  : 'This listing is reserved for your company. We already hold your details from the public trade directory — you are not filling in a blank form, you are correcting what we have and confirming it. Create your account to claim it.')}
        </div>
        {!taken && <Button className="mt-4" onClick={onStart}>{ar ? 'المطالبة بسجل الشركة' : 'Claim my listing'}</Button>}
      </Card>
    </section>
  );
}
// login_otp answers with English sentences and no code (read 15 Sep 2026), and the form printed them
// raw on /ar/portal. The known sentences map to EN/AR keys; anything unknown is a generic message plus
// the HTTP status, never untranslated English on an Arabic page.
const LOGIN_ERR = [
  [/too many code requests/i, 'le_too_many'], [/valid (email address or uae )?mobile|valid email address/i, 'le_bad_id'],
  [/do-not-send list/i, 'le_suppressed'], [/more than one quotesdone account/i, 'le_ambiguous'],
  [/cannot create an account from a mobile/i, 'le_signup_email'], [/isn't linked|no account is registered/i, 'le_no_account'],
  [/sms (sign-in is not enabled|codes are not available)/i, 'le_sms_off'], [/could not send the (sms|email)/i, 'err_code_send'],
  [/enter the code/i, 'le_enter_code'], [/too many (incorrect )?attempts/i, 'le_attempts'], [/has expired/i, 'le_expired'],
  [/incorrect or expired/i, 'err_incorrect'], [/could not start your session/i, 'le_session'],
];
export const loginErr = (lang, j, fallbackKey) => {
  const e = String((j && j.error) || '');
  if (!e) return t(lang, fallbackKey);
  const hit = LOGIN_ERR.find(([re]) => re.test(e));
  return hit ? t(lang, hit[1]) : t(lang, 'le_generic') + (j && j._http ? ' (' + j._http + ')' : '');
};
function Login({ onAuth, lang, startMode }) {
  const [mode, setMode] = useState(startMode === 'signup' ? 'signup' : 'signin'); const [step, setStep] = useState('id'); const [id, setId] = useState(''); const [code, setCode] = useState(''); const [ident, setIdent] = useState(''); const [msg, setMsg] = useState(''); const [busy, setBusy] = useState(false);
  const isSignup = mode === 'signup';
  // claim_lookup resolves after mount, so startMode arrives late and cannot be a useState initial
  // value. Flip to sign-up when the invitation lands, unless the supplier has already chosen a tab
  // themselves — a link that only ever reaches someone without an account should not open on
  // "Welcome back", but it must not override a deliberate choice either.
  const swapped = useRef(false);
  useEffect(() => { if (startMode === 'signup' && !swapped.current) setMode('signup'); }, [startMode]);
  // An empty press says so, and a sign-up address is checked for shape AND for reserved names that
  // can never receive a code (src/lib/signupEmail.ts; audit 21 Sep 2026, items 26 and 28).
  const send = async () => { const v = id.trim(); if (!v) { setMsg(t(lang, isSignup ? 'err_need_email' : 'err_need_id')); return; } if (isSignup) { const p = signupEmailProblem(v); if (p) { setMsg(t(lang, p)); return; } } setBusy(true); setMsg('');
    try { const g = await call('role_guard', { user_kind: 'supplier', identifier: v }); if (g && g.conflict === 'customer') { setBusy(false); setMsg(t(lang, 'conflict_customer')); return; } } catch (_e) {}
    let j; try { j = await call('login_otp', { action: 'send', user_kind: 'supplier', identifier: v, allow_signup: isSignup, lang }); } catch (_e) { setBusy(false); setMsg(t(lang, 'err_code_send')); return; } setBusy(false); if (j && j.ok) { setIdent(j.identifier || v); setStep('code'); } else setMsg(loginErr(lang, j, 'err_code_send')); };
  const verify = async () => { if (!code.trim()) return; setBusy(true); setMsg(''); let j; try { j = await call('login_otp', { action: 'verify', user_kind: 'supplier', identifier: ident, code: code.trim() }); } catch (_e) { setBusy(false); setMsg(t(lang, 'err_incorrect')); return; } if (!j || !j.ok || !j.access_token) { setBusy(false); setMsg(loginErr(lang, j, 'err_incorrect')); return; } setBusy(false); onAuth(j.access_token, j.refresh_token, j.locale); };
  const swap = (m) => { swapped.current = true; setMode(m); setStep('id'); setMsg(''); setCode(''); };
  return (
    <div className={S.center}><Card className="qd-login qd-panel w-full max-w-[410px] p-6 sm:p-7">
      <div className="mb-5 flex flex-col items-center text-center">
        <span className="qd-brandbadge mb-4 grid h-12 w-12 place-items-center rounded-2xl"><BrandMark className="h-6 w-6" /></span>
        <h1 className={cn(S.h1, 'qd-grad-text font-[family-name:var(--font-head)]')}>{isSignup ? t(lang, 'register_title') : t(lang, 'welcome_back')}</h1>
        <div className={cn(S.sub, 'mx-auto mt-2')}>{isSignup ? t(lang, 'signup_sub') : t(lang, 'signin_sub')}</div>
      </div>
      <div className={cn(S.tabsWrap, 'mb-4 flex w-full')}><button className={cn(S.tab, 'flex-1', !isSignup && S.tabOn)} onClick={() => swap('signin')}>{t(lang, 'tab_signin')}</button><button className={cn(S.tab, 'flex-1', isSignup && S.tabOn)} onClick={() => swap('signup')}>{t(lang, 'tab_signup')}</button></div>
      {step === 'id' ? (<>
        <Lbl text={isSignup ? t(lang, 'work_email') : t(lang, 'email_or_mobile')}><Input className="mt-3" autoComplete={isSignup ? 'email' : 'username'} dir="ltr" placeholder={isSignup ? t(lang, 'work_email') : t(lang, 'email_or_mobile')} value={id} onChange={(e) => setId(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && send()} /></Lbl>
        <Button className="w-full mt-3" disabled={busy} onClick={send}>{busy ? t(lang, 'sending') : (isSignup ? t(lang, 'create_my_account') : t(lang, 'send_code'))}</Button>
      </>) : (<>
        <Lbl text={t(lang, 'code_placeholder')}><Input className="mt-3" inputMode="numeric" autoComplete="one-time-code" dir="ltr" placeholder={t(lang, 'code_placeholder')} value={code} onChange={(e) => setCode(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && verify()} /></Lbl>
        <div className={S.hint}>{t(lang, 'junk_note')}</div>
        <Button className="w-full mt-3" disabled={busy} onClick={verify}>{busy ? t(lang, 'verifying') : (isSignup ? t(lang, 'verify_continue') : t(lang, 'verify_signin'))}</Button>
        <Button variant="link" className="mt-2 px-0 h-auto" onClick={() => { setStep('id'); setCode(''); setMsg(''); }}>{t(lang, 'use_diff')}</Button>
      </>)}
      {msg && <div className={S.err}>{msg}</div>}
    </Card></div>
  );
}
// THE DASHBOARD IS A JOURNEY, NOT 24 TABS (14 Sep 2026).
//
// It had 24 equal tabs; on a 375x812 phone the strip alone was 366px tall and the one action that
// unlocks every RFQ sat 2,547px down (measurements recorded in CapabilityConfirmPanel). Now: the
// overview is "Get matched" (the eligibility payload as a progress ring and checklist), then the core
// work — RFQs, Quotes, Projects, Messages, Documents, Billing — and ONE Insights section that lists only
// the intelligence panels whose routine has something to show. Profile, scope and settings are account
// links; the checklist sends the supplier to whichever one is next. The strip scrolls sideways rather
// than wrapping, so on a phone it is one row.
//
// 15 SEP 2026, THE FOUNDER'S ORDER: Services, Inquiries received, Quotations submitted, Messages,
// Documents, Insights; Profile, Billing and Settings in an account menu. The "Get matched" overview was
// dropped ("drop it"): its alerts are the bell, its registration checklist heads the Documents tab, and its
// tiles, funnel and price position are the Insights tab. Projects (revealed jobs) fold into Messages.
// Services is ./supplier/ServicesTab (#722: the services checklist inside the confirmed trades) and is the landing tab.
// Old keys still resolve through go(): overview/scope -> services, projects -> messages, inbox -> rfqs.
const MAIN_TABS = ['services', 'rfqs', 'quotes', 'messages', 'documents', 'insights'];
const ACCOUNT_TABS = ['profile', 'billing', 'settings'];
const TAB_ALIAS = { overview: 'services', scope: 'services', projects: 'messages', inbox: 'rfqs' };
// A NEW AGREEMENT VERSION IS ACCEPTED AGAIN ON THE NEXT SIGN-IN (14 Sep 2026, agent: sales_engineer).
// The founder approved Supplier Agreement v11. Clause 23 says a material change is re-confirmed, and until
// now nothing compared a supplier's accepted_terms_version with the live one, so a supplier who accepted v10
// would have gone on working under v11 without ever seeing it. A supplier who has accepted SOME version but
// not the current one sees this card instead of the dashboard until they accept. A supplier who has never
// accepted is in onboarding, which already asks. The record is written by supplier_api accept_terms (time,
// server-read version, IP, text hash) and kyc accept_terms issues the signed acceptance certificate.
// What each version changed, in the supplier's language. A supplier is shown every change after the version it
// accepted (a v10 supplier re-accepting v12 sees v11's and v12's). v12, 14 Sep 2026, founder: "whatsapp number
// supplier confirmed." Archived versions are the ones with a /supplier-agreement/vN page.
export const ARCHIVED_AGREEMENTS = ['v10', 'v11'];
const AGREEMENT_CHANGES = {
  11: {
    en: [
      'Notices may also reach you by WhatsApp and SMS on your registered mobile, alongside email and the portal (clause 21).',
      'The Arabic text of the agreement is the one that counts for all purposes, including in court (clause 22).',
      'The non-response charge is a fixed amount once our notice is issued, and the AED 250 fee is agreed compensation under the Civil Transactions Law (clause 33).',
      'Our licence is described exactly as DET issued it: Trader License No. 1633275.',
    ],
    ar: [
      'قد تصلكم الإشعارات أيضًا عبر واتساب والرسائل النصية على رقم هاتفكم المحمول المسجَّل، إلى جانب البريد الإلكتروني والبوابة (البند 21).',
      'النص العربي للاتفاقية هو المعتمد لجميع الأغراض، بما في ذلك أمام المحاكم (البند 22).',
      'رسم عدم الاستجابة مبلغ ثابت متى صدر إشعارنا، والرسم الإداري البالغ 250 درهمًا تعويض متفق عليه وفق قانون المعاملات المدنية (البند 33).',
      'وصف رخصتنا مطابق لما صدر عن دائرة الاقتصاد والسياحة: رخصة تاجر رقم 1633275.',
    ],
  },
  12: {
    en: ['WhatsApp notices go to the WhatsApp number you confirm in the portal with a verification code, or to your registered mobile if you confirm it is your WhatsApp. SMS stays on your registered mobile (clause 21).'],
    ar: ['تصلكم إشعارات واتساب على رقم الواتساب الذي تؤكّدونه في البوابة برمز تحقق، أو على رقم هاتفكم المحمول المسجَّل إذا أكّدتم أنه رقمكم على واتساب. وتبقى الرسائل النصية على رقم هاتفكم المحمول المسجَّل (البند 21).'],
  },
};
export function agreementChanges(accepted, current, ar) {
  const n = (v) => Number(String(v || '').replace(/\D/g, '')) || 0;
  const from = n(accepted), to = n(current);
  return Object.keys(AGREEMENT_CHANGES).map(Number).sort((a, b) => a - b)
    .filter((v) => v > from && v <= to).flatMap((v) => AGREEMENT_CHANGES[v][ar ? 'ar' : 'en']);
}
export function needsReaccept(me) {
  return !!(me && me.accepted_terms_at && me.terms_current && me.accepted_terms_version !== me.terms_current);
}
function ReacceptTerms({ token, lang, me, onDone }) {
  const ar = lang === 'ar'; const pre = ar ? '/ar' : '';
  const [ok, setOk] = useState(false); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const accept = async () => {
    if (!ok) { setMsg(t(lang, 'must_accept')); return; }
    setBusy(true); setMsg('');
    const j = await call('supplier_api', { action: 'accept_terms' }, token).catch(() => null);
    if (!j || !j.ok) { setBusy(false); setMsg(t(lang, 'err_generic')); return; }
    try { await call('kyc', { action: 'accept_terms' }, token); } catch (_e) { /* the acceptance is recorded; the certificate is retried by kyc's own trail */ }
    setBusy(false); onDone();
  };
  const changes = agreementChanges(me.accepted_terms_version, me.terms_current, ar);
  // The version this supplier accepted stays readable at /supplier-agreement/vN for every archived version.
  const prev = ARCHIVED_AGREEMENTS.includes(me.accepted_terms_version) ? me.accepted_terms_version : null;
  return (
    <div className={S.center}>
      <Card className="qd-panel max-w-[600px] p-5" dir={ar ? 'rtl' : 'ltr'}>
        <div className={S.h2}>{ar ? `تحديث اتفاقية المورّد — الإصدار ${me.terms_current}` : `The Supplier Agreement has been updated — version ${me.terms_current}`}</div>
        <div className={cn(S.sub, 'mt-2')}>{ar ? `قبلتم الإصدار ${me.accepted_terms_version || '—'}. يُرجى قراءة الإصدار الجديد وقبوله لمتابعة استخدام البوابة. ما الذي تغيّر:` : `You accepted version ${me.accepted_terms_version || '—'}. Please read the new version and accept it to keep using the portal. What changed:`}</div>
        <ul className="mt-3 flex list-disc flex-col gap-1.5 ps-5 text-[13px] text-foreground">{changes.map((c) => <li key={c}>{c}</li>)}</ul>
        <div className="mt-3 flex flex-wrap gap-4 text-[13px]">
          <a className="font-medium text-primary underline" href={pre + '/supplier-agreement/'} target="_blank" rel="noopener">{ar ? 'اقرأ الإصدار الجديد' : 'Read the new version'}</a>
          {prev ? <a className="text-muted-foreground underline" href={pre + '/supplier-agreement/' + prev + '/'} target="_blank" rel="noopener">{ar ? `الإصدار الذي قبلتموه (${prev})` : `The version you accepted (${prev})`}</a> : null}
        </div>
        <label className="mt-4 flex items-center gap-2 text-[13px] text-muted-foreground"><input type="checkbox" checked={ok} onChange={(e) => setOk(e.target.checked)} /> {ar ? `قرأتُ اتفاقية المورّد (الإصدار ${me.terms_current}) وأوافق عليها.` : `I have read and accept Supplier Agreement version ${me.terms_current}.`}</label>
        {msg ? <div className="mt-2 text-[13px] text-destructive" role="alert">{msg}</div> : null}
        <Button className="mt-4" disabled={busy} onClick={accept}>{busy ? t(lang, 'submitting') : (ar ? 'أوافق وأتابع' : 'Accept and continue')}</Button>
      </Card>
    </div>
  );
}
// A NATIVE <details> IS A DISCLOSURE, AND A POPOVER IS EXPECTED TO CLOSE (a11y review, 18 Sep 2026).
// `<details>` gives us keyboard operation and a second-press close for free, which is why the bell and
// the Account menu below use it. What it does NOT give is the two things everyone tries on a panel
// floating over the page: Escape, and clicking away from it. The customer portal's own bell has both
// (src/components/me/PortalShell.tsx: a keydown listener and a full-viewport backdrop button); these two
// had neither, so a supplier who opened the Account menu and changed their mind was left with it pinned
// open over the tab strip. Nine lines, once, for both.
function useDismissablePopover() {
  const ref = useRef(null);
  useEffect(() => {
    const shut = () => {
      const d = ref.current;
      if (!d || !d.open) return false;
      d.open = false;
      return true;
    };
    const onKey = (e) => { if (e.key === 'Escape' && shut()) { const s = ref.current.querySelector('summary'); if (s) s.focus(); } };
    const onDown = (e) => { if (ref.current && !ref.current.contains(e.target)) shut(); };
    document.addEventListener('keydown', onKey);
    document.addEventListener('pointerdown', onDown);
    return () => { document.removeEventListener('keydown', onKey); document.removeEventListener('pointerdown', onDown); };
  }, []);
  return ref;
}
// THE BELL (15 Sep 2026). One list of what is waiting for this supplier, fed by what the dashboard call
// already carries: unread customer messages, quotes held for exact details, and the overview alerts
// (new RFQs, draft quotes, expiring documents). Each item opens the tab where it is dealt with. A native
// <details> is the popover: it opens with the keyboard and closes on a second press with no script.
function NotificationBell({ ov, lang, go }) {
  const ar = lang === 'ar'; const n = ov.notifications || {};
  const msgs = n.unread_messages || 0; const holds = n.spec_holds || 0; const alerts = ov.alerts || [];
  const items = [
    msgs ? { k: 'm', tab: 'messages', text: ar ? `${msgs} ${msgs === 1 ? 'رسالة غير مقروءة' : 'رسائل غير مقروءة'} من العملاء` : `${msgs} unread customer message${msgs > 1 ? 's' : ''}` } : null,
    holds ? { k: 'h', tab: 'quotes', text: ar ? `${holds} ${holds === 1 ? 'عرض محجوز' : 'عروض محجوزة'} بانتظار تفاصيل دقيقة` : `${holds} quote${holds > 1 ? 's' : ''} held for exact details` } : null,
    ...alerts.map((a, i) => ({ k: 'a' + i, tab: a.action === 'documents' ? 'documents' : a.kind === 'draft_quote' ? 'quotes' : 'rfqs', text: itemCopy(lang, a).title })),
  ].filter(Boolean);
  // WHAT THE ESTATE TOLD THIS SUPPLIER (audit 21 Sep 2026, finding 6): a customer revealing this
  // supplier's quote changed nothing on the bell. Every notice carries a SUPPLIER-portal tab, never a
  // URL (finding 5: the only link a supplier had was the e-mail's, which opened the customer portal),
  // and a notice counts on the badge until the bell is opened once (the newest id seen is remembered).
  const notices = (n.notices || []).filter((x) => MAIN_TABS.includes(x.tab)).slice(0, 8);
  const [seen, setSeen] = useState(() => { try { return Number(localStorage.getItem('qd-sup-notice-seen') || 0); } catch (_e) { return 0; } });
  const fresh = notices.filter((x) => x.id > seen).length;
  const markSeen = () => { const top = notices.length ? notices[0].id : 0; if (top > seen) { setSeen(top); try { localStorage.setItem('qd-sup-notice-seen', String(top)); } catch (_e) {} } };
  const badge = items.length + fresh;
  const label = ar ? `الإشعارات (${badge})` : `Notifications (${badge})`;
  const ref = useDismissablePopover();
  const when = (at) => { try { return new Date(at).toLocaleDateString(ar ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short' }); } catch (_e) { return ''; } };
  return (
    <details ref={ref} className="relative" onToggle={(e) => { if (e.currentTarget.open) markSeen(); }}>
      <summary aria-label={label} title={label} className="relative inline-flex min-h-11 min-w-11 cursor-pointer list-none items-center justify-center rounded-md border border-border text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring [&::-webkit-details-marker]:hidden">
        <Bell aria-hidden className="h-[18px] w-[18px]" />
        {badge ? <span aria-hidden className="absolute -top-1 -end-1 rounded-full bg-primary px-1.5 py-0.5 text-[10px] font-bold leading-none text-primary-foreground tabular-nums">{badge}</span> : null}
      </summary>
      <div className="qd-panel absolute end-0 z-20 mt-2 w-[min(320px,calc(100vw-32px))] p-1.5">
        {items.length ? <ul>{items.map((it) => (
          <li key={it.k}><button type="button" className="flex min-h-11 w-full items-center rounded-md px-3 py-2.5 text-start text-[13px] text-foreground hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            onClick={(e) => { const d = e.currentTarget.closest('details'); if (d) d.open = false; go(it.tab); }}>{it.text}</button></li>))}</ul>
          : (fresh ? null : <div className="px-3 py-2.5 text-[13px] text-muted-foreground">{ar ? 'لا شيء جديد.' : 'Nothing new.'}</div>)}
        {notices.length ? <div className="mt-1 border-t border-border pt-1">
          <div className="px-3 py-1.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{ar ? 'آخر الإشعارات' : 'Recent notices'}</div>
          <ul>{notices.map((x) => (
            <li key={'n' + x.id}><button type="button" className="flex min-h-11 w-full items-center justify-between gap-3 rounded-md px-3 py-2 text-start text-[13px] text-foreground hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              onClick={(e) => { const d = e.currentTarget.closest('details'); if (d) d.open = false; go(x.tab); }}>
              <span className={x.id > seen ? 'font-semibold' : ''}>{srvText(lang, 'notice_' + x.type, {}, srvText(lang, 'notice_quote', {}, ''))}</span>
              <span className="shrink-0 text-[11px] text-muted-foreground">{when(x.at)}</span></button></li>))}</ul>
        </div> : null}
      </div>
    </details>
  );
}
// THE ACCOUNT MENU (15 Sep 2026): Profile, Billing and Settings, out of the main tabs. A native
// <details>, like the bell: keyboard-operable and closed by a second press with no script.
function AccountMenu({ tab, labels, lang, go }) {
  const on = ACCOUNT_TABS.includes(tab);
  const ref = useDismissablePopover();
  return (
    <details ref={ref} className="relative">
      <summary className={cn('inline-flex min-h-11 cursor-pointer list-none items-center gap-1.5 rounded-md border border-border px-3 text-[13px] font-semibold focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring [&::-webkit-details-marker]:hidden', on ? 'text-primary' : 'text-muted-foreground hover:text-foreground')}>
        {ws(lang, 'account_menu')}{on ? <span className="font-normal"> · {labels[tab]}</span> : null}<span aria-hidden>▾</span>
      </summary>
      <ul className="qd-panel absolute end-0 z-20 mt-2 w-48 p-1.5">
        {ACCOUNT_TABS.map((k) => (
          <li key={k}><button type="button" aria-current={tab === k ? 'page' : undefined}
            className={cn('flex min-h-11 w-full items-center rounded-md px-3 text-start text-[13px] hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring', tab === k ? 'font-semibold text-primary' : 'text-foreground')}
            onClick={(e) => { const d = e.currentTarget.closest('details'); if (d) d.open = false; go(k); }}>{labels[k]}</button></li>
        ))}
      </ul>
    </details>
  );
}
function Dashboard({ token, lang, onExpired }) {
  const ar = lang === 'ar';
  const [ov, setOv] = useState(null); const [tab, setTab] = useState('services'); const [err, setErr] = useState('');
  const [panel, setPanel] = useState(null); const [receipt, setReceipt] = useState(null);
  // Which record a card opened: an RFQ by inquiry id (from Quotes), a chat by inquiry id (from Projects).
  const [focusRfq, setFocusRfq] = useState(null);
  // The one-time WhatsApp question for suppliers registered before it existed (founder, 14 Sep 2026).
  // Holds the kyc state while the card is due, null otherwise. It never blocks a tab.
  const [waPrompt, setWaPrompt] = useState(null);
  useEffect(() => { call('kyc', { action: 'state' }, token).then((k) => { if (waNeedsPrompt(k)) setWaPrompt(k); }).catch(() => {}); }, [token]);
  // Which agreement version this supplier accepted, against the live one (supplier_api me).
  const [me, setMe] = useState(null);
  useEffect(() => { call('supplier_api', { action: 'me' }, token).then((j) => setMe((j && j.supplier) || null)).catch(() => {}); }, [token]);
  // ONE call (supplier_portal `dashboard`): stats, alerts, eligibility, document impact and the bell's
  // counts. It was three, the second wave starting only after the first rendered. `first` takes the
  // request warmSupplier started with the token; every later load asks fresh.
  // Only the latest request may write: an older answer arriving late must not overwrite a newer one.
  const seq = useRef(0);
  // busy-exempt: the affordance is the absence of `ov` — the dashboard renders its aria-busy
  // redaction-bar card until this resolves, and resolves into `err` on failure. A second flag here
  // would be a second source of truth for the same state. (docs/CONVENTIONS_LOADING.md)
  const load = async (first = false) => { const n = ++seq.current; const j = await (first ? take(token, DASH_KEY, () => fetchDashboard(token)) : fetchDashboard(token)); if (n !== seq.current) return; if (j && j.ok) setOv(j); else if (j && j._http === 401 && onExpired) onExpired(); else setErr((j && (j.code || j.error)) || 'load_err'); };
  useEffect(() => { load(true); }, [token]);
  // On leaving Messages only the bell's counts are read again (two reads, not the whole dashboard), so
  // the badge drops once the thread was read.
  const prevTab = useRef(tab);
  useEffect(() => {
    if (prevTab.current === 'messages' && tab !== 'messages') {
      const n = seq.current;
      call('supplier_portal', { action: 'notifications' }, token).then((j) => { if (j && j.ok && n === seq.current) setOv((o) => (o ? { ...o, notifications: j.notifications } : o)); }).catch(() => {});
    }
    prevTab.current = tab;
  }, [tab, token]);
  useEffect(() => {
    // Stripe's return (see ReceiptBanner). Read once, then removed so a reload does not re-announce it.
    try {
      const q = new URLSearchParams(window.location.search);
      const d = q.get('dues_paid'); const r = q.get('registration_paid');
      if (d || r) {
        setReceipt({ kind: d ? 'dues' : 'registration', ref: String(d || r) }); setTab('billing');
        q.delete('dues_paid'); q.delete('registration_paid');
        const s = q.toString(); window.history.replaceState(null, '', window.location.pathname + (s ? '?' + s : ''));
      }
    } catch (_e) {}
  }, []);
  // THE SWITCH WINDOW (18 Sep 2026). Pressing a tab said nothing at all on this side, while the
  // customer's tabs get a ModuleLoading skeleton. Each supplier tab owns its own fetch, so the parent
  // cannot see a child's data arrive — but it CAN see what the press costs: useDeferredValue keeps the
  // panel already on screen while the new tab renders at low priority, and `switching` is exactly that
  // render, which on a phone is the whole of a heavy tab's mount. The redaction bars sit ABOVE the
  // still-mounted old panel rather than replacing it — replacing it would unmount the child and restart
  // the very fetch being waited on — and appear only past 150ms (busy.tsx rule 1), so a light tab
  // never flashes them.
  const shownTab = useDeferredValue(tab);
  const switching = shownTab !== tab;
  const switchBars = useDelayedFlag(switching);
  // Every panel's goTo(...) lands here. Old tab keys still resolve: 'inbox' is the RFQs list, and the
  // intelligence keys open their panel inside Insights.
  const go = (k) => {
    if (MAIN_TABS.includes(k) || ACCOUNT_TABS.includes(k)) { setTab(k); return; }
    if (TAB_ALIAS[k]) { setTab(TAB_ALIAS[k]); return; }
    if (INSIGHT_PANELS.includes(k)) { setPanel(k); setTab('insights'); return; }
    setTab('services');
  };
  if (err === 'no_company') return <Onboarding token={token} lang={lang} onDone={() => { setErr(''); load(); }} />;
  if (err) return <div className={S.center}><Card className="qd-panel max-w-[460px] p-5"><div className={S.h2}>{t(lang, 'something_wrong')}</div><div className={S.sub}>{t(lang, 'err_generic')}</div><Button className="mt-3" onClick={() => { setErr(''); load(); }}>{t(lang, 'bill_retry')}</Button></Card></div>;
  if (needsReaccept(me)) return <ReacceptTerms token={token} lang={lang} me={me} onDone={() => setMe({ ...me, accepted_terms_version: me.terms_current })} />;
  if (!ov) return <div className={S.center} aria-busy="true">{t(lang, 'loading_dash')}</div>;
  const unread = (ov.notifications && ov.notifications.unread_messages) || 0;
  const TAB = { services: ws(lang, 'tab_services'), rfqs: ws(lang, 'tab_rfqs'), quotes: ws(lang, 'tab_quotes'), messages: ws(lang, 'tab_messages'), documents: ws(lang, 'tab_documents'), insights: ws(lang, 'tab_insights'), profile: ws(lang, 'acct_profile'), billing: ws(lang, 'acct_billing'), settings: ws(lang, 'acct_settings') };
  const stBadge = (() => {
    // AUDIT 6.5(d): action_required is NOT pending — a clock is running that ends in rejection.
    const st = ov.supplier.approval_status;
    if (st === 'action_required') {
      const due = ov.supplier.exception_due_at ? new Date(ov.supplier.exception_due_at) : null;
      const days = due ? Math.ceil((due.getTime() - Date.now()) / 864e5) : null;
      const when = days === null ? '' : (days <= 0 ? ' · ' + t(lang, 'ar_overdue') : ' · ' + days + ' ' + t(lang, 'ar_days_left'));
      return <Badge variant="destructive">{t(lang, 'action_required') + when}</Badge>;
    }
    return <Badge variant={st === 'approved' ? 'ok' : 'warn'}>{st === 'approved' ? t(lang, 'approved') : t(lang, 'pending')}</Badge>;
  })();
  return (
    <div className={S.wrap}>
      {waPrompt && <div className="mb-5"><WhatsAppChoice token={token} lang={lang} mode="prompt" current={waPrompt.whatsapp} mobile={waPrompt.phone} onDone={() => setWaPrompt(null)} /></div>}
      <div className="mb-5 flex flex-col gap-3">
        <div>
          <div className="flex items-center justify-between gap-3"><Kicker>{t(lang, 'brand_sub')}</Kicker><div className="flex items-center gap-2"><NotificationBell ov={ov} lang={lang} go={go} /><AccountMenu tab={tab} labels={TAB} lang={lang} go={go} /></div></div>
          <h1 dir="auto" className="mt-2.5 font-head text-[24px] sm:text-[30px] font-semibold tracking-snug text-foreground">{ov.supplier.company_name}</h1>
          <div className="flex items-center gap-2 mt-1.5 flex-wrap">
            {stBadge}
            {ov.supplier.approval_status === 'action_required' && ov.supplier.licence_gate_reason
              ? <span className="text-[13px] text-destructive font-medium basis-full">{t(lang, 'ar_why') + ': ' + srvText(lang, ov.supplier.licence_gate_reason, {}, ov.supplier.licence_gate_reason)}</span> : null}
            {ov.supplier.license_expiry ? (() => { const days = Math.round((new Date(ov.supplier.license_expiry) - new Date()) / 864e5); const v = days < 0 ? 'destructive' : days <= 30 ? 'warn' : 'secondary'; return <Badge variant={v}>{(days < 0 ? t(lang, 'lic_expired') : t(lang, 'lic_expires')) + ' · '}<Ltr>{fmtDate(ov.supplier.license_expiry, lang)}</Ltr></Badge>; })() : null}
          </div>
        </div>
        {/* EVERY SECTION NAME IS ON SCREEN (founder, 14 Sep 2026: navigation must read as text).
            This strip used to be flex-nowrap inside overflow-x-auto, so at 375px only the first
            two and a half names were visible and the rest sat off-screen with no hint they existed.
            It wraps now, and every control is at least 44px tall for a thumb. */}
        <nav aria-label={t(lang, 'main_nav')}>
          <div className={cn(S.tabsWrap, 'flex')}>
            {MAIN_TABS.map((k) => <button key={k} type="button" aria-current={tab === k ? 'page' : undefined} className={cn(S.tab, 'min-h-11 whitespace-nowrap focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring', tab === k && S.tabOn)} onClick={() => setTab(k)}>{k === 'rfqs' ? TAB.rfqs + (ov.active_matches ? ' (' + ov.active_matches + ')' : '') : k === 'messages' && unread ? <>{TAB[k]} <span className="ms-1 rounded-full bg-primary px-1.5 py-0.5 text-[10px] font-bold text-primary-foreground tabular-nums">{unread}</span><span className="sr-only">{ar ? ' رسائل غير مقروءة' : ' unread'}</span></> : TAB[k]}</button>)}
          </div>
        </nav>
      </div>
      <SupplierCommandPalette tabs={[...MAIN_TABS, ...ACCOUNT_TABS]} labels={TAB} onGo={go} lang={lang} />
      {/* aria-busy sits on the INCOMING skeleton, not on the wrapper: the previous tab under it
          is still valid, rendered content, and marking it busy tells assistive tech to ignore
          something that is not stale. The status node is what announces the switch. */}
      <div>
      <span className="sr-only" role="status" aria-live="polite">{switching ? (ar ? "جارٍ التحميل" : "Loading") : ""}</span>
      {switchBars && <Card aria-busy className="qd-panel mb-3 p-5"><Skeleton className="w-1/3" /><Skeleton className="mt-3" /><Skeleton className="mt-2 w-2/3" /></Card>}
      {shownTab === 'services' && <ServicesTab token={token} lang={lang} goTo={go} />}
      {/* THE TAB THAT IS ON ITS WAY OUT MUST NOT EAT THE FOCUS THE NEXT ONE WAS SENT (18 Sep 2026).
          `focusRfq` is one token that BOTH tabs read and BOTH clear through onFocused. That was fine
          while the panels rendered on `tab`, because setFocusRfq(id) and setTab(...) commit together
          and the old panel is gone in the same render. Since #736 they render on `shownTab`, a
          useDeferredValue of `tab` — so after "Send your quotation to the sales engineer" runs
          setFocusRfq(id); setTab('quotes'), InquiriesTab is STILL MOUNTED for at least one commit,
          now holding the new focus. Its own focus effect fires, opens that inquiry again, and calls
          onFocused() — which clears focusRfq. QuotationsTab then mounts with focus=null and opens
          nothing, so the supplier lands on a list of collapsed jobs instead of the review
          conversation they just asked for. Measured on production 18 Sep 2026: it failed in all four
          matrices (en/ar x desktop/phone) of scripts/e2e/supplier_quote_review.mjs, every one of them
          timing out waiting for the sales engineer's first line, with the capture showing the
          Quotations submitted list and every job shut. Same shape in the other direction
          (openInquiry, quotes -> rfqs).
          The guard is `switching`: while shownTab has not caught up with tab, the panel on screen is
          the OUTGOING one and the focus is not addressed to it, so it may act on it but may not
          consume it. One condition, both directions, and nothing about the deferred render changes. */}
      {shownTab === 'rfqs' && <InquiriesTab token={token} lang={lang} focus={focusRfq} onFocused={() => { if (!switching) setFocusRfq(null); }} onQuote={(id) => { setFocusRfq(id); setTab('quotes'); }}
        renderQuoteForm={(inq, done) => <QuoteForm inquiry={inq} token={token} lang={lang} onDone={done} />} />}
      {shownTab === 'quotes' && <QuotationsTab token={token} lang={lang} focus={focusRfq} onFocused={() => { if (!switching) setFocusRfq(null); }} openInquiry={(id) => { setFocusRfq(id); setTab('rfqs'); }} />}
      {/* Messages holds the revealed jobs (Projects) above the conversations, behind the reveal gate. */}
      {shownTab === 'messages' && <SupplierMailbox token={token} lang={lang} goTo={go}
        jobs={(open) => <Projects token={token} lang={lang} openChat={open} />} />}
      {/* The registration checklist heads Documents, next to the uploads it asks for; after an upload the
          dashboard is read again so the checklist and document impact reflect the new file. */}
      {shownTab === 'documents' && <>
        <GetMatched token={token} lang={lang} go={go} initial={ov.eligibility || null} />
        <div className="mb-4"><SupplierDocumentImpact token={token} lang={lang} goTo={go} initial={ov.document_impact || null} /></div>
        <Documents token={token} lang={lang} onSaved={load} />
        <div className="mt-4"><SupplierSupportingDocuments token={token} lang={lang} /></div>
      </>}
      {shownTab === 'insights' && <Insights token={token} lang={lang} goTo={go} initial={panel} />}
      {shownTab === 'profile' && <ProfilePanel token={token} lang={lang} initial={me} onSaved={load} />}
      {shownTab === 'billing' && <BillingPanel token={token} lang={lang} receipt={receipt} />}
      {shownTab === 'settings' && <SupplierSettings token={token} lang={lang} onLang={(l) => adoptLocale(l, setLang)} />}
      </div>
    </div>
  );
}
// Label above figure, not below: the eye lands on the number, and the label is
// already read by then. Figures are tabular so a row of KPIs aligns on the digit.
function QuoteForm({ inquiry, token, onDone, lang, initialItems = null, quote = null, newOption = false }) {
  // An existing quote (a held draft, or one already sent) reopens with what was sent, lines included.
  // `quote` names one option to edit; `newOption` starts another option, which is its own quotation.
  const q0 = quote || (newOption ? {} : inquiry.quote || {});
  const optionArgs = newOption ? { new_option: true } : (q0.option_no ? { option_no: q0.option_no } : {});
  // VAT (founder, 14 Sep 2026): the customer compares and pays on the price EXCLUDING VAT, and never
  // sees the supplier's VAT details. The supplier says how the total is stated; if it includes VAT,
  // they give the ex-VAT figure.
  const VAT_BASIS = ['exclusive', 'inclusive', 'not_registered'];
  // A quote sent with an ex-VAT figure is stored as 'confirmed_on_portal' (vat.ts), which is none of
  // the three choices, so the select reopened on "Choose…" (audit 21 Sep 2026, finding 35). The
  // stated amount above the ex-VAT figure says it was VAT-inclusive; equal, VAT-exclusive.
  const vat0 = VAT_BASIS.includes(q0.vat_treatment) ? q0.vat_treatment
    : q0.vat_treatment === 'confirmed_on_portal' && Number(q0.price_ex_vat) > 0
      ? (Number(q0.amount_as_stated) > Number(q0.price_ex_vat) + 0.5 ? 'inclusive' : 'exclusive') : '';
  const [vat, setVat] = useState(vat0);
  const [exVat, setExVat] = useState(vat0 === 'inclusive' && q0.price_ex_vat != null ? String(q0.price_ex_vat) : '');
  const lines0 = initialItems && initialItems.length ? initialItems
    : (Array.isArray(q0.items) && q0.items.length ? q0.items.map((r) => ({ description: r.description || '', qty: r.qty == null ? '' : String(r.qty), unit: r.unit || '', unit_price: r.unit_price == null ? '' : String(r.unit_price) })) : [{ description: '', qty: '', unit: '', unit_price: '' }]);
  const [amount, setAmount] = useState(vat0 === 'inclusive' && Number(q0.amount_as_stated) > 0 ? String(q0.amount_as_stated) : q0.quote_amount != null ? String(q0.quote_amount) : ''); const [lead, setLead] = useState(q0.lead_time || ''); const [notes, setNotes] = useState(q0.notes || ''); const [scope, setScope] = useState(q0.scope || ''); const [validity, setValidity] = useState(q0.validity || ''); const [payment, setPayment] = useState(q0.payment_terms || ''); const [warranty, setWarranty] = useState(q0.warranty || ''); const [items, setItems] = useState(lines0); const [msg, setMsg] = useState(''); const [busy, setBusy] = useState(false);
  const [reading, setReading] = useState(false); const [prop, setProp] = useState(null); const [orig, setOrig] = useState(null);
  const onFile = async (file) => { if (!file) return; setReading(true); setMsg(''); try { const { images, b64, mime } = await fileToImages(file); const j = await call('supplier_api', { action: 'extract_quote', inquiry_id: inquiry.id, images, original: { b64, filename: file.name, mime } }, token); if (j && j.ok && j.proposal) { const pr = j.proposal; setProp(pr); setOrig({ path: j.original_file_path, name: j.original_file_name }); const amt = pr.total != null ? pr.total : (pr.amount != null ? pr.amount : (pr.grand_total != null ? pr.grand_total : '')); if (amt !== '' && amt != null) setAmount(String(amt)); if (pr.lead_time) setLead(pr.lead_time); if (pr.scope || pr.description_anonymized) setScope(pr.scope || pr.description_anonymized); if (pr.notes) setNotes(pr.notes); if (VAT_BASIS.includes(pr.vat_treatment)) setVat(pr.vat_treatment); setMsg(t(lang, 'read_quote_pre') + (pr.line_items ? ' — ' + pr.line_items.length + ' ' + t(lang, 'line_items') : '') + t(lang, 'read_quote_post') + (pr.options && pr.options.length > 1 ? ' ' + srvText(lang, 'options_split', { count: pr.options.length }) : '')); } else setMsg(srvMsg(lang, j, t(lang, 'could_not_read'))); } catch (_e) { setMsg(t(lang, 'could_not_read')); } setReading(false); };
  const [chk, setChk] = useState(null); const [checking, setChecking] = useState(false);
  const vatArgs = { vat_treatment: vat || undefined, price_ex_vat: vat === 'inclusive' && Number(exVat) > 0 ? Number(exVat) : undefined };
  const buildPayload = () => prop ? { action: 'submit_quote', inquiry_id: inquiry.id, amount: Number(amount), lead_time: lead, notes, scope, conditions: prop.conditions || '', exclusions: prop.exclusions || '', validity: validity || prop.validity || '', payment_terms: payment || prop.payment_terms || '', warranty: warranty || prop.warranty || '', items: prop.line_items || [], masked_terms: prop.masked_terms || null, source: 'upload', original_file_path: orig && orig.path, original_file_name: orig && orig.name, subtotal: prop.subtotal ?? undefined, vat_amount: prop.vat_amount ?? undefined, trn: prop.trn ?? undefined, option_totals: prop.option_totals || undefined, ...vatArgs, ...optionArgs } : { action: 'submit_quote', inquiry_id: inquiry.id, amount: Number(amount), lead_time: lead, notes, scope, validity, payment_terms: payment, warranty, items: items.filter((x) => (x.description || '').trim()), source: 'form', ...vatArgs, ...optionArgs };
  // Preflight. submit_quote accepts dry_run: it runs the REAL scorer and the REAL accept rule,
  // then stops — no status change, no customer notification, and deliberately no coaching email,
  // because fn_quote_coach queues mail that must not fire while someone is mid-edit.
  //
  // This is the gap the product had. Feedback only ever arrived AFTER a quote was accepted, by
  // email, hours later. And "accepted" was never the whole story: every quote on the platform
  // today passes through the form_complete branch at a score of 65 while the structured scorer
  // says submittable=false — so they reach customers without per-item pricing or brand/model,
  // which is exactly what the comparison depends on. accept_via makes that visible here instead.
  const check = async () => {
    if (!(Number(amount) > 0)) { setMsg(t(lang, 'enter_valid_amount')); return; }
    setChecking(true); setMsg(''); setChk(null);
    const j = await call('supplier_api', { ...buildPayload(), dry_run: true }, token);
    setChecking(false);
    if (j && j.ok) setChk(j.options ? { ...j.options[0], options: j.options } : j); else setMsg(srvMsg(lang, j, t(lang, 'could_not_submit')));
  };
  const submit = async () => {
    if (!(Number(amount) > 0)) { setMsg(t(lang, 'enter_valid_amount')); return; }
    setBusy(true); setMsg('');
    const j = await call('supplier_api', buildPayload(), token);
    setBusy(false);
    // Accepted, held by the sales engineer (the card then shows exactly what is missing and the two
    // ways out) or split into options: the card is the next thing the supplier needs to see.
    if (j && j.ok && (j.accepted || j.held || j.options)) onDone({ held: !!j.held && !j.accepted });
    else if (j && j.ok) setMsg(srvMsg(lang, j, t(lang, 'draft_saved')));
    else setMsg(srvMsg(lang, j, t(lang, 'could_not_submit')));
  };
  const ar = lang === 'ar';
  // Presentation only: the sum of what the supplier typed into priced lines, so the totals row can sit
  // beside the quoted total. It is never sent; `amount` stays the figure the supplier entered.
  const lineSum = items.reduce((acc, x) => { const q = Number(x.qty), p = Number(x.unit_price); return acc + (q > 0 && p > 0 ? q * p : 0); }, 0);
  const grp = 'font-mono text-label uppercase tracking-caps text-muted-foreground';
  return <div className="mt-5 flex flex-col gap-4 rounded-panel border border-border bg-background/40 p-4 sm:p-5">
    <div className="flex gap-2.5 flex-wrap items-center"><span className={cn(S.sub, 'font-semibold')}>{t(lang, 'upload_quote')}</span><FilePick lang={lang} accept={QUOTE_ACCEPT} onPick={(fl) => fl && onFile(fl)} />{reading && <span className={S.sub}>{t(lang, 'reading')}</span>}</div>
    <div className={cn(grp, 'border-t border-border pt-4')}>{ar ? 'السعر والشروط' : 'Price and terms'}</div>
    <div className="flex gap-2.5 flex-wrap -mt-2"><Lbl className="flex-1" text={t(lang, 'total_aed')}><Input className="tabular font-mono text-[15px]" inputMode="decimal" placeholder={t(lang, 'total_aed')} value={amount} onChange={(e) => setAmount(e.target.value)} /></Lbl><Lbl className="flex-1" text={t(lang, 'lead_time')}><Input placeholder={t(lang, 'lead_time')} value={lead} onChange={(e) => setLead(e.target.value)} /></Lbl></div>
    <div className="flex gap-2.5 flex-wrap">
      <Lbl className="flex-1 min-w-[200px]" visible text={ar ? 'الإجمالي أعلاه' : 'The total above'}>
        <select className="h-9 w-full rounded-md border border-input bg-background px-2 text-[13px]" value={vat} onChange={(e) => setVat(e.target.value)}>
          <option value="">{ar ? 'يُرجى الاختيار: هل يشمل ضريبة القيمة المضافة؟' : 'Choose: does it include VAT?'}</option>
          <option value="exclusive">{ar ? 'غير شامل ضريبة القيمة المضافة' : 'Excludes VAT'}</option>
          <option value="inclusive">{ar ? 'شامل ضريبة القيمة المضافة' : 'Includes VAT'}</option>
          <option value="not_registered">{ar ? 'لسنا مسجلين في ضريبة القيمة المضافة' : 'We are not VAT-registered'}</option>
        </select></Lbl>
      {vat === 'inclusive' ? <Lbl className="flex-1 min-w-[200px]" visible text={ar ? 'السعر غير شامل الضريبة (درهم)' : 'Price excluding VAT (AED)'}><Input className="tabular font-mono" inputMode="decimal" value={exVat} onChange={(e) => setExVat(e.target.value)} /></Lbl> : null}
    </div>
    <div className={S.sub}>{ar ? 'يقارن العميل ويدفع على السعر غير شامل الضريبة، ولا تُعرض عليه تفاصيل الضريبة ولا رقمكم الضريبي.' : 'The customer compares and pays on the price excluding VAT; your VAT details and TRN are never shown to them.'}</div>
    <div className="flex gap-2.5 flex-wrap">{[[validity, setValidity, lang === 'ar' ? 'صلاحية العرض (مثلاً 30 يومًا)' : 'Quote validity (e.g. 30 days)'], [payment, setPayment, lang === 'ar' ? 'شروط الدفع (مثلاً 50% مقدمًا)' : 'Payment terms (e.g. 50% advance)'], [warranty, setWarranty, lang === 'ar' ? 'الضمان (مثلاً سنة واحدة)' : 'Warranty (e.g. 1 year)']].map(([v, sv, ph], k) => <Lbl key={k} className="flex-1 min-w-[160px]" text={ph}><Input placeholder={ph} value={v} onChange={(e) => sv(e.target.value)} /></Lbl>)}</div>
    <div className="border-t border-border pt-4">
      <div className={cn(grp, 'mb-1')}>{ar ? 'بنود العرض' : 'Line items'}</div>
      <div className={cn(S.sub, 'mb-2')}>{lang === 'ar' ? 'بنود العرض (الوصف والكمية والسعر)، وبها يصبح عرضكم جاهزًا للإرسال' : 'Quote items (description, qty, price) — makes your quote ready to send'}</div>
      <div className="overflow-x-auto"><div className="min-w-[460px]">
      {items.map((it, ix) => (<div key={ix} className="flex gap-1.5 mb-1.5 items-center">
        <Lbl className="flex-1" text={(lang === 'ar' ? 'الوصف، البند ' : 'Description, line ') + (ix + 1)}><Input placeholder={lang === 'ar' ? 'الوصف' : 'Description'} value={it.description} onChange={(e) => setItems(items.map((r, i) => i === ix ? { ...r, description: e.target.value } : r))} /></Lbl>
        <Lbl text={(lang === 'ar' ? 'الكمية، البند ' : 'Quantity, line ') + (ix + 1)}><Input className="tabular font-mono text-end" style={{ maxWidth: 72 }} inputMode="decimal" placeholder={lang === 'ar' ? 'كمية' : 'Qty'} value={it.qty} onChange={(e) => setItems(items.map((r, i) => i === ix ? { ...r, qty: e.target.value } : r))} /></Lbl>
        <Lbl text={(lang === 'ar' ? 'الوحدة، البند ' : 'Unit, line ') + (ix + 1)}><Input style={{ maxWidth: 72 }} placeholder={lang === 'ar' ? 'وحدة' : 'Unit'} value={it.unit} onChange={(e) => setItems(items.map((r, i) => i === ix ? { ...r, unit: e.target.value } : r))} /></Lbl>
        <Lbl text={(lang === 'ar' ? 'سعر الوحدة، البند ' : 'Unit price, line ') + (ix + 1)}><Input className="tabular font-mono text-end" style={{ maxWidth: 104 }} inputMode="decimal" placeholder={lang === 'ar' ? 'سعر الوحدة' : 'Unit price'} value={it.unit_price} onChange={(e) => setItems(items.map((r, i) => i === ix ? { ...r, unit_price: e.target.value } : r))} /></Lbl>
        <Button size="sm" variant="outline" aria-label={(lang === 'ar' ? 'حذف البند ' : 'Remove line ') + (ix + 1)} onClick={() => setItems(items.length > 1 ? items.filter((_, i) => i !== ix) : [{ description: '', qty: '', unit: '', unit_price: '' }])}>×</Button>
      </div>))}
      </div></div>
      <div className="mt-1 flex flex-wrap items-center justify-between gap-2">
        <Button size="sm" variant="outline" onClick={() => setItems([...items, { description: '', qty: '', unit: '', unit_price: '' }])}>{lang === 'ar' ? '+ إضافة بند' : '+ Add item'}</Button>
        {lineSum > 0 && <div className="flex items-baseline gap-3 rounded-chip border border-border px-3 py-1.5">
          <span className={grp}>{ar ? 'مجموع البنود المسعّرة' : 'Sum of priced lines'}</span>
          <span className="tabular font-mono text-[14px] font-semibold text-foreground">{aed(lineSum)}</span>
        </div>}
      </div>
    </div>
    <div className={cn(grp, 'border-t border-border pt-4 -mb-2')}>{ar ? 'النطاق والملاحظات' : 'Scope and notes'}</div>
    <Lbl text={t(lang, 'scope_work')}><textarea className={S.area} placeholder={t(lang, 'scope_work')} value={scope} onChange={(e) => setScope(e.target.value)} rows={2} /></Lbl>
    <Lbl text={t(lang, 'notes_customer')}><textarea className={S.area} placeholder={t(lang, 'notes_customer')} value={notes} onChange={(e) => setNotes(e.target.value)} rows={2} /></Lbl>
    {chk && <QuoteCheck chk={chk} lang={lang} />}
    <div className="flex gap-2 items-center flex-wrap justify-end border-t border-border pt-4">
      <Button size="sm" variant="secondary" disabled={checking || busy || reading} onClick={check}>
        {checking ? (lang === 'ar' ? 'جارٍ الفحص…' : 'Checking…') : (lang === 'ar' ? 'الفحص قبل الإرسال' : 'Check before sending')}
      </Button>
      <Button size="sm" disabled={busy || reading} onClick={submit}>{busy ? t(lang, 'submitting') : t(lang, 'submit_quote')}</Button>
    </div>
    {msg && <div className={cn(S.sub, 'mt-1.5')}>{msg}</div>}
  </div>;
}
// Result of the dry_run preflight.
//
// Two things are shown that the product never surfaced before sending:
//   1. the structured score against the 70 pass mark, and
//   2. WHY the quote would be accepted — because passing via `form_complete` at 65 is not the
//      same as passing the quality bar, and telling a supplier only "this will send" hides that
//      their quote reaches the customer without per-item pricing or brand/model.
// Missing codes come straight from fn_quote_structured_score, so this panel and the email a
// supplier might receive later cannot disagree with each other.
function QuoteCheck({ chk, lang }) {
  const ar = lang === 'ar';
  const sc = chk.score || {}; const pts = sc.score ?? 0; const pass = 70;
  const missing = Array.isArray(sc.missing) ? sc.missing : [];
  const viaForm = chk.accept_via === 'form_complete' && !chk.submittable;
  return (
    <Card className="qd-panel p-4 mt-1">
      <div className="flex justify-between items-baseline gap-3 flex-wrap">
        <div className="text-[13.5px] font-bold text-foreground">{ar ? 'جاهزية العرض' : 'Quote readiness'}</div>
        <div className="text-[13px] font-bold tabular-nums text-foreground">{pts}<span className="text-muted-foreground font-semibold">/100</span></div>
      </div>
      <div className="mt-1.5 h-2 rounded-full bg-secondary/50 overflow-hidden relative">
        <div className={cn('h-full rounded-full transition-[width] duration-700 motion-reduce:transition-none', pts >= pass ? 'bg-primary' : 'bg-warn')}
             style={{ width: Math.max(2, Math.min(100, pts)) + '%' }} />
        {/* the 70 pass mark, shown so the number has meaning */}
        <div className="absolute top-0 bottom-0 w-px bg-foreground/40" style={{ left: pass + '%' }} aria-hidden="true" />
      </div>
      {/* A quote below 70 can still be sent (accept_via form_complete), so 70 is the QUALITY mark, not a
          pass mark: "Pass mark is 70" beside "This will be sent" read as a contradiction (audit 21 Sep 2026, finding 15). */}
      <div className={cn(S.sub, 'mt-1.5')}>{ar ? 'علامة الجودة 70 — العرض الأقوى للمقارنة' : 'Quality mark is 70 — the strongest quotes to compare'}</div>

      {chk.would_accept
        ? <div className="mt-2.5">
            <Badge variant={chk.submittable ? 'ok' : 'warn'}>{viaForm ? (ar ? 'سيُرسل إلى العميل — دون علامة الجودة' : 'This will be sent to the customer — below the quality mark') : (ar ? 'سيُرسل إلى العميل' : 'This will be sent to the customer')}</Badge>
            {viaForm && <div className={cn(S.sub, 'mt-1.5')}>{ar
              ? 'سيُقبل لأن الحقول الأساسية مكتملة، لكنه لم يبلغ علامة الجودة. وإضافة ما يلي تجعل عرضكم أسهل للمقارنة وأقوى أمام العميل.'
              : 'It is accepted because the essential fields are filled, but it has not reached the quality mark. Adding the items below makes your quote easier to compare and stronger against competing bids.'}</div>}
          </div>
        : <div className="mt-2.5">
            <Badge variant="destructive">{ar ? 'سيُحفظ كمسودة' : 'This will be saved as a draft'}</Badge>
            <div className={cn(S.sub, 'mt-1.5')}>{ar ? 'لن يصل إلى العميل حتى تُكملوا ما يلي.' : 'It will not reach the customer until the items below are added.'}</div>
          </div>}

      {!!missing.length && <ul className="mt-2.5 flex flex-col gap-1">
        {missing.map((m, i) => <li key={i} className="flex items-start gap-2">
          <span className="mt-[7px] h-1.5 w-1.5 rounded-full bg-warn shrink-0" />
          <span className="text-[13px] text-foreground">{missingLabel(lang, m)}</span>
        </li>)}
      </ul>}
      {!missing.length && !(chk.spec_missing && chk.spec_missing.length) && <div className={cn(S.sub, 'mt-2.5')}>{ar ? 'لا ينقص شيء. عرض مكتمل.' : 'Nothing missing — this is a complete quote.'}</div>}
      {Array.isArray(chk.spec_missing) && chk.spec_missing.length > 0 && <div className="mt-2.5 border-t border-border pt-2.5">
        <div className="text-[13px] font-semibold text-foreground">{ar ? 'سيُعلّق مهندس المبيعات العرض حتى تُذكر هذه التفاصيل الدقيقة:' : 'The sales engineer will hold this quote until these exact details are stated:'}</div>
        <ul className="mt-1.5 flex flex-col gap-1">{chk.spec_missing.map((m, i) => <li key={i} className="flex items-start gap-2 text-[13px] text-foreground"><span aria-hidden className="mt-[7px] h-1.5 w-1.5 shrink-0 rounded-full bg-warn" />{m.scope === 'line' ? (ar ? `البند ${m.line_no}: ` : `Line ${m.line_no}: `) : ''}{ar ? m.label_ar : m.label_en}</li>)}</ul>
      </div>}
      {Array.isArray(chk.options) && chk.options.length > 1 && <div className={cn(S.sub, 'mt-2.5')}>{srvText(lang, 'options_split', { count: chk.options.length })}</div>}
      {chk.total_items != null && <div className={cn(S.sub, 'mt-2.5 pt-2.5 border-t border-border')}>
        {ar ? `${chk.priced_items} من ${chk.total_items} بند مُسعّر` : `${chk.priced_items} of ${chk.total_items} line items priced`}
      </div>}
    </Card>
  );
}
function Documents({ token, lang, onSaved = null }) {
  const [data, setData] = useState(null); const [busy, setBusy] = useState('');
  const load = () => call('supplier_portal', { action: 'documents' }, token).then((j) => { setData(j); return j; });
  // ONE READ AFTER EVERY WRITE (audit 21 Sep 2026, finding 16): save_documents, remove_document and
  // set_expiry answer with the fresh list, so the card, the counter and the unlock panel are painted
  // from the row as it is NOW. A second `documents` round trip used to race the write.
  const take = (j) => { if (j && Array.isArray(j.documents)) setData({ ok: true, documents: j.documents, expiries: j.expiries || [], summary: j.summary }); else load(); };
  useEffect(() => { load(); }, [token]);
  // `err` is a string or, for an Arabic per-file failure, a small JSX fragment; it is only rendered.
  const [err, setErr] = useState('');
  // What the server READ off each uploaded file (instruction 524): the expiry it found, or that it
  // could not find one. Shown to the supplier to confirm; never written for them unconfirmed.
  const [reads, setReads] = useState({});
  // The server reports per-file failures now. Previously a failed storage write was swallowed and
  // the kind still came back as saved, so a supplier could be told their licence was on file when
  // nothing had been written. Surface it instead of reloading over the top of it.
  const upload = async (kind, file, expiry) => {
    setBusy(kind); setErr('');
    const b64 = await fileToB64(file);
    const j = await call('supplier_portal', { action: 'save_documents', items: [{ kind, original_b64: b64, filename: file.name, mime: file.type, expiry }] }, token);
    setBusy('');
    if (j && j.read) setReads((o) => ({ ...o, ...j.read }));
    const failed = (j && j.failed) || [];
    // The server's per-file reasons are English sentences; an Arabic page says the same thing in Arabic.
    // The Arabic sentence used to REPLACE the reason, so an Arabic supplier never learned why (audit 15 Sep
    // 2026). The server's specific reason is kept after it, isolated left-to-right.
    if (failed.length) { const why = failed.map((f) => f.reason).filter(Boolean).join('; '); setErr(lang === 'ar' ? <>تعذّر حفظ الملف. يُرجى رفع نسخة PDF أو صورة واضحة للمستند كاملًا، ثم المحاولة مرة أخرى.{why ? <> السبب: <Ltr>{why}</Ltr></> : null}</> : 'Upload failed: ' + why); }
    else if (j && (j.error || j._http)) setErr(srvMsg(lang, j, lang === 'ar' ? 'تعذّر حفظ الملف. يُرجى المحاولة مرة أخرى.' : 'We could not save that file. Please try again.'));
    take(j);
    if (j && j.ok && onSaved) onSaved();
  };
  // REMOVE hides, never destroys; the server refuses a sealed record with a sentence in this language.
  const remove = async (kind, path) => {
    setErr('');
    const j = await call('supplier_portal', { action: 'remove_document', kind, path, lang }, token);
    if (j && j.ok) { setReads((o) => { const n = { ...o }; delete n[kind]; return n; }); take(j); if (onSaved) onSaved(); return { ok: true }; }
    return { ok: false, message: (j && j.message) || srvMsg(lang, j, lang === 'ar' ? 'تعذّرت الإزالة. يُرجى المحاولة مرة أخرى.' : 'Could not remove. Please try again.') };
  };
  // The supplier confirms (or corrects) the date the document was read to say.
  const confirmExpiry = async (kind, expiry) => {
    setErr('');
    const j = await call('supplier_portal', { action: 'set_expiry', kind, expiry }, token);
    if (j && j.ok) { setReads((o) => { const n = { ...o }; delete n[kind]; return n; }); take(j); if (onSaved) onSaved(); return true; }
    setErr(srvMsg(lang, j, lang === 'ar' ? 'تعذّر حفظ التاريخ.' : 'Could not save the date.')); return false;
  };
  if (!data) return <Card className="qd-panel p-5">{t(lang, 'loading_docs')}</Card>;
  // Order comes from the server (DOC_ORDER) so adding a document type needs no change here.
  const allDocs = data.documents || [];
  // Count only what is actually shown. The server still returns vat, and counting it would report
  // "2/8 on file" against a list of seven — a completeness bar that can never fill.
  const shownKeys = new Set(DOC_GROUPS.flatMap((g) => g.keys));
  const docs = allDocs.filter((d) => shownKeys.has(d.key));
  const sum = { on_file: docs.filter((d) => d.status !== 'missing').length, total: docs.length };
  const attention = docs.filter((d) => d.status === 'expired' || d.status === 'expiring');
  const missingReq = docs.filter((d) => d.required && d.status === 'missing');
  return <div className={S.list}>
    <Card className="qd-panel p-5">
      <div className="flex justify-between items-start gap-3 flex-wrap">
        <div>
          <div className={S.h2}>{t(lang, 'docs_h')}</div>
          <div className={cn(S.sub, 'mt-1')}>{lang === 'ar'
            ? 'الرخصة التجارية والملف التعريفي للشركة مطلوبان للتسجيل، ويجب أن تبقى الرخصة سارية لتستمر الطلبات في الوصول إليكم. وكل ما عدا ذلك اختياري.'
            : 'Your trade licence and company profile are required to register, and the licence must stay valid to keep receiving requests. Everything else is optional.'}</div>
        </div>
        <div className="text-end shrink-0">
          <div className="text-[22px] font-extrabold text-foreground leading-none"><Ltr>{sum.on_file ?? 0}<span className="text-muted-foreground text-[15px]">/{sum.total ?? docs.length}</span></Ltr></div>
          <div className={S.sub}>{lang === 'ar' ? 'على الملف' : 'on file'}</div>
        </div>
      </div>
      {/* Completeness bar — one glance at how far off "complete" they are. */}
      <div className="mt-3 h-2 rounded-full bg-secondary/60 overflow-hidden" role="progressbar"
           aria-valuenow={sum.on_file ?? 0} aria-valuemin={0} aria-valuemax={sum.total ?? docs.length}
           aria-label={lang === 'ar' ? 'اكتمال المستندات' : 'Document completeness'}>
        <div className="h-full bg-primary transition-[width] duration-700 motion-reduce:transition-none"
             style={{ width: (sum.total ? Math.round(100 * (sum.on_file || 0) / sum.total) : 0) + '%' }} />
      </div>
      {(!!missingReq.length || !!attention.length) && <div className="flex gap-2 flex-wrap mt-3">
        {!!missingReq.length && <Badge variant="destructive">{missingReq.length} {lang === 'ar' ? 'مطلوب ومفقود' : (missingReq.length === 1 ? 'required document missing' : 'required documents missing')}</Badge>}
        {!!attention.length && <Badge variant="warn">{attention.length} {lang === 'ar' ? 'بحاجة إلى انتباه' : 'needs attention'}</Badge>}
      </div>}
      {err && <div className={cn(S.err, 'mt-3')}>{err}</div>}
    </Card>
    {DOC_GROUPS.map((g) => {
      const rows = g.keys.map((k) => docs.find((d) => d.key === k)).filter(Boolean);
      if (!rows.length) return null;
      return <div key={g.id} className={S.section}>
        <div className="px-1 pt-2 pb-1">
          <div className="text-[12px] font-bold tracking-[.04em] uppercase text-muted-foreground/90">{g.title(lang)}</div>
          {g.note && <div className={cn(S.sub, 'mt-1')}>{g.note(lang)}</div>}
        </div>
        <div className={S.list}>
          {rows.map((d) => <DocRow key={d.key + '|' + (d.path || '') + '|' + (d.expiry || '')} d={d} lang={lang} busy={busy === d.key} onUpload={upload} onRemove={remove} onConfirmExpiry={confirmExpiry} read={reads[d.key] || null} />)}
        </div>
      </div>;
    })}
  </div>;
}
// Grouped by what each document actually gates, because eight identical "Not uploaded" badges in one
// list reads as eight blockers. Only the first group can stop a supplier being verified; the second is
// framed by what it UNLOCKS rather than as an unmet requirement.
//
// VAT is deliberately absent: their TRN is already read off the trade licence automatically, so the VAT
// certificate was asking for something we had. The backend still supports the type; this removes the ask.
// Bank details are absent EVERYWHERE since 21 Sep 2026 (founder instruction 527): money moves both directions
// through Stripe — customers pay us, and a supplier settling a due pays us the same way — so the estate
// never holds a supplier's bank details. The IBAN document type and the bank columns were removed.
const DOC_GROUPS = [
  // Required = the documents in the mandatory six (supabase/functions/_shared/supplier_registration.ts
  // REQUIRED_DOC_KEYS). Catalogues were in this group while the server marked only the licence
  // required; they are optional, and now sit with the other optional documents.
  { id: 'required', keys: ['license', 'profile'],
    title: (l) => (l === 'ar' ? 'مطلوب للتحقق' : 'Required to get verified'),
    note: (l) => (l === 'ar'
      ? 'الرخصة التجارية والملف التعريفي للشركة، ونستخلص منهما نشاطكم لنحدد الطلبات التي نرسلها إليكم.'
      : 'Your trade licence and company profile. We read these to work out what work to send you.') },
  { id: 'optional', keys: ['catalogs', 'insurance', 'iso', 'manufacturer', 'egr'],
    title: (l) => (l === 'ar' ? 'اختياري — للحصول على مطابقات أكثر' : 'Optional — get matched to more work'),
    note: (l) => (l === 'ar'
      ? 'لا يُشترط أيٌّ منها للتحقق، لكن كل مستند تضيفونه يفتح لكم طلبات إضافية؛ فبعض العملاء يشترطون التأمين، وخطاب الوكالة يتيح لنا مطابقتكم عندما يطلب العميل علامة تجارية بعينها.'
      : 'None of these are needed to be verified. Each one you add opens up more requests — some customers require insurance, and a dealer letter lets us match you when a customer names a brand you carry.') },
];
// Every document type is editable here. The trade licence and company profile used to be
// deliberately read-only (editable={d.key !== 'license' && d.key !== 'profile'}), and the only
// licence upload in the product lived in ProfileForm, which renders solely while the account has
// no company yet. An established supplier whose licence expired therefore had nowhere to replace
// it — while receiving alerts telling them to do exactly that. Now that expiry suspends matching,
// that dead end would have been an account they could not reopen.
// Storage paths are prefixed with an epoch stamp to keep uploads unique, so the filename the
// server falls back to reads as "1784642799037_catalogue-vrf-2026.pdf". Only license and egr
// have a dedicated name column; everything else shows the path tail. Strip the stamp for
// display so the supplier sees the name they actually uploaded.
const cleanName = (n) => String(n || '').replace(/^\d{10,}_/, '');
// What the server read off the file, said back to the supplier (instruction 524). Three shapes:
// the licence's date (written from the licence, shown as a fact); a certificate's date (shown with
// Confirm, and a box to correct it — nothing is written until they do); or that nothing could be
// read, said plainly, in which case the date box below is how the supplier tells us.
function ExpiryRead({ read, lang, label, onConfirm }) {
  const ar = lang === 'ar';
  const [val, setVal] = useState(read && read.expiry ? read.expiry : ''); const [busy, setBusy] = useState(false);
  if (!read) return null;
  if (read.unread) return <div className={cn(S.sub, 'mt-2')} role="status">{ar
    ? `تعذّرت قراءة تاريخ الانتهاء من هذا الملف تلقائيًا (${read.kind === 'license' ? 'يُرجى رفع نسخة PDF واضحة من الرخصة كاملة' : 'يُرجى إدخاله أدناه وسنحفظه'}).`
    : `We could not read the expiry date from this file automatically${read.kind === 'license' ? ' — please upload a clear PDF of the full licence' : ' — enter it below and we will save it'}.`}</div>;
  if (!read.needs_confirm) return <div className={cn(S.sub, 'mt-2')} role="status">{ar ? 'قرأنا من المستند: ينتهي في ' : 'Read from the document: expires '}<Ltr>{fmtDate(read.expiry, lang)}</Ltr>{read.source === 'ai' ? (ar ? ' (قراءة آلية)' : ' (machine-read)') : ''}</div>;
  const save = async (v) => { setBusy(true); await onConfirm(read.kind, v); setBusy(false); };
  return <div className="mt-2 flex flex-wrap items-center gap-2" role="status">
    <span className={S.sub}>{ar ? 'قرأنا من المستند: ينتهي في ' : 'We read from the document: expires '}<Ltr>{fmtDate(read.expiry, lang)}</Ltr>{read.typed && read.typed !== read.expiry ? (ar ? ` (أدخلتم ${read.typed})` : ` (you typed ${read.typed})`) : ''} — {ar ? 'هل هذا صحيح؟' : 'is that right?'}</span>
    <Button size="sm" disabled={busy} onClick={() => save(read.expiry)}>{ar ? 'تأكيد' : 'Confirm'}</Button>
    <Input type="date" dir="ltr" className="w-auto" value={val} onChange={(e) => setVal(e.target.value)} aria-label={(ar ? 'تصحيح تاريخ انتهاء ' : 'Correct the expiry date for ') + label} />
    <Button size="sm" variant="outline" disabled={busy || !val || val === read.expiry} onClick={() => save(val)}>{ar ? 'حفظ التصحيح' : 'Save correction'}</Button>
  </div>;
}
function DocRow({ d, busy, onUpload, onRemove, onConfirmExpiry, read, lang }) {
  const [exp, setExp] = useState(d.expiry || ''); const [file, setFile] = useState(null);
  const ar = lang === 'ar';
  const label = ({ license: t(lang, 'h_trade'), profile: t(lang, 'doc_profile'), catalogs: t(lang, 'catalogues'), iso: t(lang, 'doc_iso'), insurance: t(lang, 'doc_insurance'), manufacturer: t(lang, 'doc_manufacturer'), egr: t(lang, 'doc_egr') })[d.key] || d.label;
  // Status is computed server-side so the badge, the alerts and the suspension job cannot disagree.
  const ST = {
    expired:  { t: ar ? 'منتهية' : 'Expired',      v: 'destructive' },
    expiring: { t: ar ? 'تنتهي قريبًا' : 'Expiring soon', v: 'warn' },
    valid:    { t: ar ? 'سارية' : 'Valid',          v: 'ok' },
    on_file:  { t: ar ? 'على الملف' : 'On file',    v: 'secondary' },
    missing:  { t: ar ? 'مفقود' : 'Not uploaded',   v: d.required ? 'destructive' : 'secondary' },
  };
  const st = ST[d.status] || null;
  const isCat = d.key === 'catalogs';
  const items = Array.isArray(d.items) ? d.items : [];
  return <Card className="qd-panel p-5">
    <div className="flex justify-between items-start gap-3 flex-wrap">
      <div className="min-w-[240px] flex-1">
        <div className="flex items-center gap-2 flex-wrap">
          <b className="text-foreground">{label}</b>
          {d.required && <Badge variant="secondary">{ar ? 'مطلوب' : 'Required'}</Badge>}
          {st && <Badge variant={st.v}>{st.t}</Badge>}
        </div>
        <div className={cn(S.sub, 'mt-1')}>{srvText(lang, d.hint_code, {}, d.hint)}</div>
        {/* What is actually on file, by name, so they can tell whether the right file went up. */}
        {!isCat && d.path && <div className={cn(S.sub, 'mt-1.5')}>
          <bdi className="text-foreground/80">{cleanName(d.name) || (ar ? 'ملف' : 'File')}</bdi>
          {d.expiry ? <> · {ar ? 'تنتهي ' : 'expires '}<Ltr>{fmtDate(d.expiry, lang)}</Ltr></> : null}
        </div>}
        {/* The four actions every document offers (instruction 524): View / Download / Replace / Remove.
            Replace re-runs the reading and keeps the previous version; Remove hides, never destroys, and
            the server refuses it on a mandatory document of an approved supplier, in this language. */}
        {/* ONE HOME PER SUBJECT (finding 17): a certificate filed under Supporting documents counts here
            too. It is managed where it was filed, so this row says so instead of offering a Remove that
            would find nothing in this slot. */}
        {!isCat && d.path && d.source === 'supporting' && <div className={cn(S.sub, 'mt-1.5')} role="note">{ar ? 'مرفوع ضمن «المستندات الداعمة» — يُدار من هناك.' : 'Filed under Supporting documents — manage it there.'}</div>}
        {!isCat && d.path && d.source !== 'supporting' && <DocActions lang={lang} name={cleanName(d.name)} url={d.url} versions={d.versions || 0} className="mt-2"
          onReplace={(f) => onUpload(d.key, f, '')} onRemove={() => onRemove(d.key)} />}
        {isCat && (items.length
          ? <ul className="mt-1.5 flex flex-col gap-2">{items.map((c, i) => <li key={c.path || i} className={S.sub}>
              <bdi className="text-foreground/80">{cleanName(c.name)}</bdi>
              <DocActions lang={lang} name={cleanName(c.name)} url={c.url} className="mt-1"
                onReplace={async (f) => { const r = await onRemove('catalogs', c.path); if (r && r.ok === false) throw new Error(r.message); await onUpload('catalogs', f, ''); }}
                onRemove={() => onRemove('catalogs', c.path)} />
            </li>)}</ul>
          : <div className={cn(S.sub, 'mt-1.5')}>{t(lang, 'not_uploaded')}</div>)}
        {!isCat && !d.path && <div className={cn(S.sub, 'mt-1.5')}>{t(lang, 'not_uploaded')}</div>}
        <ExpiryRead read={read} lang={lang} label={label} onConfirm={onConfirmExpiry} />
      </div>
      {/* First upload (nothing on file) or another catalogue. A file on record is replaced from its own row above. */}
      {(!d.path || isCat) && <div className="flex gap-2 items-center flex-wrap shrink-0">
        <FilePick lang={lang} onPick={setFile} />
        {file && <span className={cn(S.sub, 'max-w-[180px] truncate')}>{file.name}</span>}
        {/* Not for the trade licence: its expiry is read off the licence itself and save_documents
            refuses a typed one (the #86 gate), so a date box there was a control that could only fail.
            For the others the box is optional now: the date is read off the file first (instruction 524). */}
        {d.has_expiry && d.key !== 'license' && <Input type="date" dir="ltr" className="w-auto" value={exp}
          onChange={(e) => setExp(e.target.value)} aria-label={(ar ? 'تاريخ انتهاء ' : 'Expiry date for ') + label} />}
        <Button size="sm" disabled={busy || !file} onClick={() => { onUpload(d.key, file, d.key === 'license' ? '' : exp); setFile(null); }}>
          {busy ? t(lang, 'uploading') : t(lang, 'upload')}
        </Button>
      </div>}
      {/* A certificate on file whose date is missing or wrong: the same box, without a new file. */}
      {d.path && !isCat && d.has_expiry && d.key !== 'license' && !read && <div className="flex gap-2 items-center flex-wrap shrink-0">
        <Input type="date" dir="ltr" className="w-auto" value={exp} onChange={(e) => setExp(e.target.value)} aria-label={(ar ? 'تاريخ انتهاء ' : 'Expiry date for ') + label} />
        <Button size="sm" variant="outline" disabled={busy || !exp || exp === (d.expiry || '')} onClick={() => onConfirmExpiry(d.key, exp)}>{ar ? 'حفظ التاريخ' : 'Save date'}</Button>
      </div>}
    </div>
  </Card>;
}
// A revealed job: the customer paid to know this supplier. The signed Supplier Agreement (v9, cl. 11
// and 33) gives the supplier 5 working days to respond, and QuotesDone chases at 3. The customer's
// contact is shown here because this list is built from the supplier's own transactions rows — the
// reveal itself — so it cannot appear before one.
function Projects({ token, lang, openChat }) {
  const ar = lang === 'ar';
  const [data, setData] = useState(null); const [busy, setBusy] = useState(''); const [msg, setMsg] = useState('');
  const load = () => call('supplier_api', { action: 'projects' }, token).then((j) => setData(j));
  useEffect(() => { load(); }, [token]);
  const ack = async (id) => {
    setBusy(id); setMsg('');
    const j = await call('supplier_api', { action: 'ack_contact', transaction_id: id }, token);
    setBusy('');
    if (j && j.ok) load(); else setMsg(srvMsg(lang, j, ar ? 'تعذّر تسجيل ذلك. يُرجى المحاولة مرة أخرى.' : 'We could not record that. Please try again.'));
  };
  if (!data) return <Card className="qd-panel p-5" aria-busy="true">{t(lang, 'loading')}</Card>;
  if (data.error) return <Card className="qd-panel p-5">{srvMsg(lang, data, t(lang, 'err_generic'))}</Card>;
  const list = data.projects || [];
  const rule = ar
    ? 'عندما يكشف العميل عن عرضكم يجب أن تتواصلوا معه خلال 5 أيام عمل من تاريخ الكشف. وإن لم تتواصلوا خلال 3 أيام عمل نتابع معكم ونُشرك العميل في المراسلة، وإن لم يصل منكم أي رد يُردّ إلى العميل كل ما دفعه، وتُستحق عليكم رسوم عدم الاستجابة: المبلغ الذي رُدّ إلى العميل بالضبط (رسوم الكشف البالغة 3% مضافًا إليها رسوم معالجة البطاقة)، ورسم إداري قدره 250 درهمًا، وفائدة بسيطة بنسبة 9% سنويًا (أو الحد الأقصى الذي يسمح به القانون) من تاريخ الاستحقاق (البند 33 من اتفاقية المورّد).'
    : 'When a customer reveals your quote you must respond to them within 5 working days of the reveal. If you have not responded within 3 working days we chase you with the customer copied; if you stay silent everything the customer paid is refunded and the non-response charge applies: the exact amount refunded (the 3% reveal fee plus the card processing fee charged on it), an AED 250 administrative fee, and simple interest at 9% a year (or the maximum lawful rate) from the due date (Supplier Agreement, clause 33).';
  if (!list.length) return <Card className="qd-panel p-5"><div className={S.h2}>{t(lang, 'no_projects_h')}</div><div className={S.sub}>{t(lang, 'no_projects_sub')}</div><div className={cn(S.sub, 'mt-2')}>{rule}</div></Card>;
  const now = Date.now();
  return <div className={S.list}>
    <Card className="qd-panel p-4"><div className={S.sub}>{rule}</div>{msg && <div role="alert" className={S.err}>{msg}</div>}</Card>
    {list.map((p) => {
      const c = p.customer || {};
      const late = !p.acknowledged_at && p.respond_by && new Date(p.respond_by).getTime() < now;
      const chased = !p.acknowledged_at && p.chase_at && new Date(p.chase_at).getTime() < now;
      return <Card key={p.id} className="qd-panel p-5">
        <div className="flex justify-between items-start gap-3 flex-wrap">
          <div className="min-w-0">
            <div className="font-semibold text-foreground">{categoryLabel(p.category || '', lang) || t(lang, 'project_w')} · {emirateLabel(lang, p.emirate || '')}</div>
            {p.summary ? <div className={cn(S.sub, 'mt-0.5')}>{p.summary}</div> : null}
          </div>
          <div className="text-end shrink-0"><b className="tabular-nums text-foreground"><Ltr>{aed(p.amount)}</Ltr></b><div className={S.sub}>{(ar ? 'كُشف في ' : 'Revealed ')}<Ltr>{fmtDate(p.revealed_at, lang)}</Ltr></div></div>
        </div>
        <div className="mt-3 rounded-md border border-border px-3.5 py-3">
          <div className="font-mono text-label uppercase tracking-caps text-muted-foreground">{ar ? 'العميل' : 'Customer'}</div>
          <div className="mt-1 text-[14px] font-semibold text-foreground"><bdi>{c.name || (ar ? 'العميل' : 'Customer')}</bdi></div>
          <div className="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-[13px]">
            {c.phone ? <a className="text-primary font-semibold underline-offset-2 hover:underline" href={'tel:' + String(c.phone).replace(/[^\d+]/g, '')}><Ltr>{c.phone}</Ltr></a> : null}
            {c.email ? <a className="text-primary font-semibold underline-offset-2 hover:underline" href={'mailto:' + c.email}><Ltr>{c.email}</Ltr></a> : null}
            {!c.phone && !c.email ? <span className={S.sub}>{ar ? 'يمكنكم التواصل معه عبر الرسائل أدناه.' : 'Use the messages below to reach them.'}</span> : null}
          </div>
        </div>
        <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
          <div className="text-[13px]">
            {p.acknowledged_at
              ? <Badge variant="ok">{ar ? 'سجّلتم التواصل' : 'You confirmed contact'} · <Ltr>{fmtDate(p.acknowledged_at, lang, false)}</Ltr></Badge>
              : <Badge variant={late ? 'destructive' : chased ? 'warn' : 'secondary'}>{(late ? (ar ? 'تجاوزتم مهلة الرد — ' : 'Response overdue — ') : (ar ? 'الرد قبل ' : 'Respond by '))}<Ltr>{fmtDate(p.respond_by, lang)}</Ltr></Badge>}
          </div>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" variant="outline" onClick={() => openChat(p.inquiry_id)}>{ar ? 'مراسلة العميل' : 'Message the customer'}</Button>
            {!p.acknowledged_at && <Button size="sm" disabled={busy === p.id} onClick={() => ack(p.id)}>{busy === p.id ? (ar ? 'جارٍ التسجيل…' : 'Saving…') : (ar ? 'تواصلنا مع العميل' : 'I have contacted the customer')}</Button>}
          </div>
        </div>
      </Card>;
    })}
  </div>;
}
// Profile tab for an established supplier. Reuses ProfileForm rather than duplicating it, so the
// same validation, terms handling and save_profile call apply whether the supplier is registering
// for the first time or correcting a detail two years later.
function ProfilePanel({ token, lang, onSaved, initial = null }) {
  // Audit 21 Sep 2026, finding 34: the tab re-read `me` the portal had already read, and waited for it.
  const [me, setMe] = useState(initial || undefined);
  const load = () => call('supplier_api', { action: 'me' }, token).then((j) => setMe(j.supplier || null)).catch(() => setMe(null));
  useEffect(() => { if (!initial) load(); }, [token]);
  if (me === undefined) return <Card className="qd-panel p-5">{t(lang, 'loading')}</Card>;
  if (!me) return <Card className="qd-panel p-5"><div className={S.h2}>{t(lang, 'something_wrong')}</div><div className={S.sub}>{t(lang, 'err_generic')}</div></Card>;
  return <div className={S.list}>
    <Card className="qd-panel p-5">
      <div className={S.h2}>{lang === 'ar' ? 'ملف الشركة' : 'Company profile'}</div>
      <div className={cn(S.sub, 'mt-1')}>{lang === 'ar'
        ? 'ما تكتبونه هنا يحدّد الطلبات التي تصلكم؛ إذ تُطابَق الطلبات على القطاع والمنتجات والخدمات والفئات، وكلما كانت أدق زادت فرص مطابقتكم.'
        : 'What you write here decides which requests reach you. Requests are matched on your sector, products, services and categories — the more specific these are, the more you match.'}</div>
    </Card>
    <ProfileForm token={token} me={me} onSaved={() => { load(); if (onSaved) onSaved(); }} lang={lang} mode="edit" />
  </div>;
}
function Onboarding({ token, onDone, lang }) {
  const [me, setMe] = useState(undefined);
  const load = () => call('supplier_api', { action: 'me' }, token).then((j) => setMe(j.supplier || null)).catch(() => setMe(null));
  useEffect(() => { load(); }, []);
  if (me === undefined) return <div className={S.center}>{t(lang, 'loading')}</div>;
  return (<div className={S.wrap} style={{ maxWidth: 640 }}>
    <h1 className={cn(S.h1, 'mb-1 font-[family-name:var(--font-head)]')}>{t(lang, 'setup_title')}</h1>
    <div className={cn(S.sub, 'mb-3.5')}>{me ? t(lang, 'setup_sub_profile') : t(lang, 'setup_sub_company')}</div>
    {!me ? <NewCompany token={token} onReady={load} lang={lang} /> : <ProfileForm token={token} me={me} onSaved={onDone} lang={lang} />}
  </div>);
}
// ONE QUESTION PER FACT, AND THE TRADE IS A CODE (15 Sep 2026, agent: customer_support).
// The emirate was asked twice: one emirate here, then the service-emirate chips in ProfileForm. The
// chips are the answer that is kept (save_profile stores service_emirates and capability coverage
// defaults to them), so this screen no longer asks. The trade was free text over 29 suggestions that
// no taxonomy_trade code carried; it is now one of the 40 codes, which create_company writes to
// leads.sector unchanged. "My trade isn't listed" keeps the founder's open list (14 Sep 2026: a new
// trade is welcome): the typed words are stored in the same column and read by a person.
const TRADE_OTHER = '__other';
function NewCompany({ token, onReady, lang }) {
  const [cname, setCname] = useState(''); const [trade, setTrade] = useState(''); const [other, setOther] = useState(''); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const category = trade === TRADE_OTHER ? (other.trim().slice(0, 60) || null) : (trade || null);
  const create = async () => { if (cname.trim().length < 2) { setMsg(t(lang, 'enter_company')); return; } setBusy(true); setMsg(''); const j = await call('supplier_api', { action: 'create_company', company_name: cname.trim(), category, role: 'supplier', lang }, token); setBusy(false); if (j && j.ok) onReady(); else setMsg(srvMsg(lang, j, t(lang, 'err_generic'))); };
  const codes = [...TRADE_CODES].sort((a, b) => tradeLabel(lang, a).localeCompare(tradeLabel(lang, b), lang));
  return (<Card className="qd-panel p-5">
    <h2 className={S.h2}>{t(lang, 'onboard_title')}</h2>
    <div className={cn(S.sub, 'mb-2')}>{t(lang, 'onboard_sub')}</div>
    <Lbl need="req" lang={lang} className="mt-3" text={t(lang, 'company_name')}><Input dir="auto" autoComplete="organization" aria-required="true" placeholder={t(lang, 'company_name')} value={cname} onChange={(e) => setCname(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && create()} /></Lbl>
    <Lbl need="opt" lang={lang} className="mt-3" text={t(lang, 'trade_label')}>
      <select className={cn(S.field, 'mt-0 bg-card')} value={trade} onChange={(e) => setTrade(e.target.value)} aria-describedby="qd-trade-help">
        <option value="">{t(lang, 'trade_ph')}</option>
        {codes.map((c) => <option key={c} value={c}>{tradeLabel(lang, c)}</option>)}
        <option value={TRADE_OTHER}>{t(lang, 'trade_not_listed')}</option>
      </select>
    </Lbl>
    {trade === TRADE_OTHER && <Lbl className="mt-2" text={t(lang, 'trade_other_ph')}><Input dir="auto" maxLength={60} placeholder={t(lang, 'trade_other_ph')} value={other} onChange={(e) => setOther(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && create()} /></Lbl>}
    <div id="qd-trade-help" className={cn(S.sub, 'mt-1 mb-2 text-[12px]')}>{t(lang, 'trade_help')}</div>
    <Button className="w-full mt-3" disabled={busy} onClick={create}>{busy ? t(lang, 'sending') : t(lang, 'create_company')}</Button>
    {msg && <div role="alert" className={S.err}>{msg}</div>}
  </Card>);
}
function FilePick({ lang, accept, multiple, onPick, label }) {
  return <label className="inline-flex items-center gap-2 cursor-pointer rounded-md border border-border bg-secondary px-3 py-1.5 text-sm font-medium text-secondary-foreground hover:bg-secondary/80"><input type="file" accept={accept} multiple={multiple ? true : undefined} className="hidden" onChange={(e) => { const fs = e.target.files; if (!fs || !fs.length) return; onPick(multiple ? Array.from(fs) : fs[0]); e.target.value = ''; }} />📎 {label || t(lang, 'attach_file')}</label>;
}
// `mode` distinguishes first-time REGISTRATION (Onboarding) from an established supplier
// EDITING their profile (the Profile tab). Document uploads (trade licence, company profile,
// catalogues) are shown only during registration. In edit mode they are hidden and the supplier
// is pointed to the Documents tab, which is the single home for every document file — the same
// file is never asked for in two places.
function ProfileForm({ token, me, onSaved, lang, mode = 'register' }) {
  const isEdit = mode === 'edit';
  const ar = lang === 'ar';
  const [f, setF] = useState({
    contact_name: me.contact_name || '', signatory_name: me.signatory_name || '', owner_dob: me.owner_dob || '', phone: me.phone || '',
    products: me.products || '', services: me.services || '', description: me.description || '',
    trade_license_no: me.trade_license_no || '', license_authority: me.license_authority || '', license_expiry: me.license_expiry || '',
    trn: me.trn || '', egr_number: me.egr_number || '', founded_year: me.founded_year || '', company_type: me.company_type || '', company_size: me.company_size || '',
  });
  const [emirates, setEmirates] = useState(me.service_emirates || []); const [terms, setTerms] = useState(!!me.accepted_terms_at);
  const [profileFile, setProfileFile] = useState(null); const [catalogFiles, setCatalogFiles] = useState([]); const [catCut, setCatCut] = useState(false); const [docsSent, setDocsSent] = useState(false);
  const [phoneVerified, setPhoneVerified] = useState(false); const [smsSent, setSmsSent] = useState(false); const [smsCode, setSmsCode] = useState(''); const [vbusy, setVbusy] = useState(false);
  const [emailVerified, setEmailVerified] = useState(!!me.owner_email_verified); const [mailSent, setMailSent] = useState(false); const [mailCode, setMailCode] = useState('');
  // wa: kyc's `whatsapp` answer. Registration waits for it (founder, 15 Sep 2026: "It's in the sign
  // up"): save() lists it as missing and supplier_api save_profile refuses without it (reg_whatsapp).
  const [wa, setWa] = useState(undefined);
  const [saved, setSaved] = useState(false);
  const loadKyc = () => call('kyc', { action: 'state' }, token).then((k) => { if (k && k.phone_verified) setPhoneVerified(true); if (k && k.email_verified) setEmailVerified(true); setWa(k ? k.whatsapp : undefined); });
  useEffect(() => { loadKyc(); }, []);
  const sendSms = async () => { const e164 = uaeMobile(f.phone); if (!e164) { setMsg(t(lang, 'mobile_format')); return; } if (e164 !== f.phone) set('phone', e164); setVbusy(true); setMsg(''); const j = await call('kyc', { action: 'send_sms', phone: e164 }, token); setVbusy(false); if (j && j.ok) setSmsSent(true); else setMsg(srvMsg(lang, j, t(lang, 'could_not_sms'))); };
  const verifySms = async () => { setVbusy(true); setMsg(''); const j = await call('kyc', { action: 'verify_sms', phone: f.phone, code: smsCode }, token); setVbusy(false); if (j && j.ok) setPhoneVerified(true); else setMsg(srvMsg(lang, j, t(lang, 'wrong_code'))); };
  // E-MAIL, THE ONE ITEM OF THE SIX WITH NO BUTTON (14 Sep 2026). The form showed "e-mail not yet
  // verified" with nothing to press, and save_profile now requires it. kyc send_email / verify_email
  // already existed; this is their caller. (supplier_api also records it from the sign-up OTP, so most
  // suppliers will never see this.)
  const sendMail = async () => { setVbusy(true); setMsg(''); const j = await call('kyc', { action: 'send_email' }, token); setVbusy(false); if (j && j.ok) { setMailSent(true); setMsg(t(lang, 'email_sent')); } else setMsg(srvMsg(lang, j, t(lang, 'could_not_email'))); };
  const verifyMail = async () => { setVbusy(true); setMsg(''); const j = await call('kyc', { action: 'verify_email', code: mailCode }, token); setVbusy(false); if (j && j.ok) { setEmailVerified(true); setMsg(''); } else setMsg(srvMsg(lang, j, t(lang, 'wrong_code'))); };
  const [uploading, setUploading] = useState(false); const [licNote, setLicNote] = useState(me.license_doc_path ? t(lang, 'lic_on_file') : '');
  const [licOnFile, setLicOnFile] = useState(!!me.license_doc_path);
  const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const set = (k, v) => setF((o) => ({ ...o, [k]: v }));
  // THE LICENCE DEAD-END (audit 2026-09-14, BLOCKS CONVERSION). After any upload licNote became
  // non-empty ("Licence uploaded." when extraction returned nothing), which HID the typed licence-number
  // field, while save() still refused without a number. Under the OpenRouter hold license_extract never
  // returns, so every new supplier could neither type the number nor submit. Now: the upload itself
  // counts as the licence (the server's gate is path OR number, and the mandatory six say the same),
  // the number field is always shown, and extraction only fills it in when it happens to answer.
  // A failed STORE is reported as a failure instead of being announced as "uploaded".
  const upLicense = async (file) => {
    if (!file) return; setUploading(true); setLicNote(''); setMsg('');
    try {
      const { images, b64, mime } = await fileToImages(file);
      const j = await call('supplier_api', { action: 'process_docs', license: { original_b64: b64, file_b64: b64, images, filename: file.name, mime } }, token);
      if (!(j && j.ok)) { setMsg(srvMsg(lang, j, t(lang, 'lic_upload_failed'))); }
      else {
        setLicOnFile(true);
        const ex = (j.extracted && j.extracted.license) || null;
        if (ex) { setF((o) => ({ ...o, trade_license_no: ex.license_number || o.trade_license_no, license_authority: ex.authority || o.license_authority, license_expiry: ex.expiry || o.license_expiry, trn: ex.trn || o.trn })); setLicNote(t(lang, 'read_lic') + (ex.license_number ? ' — ' + ex.license_number : '') + (ex.expiry ? t(lang, 'expires_comma') + ex.expiry : '') + '.'); }
        else setLicNote(t(lang, 'lic_uploaded_type'));
      }
    } catch (_e) { setMsg(t(lang, 'lic_upload_failed')); }
    setUploading(false);
  };
  const save = async () => {
    // The mandatory six, checked here in the same order and with the same codes save_profile enforces
    // (supabase/functions/_shared/supplier_registration.ts), so the refusal a supplier sees on screen
    // and the one the server would give cannot disagree. An approved company editing its profile is
    // not re-gated — the server does not re-gate it either.
    if (me.approval_status !== 'approved') {
      const missing = [];
      if (!phoneVerified) missing.push('reg_mobile');
      if (!emailVerified) missing.push('reg_email');
      if (!waSignupSettled(wa)) missing.push('reg_whatsapp');
      if (!licOnFile && !String(f.trade_license_no || '').trim()) missing.push('reg_licence');
      if (!profileFile && !me.company_profile_doc_path) missing.push('reg_profile');
      if (!terms) missing.push('reg_terms');
      if (missing.length) { setMsg(srvText(lang, 'missing_required', { missing })); return; }
    } else if (!terms) { setMsg(t(lang, 'must_accept')); return; }
    setBusy(true); setMsg('');
    try {
      // A retry after a certificate failure does not upload the same files again (review of #695).
      if (!docsSent && (profileFile || catalogFiles.length)) {
        const prof = profileFile ? { original_b64: await fileToB64(profileFile), filename: profileFile.name, mime: profileFile.type } : undefined;
        const cats = []; for (const cf of catalogFiles.slice(0, 5)) cats.push({ original_b64: await fileToB64(cf), filename: cf.name, mime: cf.type });
        const pj = await call('supplier_api', { action: 'process_docs', company_profile: prof, catalogs: cats }, token);
        if (!(pj && pj.ok)) { setBusy(false); setMsg(srvMsg(lang, pj, t(lang, 'save_error'))); return; }
        setDocsSent(true);
      }
      // The checkbox's own value (audit 15 Sep 2026: a constant "yes" was sent whatever it said).
      const payload = { action: 'save_profile', service_emirates: emirates, accept_terms: terms };
      const strk = ['contact_name', 'signatory_name', 'phone', 'products', 'services', 'description', 'trade_license_no', 'license_authority', 'license_expiry', 'trn', 'egr_number', 'company_type', 'company_size'];
      for (const k of strk) if (String(f[k] || '').trim()) payload[k] = f[k];
      if (uaeMobile(f.phone)) payload.phone = uaeMobile(f.phone);
      if (String(f.founded_year || '').trim()) payload.founded_year = Number(f.founded_year);
      let j = await call('supplier_api', payload, token);
      // A CERTIFICATE THAT FAILED ONCE FAILED FOREVER (21 Sep 2026, campaign registration walk). Under
      // load the first certificate write timed out (compliance_archive: "cert_record_failed … statement
      // timeout", measured on production). The acceptance was recorded but no signed PDF exists, so every
      // later save_profile answers missing_required [reg_terms] — and this function returned on that
      // answer BEFORE the kyc call below, the only thing that issues the certificate. Ticked, saved,
      // refused, forever. Now the certificate is requested exactly when that is what is missing, and the
      // save is asked once more. Prevented by scripts/checks/an_invited_supplier_can_finish_registering.test.mjs.
      if (terms && j && j.saved && j.code === 'missing_required' && ((j.params && j.params.missing) || []).includes('reg_terms')) {
        const k0 = await call('kyc', { action: 'accept_terms' }, token).catch(() => null);
        if (k0 && k0.ok) j = await call('supplier_api', payload, token);
      }
      if (!(j && j.ok)) { setBusy(false); setMsg(srvMsg(lang, j, t(lang, 'could_not_save'))); return; }
      // The signed acceptance certificate. Its failure used to be swallowed, so a supplier could finish
      // registration with no certificate on file. The save above stands; pressing again retries both.
      if (terms) {
        const k = await call('kyc', { action: 'accept_terms' }, token).catch(() => null);
        if (!(k && k.ok)) { setBusy(false); setMsg(t(lang, 'terms_cert_failed')); return; }
      }
      setBusy(false);
      // Audit 21 Sep 2026, finding 32: Save closed with nothing on screen to say it worked.
      if (isEdit) { setSaved(true); setTimeout(() => setSaved(false), 6000); }
      onSaved();
    } catch (_e) { setBusy(false); setMsg(t(lang, 'save_error')); }
  };
  // Audit 21 Sep 2026, finding 48: "✓ Trade licence" put the state inside the heading's name (a screen
  // reader read "check mark trade licence"). The state is a badge after the name, in words.
  const ok = (on) => (on ? <Badge variant="ok" className="ms-2 align-middle">{ar ? 'مكتمل' : 'Done'}</Badge> : null);
  return (<Card className="qd-panel p-5">
    <h2 className={S.h2}>{t(lang, 'pf_company')}</h2>
    {/* The form registers a new supplier AND is where an existing one corrects a detail; it says which. */}
    <div className={cn(S.sub, 'mb-2')}>
      {isEdit
        ? (ar ? <>تحرير ملف <b dir="auto">{me.company_name}</b>. ما تكتبونه هنا يحدّد الطلبات التي تصلكم، ويُرجى حفظ التغييرات في الأسفل.</>
              : <>Editing the profile for <b dir="auto">{me.company_name}</b>. What you write here decides which requests reach you; save your changes at the bottom.</>)
        : <>{t(lang, 'registering_pre')}<b dir="auto">{me.company_name}</b>{me.name_corrected_from ? t(lang, 'corrected') : ''}{t(lang, 'registering_post')}</>}
    </div>
    <EmirateCheckboxes lang={lang} value={emirates} onChange={setEmirates} legend={<>{t(lang, 'pf_emirates')}{!isEdit && <Need lang={lang} />}</>} />

    {/* ── REGISTRATION = THE MANDATORY SIX ───────────────────────────────────────────────────────
        Founder decision: name, mobile, e-mail (both verified), trade licence, company profile, signed
        terms; everything else optional (memory: supplier-verification-mandatory-six). The 8 Aug
        "five things" note (licence, profile, catalogue, mobile, e-mail) is superseded: the catalogue is
        optional. Contact name, products and services stay on the Profile tab, asked once inside. */}
    <h3 className={cn(S.h2, 'mt-4')}>{t(lang, 'h_trade')}{ok(licOnFile || !!String(f.trade_license_no || '').trim())}{!isEdit && <Need lang={lang} req />}</h3>
    {!isEdit && <>
      <div className={cn(S.sub, 'mb-1.5')}>{t(lang, 'trade_sub')}</div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5"><FilePick lang={lang} accept="image/*,application/pdf" onPick={(fl) => fl && upLicense(fl)} />{uploading && <span className={S.sub} role="status">{t(lang, 'reading_lic')}</span>}</div>
      {licNote && <div role="status" className={cn(S.sub, 'font-semibold text-primary')}>{licNote}</div>}
    </>}
    <div className={S.frow}>
      <Lbl className="flex-1 min-w-[180px]" visible need={isEdit ? null : 'opt'} lang={lang} text={t(lang, 'lic_no')}><Input dir="ltr" placeholder={t(lang, 'lic_no')} value={f.trade_license_no} onChange={(e) => set('trade_license_no', e.target.value)} /></Lbl>
      <Lbl className="flex-1 min-w-[180px]" visible need={isEdit ? null : 'opt'} lang={lang} text={t(lang, 'authority')}><Input placeholder={t(lang, 'authority')} value={f.license_authority} onChange={(e) => set('license_authority', e.target.value)} /></Lbl>
    </div>

    <h3 className={cn(S.h2, 'mt-4')}>{t(lang, 'pf_contact')}{ok(phoneVerified && emailVerified)}{!isEdit && <Need lang={lang} req />}</h3>
    {/* E-mail is shown with its state, never asked for again: the supplier signed in with it. */}
    <div className={cn(S.sub, 'mb-1.5')}>
      <span dir="ltr">{me.claimed_by || ''}</span>
      {emailVerified
        ? <b className="text-primary"> · {t(lang, 'email_verified')}</b>
        : <b className="text-warn-fg"> · {t(lang, 'email_unverified')}</b>}
    </div>
    {!emailVerified && (!mailSent
      ? <Button variant="link" className="px-0 h-auto" disabled={vbusy} onClick={sendMail}>{t(lang, 'verify_my_email')}</Button>
      : <div className={S.frow}><Lbl text={t(lang, 'email_code')}><Input inputMode="numeric" autoComplete="one-time-code" dir="ltr" placeholder={t(lang, 'email_code')} value={mailCode} onChange={(e) => setMailCode(e.target.value)} /></Lbl><Button size="sm" disabled={vbusy} onClick={verifyMail}>{t(lang, 'verify')}</Button></div>)}
    <div className={S.frow}><Lbl className="flex-1" need={isEdit ? null : 'req'} lang={lang} text={t(lang, 'mobile')}><Input type="tel" autoComplete="tel" dir="ltr" inputMode="tel" aria-describedby="qd-mobile-fmt" aria-invalid={!!f.phone && !uaeMobile(f.phone)} aria-required={!isEdit} readOnly={smsSent && !phoneVerified} placeholder="05X XXX XXXX" value={f.phone} onChange={(e) => set('phone', e.target.value)} /></Lbl></div>
    <div id="qd-mobile-fmt" className={cn(S.sub, 'mt-1 text-[12px]', f.phone && !uaeMobile(f.phone) && !phoneVerified && 'text-danger-fg')}>{t(lang, 'mobile_format')}</div>
    {phoneVerified ? <div className={cn(S.sub, 'font-semibold text-primary')}>{t(lang, 'mobile_verified')}</div> : (!smsSent ? <Button variant="link" className="px-0 h-auto mt-1.5" disabled={vbusy} onClick={sendSms}>{vbusy ? t(lang, 'sending') : t(lang, 'verify_my_mobile')}</Button> : <><div className={S.hint}>{t(lang, 'junk_note')}</div><div className={S.frow}><Lbl text={t(lang, 'sms_code')}><Input inputMode="numeric" autoComplete="one-time-code" dir="ltr" placeholder={t(lang, 'sms_code')} value={smsCode} onChange={(e) => setSmsCode(e.target.value)} /></Lbl><Button size="sm" disabled={vbusy} onClick={verifySms}>{t(lang, 'verify')}</Button></div>
      {/* The number is read-only while a code is out, so verify_sms checks the number that was texted
          (review of #695); this reopens it. */}
      <Button variant="link" className="px-0 h-auto" onClick={() => { setSmsSent(false); setSmsCode(''); setMsg(''); }}>{t(lang, 'change_mobile')}</Button></>)}
    {/* NOT `!isEdit` (21 Sep 2026, campaign registration walk). An INVITED supplier claims a listing
        that already exists, so Onboarding never runs and they finish registering on the Profile tab —
        edit mode. save() below demands this answer from every supplier not yet approved, and the
        question was rendered only outside edit mode: "Still needed to register: Your answer on your
        WhatsApp number" with nothing on screen to answer it, a dead end for every invited supplier.
        The question now shows exactly when save() would ask for it.
        Prevented by scripts/checks/an_invited_supplier_can_finish_registering.test.mjs. */}
    {me.approval_status !== 'approved' && phoneVerified && !waSignupSettled(wa) && <div className="mt-3">
      {/* Enforced by save() like the six, so it carries the same Required marker (review of #695). */}
      {/* S.h2 like the other required headers, but not a heading: WhatsAppChoice's own h2 follows. */}
      <div className={cn(S.h2, 'mb-1')}>{srvText(lang, 'reg_whatsapp')}<Need lang={lang} req /></div>
      <WhatsAppChoice token={token} lang={lang} mode="signup" current={wa} mobile={f.phone} onDone={() => loadKyc()} /></div>}

    {/* The contact person is asked at sign-up too (Optional), not only once inside. */}
    <div className={S.frow}><Lbl className="flex-1" need={isEdit ? null : 'opt'} lang={lang} text={t(lang, 'contact_name')}><Input autoComplete="name" dir="auto" placeholder={t(lang, 'contact_name')} value={f.contact_name} onChange={(e) => set('contact_name', e.target.value)} /></Lbl>{isEdit && <Lbl className="flex-1" text={t(lang, 'signatory')}><Input placeholder={t(lang, 'signatory')} value={f.signatory_name} onChange={(e) => set('signatory_name', e.target.value)} /></Lbl>}</div>
    {isEdit && <>
      <h3 className={cn(S.h2, 'mt-4')}>{t(lang, 'h_offer')}</h3>
      <Lbl text={t(lang, 'products_ph')}><Input className="mt-3" placeholder={t(lang, 'products_ph')} value={f.products} onChange={(e) => set('products', e.target.value)} /></Lbl>
      <Lbl text={t(lang, 'services_ph')}><Input className="mt-3" placeholder={t(lang, 'services_ph')} value={f.services} onChange={(e) => set('services', e.target.value)} /></Lbl>
      <Lbl text={t(lang, 'desc_ph')}><textarea className={S.area} rows={3} placeholder={t(lang, 'desc_ph')} value={f.description} onChange={(e) => set('description', e.target.value)} /></Lbl>
    </>}
    {!isEdit && <>
      <h3 className={cn(S.h2, 'mt-4')}>{t(lang, 'doc_profile')}{ok(!!profileFile || !!me.company_profile_doc_path)}<Need lang={lang} req /></h3>
      <div className={cn(S.sub, 'mb-1')}>{ar ? 'الملف التعريفي مطلوب؛ الكتالوجات اختيارية ويمكن إضافتها لاحقًا من تبويب المستندات.' : 'The company profile is required; catalogues are optional and can be added later from Documents.'}</div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5"><span className={S.sub}>{t(lang, 'company_profile_pdf')}</span><FilePick lang={lang} accept=".pdf,.jpg,.jpeg,.png" onPick={(fl) => { setProfileFile(fl); setDocsSent(false); }} />{profileFile && <span className={S.sub}>{profileFile.name}</span>}</div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5"><span className={S.sub}>{t(lang, 'catalogs_ph')}<Need lang={lang} /></span><FilePick lang={lang} accept=".pdf,.jpg,.jpeg,.png" multiple onPick={(a) => { const all = a || []; setCatalogFiles(all.slice(0, 5)); setCatCut(all.length > 5); setDocsSent(false); }} />{catalogFiles.length ? <span className={S.sub}>{catalogFiles.length} {t(lang, 'selected')}</span> : null}</div>
      {/* Catalogues were cut to 5 silently (audit 15 Sep 2026). The limit is stated, and a cut is announced. */}
      <div role={catCut ? 'status' : undefined} className={cn(S.sub, 'mt-1 text-[12px]', catCut && 'font-semibold text-warn-fg')}>{t(lang, catCut ? 'catalogs_cut' : 'catalogs_limit')}</div>
    </>}
    {isEdit && <div className={cn(S.sub, 'mt-3 rounded-md border border-border bg-secondary/30 px-3 py-2.5')}>{ar ? 'تُدار الرخصة التجارية والملف التعريفي والكتالوجات من تبويب المستندات، حتى لا يُطلب الملف نفسه في مكانين.' : 'Your trade licence, company profile and catalogues are managed in the Documents tab — so the same file is never asked for in two places.'}</div>}

    <label className="flex gap-2 items-center mt-3.5 text-[13px] text-muted-foreground"><input type="checkbox" aria-required={!isEdit} checked={terms} onChange={(e) => setTerms(e.target.checked)} /> {t(lang, 'accept_pre')}<a href={(ar ? '/ar' : '') + '/supplier-agreement'} target="_blank" rel="noopener" className="text-primary font-semibold">{t(lang, 'terms_link')}</a>{t(lang, 'accept_post')}{!isEdit && <Need lang={lang} req />}</label>
    <Button className="w-full mt-3" disabled={busy || uploading} onClick={save}>
      {busy ? (isEdit ? (ar ? 'جارٍ الحفظ…' : 'Saving…') : t(lang, 'submitting'))
            : isEdit ? (ar ? 'حفظ التغييرات' : 'Save changes') : t(lang, 'submit_approval')}
    </Button>
    {msg && <div role="alert" className={S.err}>{msg}</div>}
    {saved && !msg && <div role="status" className={cn(S.sub, 'mt-2 font-semibold text-primary')}>{ar ? 'تم حفظ التغييرات.' : 'Changes saved.'}</div>}
  </Card>);
}
