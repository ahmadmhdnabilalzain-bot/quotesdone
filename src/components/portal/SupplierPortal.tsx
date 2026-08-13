// @ts-nocheck
'use client';
import { useEffect, useRef, useState } from 'react';
import { createClient } from '@supabase/supabase-js';
// Row #5 §3/§4/§6/§13 — kept in its own file deliberately; see the TABS comment below.
import SupplierTwin from './supplier/SupplierTwin';
import ProductIntelligence from './supplier/ProductIntelligence';
import SupplierAdvisor from './supplier/SupplierAdvisor';
import MarketIntelligence from './supplier/MarketIntelligence';
import CollaborationWorkspace from './supplier/CollaborationWorkspace';
import SupplierOnboarding from './supplier/SupplierOnboarding';
import SupplierQuoteBuilder from './supplier/SupplierQuoteBuilder';
import SupplierSettings from './supplier/SupplierSettings';
import SupplierInventory from './supplier/SupplierInventory';
import SupplierDocumentImpact from './supplier/SupplierDocumentImpact';
import SupplierKnowledgeGraph from './supplier/SupplierKnowledgeGraph';
import SupplierInsightBoard from './supplier/SupplierInsightBoard';
import SupplierOpportunities from './supplier/SupplierOpportunities';
import SupplierTier from './supplier/SupplierTier';
import SupplierNegotiation from './supplier/SupplierNegotiation';
import SupplierCertifications from './supplier/SupplierCertifications';
import SupplierEntryHero from './supplier/SupplierEntryHero';
import SupplierCommandPalette from './supplier/SupplierCommandPalette';
import dynamic from 'next/dynamic';
// 3D is client-only and heavy; loaded on demand so the portal's first paint does not carry WebGL.
const SupplierEnvironment = dynamic(() => import('./supplier/SupplierEnvironment'), { ssr: false });
const SupplierNetworkMap = dynamic(() => import('./supplier/SupplierNetworkMap'), { ssr: false });
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

async function call(path, body, token) {
  const r = await fetch(FN + '/' + path, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) }, body: JSON.stringify(body) });
  return r.json();
}
const aed = (n) => 'AED ' + Number(n || 0).toLocaleString('en-AE', { maximumFractionDigits: 0 });
const fileToB64 = (f) => new Promise((res) => { const rd = new FileReader(); rd.onload = () => res(String(rd.result).split(',')[1]); rd.readAsDataURL(f); });
const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Umm Al Quwain', 'Fujairah'];
function BillingPanel({ token, lang }) {
  const [st, setSt] = useState({ loading: true, dues: [], total: 0, err: '' });
  const [busy, setBusy] = useState(false);
  const load = async () => {
    setSt((s) => ({ ...s, loading: true, err: '' }));
    const j = await call('supplier_pay', { action: 'list' }, token);
    if (j && j.ok) setSt({ loading: false, dues: j.dues || [], total: Number(j.total_owed || 0), err: '' });
    else setSt({ loading: false, dues: [], total: 0, err: (j && j.error) || 'load_err' });
  };
  useEffect(() => { load(); }, [token]);
  const pay = async () => {
    setBusy(true);
    const j = await call('supplier_pay', { action: 'checkout', return_url: window.location.origin }, token);
    if (j && j.ok && j.url) { window.location.href = j.url; return; }
    setBusy(false);
    setSt((s) => ({ ...s, err: (j && (j.detail || j.error)) || 'checkout_err' }));
  };
  if (st.loading) return <Card className="qd-panel p-5">{t(lang, 'loading_dash')}</Card>;
  if (st.err) return <Card className="qd-panel p-5"><div className={S.h2}>{t(lang, 'something_wrong')}</div><div className={S.sub}>{t(lang, 'bill_err')}</div><Button className="mt-3" onClick={load}>{t(lang, 'bill_retry')}</Button></Card>;
  if (!st.dues.length) return <Card className="qd-panel p-5"><div className={S.h2}>{t(lang, 'bill_title')}</div><div className={S.sub}>{t(lang, 'bill_none')}</div></Card>;
  return (
    <Card className="qd-panel p-5">
      <div className={S.h2}>{t(lang, 'bill_title')}</div>
      <div className="flex flex-col gap-2 my-3">
        {st.dues.map((d) => (
          <div key={d.id} className="flex justify-between items-center border-b border-border pb-2 text-[13.5px]">
            <div>
              <div className="font-semibold">{aed(d.amount)}</div>
              <div className={S.sub}>{t(lang, 'bill_commission') + ' ' + aed(d.commission) + (d.fine ? ' · ' + t(lang, 'bill_fine') + ' ' + aed(d.fine) : '')}</div>
            </div>
            <div className={S.sub}>{d.due_date ? t(lang, 'bill_due') + ' ' + d.due_date : ''}</div>
          </div>
        ))}
      </div>
      <div className="flex justify-between items-center mt-3 flex-wrap gap-3">
        <div>
          <div className={S.sub}>{t(lang, 'bill_total')}</div>
          <div className="text-[20px] font-extrabold text-foreground">{aed(st.total)}</div>
        </div>
        <Button onClick={pay} disabled={busy}>{busy ? t(lang, 'bill_paying') : t(lang, 'bill_pay')}</Button>
      </div>
      <div className={cn(S.sub, 'mt-3')}>{t(lang, 'bill_secure')}</div>
    </Card>
  );
}

function ensurePdfjs() { return new Promise((res, rej) => { if (window.pdfjsLib) return res(window.pdfjsLib); const sc = document.createElement('script'); sc.src = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js'; sc.onload = () => { try { window.pdfjsLib.GlobalWorkerOptions.workerSrc = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js'; } catch (_e) {} res(window.pdfjsLib); }; sc.onerror = rej; document.head.appendChild(sc); }); }
async function fileToImages(file) {
  const b64 = await fileToB64(file);
  if (file.type && file.type.startsWith('image/')) return { images: [{ mime: file.type, data: b64 }], b64, mime: file.type };
  if (file.type === 'application/pdf') {
    try { const L = await ensurePdfjs(); const raw = atob(b64); const arr = new Uint8Array(raw.length); for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
      const pdf = await L.getDocument({ data: arr }).promise; const out = []; const n = Math.min(pdf.numPages, 6);
      // Long edge capped for the same reason as the customer portal: scale 1.8 on an ANSI-D sheet
      // is 21 megapixels, which killed drawing_redact's isolate outright (HTTP 546) on one page.
      const MAX_EDGE = 2600;
      for (let pnum = 1; pnum <= n; pnum++) { const pg = await pdf.getPage(pnum); const v1 = pg.getViewport({ scale: 1 }); const vp = pg.getViewport({ scale: Math.min(1.8, MAX_EDGE / Math.max(v1.width, v1.height)) }); const c = document.createElement('canvas'); c.width = vp.width; c.height = vp.height; await pg.render({ canvasContext: c.getContext('2d'), viewport: vp }).promise; out.push({ mime: 'image/jpeg', data: c.toDataURL('image/jpeg', 0.8).split(',')[1] }); }
      return { images: out, b64, mime: 'application/pdf' };
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
    onboard_title:'Register your company', onboard_sub:'Enter your company name and main emirate. Registration is free for every supplier until 31 July 2027; the first 1,000 to register stay free permanently.', company_name:'Company name', emirate:'Emirate', create_company:'Create company', enter_company:'Enter your company name.', err_generic:'Something went wrong.', something_wrong:'Something went wrong',
    t_overview:'Overview', t_billing:'Billing', bill_title:'Amounts due', bill_none:'Nothing to pay. You are not charged commission on the work you win.', bill_total:'Total outstanding', bill_pay:'Pay now', bill_paying:'Opening secure checkout…', bill_err:'We could not load your balance. Please try again.', bill_commission:'Reveal fee recovered', bill_fine:'Late fee', bill_due:'Due', bill_retry:'Try again', bill_secure:'You will be redirected to Stripe to pay securely. QuotesDone never sees your card details. These charges arise only when a customer is refunded because we could not reach you \u2014 there is no commission on won work.', t_rfqs:'RFQs', t_documents:'Documents', t_projects:'Projects', t_messages:'Messages', approved:'Approved', pending:'Pending',
    k_quotes_sent:'Quotes sent', k_reveals:'Reveals', k_hired:'Hired', k_win:'Win ratio', k_rating:'Rating', k_deal_value:'Deal value won',
    price_pos:'Price positioning', anon_note:'anonymous — never shows competitor prices', not_enough:'not enough data', last12:'Last 12 months', quotes_reveals:'quotes / reveals',
    pp_fallback:'Once you quote on a few competitive RFQs, you will see how your pricing compares to the market here — without ever revealing anyone else pricing.',
    pf_company:'Company', pf_emirates:'Emirates you serve', pf_contact:'Contact & owner', contact_name:'Contact name *', mobile:'Mobile *',
    mobile_verified:'✓ Mobile verified', verify_my_mobile:'Verify my mobile →', sms_code:'6-digit SMS code', verify:'Verify',
    email_verified:'✓ E-mail verified', email_unverified:'e-mail not yet verified',
    reg_rest_optional:'Attach these two and you are done. Everything else is optional and can wait until you are inside.',
    wa_alerts:'Send me WhatsApp alerts when a matching RFQ comes in.', verify_first:'Please verify your mobile number first.',
    accept_pre:'I accept the QuotesDone ', terms_link:'supplier terms', accept_post:'.', submit_approval:'Submit for approval', submitting:'Submitting…', must_accept:'Please accept the supplier terms.', loading_rfqs:'Loading RFQs…', no_rfqs_h:'No open RFQs right now', no_rfqs_sub:'When a customer posts a request that matches your capabilities, it appears here.', request_w:'Request', you_won:' · You won', concluded:' · Concluded', quoted:'Quoted ', close:'Close', quote:'Quote', boq_prefix:'BOQ: ', boq_items:'line items', confidence:' confidence', drawing_p:'Drawing p', upload_quote:"Upload your quotation (PDF/photo) — we'll read it:", reading:'Reading…', total_aed:'Total amount (AED)', lead_time:'Lead time (e.g. 10 days)', scope_work:'Scope of work', notes_customer:'Notes for the customer', submit_quote:'Submit quote', enter_valid_amount:'Enter a valid amount.', could_not_read:'Could not read the file — please fill the form.', could_not_submit:'Could not submit.', draft_saved:'Saved as draft — add the missing details to send it.', read_quote_pre:'Read your quotation', line_items:'line items', read_quote_post:'. Review and submit.', loading_docs:'Loading documents…', docs_h:'Documents & certificates', docs_sub:'Upload renewals before they expire — we will remind you here and pause matching if a required document lapses.', st_expired:'Expired', st_expiring:'Expiring soon', st_valid:'Valid', expires_pre:'Expires ', on_file:'On file', not_uploaded:'Not uploaded yet', view:'view', uploading:'Uploading…', upload:'Upload', no_projects_h:'No won projects yet', no_projects_sub:'When a customer reveals and hires you, the project appears here.', project_w:'Project', loading_msgs:'Loading messages…', no_convos_h:'No conversations yet', no_convos_sub:'Once a customer reveals your quote on a project, you can request a direct chat with them here. Our assistant handles most questions instantly.', no_messages:'No messages yet', no_chat:'no chat', back:'← Back', type_message:'Type a message…', send:'Send', no_chat_open:'No chat open yet.', ask_placeholder:"Ask a question — our assistant answers instantly, or opens a direct chat if it's really needed.", ask_request:'Ask / request a chat', assistant_pre:'Assistant: ', could_not_send:'Could not send.', sent_review:'Sent for review — you will be notified if a chat opens.', sent:'Sent.', no_history:'No history yet.', registering_pre:'Registering ', registering_post:'. Registration is free for every supplier until 31 July 2027; the first 1,000 to register stay free permanently.', corrected:' (corrected from your licence)', signatory:'Authorized signatory', owner_dob:'Owner date of birth', h_trade:'Trade licence', trade_sub:'Upload your licence and we read the number, authority, expiry and TRN automatically.', reading_lic:'Reading licence…', lic_no:'Trade licence no. *', authority:'Authority (DED / free zone)', lic_expiry:'Licence expiry', vat_trn:'VAT no. (TRN)', h_egr:'Establishment (EGR)', egr_no:'Economic Register (EGR) no.', egr_cert:'EGR / establishment certificate:', h_offer:'What you offer', products_ph:'Products you supply (comma separated)', services_ph:'Services you offer', desc_ph:'Short company description / capabilities', company_profile_pdf:'Company profile (PDF):', catalogs_ph:'Product catalogs (up to 5):', h_bank:'Bank / payout', bank_name_ph:'Bank name', account_holder:'Account holder name', add_contact_phone:'Add your contact name and phone.', add_license:'Add your trade licence number (or upload your licence to auto-fill it).', could_not_save:'Could not save your profile.', save_error:'Something went wrong saving your profile. Please try again.', lic_on_file:'Trade licence on file.', could_not_sms:'Could not send SMS.', wrong_code:'Wrong code.', read_lic:'Read your licence', expires_comma:', expires ', lic_uploaded:'Licence uploaded.', lic_uploaded_noread:'Uploaded (could not auto-read).', attach_file:'Attach file', selected:'selected', lic_expires:'Licence expires', lic_expired:'Licence expired', action_required:'Action required', ar_days_left:'days left to fix this', ar_overdue:'Overdue - your account can be suspended', ar_why:'Why', catalogues:'Catalogues', doc_profile:'Company profile', doc_iso:'ISO certification', add_profile:'Please attach your company profile (required).' },
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
    onboard_title:'سجّل شركتك', onboard_sub:'أدخل اسم شركتك وإمارتك الرئيسية. التسجيل مجاني لجميع الموردين حتى 31 يوليو 2027، وأول 1,000 مورّد يسجّلون يبقون معفيين بشكل دائم.', company_name:'اسم الشركة', emirate:'الإمارة', create_company:'إنشاء الشركة', enter_company:'أدخل اسم شركتك.', err_generic:'حدث خطأ ما.', something_wrong:'حدث خطأ ما',
    t_overview:'نظرة عامة', t_billing:'الفواتير', bill_title:'المبالغ المستحقة', bill_none:'لا توجد مبالغ مستحقة. لا نأخذ أي عمولة على الأعمال التي تفوز بها.', bill_total:'إجمالي المستحق', bill_pay:'ادفع الآن', bill_paying:'جارٍ فتح صفحة الدفع الآمنة…', bill_err:'تعذّر تحميل رصيدك. يرجى المحاولة مرة أخرى.', bill_commission:'استرداد رسو�� الكشف', bill_fine:'رسوم التأخير', bill_due:'تاريخ الاستحقاق', bill_retry:'حاول مرة أخرى', bill_secure:'سيتم تحويلك إلى Stripe للدفع بأمان. لا تطّلع QuotesDone على بيانات بطاقتك. تنشأ هذه المبالغ فقط عند استرداد مبلغ للعميل لتعذّر الوصول إليك \u2014 ولا توجد عمولة على الأعمال المنجزة.', t_rfqs:'طلبات التسعير', t_documents:'المستندات', t_projects:'المشاريع', t_messages:'الرسائل', approved:'معتمد', pending:'قيد المراجعة',
    k_quotes_sent:'العروض المُرسلة', k_reveals:'مرات الكشف', k_hired:'المُتعاقد معه', k_win:'نسبة الفوز', k_rating:'التقييم', k_deal_value:'قيمة الصفقات',
    price_pos:'الموقع السعري', anon_note:'مجهول — لا يعرض أسعار المنافسين أبدًا', not_enough:'بيانات غير كافية', last12:'آخر 12 شهرًا', quotes_reveals:'عروض / كشوفات',
    pp_fallback:'بمجرد تقديمك عروضًا على بعض طلبات التسعير التنافسية، سترى هنا كيف تقارن أسعارك بالسوق — دون الكشف عن أسعار أي طرف آخر.',
    pf_company:'الشركة', pf_emirates:'الإمارات التي تخدمها', pf_contact:'جهة الاتصال والمالك', contact_name:'اسم جهة الاتصال *', mobile:'الجوال *',
    mobile_verified:'✓ تم التحقق من الجوال', verify_my_mobile:'تحقّق من جوالي ←', sms_code:'رمز الرسالة (6 أرقام)', verify:'تحقّق',
    email_verified:'✓ تم التحقق من البريد', email_unverified:'لم يتم التحقق من البريد بعد',
    reg_rest_optional:'أرفق هذين الملفين وانتهيت. كل ما عدا ذلك اختياري ويمكن إكماله بعد الدخول.',
    wa_alerts:'أرسل لي تنبيهات واتساب عند وصول طلب تسعير مطابق.', verify_first:'يُرجى التحقق من رقم جوالك أولًا.',
    accept_pre:'أوافق على ', terms_link:'شروط المورّد', accept_post:' الخاصة بمنصة QuotesDone.', submit_approval:'إرسال للموافقة', submitting:'جارٍ الإرسال…', must_accept:'يُرجى الموافقة على شروط المورّد.', loading_rfqs:'جارٍ تحميل طلبات التسعير…', no_rfqs_h:'لا توجد طلبات تسعير مفتوحة حاليًا', no_rfqs_sub:'عندما ينشر عميل طلبًا يطابق إمكانياتك، سيظهر هنا.', request_w:'طلب', you_won:' · فزت بالطلب', concluded:' · مُغلق', quoted:'قدّمت عرضًا: ', close:'إغلاق', quote:'قدّم عرضًا', boq_prefix:'جدول الكميات: ', boq_items:'بند', confidence:' ثقة', drawing_p:'المخطط ص', upload_quote:'ارفع عرض السعر (PDF/صورة) — سنقرأه:', reading:'جارٍ القراءة…', total_aed:'المبلغ الإجمالي (درهم)', lead_time:'مدة التنفيذ (مثال: 10 أيام)', scope_work:'نطاق العمل', notes_customer:'ملاحظات للعميل', submit_quote:'إرسال العرض', enter_valid_amount:'أدخل مبلغًا صحيحًا.', could_not_read:'تعذّرت قراءة الملف — يُرجى تعبئة النموذج.', could_not_submit:'تعذّر الإرسال.', draft_saved:'حُفظ كمسودة — أضف التفاصيل الناقصة لإرساله.', read_quote_pre:'قرأنا عرضك', line_items:'بند', read_quote_post:'. راجعه وأرسله.', loading_docs:'جارٍ تحميل المستندات…', docs_h:'المستندات والشهادات', docs_sub:'ارفع التجديدات قبل انتهائها — سنذكّرك هنا وسنوقف المطابقة إذا انتهى مستند مطلوب.', st_expired:'منتهٍ', st_expiring:'ينتهي قريبًا', st_valid:'سارٍ', expires_pre:'ينتهي في ', on_file:'محفوظ', not_uploaded:'لم يُرفع بعد', view:'عرض', uploading:'جارٍ الرفع…', upload:'رفع', no_projects_h:'لا توجد مشاريع فائزة بعد', no_projects_sub:'عندما يكشف العميل عن عرضك ويتعاقد معك، يظهر المشروع هنا.', project_w:'مشروع', loading_msgs:'جارٍ تحميل الرسائل…', no_convos_h:'لا توجد محادثات بعد', no_convos_sub:'بمجرد أن يكشف العميل عن عرضك في مشروع، يمكنك طلب محادثة مباشرة معه هنا. مساعدنا يجيب عن معظم الأسئلة فورًا.', no_messages:'لا رسائل بعد', no_chat:'لا محادثة', back:'→ رجوع', type_message:'اكتب رسالة…', send:'إرسال', no_chat_open:'لا توجد محادثة مفتوحة بعد.', ask_placeholder:'اطرح سؤالًا — يجيب مساعدنا فورًا، أو يفتح محادثة مباشرة عند الحاجة فعلًا.', ask_request:'اسأل / اطلب محادثة', assistant_pre:'المساعد: ', could_not_send:'تعذّر الإرسال.', sent_review:'أُرسل للمراجعة — سنُعلمك إذا فُتحت محادثة.', sent:'أُرسل.', no_history:'لا يوجد سجل بعد.', registering_pre:'تسجيل ', registering_post:'. التسجيل مجاني لجميع الموردين حتى 31 يوليو 2027، وأول 1,000 مورّد يسجّلون يبقون معفيين بشكل دائم.', corrected:' (مُصحّح من رخصتك)', signatory:'المفوّض بالتوقيع', owner_dob:'تاريخ ميلاد المالك', h_trade:'الرخصة التجارية', trade_sub:'ارفع رخصتك وسنقرأ الرقم والجهة وتاريخ الانتهاء والرقم الضريبي تلقائيًا.', reading_lic:'جارٍ قراءة الرخصة…', lic_no:'رقم الرخصة التجارية *', authority:'الجهة (دائرة التنمية الاقتصادية / منطقة حرة)', lic_expiry:'انتهاء الرخصة', vat_trn:'الرقم الضريبي (TRN)', h_egr:'المنشأة (السجل الاقتصادي)', egr_no:'رقم السجل الاقتصادي (EGR)', egr_cert:'شهادة السجل الاقتصادي / المنشأة:', h_offer:'ما الذي تقدّمه', products_ph:'المنتجات التي توردها (مفصولة بفواصل)', services_ph:'الخدمات التي تقدّمها', desc_ph:'وصف مختصر للشركة / القدرات', company_profile_pdf:'الملف التعريفي للشركة (PDF):', catalogs_ph:'كتالوجات المنتجات (حتى 5):', h_bank:'البنك / التحويل', bank_name_ph:'اسم البنك', account_holder:'اسم صاحب الحساب', add_contact_phone:'أضف اسم جهة الاتصال ورقم الهاتف.', add_license:'أضف رقم رخصتك التجارية (أو ارفع الرخصة لتعبئته تلقائيًا).', could_not_save:'تعذّر حفظ ملفك.', save_error:'حدث خطأ أثناء حفظ ملفك. يُرجى المحاولة مرة أخرى.', lic_on_file:'الرخصة التجارية محفوظة.', could_not_sms:'تعذّر إرسال الرسالة.', wrong_code:'رمز خاطئ.', read_lic:'قرأنا رخصتك', expires_comma:'، تنتهي في ', lic_uploaded:'تم رفع الرخصة.', lic_uploaded_noread:'تم الرفع (تعذّرت القراءة التلقائية).', attach_file:'إرفاق ملف', selected:'محدد', lic_expires:'تنتهي الرخصة', lic_expired:'انتهت الرخصة', action_required:'إجراء مطلوب', ar_days_left:'يوماً متبقياً لمعالجة هذا', ar_overdue:'تجاوز الموعد - قد يُعلَّق حسابك', ar_why:'السبب', catalogues:'الكتالوجات', doc_profile:'الملف التعريفي للشركة', doc_iso:'شهادة ISO', add_profile:'يُرجى إرفاق الملف التعريفي للشركة (مطلوب).' }
};
const t = (lang, k) => (T[lang] && T[lang][k]) || T.en[k] || k;
function initLang(){ try{ if(typeof window==='undefined') return 'en'; const ls=localStorage.getItem('qd-lang'); if(ls) return ls; const m=document.cookie.match(/(?:^|; )NEXT_LOCALE=([^;]+)/); if(m && String(m[1]).startsWith('ar')) return 'ar'; }catch(_e){} return 'en'; }
// Typography and chrome carry the platform's voice: display weights are optically
// tightened, body copy keeps a readable measure, and the tab bar is an inset well
// with a RAISED active pill rather than a tinted one — so the current tab reads as
// nearer to the viewer, which is how the rest of the product signals state.
const S = {
  center: 'grid place-items-center min-h-[70vh] p-5',
  h1: 'text-[22px] font-extrabold tracking-[-.03em] text-white',
  h2: 'text-[15.5px] font-bold tracking-[-.018em] text-white',
  sub: 'text-[13px] leading-[1.65] text-muted-foreground max-w-[68ch]',
  anon: 'ml-1.5 text-[11px] font-semibold text-muted-foreground/80',
  hint: 'text-xs text-muted-foreground my-2 leading-relaxed max-w-[68ch]',
  err: 'text-[13px] text-red-300 mt-2',
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

  const load = async () => {
    setSt((s) => ({ ...s, loading: true, err: '' }));
    const j = await call('supplier_api', { action: 'capability_state' }, token);
    if (j && j.ok) {
      const cap = j.capability || null;
      setTrades((cap && cap.trades) || []);
      setRoles((cap && cap.roles) || []);
      setSt({ loading: false, err: '', confirmed: !!j.confirmed, cap, vocab: j.vocabulary || { trades: [], roles: [] } });
    } else {
      setSt((s) => ({ ...s, loading: false, err: (j && (j.error || j.detail)) || 'load_err' }));
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
    else setSt((s) => ({ ...s, err: (j && (j.message || j.error)) || 'confirm_err' }));
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
          {(st.vocab.trades || []).map((tr) => (
            <button key={tr.code} type="button" className={chip(trades.includes(tr.code))}
                    onClick={() => toggle(trades, setTrades, tr.code)}>{tr.label || tr.code}</button>
          ))}
        </div>
      </div>

      <div className="mt-4">
        <div className="text-sm opacity-70 mb-2">{ar ? 'دورك' : 'Your role'}</div>
        <div className="flex flex-wrap gap-2">
          {(st.vocab.roles || []).map((r) => (
            <button key={r.code} type="button" className={chip(roles.includes(r.code))}
                    onClick={() => toggle(roles, setRoles, r.code)}>{r.label || r.code}</button>
          ))}
        </div>
      </div>

      {/* The server refuses a confirm with no trade or no role. Say so here rather than letting the
          supplier press a button that returns 400. */}
      {(!trades.length || !roles.length) && (
        <div className="mt-4 text-sm text-amber-400">
          {ar ? 'اختر تخصصًا واحدًا ودورًا واحدًا على الأقل.' : 'Choose at least one trade and one role.'}
        </div>
      )}
      {st.err && st.cap ? <div className="mt-3 text-sm text-red-400">{String(st.err)}</div> : null}
      {saved ? <div className="mt-3 text-sm text-emerald-400">{ar ? 'تم التأكيد.' : 'Confirmed.'}</div> : null}

      <Button className="mt-4" disabled={busy || !trades.length || !roles.length} onClick={confirm}>
        {busy ? (ar ? 'جارٍ الحفظ…' : 'Saving…')
              : st.confirmed ? (ar ? 'تحديث النطاق' : 'Update my scope')
                             : (ar ? 'تأكيد نطاق عملي' : 'Confirm my scope')}
      </Button>
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
    try { const tk = localStorage.getItem('qd-sup-token'); if (tk) { setToken(tk); setPhase('app'); claimIfInvited(tk); } } catch (_e) {}
    SB.auth.getSession().then(({ data }) => { const ss = data.session; if (ss && ss.access_token) { setToken(ss.access_token); try { localStorage.setItem('qd-sup-token', ss.access_token); if (ss.refresh_token) localStorage.setItem('qd-sup-refresh', ss.refresh_token); } catch (_e) {} setPhase('app'); claimIfInvited(ss.access_token); } }).catch(() => {});
  }, []);
  const onAuth = (access, refresh) => { try { localStorage.setItem('qd-sup-token', access || ''); if (refresh) localStorage.setItem('qd-sup-refresh', refresh); } catch (_e) {} setToken(access || ''); setPhase('app'); if (access) { try { SB.auth.setSession({ access_token: access, refresh_token: refresh || '' }).catch(() => {}); } catch (_e) {} claimIfInvited(access); } };
  const doSignOut = () => { try { localStorage.removeItem('qd-sup-token'); localStorage.removeItem('qd-sup-refresh'); } catch (_e) {} setToken(''); setPhase('login'); try { SB.auth.signOut().catch(() => {}); } catch (_e) {} };
  const rtl = lang === 'ar';
  if (!mounted) return null;
  return (
    <div dir={rtl ? 'rtl' : 'ltr'} className="osx min-h-screen bg-background text-foreground" style={{ fontFamily: 'Inter, system-ui, sans-serif' }}>
      <header className="qd-topbar sticky top-0 z-10 flex items-center justify-between px-5 py-3 bg-card/70 backdrop-blur-xl border-b border-border">
        <a className="group flex items-center gap-2.5 text-[15px] font-extrabold text-foreground no-underline" href="/">
          <BrandMark className="h-7 w-7 transition-transform duration-500 group-hover:rotate-[8deg]" />
          <span>QuotesDone <span className="font-mono text-[10.5px] font-semibold uppercase tracking-[0.18em] text-primary align-middle">{t(lang, 'brand_sub')}</span></span>
        </a>
        <div className="flex gap-2 items-center">
          <Button variant="outline" size="sm" onClick={() => { try { localStorage.setItem('qd-lang', lang === 'ar' ? 'en' : 'ar'); } catch (_e) {} if (typeof location !== 'undefined') location.reload(); }}>{lang === 'ar' ? 'EN' : 'عربي'}</Button>
          <Button asChild variant="outline" size="sm"><a href="/">{t(lang, 'home')}</a></Button>
          {phase === 'app' && <Button variant="outline" size="sm" onClick={doSignOut}>{t(lang, 'signout')}</Button>}
        </div>
      </header>
      {!mounted ? <div className={S.center}>{t(lang, 'loading')}</div> : (<>
        {/* An invited supplier is told whose listing this is, before anything else on the page. */}
        {phase === 'login' && invite && <InviteBanner invite={invite} lang={lang} onStart={() => { try { document.getElementById('qd-supplier-signin')?.scrollIntoView({ behavior: 'smooth', block: 'center' }); } catch (_e) {} }} />}
        {/* §1 — the supplier meets the product before the sign-in box, not after it. */}
        {phase === 'login' && <SupplierEntryHero lang={lang} onStart={() => { try { document.getElementById('qd-supplier-signin')?.scrollIntoView({ behavior: 'smooth', block: 'center' }); } catch (_e) {} }} />}
        {phase === 'login' && <div id="qd-supplier-signin"><Login onAuth={onAuth} lang={lang} startMode={invite && invite.claimable ? 'signup' : 'signin'} /></div>}
        {phase === 'app' && <Dashboard token={token} lang={lang} />}
      </>)}
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
    let j; try { j = await call('login_otp', { action: 'send', user_kind: 'supplier', identifier: v, allow_signup: isSignup }); } catch (_e) { setBusy(false); setMsg(t(lang, 'err_code_send')); return; } setBusy(false); if (j && j.ok) { setIdent(j.identifier || v); setStep('code'); } else setMsg((j && j.error) || t(lang, 'err_code_send')); };
  const verify = async () => { if (!code.trim()) return; setBusy(true); setMsg(''); let j; try { j = await call('login_otp', { action: 'verify', user_kind: 'supplier', identifier: ident, code: code.trim() }); } catch (_e) { setBusy(false); setMsg(t(lang, 'err_incorrect')); return; } if (!j || !j.ok || !j.access_token) { setBusy(false); setMsg((j && j.error) || t(lang, 'err_incorrect')); return; } setBusy(false); onAuth(j.access_token, j.refresh_token); };
  const swap = (m) => { swapped.current = true; setMode(m); setStep('id'); setMsg(''); setCode(''); };
  return (
    <div className={S.center}><Card className="qd-login qd-panel w-full max-w-[410px] p-6 sm:p-7">
      <div className="mb-5 flex flex-col items-center text-center">
        <span className="qd-brandbadge mb-4 grid h-12 w-12 place-items-center rounded-2xl"><BrandMark className="h-6 w-6" /></span>
        <div className={cn(S.h1, 'qd-grad-text')}>{isSignup ? t(lang, 'register_title') : t(lang, 'welcome_back')}</div>
        <div className={cn(S.sub, 'mx-auto mt-2')}>{isSignup ? t(lang, 'signup_sub') : t(lang, 'signin_sub')}</div>
      </div>
      <div className={cn(S.tabsWrap, 'mb-4 flex w-full')}><button className={cn(S.tab, 'flex-1', !isSignup && S.tabOn)} onClick={() => swap('signin')}>{t(lang, 'tab_signin')}</button><button className={cn(S.tab, 'flex-1', isSignup && S.tabOn)} onClick={() => swap('signup')}>{t(lang, 'tab_signup')}</button></div>
      {step === 'id' ? (<>
        <Input className="mt-3" placeholder={isSignup ? t(lang, 'work_email') : t(lang, 'email_or_mobile')} value={id} onChange={(e) => setId(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && send()} />
        <Button className="w-full mt-3" disabled={busy} onClick={send}>{busy ? t(lang, 'sending') : (isSignup ? t(lang, 'create_my_account') : t(lang, 'send_code'))}</Button>
      </>) : (<>
        <Input className="mt-3" placeholder={t(lang, 'code_placeholder')} value={code} onChange={(e) => setCode(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && verify()} />
        <div className={S.hint}>{t(lang, 'junk_note')}</div>
        <Button className="w-full mt-3" disabled={busy} onClick={verify}>{busy ? t(lang, 'verifying') : (isSignup ? t(lang, 'verify_continue') : t(lang, 'verify_signin'))}</Button>
        <Button variant="link" className="mt-2 px-0 h-auto" onClick={() => { setStep('id'); setCode(''); setMsg(''); }}>{t(lang, 'use_diff')}</Button>
      </>)}
      {msg && <div className={S.err}>{msg}</div>}
    </Card></div>
  );
}
function Dashboard({ token, lang }) {
  const [ov, setOv] = useState(null); const [tab, setTab] = useState('overview'); const [err, setErr] = useState('');
  const load = async () => { const j = await call('supplier_portal', { action: 'overview' }, token); if (j && j.ok) setOv(j); else setErr((j && (j.error || j.hint)) || 'load_err'); };
  useEffect(() => { load(); }, [token]);
  if (err === 'no_company') return <Onboarding token={token} lang={lang} onDone={() => { setErr(''); load(); }} />;
  if (err) return <div className={S.center}><Card className="qd-panel max-w-[460px] p-5"><div className={S.h2}>{t(lang, 'something_wrong')}</div><div className={S.sub}>{err === 'load_err' ? t(lang, 'err_generic') : err}</div></Card></div>;
  if (!ov) return <div className={S.center}>{t(lang, 'loading_dash')}</div>;
  const s = ov.stats || {}; const pp = s.price_positioning || {};
  const TAB = { overview: t(lang, 't_overview'), rfqs: t(lang, 't_rfqs'), documents: t(lang, 't_documents'), projects: t(lang, 't_projects'), messages: t(lang, 't_messages'), billing: t(lang, 't_billing'), profile: lang === 'ar' ? 'الملف' : 'Profile', twin: lang === 'ar' ? 'التوأم الرقمي' : 'Digital Twin', products: lang === 'ar' ? 'المنتجات' : 'Products', assistant: lang === 'ar' ? 'المساعد' : 'AI Assistant', environment: lang === 'ar' ? 'البيئة ثلاثية الأبعاد' : '3D Environment', network: lang === 'ar' ? 'خريطة الشبكة' : 'Network Map', market: lang === 'ar' ? 'ذكاء السوق' : 'Market', workspaces: lang === 'ar' ? 'مساحات العمل' : 'Workspaces', onboarding: lang === 'ar' ? 'إعداد الملف' : 'Set up my profile', board: lang === 'ar' ? 'لوحة الرؤى' : 'Insight Board', recommended: lang === 'ar' ? 'موصى به لك' : 'Recommended', ranking: lang === 'ar' ? 'التصنيف' : 'Supplier Score', negotiation: lang === 'ar' ? 'مساعد التفاوض' : 'Negotiation AI', certifications: lang === 'ar' ? 'الشهادات' : 'Certifications', quote: lang === 'ar' ? 'منشئ عروض الأسعار' : 'Quote Builder', inventory: lang === 'ar' ? 'المخزون' : 'Inventory', settings: lang === 'ar' ? 'الإعدادات' : 'Settings', scope: lang === 'ar' ? 'نطاق عملي' : 'My scope' };
  // 'profile' is new. ProfileForm previously rendered only from Onboarding, which shows solely
  // while supplier_portal returns no_company — so the moment a supplier registered, every field
  // in it became permanently unreachable: contact name, phone, products, services, description,
  // TRN, EGR, licence number and authority. They could not correct a typo in their own company
  // details, and since matching scores on products/services/categories, they could not improve
  // their own discoverability either.
  // 'twin' is row #5 §3/§4/§6/§13 — the digital twin, health panel and company intelligence. It
  // lives in its own component file (portal/supplier/SupplierTwin.tsx) rather than here: this file
  // is already 81,811 stripped characters holding six unrelated features, and that size is what
  // made three separate scorer refutation rounds necessary.
  const TABS = ['overview', 'scope', 'board', 'recommended', 'quote', 'ranking', 'negotiation', 'certifications', 'onboarding', 'twin', 'environment', 'network', 'market', 'workspaces', 'assistant', 'products', 'inventory', 'rfqs', 'documents', 'profile', 'projects', 'messages', 'settings', 'billing'];
  return (
    <div className={S.wrap}>
      <div className="flex justify-between items-center flex-wrap gap-3 mb-4">
        <div><div className="text-[22px] font-extrabold text-foreground">{ov.supplier.company_name}</div><div className="flex items-center gap-2 mt-1.5 flex-wrap">{(() => {
            // AUDIT 6.5(d): action_required is NOT pending. Pending means someone will look at it;
            // action_required means a clock is running that ends in rejection unless the supplier
            // acts. Showing both as "Pending" is why a supplier could be auto-rejected on day 14
            // having been told, on this screen, that everything was fine.
            const st = ov.supplier.approval_status;
            if (st === 'action_required') {
              const due = ov.supplier.exception_due_at ? new Date(ov.supplier.exception_due_at) : null;
              const days = due ? Math.ceil((due.getTime() - Date.now()) / 864e5) : null;
              const when = days === null ? '' : (days <= 0 ? ' \u00b7 ' + t(lang, 'ar_overdue') : ' \u00b7 ' + days + ' ' + t(lang, 'ar_days_left'));
              return <Badge variant="destructive">{t(lang, 'action_required') + when}</Badge>;
            }
            return <Badge variant={st === 'approved' ? 'ok' : 'warn'} className="capitalize">{st === 'approved' ? t(lang, 'approved') : t(lang, 'pending')}</Badge>;
          })()}{ov.supplier.approval_status === 'action_required' && ov.supplier.licence_gate_reason
            ? <span className="text-[13px] text-destructive font-medium basis-full">{t(lang, 'ar_why') + ': ' + ov.supplier.licence_gate_reason}</span>
            : null}{ov.supplier.license_expiry ? (() => { const days = Math.round((new Date(ov.supplier.license_expiry) - new Date()) / 864e5); const v = days < 0 ? 'destructive' : days <= 30 ? 'warn' : 'secondary'; return <Badge variant={v}>{(days < 0 ? t(lang, 'lic_expired') : t(lang, 'lic_expires')) + ' · ' + ov.supplier.license_expiry}</Badge>; })() : null}</div></div>
        <div className={S.tabsWrap}>{TABS.map((k) => <button key={k} className={cn(S.tab, tab === k && S.tabOn)} onClick={() => setTab(k)}>{k === 'rfqs' ? TAB.rfqs + (ov.active_matches ? ' (' + ov.active_matches + ')' : '') : TAB[k]}</button>)}</div>
      </div>
      {tab === 'twin' && <SupplierTwin token={token} lang={lang} />}
      {tab === 'products' && <ProductIntelligence token={token} lang={lang} />}
      {tab === 'environment' && <SupplierEnvironment token={token} lang={lang} />}
      {/* §19's supplier density map and §23's knowledge graph are the same subject — the shape of
          the market around this company — so they share a destination rather than splitting the
          navigation. The map answers "where", the graph answers "next to what". */}
      {tab === 'network' && <div className="space-y-4"><SupplierNetworkMap token={token} lang={lang} /><SupplierKnowledgeGraph token={token} lang={lang} /></div>}
      {tab === 'market' && <MarketIntelligence token={token} lang={lang} />}
      <SupplierCommandPalette tabs={TABS} labels={TAB} onGo={setTab} lang={lang} />
      {tab === 'board' && <SupplierInsightBoard token={token} lang={lang} />}
      {tab === 'recommended' && <SupplierOpportunities token={token} lang={lang} />}
      {tab === 'ranking' && <SupplierTier token={token} lang={lang} />}
      {tab === 'negotiation' && <SupplierNegotiation token={token} lang={lang} />}
      {tab === 'certifications' && <SupplierCertifications token={token} lang={lang} goTo={setTab} />}
      {tab === 'onboarding' && <SupplierOnboarding token={token} lang={lang} goTo={setTab} />}
      {tab === 'quote' && <SupplierQuoteBuilder token={token} lang={lang} />}
      {tab === 'inventory' && <SupplierInventory token={token} lang={lang} goTo={setTab} />}
      {tab === 'settings' && <SupplierSettings token={token} lang={lang} />}
      {tab === 'workspaces' && <CollaborationWorkspace token={token} lang={lang} goTo={setTab} />}
      {tab === 'assistant' && <SupplierAdvisor token={token} lang={lang} goTo={setTab} />}
      {tab === 'scope' && <CapabilityConfirmPanel token={token} lang={lang} />}
      {tab === 'billing' && <BillingPanel token={token} lang={lang} />}
      {tab === 'profile' && <ProfilePanel token={token} lang={lang} onSaved={load} />}
      {tab === 'overview' && <>
        {/* Severity reads as a leading indicator dot rather than a thick side-stripe, and these are
            real buttons — they were clickable divs, so keyboard users could not reach them at all. */}
        {!!(ov.alerts || []).length && <div className="flex flex-col gap-2 mb-4">{ov.alerts.map((a, i) => <button key={i} type="button" className="qd-panel qd-panel-hover w-full text-start px-4 py-3.5 cursor-pointer flex items-start gap-3" onClick={() => setTab(a.action === 'documents' ? 'documents' : 'rfqs')}><span aria-hidden className={cn('mt-[7px] h-2 w-2 rounded-full shrink-0', a.severity === 'high' ? 'bg-red-400' : a.severity === 'medium' ? 'bg-amber-300' : 'bg-primary')} /><span className="flex flex-col gap-0.5 min-w-0"><b className="text-[13.5px] text-white">{a.title}</b><span className="text-muted-foreground text-xs leading-[1.6]">{a.detail}</span></span></button>)}</div>}
        <EligibilityPanel token={token} lang={lang} goProfile={() => setTab('profile')} goDocs={() => setTab('documents')} goScope={() => setTab('scope')} />
        {/* §4's assistant has to name a concrete gap AND quantify what closing it is worth. The
            counts come from fn_supplier_document_impact, so "6 more opportunities" is a count of
            open enquiries in this supplier's trade rather than the spec's illustrative figure. */}
        <div className="mb-4"><SupplierDocumentImpact token={token} lang={lang} goTo={setTab} /></div>
        <div className="grid grid-cols-2 md:grid-cols-6 gap-2.5 mb-4">
          <Kpi label={t(lang, 'k_quotes_sent')} v={s.quotes_total ?? 0} />
          <Kpi label={t(lang, 'k_reveals')} v={s.reveals ?? 0} />
          <Kpi label={t(lang, 'k_hired')} v={s.hired ?? 0} />
          <Kpi label={t(lang, 'k_win')} v={s.win_ratio != null ? s.win_ratio + '%' : '—'} />
          <Kpi label={t(lang, 'k_rating')} v={s.rating != null ? s.rating : '—'} sub={s.rating_percentile != null ? (lang === 'ar' ? ('ضمن أفضل ' + Math.max(1, 100 - s.rating_percentile) + '% بالقطاع') : ('Top ' + Math.max(1, 100 - s.rating_percentile) + '% in sector')) : ''} />
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
            {/* The promise "we never show competitor prices" is stated everywhere and shown nowhere.
                The redaction bar is the brand's own primitive for a withheld value, so here it makes
                the guarantee visible: those prices exist, we hold them, and you cannot see them. */}
            {pp.competitive_rfqs ? (
              <div className="mt-3.5 flex items-center gap-2 flex-wrap">
                <span className="text-[11px] font-semibold text-muted-foreground/80">{lang === 'ar' ? 'أسعار المنافسين' : 'Competitor quotes'}</span>
                <span aria-hidden className="redact redact-bar" style={{ width: 52 }} />
                <span aria-hidden className="redact redact-bar" style={{ width: 36 }} />
                <span aria-hidden className="redact redact-bar" style={{ width: 44 }} />
                <span className="sr-only">{lang === 'ar' ? 'أسعار المنافسين محجوبة دائمًا' : 'Competitor prices are always withheld'}</span>
              </div>
            ) : null}
            <div className={cn(S.sub, 'mt-2.5')}>{pp.competitive_rfqs ? ((lang === 'ar' ? ('كنت الأقل سعرًا في ' + (pp.times_lowest || 0) + ' من ' + pp.competitive_rfqs + ' طلب تنافسي (' + (pp.lowest_rate || 0) + '%). في المتوسط عرضك ' + (pp.avg_pct_vs_average >= 0 ? '+' : '') + (pp.avg_pct_vs_average ?? 0) + '% مقابل متوسط السوق و' + (pp.avg_pct_above_lowest ?? 0) + '% فوق أدنى عرض.') : ('You were the lowest bid on ' + (pp.times_lowest || 0) + ' of ' + pp.competitive_rfqs + ' competitive RFQs (' + (pp.lowest_rate || 0) + '%). On average your quote is ' + (pp.avg_pct_vs_average >= 0 ? '+' : '') + (pp.avg_pct_vs_average ?? 0) + '% vs the market average and ' + (pp.avg_pct_above_lowest ?? 0) + '% above the lowest quote.'))) : t(lang, 'pp_fallback')}</div>
          </Card>
          <Card className="qd-panel p-5">
            <div className={S.h2}>{t(lang, 'last12')} <span className={S.anon}>{t(lang, 'quotes_reveals')}</span></div>
            <Spark hist={s.history_12m} lang={lang} />
          </Card>
        </div>
      </>}
      {tab === 'rfqs' && <Rfqs token={token} lang={lang} />}
      {tab === 'documents' && <Documents token={token} lang={lang} />}
      {tab === 'projects' && <Projects token={token} lang={lang} />}
      {tab === 'messages' && <Messages token={token} lang={lang} />}
    </div>
  );
}
// "Why am I not getting matched?"
//
// Across 20,465 supplier records exactly one is currently eligible, and inquiry_matches has never
// had a row — so the single most useful thing this dashboard can tell a supplier is what is
// actually standing between them and a request. Every item comes from the server, which evaluates
// the real clauses in match_suppliers_kw rather than a guess at them, and separates what BLOCKS
// matching from what only IMPROVES ranking. Conflating those would be worse than silence: a
// supplier who fixes five cosmetic things and still gets nothing stops trusting the product.
function EligibilityPanel({ token, lang, goProfile, goDocs, goScope }) {
  const [e, setE] = useState(null);
  const ar = lang === 'ar';
  useEffect(() => { call('supplier_portal', { action: 'eligibility' }, token).then((j) => { if (j && j.ok) setE(j); }); }, [token]);
  if (!e) return null;
  const blocking = e.blocking || []; const improving = e.improving || [];
  const go = (fix) => { if (fix === 'documents') goDocs(); else if (fix === 'profile') goProfile(); else if (fix === 'scope') goScope(); };
  const Row = ({ it, tone }) => (
    <li className="flex items-start gap-2.5">
      <span className={cn('mt-[7px] h-1.5 w-1.5 rounded-full shrink-0', tone === 'block' ? 'bg-red-500' : 'bg-primary')} />
      <div className="flex-1">
        <div className="text-[13.5px] font-semibold text-foreground">{it.title}</div>
        <div className={S.sub}>{it.detail}</div>
        {(it.fix === 'profile' || it.fix === 'documents' || it.fix === 'scope') && (
          <button className="mt-1 text-[12.5px] font-semibold text-primary underline-offset-2 hover:underline" onClick={() => go(it.fix)}>
            {it.fix === 'documents' ? (ar ? 'إلى المستندات ←' : 'Go to Documents →')
              : it.fix === 'scope' ? (ar ? 'تأكيد نطاق عملي ←' : 'Confirm my scope →')
              : (ar ? 'إلى الملف ←' : 'Go to Profile →')}
          </button>
        )}
      </div>
    </li>
  );
  return (
    <Card className="qd-panel p-5 mb-4">
      <div className="flex justify-between items-start gap-3 flex-wrap">
        <div>
          <div className={S.h2}>{ar ? 'وصولك إلى الطلبات' : 'Your reach'}</div>
          <div className={cn(S.sub, 'mt-1 max-w-[62ch]')}>{e.note}</div>
        </div>
        <Badge variant={e.eligible ? 'ok' : 'destructive'} className="shrink-0">
          {e.eligible ? (ar ? 'مؤهّل للمطابقة' : 'Eligible for matching') : (ar ? 'غير مؤهّل حاليًا' : 'Not currently eligible')}
        </Badge>
      </div>
      <div className="flex gap-5 mt-3 flex-wrap">
        <div><div className="text-[19px] font-extrabold text-foreground leading-none">{e.reach?.matched_requests ?? 0}</div><div className={S.sub}>{ar ? 'طلبات مطابقة' : 'requests matched'}</div></div>
        <div><div className="text-[19px] font-extrabold text-foreground leading-none">{e.reach?.quotes_sent ?? 0}</div><div className={S.sub}>{ar ? 'عروض مُرسلة' : 'quotes sent'}</div></div>
        <div><div className="text-[19px] font-extrabold text-foreground leading-none">{e.reach?.shortlist_size ?? 8}</div><div className={S.sub}>{ar ? 'حجم القائمة المختصرة' : 'shortlist size'}</div></div>
      </div>
      {!!blocking.length && <div className="mt-4">
        <div className="text-[12.5px] font-bold text-red-400">{ar ? 'يمنع وصول الطلبات إليك' : 'Stopping requests reaching you'}</div>
        <ul className="mt-2 flex flex-col gap-2.5">{blocking.map((it, i) => <Row key={i} it={it} tone="block" />)}</ul>
      </div>}
      {!!improving.length && <div className="mt-4">
        <div className="text-[12.5px] font-bold text-muted-foreground">{ar ? 'يرفع ترتيبك' : 'Improves your ranking'}</div>
        <ul className="mt-2 flex flex-col gap-2.5">{improving.slice(0, 6).map((it, i) => <Row key={i} it={it} tone="improve" />)}</ul>
      </div>}
      {!blocking.length && !improving.length && <div className={cn(S.sub, 'mt-3')}>
        {ar ? 'ملفك مكتمل. ستصلك الطلبات المطابقة فور ورودها.' : 'Your profile is complete. Matching requests will reach you as they come in.'}
      </div>}
    </Card>
  );
}
// Label above figure, not below: the eye lands on the number, and the label is
// already read by then. Figures are tabular so a row of KPIs aligns on the digit.
function Kpi({ label, v, sub }) { return <Card className="qd-panel qd-panel-hover p-3.5"><div className="text-[11px] font-semibold text-muted-foreground/90">{label}</div><div className={cn(S.figure, 'text-[23px] font-extrabold mt-1.5')}>{v}</div>{sub ? <div className="text-[10.5px] text-primary mt-1.5 font-semibold">{sub}</div> : null}</Card>; }
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
                  <span className="text-[13px] font-bold text-foreground tabular-nums">{st.v}{c != null && <span className="text-muted-foreground font-semibold ml-1.5 text-[11.5px]">{c}%</span>}</span>
                </div>
                <div className="mt-1 h-2 rounded-full bg-secondary/50 overflow-hidden">
                  <div className="h-full rounded-full bg-primary transition-[width] duration-700 motion-reduce:transition-none"
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
function Spark({ hist, lang }) { if (!hist || !hist.length) return <div className={S.sub}>{t(lang, 'no_history')}</div>; const max = Math.max(1, ...hist.map((h) => Math.max(h.quotes || 0, h.reveals || 0))); return <div className="flex gap-1.5 items-end mt-3.5 h-[70px]">{hist.map((h, i) => <div key={i} className="flex-1 flex flex-col items-center" title={h.month + ': ' + h.quotes + ' quotes / ' + h.reveals + ' reveals'}><div className="flex gap-0.5 items-end h-[50px]"><div className="w-[7px] rounded-t-sm bg-primary" style={{ height: Math.max(2, Math.round((h.quotes / max) * 46)) }} /><div className="w-[7px] rounded-t-sm bg-primary/40" style={{ height: Math.max(2, Math.round((h.reveals / max) * 46)) }} /></div><div className="text-[9px] text-muted-foreground mt-1">{String(h.month).split(' ')[0]}</div></div>)}</div>; }
function Rfqs({ token, lang }) {
  const [data, setData] = useState(null); const [open, setOpen] = useState(null);
  const reload = () => call('supplier_api', { action: 'inbox' }, token).then((j) => setData(j));
  useEffect(() => { reload(); }, [token]);
  if (!data) return <Card className="qd-panel p-5">{t(lang, 'loading_rfqs')}</Card>;
  if (data.error) return <Card className="qd-panel p-5">{data.error}</Card>;
  const list = data.inquiries || [];
  if (!list.length) return <Card className="qd-panel p-5"><div className={S.h2}>{t(lang, 'no_rfqs_h')}</div><div className={S.sub}>{t(lang, 'no_rfqs_sub')}</div></Card>;
  return <div className={S.list}>{list.map((i) => <Card key={i.id} className="p-5">
    <div className="flex justify-between items-center gap-2.5"><div><b>{i.category || t(lang, 'request_w')}</b> · {i.emirate || ''}{i.you_won ? <span className="text-primary font-bold">{t(lang, 'you_won')}</span> : i.concluded ? <span className="text-muted-foreground">{t(lang, 'concluded')}</span> : ''}</div>{i.quote ? <span className="text-primary font-bold text-[13px]">{t(lang, 'quoted')}{aed(i.quote.quote_amount)}</span> : <Button size="sm" onClick={() => setOpen(open === i.id ? null : i.id)}>{open === i.id ? t(lang, 'close') : t(lang, 'quote')}</Button>}</div>
    {i.summary && <div className={cn(S.sub, 'mt-1.5')}>{i.summary}</div>}
    {i.boq && i.boq.boq && <div className={cn(S.sub, 'mt-1.5')}>{t(lang, 'boq_prefix')}{i.boq.boq.length} {t(lang, 'boq_items')}{i.boq_confidence ? ' · ' + i.boq_confidence + t(lang, 'confidence') : ''}</div>}
    {(i.drawing_pages || []).length ? <div className={cn(S.sub, 'mt-1.5')}>{i.drawing_pages.map((u, k) => <a key={k} href={u} target="_blank" rel="noopener" className="text-primary font-semibold mr-2.5">{t(lang, 'drawing_p')}{k + 1}</a>)}</div> : null}
    {!i.concluded && !i.quote && <div className="mt-1.5"><button className="text-[12px] text-muted-foreground underline underline-offset-2 hover:text-primary" onClick={async () => { const note = window.prompt('What is unclear about this request? (optional) — we will ask the customer to add detail.'); if (note === null) return; const j = await call('rfq_flag', { inquiry_id: i.id, note: note || '' }, token); window.alert(j && j.ok ? 'Thanks — we have asked the customer to add more detail.' : ((j && j.error) || 'Could not send. Please try again.')); }}>Scope unclear? Ask the customer to clarify</button></div>}
    {open === i.id && !i.concluded && <QuoteForm inquiry={i} token={token} lang={lang} onDone={() => { setOpen(null); reload(); }} />}
  </Card>)}</div>;
}
function QuoteForm({ inquiry, token, onDone, lang }) {
  const [amount, setAmount] = useState(''); const [lead, setLead] = useState(''); const [notes, setNotes] = useState(''); const [scope, setScope] = useState(''); const [validity, setValidity] = useState(''); const [payment, setPayment] = useState(''); const [warranty, setWarranty] = useState(''); const [items, setItems] = useState([{ description: '', qty: '', unit: '', unit_price: '' }]); const [msg, setMsg] = useState(''); const [busy, setBusy] = useState(false);
  const [reading, setReading] = useState(false); const [prop, setProp] = useState(null); const [orig, setOrig] = useState(null);
  const onFile = async (file) => { if (!file) return; setReading(true); setMsg(''); try { const { images, b64 } = await fileToImages(file); const j = await call('supplier_api', { action: 'extract_quote', inquiry_id: inquiry.id, images, original: { b64, filename: file.name } }, token); if (j && j.ok && j.proposal) { const pr = j.proposal; setProp(pr); setOrig({ path: j.original_file_path, name: j.original_file_name }); const amt = pr.total != null ? pr.total : (pr.amount != null ? pr.amount : (pr.grand_total != null ? pr.grand_total : '')); if (amt !== '' && amt != null) setAmount(String(amt)); if (pr.lead_time) setLead(pr.lead_time); if (pr.scope || pr.description_anonymized) setScope(pr.scope || pr.description_anonymized); if (pr.notes) setNotes(pr.notes); setMsg(t(lang, 'read_quote_pre') + (pr.line_items ? ' — ' + pr.line_items.length + ' ' + t(lang, 'line_items') : '') + t(lang, 'read_quote_post')); } else setMsg((j && j.error) || t(lang, 'could_not_read')); } catch (_e) { setMsg(t(lang, 'could_not_read')); } setReading(false); };
  const [chk, setChk] = useState(null); const [checking, setChecking] = useState(false);
  const buildPayload = () => prop ? { action: 'submit_quote', inquiry_id: inquiry.id, amount: Number(amount), lead_time: lead, notes, scope, conditions: prop.conditions || '', exclusions: prop.exclusions || '', validity: validity || prop.validity || '', payment_terms: payment || prop.payment_terms || '', warranty: warranty || prop.warranty || '', items: prop.line_items || [], masked_terms: prop.masked_terms || null, source: 'upload', original_file_path: orig && orig.path, original_file_name: orig && orig.name } : { action: 'submit_quote', inquiry_id: inquiry.id, amount: Number(amount), lead_time: lead, notes, scope, validity, payment_terms: payment, warranty, items: items.filter((x) => (x.description || '').trim()), source: 'form' };
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
    if (j && j.ok) setChk(j); else setMsg((j && j.error) || t(lang, 'could_not_submit'));
  };
  const submit = async () => {
    if (!(Number(amount) > 0)) { setMsg(t(lang, 'enter_valid_amount')); return; }
    setBusy(true); setMsg('');
    const j = await call('supplier_api', buildPayload(), token);
    setBusy(false);
    if (j && j.ok && j.accepted) onDone();
    else if (j && j.ok) setMsg(j.message || t(lang, 'draft_saved'));
    else setMsg((j && j.error) || t(lang, 'could_not_submit'));
  };
  return <div className="mt-3 border-t border-border pt-3 flex flex-col gap-2.5">
    <div className="flex gap-2.5 flex-wrap items-center"><span className={cn(S.sub, 'font-semibold')}>{t(lang, 'upload_quote')}</span><FilePick lang={lang} accept="image/*,application/pdf" onPick={(fl) => fl && onFile(fl)} />{reading && <span className={S.sub}>{t(lang, 'reading')}</span>}</div>
    <div className="flex gap-2.5"><Input placeholder={t(lang, 'total_aed')} value={amount} onChange={(e) => setAmount(e.target.value)} /><Input placeholder={t(lang, 'lead_time')} value={lead} onChange={(e) => setLead(e.target.value)} /></div>
    <div className="flex gap-2.5"><Input placeholder={lang === 'ar' ? 'صلاحية العرض (مثلاً 30 يومًا)' : 'Quote validity (e.g. 30 days)'} value={validity} onChange={(e) => setValidity(e.target.value)} /><Input placeholder={lang === 'ar' ? 'شروط الدفع (مثلاً 50% مقدمًا)' : 'Payment terms (e.g. 50% advance)'} value={payment} onChange={(e) => setPayment(e.target.value)} /><Input placeholder={lang === 'ar' ? 'الضمان (مثلاً سنة واحدة)' : 'Warranty (e.g. 1 year)'} value={warranty} onChange={(e) => setWarranty(e.target.value)} /></div>
    <div className="mt-1">
      <div className={cn(S.sub, 'mb-1')}>{lang === 'ar' ? 'بنود العرض (الوصف، الكمية، السعر) — يجعل عرضك جاهزًا للإرسال' : 'Quote items (description, qty, price) — makes your quote ready to send'}</div>
      {items.map((it, ix) => (<div key={ix} className="flex gap-1.5 mb-1.5 items-center">
        <Input placeholder={lang === 'ar' ? 'الوصف' : 'Description'} value={it.description} onChange={(e) => setItems(items.map((r, i) => i === ix ? { ...r, description: e.target.value } : r))} />
        <Input style={{ maxWidth: 64 }} placeholder={lang === 'ar' ? 'كمية' : 'Qty'} value={it.qty} onChange={(e) => setItems(items.map((r, i) => i === ix ? { ...r, qty: e.target.value } : r))} />
        <Input style={{ maxWidth: 72 }} placeholder={lang === 'ar' ? 'وحدة' : 'Unit'} value={it.unit} onChange={(e) => setItems(items.map((r, i) => i === ix ? { ...r, unit: e.target.value } : r))} />
        <Input style={{ maxWidth: 96 }} placeholder={lang === 'ar' ? 'سعر الوحدة' : 'Unit price'} value={it.unit_price} onChange={(e) => setItems(items.map((r, i) => i === ix ? { ...r, unit_price: e.target.value } : r))} />
        <Button size="sm" variant="outline" onClick={() => setItems(items.length > 1 ? items.filter((_, i) => i !== ix) : [{ description: '', qty: '', unit: '', unit_price: '' }])}>×</Button>
      </div>))}
      <Button size="sm" variant="outline" onClick={() => setItems([...items, { description: '', qty: '', unit: '', unit_price: '' }])}>{lang === 'ar' ? '+ إضافة بند' : '+ Add item'}</Button>
    </div>
    <textarea className={S.area} placeholder={t(lang, 'scope_work')} value={scope} onChange={(e) => setScope(e.target.value)} rows={2} />
    <textarea className={S.area} placeholder={t(lang, 'notes_customer')} value={notes} onChange={(e) => setNotes(e.target.value)} rows={2} />
    {chk && <QuoteCheck chk={chk} lang={lang} />}
    <div className="flex gap-2 items-center flex-wrap">
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
  const LABEL = {
    line_items: ar ? 'بنود العرض' : 'Itemised lines',
    unit_prices_on_all_items: ar ? 'سعر الوحدة لكل بند' : 'A unit price on every line',
    brand_model_per_item: ar ? 'الماركة والموديل لكل بند' : 'Brand and model on every line',
    specifications: ar ? 'المواصفات' : 'Specifications',
    labour_or_installation: ar ? 'العمالة أو التركيب' : 'Labour or installation',
    warranty: ar ? 'الضمان' : 'Warranty',
    lead_time: ar ? 'مدة التنفيذ' : 'Lead time',
    payment_terms: ar ? 'شروط الدفع' : 'Payment terms',
    exclusions: ar ? 'الاستثناءات' : 'Exclusions',
    validity: ar ? 'مدة صلاحية العرض' : 'Quote validity',
  };
  const missing = Array.isArray(sc.missing) ? sc.missing : [];
  const viaForm = chk.accept_via === 'form_complete' && !chk.submittable;
  return (
    <Card className="qd-panel p-4 mt-1">
      <div className="flex justify-between items-baseline gap-3 flex-wrap">
        <div className="text-[13.5px] font-bold text-foreground">{ar ? 'جاهزية العرض' : 'Quote readiness'}</div>
        <div className="text-[13px] font-bold tabular-nums text-foreground">{pts}<span className="text-muted-foreground font-semibold">/100</span></div>
      </div>
      <div className="mt-1.5 h-2 rounded-full bg-secondary/50 overflow-hidden relative">
        <div className={cn('h-full rounded-full transition-[width] duration-700 motion-reduce:transition-none', pts >= pass ? 'bg-primary' : 'bg-amber-400')}
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
          <span className="mt-[7px] h-1.5 w-1.5 rounded-full bg-amber-400 shrink-0" />
          <span className="text-[13px] text-foreground">{LABEL[m] || m}</span>
        </li>)}
      </ul>}
      {!missing.length && <div className={cn(S.sub, 'mt-2.5')}>{ar ? 'لا ينقص شيء. عرض مكتمل.' : 'Nothing missing — this is a complete quote.'}</div>}
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
    if (failed.length) setErr((lang === 'ar' ? 'تعذّر رفع الملف: ' : 'Upload failed: ') + failed.map((f) => f.reason).join('; '));
    else if (j && j.error) setErr(String(j.error));
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
            ? 'رخصتك التجارية وحدها هي المطلوبة، ويجب أن تبقى سارية لاستمرار استقبال الطلبات. كل ما عدا ذلك اختياري.'
            : 'Only your trade licence is required, and it must stay valid to keep receiving requests. Everything else is optional.'}</div>
        </div>
        <div className="text-right shrink-0">
          <div className="text-[22px] font-extrabold text-foreground leading-none">{sum.on_file ?? 0}<span className="text-muted-foreground text-[15px]">/{sum.total ?? docs.length}</span></div>
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
  { id: 'required', keys: ['license', 'profile', 'catalogs'],
    title: (l) => (l === 'ar' ? 'مطلوب للتحقق' : 'Required to get verified'),
    note: (l) => (l === 'ar'
      ? 'رخصتك التجارية وملفك التعريفي. نقرأ منهما ما تقوم به لنعرف أي الطلبات نرسلها إليك.'
      : 'Your trade licence and company profile. We read these to work out what work to send you.') },
  { id: 'optional', keys: ['insurance', 'iso', 'manufacturer', 'egr'],
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
        <div className={cn(S.sub, 'mt-1')}>{d.hint}</div>
        {/* What is actually on file, by name, so they can tell whether the right file went up. */}
        {!isCat && d.path && <div className={cn(S.sub, 'mt-1.5')}>
          <span className="text-foreground/80">{cleanName(d.name) || (ar ? 'ملف' : 'File')}</span>
          {d.expiry ? <> · {ar ? 'تنتهي ' : 'expires '}{d.expiry}</> : null}
          {d.url ? <> · <a className="text-primary font-semibold underline-offset-2 hover:underline" href={d.url} target="_blank" rel="noopener">{t(lang, 'view')}</a></> : null}
        </div>}
        {isCat && (items.length
          ? <ul className="mt-1.5 flex flex-col gap-1">{items.map((c, i) => <li key={i} className={S.sub}>
              <span className="text-foreground/80">{cleanName(c.name)}</span>
              {c.url ? <> · <a className="text-primary font-semibold underline-offset-2 hover:underline" href={c.url} target="_blank" rel="noopener">{t(lang, 'view')}</a></> : null}
            </li>)}</ul>
          : <div className={cn(S.sub, 'mt-1.5')}>{t(lang, 'not_uploaded')}</div>)}
        {!isCat && !d.path && <div className={cn(S.sub, 'mt-1.5')}>{t(lang, 'not_uploaded')}</div>}
      </div>
      <div className="flex gap-2 items-center flex-wrap shrink-0">
        <FilePick lang={lang} onPick={setFile} />
        {file && <span className={cn(S.sub, 'max-w-[180px] truncate')}>{file.name}</span>}
        {d.has_expiry && <Input type="date" style={{ colorScheme: 'dark' }} className="w-auto" value={exp}
          onChange={(e) => setExp(e.target.value)} aria-label={(ar ? 'تاريخ انتهاء ' : 'Expiry date for ') + label} />}
        <Button size="sm" disabled={busy || !file} onClick={() => onUpload(d.key, file, exp)}>
          {busy ? t(lang, 'uploading') : (d.path && !isCat ? (ar ? 'استبدال' : 'Replace') : t(lang, 'upload'))}
        </Button>
      </div>
    </div>
  </Card>;
}
function Projects({ token, lang }) {
  const [data, setData] = useState(null);
  useEffect(() => { call('supplier_api', { action: 'projects' }, token).then((j) => setData(j)); }, [token]);
  if (!data) return <Card className="qd-panel p-5">{t(lang, 'loading')}</Card>;
  const list = data.projects || [];
  if (!list.length) return <Card className="qd-panel p-5"><div className={S.h2}>{t(lang, 'no_projects_h')}</div><div className={S.sub}>{t(lang, 'no_projects_sub')}</div></Card>;
  return <div className={S.list}>{list.map((p, i) => <Card key={i} className="p-5 flex justify-between items-center gap-3 flex-wrap"><div><b>{p.category || t(lang, 'project_w')}</b> · {p.emirate || ''}<div className={S.sub}>{p.summary || ''}</div></div><div className="text-right"><b>{aed(p.amount)}</b><div className={S.sub}>{p.revealed_at ? ((lang === 'ar' ? 'كُشف بتاريخ ' : 'Revealed ') + new Date(p.revealed_at).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' })) : (p.month || '')}</div></div></Card>)}</div>;
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
    <div className={cn(S.h1, 'mb-1')}>{t(lang, 'setup_title')}</div>
    <div className={cn(S.sub, 'mb-3.5')}>{me ? t(lang, 'setup_sub_profile') : t(lang, 'setup_sub_company')}</div>
    {!me ? <NewCompany token={token} onReady={load} lang={lang} /> : <ProfileForm token={token} me={me} onSaved={onDone} lang={lang} />}
  </div>);
}
function NewCompany({ token, onReady, lang }) {
  const [cname, setCname] = useState(''); const [em, setEm] = useState(''); const [cat, setCat] = useState(''); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const create = async () => { if (cname.trim().length < 2) { setMsg(t(lang, 'enter_company')); return; } setBusy(true); setMsg(''); const j = await call('supplier_api', { action: 'create_company', company_name: cname.trim(), emirate: em || null, category: cat.trim() || null, role: 'supplier' }, token); setBusy(false); if (j && j.ok) onReady(); else setMsg((j && j.error) || t(lang, 'err_generic')); };
  return (<Card className="qd-panel p-5">
    <div className={S.h2}>{t(lang, 'onboard_title')}</div>
    <div className={cn(S.sub, 'mb-2')}>{t(lang, 'onboard_sub')}</div>
    <Input className="mt-3" placeholder={t(lang, 'company_name')} value={cname} onChange={(e) => setCname(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && create()} />
    <select className={S.field} style={{ colorScheme: 'dark', backgroundColor: 'hsl(205 46% 12%)', color: 'hsl(180 25% 94%)' }} value={em} onChange={(e) => setEm(e.target.value)}><option value="" style={{ backgroundColor: '#0C2330', color: '#EAF4F2' }}>{t(lang, 'emirate')}</option>{EMIRATES.map((x) => <option key={x} value={x} style={{ backgroundColor: '#0C2330', color: '#EAF4F2' }}>{x}</option>)}</select>
    <Input className="mt-3" list="qd-sup-cats" placeholder="Your trade / category — e.g. Electrical, AC, Cleaning (type your own if not listed)" value={cat} onChange={(e) => setCat(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && create()} />
    <datalist id="qd-sup-cats">{['Electrical','AC / HVAC','AC Duct Cleaning','Plumbing','Cleaning','Painting','Fit-out / Interior Design','Joinery & Kitchens','Flooring','Tiling & Marble','False Ceiling','Aluminium & Glass','Facilities Management','CCTV & Security','Smart Home','Solar','Signage','Movers','Pest Control','Handyman','Landscaping & Gardening','Curtains & Blinds','Waterproofing','Swimming Pools','Fire & Safety','MEP','Steel & Fabrication','Carpentry','Other'].map((x) => <option key={x} value={x} />)}</datalist>
    <div className={cn(S.sub, 'mt-0.5 mb-2')} style={{ fontSize: 12 }}>Every trade is welcome — if yours isn’t listed, just type it in.</div>
    <Button className="w-full mt-3" disabled={busy} onClick={create}>{busy ? t(lang, 'sending') : t(lang, 'create_company')}</Button>
    {msg && <div className={S.err}>{msg}</div>}
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
  useEffect(() => { call('kyc', { action: 'state' }, token).then((k) => { if (k && k.phone_verified) setPhoneVerified(true); }); }, []);
  const sendSms = async () => { if (!f.phone) { setMsg(t(lang, 'verify_first')); return; } setVbusy(true); setMsg(''); const j = await call('kyc', { action: 'send_sms', phone: f.phone }, token); setVbusy(false); if (j && j.ok) setSmsSent(true); else setMsg((j && j.error) || t(lang, 'could_not_sms')); };
  const verifySms = async () => { setVbusy(true); setMsg(''); const j = await call('kyc', { action: 'verify_sms', phone: f.phone, code: smsCode }, token); setVbusy(false); if (j && j.ok) setPhoneVerified(true); else setMsg((j && j.error) || t(lang, 'wrong_code')); };
  const [uploading, setUploading] = useState(false); const [licNote, setLicNote] = useState(me.license_doc_path ? t(lang, 'lic_on_file') : '');
  const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const set = (k, v) => setF((o) => ({ ...o, [k]: v }));
  const upLicense = async (file) => { if (!file) return; setUploading(true); setLicNote(''); try { const { images, b64, mime } = await fileToImages(file); const j = await call('supplier_api', { action: 'process_docs', license: { original_b64: b64, file_b64: b64, images, filename: file.name, mime } }, token); const ex = (j && j.extracted && j.extracted.license) || null; if (ex) { setF((o) => ({ ...o, trade_license_no: ex.license_number || o.trade_license_no, license_authority: ex.authority || o.license_authority, license_expiry: ex.expiry || o.license_expiry, trn: ex.trn || o.trn })); setLicNote(t(lang, 'read_lic') + (ex.license_number ? ' — ' + ex.license_number : '') + (ex.expiry ? t(lang, 'expires_comma') + ex.expiry : '') + '.'); } else setLicNote(t(lang, 'lic_uploaded')); } catch (_e) { setLicNote(t(lang, 'lic_uploaded_noread')); } setUploading(false); };
  const toggleEm = (e) => setEmirates((a) => a.includes(e) ? a.filter((x) => x !== e) : [...a, e]);
  const save = async () => {
    if (!f.contact_name || !f.phone) { setMsg(t(lang, 'add_contact_phone')); return; }
    if (!f.trade_license_no) { setMsg(t(lang, 'add_license')); return; }
    if (!profileFile && !me.company_profile_doc_path) { setMsg(t(lang, 'add_profile')); return; }
    if (!phoneVerified) { setMsg(t(lang, 'verify_first')); return; }
    if (!terms) { setMsg(t(lang, 'must_accept')); return; }
    setBusy(true); setMsg('');
    try {
      if (profileFile || catalogFiles.length) {
        const prof = profileFile ? { original_b64: await fileToB64(profileFile), filename: profileFile.name, mime: profileFile.type } : undefined;
        const cats = []; for (const cf of catalogFiles.slice(0, 5)) cats.push({ original_b64: await fileToB64(cf), filename: cf.name, mime: cf.type });
        await call('supplier_api', { action: 'process_docs', company_profile: prof, catalogs: cats }, token);
      }
      const payload = { action: 'save_profile', service_emirates: emirates, accept_terms: true, terms_version: 'v2' };
      const strk = ['contact_name', 'signatory_name', 'phone', 'products', 'services', 'description', 'trade_license_no', 'license_authority', 'license_expiry', 'trn', 'egr_number', 'company_type', 'company_size', 'bank_name', 'bank_account_name'];
      for (const k of strk) if (String(f[k] || '').trim()) payload[k] = f[k];
      if (String(f.founded_year || '').trim()) payload.founded_year = Number(f.founded_year);
      const j = await call('supplier_api', payload, token);
      if (!(j && j.ok)) { setBusy(false); setMsg((j && j.error) || t(lang, 'could_not_save')); return; }
      try { await call('kyc', { action: 'accept_terms' }, token); } catch (_e) {}
      try { const sess = await SB.auth.getSession(); const em = sess.data.session && sess.data.session.user && sess.data.session.user.email; if (em) await call('wa_optin_set', { email: em, user_kind: 'supplier', wa_optin: wa }, token); } catch (_e) {}
      setBusy(false); onSaved();
    } catch (_e) { setBusy(false); setMsg(t(lang, 'save_error')); }
  };
  const DateField = ({ label, k }) => (<div style={{ flex: 1, minWidth: 150 }}><div className={S.sub} style={{ fontSize: 11 }}>{label}</div><Input type="date" style={{ colorScheme: 'dark' }} value={f[k] || ''} onChange={(e) => set(k, e.target.value)} /></div>);
  return (<Card className="qd-panel p-5">
    <div className={S.h2}>{t(lang, 'pf_company')}</div>
    <div className={cn(S.sub, 'mb-2')}>{t(lang, 'registering_pre')}<b>{me.company_name}</b>{me.name_corrected_from ? t(lang, 'corrected') : ''}{t(lang, 'registering_post')}</div>
    <div className={cn(S.sub, 'font-semibold mt-1.5')}>{t(lang, 'pf_emirates')}</div>
    <div className="flex gap-2 flex-wrap mt-2">{EMIRATES.map((e) => <button key={e} className={cn(S.chip, emirates.includes(e) && S.chipOn)} onClick={() => toggleEm(e)}>{e}</button>)}</div>

    {/* ── REGISTRATION ASKS FOR FIVE THINGS ───────────────────────────────────────────────────────
        Founder decision, 8 Aug 2026, verbatim: "20 fields form? why? it should be much simpler.
        once someone attach the trade license, we automatically extract most of the information,
        then we need company profile and catalogue, mobile number, email and thats it. anything
        else is optional. of course both email and mobile need to be verified."

        So the registration path is: the licence (which fills the licence number and authority by
        extraction, not by typing), the company profile, the catalogue, a verified mobile and a
        verified e-mail. Everything else this form can capture is REAL and still saved — it has
        simply moved to the Profile tab, where a supplier edits their own details after they are in.
        Nothing was deleted; the questions were moved off the front door.

        The typed licence number and authority stay visible during registration ONLY as a fallback
        for a licence the extractor could not read, which is why they sit behind `!licNote` — once
        extraction has succeeded there is nothing left to type and asking anyway would be the
        twenty-field wall arriving through a different door. */}
    <div className={cn(S.h2, 'mt-4')}>{t(lang, 'h_trade')}</div>
    {!isEdit && <>
      <div className={cn(S.sub, 'mb-1.5')}>{t(lang, 'trade_sub')}</div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5"><FilePick lang={lang} accept="image/*,application/pdf" onPick={(fl) => fl && upLicense(fl)} />{uploading && <span className={S.sub}>{t(lang, 'reading_lic')}</span>}</div>
      {licNote && <div className={cn(S.sub, 'font-semibold')} style={{ color: 'hsl(var(--primary))' }}>{licNote}</div>}
    </>}
    {(isEdit || !licNote) && <div className={S.frow}><Input placeholder={t(lang, 'lic_no')} value={f.trade_license_no} onChange={(e) => set('trade_license_no', e.target.value)} /><Input placeholder={t(lang, 'authority')} value={f.license_authority} onChange={(e) => set('license_authority', e.target.value)} /></div>}

    {/* The establishment card lived here AND in the Documents tab — the same attachment asked for
        twice. It is optional and never gates verification, so it has no place in the registration
        form. Documents is now the single home for it. The egr_number field and its upload handler
        remain in this component and still submit if populated; only the duplicated prompt is gone. */}

    <div className={cn(S.h2, 'mt-4')}>{t(lang, 'pf_contact')}</div>
    {/* E-mail is not asked for. The supplier signed in with it, so the platform already holds it and
        already knows whether it is confirmed — asking again would be a field whose only possible
        answer is the one we have. It is SHOWN with its verification state instead. */}
    <div className={cn(S.sub, 'mb-1.5')}>
      {me.claimed_by || ''}
      {me.owner_email_verified
        ? <b style={{ color: 'hsl(var(--primary))' }}> · {t(lang, 'email_verified')}</b>
        : <b className="text-amber-300"> · {t(lang, 'email_unverified')}</b>}
    </div>
    <div className={S.frow}><Input placeholder={t(lang, 'mobile')} value={f.phone} onChange={(e) => set('phone', e.target.value)} /></div>
    {phoneVerified ? <div className={cn(S.sub, 'font-semibold')} style={{ color: 'hsl(var(--primary))' }}>{t(lang, 'mobile_verified')}</div> : (!smsSent ? <Button variant="link" className="px-0 h-auto mt-1.5" disabled={vbusy} onClick={sendSms}>{vbusy ? t(lang, 'sending') : t(lang, 'verify_my_mobile')}</Button> : <><div className={S.hint}>{t(lang, 'junk_note')}</div><div className={S.frow}><Input placeholder={t(lang, 'sms_code')} value={smsCode} onChange={(e) => setSmsCode(e.target.value)} /><Button size="sm" disabled={vbusy} onClick={verifySms}>{t(lang, 'verify')}</Button></div></>)}

    {/* ── OPTIONAL, AND ONLY ON THE PROFILE TAB ───────────────────────────────────────────────────
        Contact name, signatory, products, services and the description are all optional by the
        founder's decision. They still save through exactly the same payload; they are asked once
        the supplier is inside rather than standing between them and the door. */}
    {isEdit && <>
      <div className={S.frow}><Input placeholder={t(lang, 'contact_name')} value={f.contact_name} onChange={(e) => set('contact_name', e.target.value)} /><Input placeholder={t(lang, 'signatory')} value={f.signatory_name} onChange={(e) => set('signatory_name', e.target.value)} /></div>
      <div className={cn(S.h2, 'mt-4')}>{t(lang, 'h_offer')}</div>
      <Input className="mt-3" placeholder={t(lang, 'products_ph')} value={f.products} onChange={(e) => set('products', e.target.value)} />
      <Input className="mt-3" placeholder={t(lang, 'services_ph')} value={f.services} onChange={(e) => set('services', e.target.value)} />
      <textarea className={S.area} rows={3} placeholder={t(lang, 'desc_ph')} value={f.description} onChange={(e) => set('description', e.target.value)} />
    </>}
    <label className="flex gap-2 items-center mt-3.5 text-[13px] text-muted-foreground"><input type="checkbox" checked={wa} onChange={(e) => setWa(e.target.checked)} /> {t(lang, 'wa_alerts')}</label>
    {!isEdit && <>
      <div className={cn(S.h2, 'mt-4')}>{t(lang, 'h_offer')}</div>
      <div className={cn(S.sub, 'mb-1')}>{t(lang, 'reg_rest_optional')}</div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5"><span className={S.sub}>{t(lang, 'company_profile_pdf')}</span><FilePick lang={lang} accept=".pdf,.jpg,.jpeg,.png" onPick={setProfileFile} />{profileFile && <span className={S.sub}>{profileFile.name}</span>}</div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5"><span className={S.sub}>{t(lang, 'catalogs_ph')}</span><FilePick lang={lang} accept=".pdf,.jpg,.jpeg,.png" multiple onPick={(a) => setCatalogFiles((a || []).slice(0, 5))} />{catalogFiles.length ? <span className={S.sub}>{catalogFiles.length} {t(lang, 'selected')}</span> : null}</div>
    </>}
    {isEdit && <div className={cn(S.sub, 'mt-3 rounded-md border border-border bg-secondary/30 px-3 py-2.5')}>{lang === 'ar' ? 'رخصتك التجارية وملفك التعريفي وكتالوجاتك تُدار من تبويب المستندات — حتى لا يُطلب الملف نفسه في مكانين.' : 'Your trade licence, company profile and catalogues are managed in the Documents tab — so the same file is never asked for in two places.'}</div>}


    <label className="flex gap-2 items-center mt-3.5 text-[13px] text-muted-foreground"><input type="checkbox" checked={terms} onChange={(e) => setTerms(e.target.checked)} /> {t(lang, 'accept_pre')}<a href="/supplier-agreement" target="_blank" rel="noopener" className="text-primary font-semibold">{t(lang, 'terms_link')}</a>{t(lang, 'accept_post')}</label>
    <Button className="w-full mt-3" disabled={busy || uploading} onClick={save}>{busy ? t(lang, 'submitting') : t(lang, 'submit_approval')}</Button>
    {msg && <div className={S.err}>{msg}</div>}
  </Card>);
}

function Messages({ token, lang }) {
  const [threads, setThreads] = useState(null); const [open, setOpen] = useState(null);
  useEffect(() => { call('messages_api', { action: 'threads' }, token).then((j) => setThreads(j.threads || [])); }, []);
  if (!threads) return <Card className="qd-panel p-5">{t(lang, 'loading_msgs')}</Card>;
  if (open) return <Thread token={token} th={open} lang={lang} onBack={() => { setOpen(null); call('messages_api', { action: 'threads' }, token).then((j) => setThreads(j.threads || [])); }} />;
  if (!threads.length) return <Card className="qd-panel p-5"><div className={S.h2}>{t(lang, 'no_convos_h')}</div><div className={S.sub}>{t(lang, 'no_convos_sub')}</div></Card>;
  return <div className={S.list}>{threads.map((it) => <Card key={it.inquiry_id + ':' + it.supplier_id} className="p-5 flex justify-between items-center cursor-pointer gap-3" onClick={() => setOpen(it)}>
    <div><b>{it.counterpart}</b> · {it.subject}<div className={S.sub}>{it.last || t(lang, 'no_messages')}</div></div>
    <div className="text-right">{it.unread ? <span className="inline-block rounded-full bg-primary text-primary-foreground px-2 py-0.5 text-[11px] font-bold">{it.unread}</span> : null}<div className={cn(S.sub, 'capitalize')}>{it.chat_status === 'none' ? t(lang, 'no_chat') : it.chat_status}</div></div>
  </Card>)}</div>;
}
function Thread({ token, th, onBack, lang }) {
  const [data, setData] = useState(null); const [text, setText] = useState(''); const [q, setQ] = useState(''); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const load = () => call('messages_api', { action: 'thread', inquiry_id: th.inquiry_id, supplier_id: th.supplier_id }, token).then(setData);
  useEffect(() => { load(); }, []);
  const send = async () => { if (!text.trim()) return; setBusy(true); setMsg(''); const j = await call('messages_api', { action: 'send', inquiry_id: th.inquiry_id, supplier_id: th.supplier_id, body: text.trim() }, token); setBusy(false); if (j && j.ok) { setText(''); load(); } else setMsg((j && j.warning) || (j && j.error) || t(lang, 'could_not_send')); };
  const requestChat = async () => { if (!q.trim()) return; setBusy(true); setMsg(''); const j = await call('messages_api', { action: 'request_chat', inquiry_id: th.inquiry_id, supplier_id: th.supplier_id, question: q.trim() }, token); setBusy(false); if (j && j.answered) setMsg(t(lang, 'assistant_pre') + j.answer); else if (j && j.requested) setMsg(j.note || t(lang, 'sent_review')); else setMsg((j && (j.note || j.error)) || t(lang, 'sent')); setQ(''); };
  if (!data) return <Card className="qd-panel p-5">{t(lang, 'loading')}</Card>;
  return <Card className="qd-panel p-5">
    <div className="flex justify-between items-center gap-2.5"><div className={S.h2}>{data.counterpart || th.counterpart}</div><Button variant="link" className="px-0 h-auto" onClick={onBack}>{t(lang, 'back')}</Button></div>
    {data.warning && <div className="rounded-md border border-amber-400/30 bg-amber-400/10 text-amber-300 px-3 py-2 text-[11.5px] mb-2.5">{data.warning}</div>}
    {data.chat_status === 'open' ? (<>
      <div className="flex flex-col gap-2 my-2.5 max-h-[420px] overflow-y-auto">{(data.messages || []).map((m) => <div key={m.id} className={cn('max-w-[76%] px-3 py-2 rounded-xl text-[13.5px] leading-snug', m.sender === data.role ? 'self-end bg-primary/80 text-primary-foreground rounded-br-sm' : 'self-start bg-white/8 text-foreground rounded-bl-sm')}>{m.body}</div>)}</div>
      <div className={S.frow}><Input placeholder={t(lang, 'type_message')} value={text} onChange={(e) => setText(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && send()} /><Button size="sm" disabled={busy} onClick={send}>{t(lang, 'send')}</Button></div>
    </>) : (<>
      <div className={cn(S.sub, 'mb-2')}>{data.note || t(lang, 'no_chat_open')}</div>
      <textarea className={S.area} rows={2} placeholder={t(lang, 'ask_placeholder')} value={q} onChange={(e) => setQ(e.target.value)} />
      <div className="mt-2.5"><Button size="sm" disabled={busy} onClick={requestChat}>{t(lang, 'ask_request')}</Button></div>
    </>)}
    {msg && <div className={cn(S.sub, 'mt-2')} style={{ whiteSpace: 'pre-wrap' }}>{msg}</div>}
  </Card>;
}
