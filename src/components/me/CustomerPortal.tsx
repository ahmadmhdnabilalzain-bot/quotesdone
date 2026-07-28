// @ts-nocheck
'use client';
import { useEffect, useState, useRef, useMemo } from 'react';
import { createClient } from '@supabase/supabase-js';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';

const URL = 'https://htdblwldjkcgjvmqkbeh.supabase.co';
const ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh0ZGJsd2xkamtjZ2p2bXFrYmVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA3ODU1NDYsImV4cCI6MjA5NjM2MTU0Nn0.cF9ZR_Qo1YBhLvhTLS8aANlYb6c9rTsuQS6kLxGw_Bo';
const FN = URL + '/functions/v1';
const SB = createClient(URL, ANON, { auth: { persistSession: true, autoRefreshToken: true, storageKey: 'qd-cust-auth' } });
async function call(path, body, token) { const r = await fetch(FN + '/' + path, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) }, body: JSON.stringify(body) }); return r.json(); }
function initLang(){ try{ if(typeof window==='undefined') return 'en'; const ls=localStorage.getItem('qd-lang'); if(ls) return ls; const m=document.cookie.match(/(?:^|; )NEXT_LOCALE=([^;]+)/); if(m && String(m[1]).startsWith('ar')) return 'ar'; }catch(_e){} return 'en'; }
const T = {
  en: { brand_sub:'My Requests', home:'Home', signout:'Sign out', loading:'Loading…', loading_requests:'Loading your requests…',
    tab_signin:'Sign in', tab_signup:'Create account', welcome_back:'Welcome back', create_account_title:'Create your account',
    signup_sub:"Enter your email and we'll set you up instantly. You'll add your name, date of birth and verify your mobile in the next step.",
    signin_sub:'Sign in with the email or mobile you registered with.', email_or_mobile:'Email or mobile', email_address:'Email address',
    create_my_account:'Create my account', send_code:'Send me a code', sending:'Sending…', code_placeholder:'6-digit code',
    verify_continue:'Verify & continue', verify_signin:'Verify & sign in', verifying:'Verifying…', use_diff:'Use a different email/number',
    junk_note:'The code can take a minute — please check your spam/junk folder too.', err_code_send:'Could not send a code.', err_incorrect:'Incorrect code.',
    signup_email_only:"Please sign up with an email address — you'll add and verify your mobile in the next step.",
    conflict_supplier:'This email is registered as a supplier. Please use the Supplier portal to sign in.',
    session_expired:'Your session has expired. Please sign in again.', load_failed:"Couldn't load your account. Please retry.", retry:'Retry',
    gate_title:'Complete your account', gate_sub:"A few details to finish signing up. We verify your mobile and email for everyone's security.",
    full_name:'Full name', mobile_ph:'Mobile (05x xxx xxxx)', dob_label:'Date of birth (you must be 18+)', save_details:'Save details', saving:'Saving…',
    verify_mobile:'Verify your mobile', verify_email_h:'Verify your email', verified:'✓ verified', send_sms:'Send SMS code', verify:'Verify',
    send_email_code:'Send email code', enter_mobile_first:'Enter your mobile first.', accept_pre:'I accept the QuotesDone ', terms_link:'Terms & Conditions',
    accept_post:'.', finish_continue:'Finish & continue', finishing:'Finishing…', must_accept:'Please accept the terms.',
    my_requests:'My requests', messages:'Messages', back_requests:'← Back to requests', new_request:'+ New request', close:'Close',
    k_requests:'Requests', k_open:'Open', k_quotes:'Quotes received', k_avg:'Avg quotes/req', k_hired:'Hired', k_spend:'Spend',
    your_requests:'Your requests', no_requests:'No requests yet. ', post_first:'Post your first request', describe_job:' — describe the job in text, voice, a photo, or a drawing.',
    request_sent:'Request sent — matching you with suppliers now.', payment_confirmed:'Payment confirmed — supplier contact unlocked below.',
    payment_pending:'Payment received — we are still confirming it with your bank. This page will unlock the supplier as soon as it clears; you can safely reload in a moment.',
    payment_check_failed:'We could not confirm your payment just now. Your card may still have been charged — do not pay again. Reload this page shortly, or email management@quotesdone.com with this reference: ' },
  ar: { brand_sub:'طلباتي', home:'الرئيسية', signout:'تسجيل الخروج', loading:'جارٍ التحميل…', loading_requests:'جارٍ تحميل طلباتك…',
    tab_signin:'تسجيل الدخول', tab_signup:'إنشاء حساب', welcome_back:'مرحبًا بعودتك', create_account_title:'أنشئ حسابك',
    signup_sub:'أدخل بريدك الإلكتروني وسننشئ حسابك فورًا. ستضيف اسمك وتاريخ ميلادك وتتحقق من رقم جوالك في الخطوة التالية.',
    signin_sub:'سجّل الدخول بالبريد الإلكتروني أو رقم الجوال المسجّل.', email_or_mobile:'البريد الإلكتروني أو الجوال', email_address:'البريد الإلكتروني',
    create_my_account:'إنشاء حسابي', send_code:'أرسل لي رمزًا', sending:'جارٍ الإرسال…', code_placeholder:'رمز من 6 أرقام',
    verify_continue:'تحقّق وتابع', verify_signin:'تحقّق وسجّل الدخول', verifying:'جارٍ التحقق…', use_diff:'استخدم بريدًا أو رقمًا آخر',
    junk_note:'قد يستغرق وصول الرمز دقيقة — يُرجى التحقق من مجلد الرسائل غير المرغوب فيها (Spam) أيضًا.', err_code_send:'تعذّر إرسال الرمز.', err_incorrect:'رمز غير صحيح.',
    signup_email_only:'يُرجى التسجيل باستخدام بريد إلكتروني — ستضيف رقم جوالك وتتحقق منه في الخطوة التالية.',
    conflict_supplier:'هذا البريد مسجّل كمورّد. يُرجى استخدام بوابة المورّدين لتسجيل الدخول.',
    session_expired:'انتهت جلستك. يُرجى تسجيل الدخول من جديد.', load_failed:'تعذّر تحميل حسابك. يُرجى المحاولة مجددًا.', retry:'إعادة المحاولة',
    gate_title:'أكمل حسابك', gate_sub:'بعض التفاصيل لإكمال التسجيل. نتحقق من جوالك وبريدك لأمان الجميع.',
    full_name:'الاسم الكامل', mobile_ph:'الجوال (05x xxx xxxx)', dob_label:'تاريخ الميلاد (يجب أن يكون عمرك 18 عامًا فأكثر)', save_details:'حفظ التفاصيل', saving:'جارٍ الحفظ…',
    verify_mobile:'تحقّق من جوالك', verify_email_h:'تحقّق من بريدك', verified:'✓ تم التحقق', send_sms:'أرسل رمز الرسالة النصية', verify:'تحقّق',
    send_email_code:'أرسل رمز البريد', enter_mobile_first:'أدخل رقم جوالك أولًا.', accept_pre:'أوافق على ', terms_link:'الشروط والأحكام',
    accept_post:' الخاصة بمنصة QuotesDone.', finish_continue:'إنهاء ومتابعة', finishing:'جارٍ الإنهاء…', must_accept:'يُرجى الموافقة على الشروط.',
    my_requests:'طلباتي', messages:'الرسائل', back_requests:'→ العودة إلى الطلبات', new_request:'+ طلب جديد', close:'إغلاق',
    k_requests:'الطلبات', k_open:'المفتوحة', k_quotes:'العروض المستلمة', k_avg:'متوسط العروض/طلب', k_hired:'المُتعاقد معهم', k_spend:'الإنفاق',
    your_requests:'طلباتك', no_requests:'لا توجد طلبات بعد. ', post_first:'انشر طلبك الأول', describe_job:' — صِف العمل نصًا أو صوتًا أو بصورة أو برسم.',
    request_sent:'تم إرسال الطلب — نطابقك مع المورّدين الآن.', payment_confirmed:'تم تأكيد الدفع — تم فتح بيانات تواصل المورّد أدناه.',
    payment_pending:'تم استلام الدفعة — ما زلنا نؤكدها مع البنك. ستُفتح بيانات المورّد فور اكتمال التأكيد؛ يمكنك تحديث الصفحة بعد قليل.',
    payment_check_failed:'تعذّر تأكيد الدفع الآن. قد تكون بطاقتك قد خُصمت بالفعل — لا تدفع مرة أخرى. حدّث الصفحة بعد قليل أو راسلنا على management@quotesdone.com بهذا الرقم المرجعي: ' }
};
const t = (lang, k) => (T[lang] && T[lang][k]) || T.en[k] || k;
const aed = (n) => 'AED ' + Number(n || 0).toLocaleString('en-AE', { maximumFractionDigits: 0 });
// Before a supplier is revealed, customer_api (v37, `ratingBand`) does not send a numeric rating —
// it sends a coarse BAND string: '4.5+' | '4.0-4.5' | '3.5-4.0' | 'below 3.5'. Feeding that to
// Number() yields NaN, which propagated into the value score and rendered a literal "Value NaN/100"
// on every quote card. Bands are resolved here first; a real number is still accepted post-reveal.
const RATING_BANDS = { '4.5+': 4.75, '4.0-4.5': 4.25, '3.5-4.0': 3.75, 'below 3.5': 3.0 };
const ratingScoreOf = (r) => {
  if (r == null) return 60;
  const b = RATING_BANDS[String(r).trim()];
  if (b != null) return Math.round((b / 5) * 100);
  const n = Number(r);
  return Number.isFinite(n) ? Math.round((n / 5) * 100) : 60;
};
const EMIRATES =['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Umm Al Quwain', 'Fujairah'];
const fileB64 = (f) => new Promise((res) => { const rd = new FileReader(); rd.onloadend = () => res(String(rd.result).split(',')[1] || ''); rd.readAsDataURL(f); });

// ── Additional copy for the rebuilt portal. Original keys above are untouched. ──
Object.assign(T.en, {
  nav_overview:'Overview', nav_requests:'Requests', nav_messages:'Messages', nav_account:'Account',
  greet_morning:'Good morning', greet_afternoon:'Good afternoon', greet_evening:'Good evening',
  member_since:'Member since', your_account:'Your account', account_sub:'Your profile, verification status and activity on QuotesDone.',
  activity_12m:'Requests over the last 12 months', no_activity:'No activity yet — your first request will appear here.',
  recent_requests:'Recent requests', view_all:'View all', back:'Back', back_to_requests:'Back to requests',
  overview_sub:'Everything happening across your requests, at a glance.',
  requests_sub:'Every request you have posted, and the quotes they attracted.',
  detail_title:'Request detail', what_suppliers_see:'What suppliers see', what_suppliers_see_sub:'This is the anonymised brief sent to matched suppliers. Your name and contact details are never included.',
  print_brief:'Save as PDF', request_ref:'Reference', posted_on:'Posted', budget_l:'Budget', emirate_l:'Emirate', category_l:'Category', scope_l:'Scope',
  quotes_in:'Quotes received', no_quotes_yet:'No quotes yet', awaiting:'Awaiting supplier quotes',
  edit_window_open:'Editable for {n} more minutes', edit_window_closed:'The 1-hour edit window has closed',
  edit_request:'Edit request', cancel_request:'Cancel request', cancelling:'Cancelling…', save_changes:'Save changes', cancel_edit:'Cancel edit',
  confirm_cancel:'Cancel this request? Suppliers will stop quoting.',
  supplier_profile:'Supplier profile', past_projects:'Recent projects', reveal_first:'Reveal this supplier to see their full profile.',
  view_profile:'View full profile', years_active:'Years active', jobs_won:'Jobs won', win_rate:'Win rate', based_in:'Based in',
  verification:'Verification', email_v:'Email', mobile_v:'Mobile', terms_v:'Terms accepted', complete_l:'Complete', pending_l:'Pending',
  profile_details:'Profile details', name_l:'Name', email_l:'Email', mobile_l:'Mobile', joined_l:'Joined',
  total_requests:'Total requests', total_quotes:'Quotes received', total_hired:'Suppliers hired', total_spend:'Total spend',
  value_score:'Value', best_value:'Best value', lowest_price:'Lowest price', fastest:'Fastest',
  reveal_cta:'Reveal & contact', reveal_fee_note:'Reveal fee {fee} — refundable if the supplier does not respond within 3 working days.',
  please_wait:'Please wait…', loading_contact:'Loading contact…', hired_badge:'Hired for this project',
  i_hired:'I hired this supplier', request_refund:'Request refund', rate_supplier:'Rate this supplier', rated_l:'Rated',
  download_quotation:'Download their quotation', view_quote_pdf:'View quote (PDF)', preparing:'Preparing…', pdf_failed:'Could not open the PDF',
  empty_requests_title:'No requests yet', empty_requests_sub:'Describe your job in text, voice, a photo or a drawing. We match you with suitable suppliers and keep your identity private until you choose to reveal one.',
  empty_msgs_title:'No messages', empty_msgs_sub:'Messages with suppliers appear here once a conversation starts.',
  step_sent:'Sent', step_quotes:'Quotes in', step_revealed:'Revealed', step_hired:'Hired',
  line_items:'Line items', trades_l:'Trades', drawing_l:'Drawing', combined_project:'Combined project',
  sep_requests:'{n} separate requests to specialist suppliers', guidance_only:'Guidance only — the final decision is yours.',
  shortlisted_badge:'Shortlisted', show_all_quotes:'Show all {n} quotes', show_less:'Show fewer',
  shortlist_note:'Our expert reviewed all {n} quotes and shortlisted {k}. You can still open and reveal any of the others.',
});
Object.assign(T.ar, {
  nav_overview:'نظرة عامة', nav_requests:'الطلبات', nav_messages:'الرسائل', nav_account:'الحساب',
  greet_morning:'صباح الخير', greet_afternoon:'مساء الخير', greet_evening:'مساء الخير',
  member_since:'عضو منذ', your_account:'حسابك', account_sub:'ملفك الشخصي وحالة التحقق ونشاطك على QuotesDone.',
  activity_12m:'الطلبات خلال آخر 12 شهرًا', no_activity:'لا يوجد نشاط بعد — سيظهر طلبك الأول هنا.',
  recent_requests:'أحدث الطلبات', view_all:'عرض الكل', back:'رجوع', back_to_requests:'العودة إلى الطلبات',
  overview_sub:'كل ما يجري في طلباتك في لمحة واحدة.',
  requests_sub:'كل طلب نشرته، والعروض التي وردت عليه.',
  detail_title:'تفاصيل الطلب', what_suppliers_see:'ما يراه المورّدون', what_suppliers_see_sub:'هذا هو الملخّص المجهول المُرسل للمورّدين المطابَقين. لا يتم أبدًا تضمين اسمك أو بيانات تواصلك.',
  print_brief:'حفظ كملف PDF', request_ref:'المرجع', posted_on:'نُشر في', budget_l:'الميزانية', emirate_l:'الإمارة', category_l:'الفئة', scope_l:'النطاق',
  quotes_in:'العروض المستلمة', no_quotes_yet:'لا توجد عروض بعد', awaiting:'بانتظار عروض المورّدين',
  edit_window_open:'قابل للتعديل لمدة {n} دقيقة إضافية', edit_window_closed:'انتهت مهلة التعديل (ساعة واحدة)',
  edit_request:'تعديل الطلب', cancel_request:'إلغاء الطلب', cancelling:'جارٍ الإلغاء…', save_changes:'حفظ التغييرات', cancel_edit:'إلغاء التعديل',
  confirm_cancel:'إلغاء هذا الطلب؟ سيتوقف المورّدون عن تقديم العروض.',
  supplier_profile:'ملف المورّد', past_projects:'أحدث المشاريع', reveal_first:'اكشف هذا المورّد لعرض ملفه الكامل.',
  view_profile:'عرض الملف الكامل', years_active:'سنوات النشاط', jobs_won:'المشاريع المُنجزة', win_rate:'نسبة الفوز', based_in:'المقر',
  verification:'التحقق', email_v:'البريد الإلكتروني', mobile_v:'الجوال', terms_v:'الموافقة على الشروط', complete_l:'مكتمل', pending_l:'قيد الانتظار',
  profile_details:'بيانات الملف الشخصي', name_l:'الاسم', email_l:'البريد الإلكتروني', mobile_l:'الجوال', joined_l:'تاريخ الانضمام',
  total_requests:'إجمالي الطلبات', total_quotes:'العروض المستلمة', total_hired:'المورّدون المتعاقد معهم', total_spend:'إجمالي الإنفاق',
  value_score:'القيمة', best_value:'أفضل قيمة', lowest_price:'أقل سعر', fastest:'الأسرع',
  reveal_cta:'اكشف وتواصل', reveal_fee_note:'رسوم الكشف {fee} — قابلة للاسترداد إذا لم يرد المورّد خلال 3 أيام عمل.',
  please_wait:'يُرجى الانتظار…', loading_contact:'جارٍ تحميل بيانات التواصل…', hired_badge:'المورّد المتعاقد معه لهذا المشروع',
  i_hired:'تعاقدت مع هذا المورّد', request_refund:'طلب استرداد', rate_supplier:'قيّم هذا المورّد', rated_l:'تم التقييم',
  download_quotation:'تحميل عرض السعر الخاص بهم', view_quote_pdf:'عرض السعر (PDF)', preparing:'جارٍ التحضير…', pdf_failed:'تعذّر فتح الملف',
  empty_requests_title:'لا توجد طلبات بعد', empty_requests_sub:'صِف عملك نصًا أو صوتًا أو بصورة أو برسم. نطابقك مع مورّدين مناسبين ونُبقي هويتك خاصة حتى تختار كشف أحدهم.',
  empty_msgs_title:'لا توجد رسائل', empty_msgs_sub:'تظهر المحادثات مع المورّدين هنا بمجرد بدء أي محادثة.',
  step_sent:'أُرسل', step_quotes:'وردت العروض', step_revealed:'تم الكشف', step_hired:'تم التعاقد',
  line_items:'عدد البنود', trades_l:'التخصصات', drawing_l:'الرسم', combined_project:'مشروع متعدد التخصصات',
  sep_requests:'{n} طلبات منفصلة لموردين متخصصين', guidance_only:'إرشادي فقط — القرار النهائي لك.',
  shortlisted_badge:'ضمن القائمة المختصرة', show_all_quotes:'عرض كل العروض ({n})', show_less:'عرض أقل',
  shortlist_note:'راجع خبيرنا جميع العروض ({n}) واختار {k} منها. ولا يزال بإمكانك فتح وكشف أي عرض آخر.',
});
const tf = (lang, k, vars) => { let s = t(lang, k); if (vars) for (const kk of Object.keys(vars)) s = s.split('{' + kk + '}').join(String(vars[kk])); return s; };

function ensurePdfjs() { return new Promise((res, rej) => { if (window.pdfjsLib) return res(window.pdfjsLib); const sc = document.createElement('script'); sc.src = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js'; sc.onload = () => { try { window.pdfjsLib.GlobalWorkerOptions.workerSrc = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js'; } catch (_e) {} res(window.pdfjsLib); }; sc.onerror = rej; document.head.appendChild(sc); });
}
async function fileToImages(file) {
  const b64 = await fileB64(file); const mime = file.type || 'application/octet-stream';
  if (/^image\//.test(mime)) return { images: [{ mime, b64 }], b64, mime };
  if (/pdf/i.test(mime) || /\.pdf$/i.test(file.name)) {
    try {
      const pdfjs = await ensurePdfjs(); const buf = await file.arrayBuffer();
      const doc = await pdfjs.getDocument({ data: buf }).promise; const out = [];
      const n = Math.min(doc.numPages, 8);
      for (let i = 1; i <= n; i++) {
        const page = await doc.getPage(i); const vp = page.getViewport({ scale: 1.7 });
        const cv = document.createElement('canvas'); cv.width = vp.width; cv.height = vp.height;
        await page.render({ canvasContext: cv.getContext('2d'), viewport: vp }).promise;
        out.push({ mime: 'image/jpeg', b64: cv.toDataURL('image/jpeg', 0.82).split(',')[1] });
      }
      return { images: out, b64, mime };
    } catch (_e) { return { images: [], b64, mime }; }
  }
  return { images: [], b64, mime };
}
function encodeWav(samples, rate) {
  const buf = new ArrayBuffer(44 + samples.length * 2); const view = new DataView(buf);
  const w = (o, s) => { for (let i = 0; i < s.length; i++) view.setUint8(o + i, s.charCodeAt(i)); };
  w(0, 'RIFF'); view.setUint32(4, 36 + samples.length * 2, true); w(8, 'WAVE'); w(12, 'fmt ');
  view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true);
  view.setUint32(24, rate, true); view.setUint32(28, rate * 2, true); view.setUint16(32, 2, true);
  view.setUint16(34, 16, true); w(36, 'data'); view.setUint32(40, samples.length * 2, true);
  let o = 44; for (let i = 0; i < samples.length; i++, o += 2) { const s = Math.max(-1, Math.min(1, samples[i])); view.setInt16(o, s < 0 ? s * 0x8000 : s * 0x7fff, true); }
  return new Blob([view], { type: 'audio/wav' });
}

/* ── Design primitives ─────────────────────────────────────────────────────── */
const S = {
  center: 'grid place-items-center min-h-[70vh] p-5',
  h1: 'font-head text-[19px] font-bold tracking-[-.02em] text-foreground',
  h2: 'font-head text-[15px] font-bold tracking-[-.01em] text-foreground',
  sub: 'text-[13px] leading-relaxed text-muted-foreground',
  hint: 'text-xs text-muted-foreground my-2 leading-relaxed',
  err: 'text-[13px] text-red-300 mt-2',
  note: 'rounded-lg border border-primary/35 bg-primary/10 text-primary px-3.5 py-2.5 mb-3.5 text-[13px] font-semibold',
  wrap: 'mx-auto w-full max-w-[1120px] px-4 sm:px-6 pt-7 pb-28',
  frow: 'flex gap-2.5 flex-wrap mt-2.5',
  tabsWrap: 'inline-flex flex-wrap gap-1.5 rounded-xl bg-secondary/40 p-1',
  tab: 'rounded-md px-3.5 py-2 text-[13px] font-semibold text-foreground/85 hover:text-foreground cursor-pointer border-0 bg-transparent transition-colors',
  tabOn: 'bg-primary/15 text-[#6EE7D4]',
  list: 'flex flex-col gap-3',
  field: 'mt-3 flex h-[42px] w-full rounded-md border border-input bg-transparent px-3 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring',
  area: 'mt-3 flex w-full rounded-md border border-input bg-transparent px-3 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring resize-y',
  fileInput: 'text-sm text-muted-foreground file:mr-3 file:rounded-md file:border-0 file:bg-secondary file:px-3 file:py-1.5 file:text-sm file:font-medium file:text-secondary-foreground hover:file:bg-secondary/80',
};

/* Motion: one shared stylesheet, injected once. Every animation degrades to a
   plain crossfade under prefers-reduced-motion, and nothing is *hidden* by
   default — content renders even if the animation never fires (headless, hidden
   tabs, JS off after hydration). */
const MOTION_CSS = `
.qd-rise{animation:qdRise .58s cubic-bezier(.16,1,.3,1) both}
.qd-fade{animation:qdFade .45s cubic-bezier(.16,1,.3,1) both}
@keyframes qdRise{from{opacity:0;transform:translate3d(0,10px,0)}to{opacity:1;transform:none}}
@keyframes qdFade{from{opacity:0}to{opacity:1}}
.qd-lift{transition:transform .26s cubic-bezier(.16,1,.3,1),border-color .26s cubic-bezier(.16,1,.3,1),box-shadow .26s cubic-bezier(.16,1,.3,1)}
.qd-lift:hover{transform:translate3d(0,-2px,0);border-color:rgba(20,184,166,.34);box-shadow:0 18px 44px -28px rgba(0,12,20,.9)}
.qd-bar{transform-origin:bottom;animation:qdBar .7s cubic-bezier(.16,1,.3,1) both}
@keyframes qdBar{from{transform:scaleY(.02);opacity:.35}to{transform:scaleY(1);opacity:1}}
.qd-shimmer{background:linear-gradient(90deg,rgba(110,231,212,.06),rgba(110,231,212,.16),rgba(110,231,212,.06));background-size:200% 100%;animation:qdShim 1.5s linear infinite}
@keyframes qdShim{from{background-position:200% 0}to{background-position:-200% 0}}
.qd-ring{stroke-dasharray:var(--c);stroke-dashoffset:var(--c);animation:qdRing 1.1s cubic-bezier(.16,1,.3,1) forwards}
@keyframes qdRing{to{stroke-dashoffset:var(--o)}}
@media (prefers-reduced-motion: reduce){
  .qd-rise,.qd-fade,.qd-bar,.qd-ring{animation:qdFade .01s linear both}
  .qd-lift{transition:border-color .01s linear}
  .qd-lift:hover{transform:none}
  .qd-shimmer{animation:none}
}
/* Both Save-as-PDF buttons now render server-side through pdf_native, on QuotesDone
   letterhead. What is left here is plain Ctrl+P courtesy: drop the chrome and make
   the document legible on paper. */
@media print{
  .qd-noprint{display:none !important}
  .qd-print,.qd-print *{color:#111 !important;background:transparent !important;border-color:#bbb !important;box-shadow:none !important}
  .qd-print table{border-collapse:collapse;width:100%}
  .qd-print th,.qd-print td{border:1px solid #bbb !important;padding:6px 8px !important;vertical-align:top}
  .qd-print thead{display:table-header-group}
  .qd-print tr,.qd-print li{break-inside:avoid;page-break-inside:avoid}
  .qd-print .qd-scroll{overflow:visible !important}
  .qd-print .qd-minw{min-width:0 !important}
}
`;
function Motion() { return <style dangerouslySetInnerHTML={{ __html: MOTION_CSS }} />; }
const rise = (i = 0) => ({ animationDelay: (i * 55) + 'ms' });
const backArrow = (lang) => (lang === 'ar' ? '→' : '←');
/* Small shared UI atoms */
function Section({ title, sub, right, children, i = 0 }) {
  return (<section className="qd-rise" style={rise(i)}>
    <div className="flex items-end justify-between gap-3 flex-wrap mb-2.5">
      <div><h2 className={S.h2}>{title}</h2>{sub ? <p className={cn(S.sub, 'mt-0.5')}>{sub}</p> : null}</div>
      {right}
    </div>
    {children}
  </section>);
}
function Stat({ label, value, hint, i = 0 }) {
  return (<div className="surface qd-lift qd-rise rounded-xl p-3.5" style={rise(i)}>
    <div className="font-head tabular text-[21px] font-bold leading-none text-foreground">{value}</div>
    <div className="mt-1.5 text-[11.5px] font-medium text-muted-foreground">{label}</div>
    {hint ? <div className="mt-0.5 text-[10.5px] text-muted-foreground">{hint}</div> : null}
  </div>);
}
function Pill({ children, tone = 'muted' }) {
  const tones = { muted:'bg-secondary/50 text-muted-foreground border-border', teal:'bg-primary/12 text-primary border-primary/30', gold:'bg-accent/12 text-accent border-accent/30', red:'bg-red-500/10 text-red-300 border-red-500/30' };
  return <span className={cn('inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-semibold', tones[tone])}>{children}</span>;
}
function Empty({ title, sub, action, icon = '◇' }) {
  return (<div className="surface qd-rise rounded-xl px-5 py-10 text-center">
    <div aria-hidden className="mx-auto mb-3 grid h-11 w-11 place-items-center rounded-full border border-primary/25 bg-primary/8 text-[17px] text-primary">{icon}</div>
    <div className={S.h2}>{title}</div>
    <p className={cn(S.sub, 'mx-auto mt-1.5 max-w-[46ch]')}>{sub}</p>
    {action ? <div className="mt-4">{action}</div> : null}
  </div>);
}
function Skeleton({ rows = 3 }) {
  return (<div className="flex flex-col gap-3" aria-hidden>
    {Array.from({ length: rows }).map((_, i) => <div key={i} className="qd-shimmer h-[86px] rounded-xl border border-border/60" />)}
  </div>);
}
function Steps({ idx, lang }) {
  const steps = [t(lang,'step_sent'), t(lang,'step_quotes'), t(lang,'step_revealed'), t(lang,'step_hired')];
  return (<ol className="flex items-center gap-1.5 flex-wrap text-[11px]" aria-label="Progress">
    {steps.map((s, si) => (<li key={s} className={cn('flex items-center gap-1', si <= idx ? 'text-primary font-semibold' : 'text-muted-foreground')}>
      {si > 0 ? <span aria-hidden className="text-muted-foreground/80">›</span> : null}
      <span aria-hidden className={cn('inline-block h-1.5 w-1.5 rounded-full', si <= idx ? 'bg-primary' : 'bg-muted-foreground/35')} />
      {s}{si === idx ? <span className="sr-only"> (current)</span> : null}
    </li>))}
  </ol>);
}
const fmtDate = (d, lang, withTime) => { try { return new Date(d).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day:'numeric', month:'short', year:'numeric', ...(withTime ? { hour:'2-digit', minute:'2-digit' } : {}) }); } catch (_e) { return ''; } };
const refOf = (id) => 'QD-' + String(id || '').slice(0, 8).toUpperCase();
/* The DB is the authority on the edit window: fn_edit_inquiry allows edits for
   exactly 1 hour after created_at, and only while the request is still open.
   The API's `editable` flag uses a 24h window, which disagrees with the server
   and produces an Edit button that always fails — so compute it from created_at. */
const EDIT_WINDOW_MS = 60 * 60 * 1000;
function editState(inq) {
  const open = !['revealed','completed','cancelled','closed'].includes(String(inq.status));
  const ms = EDIT_WINDOW_MS - (Date.now() - new Date(inq.created_at).getTime());
  return { canEdit: open && ms > 0, minutesLeft: Math.max(0, Math.ceil(ms / 60000)) };
}


/* ── Shell ─────────────────────────────────────────────────────────────────── */
export function CustomerPortal() {
  const [lang, setLangState] = useState('en');
  const [token, setToken] = useState('');
  const [phase, setPhase] = useState('login');
  const [mounted, setMounted] = useState(false);
  useEffect(() => {
    setMounted(true);
    try { const l = initLang(); if (l !== 'en') setLangState(l); } catch (_e) {}
    try { const tk = localStorage.getItem('qd-cust-token'); if (tk) { setToken(tk); setPhase('app'); } } catch (_e) {}
    SB.auth.getSession().then(({ data }) => { const ss = data.session; if (ss && ss.access_token) { setToken(ss.access_token); try { localStorage.setItem('qd-cust-token', ss.access_token); if (ss.refresh_token) localStorage.setItem('qd-cust-refresh', ss.refresh_token); } catch (_e) {} setPhase('app'); } }).catch(() => {});
  }, []);
  const setLang = (l) => { try { localStorage.setItem('qd-lang', l); } catch (_e) {} setLangState(l); };
  const onAuth = (access, refresh) => { try { localStorage.setItem('qd-cust-token', access || ''); if (refresh) localStorage.setItem('qd-cust-refresh', refresh); } catch (_e) {} setToken(access || ''); setPhase('app'); if (access) { try { SB.auth.setSession({ access_token: access, refresh_token: refresh || '' }).catch(() => {}); } catch (_e) {} } };
  const doSignOut = () => { try { localStorage.removeItem('qd-cust-token'); localStorage.removeItem('qd-cust-refresh'); } catch (_e) {} setToken(''); setPhase('login'); try { SB.auth.signOut().catch(() => {}); } catch (_e) {} };
  const rtl = lang === 'ar';
  if (!mounted) return null;
  return (<div dir={rtl ? 'rtl' : 'ltr'} className="osx min-h-screen bg-background text-foreground font-body">
    <Motion />
    <header className="qd-noprint sticky top-0 z-30 border-b border-border/70 bg-background/78 backdrop-blur-xl">
      <div className="mx-auto flex h-[60px] w-full max-w-[1120px] items-center justify-between gap-3 px-4 sm:px-6">
        <a className="group flex items-baseline gap-2 no-underline" href="/">
          <span className="font-head text-[16px] font-bold tracking-[-.02em] text-foreground">QuotesDone</span>
          <span className="text-[12px] font-semibold text-primary">{t(lang, 'brand_sub')}</span>
        </a>
        <div className="flex items-center gap-1.5 sm:gap-2">
          <Button asChild variant="ghost" size="sm" className="hidden sm:inline-flex"><a href="/">{t(lang, 'home')}</a></Button>
          <Button variant="outline" size="sm" onClick={() => setLang(rtl ? 'en' : 'ar')} aria-label={rtl ? 'Switch to English' : 'التبديل إلى العربية'}>{rtl ? 'EN' : 'عربي'}</Button>
          {phase === 'app' && <Button variant="outline" size="sm" onClick={doSignOut}>{t(lang, 'signout')}</Button>}
        </div>
      </div>
    </header>
    {phase === 'login' ? <Login onAuth={onAuth} lang={lang} /> : <Authed token={token} lang={lang} onSignOut={doSignOut} />}
  </div>);
}

function Login({ onAuth, lang }) {
  const [mode, setMode] = useState('signin'); const [step, setStep] = useState('id'); const [id, setId] = useState(''); const [code, setCode] = useState(''); const [ident, setIdent] = useState(''); const [msg, setMsg] = useState(''); const [busy, setBusy] = useState(false);
  const isSignup = mode === 'signup';
  const looksEmail = (v) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(v || '').trim());
  const send = async () => { const v = id.trim(); if (!v) return; if (isSignup && !looksEmail(v)) { setMsg(t(lang, 'signup_email_only')); return; } setBusy(true); setMsg('');
    try { const g = await call('role_guard', { user_kind: 'customer', identifier: v }); if (g && g.conflict === 'supplier') { setBusy(false); setMsg(t(lang, 'conflict_supplier')); return; } } catch (_e) {}
    let j; try { j = await call('login_otp', { action: 'send', user_kind: 'customer', identifier: v, allow_signup: isSignup }); } catch (_e) { setBusy(false); setMsg(t(lang, 'err_code_send')); return; } setBusy(false); if (j && j.ok) { setIdent(j.identifier || v); setStep('code'); } else setMsg((j && j.error) || t(lang, 'err_code_send')); };
  const verify = async () => { if (!code.trim()) return; setBusy(true); setMsg(''); let j; try { j = await call('login_otp', { action: 'verify', user_kind: 'customer', identifier: ident, code: code.trim() }); } catch (_e) { setBusy(false); setMsg(t(lang, 'err_incorrect')); return; } if (!j || !j.ok || !j.access_token) { setBusy(false); setMsg((j && j.error) || t(lang, 'err_incorrect')); return; } setBusy(false); onAuth(j.access_token, j.refresh_token); };
  const swap = (m) => { setMode(m); setStep('id'); setMsg(''); setCode(''); };
  return (<main id="main" className={S.center}>
    <div className="w-full max-w-[420px] qd-rise">
      <div className="surface rounded-2xl p-6">
        <div className={cn(S.tabsWrap, 'mb-4')} role="tablist">
          <button role="tab" aria-selected={!isSignup} className={cn(S.tab, !isSignup && S.tabOn)} onClick={() => swap('signin')}>{t(lang, 'tab_signin')}</button>
          <button role="tab" aria-selected={isSignup} className={cn(S.tab, isSignup && S.tabOn)} onClick={() => swap('signup')}>{t(lang, 'tab_signup')}</button>
        </div>
        <h1 className={S.h1}>{isSignup ? t(lang, 'create_account_title') : t(lang, 'welcome_back')}</h1>
        <p className={cn(S.sub, 'mt-1.5')}>{isSignup ? t(lang, 'signup_sub') : t(lang, 'signin_sub')}</p>
        {step === 'id' ? (<>
          <Input className="mt-4" inputMode="email" autoComplete="email" placeholder={isSignup ? t(lang, 'email_address') : t(lang, 'email_or_mobile')} value={id} onChange={(e) => setId(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && send()} />
          <Button className="btn-key mt-3 w-full" disabled={busy} onClick={send}>{busy ? t(lang, 'sending') : (isSignup ? t(lang, 'create_my_account') : t(lang, 'send_code'))}</Button>
        </>) : (<>
          <Input className="mt-4 tabular tracking-[.3em] text-center" inputMode="numeric" autoComplete="one-time-code" maxLength={6} placeholder={t(lang, 'code_placeholder')} value={code} onChange={(e) => setCode(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && verify()} />
          <p className={S.hint}>{t(lang, 'junk_note')}</p>
          <Button className="btn-key w-full" disabled={busy} onClick={verify}>{busy ? t(lang, 'verifying') : (isSignup ? t(lang, 'verify_continue') : t(lang, 'verify_signin'))}</Button>
          <Button variant="link" className="mt-2 h-auto px-0" onClick={() => { setStep('id'); setCode(''); setMsg(''); }}>{t(lang, 'use_diff')}</Button>
        </>)}
        {msg && <div className={S.err} role="alert">{msg}</div>}
      </div>
    </div>
  </main>);
}

function Authed({ token, lang, onSignOut }) {
  const [k, setK] = useState(null); const [err, setErr] = useState('');
  const load = () => { setErr(''); call('kyc', { action: 'state' }, token).then((j) => { if (j && j.error === 'unauthorized') setErr('unauth'); else setK(j || {}); }).catch(() => setErr('net')); };
  useEffect(() => { load(); }, [token]);
  if (err === 'unauth') return <main id="main" className={S.center}><div className="surface w-full max-w-[400px] rounded-2xl p-6 qd-rise"><p className={S.sub}>{t(lang, 'session_expired')}</p><Button className="mt-3 w-full" onClick={onSignOut}>{t(lang, 'tab_signin')}</Button></div></main>;
  if (err) return <main id="main" className={S.center}><div className="surface w-full max-w-[400px] rounded-2xl p-6 qd-rise"><p className={S.sub}>{t(lang, 'load_failed')}</p><Button className="mt-3 w-full" onClick={load}>{t(lang, 'retry')}</Button></div></main>;
  if (!k) return <main id="main" className={cn(S.wrap)}><Skeleton rows={4} /></main>;
  const complete = k.full_name && k.phone_verified && k.email_verified && k.terms_signed;
  if (!complete) return <ProfileGate token={token} lang={lang} onDone={load} kyc={k} />;
  return <Portal token={token} lang={lang} kyc={k} />;
}

function ProfileGate({ token, lang, onDone, kyc }) {
  const [st, setSt] = useState(null);
  const [full_name, setFullName] = useState(''); const [phone, setPhone] = useState(''); const [dob, setDob] = useState('');
  const [emCode, setEmCode] = useState(''); const [smsCode, setSmsCode] = useState(''); const [sentSms, setSentSms] = useState(false); const [sentEmail, setSentEmail] = useState(false);
  const [terms, setTerms] = useState(false); const [busy, setBusy] = useState(''); const [msg, setMsg] = useState('');
  const load = () => call('kyc', { action: 'state' }, token).then((j) => { setSt(j); setFullName((x) => x || j.full_name || ''); setPhone((x) => x || j.phone || ''); setDob((x) => x || j.dob || ''); }).catch(() => setMsg(t(lang, 'load_failed')));
  useEffect(() => { load(); }, []);
  if (!st) return <main id="main" className={S.center}><Skeleton rows={2} /></main>;
  const saveProfile = async () => { setBusy('save'); setMsg(''); const j = await call('kyc', { action: 'save_customer', full_name, phone, dob }, token); setBusy(''); if (j && j.ok) load(); else setMsg((j && j.error) || t(lang, 'load_failed')); };
  const sendSms = async () => { if (!phone) { setMsg(t(lang, 'enter_mobile_first')); return; } setBusy('sms'); setMsg(''); const j = await call('kyc', { action: 'send_sms', phone }, token); setBusy(''); if (j && j.ok) setSentSms(true); else setMsg((j && j.error) || t(lang, 'err_code_send')); };
  const verifySms = async () => { setBusy('vsms'); setMsg(''); const j = await call('kyc', { action: 'verify_sms', phone, code: smsCode }, token); setBusy(''); if (j && j.ok) load(); else setMsg((j && j.error) || t(lang, 'err_incorrect')); };
  const sendEmailCode = async () => { setBusy('em'); setMsg(''); const j = await call('kyc', { action: 'send_email' }, token); setBusy(''); if (j && j.ok) setSentEmail(true); else setMsg((j && j.error) || t(lang, 'err_code_send')); };
  const verifyEmail = async () => { setBusy('vem'); setMsg(''); const j = await call('kyc', { action: 'verify_email', code: emCode }, token); setBusy(''); if (j && j.ok) load(); else setMsg((j && j.error) || t(lang, 'err_incorrect')); };
  const acceptTerms = async () => { if (!terms) { setMsg(t(lang, 'must_accept')); return; } setBusy('terms'); setMsg(''); const j = await call('kyc', { action: 'accept_terms' }, token); setBusy(''); if (j && j.ok) { onDone(); } else setMsg((j && j.error) || t(lang, 'load_failed')); };
  const profileDone = st.full_name && st.phone && st.dob;
  const done = [!!profileDone, !!st.phone_verified, !!st.email_verified, !!st.terms_signed].filter(Boolean).length;
  return (<main id="main" className={S.center}>
    <div className="w-full max-w-[460px] qd-rise">
      <div className="surface rounded-2xl p-6">
        <h1 className={S.h1}>{t(lang, 'gate_title')}</h1>
        <p className={cn(S.sub, 'mt-1.5')}>{t(lang, 'gate_sub')}</p>
        <div className="mt-4 flex items-center gap-1.5" aria-label={`Step ${done + 1} of 4`}>
          {[0,1,2,3].map((i) => <span key={i} className={cn('h-1 flex-1 rounded-full transition-colors duration-500', i < done ? 'bg-primary' : 'bg-secondary')} />)}
        </div>
        <Input className="mt-4" autoComplete="name" placeholder={t(lang, 'full_name')} value={full_name} onChange={(e) => setFullName(e.target.value)} />
        <Input className="mt-3" inputMode="tel" autoComplete="tel" placeholder={t(lang, 'mobile_ph')} value={phone} onChange={(e) => setPhone(e.target.value)} />
        <label className={cn(S.sub, 'mt-3 mb-1 block')} htmlFor="qd-dob">{t(lang, 'dob_label')}</label>
        <Input id="qd-dob" type="date" style={{ colorScheme: 'dark' }} value={dob} onChange={(e) => setDob(e.target.value)} />
        {!profileDone && <Button className="btn-key mt-3 w-full" disabled={busy === 'save'} onClick={saveProfile}>{busy === 'save' ? t(lang, 'saving') : t(lang, 'save_details')}</Button>}
        {profileDone && <>
          <h2 className={cn(S.h2, 'mt-5')}>{t(lang, 'verify_mobile')} {st.phone_verified ? <Pill tone="teal">{t(lang, 'verified')}</Pill> : null}</h2>
          {!st.phone_verified && (!sentSms ? <Button size="sm" className="mt-2.5" disabled={busy === 'sms'} onClick={sendSms}>{busy === 'sms' ? t(lang, 'sending') : t(lang, 'send_sms')}</Button>
            : <><p className={S.hint}>{t(lang, 'junk_note')}</p><div className={S.frow}><Input className="tabular" inputMode="numeric" maxLength={6} placeholder={t(lang, 'code_placeholder')} value={smsCode} onChange={(e) => setSmsCode(e.target.value)} /><Button size="sm" disabled={busy === 'vsms'} onClick={verifySms}>{t(lang, 'verify')}</Button></div></>)}
          <h2 className={cn(S.h2, 'mt-5')}>{t(lang, 'verify_email_h')} {st.email_verified ? <Pill tone="teal">{t(lang, 'verified')}</Pill> : null}</h2>
          {!st.email_verified && (!sentEmail ? <Button size="sm" className="mt-2.5" disabled={busy === 'em'} onClick={sendEmailCode}>{busy === 'em' ? t(lang, 'sending') : t(lang, 'send_email_code')}</Button>
            : <><p className={S.hint}>{t(lang, 'junk_note')}</p><div className={S.frow}><Input className="tabular" inputMode="numeric" maxLength={6} placeholder={t(lang, 'code_placeholder')} value={emCode} onChange={(e) => setEmCode(e.target.value)} /><Button size="sm" disabled={busy === 'vem'} onClick={verifyEmail}>{t(lang, 'verify')}</Button></div></>)}
          {st.phone_verified && st.email_verified && <>
            <label className="mt-5 flex items-center gap-2 text-[13px] text-muted-foreground"><input type="checkbox" checked={terms} onChange={(e) => setTerms(e.target.checked)} /> {t(lang, 'accept_pre')}<a href="/terms" target="_blank" rel="noopener" className="font-semibold text-primary underline underline-offset-2">{t(lang, 'terms_link')}</a>{t(lang, 'accept_post')}</label>
            <Button className="btn-key mt-3 w-full" disabled={busy === 'terms'} onClick={acceptTerms}>{busy === 'terms' ? t(lang, 'finishing') : t(lang, 'finish_continue')}</Button>
          </>}
        </>}
        {msg && <div className={S.err} role="alert">{msg}</div>}
      </div>
    </div>
  </main>);
}

/* ── Portal (tabbed) ───────────────────────────────────────────────────────── */
function Portal({ token, lang, kyc }) {
  const [view, setView] = useState('overview');
  const [detail, setDetail] = useState(null);
  const [ov, setOv] = useState(null); const [data, setData] = useState(null); const [me, setMe] = useState(null);
  const [note, setNote] = useState(''); const [showNew, setShowNew] = useState(false); const [loading, setLoading] = useState(true);
  const loadInq = () => call('customer_api', { action: 'my_inquiries' }, token).then((j) => setData(j)).catch(() => {});
  const loadOv  = () => call('customer_portal', { action: 'overview', lang }, token).then((j) => { if (j && j.ok) setOv(j); }).catch(() => {});
  const loadMe  = () => call('customer_api', { action: 'me' }, token).then((j) => setMe((j && j.customer) || null)).catch(() => {});
  const refresh = () => { loadInq(); loadOv(); loadMe(); };
  useEffect(() => {
    Promise.allSettled([loadOv(), loadInq(), loadMe()]).then(() => setLoading(false));
    const sid = new URLSearchParams(location.search).get('session_id');
    // 27 Jul 2026: history.replaceState used to run unconditionally, BEFORE the ok check, and there
    // was no else branch. A payment that came back pending (async payment method) or errored at
    // Stripe left the customer with no message at all AND erased session_id from the address bar,
    // so a reload could not retry. They had been charged and had no way to tell. The URL is now
    // cleared only on success; every other outcome says something and keeps the reference.
    if (sid) {
      call('stripe_confirm', { session_id: sid }, token).then((j) => {
        if (j && j.ok) { history.replaceState({}, '', location.pathname); setNote(t(lang, 'payment_confirmed')); loadInq(); }
        else if (j && j.pending) { setNote(t(lang, 'payment_pending')); loadInq(); }
        else { setNote(t(lang, 'payment_check_failed') + sid); }
      }).catch(() => setNote(t(lang, 'payment_check_failed') + sid));
    }
  }, [token]);

  const inqs = (data && data.inquiries) || [];
  const stats = (ov && ov.stats) || {};
  const flat = useMemo(() => { const out = []; for (const i of inqs) { out.push(i); if (Array.isArray(i.children)) for (const c of i.children) out.push(c); } return out; }, [inqs]);
  const current = detail ? flat.find((x) => x.id === detail) : null;

  const NAV = [
    ['overview', t(lang, 'nav_overview')],
    ['requests', t(lang, 'nav_requests')],
    ['messages', t(lang, 'nav_messages')],
    ['account',  t(lang, 'nav_account')],
  ];
  const go = (v) => { setDetail(null); setView(v); setShowNew(false); };

  return (<main id="main" className={S.wrap}>
    <nav className="qd-noprint mb-5 flex items-center justify-between gap-3 flex-wrap" aria-label="Portal sections">
      <div className={S.tabsWrap} role="tablist">
        {NAV.map(([k, label]) => (
          <button key={k} role="tab" aria-selected={view === k} className={cn(S.tab, view === k && S.tabOn)} onClick={() => go(k)}>{label}</button>
        ))}
      </div>
      <Button size="sm" className="btn-key" onClick={() => { setView('requests'); setDetail(null); setShowNew((v) => !v); }}>
        {showNew ? t(lang, 'close') : t(lang, 'new_request')}
      </Button>
    </nav>

    {note && <div className={cn(S.note, 'qd-rise')} role="status">{note}</div>}
    {showNew && <div className="mb-5 qd-rise"><NewRequest token={token} lang={lang} onDone={() => { setShowNew(false); refresh(); setNote(t(lang, 'request_sent')); }} onCancel={() => setShowNew(false)} /></div>}

    {loading ? <Skeleton rows={4} /> : (<>
      {view === 'overview' && <Overview lang={lang} me={me} kyc={kyc} stats={stats} alerts={(ov && ov.alerts) || []} inqs={inqs} onOpen={(id) => { setView('requests'); setDetail(id); }} onNew={() => { setView('requests'); setShowNew(true); }} />}
      {view === 'requests' && (current
        ? <RequestDetail inq={current} token={token} lang={lang} onBack={() => setDetail(null)} onChange={refresh} />
        : <RequestList inqs={inqs} lang={lang} onOpen={setDetail} onNew={() => setShowNew(true)} />)}
      {view === 'messages' && <Messages token={token} lang={lang} />}
      {view === 'account' && <Account me={me} kyc={kyc} stats={stats} lang={lang} />}
    </>)}
  </main>);
}

/* ── Overview ──────────────────────────────────────────────────────────────── */
function Overview({ lang, me, kyc, stats, alerts, inqs, onOpen, onNew }) {
  const h = new Date().getHours();
  const greet = h < 12 ? t(lang,'greet_morning') : h < 18 ? t(lang,'greet_afternoon') : t(lang,'greet_evening');
  const name = (kyc && kyc.full_name) || (me && me.full_name) || '';
  const first = String(name).trim().split(/\s+/)[0] || '';
  const joined = me && me.created_at ? fmtDate(me.created_at, lang) : null;
  const hist = Array.isArray(stats.history_12m) ? stats.history_12m : [];
  const peak = Math.max(1, ...hist.map((m) => Number(m.inquiries) || 0));
  const recent = inqs.slice(0, 3);
  return (<div className="flex flex-col gap-7">
    <header className="qd-rise">
      <h1 className="font-head text-[25px] font-bold tracking-[-.025em] text-foreground text-balance">{greet}{first ? ', ' + first : ''}</h1>
      <p className={cn(S.sub, 'mt-1')}>{t(lang, 'overview_sub')}{joined ? ' · ' + t(lang,'member_since') + ' ' + joined : ''}</p>
    </header>

    {!!alerts.length && <div className="flex flex-col gap-2 qd-rise" style={rise(1)}>
      {alerts.map((a, i) => (<div key={i} className={cn('surface rounded-xl px-4 py-3', a.severity === 'high' ? 'border-red-500/35' : a.severity === 'medium' ? 'border-accent/35' : 'border-primary/30')}>
        <div className="flex items-center gap-2"><Pill tone={a.severity === 'high' ? 'red' : a.severity === 'medium' ? 'gold' : 'teal'}>!</Pill><b className="text-[13.5px] text-foreground">{a.title}</b></div>
        {a.detail ? <p className={cn(S.sub, 'mt-1')}>{a.detail}</p> : null}
      </div>))}
    </div>}

    <div className="grid grid-cols-2 gap-2.5 sm:grid-cols-3 lg:grid-cols-6">
      <Stat i={0} label={t(lang, 'k_requests')} value={stats.inquiries_total ?? 0} />
      <Stat i={1} label={t(lang, 'k_open')}     value={stats.open_inquiries ?? 0} />
      <Stat i={2} label={t(lang, 'k_quotes')}   value={stats.quotes_received ?? 0} />
      <Stat i={3} label={t(lang, 'k_avg')}      value={stats.avg_quotes_per_inquiry ?? 0} />
      <Stat i={4} label={t(lang, 'k_hired')}    value={stats.deals ?? 0} />
      <Stat i={5} label={t(lang, 'k_spend')}    value={aed(stats.total_spend)} />
    </div>

    <Section i={2} title={t(lang, 'activity_12m')}>
      <div className="surface rounded-xl p-4">
        {hist.length ? (<>
          <div className="flex h-[110px] items-end gap-[3px]" role="img" aria-label={t(lang, 'activity_12m')}>
            {hist.map((m, i) => { const v = Number(m.inquiries) || 0; return (
              <div key={i} className="group relative flex flex-1 flex-col items-center justify-end" title={`${m.month}: ${v}`}>
                <div className="qd-bar w-full rounded-t-[3px] bg-primary/35 group-hover:bg-primary/60 transition-colors"
                     style={{ height: Math.max(3, (v / peak) * 92) + 'px', animationDelay: (i * 38) + 'ms' }} />
              </div>); })}
          </div>
          <div className="mt-2 flex gap-[3px]">
            {hist.map((m, i) => <div key={i} className="flex-1 text-center text-[9.5px] text-muted-foreground">{String(m.month).split(' ')[0]}</div>)}
          </div>
        </>) : <p className={S.sub}>{t(lang, 'no_activity')}</p>}
      </div>
    </Section>

    <Section i={3} title={t(lang, 'recent_requests')}>
      {recent.length
        ? <div className={S.list}>{recent.map((i, ix) => <RequestRow key={i.id} inq={i} lang={lang} onOpen={onOpen} i={ix} />)}</div>
        : <Empty title={t(lang, 'empty_requests_title')} sub={t(lang, 'empty_requests_sub')} action={<Button className="btn-key" onClick={onNew}>{t(lang, 'new_request')}</Button>} />}
    </Section>
  </div>);
}

/* ── Account ───────────────────────────────────────────────────────────────── */
function Account({ me, kyc, stats, lang }) {
  const rows = [
    [t(lang,'name_l'),   (kyc && kyc.full_name) || (me && me.full_name) || '—'],
    [t(lang,'email_l'),  (me && me.email) || (kyc && kyc.email) || '—'],
    [t(lang,'mobile_l'), (kyc && kyc.phone) || (me && me.phone) || '—'],
    [t(lang,'joined_l'), me && me.created_at ? fmtDate(me.created_at, lang) : '—'],
  ];
  const checks = [
    [t(lang,'email_v'),  !!(kyc && kyc.email_verified)],
    [t(lang,'mobile_v'), !!(kyc && kyc.phone_verified)],
    [t(lang,'terms_v'),  !!(kyc && kyc.terms_signed)],
  ];
  return (<div className="flex flex-col gap-7">
    <header className="qd-rise">
      <h1 className="font-head text-[25px] font-bold tracking-[-.025em] text-foreground">{t(lang, 'your_account')}</h1>
      <p className={cn(S.sub, 'mt-1')}>{t(lang, 'account_sub')}</p>
    </header>
    <div className="grid gap-4 md:grid-cols-2">
      <Section i={1} title={t(lang, 'profile_details')}>
        <dl className="surface rounded-xl p-4">
          {rows.map(([k, v], i) => (<div key={k} className={cn('flex items-baseline justify-between gap-4 py-2', i < rows.length - 1 && 'border-b border-border/50')}>
            <dt className="text-[12.5px] text-muted-foreground">{k}</dt>
            <dd className="text-[13.5px] font-medium text-foreground text-right break-all">{v}</dd>
          </div>))}
        </dl>
      </Section>
      <Section i={2} title={t(lang, 'verification')}>
        <ul className="surface rounded-xl p-4">
          {checks.map(([k, ok], i) => (<li key={k} className={cn('flex items-center justify-between gap-4 py-2', i < checks.length - 1 && 'border-b border-border/50')}>
            <span className="text-[12.5px] text-muted-foreground">{k}</span>
            <Pill tone={ok ? 'teal' : 'muted'}>{ok ? t(lang, 'complete_l') : t(lang, 'pending_l')}</Pill>
          </li>))}
        </ul>
      </Section>
    </div>
    <Section i={3} title={t(lang, 'total_requests')}>
      <div className="grid grid-cols-2 gap-2.5 lg:grid-cols-4">
        <Stat i={0} label={t(lang, 'total_requests')} value={stats.inquiries_total ?? 0} />
        <Stat i={1} label={t(lang, 'total_quotes')}   value={stats.quotes_received ?? 0} />
        <Stat i={2} label={t(lang, 'total_hired')}    value={stats.deals ?? 0} />
        <Stat i={3} label={t(lang, 'total_spend')}    value={aed(stats.total_spend)} />
      </div>
    </Section>
  </div>);
}


/* ── Requests: list ────────────────────────────────────────────────────────── */
function statusTone(s) { return ({ sent:'teal', revealed:'gold', completed:'teal', closed:'muted', cancelled:'red', split:'teal' })[String(s)] || 'muted'; }
const STATUS_AR = { sent:'أُرسل', revealed:'تم الكشف', completed:'مكتمل', closed:'مُغلق', cancelled:'مُلغى', split:'مُقسّم' };
function statusLabel(s, lang) { const k = String(s || ''); return lang === 'ar' ? (STATUS_AR[k] || k) : k; }
function stepIndex(inq, quotes, anyRevealed) {
  return (inq.status === 'completed' || inq.hired_supplier_id) ? 3 : (anyRevealed ? 2 : (quotes.length ? 1 : 0));
}
function RequestRow({ inq, lang, onOpen, i = 0 }) {
  const quotes = inq.quotes || [];
  const anyRevealed = quotes.some((q) => q.revealed);
  const prices = quotes.map((q) => Number(q.price) || 0).filter(Boolean);
  const lo = prices.length ? Math.min(...prices) : null;
  const { canEdit, minutesLeft } = editState(inq);
  return (
    <button type="button" onClick={() => onOpen(inq.id)}
      className="surface qd-lift qd-rise w-full rounded-xl p-4 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      style={rise(i)} aria-label={`${inq.category || 'Request'} — ${quotes.length} quotes`}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-head text-[14.5px] font-bold capitalize text-foreground">{inq.category || 'Request'}</span>
            {inq.emirate ? <span className="text-[12px] text-muted-foreground">{inq.emirate}</span> : null}
            <Pill tone={statusTone(inq.status)}>{statusLabel(inq.status, lang)}</Pill>
            {canEdit ? <Pill tone="gold">{tf(lang, 'edit_window_open', { n: minutesLeft })}</Pill> : null}
          </div>
          {inq.summary ? <p className={cn(S.sub, 'mt-1 line-clamp-2')}>{inq.summary}</p> : null}
          <div className="mt-2"><Steps idx={stepIndex(inq, quotes, anyRevealed)} lang={lang} /></div>
        </div>
        <div className="shrink-0 text-right">
          <div className="font-head tabular text-[16px] font-bold text-foreground">{quotes.length}</div>
          <div className="text-[10.5px] text-muted-foreground">{t(lang, 'quotes_in')}</div>
          {lo ? <div className="tabular mt-1 text-[11.5px] text-primary">{aed(lo)}+</div> : null}
        </div>
      </div>
    </button>
  );
}
function RequestList({ inqs, lang, onOpen, onNew }) {
  if (!inqs.length) return (<div className="flex flex-col gap-5">
    <header className="qd-rise"><h1 className="font-head text-[25px] font-bold tracking-[-.025em] text-foreground">{t(lang, 'my_requests')}</h1><p className={cn(S.sub, 'mt-1')}>{t(lang, 'requests_sub')}</p></header>
    <Empty title={t(lang, 'empty_requests_title')} sub={t(lang, 'empty_requests_sub')} action={<Button className="btn-key" onClick={onNew}>{t(lang, 'new_request')}</Button>} />
  </div>);
  return (<div className="flex flex-col gap-5">
    <header className="qd-rise"><h1 className="font-head text-[25px] font-bold tracking-[-.025em] text-foreground">{t(lang, 'my_requests')}</h1><p className={cn(S.sub, 'mt-1')}>{t(lang, 'requests_sub')}</p></header>
    <div className={S.list}>
      {inqs.map((inq, i) => inq.is_combined && Array.isArray(inq.children) ? (
        <div key={inq.id} className="surface qd-rise rounded-xl p-4" style={rise(i)}>
          <div className="mb-2 flex items-center gap-2 flex-wrap">
            <Pill tone="teal">{t(lang, 'combined_project')}</Pill>
            <span className={S.sub}>{tf(lang, 'sep_requests', { n: inq.children.length })}</span>
          </div>
          {inq.summary ? <p className={cn(S.sub, 'mb-3')}>{inq.summary}</p> : null}
          <div className="flex flex-col gap-2.5">{inq.children.map((c, ci) => <RequestRow key={c.id} inq={c} lang={lang} onOpen={onOpen} i={ci} />)}</div>
        </div>
      ) : <RequestRow key={inq.id} inq={inq} lang={lang} onOpen={onOpen} i={i} />)}
    </div>
  </div>);
}

/* ── Requests: detail ──────────────────────────────────────────────────────── */
function RequestDetail({ inq, token, lang, onBack, onChange }) {
  const [editing, setEditing] = useState(false);
  const [eSummary, setESummary] = useState(inq.summary || '');
  const [eBudget, setEBudget] = useState(inq.budget || '');
  const [eEmirate, setEEmirate] = useState(inq.emirate || '');
  const [saving, setSaving] = useState(false); const [canceling, setCanceling] = useState(false); const [err, setErr] = useState('');
  const [showAll, setShowAll] = useState(false);
  const quotes = (inq.quotes || []).slice().sort((a, b) => (a.price || 0) - (b.price || 0));
  const concluded = ['completed', 'closed', 'cancelled'].includes(String(inq.status));
  const anyRevealed = quotes.some((q) => q.revealed);
  const { canEdit, minutesLeft } = editState(inq);

  const vmap = useMemo(() => { const m = {}; if (!quotes.length) return m;
    const ps = quotes.map((q) => Number(q.price) || 0).filter((p) => p > 0);
    const minP = ps.length ? Math.min(...ps) : 0, maxP = ps.length ? Math.max(...ps) : 0;
    for (const q of quotes) { const p = Number(q.price) || 0;
      const priceScore = (!p || maxP === minP) ? 70 : Math.round(100 - ((p - minP) / (maxP - minP)) * 55);
      const ratingScore = ratingScoreOf(q.rating);
      const compScore = Math.min(100, 50 + (q.scope ? 20 : 0) + (q.warranty ? 10 : 0) + (q.lead_time ? 10 : 0) + (q.verified ? 10 : 0));
      m[q.id] = Math.round(priceScore * 0.5 + ratingScore * 0.3 + compScore * 0.2); }
    return m; }, [quotes]);
  const bestId = quotes.length ? quotes.slice().sort((a, b) => (vmap[b.id] || 0) - (vmap[a.id] || 0))[0].id : null;
  const cheapestId = quotes.length ? quotes[0].id : null;

  // The agent evaluates every quote and shortlists three. Lead with those three,
  // keep the rest one click away — the customer can still reveal any of them.
  const cmp = useComparison(inq.id, token, lang, quotes.length >= 2);
  const shortlist = new Set((Array.isArray(cmp.analysis?.quotes) ? cmp.analysis.quotes : []).map((q) => q.label));
  const isShort = (q) => shortlist.has(q.label);
  const ordered = shortlist.size
    ? [...quotes.filter(isShort), ...quotes.filter((q) => !isShort(q))]
    : quotes;
  const LEAD = shortlist.size || Math.min(5, quotes.length);
  const collapsible = quotes.length > LEAD + 1;
  const visible = (collapsible && !showAll) ? ordered.slice(0, LEAD) : ordered;

  const doCancel = async () => {
    if (canceling) return;
    if (!confirm(t(lang, 'confirm_cancel'))) return;
    setCanceling(true); setErr('');
    try { const j = await call('customer_api', { action: 'cancel_inquiry', inquiry_id: inq.id }, token);
      if (j && j.ok) { onChange(); onBack(); } else { setErr((j && (j.message || j.error)) || 'Could not cancel. Please try again.'); setCanceling(false); } }
    catch (_e) { setErr('Could not cancel. Please check your connection and try again.'); setCanceling(false); }
  };
  const saveEdit = async () => {
    setSaving(true); setErr('');
    try { const j = await call('customer_api', { action: 'edit_inquiry', inquiry_id: inq.id, patch: { summary: eSummary, budget: eBudget || null, emirate: eEmirate || null } }, token);
      if (j && j.ok) { setEditing(false); onChange(); } else { setErr((j && (j.message || j.error)) || 'Could not save changes.'); } }
    catch (_e) { setErr('Could not save changes. Please try again.'); }
    setSaving(false);
  };

  return (<div className="flex flex-col gap-6">
    <div className="qd-noprint qd-rise">
      <Button variant="ghost" size="sm" onClick={onBack} className="-ms-2">{backArrow(lang)} {t(lang, 'back_to_requests')}</Button>
    </div>

    <header className="qd-rise" style={rise(1)}>
      <div className="flex flex-wrap items-center gap-2">
        <h1 className="font-head text-[24px] font-bold capitalize tracking-[-.025em] text-foreground">{inq.category || 'Request'}</h1>
        <Pill tone={statusTone(inq.status)}>{statusLabel(inq.status, lang)}</Pill>
        <span className="tabular text-[11.5px] text-muted-foreground">{t(lang, 'request_ref')} {refOf(inq.id)}</span>
      </div>
      {inq.summary && !editing ? <p className={cn(S.sub, 'mt-2 max-w-[70ch]')}>{inq.summary}</p> : null}
      <div className="mt-3"><Steps idx={stepIndex(inq, quotes, anyRevealed)} lang={lang} /></div>
    </header>

    {/* Edit / cancel — mirrors the server rules exactly (1h window, open status only) */}
    {!concluded && !anyRevealed && (
      <div className="qd-noprint qd-rise" style={rise(2)}>
        {editing ? (<div className="surface rounded-xl p-4">
          <textarea className={S.area} rows={3} value={eSummary} onChange={(e) => setESummary(e.target.value)} aria-label={t(lang, 'edit_request')} />
          <div className={S.frow}>
            <select className={S.field} style={{ colorScheme:'dark', backgroundColor:'hsl(205 46% 12%)', color:'hsl(180 25% 94%)' }} value={eEmirate} onChange={(e) => setEEmirate(e.target.value)} aria-label={t(lang, 'emirate_l')}>
              <option value="" style={{ backgroundColor:'#0C2330', color:'#EAF4F2' }}>{t(lang, 'emirate_l')}</option>
              {EMIRATES.map((em) => <option key={em} value={em} style={{ backgroundColor:'#0C2330', color:'#EAF4F2' }}>{em}</option>)}
            </select>
            <Input placeholder={t(lang, 'budget_l')} value={eBudget} onChange={(e) => setEBudget(e.target.value)} />
          </div>
          <div className="mt-3 flex flex-wrap items-center gap-2.5">
            <Button disabled={saving} onClick={saveEdit}>{saving ? t(lang, 'saving') : t(lang, 'save_changes')}</Button>
            <Button variant="link" className="h-auto px-0" onClick={() => { setEditing(false); setErr(''); }}>{t(lang, 'cancel_edit')}</Button>
          </div>
        </div>) : (<div className="flex flex-wrap items-center gap-3">
          {canEdit
            ? <Button variant="outline" size="sm" onClick={() => { setESummary(inq.summary || ''); setEBudget(inq.budget || ''); setEEmirate(inq.emirate || ''); setEditing(true); }}>
                {t(lang, 'edit_request')} <span className="ml-1.5 text-[11px] text-muted-foreground">· {tf(lang, 'edit_window_open', { n: minutesLeft })}</span>
              </Button>
            : <span className={S.sub}>{t(lang, 'edit_window_closed')}</span>}
          <Button variant="ghost" size="sm" className="text-red-300 hover:text-red-200" disabled={canceling} onClick={doCancel}>
            {canceling ? t(lang, 'cancelling') : t(lang, 'cancel_request')}
          </Button>
        </div>)}
        {err && <div className={S.err} role="alert">{err}</div>}
      </div>
    )}

    <SupplierBrief inq={inq} lang={lang} token={token} />

    {quotes.length >= 2 && <Section i={4} title={t(lang, 'quotes_in')}><Comparison a={cmp.analysis} busy={cmp.busy} note={cmp.note} lang={lang} inqId={inq.id} token={token} /></Section>}

    <Section i={5} title={`${t(lang, 'quotes_in')} (${quotes.length})`}
      sub={shortlist.size && collapsible ? tf(lang, 'shortlist_note', { n: quotes.length, k: shortlist.size }) : undefined}>
      {quotes.length ? (<div className="flex flex-col gap-3">
        {visible.map((q, i) => <QuoteCard key={q.id} q={q} token={token} lang={lang} concluded={concluded} onChange={onChange}
          vscore={vmap[q.id]} best={q.id === bestId} cheapest={q.id === cheapestId} shortlisted={isShort(q)}
          hired={inq.hired_supplier_id} i={i} />)}
        {collapsible ? (<Button variant="outline" className="qd-noprint mt-1 w-full" onClick={() => setShowAll((v) => !v)} aria-expanded={showAll}>
          {showAll ? t(lang, 'show_less') : tf(lang, 'show_all_quotes', { n: quotes.length })}
        </Button>) : null}
      </div>) : <Empty icon="◷" title={t(lang, 'no_quotes_yet')} sub={waitingSub(inq, lang)} />}
    </Section>
  </div>);
}

/* Honest empty state. my_inquiries returns matched_suppliers — the number of
   suppliers this request was actually dispatched to. Telling someone "we matched
   you with suitable suppliers" when that number is 0 is a lie they wait on, so
   the copy branches on the real figure. Older rows omit the field; those keep the
   neutral wording rather than claiming a count we cannot prove. */
function waitingSub(inq, lang) {
  const n = inq && inq.matched_suppliers;
  if (n === 0) return lang === 'ar'
    ? 'لم يُطابَق بعد أي مورّد نشط في هذه الفئة والإمارة. تم تنبيه فريقنا وسنعلمك فور توفّر مورّد مناسب.'
    : 'No active supplier in this category and emirate has been matched yet. Our team has been alerted and we will let you know as soon as one is available.';
  if (typeof n === 'number' && n > 0) return lang === 'ar'
    ? `طابقناك مع ${n} مورّدًا مناسبًا وسننبهك فور وصول أول عرض.`
    : `We matched you with ${n} suitable supplier${n === 1 ? '' : 's'} and will alert you the moment the first quote lands.`;
  return lang === 'ar'
    ? 'سننبهك فور وصول أول عرض.'
    : 'We will alert you the moment the first quote lands.';
}

/* What suppliers see — the anonymised brief, printable to PDF.
   Rendered from the same fields the dispatcher sends out, so the customer can
   verify exactly what left the building and that no contact detail went with it. */
function SupplierBrief({ inq, lang, token }) {
  const [open, setOpen] = useState(false);
  const ref = useRef(null);
  // Save as PDF goes through customer_api.brief_pdf -> pdf_native, so the download
  // carries the QuotesDone header band, logo, letterhead and footer exactly like a
  // quotation. It is not a browser print of this panel.
  const [pdfBusy, setPdfBusy] = useState(false);
  const [pdfMsg, setPdfMsg] = useState('');
  const savePdf = async () => {
    if (pdfBusy) return;
    setPdfBusy(true); setPdfMsg('');
    try {
      const j = await call('customer_api', { action: 'brief_pdf', inquiry_id: inq.id, lang }, token);
      if (j && j.ok && j.url) window.open(j.url, '_blank', 'noopener');
      else setPdfMsg((j && (j.detail || j.error)) || t(lang, 'pdf_failed'));
    } catch (_e) { setPdfMsg(t(lang, 'pdf_failed')); }
    setPdfBusy(false);
  };
  const spec = inq.spec && typeof inq.spec === 'object' ? inq.spec : null;
  const boq = inq.boq && Array.isArray(inq.boq.boq) ? inq.boq.boq : null;
  const facts = [];
  if (inq.category) facts.push([t(lang,'category_l'), String(inq.category)]);
  if (inq.emirate)  facts.push([t(lang,'emirate_l'),  String(inq.emirate)]);
  if (inq.budget)   facts.push([t(lang,'budget_l'),   String(inq.budget)]);
  if (Array.isArray(inq.trades) && inq.trades.length) facts.push([t(lang,'trades_l'), inq.trades.join(', ')]);
  if (inq.created_at) facts.push([t(lang,'posted_on'), fmtDate(inq.created_at, lang, true)]);
  if (spec) for (const k of Object.keys(spec)) { const v = spec[k]; if (v && typeof v === 'string' && k !== 'plausibility' && k !== 'provenance') facts.push([k.replace(/_/g, ' '), v]); }
  return (<Section i={3} title={t(lang, 'what_suppliers_see')} sub={t(lang, 'what_suppliers_see_sub')}
    right={<div className="qd-noprint flex gap-2">
      <Button variant="ghost" size="sm" onClick={() => setOpen((v) => !v)} aria-expanded={open}>{open ? t(lang, 'close') : t(lang, 'view_all')}</Button>
      {open ? <Button variant="outline" size="sm" disabled={pdfBusy} onClick={savePdf}>{pdfBusy ? t(lang, 'preparing') : t(lang, 'print_brief')}</Button> : null}
      {pdfMsg ? <span className="text-[12px] text-red-300">{pdfMsg}</span> : null}
    </div>}>
    <div ref={ref} className="surface rounded-xl p-4">
      <div className="flex items-center justify-between gap-3 border-b border-border/60 pb-3">
        <div>
          <div className="font-head text-[13.5px] font-bold text-foreground">QuotesDone · {t(lang, 'request_ref')} {refOf(inq.id)}</div>
          <div className={cn(S.sub, 'mt-0.5')}>{inq.summary || ''}</div>
        </div>
        <Pill tone="teal">{lang === 'ar' ? 'مجهول الهوية' : 'Anonymised'}</Pill>
      </div>
      {open ? (<div className="qd-fade">
        <dl className="mt-3 grid gap-x-5 gap-y-1.5 sm:grid-cols-2">
          {facts.slice(0, 16).map(([k, v], i) => (<div key={i} className="flex items-baseline justify-between gap-3 border-b border-border/35 py-1">
            <dt className="text-[12px] capitalize text-muted-foreground">{k}</dt>
            <dd className="text-[12.5px] text-foreground text-right">{v}</dd>
          </div>))}
        </dl>
        {boq ? (<div className="mt-4">
          <div className={cn(S.h2, 'mb-1.5')}>{t(lang, 'line_items')} ({boq.length})</div>
          <div className="overflow-x-auto">
            <table className="w-full text-[12.5px]">
              <thead><tr className="border-b border-border/60 text-left text-muted-foreground">
                <th scope="col" className="py-1.5 pr-3 font-medium">#</th>
                <th scope="col" className="py-1.5 pr-3 font-medium">{lang === 'ar' ? 'الوصف' : 'Description'}</th>
                <th scope="col" className="py-1.5 pr-3 font-medium">{lang === 'ar' ? 'الكمية' : 'Qty'}</th>
                <th scope="col" className="py-1.5 font-medium">{lang === 'ar' ? 'الوحدة' : 'Unit'}</th>
              </tr></thead>
              <tbody>{boq.slice(0, 40).map((b, i) => (<tr key={i} className="border-b border-border/30">
                <td className="tabular py-1.5 pr-3 text-muted-foreground">{i + 1}</td>
                <td className="py-1.5 pr-3 text-foreground">{String(b.description || b.desc || '')}</td>
                <td className="tabular py-1.5 pr-3 text-foreground">{b.qty == null ? '' : String(b.qty)}</td>
                <td className="py-1.5 text-muted-foreground">{String(b.unit || '')}</td>
              </tr>))}</tbody>
            </table>
          </div>
        </div>) : null}
        {inq.drawing_file_url ? (<div className="qd-noprint mt-3">
          <a href={inq.drawing_file_url} target="_blank" rel="noopener" className="text-[12.5px] font-semibold text-primary underline underline-offset-2">
            {t(lang, 'drawing_l')}{inq.drawing_file_name ? ' — ' + inq.drawing_file_name : ''}
          </a>
        </div>) : null}
        <p className={cn(S.sub, 'mt-4 border-t border-border/50 pt-2.5 text-[11.5px]')}>
          {lang === 'ar'
            ? 'لا يتضمّن هذا الملخّص اسمك أو بريدك أو رقم هاتفك. تُكشف بياناتك فقط عندما تختار كشف مورّد.'
            : 'This brief carries no name, email or phone number. Your details are released only when you choose to reveal a supplier.'}
        </p>
      </div>) : null}
    </div>
  </Section>);
}

/* One fetch, shared by the report and the quote list — so the list can lead with
   the same three the agent shortlisted instead of dumping N undifferentiated cards. */
function useComparison(inqId, token, lang, enabled) {
  const [a, setA] = useState(null); const [busy, setBusy] = useState(!!enabled); const [note, setNote] = useState('');
  useEffect(() => { if (!enabled) { setBusy(false); return; } let on = true; setBusy(true);
    call('quote_compare', { inquiry_id: inqId, lang }, token)
      .then((j) => { if (!on) return; setBusy(false); if (j && j.ok && j.analysis) setA(j.analysis); else setNote((j && (j.note || j.error)) || ''); })
      .catch(() => { if (on) setBusy(false); });
    return () => { on = false; }; }, [inqId, lang, enabled]);
  return { analysis: a, busy, note };
}

/* ── Comparison (AI report) ────────────────────────────────────────────────
   The data is inherently tabular (N suppliers x ~11 attributes), so on screen it
   renders as a real side-by-side table. "Save as PDF" does NOT print the page —
   it calls customer_api.compare_pdf, which builds the report through pdf_native,
   so the download carries the same letterhead, header band, gold rule and footer
   as a QuotesDone quotation. */
function Comparison({ a, busy, note, lang, inqId, token }) {
  const ref = useRef(null);
  const arr = (x) => Array.isArray(x) ? x : [];
  const [pdfBusy, setPdfBusy] = useState(false);
  const [pdfMsg, setPdfMsg] = useState('');
  const savePdf = async () => {
    if (pdfBusy) return;
    setPdfBusy(true); setPdfMsg('');
    try {
      const j = await call('customer_api', { action: 'compare_pdf', inquiry_id: inqId, lang }, token);
      if (j && j.ok && j.url) window.open(j.url, '_blank', 'noopener');
      else setPdfMsg((j && (j.detail || j.error)) || t(lang, 'pdf_failed'));
    } catch (_e) { setPdfMsg(t(lang, 'pdf_failed')); }
    setPdfBusy(false);
  };

  if (busy) return (<div className="surface rounded-xl border-primary/25 p-4">
    <div className="flex items-center gap-2"><span className="qd-shimmer inline-block h-2 w-2 rounded-full bg-primary/60" />
      <span className={cn(S.sub, 'text-primary')}>{lang === 'ar' ? 'يُعدّ خبيرنا تقرير المقارنة…' : 'Our expert is preparing your comparison report…'}</span></div>
  </div>);
  if (!a) return note ? (<div className="surface rounded-xl p-4"><p className={S.sub}>{note}</p></div>) : null;

  const qs = arr(a.quotes);
  const L = (en, ar) => (lang === 'ar' ? ar : en);
  const listCell = (items, tone) => { const xs = arr(items).filter(Boolean);
    if (!xs.length) return <span className="text-muted-foreground">—</span>;
    return (<ul className="m-0 list-none space-y-1 p-0">{xs.map((x, k) => (
      <li key={k} className={cn('flex gap-1.5', tone === 'warn' && 'text-accent', tone === 'bad' && 'text-red-300')}>
        <span aria-hidden className="mt-[2px] shrink-0 opacity-60">{tone === 'good' ? '+' : tone === 'bad' ? '!' : '·'}</span>
        <span>{x}</span></li>))}</ul>); };
  const ROWS = [
    { k:'price',        label:L('Price','السعر'),                       cell:(q)=> q.price!=null ? <b className="tabular text-foreground">{aed(q.price)}</b> : <span className="text-muted-foreground">—</span> },
    { k:'lead_time',    label:L('Lead time','مدة التنفيذ'),             cell:(q)=> q.lead_time || <span className="text-muted-foreground">—</span> },
    { k:'warranty',     label:L('Warranty','الضمان'),                   cell:(q)=> q.warranty || <span className="text-muted-foreground">—</span> },
    { k:'payment',      label:L('Payment terms','شروط الدفع'),          cell:(q)=> q.payment_terms || <span className="text-muted-foreground">—</span> },
    { k:'validity',     label:L('Valid for','مدة الصلاحية'),            cell:(q)=> q.validity || <span className="text-muted-foreground">—</span> },
    { k:'getting',      label:L('What you get','ما ستحصل عليه'),        cell:(q)=> q.getting || <span className="text-muted-foreground">—</span> },
    { k:'includes',     label:L('Included','مشمول'),                    cell:(q)=> listCell(q.includes,'good') },
    { k:'excludes',     label:L('Not included','غير مشمول'),            cell:(q)=> listCell(q.excludes,'warn') },
    { k:'missing',      label:L('Missing from your request','ناقص مما طلبت'), cell:(q)=> listCell(q.missing_from_request,'warn') },
    { k:'deviation',    label:L('Differs from your spec','اختلاف عن مواصفاتك'), cell:(q)=> listCell(q.spec_deviation,'warn') },
    { k:'flags',        label:L('Watch out','تنبيهات'),                 cell:(q)=> listCell(q.flags,'bad') },
  ].filter((r) => qs.some((q) => { const v=q[r.k==='payment'?'payment_terms':r.k==='missing'?'missing_from_request':r.k==='deviation'?'spec_deviation':r.k];
    return Array.isArray(v) ? v.length : (v!=null && v!==''); }) || r.k==='price');

  return (<div ref={ref} className="surface qd-fade rounded-xl border-primary/25 p-4">
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div className="min-w-0">
        <div className="mb-1 flex flex-wrap items-center gap-2">
          <Pill tone="teal">AI</Pill>
          <b className="font-head text-[13.5px] text-primary">{L('Expert comparison report','تقرير المقارنة من الخبير')}{a.trade ? ' · ' + a.trade : ''}</b>
        </div>
        {(a.considered || a.total_quotes) ? (<p className="text-[11.5px] text-muted-foreground">
          {L(`Evaluated ${a.considered ?? a.total_quotes} quote${(a.considered ?? a.total_quotes)===1?'':'s'} · shortlisted the strongest ${a.shortlisted ?? qs.length}`,
             `تم تقييم ${a.considered ?? a.total_quotes} عرضًا · واختيار أقوى ${a.shortlisted ?? qs.length}`)}
        </p>) : null}
      </div>
      <div className="qd-noprint shrink-0">
        <Button variant="outline" size="sm" disabled={pdfBusy} onClick={savePdf}>
          {pdfBusy ? t(lang, 'preparing') : t(lang, 'print_brief')}
        </Button>
        {pdfMsg ? <p className="mt-1 text-[12px] text-red-300">{pdfMsg}</p> : null}
      </div>
    </div>

    {a.bottom_line ? <p className="mt-2.5 text-[13.5px] font-semibold text-foreground">{a.bottom_line}</p> : null}
    {a.overview ? <p className={cn(S.sub, 'mt-1.5')}>{a.overview}</p> : null}
    {a.shortlist_reason ? <p className={cn(S.sub, 'mt-1.5 text-[12px] italic')}>{a.shortlist_reason}</p> : null}

    {arr(a.top3).length ? (<ol className="mt-3.5 grid gap-2 sm:grid-cols-3">
      {arr(a.top3).map((r, i) => (
        <li key={i} className={cn('rounded-lg border p-3', i === 0 ? 'border-primary/40 bg-primary/8' : 'border-border bg-background/30')}>
          <div className="flex items-center gap-1.5">
            <span className={cn('grid h-5 w-5 shrink-0 place-items-center rounded-full text-[11px] font-bold', i === 0 ? 'bg-primary text-primary-foreground' : 'bg-secondary text-foreground')}>{r.rank ?? i + 1}</span>
            <b className="text-[13px] text-foreground">{r.label}</b>
          </div>
          {r.why ? <p className={cn(S.sub, 'mt-1')}>{r.why}</p> : null}
          {r.tradeoff ? <p className="mt-1 text-[12px] text-accent">{L('Catch: ','الاعتبار: ') + r.tradeoff}</p> : null}
        </li>))}
    </ol>) : null}

    {qs.length ? (<div className="mt-4">
      <div className="qd-scroll -mx-1 overflow-x-auto px-1">
        <table className="qd-minw w-full min-w-[620px] border-collapse text-[12.5px]">
          <caption className="sr-only">{L('Side-by-side comparison of the shortlisted quotes','مقارنة جنبًا إلى جنب للعروض المختارة')}</caption>
          <thead>
            <tr>
              <th scope="col" className="w-[132px] border-b border-border/70 py-2 pe-3 text-start text-[11.5px] font-medium text-muted-foreground">
                {L('Compare','المقارنة')}
              </th>
              {qs.map((q) => { const best = a.best_value_label && q.label === a.best_value_label; const cheap = a.cheapest_label && q.label === a.cheapest_label;
                return (<th key={q.label} scope="col" className="border-b border-border/70 px-3 py-2 text-start align-bottom">
                  <div className="font-head text-[13px] font-bold text-foreground">{q.label}</div>
                  <div className="mt-1 flex flex-wrap gap-1">
                    {best ? <Pill tone="teal">{t(lang,'best_value')}</Pill> : null}
                    {cheap && !best ? <Pill tone="muted">{t(lang,'lowest_price')}</Pill> : null}
                  </div>
                </th>); })}
            </tr>
          </thead>
          <tbody>
            {ROWS.map((r, ri) => (
              <tr key={r.k} className={cn(ri % 2 ? 'bg-background/20' : '')}>
                <th scope="row" className="border-b border-border/40 py-2 pe-3 text-start align-top text-[11.5px] font-medium text-muted-foreground">{r.label}</th>
                {qs.map((q) => <td key={q.label + r.k} className="border-b border-border/40 px-3 py-2 align-top text-foreground">{r.cell(q)}</td>)}
              </tr>))}
          </tbody>
        </table>
      </div>
      {a.best_value_reason ? <p className={cn(S.sub, 'mt-2')}><b className="text-foreground">{L('Why that pick: ','سبب الاختيار: ')}</b>{a.best_value_reason}</p> : null}
    </div>) : null}

    {arr(a.line_findings).length ? (<div className="mt-4">
      <div className="mb-1.5 flex items-baseline gap-2">
        <h3 className={S.h2}>{L('Line by line','بندًا بندًا')}</h3>
        {a.itemised_quotes ? <span className="text-[11.5px] text-muted-foreground">
          {L(`${a.itemised_quotes} of ${qs.length} quotes are itemised`, `${a.itemised_quotes} من ${qs.length} عروض مُفصّلة ببنود`)}
        </span> : null}
      </div>
      <dl className="rounded-lg border border-border/60 bg-background/25 p-3">
        {arr(a.line_findings).map((f, i) => (
          <div key={i} className={cn('py-1.5', i < arr(a.line_findings).length - 1 && 'border-b border-border/35')}>
            <dt className="text-[12.5px] font-semibold text-foreground">{f.item}</dt>
            <dd className={cn(S.sub, 'mt-0.5')}>{f.finding}</dd>
          </div>))}
      </dl>
    </div>) : null}

    {arr(a.watch_outs).length ? (<div className="mt-3.5 rounded-lg border border-red-500/30 bg-red-500/8 p-3">
      <b className="text-[12.5px] text-red-300">{L('Watch out','انتبه')}</b>
      <ul className="mt-1 space-y-0.5">{arr(a.watch_outs).map((w, i) => <li key={i} className="text-[12.5px] text-red-200">· {w}</li>)}</ul>
    </div>) : null}

    {a.advice ? <p className={cn(S.sub, 'mt-3 text-foreground')}>{a.advice}</p> : null}
    <p className="mt-3 border-t border-border/50 pt-2.5 text-[11px] leading-relaxed text-muted-foreground">
      {a.disclaimer || t(lang, 'guidance_only')}
    </p>
  </div>);
}

/* ── Quote card ────────────────────────────────────────────────────────────── */
function QuotePdfLink({ q, token, lang }) {
  const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const open = async (e) => { e.stopPropagation(); setBusy(true); setMsg('');
    const j = await call('customer_api', { action: 'quote_pdf', quote_id: q.id, lang }, token);
    setBusy(false);
    if (j && j.ok && j.url) window.open(j.url, '_blank', 'noopener'); else setMsg((j && (j.detail || j.error)) || t(lang, 'pdf_failed')); };
  return (<>
    <button type="button" className="inline-flex min-h-[40px] items-center text-[12.5px] font-semibold text-primary underline underline-offset-2 disabled:opacity-60" disabled={busy} onClick={open}>
      {busy ? t(lang, 'preparing') : t(lang, 'view_quote_pdf')}
    </button>
    {msg ? <span className="ml-2 text-[12px] text-red-300">{msg}</span> : null}
  </>);
}
function ValueRing({ score }) {
  const R = 15, C = 2 * Math.PI * R, pct = Math.max(0, Math.min(100, Number(score) || 0));
  return (<svg width="38" height="38" viewBox="0 0 38 38" aria-hidden className="shrink-0">
    <circle cx="19" cy="19" r={R} fill="none" stroke="hsl(var(--secondary))" strokeWidth="3" />
    <circle cx="19" cy="19" r={R} fill="none" stroke="hsl(var(--primary))" strokeWidth="3" strokeLinecap="round"
      transform="rotate(-90 19 19)" className="qd-ring" style={{ '--c': C, '--o': C - (C * pct) / 100 }} />
    <text x="19" y="22.5" textAnchor="middle" className="tabular" fill="hsl(var(--foreground))" fontSize="11" fontWeight="700">{pct}</text>
  </svg>);
}
function QuoteCard({ q, token, concluded, onChange, vscore, best, cheapest, shortlisted, lang, hired, i = 0 }) {
  const [state, setState] = useState(q.revealed ? 'revealed' : 'idle');
  const [contact, setContact] = useState(null); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const reveal = async () => {
    setBusy(true); setMsg('');
    const r = await call('customer_api', { action: 'reveal', quote_id: q.id }, token);
    if (r.error) { setBusy(false); setMsg(r.error); return; }
    if (r.already_revealed) { setContact({ supplier: r.supplier, file_url: r.original_file_url, file_name: r.original_file_name }); setState('revealed'); setBusy(false); return; }
    // payment required — reuse the existing proven Stripe flow
    const cr = await call('stripe_checkout', { quote_id: q.id, return_url: location.origin + '/me' }, token);
    if (cr.already_revealed) { const rr = await call('customer_api', { action: 'reveal', quote_id: q.id }, token); setContact({ supplier: rr.supplier, file_url: rr.original_file_url, file_name: rr.original_file_name }); setState('revealed'); setBusy(false); return; }
    if (cr.url) { location.href = cr.url; return; }
    setBusy(false); setMsg(cr.error || 'Could not start checkout. Please try again.');
  };
  const showContactData = async () => { const r = await call('customer_api', { action: 'reveal', quote_id: q.id }, token); if (r.supplier) setContact({ supplier: r.supplier, file_url: r.original_file_url, file_name: r.original_file_name }); };
  useEffect(() => { if (state === 'revealed' && !contact) showContactData(); }, [state]);
  const meta = [
    q.lead_time ? [lang === 'ar' ? 'مدة التنفيذ' : 'Lead time', q.lead_time] : null,
    q.warranty ? [lang === 'ar' ? 'الضمان' : 'Warranty', q.warranty] : null,
    q.payment_terms ? [lang === 'ar' ? 'الدفع' : 'Terms', q.payment_terms] : null,
    q.validity ? [lang === 'ar' ? 'الصلاحية' : 'Valid', q.validity] : null,
  ].filter(Boolean);
  return (<article className="surface qd-lift qd-rise rounded-xl p-4" style={rise(i)}>
    <div className="flex items-start justify-between gap-3">
      <div className="min-w-0">
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="font-head text-[14.5px] font-bold text-foreground">{q.label}</span>
          {shortlisted ? <Pill tone="gold">{t(lang, 'shortlisted_badge')}</Pill> : null}
          {best ? <Pill tone="teal">{t(lang, 'best_value')}</Pill> : null}
          {cheapest && !best ? <Pill tone="muted">{t(lang, 'lowest_price')}</Pill> : null}
          {q.verified ? <Pill tone="teal">✓</Pill> : null}
          {q.expired ? <Pill tone="red">{lang === 'ar' ? 'منتهٍ' : 'Expired'}</Pill> : null}
        </div>
        <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-[11.5px] text-muted-foreground">
          {q.rating != null ? <span className="text-accent">★ <span className="tabular">{q.rating}</span> ({q.rating_count})</span> : null}
          {q.emirate ? <span>{q.emirate}</span> : null}
          {q.years_active != null ? <span>{q.years_active}y</span> : null}
          {q.win_rate != null ? <span>{lang === 'ar' ? 'الفوز' : 'win'} {Math.round(q.win_rate)}%</span> : null}
        </div>
      </div>
      <div className="flex shrink-0 items-center gap-3">
        <div className="text-right">
          <div className="font-head tabular text-[18px] font-bold leading-none text-foreground">{aed(q.price)}</div>
          {vscore != null ? <div className="mt-1 text-[10px] text-muted-foreground">{t(lang, 'value_score')}</div> : null}
        </div>
        {vscore != null ? <ValueRing score={vscore} /> : null}
      </div>
    </div>

    {meta.length ? (<dl className="mt-2.5 grid gap-x-4 gap-y-1 sm:grid-cols-2">
      {meta.map(([k, v]) => (<div key={k} className="flex items-baseline gap-1.5 text-[12px]">
        <dt className="text-muted-foreground">{k}:</dt><dd className="text-foreground">{v}</dd>
      </div>))}
    </dl>) : null}
    {q.scope ? <p className={cn(S.sub, 'mt-2')}>{q.scope}</p> : null}
    <div className="mt-2.5"><QuotePdfLink q={q} token={token} lang={lang} /></div>

    {state === 'revealed'
      ? (contact ? <Contact c={contact} q={q} token={token} onChange={onChange} lang={lang} won={hired != null && q.supplier_ref != null && Number(hired) === Number(q.supplier_ref)} />
                 : <p className={cn(S.sub, 'mt-2.5')}>{t(lang, 'loading_contact')}</p>)
      : (<div className="qd-noprint mt-3 flex flex-wrap items-center justify-between gap-2.5 border-t border-border/50 pt-3">
          <p className="max-w-[46ch] text-[12px] text-muted-foreground">{tf(lang, 'reveal_fee_note', { fee: aed(q.reveal_fee) })}</p>
          <Button size="sm" className="btn-key" disabled={busy || concluded} onClick={reveal}>{busy ? t(lang, 'please_wait') : t(lang, 'reveal_cta')}</Button>
        </div>)}
    {msg && <div className={S.err} role="alert">{msg}</div>}
  </article>);
}

/* Revealed supplier: contact details + full profile drill-down (supplier_history) */
function Contact({ c, q, token, onChange, lang, won }) {
  const s = c.supplier || {};
  const [rating, setRating] = useState(0); const [rated, setRated] = useState(!!(q && q.rated)); const [done, setDone] = useState('');
  const [prof, setProf] = useState(null); const [profOpen, setProfOpen] = useState(false); const [profBusy, setProfBusy] = useState(false);
  const rate = async (n) => { setRating(n); const j = await call('customer_api', { action: 'rate_supplier', quote_id: q.id, rating: n }, token); if (j && j.ok) { setRated(true); setDone(lang === 'ar' ? 'شكرًا لتقييمك.' : 'Thanks for rating.'); } else setDone((j && j.error) || 'Could not save rating.'); };
  const refund = async () => { if (!confirm(lang === 'ar' ? 'طلب استرداد رسوم الكشف؟ سنراجع طلبك. تنبيه المورّد أولًا يُبقي نافذة الاسترداد مفتوحة بينما نتابعه.' : 'Request a refund of the reveal fee? We will review it. Notifying the supplier first keeps your refund window open while we chase them.')) return; const j = await call('customer_api', { action: 'request_refund', quote_id: q.id }, token); setDone(j && j.ok ? (lang === 'ar' ? 'تم استلام طلب الاسترداد — سنراجعه.' : 'Refund requested — we will review it.') : ((j && j.error) || 'Could not request refund.')); };

  // ── Unresponsive-supplier escalation ────────────────────────────────────
  // Every date and gate is computed server-side (fn_refund_state) in UAE working days. This
  // component only renders what the server returns and never recomputes a deadline itself, so the
  // button, the escalation email and the server's refund decision always agree about the clock.
  const [esc, setEsc] = useState(null); const [escBusy, setEscBusy] = useState(false);
  const loadEsc = async () => {
    // customer_api does not return transaction_id on a quote, so refund_flow resolves it from
    // the quote id server-side (with the same ownership check).
    if (!q || !q.id || !q.revealed) return;
    const j = await call('refund_flow', { action: 'state', quote_id: q.id }, token);
    if (j && j.ok) setEsc(j);
  };
  useEffect(() => { loadEsc(); }, [q && q.id, q && q.revealed]);
  const notifySupplier = async () => {
    if (!confirm(lang === 'ar'
      ? 'سنرسل تنبيهًا رسميًا للمورّد، ونضعك ونضع فريق QuotesDone في نسخة من نفس الرسالة. متابعة؟'
      : 'We will send the supplier a formal notice, with you and the QuotesDone team copied on the same email. Continue?')) return;
    setEscBusy(true);
    const j = await call('refund_flow', { action: 'notify', quote_id: q.id }, token);
    setEscBusy(false);
    if (j && j.ok) { setEsc(j.state ? { ok: true, ...j.state } : null); await loadEsc();
      setDone(lang === 'ar' ? 'تم إرسال التنبيه — أنت والمورّد وفريقنا على نفس الرسالة.'
                            : 'Notice sent — you, the supplier and our team are on the same email.'); }
    else setDone((j && (j.error === 'not_available'
      ? (lang === 'ar' ? 'لم يحن وقت التنبيه بعد.' : 'It is not time to notify them yet.')
      : j.error)) || 'Could not send the notice.');
  };
  const hire = async () => { if (!confirm(lang === 'ar' ? 'تعليم هذا المورّد كمتعاقد معه لهذا المشروع؟' : 'Mark this supplier as hired for this project?')) return; const j = await call('customer_api', { action: 'complete_inquiry', quote_id: q.id }, token); if (j && j.ok) { setDone(lang === 'ar' ? 'تم التعليم كمتعاقد.' : 'Marked as hired.'); onChange && onChange(); } else setDone((j && j.error) || 'Could not update.'); };
  const loadProfile = async () => {
    if (prof) { setProfOpen((v) => !v); return; }
    setProfBusy(true);
    const j = await call('customer_api', { action: 'supplier_history', quote_id: q.id }, token);
    setProfBusy(false);
    if (j && j.ok) { setProf(j); setProfOpen(true); } else setDone((j && j.error) || t(lang, 'reveal_first'));
  };
  const sup = prof && prof.supplier ? prof.supplier : null;
  const rd = sup && sup.rating_display ? sup.rating_display : null;
  return (<div className="mt-3 rounded-xl border border-primary/30 bg-primary/8 p-4">
    <div className="flex flex-wrap items-center gap-2">
      <b className="font-head text-[14px] text-foreground">{s.company_name || 'Supplier'}</b>
      {won ? <Pill tone="gold">★ {t(lang, 'hired_badge')}</Pill> : null}
    </div>
    {q && q.revealed_at ? <p className={cn(S.sub, 'mt-0.5')}>{(lang === 'ar' ? 'كُشف بتاريخ ' : 'Revealed on ') + fmtDate(q.revealed_at, lang)}</p> : null}
    <p className={cn(S.sub, 'mt-0.5')}>{(lang === 'ar' ? 'دفعت ' : 'You paid ') + aed(q.reveal_fee) + (lang === 'ar' ? ' لكشف هذا المورّد' : ' to reveal this supplier')}</p>

    <div className="mt-2.5 flex flex-wrap gap-x-4 gap-y-1.5">
      {s.phone && <a href={'tel:' + s.phone} className="text-[13px] font-semibold text-primary underline underline-offset-2">☎ {s.phone}</a>}
      {s.whatsapp && <a href={'https://wa.me/' + String(s.whatsapp).replace(/[^0-9]/g, '')} target="_blank" rel="noopener" className="text-[13px] font-semibold text-primary underline underline-offset-2">WhatsApp</a>}
      {s.email && <a href={'mailto:' + s.email} className="text-[13px] font-semibold text-primary underline underline-offset-2 break-all">✉ {s.email}</a>}
      {s.website && <a href={/^https?:/.test(s.website) ? s.website : 'https://' + s.website} target="_blank" rel="noopener" className="text-[13px] font-semibold text-primary underline underline-offset-2">{lang === 'ar' ? 'الموقع' : 'Website'}</a>}
    </div>
    {c.file_url && <div className="mt-2"><a href={c.file_url} target="_blank" rel="noopener" className="text-[12.5px] font-semibold text-primary underline underline-offset-2">{t(lang, 'download_quotation')}{c.file_name ? ' (' + c.file_name + ')' : ''}</a></div>}

    <div className="qd-noprint mt-3 border-t border-primary/20 pt-3">
      <Button variant="ghost" size="sm" className="-ms-2" disabled={profBusy} onClick={loadProfile} aria-expanded={profOpen}>
        {profBusy ? t(lang, 'preparing') : (profOpen ? t(lang, 'close') : t(lang, 'view_profile'))}
      </Button>
      {profOpen && sup ? (<div className="qd-fade mt-2 rounded-lg border border-border/60 bg-background/40 p-3.5">
        <div className="flex flex-wrap items-center gap-2">
          <b className="font-head text-[13.5px] text-foreground">{sup.company_name}</b>
          {rd && rd.value != null ? <span className="text-[12px] text-accent">★ <span className="tabular">{rd.value}</span> ({rd.count}) · {rd.source}</span> : null}
        </div>
        {sup.capability_summary || sup.description ? <p className={cn(S.sub, 'mt-1.5')}>{sup.capability_summary || sup.description}</p> : null}
        <div className="mt-2.5 grid grid-cols-2 gap-2 sm:grid-cols-4">
          {sup.emirate ? <div><div className="text-[10.5px] text-muted-foreground">{t(lang,'based_in')}</div><div className="text-[12.5px] text-foreground">{sup.emirate}</div></div> : null}
          {sup.founded_year ? <div><div className="text-[10.5px] text-muted-foreground">{t(lang,'years_active')}</div><div className="tabular text-[12.5px] text-foreground">{Math.max(0, new Date().getFullYear() - Number(sup.founded_year))}</div></div> : null}
          {sup.company_type ? <div><div className="text-[10.5px] text-muted-foreground">{lang === 'ar' ? 'النوع' : 'Type'}</div><div className="text-[12.5px] text-foreground">{sup.company_type}</div></div> : null}
          <div><div className="text-[10.5px] text-muted-foreground">{t(lang,'past_projects')}</div><div className="tabular text-[12.5px] text-foreground">{prof.projects_count ?? 0}</div></div>
        </div>
        {Array.isArray(prof.projects) && prof.projects.length ? (<div className="mt-3">
          <div className={cn(S.h2, 'mb-1')}>{t(lang, 'past_projects')}</div>
          <ul className="flex flex-col gap-1">
            {prof.projects.slice(0, 8).map((p, i) => (<li key={i} className="flex items-baseline justify-between gap-3 border-b border-border/30 py-1 text-[12px]">
              <span className="capitalize text-foreground">{p.category || '—'}{p.emirate ? ' · ' + p.emirate : ''}</span>
              <span className="tabular text-muted-foreground">{p.month || ''} · {p.value_band || ''}</span>
            </li>))}
          </ul>
        </div>) : null}
      </div>) : null}
    </div>

    <div className="qd-noprint mt-3 flex flex-wrap items-center gap-4 border-t border-primary/20 pt-3">
      {!rated ? (<span className="flex items-center gap-1" role="group" aria-label={t(lang, 'rate_supplier')}>
        <span className="text-[12px] text-muted-foreground">{t(lang, 'rate_supplier')}</span>
        {[1,2,3,4,5].map((n) => (<button key={n} type="button" onClick={() => rate(n)} aria-label={`${n}`}
          className={cn('text-[17px] leading-none transition-colors', n <= rating ? 'text-accent' : 'text-muted-foreground/45 hover:text-accent/70')}>★</button>))}
      </span>) : <Pill tone="gold">★ {t(lang, 'rated_l')}</Pill>}
      <Button variant="link" className="h-auto px-0" onClick={hire}>{t(lang, 'i_hired')}</Button>
      {/* The escalation replaces the bare "Request refund" link, which promised a rule the server
          would not honour. The customer now sees exactly where they are and what happens next.
          Falls back to the old link only if the state could not be loaded, so this can never
          leave someone with no way to raise a problem. */}
      {esc && esc.state === 'waiting' ? (
        <span className="text-[12.5px] text-muted-foreground">
          {(lang === 'ar' ? 'لم يرد المورّد؟ يمكنك تنبيهه رسميًا اعتبارًا من ' : "No reply yet? You can formally notify them from ")
            + fmtDate(esc.notify_available_at, lang)}
        </span>
      ) : esc && esc.state === 'notify_available' ? (
        <Button variant="link" className="h-auto px-0 text-primary" disabled={escBusy} onClick={notifySupplier}>
          {escBusy ? (lang === 'ar' ? 'جارٍ الإرسال…' : 'Sending…')
                   : (lang === 'ar' ? 'تنبيه المورّد' : 'Notify supplier')}
        </Button>
      ) : esc && esc.state === 'notified_waiting' ? (
        <span className="text-[12.5px] text-muted-foreground">
          {(lang === 'ar' ? 'تم تنبيه المورّد. إذا لم يرد بحلول ' : 'Supplier notified. If they have not replied by ')
            + fmtDate(esc.founder_call_due_at, lang)
            + (lang === 'ar' ? '، سنتصل به مباشرة.' : ', we will call them directly.')}
        </span>
      ) : esc && esc.state === 'call_due' ? (
        // The full ladder has elapsed with no supplier reply, so this is the moment the customer
        // is entitled to their money back. The request action MUST be reachable here: it is the
        // only thing that sets refund_status='requested' and puts the claim in the founder's
        // approval queue (refunds_api). Without it the ladder dead-ends and no claim is ever
        // raised. fn_notify_supplier extends refund_deadline past this point so the server will
        // accept it — before that fix the window always closed before call_due was reached.
        <>
          <span className="text-[12.5px] text-accent">
            {lang === 'ar' ? 'لم يستجب المورّد ونحن نتابعه هاتفيًا. يمكنك طلب الاسترداد الآن.'
                           : 'The supplier has not responded and we are following up by phone. You can request your refund now.'}
          </span>
          <Button variant="link" className="h-auto px-0 text-primary" onClick={refund}>{t(lang, 'request_refund')}</Button>
        </>
      ) : esc && esc.state === 'supplier_responded' ? null : (
        <Button variant="link" className="h-auto px-0 text-muted-foreground" onClick={refund}>{t(lang, 'request_refund')}</Button>
      )}
    </div>
    {done && <p className={cn(S.sub, 'mt-2 text-primary')} role="status">{done}</p>}
  </div>);
}


/* ── Messages ──────────────────────────────────────────────────────────────
   Chat is gated: a customer asks a question, the assistant answers instantly,
   and a direct supplier chat opens only when it genuinely needs to. Preserved
   exactly — only the presentation changed. */
function Messages({ token, lang }) {
  const [threads, setThreads] = useState(null); const [open, setOpen] = useState(null);
  const reload = () => call('messages_api', { action: 'threads' }, token).then((j) => setThreads((j && j.threads) || [])).catch(() => setThreads([]));
  useEffect(() => { reload(); }, []);
  if (open) return <Thread token={token} th={open} lang={lang} onBack={() => { setOpen(null); reload(); }} />;
  return (<div className="flex flex-col gap-5">
    <header className="qd-rise">
      <h1 className="font-head text-[25px] font-bold tracking-[-.025em] text-foreground">{t(lang, 'messages')}</h1>
    </header>
    {!threads ? <Skeleton rows={3} />
      : !threads.length
        ? <Empty icon="✉" title={lang === 'ar' ? 'لا توجد محادثات بعد' : 'No conversations yet'}
            sub={lang === 'ar'
              ? 'بعد كشف مورّد، يمكنك طرح أسئلتك هنا. يجيب مساعدنا على معظم الأمور فورًا ويفتح محادثة مباشرة عند الحاجة فقط.'
              : 'After you reveal a supplier, you can ask them questions here. Our assistant answers most things instantly and opens a direct chat only when needed.'} />
        : <div className={S.list}>{threads.map((th, i) => (
            <button key={th.inquiry_id + ':' + th.supplier_id} type="button" onClick={() => setOpen(th)} style={rise(i)}
              className="surface qd-lift qd-rise w-full rounded-xl p-4 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <b className="font-head text-[13.5px] text-foreground">{th.counterpart}</b>
                    {th.subject ? <span className="text-[12px] text-muted-foreground">{th.subject}</span> : null}
                  </div>
                  <p className={cn(S.sub, 'mt-1 line-clamp-1')}>{th.last || (lang === 'ar' ? 'لا توجد رسائل بعد' : 'No messages yet')}</p>
                </div>
                <div className="shrink-0 text-right">
                  {th.unread ? <Pill tone="teal">{th.unread}</Pill> : null}
                  <div className="mt-1 text-[10.5px] capitalize text-muted-foreground">{th.chat_status === 'none' ? (lang === 'ar' ? 'لا توجد محادثة' : 'no chat') : th.chat_status}</div>
                </div>
              </div>
            </button>))}
          </div>}
  </div>);
}
function Thread({ token, th, onBack, lang }) {
  const [data, setData] = useState(null); const [text, setText] = useState(''); const [q, setQ] = useState(''); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const load = () => call('messages_api', { action: 'thread', inquiry_id: th.inquiry_id, supplier_id: th.supplier_id }, token).then(setData).catch(() => {});
  useEffect(() => { load(); }, []);
  const send = async () => { if (!text.trim()) return; setBusy(true); setMsg(''); const j = await call('messages_api', { action: 'send', inquiry_id: th.inquiry_id, supplier_id: th.supplier_id, body: text.trim() }, token); setBusy(false); if (j && j.ok) { setText(''); load(); } else setMsg((j && j.warning) || (j && j.error) || 'Could not send.'); };
  const requestChat = async () => { if (!q.trim()) return; setBusy(true); setMsg(''); const j = await call('messages_api', { action: 'request_chat', inquiry_id: th.inquiry_id, supplier_id: th.supplier_id, question: q.trim() }, token); setBusy(false); if (j && j.answered) setMsg('Assistant: ' + j.answer); else if (j && j.requested) setMsg(j.note || 'Sent for review — you will be notified if a chat opens.'); else setMsg((j && (j.note || j.error)) || 'Sent.'); setQ(''); };
  if (!data) return <div className="flex flex-col gap-4"><div className="qd-rise"><Button variant="ghost" size="sm" className="-ms-2" onClick={onBack}>{backArrow(lang)} {t(lang, 'back')}</Button></div><Skeleton rows={2} /></div>;
  return (<div className="flex flex-col gap-4">
    <div className="qd-rise"><Button variant="ghost" size="sm" className="-ms-2" onClick={onBack}>{backArrow(lang)} {t(lang, 'back')}</Button></div>
    <div className="surface qd-rise rounded-xl p-5">
      <h1 className={S.h2}>{data.counterpart || th.counterpart}</h1>
      {data.warning && <div className="mt-2.5 rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-[11.5px] text-accent">{data.warning}</div>}
      {data.chat_status === 'open' ? (<>
        <div className="my-3 flex max-h-[420px] flex-col gap-2 overflow-y-auto">
          {(data.messages || []).map((m, i) => (
            <div key={m.id} style={rise(Math.min(i, 8))}
              className={cn('qd-fade max-w-[76%] rounded-xl px-3 py-2 text-[13.5px] leading-snug',
                m.sender === data.role ? 'self-end rounded-br-sm bg-primary text-primary-foreground' : 'self-start rounded-bl-sm border border-border bg-secondary/55 text-foreground')}>{m.body}</div>))}
        </div>
        <div className="flex gap-2">
          <Input placeholder={lang === 'ar' ? 'اكتب رسالة…' : 'Type a message…'} value={text} onChange={(e) => setText(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && send()} />
          <Button size="sm" disabled={busy} onClick={send}>{busy ? t(lang, 'sending') : (lang === 'ar' ? 'إرسال' : 'Send')}</Button>
        </div>
      </>) : (<>
        <p className={cn(S.sub, 'mt-2')}>{data.note || (lang === 'ar' ? 'لا توجد محادثة مفتوحة بعد.' : 'No chat open yet.')}</p>
        <textarea className={S.area} rows={2} value={q} onChange={(e) => setQ(e.target.value)}
          aria-label={lang === 'ar' ? 'اسأل المورّد' : 'Ask the supplier a question'}
          placeholder={lang === 'ar'
            ? 'اسأل المورّد سؤالًا — يجيب مساعدنا فورًا، ويفتح محادثة مباشرة عند الحاجة.'
            : 'Ask the supplier a question — our assistant answers instantly, or opens a direct chat if needed.'} />
        <div className="mt-2.5"><Button size="sm" disabled={busy} onClick={requestChat}>{lang === 'ar' ? 'اسأل / اطلب محادثة' : 'Ask / request a chat'}</Button></div>
      </>)}
      {msg && <p className={cn(S.sub, 'mt-2.5 whitespace-pre-wrap text-foreground')} role="status">{msg}</p>}
    </div>
  </div>);
}


async function blobToWavB64(blob) {
  const AC = window.AudioContext || window.webkitAudioContext; const ac = new AC();
  const buf = await ac.decodeAudioData(await blob.arrayBuffer());
  const rate = 16000; const off = new OfflineAudioContext(1, Math.ceil(buf.duration * rate), rate);
  const src = off.createBufferSource(); src.buffer = buf; src.connect(off.destination); src.start();
  const rendered = await off.startRendering(); const pcm = rendered.getChannelData(0);
  const wav = encodeWav(pcm, rate); const bytes = new Uint8Array(await wav.arrayBuffer()); let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

/* ── New request: conversational intake ────────────────────────────────────── */
function NewRequest({ token, onDone, onCancel, lang }) {
  const GREETING = { role: 'assistant', text: lang === 'ar'
    ? 'مرحبًا — أنا مساعد الطلبات في QuotesDone. أخبرني بما تحتاجه وفي أي إمارة، وسأطرح سؤالين سريعين حتى يتمكن المورّدون من التسعير بدقة. يمكنك الكتابة أو إرفاق رسم أو صورة أو عرض سعر، أو الضغط على الميكروفون. تبقى هويتك مخفية حتى تختار كشف مورّد.'
    : "Hi — I'm your QuotesDone intake assistant. Tell me what you need done and which emirate it's in, and I'll ask a couple of quick questions so suppliers can quote accurately. You can type, attach a drawing / photo / your own quotation, or tap the mic. Your identity stays hidden until you choose to reveal a supplier." };
  const [messages, setMessages] = useState([GREETING]);
  const [input, setInput] = useState('');
  const [intakeId, setIntakeId] = useState(null);
  const [drawing, setDrawing] = useState(null);
  const [thinking, setThinking] = useState(false);
  const [analyzing, setAnalyzing] = useState(false);
  const [brief, setBrief] = useState(null);
  const [ready, setReady] = useState(false);
  const [combineMode, setCombineMode] = useState('multi');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');
  const [rec, setRec] = useState(false); const [voxBusy, setVoxBusy] = useState(false); const recRef = useRef(null);
  const fileRef = useRef(null); const endRef = useRef(null);
  const push = (m) => setMessages((a) => [...a, m]);
  useEffect(() => { try { endRef.current && endRef.current.scrollIntoView({ behavior: 'smooth', block: 'end' }); } catch (_e) {} }, [messages, thinking, analyzing, ready]);
  const runIntake = async (message) => {
    setThinking(true); setMsg('');
    const r = await call('inquiry_intake', { intake_id: intakeId, text: message, drawing_boq: (drawing && drawing.boq) || null }, token);
    setThinking(false);
    if (!r || r.error) { push({ role: 'assistant', text: (r && (r.message || r.error)) || 'Sorry — something went wrong. Please try again.' }); return; }
    if (r.intake_id) setIntakeId(r.intake_id);
    if (r.assistant_message) push({ role: 'assistant', text: r.assistant_message });
    if (r.status === 'ready') { setBrief(r.brief || null); setReady(true); } else { setReady(false); }
  };
  const send = async () => { const v = input.trim(); if (!v) return; push({ role: 'user', text: v }); setInput(''); await runIntake(v); };
  const onKey = (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); } };
  const onFile = async (file) => {
    if (!file) return; setMsg(''); setAnalyzing(true);
    push({ role: 'user', text: '', chip: file.name });
    try {
      const { images, b64, mime } = await fileToImages(file);
      const res = await call('customer_api', { action: 'analyze_drawing', images, original_b64: b64, mime, drawing_file_name: file.name, hint: messages.filter((m) => m.role === 'user').map((m) => m.text).join(' ').slice(0, 400) }, token);
      const dr = { drawing_file_path: (res && res.drawing_file_path) || null, drawing_file_name: (res && res.drawing_file_name) || file.name, drawing_redacted_paths: (res && res.drawing_redacted_paths) || null, boq: (res && res.boq) || null, brief_source: 'drawing' };
      setDrawing(dr);
      const n = res && res.boq && res.boq.boq ? res.boq.boq.length : 0;
      if (n >= 1) { setBrief((b) => b || { category: res.boq.category || '', summary: res.boq.summary || file.name, emirate: '', trades: [] }); setReady(true); }
      push({ role: 'assistant', text: n ? ('Got it — I read ' + n + ' line item' + (n > 1 ? 's' : '') + ' from your file' + (res.boq.category ? ' (' + res.boq.category + ')' : '') + '. Add anything else, or tap Send to suppliers below.') : 'Thanks — I\'ve attached your file for suppliers. Tell me a little about the job so I can brief them properly.' });
    } catch (_e) { push({ role: 'assistant', text: 'I could not read that file, but you can still describe the job here in the chat.' }); }
    setAnalyzing(false); try { if (fileRef.current) fileRef.current.value = ''; } catch (_e) {}
  };
  const startRec = async () => { try { const stream = await navigator.mediaDevices.getUserMedia({ audio: true }); const mr = new MediaRecorder(stream); recRef.current = { mr, chunks: [], stream }; mr.ondataavailable = (e) => { if (e.data && e.data.size) recRef.current.chunks.push(e.data); }; mr.onstop = async () => { setVoxBusy(true); try { const blob = new Blob(recRef.current.chunks, { type: (recRef.current.chunks[0] && recRef.current.chunks[0].type) || 'audio/webm' }); const b64 = await blobToWavB64(blob); const j = await call('transcribe', { audio_b64: b64, mime: 'audio/wav' }, token); if (j && j.ok && j.text) setInput((tx) => (tx ? tx + ' ' : '') + j.text); else if (j && j.error) setMsg('Could not transcribe: ' + j.error); } catch (_e) { setMsg('Could not process the recording.'); } setVoxBusy(false); try { recRef.current.stream.getTracks().forEach((t) => t.stop()); } catch (_e) {} }; mr.start(); setRec(true); } catch (_e) { setMsg('Please allow microphone access to use voice.'); } };
  const stopRec = () => { try { recRef.current && recRef.current.mr.stop(); } catch (_e) {} setRec(false); };
  const submit = async () => {
    setBusy(true); setMsg('');
    const category = (brief && brief.category) || (drawing && drawing.boq && drawing.boq.category) || '';
    const firstUser = messages.find((m) => m.role === 'user' && m.text);
    const summary = (brief && brief.summary) || (firstUser ? firstUser.text.slice(0, 180) : category);
    const r = await call('customer_api', { action: 'create_inquiry', intake_id: intakeId || null, category: category || null, emirate: (brief && brief.emirate) || null, raw_input: messages.filter((m) => m.role === 'user' && m.text).map((m) => m.text).join('\n'), spec: { plausibility: (brief && brief.plausibility) || null, provenance: (brief && brief.provenance) || null }, summary, budget: (brief && brief.budget) || null, scope_type: (brief && Array.isArray(brief.trades) && brief.trades.length > 1) ? combineMode : 'single', trades: (brief && Array.isArray(brief.trades)) ? brief.trades : [], drawing }, token);
    setBusy(false);
    if (r && r.ok) onDone();
    else if (r && r.error === 'intake_required') { setReady(false); push({ role: 'assistant', text: 'Just a couple more details first, so suppliers can quote accurately.' }); }
    else setMsg((r && (r.message || r.error)) || 'Could not send your request.');
  };
  const trades = (brief && Array.isArray(brief.trades)) ? brief.trades : [];
  return (<div className="surface flex flex-col overflow-hidden rounded-2xl" style={{ height: 'min(72vh, 640px)' }}>
    <div className="flex items-center justify-between gap-2.5 border-b border-border/70 px-5 py-3">
      <div className="flex items-center gap-2">
        <span aria-hidden className="grid h-6 w-6 place-items-center rounded-full bg-primary/12 text-[11px] font-bold text-primary">AI</span>
        <h2 className={S.h2}>{t(lang, 'new_request').replace('+ ', '')}</h2>
      </div>
      <Button variant="link" className="h-auto px-0" onClick={onCancel}>{t(lang, 'close')}</Button>
    </div>
    <div className="flex-1 space-y-2.5 overflow-y-auto px-4 py-3.5">
      {messages.map((m, i) => (
        m.chip !== undefined
          ? <div key={i} className="flex justify-end qd-fade"><div className="rounded-2xl border border-primary/30 bg-primary/12 px-3 py-2 text-[13px] text-foreground">◫ {m.chip}</div></div>
          : <div key={i} className={cn('flex qd-fade', m.role === 'user' ? 'justify-end' : 'justify-start')}>
              <div className={cn('max-w-[85%] whitespace-pre-wrap rounded-2xl px-3.5 py-2 text-[13.5px] leading-relaxed',
                m.role === 'user' ? 'bg-primary text-primary-foreground' : 'border border-border bg-secondary/55 text-foreground')}>{m.text}</div>
            </div>
      ))}
      {(thinking || analyzing) && (<div className="flex justify-start">
        <div className="flex items-center gap-1.5 rounded-2xl border border-border bg-secondary/55 px-3.5 py-2.5">
          {[0,1,2].map((d) => <span key={d} className="qd-shimmer inline-block h-1.5 w-1.5 rounded-full bg-primary/70" style={{ animationDelay: (d * 160) + 'ms' }} />)}
          <span className="ml-1 text-[12.5px] text-muted-foreground">{analyzing ? (lang === 'ar' ? 'أقرأ ملفك…' : 'Reading your file…') : (lang === 'ar' ? 'يكتب…' : 'Typing…')}</span>
        </div>
      </div>)}
      {ready && brief && (
        <div className="qd-rise rounded-xl border border-primary/30 bg-primary/6 p-4">
          <div className="flex items-center gap-2"><Pill tone="teal">{lang === 'ar' ? 'جاهز' : 'Ready'}</Pill>
            <b className="font-head text-[13.5px] capitalize text-foreground">{brief.category || 'Request'}{brief.emirate ? ' — ' + brief.emirate : ''}</b></div>
          <p className={cn(S.sub, 'mt-1.5')}>{brief.summary || ''}</p>
          <dl className="mt-2 grid gap-x-4 gap-y-0.5 sm:grid-cols-2">
            {brief.scope ? <div className="text-[12.5px]"><dt className="inline text-muted-foreground">{t(lang,'scope_l')}: </dt><dd className="inline text-foreground">{brief.scope}</dd></div> : null}
            {brief.timeline ? <div className="text-[12.5px]"><dt className="inline text-muted-foreground">{lang === 'ar' ? 'المدة' : 'Timeline'}: </dt><dd className="inline text-foreground">{brief.timeline}</dd></div> : null}
            {brief.budget ? <div className="text-[12.5px]"><dt className="inline text-muted-foreground">{t(lang,'budget_l')}: </dt><dd className="inline text-foreground">{brief.budget}</dd></div> : null}
            {brief.quantity ? <div className="text-[12.5px]"><dt className="inline text-muted-foreground">{lang === 'ar' ? 'الكمية' : 'Quantity'}: </dt><dd className="inline text-foreground">{brief.quantity}</dd></div> : null}
          </dl>
          {trades.length > 1 ? (<fieldset className="mt-3 rounded-lg border border-primary/25 bg-primary/5 p-3">
            <legend className="px-1 text-[12.5px] font-semibold text-primary">{lang === 'ar' ? ('يشمل هذا المشروع عدة تخصصات: ' + trades.join('، ')) : ('This project spans several trades: ' + trades.join(', '))}</legend>
            <p className={cn(S.sub, 'mb-1.5')}>{lang === 'ar' ? 'كيف تود توريده؟' : 'How would you like to source it?'}</p>
            <label className="flex cursor-pointer items-start gap-2 rounded-md p-2 hover:bg-secondary/40"><input type="radio" name="combine" className="mt-1" checked={combineMode === 'multi'} onChange={() => setCombineMode('multi')} />
              <span className={S.sub}><span className="font-semibold text-foreground">{lang === 'ar' ? 'متخصصون منفصلون (موصى به)' : 'Separate specialists (recommended)'}</span> — {lang === 'ar' ? 'يُرسل طلب منفصل لمتخصصي كل تخصص، فتحصل على أفضل سعر لكل جزء.' : 'a separate request goes to specialists in each trade, so you get the sharpest price on every part.'}</span></label>
            <label className="flex cursor-pointer items-start gap-2 rounded-md p-2 hover:bg-secondary/40"><input type="radio" name="combine" className="mt-1" checked={combineMode === 'turnkey'} onChange={() => setCombineMode('turnkey')} />
              <span className={S.sub}><span className="font-semibold text-foreground">{lang === 'ar' ? 'شركة واحدة تسليم مفتاح' : 'One turnkey company'}</span> — {lang === 'ar' ? 'شركة تجهيز/ديكور واحدة تتولى المشروع بالكامل.' : 'a single fit-out / decoration company handles the whole project end to end.'}</span></label>
          </fieldset>) : null}
          {brief.plausibility && brief.plausibility.note ? <p className="mt-1.5 text-[12.5px] text-accent">{(lang === 'ar' ? 'ملاحظة: ' : 'Note: ') + brief.plausibility.note}</p> : null}
          <Button className="btn-key mt-3 w-full" disabled={busy} onClick={submit}>{busy ? t(lang, 'sending') : (lang === 'ar' ? 'إرسال إلى المورّدين' : 'Send to suppliers')}</Button>
          <p className={cn(S.sub, 'mt-1.5 text-center')}>{lang === 'ar' ? 'أو تابع الكتابة أدناه لإضافة تفاصيل' : 'or keep typing below to add more detail'}</p>
        </div>
      )}
      <div ref={endRef} />
    </div>
    <div className="border-t border-border/70 px-3 py-2.5">
      {msg && <div className={cn(S.err, 'mb-1.5')} role="alert">{msg}</div>}
      <div className="flex items-end gap-2">
        <input ref={fileRef} type="file" accept="image/*,application/pdf" className="hidden" onChange={(e) => onFile(e.target.files[0])} />
        <button type="button" aria-label={lang === 'ar' ? 'إرفاق ملف' : 'Attach a drawing, photo or quotation'} title={lang === 'ar' ? 'إرفاق ملف' : 'Attach a drawing, photo or quotation'}
          className="grid h-9 w-9 shrink-0 place-items-center rounded-lg text-primary transition-colors hover:bg-primary/10 disabled:opacity-40"
          disabled={analyzing || thinking} onClick={() => fileRef.current && fileRef.current.click()}>◫</button>
        <button type="button" aria-label={lang === 'ar' ? 'التسجيل الصوتي' : 'Speak your request'} aria-pressed={rec} title={lang === 'ar' ? 'التسجيل الصوتي' : 'Speak your request'}
          className={cn('grid h-9 w-9 shrink-0 place-items-center rounded-lg transition-colors hover:bg-primary/10', rec ? 'text-red-400' : 'text-primary')}
          onClick={rec ? stopRec : startRec}>{voxBusy ? '…' : (rec ? '◉' : '◎')}</button>
        <textarea className="flex-1 resize-none rounded-xl border border-border bg-secondary/40 px-3 py-2 text-[13.5px] text-foreground outline-none focus:border-primary/60"
          rows={1} aria-label={lang === 'ar' ? 'رسالة إلى المساعد' : 'Message the assistant'}
          placeholder={rec ? (lang === 'ar' ? 'أستمع… اضغط الميكروفون للإيقاف' : 'Listening… tap the mic to stop') : (lang === 'ar' ? 'راسل المساعد…' : 'Message the assistant…')}
          value={input} onChange={(e) => setInput(e.target.value)} onKeyDown={onKey} />
        <Button className="shrink-0" disabled={thinking || analyzing || !input.trim()} onClick={send}>{lang === 'ar' ? 'إرسال' : 'Send'}</Button>
      </div>
    </div>
  </div>);
}
