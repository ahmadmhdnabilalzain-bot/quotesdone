// @ts-nocheck
'use client';
import { useEffect, useRef, useState } from 'react';
import { createClient } from '@supabase/supabase-js';
// 14 Sep 2026: the row-#5 intelligence panels are no longer top-level tabs; ./supplier/Insights loads
// the ones whose routine has something to show, each on demand. The AI onboarding chat
// (SupplierOnboarding) is not reachable while the OpenRouter hold stands — it has no model to call,
// and the registration it duplicated is the deterministic ProfileForm below.
import SupplierSettings from './supplier/SupplierSettings';
import SupplierDocumentImpact from './supplier/SupplierDocumentImpact';
import SupplierEntryHero from './supplier/SupplierEntryHero';
import SupplierCommandPalette from './supplier/SupplierCommandPalette';
import GetMatched from './supplier/GetMatched';
import Insights, { INSIGHT_PANELS } from './supplier/Insights';
import { DrawingGallery, BoqTable, ClarifyThread, WithheldCustomer, RequestedTerms } from './supplier/RfqParts';
import { SpecHoldPanel } from './supplier/SpecHold';
import { Kicker } from '@/components/ui/sealed';
import { srvMsg, srvText, itemCopy, emirateLabel, vocabLabel, CATEGORY_AR } from './supplier/serverCopy';
import { call } from './supplier/api';
import { categoryLabel } from '@/lib/categoryLabel';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { BrandMark } from '@/components/BrandMark';

// Same as the customer portal: an inline production fallback meant an unconfigured preview let
// suppliers upload trade licences into the LIVE database. See supaEnv.
import { SUPA_URL as URL, SUPA_ANON as ANON, SUPA_FN as FN } from '@/lib/supaEnv';
const SB = createClient(URL, ANON, { auth: { persistSession: true, autoRefreshToken: true, storageKey: 'qd-portal-auth' } });

// call() lives in ./supplier/api.ts, shared with the journey, RFQ and insights components.
// Every field carries a <label> (audit 2026-09-14: three unlabeled fields, the Emirate <select> with
// no accessible name at all). Visually hidden where a placeholder already shows the same words.
function Lbl({ text, children, className = '', visible = false }) {
  return <label className={cn('block min-w-0', className)}><span className={visible ? 'mb-1 block text-[12px] font-semibold text-muted-foreground' : 'sr-only'}>{text}</span>{children}</label>;
}
const aed = (n) => 'AED ' + Number(n || 0).toLocaleString('en-AE', { maximumFractionDigits: 0 });
// Amounts, phone numbers, e-mails, dates and reference codes are left-to-right runs. Inside the Arabic
// portal an unisolated "AED 12,500" or "+971 50 …" is reordered by the bidi algorithm around the
// Arabic text beside it (portal audit 14 Sep 2026); <bdi dir="ltr"> keeps each one whole.
const Ltr = ({ children, className = '' }) => <bdi dir="ltr" className={className}>{children}</bdi>;
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
const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Umm Al Quwain', 'Fujairah'];
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
          ? 'استلمت Stripe دفعتك وسترسل إليك الفاتورة بالبريد الإلكتروني. يتحدّث رصيدك هنا فور تأكيد Stripe لنا، عادةً خلال دقيقة.'
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
        ? 'التسجيل مجاني بشكل دائم لأول 1,000 مورّد؛ واعتبارًا من التسجيل رقم 1,001 تكون الرسوم 1,000 درهم سنويًا. إن كانت رسوم مستحقة عليك تنتقل مباشرة إلى صفحة الدفع الآمنة في Stripe، وإلا نخبرك بالسبب.'
        : 'Registration is permanently free for the first 1,000 suppliers; from the 1,001st registration it is AED 1,000 per year. If a fee is due you go straight to Stripe’s secure checkout; if not, we tell you why.'}</div>
      <Button className="mt-3" variant="outline" disabled={busy} onClick={check}>{busy ? (ar ? 'جارٍ التحقق…' : 'Checking…') : (ar ? 'تحقّق من رسوم تسجيلي' : 'Check my registration fee')}</Button>
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
  const dispute = async (dueId) => {
    const reason = window.prompt(lang === 'ar' ? 'ما سبب اعتراضك على هذه الرسوم؟' : 'What is wrong with this charge?');
    if (!reason) return;
    const j = await call('supplier_api', { action: 'dispute_charge', due_id: dueId, reason }, token);
    window.alert(j && j.ok
      ? (lang === 'ar' ? 'استلمنا اعتراضك. نراجع الرسوم مقابل سجل الدفع وسنراسلك.' : 'We have your query. We are checking the charge against the payment record and will write back to you.')
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
              <button type="button" className="text-[12px] underline text-muted-foreground" onClick={() => dispute(d.id)}>
                {lang === 'ar' ? 'الاعتراض على هذه الرسوم' : 'Dispute this charge'}
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
  return <div className={S.list}>{receipt ? <ReceiptBanner receipt={receipt} lang={lang} /> : null}{dues}<RegistrationFeeCard token={token} lang={lang} base={base} /></div>;
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
  en: { brand_sub:'Supplier Portal', home:'Home', signout:'Sign out', loading:'Loading…', loading_dash:'Loading your dashboard…',
    tab_signin:'Sign in', tab_signup:'Create account', welcome_back:'Welcome back', register_title:'Register as a supplier',
    signup_sub:"Enter your work email and we'll create your account — then you'll register your company and verify your mobile.",
    signin_sub:'Sign in with the email or mobile you registered with.', work_email:'Work email', email_or_mobile:'Email or mobile',
    create_my_account:'Create my account', send_code:'Send me a code', sending:'Sending…', code_placeholder:'6-digit code',
    verify_continue:'Verify & continue', verify_signin:'Verify & sign in', verifying:'Verifying…', use_diff:'Use a different email/number',
    junk_note:'The code can take a minute — please check your spam/junk folder too.', err_code_send:'Could not send a code.', err_incorrect:'Incorrect code.',
    signup_email_only:"Please sign up with your work email — you'll register your company and verify your mobile next.",
    conflict_customer:'This email is registered as a customer. Please use the customer app to sign in.',
    setup_title:'Set up your supplier account', setup_sub_company:'Register your company, then complete your profile.', setup_sub_profile:'Complete your profile to start receiving RFQs and submitting quotes.',
    onboard_title:'Register your company', onboard_sub:'Enter your company name and main emirate. Registration is free for the first 1,000 suppliers to register, permanently; from the 1,001st registration it is AED 1,000 per year.', company_name:'Company name', emirate:'Emirate', create_company:'Create company', enter_company:'Enter your company name.', err_generic:'Something went wrong.', something_wrong:'Something went wrong',
    t_overview:'Overview', t_billing:'Billing', bill_title:'Amounts due', bill_none:'Nothing to pay. You are not charged commission on the work you win.', bill_total:'Total outstanding', bill_pay:'Pay now', bill_paying:'Opening secure checkout…', bill_err:'We could not load your balance. Please try again.', bill_commission:'Refunded amount recovered', bill_fine:'Late fee', bill_due:'Due', bill_retry:'Try again', bill_secure:'You will be redirected to Stripe to pay securely. QuotesDone never sees your card details. These charges arise only when a customer is refunded because we could not reach you \u2014 there is no commission on won work.', t_rfqs:'RFQs', t_documents:'Documents', t_projects:'Projects', t_messages:'Messages', approved:'Approved', pending:'Pending',
    k_quotes_sent:'Quotes sent', k_reveals:'Reveals', k_hired:'Hired', k_win:'Win ratio', k_rating:'Rating', k_deal_value:'Deal value won',
    price_pos:'Price positioning', anon_note:'anonymous — never shows competitor prices', not_enough:'not enough data', last12:'Last 12 months', quotes_reveals:'quotes / reveals',
    pp_fallback:'Once you quote on a few competitive RFQs, you will see how your pricing compares to the market here — without ever revealing anyone else pricing.',
    pf_company:'Company', pf_emirates:'Emirates you serve', pf_contact:'Contact & owner', contact_name:'Contact name *', mobile:'Mobile *',
    mobile_verified:'✓ Mobile verified', verify_my_mobile:'Verify my mobile →', sms_code:'6-digit SMS code', verify:'Verify',
    email_verified:'✓ E-mail verified', email_unverified:'e-mail not yet verified',
    reg_rest_optional:'Attach these two and you are done. Everything else is optional and can wait until you are inside.',
    wa_alerts:'Send me WhatsApp alerts when a matching RFQ comes in.', verify_first:'Please verify your mobile number first.',
    accept_pre:'I accept the QuotesDone ', terms_link:'supplier terms', accept_post:'.', submit_approval:'Submit for approval', submitting:'Submitting…', must_accept:'Please accept the supplier terms.', loading_rfqs:'Loading RFQs…', no_rfqs_h:'No open RFQs right now', no_rfqs_sub:'When a customer posts a request that matches your capabilities, it appears here.', request_w:'Request', you_won:' · You won', concluded:' · Concluded', quoted:'Quoted ', close:'Close', quote:'Quote', boq_prefix:'BOQ: ', boq_items:'line items', confidence:' confidence', drawing_p:'Drawing p', upload_quote:"Upload your quotation — PDF, photo, Excel, Word, e-mail, CAD or ZIP — and we'll read it:", reading:'Reading…', total_aed:'Total amount (AED)', lead_time:'Lead time (e.g. 10 days)', scope_work:'Scope of work', notes_customer:'Notes for the customer', submit_quote:'Submit quote', enter_valid_amount:'Enter a valid amount.', could_not_read:'Could not read the file — please fill the form.', could_not_submit:'Could not submit.', draft_saved:'Saved as draft — add the missing details to send it.', read_quote_pre:'Read your quotation', line_items:'line items', read_quote_post:'. Review and submit.', loading_docs:'Loading documents…', docs_h:'Documents & certificates', docs_sub:'Upload renewals before they expire — we will remind you here and pause matching if a required document lapses.', st_expired:'Expired', st_expiring:'Expiring soon', st_valid:'Valid', expires_pre:'Expires ', on_file:'On file', not_uploaded:'Not uploaded yet', view:'view', uploading:'Uploading…', upload:'Upload', no_projects_h:'No won projects yet', no_projects_sub:'When a customer reveals and hires you, the project appears here.', project_w:'Project', loading_msgs:'Loading messages…', no_convos_h:'No conversations yet', no_convos_sub:'Once a customer reveals your quote on a project, you can request a direct chat with them here. Our assistant handles most questions instantly.', no_messages:'No messages yet', no_chat:'no chat', back:'← Back', type_message:'Type a message…', send:'Send', no_chat_open:'No chat open yet.', ask_placeholder:"Ask a question — our assistant answers instantly, or opens a direct chat if it's really needed.", ask_request:'Ask / request a chat', assistant_pre:'Assistant: ', could_not_send:'Could not send.', sent_review:'Sent for review — you will be notified if a chat opens.', sent:'Sent.', no_history:'No history yet.', registering_pre:'Registering ', registering_post:'. Registration is free for the first 1,000 suppliers to register, permanently; from the 1,001st registration it is AED 1,000 per year.', corrected:' (corrected from your licence)', signatory:'Authorized signatory', owner_dob:'Owner date of birth', h_trade:'Trade licence', trade_sub:'Upload your licence and we read the number, authority, expiry and TRN automatically.', reading_lic:'Reading licence…', lic_no:'Trade licence no. *', authority:'Authority (DED / free zone)', lic_expiry:'Licence expiry', vat_trn:'VAT no. (TRN)', h_egr:'Establishment (EGR)', egr_no:'Economic Register (EGR) no.', egr_cert:'EGR / establishment certificate:', h_offer:'What you offer', products_ph:'Products you supply (comma separated)', services_ph:'Services you offer', desc_ph:'Short company description / capabilities', company_profile_pdf:'Company profile (PDF):', catalogs_ph:'Product catalogs (up to 5):', h_bank:'Bank / payout', bank_name_ph:'Bank name', account_holder:'Account holder name', add_contact_phone:'Add your contact name and phone.', add_license:'Add your trade licence number (or upload your licence to auto-fill it).', could_not_save:'Could not save your profile.', save_error:'Something went wrong saving your profile. Please try again.', lic_on_file:'Trade licence on file.', could_not_sms:'Could not send SMS.', wrong_code:'Wrong code.', read_lic:'Read your licence', expires_comma:', expires ', lic_uploaded:'Licence uploaded.', lic_uploaded_noread:'Uploaded (could not auto-read).', attach_file:'Attach file', selected:'selected', lic_expires:'Licence expires', lic_expired:'Licence expired', action_required:'Action required', ar_days_left:'days left to fix this', ar_overdue:'Overdue - your account can be suspended', ar_why:'Why', catalogues:'Catalogues', doc_profile:'Company profile', doc_iso:'ISO certification', add_profile:'Please attach your company profile (required).',
    lic_uploaded_type:'Licence uploaded. If the number did not fill in, type it below — automatic reading is optional.', lic_upload_failed:'We could not store your licence file. Please try again with a PDF or a clear photo.',
    verify_my_email:'Verify my e-mail →', email_code:'6-digit e-mail code', email_sent:'We emailed you a 6-digit code.', could_not_email:'Could not send the e-mail code.',
    cat_label:'Your trade or category', cat_ph:'e.g. Electrical, AC, Cleaning — type your own if not listed', cat_help:'Every trade is welcome — if yours isn’t listed, just type it in.', emirate_ph:'Choose your main emirate',
    t_quotes:'Quotes', t_insights:'Insights', t_profile:'Profile', t_scope:'My scope', t_settings:'Settings', main_nav:'Supplier portal sections', account:'Account' },
  ar: { brand_sub:'بوابة المورّدين', home:'الرئيسية', signout:'تسجيل الخروج', loading:'جارٍ التحميل…', loading_dash:'جارٍ تحميل لوحتك…',
    tab_signin:'تسجيل الدخول', tab_signup:'إنشاء حساب', welcome_back:'مرحبًا بعودتك', register_title:'سجّل كمورّد',
    signup_sub:'أدخل بريدك الإلكتروني للعمل وسننشئ حسابك — ثم تسجّل شركتك وتتحقق من رقم جوالك.',
    signin_sub:'سجّل الدخول بالبريد الإلكتروني أو رقم الجوال المسجّل.', work_email:'البريد الإلكتروني للعمل', email_or_mobile:'البريد الإلكتروني أو الجوال',
    create_my_account:'إنشاء حسابي', send_code:'أرسل لي رمزًا', sending:'جارٍ الإرسال…', code_placeholder:'رمز من 6 أرقام',
    verify_continue:'تحقّق وتابع', verify_signin:'تحقّق وسجّل الدخول', verifying:'جارٍ التحقق…', use_diff:'استخدم بريدًا أو رقمًا آخر',
    junk_note:'قد يستغرق وصول الرمز دقيقة — يُرجى التحقق من مجلد الرسائل غير المرغوب فيها (Spam) أيضًا.', err_code_send:'تعذّر إرسال الرمز.', err_incorrect:'رمز غير صحيح.',
    signup_email_only:'يُرجى التسجيل ببريدك الإلكتروني للعمل — ستسجّل شركتك وتتحقق من جوالك لاحقًا.',
    conflict_customer:'هذا البريد مسجّل كعميل. يُرجى استخدام تطبيق العملاء لتسجيل الدخول.',
    setup_title:'أنشئ حساب المورّد', setup_sub_company:'سجّل شركتك ثم أكمل ملفك.', setup_sub_profile:'أكمل ملفك لبدء استقبال طلبات التسعير وتقديم العروض.',
    onboard_title:'سجّل شركتك', onboard_sub:'أدخل اسم شركتك وإمارتك الرئيسية. التسجيل مجاني لأول 1,000 مورّد يسجّلون، إعفاءً دائمًا؛ واعتبارًا من التسجيل رقم 1,001 تكون الرسوم 1,000 درهم إماراتي سنويًا.', company_name:'اسم الشركة', emirate:'الإمارة', create_company:'إنشاء الشركة', enter_company:'أدخل اسم شركتك.', err_generic:'حدث خطأ ما.', something_wrong:'حدث خطأ ما',
    t_overview:'نظرة عامة', t_billing:'الفواتير', bill_title:'المبالغ المستحقة', bill_none:'لا توجد مبالغ مستحقة. لا نأخذ أي عمولة على الأعمال التي تفوز بها.', bill_total:'إجمالي المستحق', bill_pay:'ادفع الآن', bill_paying:'جارٍ فتح صفحة الدفع الآمنة…', bill_err:'تعذّر تحميل رصيدك. يرجى المحاولة مرة أخرى.', bill_commission:'استرداد المبلغ المردود للعميل', bill_fine:'رسوم التأخير', bill_due:'تاريخ الاستحقاق', bill_retry:'حاول مرة أخرى', bill_secure:'سيتم تحويلك إلى Stripe للدفع بأمان. لا تطّلع QuotesDone على بيانات بطاقتك. تنشأ هذه المبالغ فقط عند استرداد مبلغ للعميل لتعذّر الوصول إليك \u2014 ولا توجد عمولة على الأعمال المنجزة.', t_rfqs:'طلبات التسعير', t_documents:'المستندات', t_projects:'المشاريع', t_messages:'الرسائل', approved:'معتمد', pending:'قيد المراجعة',
    k_quotes_sent:'العروض المُرسلة', k_reveals:'مرات الكشف', k_hired:'المُتعاقد معه', k_win:'نسبة الفوز', k_rating:'التقييم', k_deal_value:'قيمة الصفقات',
    price_pos:'الموقع السعري', anon_note:'مجهول — لا يعرض أسعار المنافسين أبدًا', not_enough:'بيانات غير كافية', last12:'آخر 12 شهرًا', quotes_reveals:'عروض / كشوفات',
    pp_fallback:'بمجرد تقديمك عروضًا على بعض طلبات التسعير التنافسية، سترى هنا كيف تقارن أسعارك بالسوق — دون الكشف عن أسعار أي طرف آخر.',
    pf_company:'الشركة', pf_emirates:'الإمارات التي تخدمها', pf_contact:'جهة الاتصال والمالك', contact_name:'اسم جهة الاتصال *', mobile:'الجوال *',
    mobile_verified:'✓ تم التحقق من الجوال', verify_my_mobile:'تحقّق من جوالي ←', sms_code:'رمز الرسالة (6 أرقام)', verify:'تحقّق',
    email_verified:'✓ تم التحقق من البريد', email_unverified:'لم يتم التحقق من البريد بعد',
    reg_rest_optional:'أرفق هذين الملفين وانتهيت. كل ما عدا ذلك اختياري ويمكن إكماله بعد الدخول.',
    wa_alerts:'أرسل لي تنبيهات واتساب عند وصول طلب تسعير مطابق.', verify_first:'يُرجى التحقق من رقم جوالك أولًا.',
    accept_pre:'أوافق على ', terms_link:'شروط المورّد', accept_post:' الخاصة بمنصة QuotesDone.', submit_approval:'إرسال للموافقة', submitting:'جارٍ الإرسال…', must_accept:'يُرجى الموافقة على شروط المورّد.', loading_rfqs:'جارٍ تحميل طلبات التسعير…', no_rfqs_h:'لا توجد طلبات تسعير مفتوحة حاليًا', no_rfqs_sub:'عندما ينشر عميل طلبًا يطابق إمكانياتك، سيظهر هنا.', request_w:'طلب', you_won:' · فزت بالطلب', concluded:' · مُغلق', quoted:'قدّمت عرضًا: ', close:'إغلاق', quote:'قدّم عرضًا', boq_prefix:'جدول الكميات: ', boq_items:'بند', confidence:' ثقة', drawing_p:'المخطط ص', upload_quote:'ارفع عرض السعر — PDF أو صورة أو Excel أو Word أو بريد إلكتروني أو ملف CAD أو ZIP — وسنقرأه:', reading:'جارٍ القراءة…', total_aed:'المبلغ الإجمالي (درهم)', lead_time:'مدة التنفيذ (مثال: 10 أيام)', scope_work:'نطاق العمل', notes_customer:'ملاحظات للعميل', submit_quote:'إرسال العرض', enter_valid_amount:'أدخل مبلغًا صحيحًا.', could_not_read:'تعذّرت قراءة الملف — يُرجى تعبئة النموذج.', could_not_submit:'تعذّر الإرسال.', draft_saved:'حُفظ كمسودة — أضف التفاصيل الناقصة لإرساله.', read_quote_pre:'قرأنا عرضك', line_items:'بند', read_quote_post:'. راجعه وأرسله.', loading_docs:'جارٍ تحميل المستندات…', docs_h:'المستندات والشهادات', docs_sub:'ارفع التجديدات قبل انتهائها — سنذكّرك هنا وسنوقف المطابقة إذا انتهى مستند مطلوب.', st_expired:'منتهٍ', st_expiring:'ينتهي قريبًا', st_valid:'سارٍ', expires_pre:'ينتهي في ', on_file:'محفوظ', not_uploaded:'لم يُرفع بعد', view:'عرض', uploading:'جارٍ الرفع…', upload:'رفع', no_projects_h:'لا توجد مشاريع فائزة بعد', no_projects_sub:'عندما يكشف العميل عن عرضك ويتعاقد معك، يظهر المشروع هنا.', project_w:'مشروع', loading_msgs:'جارٍ تحميل الرسائل…', no_convos_h:'لا توجد محادثات بعد', no_convos_sub:'بمجرد أن يكشف العميل عن عرضك في مشروع، يمكنك طلب محادثة مباشرة معه هنا. مساعدنا يجيب عن معظم الأسئلة فورًا.', no_messages:'لا رسائل بعد', no_chat:'لا محادثة', back:'→ رجوع', type_message:'اكتب رسالة…', send:'إرسال', no_chat_open:'لا توجد محادثة مفتوحة بعد.', ask_placeholder:'اطرح سؤالًا — يجيب مساعدنا فورًا، أو يفتح محادثة مباشرة عند الحاجة فعلًا.', ask_request:'اسأل / اطلب محادثة', assistant_pre:'المساعد: ', could_not_send:'تعذّر الإرسال.', sent_review:'أُرسل للمراجعة — سنُعلمك إذا فُتحت محادثة.', sent:'أُرسل.', no_history:'لا يوجد سجل بعد.', registering_pre:'تسجيل ', registering_post:'. التسجيل مجاني لأول 1,000 مورّد يسجّلون، إعفاءً دائمًا؛ واعتبارًا من التسجيل رقم 1,001 تكون الرسوم 1,000 درهم إماراتي سنويًا.', corrected:' (مُصحّح من رخصتك)', signatory:'المفوّض بالتوقيع', owner_dob:'تاريخ ميلاد المالك', h_trade:'الرخصة التجارية', trade_sub:'ارفع رخصتك وسنقرأ الرقم والجهة وتاريخ الانتهاء والرقم الضريبي تلقائيًا.', reading_lic:'جارٍ قراءة الرخصة…', lic_no:'رقم الرخصة التجارية *', authority:'الجهة (دائرة التنمية الاقتصادية / منطقة حرة)', lic_expiry:'انتهاء الرخصة', vat_trn:'الرقم الضريبي (TRN)', h_egr:'المنشأة (السجل الاقتصادي)', egr_no:'رقم السجل الاقتصادي (EGR)', egr_cert:'شهادة السجل الاقتصادي / المنشأة:', h_offer:'ما الذي تقدّمه', products_ph:'المنتجات التي توردها (مفصولة بفواصل)', services_ph:'الخدمات التي تقدّمها', desc_ph:'وصف مختصر للشركة / القدرات', company_profile_pdf:'الملف التعريفي للشركة (PDF):', catalogs_ph:'كتالوجات المنتجات (حتى 5):', h_bank:'البنك / التحويل', bank_name_ph:'اسم البنك', account_holder:'اسم صاحب الحساب', add_contact_phone:'أضف اسم جهة الاتصال ورقم الهاتف.', add_license:'أضف رقم رخصتك التجارية (أو ارفع الرخصة لتعبئته تلقائيًا).', could_not_save:'تعذّر حفظ ملفك.', save_error:'حدث خطأ أثناء حفظ ملفك. يُرجى المحاولة مرة أخرى.', lic_on_file:'الرخصة التجارية محفوظة.', could_not_sms:'تعذّر إرسال الرسالة.', wrong_code:'رمز خاطئ.', read_lic:'قرأنا رخصتك', expires_comma:'، تنتهي في ', lic_uploaded:'تم رفع الرخصة.', lic_uploaded_noread:'تم الرفع (تعذّرت القراءة التلقائية).', attach_file:'إرفاق ملف', selected:'محدد', lic_expires:'تنتهي الرخصة', lic_expired:'انتهت الرخصة', action_required:'إجراء مطلوب', ar_days_left:'يوماً متبقياً لمعالجة هذا', ar_overdue:'تجاوز الموعد - قد يُعلَّق حسابك', ar_why:'السبب', catalogues:'الكتالوجات', doc_profile:'الملف التعريفي للشركة', doc_iso:'شهادة ISO', add_profile:'يُرجى إرفاق الملف التعريفي للشركة (مطلوب).',
    lic_uploaded_type:'تم رفع الرخصة. إن لم يظهر الرقم تلقائيًا فاكتبه أدناه — القراءة التلقائية اختيارية.', lic_upload_failed:'تعذّر حفظ ملف الرخصة. يُرجى المحاولة مرة أخرى بملف PDF أو صورة واضحة.',
    verify_my_email:'تحقّق من بريدي ←', email_code:'رمز البريد (6 أرقام)', email_sent:'أرسلنا إليك رمزًا من 6 أرقام بالبريد الإلكتروني.', could_not_email:'تعذّر إرسال رمز البريد.',
    cat_label:'تخصصك أو فئتك', cat_ph:'مثال: كهرباء، تكييف، تنظيف — اكتب تخصصك إن لم يكن مدرجًا', cat_help:'كل التخصصات مرحّب بها — إن لم يكن تخصصك مدرجًا فاكتبه.', emirate_ph:'اختر إمارتك الرئيسية',
    t_quotes:'العروض', t_insights:'الرؤى', t_profile:'الملف', t_scope:'نطاق عملي', t_settings:'الإعدادات', main_nav:'أقسام بوابة المورّدين', account:'الحساب' }
};
const t = (lang, k) => (T[lang] && T[lang][k]) || T.en[k] || k;
// The URL decides the language (14 Sep 2026). /ar/portal must render Arabic and /portal English, the
// same as every other page and the same as the page's own <title>; a remembered localStorage choice
// used to override the URL, so a shared /ar/portal link could open in English.
function initLang(){ try{ if(typeof window==='undefined') return 'en'; return /^\/ar(\/|$)/.test(window.location.pathname) ? 'ar' : 'en'; }catch(_e){} return 'en'; }
function switchLang(to){ try{ localStorage.setItem('qd-lang', to); document.cookie = 'NEXT_LOCALE=' + to + ';path=/;max-age=31536000;samesite=lax'; }catch(_e){} const p = window.location.pathname.replace(/^\/ar(?=\/|$)/, '') || '/'; window.location.href = (to === 'ar' ? '/ar' : '') + (p === '/' && to === 'ar' ? '' : p) + window.location.search; }
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

// WHAT THIS COMPANY CAN ACTUALLY QUOTE FOR — the last gate on the revenue path (12 Aug 2026).
//
// fn_match_capability's candidate CTE opens with `where sc.confirmed_at is not null` and the comment
// beside it reads "GATE: supplier confirmed their own scope". capability_agent's `confirm` action is
// the only writer of that column. It is complete, it validates against the controlled vocabulary,
// it versions every confirmation into supplier_capability_confirmation — and it had NO CALLER
// ANYWHERE IN src/. Neither did claim_lookup. So no supplier could ever be matched to anything: not
// because matching was broken, but because the one screen that unlocks it was never built.
//
// It is a CONFIRMATION screen, not a form, and that distinction is the whole point. The company has
// already derived this supplier's trades from its own directory entry and its role from
// leads.business_role, so the supplier is asked to correct a proposal rather than fill in a blank.
// On a cold B2B onboarding those are very different asks.
//
// Nothing here can widen a scope silently: every code is rendered from the vocabulary the server
// returns, and the server re-validates against taxonomy_trade / taxonomy_role on the way in.
function CapabilityConfirmPanel({ token, lang }) {
  const ar = lang === 'ar';
  const [st, setSt] = useState({ loading: true, err: '', confirmed: false, cap: null, vocab: { trades: [], roles: [] } });
  const [trades, setTrades] = useState([]);
  const [roles, setRoles] = useState([]);
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);
  // WHAT WE ALREADY BELIEVE, FIRST. Measured on a 375x812 phone: the vocabulary renders 40 trade
  // chips and 8 role chips in taxonomy sort order, so the four this company actually holds were
  // scattered through the list and the confirm button sat 2,547px down — 3.1 screens of scrolling.
  // The header above says this is a CONFIRMATION screen and not a form; a supplier cannot correct a
  // proposal they have to hunt for. Pinned once, from the row as loaded, and never re-sorted on a
  // toggle: chips that jump under a thumb are worse than chips in the wrong order.
  const [pinned, setPinned] = useState({ trades: [], roles: [] });
  const order = (vocab, pin) => {
    const p = new Set(pin);
    return [...(vocab || [])].sort((a, b) => (p.has(b.code) ? 1 : 0) - (p.has(a.code) ? 1 : 0));
  };

  const load = async () => {
    setSt((s) => ({ ...s, loading: true, err: '' }));
    const j = await call('supplier_api', { action: 'capability_state' }, token);
    if (j && j.ok) {
      const cap = j.capability || null;
      setTrades((cap && cap.trades) || []);
      setRoles((cap && cap.roles) || []);
      setPinned({ trades: (cap && cap.trades) || [], roles: (cap && cap.roles) || [] });
      setSt({ loading: false, err: '', confirmed: !!j.confirmed, cap, vocab: j.vocabulary || { trades: [], roles: [] } });
    } else {
      setSt((s) => ({ ...s, loading: false, err: srvMsg(lang, j, ar ? 'تعذّر تحميل نطاق عملك.' : 'Could not load your scope.') }));
    }
  };
  useEffect(() => { load(); }, [token]);

  const toggle = (arr, setArr, code) => setArr(arr.includes(code) ? arr.filter((c) => c !== code) : arr.concat(code));

  const confirm = async () => {
    setBusy(true); setSaved(false);
    const cap = st.cap || {};
    // Everything the derivation already holds is sent back unchanged. Omitting a key on a
    // merge-duplicates upsert leaves the stored value alone, but sending what is on screen keeps
    // the confirmed row and the screen the supplier saw identical.
    const j = await call('supplier_api', {
      action: 'capability_confirm', trades, roles,
      services: cap.services || [], products: cap.products_norm || [],
      coverage_emirates: cap.coverage_emirates || [],
      brands: cap.brands || [], project_types: cap.project_types || [], exclusions: cap.exclusions || [],
    }, token);
    setBusy(false);
    if (j && j.ok) { setSaved(true); load(); }
    else setSt((s) => ({ ...s, err: srvMsg(lang, j, ar ? 'تعذّر حفظ نطاق عملك.' : 'Could not save your scope.') }));
  };

  if (st.loading) return <Card className="qd-panel p-5">{ar ? 'جارٍ التحميل…' : 'Loading…'}</Card>;
  if (st.err && !st.cap) return (
    <Card className="qd-panel p-5">
      <div className={S.h2}>{ar ? 'تعذّر تحميل نطاق عملك' : 'Could not load your scope'}</div>
      <div className={S.sub}>{String(st.err)}</div>
      <Button className="mt-3" onClick={load}>{ar ? 'إعادة المحاولة' : 'Retry'}</Button>
    </Card>
  );

  const chip = (on) => cn('px-3 py-1.5 rounded-full text-sm border transition',
    on ? 'bg-emerald-600 text-white border-emerald-600' : 'bg-transparent border-white/20 hover:border-white/40');

  return (
    <Card className="qd-panel p-5">
      <div className={S.h2}>{ar ? 'ما الذي يمكن لشركتك تسعيره' : 'What your company can quote for'}</div>
      <div className={S.sub}>
        {st.confirmed
          ? (ar ? 'نطاقك مؤكَّد. تظهر طلبات التسعير المطابقة في تبويب طلبات التسعير.'
                : 'Your scope is confirmed. Matching requests appear in the RFQs tab.')
          : (ar ? 'هذا ما سجّلناه عن شركتك. صحّحه ثم أكّده — لن تصلك طلبات تسعير قبل التأكيد.'
                : 'This is what we have on file for your company. Correct it, then confirm — you will not receive any requests until you do.')}
      </div>

      <div className="mt-4">
        <div className="text-sm opacity-70 mb-2">{ar ? 'التخصصات' : 'Trades'}</div>
        <div className="flex flex-wrap gap-2">
          {order(st.vocab.trades, pinned.trades).map((tr) => (
            <button key={tr.code} type="button" className={chip(trades.includes(tr.code))}
                    aria-pressed={trades.includes(tr.code)}
                    onClick={() => toggle(trades, setTrades, tr.code)}>{vocabLabel(lang, 'trade', tr.code, tr.label)}</button>
          ))}
        </div>
      </div>

      <div className="mt-4">
        <div className="text-sm opacity-70 mb-2">{ar ? 'دورك' : 'Your role'}</div>
        <div className="flex flex-wrap gap-2">
          {order(st.vocab.roles, pinned.roles).map((r) => (
            <button key={r.code} type="button" className={chip(roles.includes(r.code))}
                    aria-pressed={roles.includes(r.code)}
                    onClick={() => toggle(roles, setRoles, r.code)}>{vocabLabel(lang, 'role', r.code, r.label)}</button>
          ))}
        </div>
      </div>

      {/* The server refuses a confirm with no trade or no role. Say so here rather than letting the
          supplier press a button that returns 400. */}
      {(!trades.length || !roles.length) && (
        <div className="mt-4 text-sm text-warn">
          {ar ? 'اختر تخصصًا واحدًا ودورًا واحدًا على الأقل.' : 'Choose at least one trade and one role.'}
        </div>
      )}
      {st.err && st.cap ? <div className="mt-3 text-sm text-danger">{String(st.err)}</div> : null}
      {saved ? <div className="mt-3 text-sm text-ok">{ar ? 'تم التأكيد.' : 'Confirmed.'}</div> : null}

      {/* STICKY, BECAUSE OF WHERE IT WAS. On a 375x812 phone this button rendered at y=2547 —
          3.1 screens below the fold, past 48 chips, after a 366px tab strip. The ask that unlocks
          every RFQ was the last thing on the longest screen in the portal. It now travels with the
          thumb, and carries the count so a supplier can see what they are confirming without
          scrolling back up. Unconfirmed only: once the scope is confirmed this is an edit screen
          and a permanently docked bar would be noise. */}
      {/* pe-16 on mobile: the docked assistant bubble is position:fixed at the bottom-end corner and
          sits above this bar, and it was covering 29px of the button. A chat launcher must not eat
          the edge of the one control that unlocks every RFQ. */}
      <div className={cn('mt-4', !st.confirmed && 'sticky bottom-0 -mx-5 -mb-5 px-5 pe-16 sm:pe-5 pb-5 pt-3 bg-card/85 backdrop-blur-md border-t border-border')}>
        {!st.confirmed && (
          <div className={cn(S.sub, 'mb-2')}>
            {ar ? `${trades.length} تخصص · ${roles.length} دور` : `${trades.length} trade${trades.length === 1 ? '' : 's'} · ${roles.length} role${roles.length === 1 ? '' : 's'} selected`}
          </div>
        )}
        <Button className="w-full sm:w-auto" disabled={busy || !trades.length || !roles.length} onClick={confirm}>
          {busy ? (ar ? 'جارٍ الحفظ…' : 'Saving…')
                : st.confirmed ? (ar ? 'تحديث النطاق' : 'Update my scope')
                               : (ar ? 'تأكيد نطاق عملي' : 'Confirm my scope')}
        </Button>
      </div>
    </Card>
  );
}

export function SupplierPortal() {
  const [lang, setLang] = useState('en');
  const [token, setToken] = useState('');
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
  const claimIfInvited = async (access) => {
    let t = '';
    try { t = sessionStorage.getItem(CLAIM_KEY) || ''; } catch (_e) {}
    if (!UUID_RE.test(t) || !access) return;
    try {
      // A failure here must never block the portal: the supplier can still register manually, which
      // is exactly what everyone has had to do until now.
      await call('supplier_api', { action: 'claim', t }, access);
    } catch (_e) { /* claim is an improvement on the flow, not a gate into it */ }
    try { sessionStorage.removeItem(CLAIM_KEY); } catch (_e) {}
  };
  // THE SUPPLIER'S REGISTERED LANGUAGE WINS ONCE SIGNED IN (founder, 14 Sep 2026). The portal took its
  // language from the URL alone, so a supplier registered in Arabic who opened an English link worked
  // in English while every notice reached them in Arabic. leads.locale decides; Settings changes it.
  useEffect(() => {
    if (phase !== 'app' || !token) return;
    call('supplier_api', { action: 'settings' }, token).then((j) => {
      const l = j && j.ok && j.settings ? j.settings.locale : null;
      if ((l === 'ar' || l === 'en') && l !== initLang()) switchLang(l);
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
    try { const tk = localStorage.getItem('qd-sup-token'); if (tk) { setToken(tk); setPhase('app'); claimIfInvited(tk); } } catch (_e) {}
    SB.auth.getSession().then(({ data }) => { const ss = data.session; if (ss && ss.access_token) { setToken(ss.access_token); try { localStorage.setItem('qd-sup-token', ss.access_token); if (ss.refresh_token) localStorage.setItem('qd-sup-refresh', ss.refresh_token); } catch (_e) {} setPhase('app'); claimIfInvited(ss.access_token); } }).catch(() => {});
    // THE HOUR MARK (14 Sep 2026). supabase-js refreshes the access token on schedule, and nothing here
    // listened — the customer portal learned this on 13 Aug; the supplier portal still sent the token
    // captured at mount, so after 60 minutes every tab answered "Something went wrong". One listener,
    // moving forward only: SIGNED_OUT carries no token and is not a refresh failure.
    let sub;
    try { sub = SB.auth.onAuthStateChange((_evt, ss) => { const at = ss && ss.access_token; if (!at) return; setToken(at); try { localStorage.setItem('qd-sup-token', at); if (ss.refresh_token) localStorage.setItem('qd-sup-refresh', ss.refresh_token); } catch (_e) {} }); } catch (_e) {}
    return () => { try { sub && sub.data && sub.data.subscription && sub.data.subscription.unsubscribe(); } catch (_e) {} };
  }, []);
  // The root element, not only this div, carries the language: it is what a screen reader reads.
  useEffect(() => { try { document.documentElement.lang = lang; document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr'; } catch (_e) {} }, [lang]);
  // Light/dark is a per-device choice, the same key and the same .osx[data-theme] palette as the
  // customer portal (globals.css). The supplier portal had no control for it at all.
  const [theme, setTheme] = useState('dark');
  const swapTheme = () => { const next = theme === 'dark' ? 'light' : 'dark'; try { localStorage.setItem('qd-theme', next); } catch (_e) {} setTheme(next); };
  const onAuth = (access, refresh) => { try { localStorage.setItem('qd-sup-token', access || ''); if (refresh) localStorage.setItem('qd-sup-refresh', refresh); } catch (_e) {} setToken(access || ''); setPhase('app'); if (access) { try { SB.auth.setSession({ access_token: access, refresh_token: refresh || '' }).catch(() => {}); } catch (_e) {} claimIfInvited(access); } };
  const doSignOut = () => { try { localStorage.removeItem('qd-sup-token'); localStorage.removeItem('qd-sup-refresh'); } catch (_e) {} setToken(''); setPhase('login'); try { SB.auth.signOut().catch(() => {}); } catch (_e) {} };
  // A 401 from the dashboard: try the stored refresh token once, and only if that fails send the
  // supplier back to sign-in — never leave them on a retry button that cannot succeed.
  const onExpired = async () => {
    try { const { data } = await SB.auth.refreshSession(); const ss = data && data.session; if (ss && ss.access_token) { onAuth(ss.access_token, ss.refresh_token); return; } } catch (_e) {}
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
          <Button variant="outline" size="sm" lang={lang === 'ar' ? 'en' : 'ar'} onClick={() => switchLang(lang === 'ar' ? 'en' : 'ar')}>{lang === 'ar' ? 'EN' : 'عربي'}</Button>
          <Button variant="outline" size="sm" onClick={swapTheme} aria-pressed={theme === 'light'} aria-label={theme === 'dark' ? (rtl ? 'الوضع الفاتح' : 'Light mode') : (rtl ? 'الوضع الداكن' : 'Dark mode')} title={theme === 'dark' ? (rtl ? 'الوضع الفاتح' : 'Light mode') : (rtl ? 'الوضع الداكن' : 'Dark mode')}><span aria-hidden>{theme === 'dark' ? '☀' : '☾'}</span></Button>
          <Button asChild variant="outline" size="sm" className="hidden sm:inline-flex"><a href={rtl ? '/ar' : '/'}>{t(lang, 'home')}</a></Button>
          {phase === 'app' && <Button variant="outline" size="sm" onClick={doSignOut}>{t(lang, 'signout')}</Button>}
        </div>
      </header>
      <main id="qd-portal-main">
      {!mounted ? <div className={S.center}>{t(lang, 'loading')}</div> : (<>
        {/* An invited supplier is told whose listing this is, before anything else on the page. */}
        {phase === 'login' && invite && <InviteBanner invite={invite} lang={lang} onStart={() => { try { document.getElementById('qd-supplier-signin')?.scrollIntoView({ behavior: 'smooth', block: 'center' }); } catch (_e) {} }} />}
        {/* §1 — the supplier meets the product before the sign-in box, not after it. */}
        {phase === 'login' && <SupplierEntryHero lang={lang} onStart={() => { try { document.getElementById('qd-supplier-signin')?.scrollIntoView({ behavior: 'smooth', block: 'center' }); } catch (_e) {} }} />}
        {phase === 'login' && <div id="qd-supplier-signin"><Login onAuth={onAuth} lang={lang} startMode={invite && invite.claimable ? 'signup' : 'signin'} /></div>}
        {phase === 'app' && <Dashboard token={token} lang={lang} onExpired={onExpired} />}
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
  const name = invite.company_name || (ar ? 'شركتك' : 'your company');
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
            ? (ar ? 'هذه الشركة مسجّلة بالفعل على QuotesDone. إن كان زميل لك قد سجّلها، اطلب منه إضافتك — أو سجّل الدخول بالبريد الذي استُخدم.'
                  : 'This company is already registered on QuotesDone. If a colleague claimed it, ask them to add you — or sign in with the email they used.')
            : (ar ? 'هذه القائمة محجوزة لشركتك. بياناتك موجودة لدينا بالفعل من السجل التجاري العام — لا تملأ نموذجًا فارغًا، بل تصحّح ما نعرفه وتؤكّده. أنشئ حسابك للمطالبة بها.'
                  : 'This listing is reserved for your company. We already hold your details from the public trade directory — you are not filling in a blank form, you are correcting what we have and confirming it. Create your account to claim it.')}
        </div>
        {!taken && <Button className="mt-4" onClick={onStart}>{ar ? 'المطالبة بقائمة شركتي' : 'Claim my listing'}</Button>}
      </Card>
    </section>
  );
}
function Login({ onAuth, lang, startMode }) {
  const [mode, setMode] = useState(startMode === 'signup' ? 'signup' : 'signin'); const [step, setStep] = useState('id'); const [id, setId] = useState(''); const [code, setCode] = useState(''); const [ident, setIdent] = useState(''); const [msg, setMsg] = useState(''); const [busy, setBusy] = useState(false);
  const isSignup = mode === 'signup';
  // claim_lookup resolves after mount, so startMode arrives late and cannot be a useState initial
  // value. Flip to sign-up when the invitation lands, unless the supplier has already chosen a tab
  // themselves — a link that only ever reaches someone without an account should not open on
  // "Welcome back", but it must not override a deliberate choice either.
  const swapped = useRef(false);
  useEffect(() => { if (startMode === 'signup' && !swapped.current) setMode('signup'); }, [startMode]);
  const looksEmail = (v) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(v || '').trim());
  const send = async () => { const v = id.trim(); if (!v) return; if (isSignup && !looksEmail(v)) { setMsg(t(lang, 'signup_email_only')); return; } setBusy(true); setMsg('');
    try { const g = await call('role_guard', { user_kind: 'supplier', identifier: v }); if (g && g.conflict === 'customer') { setBusy(false); setMsg(t(lang, 'conflict_customer')); return; } } catch (_e) {}
    let j; try { j = await call('login_otp', { action: 'send', user_kind: 'supplier', identifier: v, allow_signup: isSignup, lang }); } catch (_e) { setBusy(false); setMsg(t(lang, 'err_code_send')); return; } setBusy(false); if (j && j.ok) { setIdent(j.identifier || v); setStep('code'); } else setMsg((j && j.error) || t(lang, 'err_code_send')); };
  const verify = async () => { if (!code.trim()) return; setBusy(true); setMsg(''); let j; try { j = await call('login_otp', { action: 'verify', user_kind: 'supplier', identifier: ident, code: code.trim() }); } catch (_e) { setBusy(false); setMsg(t(lang, 'err_incorrect')); return; } if (!j || !j.ok || !j.access_token) { setBusy(false); setMsg((j && j.error) || t(lang, 'err_incorrect')); return; } setBusy(false); onAuth(j.access_token, j.refresh_token); };
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
const MAIN_TABS = ['overview', 'rfqs', 'quotes', 'projects', 'messages', 'documents', 'billing', 'insights'];
const ACCOUNT_TABS = ['profile', 'scope', 'settings'];
function Dashboard({ token, lang, onExpired }) {
  const ar = lang === 'ar';
  const [ov, setOv] = useState(null); const [tab, setTab] = useState('overview'); const [err, setErr] = useState('');
  const [panel, setPanel] = useState(null); const [receipt, setReceipt] = useState(null);
  // Which record a card opened: an RFQ by inquiry id (from Quotes), a chat by inquiry id (from Projects).
  const [focusRfq, setFocusRfq] = useState(null); const [openChat, setOpenChat] = useState(null);
  const load = async () => { const j = await call('supplier_portal', { action: 'overview' }, token); if (j && j.ok) setOv(j); else if (j && j._http === 401 && onExpired) onExpired(); else setErr((j && (j.code || j.error)) || 'load_err'); };
  useEffect(() => { load(); }, [token]);
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
  // Every panel's goTo(...) lands here. Old tab keys still resolve: 'inbox' is the RFQs list, and the
  // intelligence keys open their panel inside Insights.
  const go = (k) => {
    if (MAIN_TABS.includes(k) || ACCOUNT_TABS.includes(k)) { setTab(k); return; }
    if (k === 'inbox') { setTab('rfqs'); return; }
    if (INSIGHT_PANELS.includes(k)) { setPanel(k); setTab('insights'); return; }
    setTab('overview');
  };
  if (err === 'no_company') return <Onboarding token={token} lang={lang} onDone={() => { setErr(''); load(); }} />;
  if (err) return <div className={S.center}><Card className="qd-panel max-w-[460px] p-5"><div className={S.h2}>{t(lang, 'something_wrong')}</div><div className={S.sub}>{t(lang, 'err_generic')}</div><Button className="mt-3" onClick={() => { setErr(''); load(); }}>{t(lang, 'bill_retry')}</Button></Card></div>;
  if (!ov) return <div className={S.center} aria-busy="true">{t(lang, 'loading_dash')}</div>;
  const s = ov.stats || {}; const pp = s.price_positioning || {};
  const TAB = { overview: ar ? 'احصل على المطابقة' : 'Get matched', rfqs: t(lang, 't_rfqs'), quotes: t(lang, 't_quotes'), projects: t(lang, 't_projects'), messages: t(lang, 't_messages'), documents: t(lang, 't_documents'), billing: t(lang, 't_billing'), insights: t(lang, 't_insights'), profile: t(lang, 't_profile'), scope: t(lang, 't_scope'), settings: t(lang, 't_settings') };
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
      <div className="mb-5 flex flex-col gap-3">
        <div>
          <Kicker>{t(lang, 'brand_sub')}</Kicker>
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
            {MAIN_TABS.map((k) => <button key={k} type="button" aria-current={tab === k ? 'page' : undefined} className={cn(S.tab, 'min-h-11 whitespace-nowrap focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring', tab === k && S.tabOn)} onClick={() => setTab(k)}>{k === 'rfqs' ? TAB.rfqs + (ov.active_matches ? ' (' + ov.active_matches + ')' : '') : TAB[k]}</button>)}
          </div>
        </nav>
        <nav aria-label={t(lang, 'account')} className="flex flex-wrap items-center gap-x-4 text-[13px]">
          <span className="text-muted-foreground">{t(lang, 'account')}:</span>
          {ACCOUNT_TABS.map((k) => <button key={k} type="button" aria-current={tab === k ? 'page' : undefined} className={cn('inline-flex min-h-11 items-center rounded-md px-1 font-semibold underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring', tab === k ? 'text-primary' : 'text-muted-foreground')} onClick={() => setTab(k)}>{TAB[k]}</button>)}
        </nav>
      </div>
      <SupplierCommandPalette tabs={[...MAIN_TABS, ...ACCOUNT_TABS]} labels={TAB} onGo={go} lang={lang} />
      {tab === 'overview' && <>
        {!!(ov.alerts || []).length && <div className="flex flex-col gap-2 mb-4">{ov.alerts.map((a, i) => { const c = itemCopy(lang, a); return <button key={i} type="button" className="qd-panel qd-panel-hover w-full text-start px-4 py-3.5 cursor-pointer flex items-start gap-3" onClick={() => setTab(a.action === 'documents' ? 'documents' : a.kind === 'draft_quote' ? 'quotes' : 'rfqs')}><span aria-hidden className={cn('mt-[7px] h-2 w-2 rounded-full shrink-0', a.severity === 'high' ? 'bg-danger' : a.severity === 'medium' ? 'bg-warn' : 'bg-primary')} /><span className="flex flex-col gap-0.5 min-w-0"><b className="text-[13.5px] text-foreground">{c.title}</b><span className="text-muted-foreground text-xs leading-[1.6]">{c.detail}</span></span></button>; })}</div>}
        <GetMatched token={token} lang={lang} go={go} />
        {/* Counts come from fn_supplier_document_impact: open enquiries in this trade, not an estimate. */}
        <div className="mb-4"><SupplierDocumentImpact token={token} lang={lang} goTo={go} /></div>
        <div className="grid grid-cols-2 md:grid-cols-6 gap-2.5 mb-4">
          <Kpi label={t(lang, 'k_quotes_sent')} v={s.quotes_total ?? 0} />
          <Kpi label={t(lang, 'k_reveals')} v={s.reveals ?? 0} />
          <Kpi label={t(lang, 'k_hired')} v={s.hired ?? 0} />
          <Kpi label={t(lang, 'k_win')} v={s.win_ratio != null ? s.win_ratio + '%' : '—'} />
          <Kpi label={t(lang, 'k_rating')} v={s.rating != null ? s.rating : '—'} sub={s.rating_percentile != null ? (ar ? ('ضمن أفضل ' + Math.max(1, 100 - s.rating_percentile) + '% بالقطاع') : ('Top ' + Math.max(1, 100 - s.rating_percentile) + '% in sector')) : ''} />
          <Kpi label={t(lang, 'k_deal_value')} v={aed(s.deal_value_awarded)} />
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3.5 mb-3.5">
          <Funnel s={s} matched={ov.active_matches} lang={lang} />
          <Earnings s={s} lang={lang} />
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3.5">
          <Card className="qd-panel p-5">
            <div className={S.h2}>{t(lang, 'price_pos')} <span className={S.anon}>{t(lang, 'anon_note')}</span></div>
            <div className="mt-2.5"><Badge variant={/below/.test(pp.band || '') ? 'ok' : /above/.test(pp.band || '') ? 'warn' : 'secondary'} className="capitalize text-sm px-3.5 py-1.5">{pp.band || t(lang, 'not_enough')}</Badge></div>
            {/* The redaction bar makes "we never show competitor prices" visible: they exist, we hold them. */}
            {pp.competitive_rfqs ? (
              <div className="mt-3.5 flex items-center gap-2 flex-wrap">
                <span className="text-[11px] font-semibold text-muted-foreground/80">{ar ? 'أسعار المنافسين' : 'Competitor quotes'}</span>
                <span aria-hidden className="redact redact-bar" style={{ width: 52 }} />
                <span aria-hidden className="redact redact-bar" style={{ width: 36 }} />
                <span aria-hidden className="redact redact-bar" style={{ width: 44 }} />
                <span className="sr-only">{ar ? 'أسعار المنافسين محجوبة دائمًا' : 'Competitor prices are always withheld'}</span>
              </div>
            ) : null}
            <div className={cn(S.sub, 'mt-2.5')}>{pp.competitive_rfqs ? ((ar ? ('كنت الأقل سعرًا في ' + (pp.times_lowest || 0) + ' من ' + pp.competitive_rfqs + ' طلب تنافسي (' + (pp.lowest_rate || 0) + '%). في المتوسط عرضك ' + (pp.avg_pct_vs_average >= 0 ? '+' : '') + (pp.avg_pct_vs_average ?? 0) + '% مقابل متوسط السوق و' + (pp.avg_pct_above_lowest ?? 0) + '% فوق أدنى عرض.') : ('You were the lowest bid on ' + (pp.times_lowest || 0) + ' of ' + pp.competitive_rfqs + ' competitive RFQs (' + (pp.lowest_rate || 0) + '%). On average your quote is ' + (pp.avg_pct_vs_average >= 0 ? '+' : '') + (pp.avg_pct_vs_average ?? 0) + '% vs the market average and ' + (pp.avg_pct_above_lowest ?? 0) + '% above the lowest quote.'))) : t(lang, 'pp_fallback')}</div>
          </Card>
          <Card className="qd-panel p-5">
            <div className={S.h2}>{t(lang, 'last12')} <span className={S.anon}>{t(lang, 'quotes_reveals')}</span></div>
            <Spark hist={s.history_12m} lang={lang} />
          </Card>
        </div>
      </>}
      {tab === 'rfqs' && <Rfqs token={token} lang={lang} focus={focusRfq} onFocused={() => setFocusRfq(null)} />}
      {tab === 'quotes' && <MyQuotes token={token} lang={lang} goRfqs={() => setTab('rfqs')} openRfq={(id) => { setFocusRfq(id); setTab('rfqs'); }} />}
      {tab === 'projects' && <Projects token={token} lang={lang} openChat={(id) => { setOpenChat(id); setTab('messages'); }} />}
      {tab === 'messages' && <Messages token={token} lang={lang} openInquiry={openChat} onOpened={() => setOpenChat(null)} />}
      {tab === 'documents' && <Documents token={token} lang={lang} />}
      {tab === 'billing' && <BillingPanel token={token} lang={lang} receipt={receipt} />}
      {tab === 'insights' && <Insights token={token} lang={lang} goTo={go} initial={panel} />}
      {tab === 'profile' && <ProfilePanel token={token} lang={lang} onSaved={load} />}
      {tab === 'scope' && <CapabilityConfirmPanel token={token} lang={lang} />}
      {tab === 'settings' && <SupplierSettings token={token} lang={lang} onLang={switchLang} />}
    </div>
  );
}
// Quotes: what this supplier has sent, and which are still drafts that no customer can see. The inbox
// already carries each RFQ's quote; this is that list read the other way round.
// A quote's state in words. draft = held by the accept rule (the customer cannot see it); anything the
// quotes table may hold that is not listed here still gets an Arabic word rather than a raw code.
const QUOTE_ST = {
  draft: { v: 'warn', en: 'Held — not sent yet', ar: 'محجوز — لم يُرسل بعد' },
  submitted: { v: 'ok', en: 'Sent to the customer', ar: 'أُرسل إلى العميل' },
  accepted: { v: 'ok', en: 'Customer revealed you', ar: 'كشف العميل عن عرضك' },
  withdrawn: { v: 'secondary', en: 'Withdrawn', ar: 'مسحوب' },
  expired: { v: 'secondary', en: 'Expired', ar: 'منتهي الصلاحية' },
};
const quoteSt = (q) => QUOTE_ST[q && q.status] || { v: 'secondary', en: String((q && q.status) || '').replace(/_/g, ' '), ar: 'حالة أخرى' };
// The notes a held quote carries: what fn_quote_structured_score says is missing, in words, and the
// one button that reopens the form to fix it.
// 14 Sep 2026: a quote the sales engineer holds for exact details carries `spec_hold`; its notes are the
// per-line list and the two ways out (./supplier/SpecHold). Otherwise the commercial draft notes below.
const optLabel = (lang, n) => (lang === 'ar' ? `الخيار ${n}` : `Option ${n}`);
function HeldNotes({ q, lang, onFix, token = null, onChanged = null, title = null }) {
  if (q.spec_hold && token) return <SpecHoldPanel quoteId={q.id} lang={lang} token={token} onChanged={onChanged || undefined} onResubmit={onFix || undefined} title={title} />;
  const ar = lang === 'ar';
  const miss = Array.isArray(q.missing) ? q.missing : [];
  return (
    <div role="note" className="mt-3 rounded-md border border-warn/40 bg-warn/10 px-3.5 py-3">
      <div className="text-[13px] font-semibold text-foreground">{ar ? 'لم يُرسل هذا العرض إلى العميل بعد — أكمل ما يلي ثم أعد الإرسال:' : 'This quote has not reached the customer yet — add the following, then send it again:'}</div>
      {miss.length
        ? <ul className="mt-1.5 flex flex-col gap-1">{miss.map((m) => <li key={m} className="flex items-start gap-2 text-[13px] text-foreground"><span aria-hidden className="mt-[7px] h-1.5 w-1.5 shrink-0 rounded-full bg-warn" />{missingLabel(lang, m)}</li>)}</ul>
        : <div className={cn(S.sub, 'mt-1')}>{ar ? 'أضف بندًا مسعّرًا واحدًا على الأقل، ومدة التنفيذ، وصلاحية العرض، والضمان.' : 'Add at least one priced line, the lead time, the quote validity and the warranty.'}</div>}
      {onFix && <Button size="sm" className="mt-2.5" onClick={onFix}>{ar ? 'أصلح العرض وأعد إرساله' : 'Fix and resend'}</Button>}
    </div>
  );
}
function MyQuotes({ token, lang, goRfqs, openRfq }) {
  const ar = lang === 'ar';
  const [data, setData] = useState(null);
  const load = () => call('supplier_api', { action: 'inbox' }, token).then(setData);
  useEffect(() => { load(); }, [token]);
  if (!data) return <Card className="qd-panel p-5" aria-busy="true">{t(lang, 'loading')}</Card>;
  if (data.error) return <Card className="qd-panel p-5">{srvMsg(lang, data, t(lang, 'err_generic'))}</Card>;
  // Every option is its own quotation (founder, 14 Sep 2026), so each gets its own card.
  const list = (data.inquiries || []).flatMap((i) => { const qs = i.quotes && i.quotes.length ? i.quotes : (i.quote ? [i.quote] : []); return qs.map((q) => ({ ...i, quote: q, multi: qs.length > 1 })); });
  if (!list.length) return <Card className="qd-panel p-5"><div className={S.h2}>{ar ? 'لم تقدّم أي عرض بعد' : 'No quotes yet'}</div><div className={S.sub}>{ar ? 'تظهر هنا عروضك بعد أن تسعّر طلبًا من تبويب طلبات التسعير.' : 'Your quotes appear here once you price a request from the RFQs tab.'}</div><Button className="mt-3" variant="outline" onClick={goRfqs}>{t(lang, 't_rfqs')}</Button></Card>;
  return <ul className={S.list}>{list.map((i) => { const q = i.quote; const st = quoteSt(q); const editable = !i.concluded && !i.revealed; return (
    <li key={i.id + ':' + (q.option_no || 1)}><Card className="qd-panel qd-panel-hover p-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <button type="button" className="min-w-0 text-start" onClick={() => openRfq(i.id)} aria-label={(ar ? 'افتح الطلب ' : 'Open request ') + String(i.id).slice(0, 8).toUpperCase()}>
          <div className="font-semibold text-foreground underline-offset-2 hover:underline">{categoryLabel(i.category || '', lang) || t(lang, 'request_w')} · {emirateLabel(lang, i.emirate || '')}{i.multi ? ' · ' + optLabel(lang, q.option_no || 1) : ''}</div>
          <div className="mt-1 flex flex-wrap gap-2 items-center"><Badge variant={st.v}>{ar ? st.ar : st.en}</Badge>{i.you_won ? <Badge variant="ok">{t(lang, 'you_won').replace(' · ', '')}</Badge> : i.concluded ? <Badge variant="secondary">{t(lang, 'concluded').replace(' · ', '')}</Badge> : null}{q.lead_time ? <span className={S.sub}>{(ar ? 'مدة التنفيذ: ' : 'Lead time: ') + q.lead_time}</span> : null}</div>
        </button>
        <div className="text-end"><div className="font-[family-name:var(--font-head)] text-[18px] font-extrabold tabular-nums text-foreground"><Ltr>{aed(q.quote_amount)}</Ltr></div>
          {editable && q.status !== 'draft' ? <Button size="sm" variant="outline" className="mt-1" onClick={() => openRfq(i.id)}>{ar ? 'عدّل العرض' : 'Edit quote'}</Button> : null}</div>
      </div>
      {q.status === 'draft' && editable ? <HeldNotes q={q} lang={lang} token={token} onChanged={load} onFix={() => openRfq(i.id)} /> : null}
    </Card></li>); })}</ul>;
}
// Label above figure, not below: the eye lands on the number, and the label is
// already read by then. Figures are tabular so a row of KPIs aligns on the digit.
function Kpi({ label, v, sub }) { return <Card className="qd-panel qd-panel-hover qd-ticks p-3.5 pt-5"><div className="font-mono text-[10.5px] uppercase tracking-caps text-muted-foreground">{label}</div><div className={cn(S.figure, 'font-head text-[26px] font-semibold mt-2')}>{v}</div>{sub ? <div className="text-[10.5px] text-primary mt-1.5 font-semibold">{sub}</div> : null}</Card>; }
// Conversion funnel: matched -> quoted -> revealed -> won.
//
// fn_supplier_stats has always returned every number here — quotes_total, reveals, hired,
// lost_to_others, reveal_ratio, win_ratio, response_rate, avg_lead_time_days, active_rfqs — and
// the portal rendered none of them beyond four flat counters. Counters tell a supplier what
// happened; the funnel tells them WHERE they lose, which is the only version they can act on.
// Bars are drawn relative to the widest stage so a low-volume account still reads clearly.
function Funnel({ s, matched, lang }) {
  const ar = lang === 'ar';
  const stages = [
    { k: 'matched',  label: ar ? 'طلبات وصلتك'  : 'Requests matched', v: matched || 0 },
    { k: 'quoted',   label: ar ? 'قدّمت عرضًا'   : 'You quoted',       v: s.quotes_total || 0 },
    { k: 'revealed', label: ar ? 'كشف العميل'    : 'Customer revealed', v: s.reveals || 0 },
    { k: 'won',      label: ar ? 'فزت بالمشروع'  : 'You won',          v: s.hired || 0 },
  ];
  const max = Math.max(1, ...stages.map((x) => x.v));
  // Step conversion, so a supplier can see which single transition is costing them.
  const conv = (i) => { if (i === 0) return null; const prev = stages[i - 1].v; if (!prev) return null; return Math.round(100 * stages[i].v / prev); };
  const anyData = stages.some((x) => x.v > 0);
  return (
    <Card className="qd-panel p-5">
      <div className={S.h2}>{ar ? 'مسار التحويل' : 'Your funnel'}</div>
      {!anyData
        ? <div className={cn(S.sub, 'mt-2.5')}>{ar
            ? 'لا توجد بيانات بعد. سيظهر هذا المسار بمجرد وصول أول طلب مطابق إليك.'
            : 'Nothing to show yet. This fills in as soon as the first matching request reaches you.'}</div>
        : <div className="mt-3 flex flex-col gap-2.5">
            {stages.map((st, i) => { const c = conv(i); return (
              <div key={st.k}>
                <div className="flex justify-between items-baseline gap-2">
                  <span className="text-[13px] text-foreground">{st.label}</span>
                  <span className="text-[13px] font-bold text-foreground tabular-nums">{st.v}{c != null && <span className="text-muted-foreground font-semibold ms-1.5 text-[11.5px]">{c}%</span>}</span>
                </div>
                <div className="qd-meter mt-1.5">
                  <span className="transition-[width] duration-700 motion-reduce:transition-none"
                       style={{ width: Math.max(2, Math.round(100 * st.v / max)) + '%', opacity: 1 - i * 0.18 }} />
                </div>
              </div>
            ); })}
          </div>}
      {/* Numbers the platform already had and never showed. Only rendered when real. */}
      <div className="grid grid-cols-2 gap-x-4 gap-y-2 mt-4 pt-3.5 border-t border-border">
        {s.response_rate != null && <Stat label={ar ? 'معدل الاستجابة' : 'Response rate'} v={s.response_rate + '%'} />}
        {s.reveal_ratio != null && <Stat label={ar ? 'نسبة الكشف' : 'Reveal rate'} v={s.reveal_ratio + '%'} />}
        {s.avg_lead_time_days != null && <Stat label={ar ? 'متوسط مدة التنفيذ' : 'Avg lead time'} v={s.avg_lead_time_days + (ar ? ' يوم' : ' days')} />}
        {!!s.lost_to_others && <Stat label={ar ? 'خسرتها لمنافس' : 'Lost to others'} v={s.lost_to_others} />}
        {!!s.active_rfqs && <Stat label={ar ? 'طلبات مفتوحة' : 'Still open'} v={s.active_rfqs} />}
        {!!s.pending_reviews && <Stat label={ar ? 'تقييمات معلّقة' : 'Reviews pending'} v={s.pending_reviews} />}
      </div>
    </Card>
  );
}
function Stat({ label, v }) { return <div className="flex justify-between items-baseline gap-2"><span className={S.sub}>{label}</span><span className="text-[13px] font-bold text-foreground tabular-nums">{v}</span></div>; }
// Value won over time. deal_value_awarded and history_12m were both already computed.
function Earnings({ s, lang }) {
  const ar = lang === 'ar';
  const hist = Array.isArray(s.history_12m) ? s.history_12m : [];
  const active = hist.filter((h) => (h.quotes || 0) + (h.reveals || 0) > 0).length;
  return (
    <Card className="qd-panel p-5">
      <div className={S.h2}>{ar ? 'قيمة الأعمال' : 'Business value'}</div>
      <div className="flex gap-6 mt-3 flex-wrap">
        <div>
          <div className="text-[22px] font-extrabold text-foreground leading-none">{aed(s.deal_value_awarded)}</div>
          <div className={S.sub}>{ar ? 'إجمالي قيمة ما فزت به' : 'total value awarded to you'}</div>
        </div>
        <div>
          <div className="text-[22px] font-extrabold text-foreground leading-none">{active}<span className="text-muted-foreground text-[15px]">/12</span></div>
          <div className={S.sub}>{ar ? 'أشهر بها نشاط' : 'months with activity'}</div>
        </div>
      </div>
      <div className={cn(S.sub, 'mt-3')}>{ar
        ? 'تُحتسب هذه القيمة من العروض التي كشفها العملاء فعليًا، لا من العروض المُرسلة.'
        : 'Counted from quotes customers actually revealed, not from quotes sent.'}</div>
    </Card>
  );
}
function Spark({ hist, lang }) { if (!hist || !hist.length) return <div className={S.sub}>{t(lang, 'no_history')}</div>; const max = Math.max(1, ...hist.map((h) => Math.max(h.quotes || 0, h.reveals || 0))); return <div className="flex gap-1.5 items-end mt-3.5 h-[70px]">{hist.map((h, i) => <div key={i} className="flex-1 flex flex-col items-center" title={h.month + ': ' + h.quotes + (lang === 'ar' ? ' عروض / ' : ' quotes / ') + h.reveals + (lang === 'ar' ? ' كشوفات' : ' reveals')}><div className="flex gap-0.5 items-end h-[50px]"><div className="w-[7px] rounded-t-sm bg-primary" style={{ height: Math.max(2, Math.round((h.quotes / max) * 46)) }} /><div className="w-[7px] rounded-t-sm bg-primary/40" style={{ height: Math.max(2, Math.round((h.reveals / max) * 46)) }} /></div><div className="text-[9px] text-muted-foreground mt-1">{String(h.month).split(' ')[0]}</div></div>)}</div>; }
// An RFQ card shows what is actually being priced: the redacted drawing pages, the BOQ as a table
// (with "quote against this BOQ" pre-filling the quote's line items), the customer's identity as a
// redaction bar, and the anonymous pre-reveal Q&A. See ./supplier/RfqParts.tsx for why.
function Rfqs({ token, lang, focus = null, onFocused = null }) {
  const ar = lang === 'ar';
  const [data, setData] = useState(null); const [open, setOpen] = useState(null); const [prefill, setPrefill] = useState({});
  // A second form on a card: "<inquiry>#<option_no>" edits that option, "<inquiry>#new" adds another option.
  const [extra, setExtra] = useState(null);
  const reload = () => call('supplier_api', { action: 'inbox' }, token).then((j) => setData(j));
  useEffect(() => { reload(); }, [token]);
  // Opened from a Quotes card: open THAT request's form (if it can still be edited) and scroll to it.
  useEffect(() => {
    if (!focus || !data || !data.inquiries) return;
    const it = data.inquiries.find((x) => x.id === focus);
    if (it && !it.concluded && !it.revealed) setOpen(focus);
    requestAnimationFrame(() => { try { document.getElementById('qd-rfq-' + focus)?.scrollIntoView({ behavior: 'smooth', block: 'start' }); } catch (_e) {} });
    if (onFocused) onFocused();
  }, [focus, data]);
  if (!data) return <Card className="qd-panel p-5" aria-busy="true">{t(lang, 'loading_rfqs')}</Card>;
  if (data.error) return <Card className="qd-panel p-5">{srvMsg(lang, data, t(lang, 'err_generic'))}</Card>;
  const list = data.inquiries || [];
  if (!list.length) return <Card className="qd-panel p-5"><div className={S.h2}>{t(lang, 'no_rfqs_h')}</div><div className={S.sub}>{t(lang, 'no_rfqs_sub')}</div></Card>;
  const quoteBoq = (id, rows) => {
    setPrefill((p) => ({ ...p, [id]: rows.slice(0, 80).map((r) => ({ description: String(r.description || '').slice(0, 300), qty: r.qty == null ? '' : String(r.qty), unit: r.unit || '', unit_price: '' })) }));
    setOpen(id);
    requestAnimationFrame(() => { try { document.getElementById('qd-qf-' + id)?.scrollIntoView({ behavior: 'smooth', block: 'start' }); } catch (_e) {} });
  };
  const date = (d) => (d ? new Date(d).toLocaleDateString(ar ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short' }) : '');
  return <ul className={S.list}>{list.map((i) => {
    // A quote can be edited and re-sent until the request concludes or the customer reveals it:
    // submit_quote upserts on (inquiry, supplier). A held draft must be editable — that is the fix.
    const canQuote = !i.concluded && !i.revealed;
    const q = i.quote;
    return <li key={i.id} id={'qd-rfq-' + i.id}><Card className="qd-panel qd-panel-hover p-5 sm:p-6">
      <div className="flex justify-between items-start gap-3 flex-wrap">
        <div className="min-w-0">
          <div className="mb-2 flex flex-wrap items-center gap-1.5">
            <span className="me-1 font-mono text-label uppercase tracking-caps text-muted-foreground tabular-nums">{ar ? 'طلب ' : 'RFQ '}<Ltr>{String(i.id || '').slice(0, 8).toUpperCase()}</Ltr></span>
            {i.category ? <Badge variant="outline">{categoryLabel(i.category, lang)}</Badge> : null}
            {i.emirate ? <Badge variant="secondary">{emirateLabel(lang, i.emirate)}</Badge> : null}
          </div>
          <h2 className="font-head text-[17px] font-semibold tracking-snug text-foreground">{categoryLabel(i.category || '', lang) || t(lang, 'request_w')} <span className="font-medium text-muted-foreground">· {emirateLabel(lang, i.emirate || '')}</span>
            {i.you_won ? <span className="text-primary font-bold">{t(lang, 'you_won')}</span> : i.concluded ? <span className="text-muted-foreground">{t(lang, 'concluded')}</span> : ''}</h2>
          <div className="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1">{!i.you_won && !i.revealed && <WithheldCustomer lang={lang} />}<span className="font-mono text-[11.5px] text-muted-foreground tabular-nums">{date(i.created_at)}</span>{i.budget ? <span className="text-[11.5px] text-muted-foreground">{(ar ? 'الميزانية: ' : 'Budget: ') + i.budget}</span> : null}</div>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {q ? <span className="rounded-chip border border-primary/30 bg-primary/10 px-2.5 py-1 font-mono text-primary text-[13px] tabular-nums">{t(lang, 'quoted')}<Ltr>{aed(q.quote_amount)}</Ltr></span> : null}
          {q ? <Badge variant={quoteSt(q).v}>{ar ? quoteSt(q).ar : quoteSt(q).en}</Badge> : null}
          {canQuote ? <Button size="sm" variant={q ? 'outline' : 'default'} aria-expanded={open === i.id} aria-controls={'qd-qf-' + i.id} onClick={() => setOpen(open === i.id ? null : i.id)}>{open === i.id ? t(lang, 'close') : q ? (q.status === 'draft' ? (ar ? 'أصلح العرض' : 'Fix quote') : (ar ? 'عدّل العرض' : 'Edit quote')) : t(lang, 'quote')}</Button> : null}
        </div>
      </div>
      {q && q.status === 'draft' && canQuote && open !== i.id && !(i.quotes && i.quotes.length > 1) ? <HeldNotes q={q} lang={lang} token={token} onChanged={reload} onFix={() => setOpen(i.id)} /> : null}
      {i.quotes && i.quotes.length > 1 ? <ul className="mt-3 flex flex-col gap-2" aria-label={ar ? 'خياراتك لهذا الطلب' : 'Your options on this request'}>{i.quotes.map((o) => (
        <li key={o.id} className="rounded-md border border-border px-3 py-2.5">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <span className="text-[13.5px] font-semibold text-foreground">{optLabel(lang, o.option_no || 1)} · <Ltr>{aed(o.quote_amount)}</Ltr></span>
            <span className="flex items-center gap-2"><Badge variant={quoteSt(o).v}>{ar ? quoteSt(o).ar : quoteSt(o).en}</Badge>
              {canQuote ? <Button size="sm" variant="outline" onClick={() => setExtra(extra === i.id + '#' + (o.option_no || 1) ? null : i.id + '#' + (o.option_no || 1))}>{ar ? 'عدّل هذا الخيار' : 'Edit this option'}</Button> : null}</span>
          </div>
          {o.status === 'draft' && canQuote && extra !== i.id + '#' + (o.option_no || 1) ? <HeldNotes q={o} lang={lang} token={token} onChanged={reload} onFix={() => setExtra(i.id + '#' + (o.option_no || 1))} /> : null}
        </li>))}</ul> : null}
      {canQuote && q ? <div className="mt-2.5"><Button size="sm" variant="ghost" onClick={() => setExtra(extra === i.id + '#new' ? null : i.id + '#new')}>{ar ? '+ أضف خيارًا آخر (عرض مستقل)' : '+ Add another option (its own quotation)'}</Button></div> : null}
      {canQuote && extra && extra.startsWith(i.id + '#') ? <div id={'qd-qf-' + extra}><QuoteForm key={extra} inquiry={i} token={token} lang={lang} newOption={extra.endsWith('#new')} quote={extra.endsWith('#new') ? null : (i.quotes || []).find((o) => i.id + '#' + (o.option_no || 1) === extra) || null} onDone={() => { setExtra(null); reload(); }} /></div> : null}
      {i.summary && <p className={cn(S.sub, 'mt-2')}>{i.summary}</p>}
      <RequestedTerms spec={i.spec} lang={lang} />
      <DrawingGallery pages={i.drawing_pages || []} lang={lang} />
      <BoqTable boq={i.boq} confidence={i.boq_confidence} lang={lang} onQuote={canQuote && !q ? (rows) => quoteBoq(i.id, rows) : undefined} />
      {i.boq_withheld ? <div className={cn(S.sub, 'mt-3')}>{ar ? 'حُجب جدول الكميات لأننا لم نتمكّن من إثبات خلوّه من بيانات العميل. سعّر من المخططات والوصف.' : 'The bill of quantities is held back because we could not prove it free of the customer’s details. Price from the drawings and the description.'}</div> : null}
      <ClarifyThread inquiryId={i.id} token={token} lang={lang} canAsk={canQuote && !q} />
      {open === i.id && canQuote && <div id={'qd-qf-' + i.id}><QuoteForm key={i.id + ':' + ((prefill[i.id] || []).length)} inquiry={i} token={token} lang={lang} initialItems={prefill[i.id]} onDone={() => { setOpen(null); reload(); }} /></div>}
    </Card></li>;
  })}</ul>;
}
function QuoteForm({ inquiry, token, onDone, lang, initialItems = null, quote = null, newOption = false }) {
  // An existing quote (a held draft, or one already sent) reopens with what was sent, lines included.
  // `quote` names one option to edit; `newOption` starts another option, which is its own quotation.
  const q0 = quote || (newOption ? {} : inquiry.quote || {});
  const optionArgs = newOption ? { new_option: true } : (q0.option_no ? { option_no: q0.option_no } : {});
  // VAT (founder, 14 Sep 2026): the customer compares and pays on the price EXCLUDING VAT, and never
  // sees the supplier's VAT details. The supplier says how the total is stated; if it includes VAT,
  // they give the ex-VAT figure.
  const VAT_BASIS = ['exclusive', 'inclusive', 'not_registered'];
  const [vat, setVat] = useState(VAT_BASIS.includes(q0.vat_treatment) ? q0.vat_treatment : '');
  const [exVat, setExVat] = useState(q0.vat_treatment === 'inclusive' && q0.price_ex_vat != null ? String(q0.price_ex_vat) : '');
  const lines0 = initialItems && initialItems.length ? initialItems
    : (Array.isArray(q0.items) && q0.items.length ? q0.items.map((r) => ({ description: r.description || '', qty: r.qty == null ? '' : String(r.qty), unit: r.unit || '', unit_price: r.unit_price == null ? '' : String(r.unit_price) })) : [{ description: '', qty: '', unit: '', unit_price: '' }]);
  const [amount, setAmount] = useState(q0.quote_amount != null ? String(q0.quote_amount) : ''); const [lead, setLead] = useState(q0.lead_time || ''); const [notes, setNotes] = useState(q0.notes || ''); const [scope, setScope] = useState(q0.scope || ''); const [validity, setValidity] = useState(q0.validity || ''); const [payment, setPayment] = useState(q0.payment_terms || ''); const [warranty, setWarranty] = useState(q0.warranty || ''); const [items, setItems] = useState(lines0); const [msg, setMsg] = useState(''); const [busy, setBusy] = useState(false);
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
    if (j && j.ok && (j.accepted || j.held || j.options)) onDone();
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
          <option value="">{ar ? 'اختر: هل يشمل ضريبة القيمة المضافة؟' : 'Choose: does it include VAT?'}</option>
          <option value="exclusive">{ar ? 'غير شامل ضريبة القيمة المضافة' : 'Excludes VAT'}</option>
          <option value="inclusive">{ar ? 'شامل ضريبة القيمة المضافة' : 'Includes VAT'}</option>
          <option value="not_registered">{ar ? 'لسنا مسجلين في ضريبة القيمة المضافة' : 'We are not VAT-registered'}</option>
        </select></Lbl>
      {vat === 'inclusive' ? <Lbl className="flex-1 min-w-[200px]" visible text={ar ? 'السعر غير شامل الضريبة (درهم)' : 'Price excluding VAT (AED)'}><Input className="tabular font-mono" inputMode="decimal" value={exVat} onChange={(e) => setExVat(e.target.value)} /></Lbl> : null}
    </div>
    <div className={S.sub}>{ar ? 'يقارن العميل ويدفع على السعر غير شامل الضريبة، ولا تُعرض عليه تفاصيل الضريبة ولا رقمك الضريبي.' : 'The customer compares and pays on the price excluding VAT; your VAT details and TRN are never shown to them.'}</div>
    <div className="flex gap-2.5 flex-wrap">{[[validity, setValidity, lang === 'ar' ? 'صلاحية العرض (مثلاً 30 يومًا)' : 'Quote validity (e.g. 30 days)'], [payment, setPayment, lang === 'ar' ? 'شروط الدفع (مثلاً 50% مقدمًا)' : 'Payment terms (e.g. 50% advance)'], [warranty, setWarranty, lang === 'ar' ? 'الضمان (مثلاً سنة واحدة)' : 'Warranty (e.g. 1 year)']].map(([v, sv, ph], k) => <Lbl key={k} className="flex-1 min-w-[160px]" text={ph}><Input placeholder={ph} value={v} onChange={(e) => sv(e.target.value)} /></Lbl>)}</div>
    <div className="border-t border-border pt-4">
      <div className={cn(grp, 'mb-1')}>{ar ? 'بنود العرض' : 'Line items'}</div>
      <div className={cn(S.sub, 'mb-2')}>{lang === 'ar' ? 'بنود العرض (الوصف، الكمية، السعر) — يجعل عرضك جاهزًا للإرسال' : 'Quote items (description, qty, price) — makes your quote ready to send'}</div>
      <div className="overflow-x-auto"><div className="min-w-[460px]">
      {items.map((it, ix) => (<div key={ix} className="flex gap-1.5 mb-1.5 items-center">
        <Lbl className="flex-1" text={(lang === 'ar' ? 'الوصف، البند ' : 'Description, line ') + (ix + 1)}><Input placeholder={lang === 'ar' ? 'الوصف' : 'Description'} value={it.description} onChange={(e) => setItems(items.map((r, i) => i === ix ? { ...r, description: e.target.value } : r))} /></Lbl>
        <Lbl text={(lang === 'ar' ? 'الكمية، البند ' : 'Quantity, line ') + (ix + 1)}><Input className="tabular font-mono text-end" style={{ maxWidth: 72 }} inputMode="decimal" placeholder={lang === 'ar' ? 'كمية' : 'Qty'} value={it.qty} onChange={(e) => setItems(items.map((r, i) => i === ix ? { ...r, qty: e.target.value } : r))} /></Lbl>
        <Lbl text={(lang === 'ar' ? 'الوحدة، البند ' : 'Unit, line ') + (ix + 1)}><Input style={{ maxWidth: 72 }} placeholder={lang === 'ar' ? 'وحدة' : 'Unit'} value={it.unit} onChange={(e) => setItems(items.map((r, i) => i === ix ? { ...r, unit: e.target.value } : r))} /></Lbl>
        <Lbl text={(lang === 'ar' ? 'سعر الوحدة، البند ' : 'Unit price, line ') + (ix + 1)}><Input className="tabular font-mono text-end" style={{ maxWidth: 104 }} inputMode="decimal" placeholder={lang === 'ar' ? 'سعر الوحدة' : 'Unit price'} value={it.unit_price} onChange={(e) => setItems(items.map((r, i) => i === ix ? { ...r, unit_price: e.target.value } : r))} /></Lbl>
        <Button size="sm" variant="outline" aria-label={(lang === 'ar' ? 'احذف البند ' : 'Remove line ') + (ix + 1)} onClick={() => setItems(items.length > 1 ? items.filter((_, i) => i !== ix) : [{ description: '', qty: '', unit: '', unit_price: '' }])}>×</Button>
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
        {checking ? (lang === 'ar' ? 'جارٍ الفحص…' : 'Checking…') : (lang === 'ar' ? 'افحص قبل الإرسال' : 'Check before sending')}
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
      <div className={cn(S.sub, 'mt-1.5')}>{ar ? 'علامة النجاح 70' : 'Pass mark is 70'}</div>

      {chk.would_accept
        ? <div className="mt-2.5">
            <Badge variant={chk.submittable ? 'ok' : 'warn'}>{ar ? 'سيُرسل إلى العميل' : 'This will be sent to the customer'}</Badge>
            {viaForm && <div className={cn(S.sub, 'mt-1.5')}>{ar
              ? 'سيُقبل لأن الحقول الأساسية مكتملة، لكنه لم يبلغ علامة الجودة. إضافة ما يلي تجعل عرضك أسهل للمقارنة وأقوى أمام العميل.'
              : 'It is accepted because the essential fields are filled, but it has not reached the quality mark. Adding the items below makes your quote easier to compare and stronger against competing bids.'}</div>}
          </div>
        : <div className="mt-2.5">
            <Badge variant="destructive">{ar ? 'سيُحفظ كمسودة' : 'This will be saved as a draft'}</Badge>
            <div className={cn(S.sub, 'mt-1.5')}>{ar ? 'لن يصل العميل حتى تُكمل ما يلي.' : 'It will not reach the customer until the items below are added.'}</div>
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
function Documents({ token, lang }) {
  const [data, setData] = useState(null); const [busy, setBusy] = useState('');
  const load = () => call('supplier_portal', { action: 'documents' }, token).then((j) => setData(j));
  useEffect(() => { load(); }, [token]);
  const [err, setErr] = useState('');
  // The server reports per-file failures now. Previously a failed storage write was swallowed and
  // the kind still came back as saved, so a supplier could be told their licence was on file when
  // nothing had been written. Surface it instead of reloading over the top of it.
  const upload = async (kind, file, expiry) => {
    setBusy(kind); setErr('');
    const b64 = await fileToB64(file);
    const j = await call('supplier_portal', { action: 'save_documents', items: [{ kind, original_b64: b64, filename: file.name, mime: file.type, expiry }] }, token);
    setBusy('');
    const failed = (j && j.failed) || [];
    // The server's per-file reasons are English sentences; an Arabic page says the same thing in Arabic.
    if (failed.length) setErr(lang === 'ar' ? 'تعذّر حفظ الملف. يُرجى رفع نسخة PDF أو صورة واضحة للمستند كاملًا، ثم المحاولة مرة أخرى.' : 'Upload failed: ' + failed.map((f) => f.reason).join('; '));
    else if (j && (j.error || j._http)) setErr(srvMsg(lang, j, lang === 'ar' ? 'تعذّر حفظ الملف. يُرجى المحاولة مرة أخرى.' : 'We could not save that file. Please try again.'));
    load();
  };
  if (!data) return <Card className="qd-panel p-5">{t(lang, 'loading_docs')}</Card>;
  // Order comes from the server (DOC_ORDER) so adding a document type needs no change here.
  const allDocs = data.documents || [];
  // Count only what is actually shown. The server still returns iban/vat, and counting them would
  // report "2/9 on file" against a list of seven — a completeness bar that can never fill.
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
            ? 'رخصتك التجارية وملفك التعريفي مطلوبان للتسجيل، ويجب أن تبقى الرخصة سارية لاستمرار استقبال الطلبات. كل ما عدا ذلك اختياري.'
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
          {rows.map((d) => <DocRow key={d.key} d={d} lang={lang} busy={busy === d.key} onUpload={upload} />)}
        </div>
      </div>;
    })}
  </div>;
}
// Grouped by what each document actually gates, because eight identical "Not uploaded" badges in one
// list reads as eight blockers. Only the first group can stop a supplier being verified; the second is
// framed by what it UNLOCKS rather than as an unmet requirement.
//
// IBAN and VAT are deliberately absent. Money moves both directions through Stripe — customers pay us,
// and a supplier settling a due pays us the same way — so we never hold a supplier's bank details.
// Their TRN is already read off the trade licence automatically, so the VAT certificate was asking for
// something we had. The backend still supports both types; this removes the ask, not the capability.
const DOC_GROUPS = [
  // Required = the documents in the mandatory six (supabase/functions/_shared/supplier_registration.ts
  // REQUIRED_DOC_KEYS). Catalogues were in this group while the server marked only the licence
  // required; they are optional, and now sit with the other optional documents.
  { id: 'required', keys: ['license', 'profile'],
    title: (l) => (l === 'ar' ? 'مطلوب للتحقق' : 'Required to get verified'),
    note: (l) => (l === 'ar'
      ? 'رخصتك التجارية وملفك التعريفي. نقرأ منهما ما تقوم به لنعرف أي الطلبات نرسلها إليك.'
      : 'Your trade licence and company profile. We read these to work out what work to send you.') },
  { id: 'optional', keys: ['catalogs', 'insurance', 'iso', 'manufacturer', 'egr'],
    title: (l) => (l === 'ar' ? 'اختياري — للحصول على مطابقات أكثر' : 'Optional — get matched to more work'),
    note: (l) => (l === 'ar'
      ? 'لا شيء من هذه مطلوب للتحقق. كل مستند تضيفه يفتح لك طلبات إضافية — بعض العملاء يشترطون التأمين، وخطاب الوكالة يتيح لنا مطابقتك عندما يطلب العميل علامة تجارية بعينها.'
      : 'None of these are needed to be verified. Each one you add opens up more requests — some customers require insurance, and a dealer letter lets us match you when a customer names a brand you carry.') },
];
// Every document type is editable here. The trade licence and company profile used to be
// deliberately read-only (editable={d.key !== 'license' && d.key !== 'profile'}), and the only
// licence upload in the product lived in ProfileForm, which renders solely while the account has
// no company yet. An established supplier whose licence expired therefore had nowhere to replace
// it — while receiving alerts telling them to do exactly that. Now that expiry suspends matching,
// that dead end would have been an account they could not reopen.
// Storage paths are prefixed with an epoch stamp to keep uploads unique, so the filename the
// server falls back to reads as "1784642799037_catalogue-vrf-2026.pdf". Only license, egr and
// iban have a dedicated name column; everything else shows the path tail. Strip the stamp for
// display so the supplier sees the name they actually uploaded.
const cleanName = (n) => String(n || '').replace(/^\d{10,}_/, '');
function DocRow({ d, busy, onUpload, lang }) {
  const [exp, setExp] = useState(d.expiry || ''); const [file, setFile] = useState(null);
  const ar = lang === 'ar';
  const label = ({ license: t(lang, 'h_trade'), profile: t(lang, 'doc_profile'), catalogs: t(lang, 'catalogues'), iso: t(lang, 'doc_iso') })[d.key] || d.label;
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
          {d.url ? <> · <a className="text-primary font-semibold underline-offset-2 hover:underline" href={d.url} target="_blank" rel="noopener">{t(lang, 'view')}</a></> : null}
        </div>}
        {isCat && (items.length
          ? <ul className="mt-1.5 flex flex-col gap-1">{items.map((c, i) => <li key={i} className={S.sub}>
              <bdi className="text-foreground/80">{cleanName(c.name)}</bdi>
              {c.url ? <> · <a className="text-primary font-semibold underline-offset-2 hover:underline" href={c.url} target="_blank" rel="noopener">{t(lang, 'view')}</a></> : null}
            </li>)}</ul>
          : <div className={cn(S.sub, 'mt-1.5')}>{t(lang, 'not_uploaded')}</div>)}
        {!isCat && !d.path && <div className={cn(S.sub, 'mt-1.5')}>{t(lang, 'not_uploaded')}</div>}
      </div>
      <div className="flex gap-2 items-center flex-wrap shrink-0">
        <FilePick lang={lang} onPick={setFile} />
        {file && <span className={cn(S.sub, 'max-w-[180px] truncate')}>{file.name}</span>}
        {/* Not for the trade licence: its expiry is read off the licence itself and save_documents
            refuses a typed one (the #86 gate), so a date box there was a control that could only fail. */}
        {d.has_expiry && d.key !== 'license' && <Input type="date" dir="ltr" className="w-auto" value={exp}
          onChange={(e) => setExp(e.target.value)} aria-label={(ar ? 'تاريخ انتهاء ' : 'Expiry date for ') + label} />}
        <Button size="sm" disabled={busy || !file} onClick={() => onUpload(d.key, file, d.key === 'license' ? '' : exp)}>
          {busy ? t(lang, 'uploading') : (d.path && !isCat ? (ar ? 'استبدال' : 'Replace') : t(lang, 'upload'))}
        </Button>
      </div>
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
    ? 'عندما يكشف العميل عن عرضك يجب أن تتواصل معه خلال 5 أيام عمل من الكشف. إن لم تتواصل خلال 3 أيام عمل نتابع معك ونُشرك العميل في المراسلة، وإن بقيت دون رد يُردّ إلى العميل كل ما دفعه، وتُستحق عليك رسوم عدم الاستجابة: المبلغ الذي رُدّ إلى العميل بالضبط (رسوم الكشف البالغة 3% مضافًا إليها رسوم معالجة البطاقة)، ورسم إداري قدره 250 درهمًا، وفائدة بسيطة بنسبة 9% سنويًا (أو الحد الأقصى الذي يسمح به القانون) من تاريخ الاستحقاق (البند 33 من اتفاقية المورّد).'
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
            {!c.phone && !c.email ? <span className={S.sub}>{ar ? 'تواصل عبر الرسائل أدناه.' : 'Use the messages below to reach them.'}</span> : null}
          </div>
        </div>
        <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
          <div className="text-[13px]">
            {p.acknowledged_at
              ? <Badge variant="ok">{ar ? 'سجّلت أنك تواصلت' : 'You confirmed contact'} · <Ltr>{fmtDate(p.acknowledged_at, lang, false)}</Ltr></Badge>
              : <Badge variant={late ? 'destructive' : chased ? 'warn' : 'secondary'}>{(late ? (ar ? 'تجاوزت مهلة الرد — ' : 'Response overdue — ') : (ar ? 'ردّ قبل ' : 'Respond by '))}<Ltr>{fmtDate(p.respond_by, lang)}</Ltr></Badge>}
          </div>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" variant="outline" onClick={() => openChat(p.inquiry_id)}>{ar ? 'راسل العميل' : 'Message the customer'}</Button>
            {!p.acknowledged_at && <Button size="sm" disabled={busy === p.id} onClick={() => ack(p.id)}>{busy === p.id ? (ar ? 'جارٍ التسجيل…' : 'Saving…') : (ar ? 'تواصلت مع العميل' : 'I have contacted the customer')}</Button>}
          </div>
        </div>
      </Card>;
    })}
  </div>;
}
// Profile tab for an established supplier. Reuses ProfileForm rather than duplicating it, so the
// same validation, terms handling and save_profile call apply whether the supplier is registering
// for the first time or correcting a detail two years later.
function ProfilePanel({ token, lang, onSaved }) {
  const [me, setMe] = useState(undefined);
  const load = () => call('supplier_api', { action: 'me' }, token).then((j) => setMe(j.supplier || null)).catch(() => setMe(null));
  useEffect(() => { load(); }, [token]);
  if (me === undefined) return <Card className="qd-panel p-5">{t(lang, 'loading')}</Card>;
  if (!me) return <Card className="qd-panel p-5"><div className={S.h2}>{t(lang, 'something_wrong')}</div><div className={S.sub}>{t(lang, 'err_generic')}</div></Card>;
  return <div className={S.list}>
    <Card className="qd-panel p-5">
      <div className={S.h2}>{lang === 'ar' ? 'ملف الشركة' : 'Company profile'}</div>
      <div className={cn(S.sub, 'mt-1')}>{lang === 'ar'
        ? 'ما تكتبه هنا يحدّد الطلبات التي تصلك. تُطابَق الطلبات على القطاع والمنتجات والخدمات والفئات — كلما كانت أدق، زادت مطابقتك.'
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
// Visible labels on all three fields (the audit found none, and the Emirate <select> had no accessible
// name). The emirate VALUE stays English — it is what leads.emirate and matching hold — while the
// option text is Arabic on /ar. The category is free text; the datalist offers Arabic labels over the
// same English values.
const CATEGORIES = ['Electrical','AC / HVAC','AC Duct Cleaning','Plumbing','Cleaning','Painting','Fit-out / Interior Design','Joinery & Kitchens','Flooring','Tiling & Marble','False Ceiling','Aluminium & Glass','Facilities Management','CCTV & Security','Smart Home','Solar','Signage','Movers','Pest Control','Handyman','Landscaping & Gardening','Curtains & Blinds','Waterproofing','Swimming Pools','Fire & Safety','MEP','Steel & Fabrication','Carpentry','Other'];
function NewCompany({ token, onReady, lang }) {
  const ar = lang === 'ar';
  const [cname, setCname] = useState(''); const [em, setEm] = useState(''); const [cat, setCat] = useState(''); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const create = async () => { if (cname.trim().length < 2) { setMsg(t(lang, 'enter_company')); return; } setBusy(true); setMsg(''); const j = await call('supplier_api', { action: 'create_company', company_name: cname.trim(), emirate: em || null, category: cat.trim() || null, role: 'supplier', lang }, token); setBusy(false); if (j && j.ok) onReady(); else setMsg(srvMsg(lang, j, t(lang, 'err_generic'))); };
  return (<Card className="qd-panel p-5">
    <h2 className={S.h2}>{t(lang, 'onboard_title')}</h2>
    <div className={cn(S.sub, 'mb-2')}>{t(lang, 'onboard_sub')}</div>
    <Lbl visible className="mt-3" text={t(lang, 'company_name')}><Input dir="auto" autoComplete="organization" placeholder={t(lang, 'company_name')} value={cname} onChange={(e) => setCname(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && create()} /></Lbl>
    <Lbl visible className="mt-3" text={t(lang, 'emirate')}>
      <select className={cn(S.field, 'mt-0 bg-card')} value={em} onChange={(e) => setEm(e.target.value)}>
        <option value="">{t(lang, 'emirate_ph')}</option>
        {EMIRATES.map((x) => <option key={x} value={x}>{emirateLabel(lang, x)}</option>)}
      </select>
    </Lbl>
    <Lbl visible className="mt-3" text={t(lang, 'cat_label')}><Input list="qd-sup-cats" dir="auto" placeholder={t(lang, 'cat_ph')} value={cat} onChange={(e) => setCat(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && create()} aria-describedby="qd-cat-help" /></Lbl>
    <datalist id="qd-sup-cats">{CATEGORIES.map((x) => <option key={x} value={x} label={ar ? CATEGORY_AR[x] || x : undefined} />)}</datalist>
    <div id="qd-cat-help" className={cn(S.sub, 'mt-1 mb-2 text-[12px]')}>{t(lang, 'cat_help')}</div>
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
    bank_name: me.bank_name || '', bank_account_name: me.bank_account_name || '',
  });
  const [emirates, setEmirates] = useState(me.service_emirates || []); const [terms, setTerms] = useState(!!me.accepted_terms_at); const [wa, setWa] = useState(!!me.wa_optin);
  const [profileFile, setProfileFile] = useState(null); const [catalogFiles, setCatalogFiles] = useState([]);
  const [phoneVerified, setPhoneVerified] = useState(false); const [smsSent, setSmsSent] = useState(false); const [smsCode, setSmsCode] = useState(''); const [vbusy, setVbusy] = useState(false);
  const [emailVerified, setEmailVerified] = useState(!!me.owner_email_verified); const [mailSent, setMailSent] = useState(false); const [mailCode, setMailCode] = useState('');
  useEffect(() => { call('kyc', { action: 'state' }, token).then((k) => { if (k && k.phone_verified) setPhoneVerified(true); if (k && k.email_verified) setEmailVerified(true); }); }, []);
  const sendSms = async () => { if (!f.phone) { setMsg(t(lang, 'verify_first')); return; } setVbusy(true); setMsg(''); const j = await call('kyc', { action: 'send_sms', phone: f.phone }, token); setVbusy(false); if (j && j.ok) setSmsSent(true); else setMsg(srvMsg(lang, j, t(lang, 'could_not_sms'))); };
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
  const toggleEm = (e) => setEmirates((a) => a.includes(e) ? a.filter((x) => x !== e) : [...a, e]);
  const save = async () => {
    // The mandatory six, checked here in the same order and with the same codes save_profile enforces
    // (supabase/functions/_shared/supplier_registration.ts), so the refusal a supplier sees on screen
    // and the one the server would give cannot disagree. An approved company editing its profile is
    // not re-gated — the server does not re-gate it either.
    if (me.approval_status !== 'approved') {
      const missing = [];
      if (!phoneVerified) missing.push('reg_mobile');
      if (!emailVerified) missing.push('reg_email');
      if (!licOnFile && !String(f.trade_license_no || '').trim()) missing.push('reg_licence');
      if (!profileFile && !me.company_profile_doc_path) missing.push('reg_profile');
      if (!terms) missing.push('reg_terms');
      if (missing.length) { setMsg(srvText(lang, 'missing_required', { missing })); return; }
    } else if (!terms) { setMsg(t(lang, 'must_accept')); return; }
    setBusy(true); setMsg('');
    try {
      if (profileFile || catalogFiles.length) {
        const prof = profileFile ? { original_b64: await fileToB64(profileFile), filename: profileFile.name, mime: profileFile.type } : undefined;
        const cats = []; for (const cf of catalogFiles.slice(0, 5)) cats.push({ original_b64: await fileToB64(cf), filename: cf.name, mime: cf.type });
        const pj = await call('supplier_api', { action: 'process_docs', company_profile: prof, catalogs: cats }, token);
        if (!(pj && pj.ok)) { setBusy(false); setMsg(srvMsg(lang, pj, t(lang, 'save_error'))); return; }
      }
      const payload = { action: 'save_profile', service_emirates: emirates, accept_terms: true };
      const strk = ['contact_name', 'signatory_name', 'phone', 'products', 'services', 'description', 'trade_license_no', 'license_authority', 'license_expiry', 'trn', 'egr_number', 'company_type', 'company_size', 'bank_name', 'bank_account_name'];
      for (const k of strk) if (String(f[k] || '').trim()) payload[k] = f[k];
      if (String(f.founded_year || '').trim()) payload.founded_year = Number(f.founded_year);
      const j = await call('supplier_api', payload, token);
      if (!(j && j.ok)) { setBusy(false); setMsg(srvMsg(lang, j, t(lang, 'could_not_save'))); return; }
      try { await call('kyc', { action: 'accept_terms' }, token); } catch (_e) {}
      try { const sess = await SB.auth.getSession(); const em = sess.data.session && sess.data.session.user && sess.data.session.user.email; if (em) await call('wa_optin_set', { email: em, user_kind: 'supplier', wa_optin: wa }, token); } catch (_e) {}
      setBusy(false); onSaved();
    } catch (_e) { setBusy(false); setMsg(t(lang, 'save_error')); }
  };
  const ok = (on) => (on ? <span aria-hidden className="text-primary">✓</span> : null);
  return (<Card className="qd-panel p-5">
    <h2 className={S.h2}>{t(lang, 'pf_company')}</h2>
    {/* The form registers a new supplier AND is where an existing one corrects a detail; it says which. */}
    <div className={cn(S.sub, 'mb-2')}>
      {isEdit
        ? (ar ? <>تحرير ملف <b dir="auto">{me.company_name}</b>. ما تكتبه هنا يحدّد الطلبات التي تصلك — احفظ التغييرات في الأسفل.</>
              : <>Editing the profile for <b dir="auto">{me.company_name}</b>. What you write here decides which requests reach you; save your changes at the bottom.</>)
        : <>{t(lang, 'registering_pre')}<b dir="auto">{me.company_name}</b>{me.name_corrected_from ? t(lang, 'corrected') : ''}{t(lang, 'registering_post')}</>}
    </div>
    <fieldset className="mt-1.5">
      <legend className={cn(S.sub, 'font-semibold')}>{t(lang, 'pf_emirates')}</legend>
      <div className="flex gap-2 flex-wrap mt-2">{EMIRATES.map((e) => <button key={e} type="button" aria-pressed={emirates.includes(e)} className={cn(S.chip, emirates.includes(e) && S.chipOn)} onClick={() => toggleEm(e)}>{emirateLabel(lang, e)}</button>)}</div>
    </fieldset>

    {/* ── REGISTRATION = THE MANDATORY SIX ───────────────────────────────────────────────────────
        Founder decision: name, mobile, e-mail (both verified), trade licence, company profile, signed
        terms; everything else optional (memory: supplier-verification-mandatory-six). The 8 Aug
        "five things" note (licence, profile, catalogue, mobile, e-mail) is superseded: the catalogue is
        optional. Contact name, products and services stay on the Profile tab, asked once inside. */}
    <h3 className={cn(S.h2, 'mt-4')}>{ok(licOnFile || !!String(f.trade_license_no || '').trim())} {t(lang, 'h_trade')}</h3>
    {!isEdit && <>
      <div className={cn(S.sub, 'mb-1.5')}>{t(lang, 'trade_sub')}</div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5"><FilePick lang={lang} accept="image/*,application/pdf" onPick={(fl) => fl && upLicense(fl)} />{uploading && <span className={S.sub} role="status">{t(lang, 'reading_lic')}</span>}</div>
      {licNote && <div role="status" className={cn(S.sub, 'font-semibold text-primary')}>{licNote}</div>}
    </>}
    <div className={S.frow}>
      <Lbl className="flex-1 min-w-[180px]" text={t(lang, 'lic_no')}><Input dir="ltr" placeholder={t(lang, 'lic_no')} value={f.trade_license_no} onChange={(e) => set('trade_license_no', e.target.value)} /></Lbl>
      <Lbl className="flex-1 min-w-[180px]" text={t(lang, 'authority')}><Input placeholder={t(lang, 'authority')} value={f.license_authority} onChange={(e) => set('license_authority', e.target.value)} /></Lbl>
    </div>

    <h3 className={cn(S.h2, 'mt-4')}>{ok(phoneVerified && emailVerified)} {t(lang, 'pf_contact')}</h3>
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
    <div className={S.frow}><Lbl className="flex-1" text={t(lang, 'mobile')}><Input type="tel" autoComplete="tel" dir="ltr" placeholder={t(lang, 'mobile')} value={f.phone} onChange={(e) => set('phone', e.target.value)} /></Lbl></div>
    {phoneVerified ? <div className={cn(S.sub, 'font-semibold text-primary')}>{t(lang, 'mobile_verified')}</div> : (!smsSent ? <Button variant="link" className="px-0 h-auto mt-1.5" disabled={vbusy} onClick={sendSms}>{vbusy ? t(lang, 'sending') : t(lang, 'verify_my_mobile')}</Button> : <><div className={S.hint}>{t(lang, 'junk_note')}</div><div className={S.frow}><Lbl text={t(lang, 'sms_code')}><Input inputMode="numeric" autoComplete="one-time-code" dir="ltr" placeholder={t(lang, 'sms_code')} value={smsCode} onChange={(e) => setSmsCode(e.target.value)} /></Lbl><Button size="sm" disabled={vbusy} onClick={verifySms}>{t(lang, 'verify')}</Button></div></>)}

    {isEdit && <>
      <div className={S.frow}><Lbl className="flex-1" text={t(lang, 'contact_name')}><Input placeholder={t(lang, 'contact_name')} value={f.contact_name} onChange={(e) => set('contact_name', e.target.value)} /></Lbl><Lbl className="flex-1" text={t(lang, 'signatory')}><Input placeholder={t(lang, 'signatory')} value={f.signatory_name} onChange={(e) => set('signatory_name', e.target.value)} /></Lbl></div>
      <h3 className={cn(S.h2, 'mt-4')}>{t(lang, 'h_offer')}</h3>
      <Lbl text={t(lang, 'products_ph')}><Input className="mt-3" placeholder={t(lang, 'products_ph')} value={f.products} onChange={(e) => set('products', e.target.value)} /></Lbl>
      <Lbl text={t(lang, 'services_ph')}><Input className="mt-3" placeholder={t(lang, 'services_ph')} value={f.services} onChange={(e) => set('services', e.target.value)} /></Lbl>
      <Lbl text={t(lang, 'desc_ph')}><textarea className={S.area} rows={3} placeholder={t(lang, 'desc_ph')} value={f.description} onChange={(e) => set('description', e.target.value)} /></Lbl>
    </>}
    <label className="flex gap-2 items-center mt-3.5 text-[13px] text-muted-foreground"><input type="checkbox" checked={wa} onChange={(e) => setWa(e.target.checked)} /> {t(lang, 'wa_alerts')}</label>
    {!isEdit && <>
      <h3 className={cn(S.h2, 'mt-4')}>{ok(!!profileFile || !!me.company_profile_doc_path)} {t(lang, 'doc_profile')}</h3>
      <div className={cn(S.sub, 'mb-1')}>{ar ? 'الملف التعريفي مطلوب؛ الكتالوجات اختيارية ويمكن إضافتها لاحقًا من تبويب المستندات.' : 'The company profile is required; catalogues are optional and can be added later from Documents.'}</div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5"><span className={S.sub}>{t(lang, 'company_profile_pdf')}</span><FilePick lang={lang} accept=".pdf,.jpg,.jpeg,.png" onPick={setProfileFile} />{profileFile && <span className={S.sub}>{profileFile.name}</span>}</div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5"><span className={S.sub}>{t(lang, 'catalogs_ph')}</span><FilePick lang={lang} accept=".pdf,.jpg,.jpeg,.png" multiple onPick={(a) => setCatalogFiles((a || []).slice(0, 5))} />{catalogFiles.length ? <span className={S.sub}>{catalogFiles.length} {t(lang, 'selected')}</span> : null}</div>
    </>}
    {isEdit && <div className={cn(S.sub, 'mt-3 rounded-md border border-border bg-secondary/30 px-3 py-2.5')}>{ar ? 'رخصتك التجارية وملفك التعريفي وكتالوجاتك تُدار من تبويب المستندات — حتى لا يُطلب الملف نفسه في مكانين.' : 'Your trade licence, company profile and catalogues are managed in the Documents tab — so the same file is never asked for in two places.'}</div>}

    <label className="flex gap-2 items-center mt-3.5 text-[13px] text-muted-foreground"><input type="checkbox" checked={terms} onChange={(e) => setTerms(e.target.checked)} /> {t(lang, 'accept_pre')}<a href={(ar ? '/ar' : '') + '/supplier-agreement'} target="_blank" rel="noopener" className="text-primary font-semibold">{t(lang, 'terms_link')}</a>{t(lang, 'accept_post')}</label>
    <Button className="w-full mt-3" disabled={busy || uploading} onClick={save}>
      {busy ? (isEdit ? (ar ? 'جارٍ الحفظ…' : 'Saving…') : t(lang, 'submitting'))
            : isEdit ? (ar ? 'حفظ التغييرات' : 'Save changes') : t(lang, 'submit_approval')}
    </Button>
    {msg && <div role="alert" className={S.err}>{msg}</div>}
  </Card>);
}

// messages_api opens a post-reveal chat on first touch (the request queue it used to wait on was
// removed 7-8 Sep), so a thread is either open or closed for a policy breach. The "Ask / request a
// chat" box that sat under a closed thread called request_chat, which now only ever answers "open" —
// a control with no remaining function — and it is gone. The server's English status words, notes
// and warning are rendered in the supplier's language here.
const CHAT_ST = { open: ['Open', 'مفتوحة'], none: ['Not started', 'لم تبدأ'], requested: ['Pending', 'قيد المراجعة'], banned: ['Closed — policy', 'مغلقة — مخالفة'], closed: ['Closed', 'مغلقة'] };
const chatSt = (lang, s) => (CHAT_ST[s] ? CHAT_ST[s][lang === 'ar' ? 1 : 0] : (lang === 'ar' ? 'مغلقة' : String(s || '')));
const CHAT_WARNING_AR = 'تُحفظ الرسائل هنا في السجل لكلا الطرفين. يُرجى أن تبقى متعلقة بهذا العمل.';
function Messages({ token, lang, openInquiry = null, onOpened = null }) {
  const [threads, setThreads] = useState(null); const [open, setOpen] = useState(null);
  const loadThreads = () => call('messages_api', { action: 'threads' }, token).then((j) => setThreads((j && j.threads) || []));
  useEffect(() => { loadThreads(); }, [token]);
  // Opened from a Projects card: go straight to that job's chat.
  useEffect(() => { if (!openInquiry || !threads) return; const th = threads.find((x) => x.inquiry_id === openInquiry); if (th) setOpen(th); if (onOpened) onOpened(); }, [openInquiry, threads]);
  if (!threads) return <Card className="qd-panel p-5" aria-busy="true">{t(lang, 'loading_msgs')}</Card>;
  if (open) return <Thread token={token} th={open} lang={lang} onBack={() => { setOpen(null); loadThreads(); }} />;
  if (!threads.length) return <Card className="qd-panel p-5"><div className={S.h2}>{t(lang, 'no_convos_h')}</div><div className={S.sub}>{t(lang, 'no_convos_sub')}</div></Card>;
  return <ul className={S.list}>{threads.map((it) => <li key={it.inquiry_id + ':' + it.supplier_id}><button type="button" className="qd-panel qd-panel-hover w-full p-5 flex justify-between items-center gap-3 text-start" onClick={() => setOpen(it)}>
    <span className="min-w-0"><b className="text-foreground">{it.counterpart === 'Customer' ? (lang === 'ar' ? 'العميل' : 'Customer') : <bdi>{it.counterpart}</bdi>}</b> · <bdi>{it.subject || ''}</bdi><span className={cn(S.sub, 'block')}>{it.last || t(lang, 'no_messages')}</span></span>
    <span className="text-end shrink-0">{it.unread ? <span className="inline-block rounded-full bg-primary text-primary-foreground px-2 py-0.5 text-[11px] font-bold">{it.unread}</span> : null}<span className={cn(S.sub, 'block')}>{it.chat_status === 'none' ? t(lang, 'no_chat') : chatSt(lang, it.chat_status)}</span></span>
  </button></li>)}</ul>;
}
function Thread({ token, th, onBack, lang }) {
  const ar = lang === 'ar';
  const [data, setData] = useState(null); const [text, setText] = useState(''); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const load = () => call('messages_api', { action: 'thread', inquiry_id: th.inquiry_id, supplier_id: th.supplier_id }, token).then(setData);
  useEffect(() => { load(); }, []);
  const send = async () => { if (!text.trim()) return; setBusy(true); setMsg(''); const j = await call('messages_api', { action: 'send', inquiry_id: th.inquiry_id, supplier_id: th.supplier_id, body: text.trim() }, token); setBusy(false); if (j && j.ok) { setText(''); load(); } else setMsg(ar ? t(lang, 'could_not_send') : ((j && (j.warning || j.error)) || t(lang, 'could_not_send'))); };
  if (!data) return <Card className="qd-panel p-5" aria-busy="true">{t(lang, 'loading')}</Card>;
  const who = !data.counterpart || data.counterpart === 'Customer' ? (ar ? 'العميل' : 'Customer') : data.counterpart;
  const closedNote = data.chat_status === 'banned' ? (ar ? 'أُغلقت هذه المحادثة بسبب مخالفة للسياسة.' : 'This chat is closed due to a policy violation.')
    : data.locked && !data.chat_status ? (ar ? 'تُفتح الرسائل بعد أن يكشف العميل عن عرضك.' : 'Messaging unlocks after the quote is revealed.')
    : (ar ? 'لا توجد محادثة مفتوحة بعد.' : (data.note || t(lang, 'no_chat_open')));
  return <Card className="qd-panel p-5">
    <div className="flex justify-between items-center gap-2.5"><div className={S.h2}><bdi>{who}</bdi></div><Button variant="link" className="px-0 h-auto" onClick={onBack}>{t(lang, 'back')}</Button></div>
    {data.warning && <div className="rounded-md border border-warn/30 bg-warn/10 text-warn-fg px-3 py-2 text-[11.5px] mb-2.5">{ar ? CHAT_WARNING_AR : data.warning}</div>}
    {data.chat_status === 'open' ? (<>
      <div className="flex flex-col gap-2 my-2.5 max-h-[420px] overflow-y-auto" aria-live="polite">{(data.messages || []).map((m) => <div key={m.id} dir="auto" className={cn('max-w-[76%] px-3 py-2 rounded-xl text-[13.5px] leading-snug', m.sender === data.role ? 'self-end bg-primary/80 text-primary-foreground' : 'self-start bg-secondary text-foreground')}>{m.body}</div>)}</div>
      <div className={S.frow}><Lbl className="flex-1" text={t(lang, 'type_message')}><Input dir="auto" placeholder={t(lang, 'type_message')} value={text} onChange={(e) => setText(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && send()} /></Lbl><Button size="sm" disabled={busy || !text.trim()} onClick={send}>{t(lang, 'send')}</Button></div>
    </>) : <div className={cn(S.sub, 'mb-2')}>{closedNote}</div>}
    {msg && <div role="alert" className={cn(S.err, 'mt-2')}>{msg}</div>}
  </Card>;
}
