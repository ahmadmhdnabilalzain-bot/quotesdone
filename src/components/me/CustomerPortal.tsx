// @ts-nocheck
'use client';
import { useEffect, useState, useRef } from 'react';
import { createClient } from '@supabase/supabase-js';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
// Spec §22 modules that were written and never mounted. Each renders ONLY fields the endpoint it
// names already returns; see the header comment in each file for the field-by-field provenance.
import { ProjectsModule } from '@/components/portal/projects';
import { SpendingIntelligence } from '@/components/portal/intelligence/SpendingIntelligence';
import { SupplierRelationshipCard, DiscoveryReachPanel } from '@/components/portal/suppliers/SupplierRelationship';
// The five surfaces the module agents exported and nothing mounted. Each fetches its own endpoint
// and owns its own empty state; the portal supplies only the token, the language and — where the
// surface can use them — rows it already holds, so nothing is fetched twice.
import { SpatialModule } from '@/components/portal/spatial';
import { DocumentVault } from '@/components/portal/documents';
import { CommunicationCenter } from '@/components/portal/comms';
import { ApprovalChain, OrdersList } from '@/components/portal/approvals';
import { PredictiveIntelligence, NegotiationAssistant } from '@/components/portal/predict';
// §2 the Company Digital Twin, §9 Supplier Discovery and §17 Customer AI Memory. fn_twin,
// v_digital_twin, customer_score and customer_preference were all built and read only by os_api —
// the staff console — so the customer could not see their own profile or correct it.
import { CompanyTwin, SupplierDiscovery, CustomerMemory } from '@/components/portal/twin';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
// expires_at / expired were served on every quote and never shown. The branch that phrases them
// decides whether a customer pays a reveal fee on a lapsed price, so it lives in a file that can be
// executed — see quoteExpiry.test.mjs — rather than inline in this one.
import { expiryOf } from './quoteExpiry';

// The customer portal is the page a paying customer uses. Its Supabase target was an inline
// fallback to the production ref, so an unconfigured preview signed real customers in against the
// LIVE database. supaEnv resolves it once and warns on fallback; see the note there.
import { SUPA_URL as URL, SUPA_ANON as ANON, SUPA_FN as FN } from '@/lib/supaEnv';
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
    my_requests:'My requests', messages:'Messages', projects:'Projects', back_requests:'← Back to requests', new_request:'+ New request', close:'Close',
    k_requests:'Requests', k_open:'Open', k_quotes:'Quotes received', k_avg:'Avg quotes/req', k_hired:'Hired', k_spend:'Spend',
    your_requests:'Your requests', no_requests:'No requests yet. ', post_first:'Post your first request', describe_job:' — describe the job in text, voice, a photo, or a drawing.',
    request_sent:'Request sent — matching you with suppliers now.', payment_confirmed:'Payment confirmed — supplier contact unlocked below.',
    payment_pending:'Your payment is still being processed. Please refresh this page in a moment — do not pay again. Keep this page open so we can finish confirming it.',
    payment_failed:"We couldn't confirm your payment yet. Please keep this page link and email management@quotesdone.com if you were charged.",
    mod_spatial:'Project room', mod_documents:'Documents', mod_approvals:'Approvals', mod_orders:'Orders',
    mod_predict:'What you may need next', mod_profile:'Company profile', mod_account:'Account', open_module:'Open', theme_light:'Light mode', theme_dark:'Dark mode',
    unread_message:'unread message', unread_messages:'unread messages',
    acct_title:'Your account', acct_sub:'What we hold for you, and the preferences this device remembers.',
    acct_name:'Name', acct_email:'Email', acct_phone:'Mobile', acct_locale:'Language on your profile', acct_since:'Customer since',
    acct_local_note:'Language and appearance are remembered on this device. We have no settings endpoint that writes them back to your profile yet, so nothing here is saved to your account.',
    acct_failed:'Could not load your account details.',
    attention_one:'decision needs your attention', attention_many:'decisions need your attention',
    attention_none:'Nothing needs your attention right now.',
    active_projects:'Active projects', projects_failed:"Couldn't load your projects just now.",
    no_projects:'No projects yet — group related requests into a project to track budget and progress. ',
    rfqs_open_of:'requests open', suppliers_engaged:'suppliers engaged', no_budget_set:'No budget set',
    budget_label:'Budget', no_target_date:'No target date set, so there is no timeline to measure yet.',
    timeline_progress:'of the timeline elapsed',
    savings_unknown:'Potential savings needs at least two quotes on one request before it can be measured.',
    savings_potential:'Potential savings across your quotes',
    search_requests:'Search your requests…', no_search_match:'No request matches that search.' },
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
    my_requests:'طلباتي', messages:'الرسائل', projects:'المشاريع', back_requests:'→ العودة إلى الطلبات', new_request:'+ طلب جديد', close:'إغلاق',
    k_requests:'الطلبات', k_open:'المفتوحة', k_quotes:'العروض المستلمة', k_avg:'متوسط العروض/طلب', k_hired:'المُتعاقد معهم', k_spend:'الإنفاق',
    your_requests:'طلباتك', no_requests:'لا توجد طلبات بعد. ', post_first:'انشر طلبك الأول', describe_job:' — صِف العمل نصًا أو صوتًا أو بصورة أو برسم.',
    request_sent:'تم إرسال الطلب — نطابقك مع المورّدين الآن.', payment_confirmed:'تم تأكيد الدفع — تم فتح بيانات تواصل المورّد أدناه.',
    payment_pending:'لا تزال عملية الدفع قيد المعالجة. يُرجى تحديث الصفحة بعد قليل — لا تدفع مرة أخرى. أبقِ هذه الصفحة مفتوحة حتى نُكمل التأكيد.',
    payment_failed:'تعذّر تأكيد عملية الدفع حتى الآن. يُرجى الاحتفاظ برابط هذه الصفحة ومراسلتنا على management@quotesdone.com إذا تم خصم المبلغ.',
    mod_spatial:'غرفة المشروع', mod_documents:'المستندات', mod_approvals:'الموافقات', mod_orders:'أوامر الشراء',
    mod_predict:'ما قد تحتاجه لاحقًا', mod_profile:'ملف الشركة', mod_account:'الحساب', open_module:'فتح', theme_light:'الوضع الفاتح', theme_dark:'الوضع الداكن',
    unread_message:'رسالة غير مقروءة', unread_messages:'رسائل غير مقروءة',
    acct_title:'حسابك', acct_sub:'ما نحتفظ به لك، والتفضيلات التي يتذكرها هذا الجهاز.',
    acct_name:'الاسم', acct_email:'البريد الإلكتروني', acct_phone:'الجوال', acct_locale:'اللغة في ملفك', acct_since:'عميل منذ',
    acct_local_note:'تُحفظ اللغة والمظهر على هذا الجهاز فقط. لا يوجد لدينا حتى الآن نقطة نهاية لحفظ الإعدادات في ملفك، لذا لا يُحفظ أي شيء هنا في حسابك.',
    acct_failed:'تعذّر تحميل تفاصيل حسابك.',
    attention_one:'قرار بحاجة إلى انتباهك', attention_many:'قرارات بحاجة إلى انتباهك',
    attention_none:'لا شيء يحتاج انتباهك الآن.',
    active_projects:'المشاريع النشطة', projects_failed:'تعذّر تحميل مشاريعك الآن.',
    no_projects:'لا توجد مشاريع بعد — اجمع الطلبات المرتبطة في مشروع لتتبع الميزانية والتقدّم. ',
    rfqs_open_of:'طلب مفتوح', suppliers_engaged:'مورّد مشارك', no_budget_set:'لم تُحدَّد ميزانية',
    budget_label:'الميزانية', no_target_date:'لم يُحدَّد تاريخ مستهدف، فلا يوجد جدول زمني لقياسه بعد.',
    timeline_progress:'من الجدول الزمني مضى',
    savings_unknown:'يحتاج قياس التوفير المحتمل إلى عرضين على الأقل لنفس الطلب.',
    savings_potential:'التوفير المحتمل عبر عروضك',
    search_requests:'ابحث في طلباتك…', no_search_match:'لا يوجد طلب يطابق هذا البحث.' }
};
const t = (lang, k) => (T[lang] && T[lang][k]) || T.en[k] || k;
const aed = (n) => 'AED ' + Number(n || 0).toLocaleString('en-AE', { maximumFractionDigits: 0 });
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
// STILL DERIVED IN THE BROWSER, AND THAT IS A KNOWN GAP. public.inquiries carries pipeline_stage
// and stage_changed_at and company_event records the lifecycle, but customer_api's my_inquiries
// column list does not include pipeline_stage, so the server's own recorded stage cannot be shown
// until that select is widened.
const RFQ_STAGES = {
  en: ['Created', 'Sent', 'Quotes received', 'AI analysis', 'Awarded'],
  ar: ['أُنشئ', 'أُرسل', 'وردت العروض', 'تحليل ذكي', 'تم التعاقد'],
};
const rfqStageIdx = (inq, quotes) => {
  if (inq && (inq.status === 'completed' || inq.hired_supplier_id)) return 4;
  const n = (quotes || []).length;
  if (n >= 2) return 3;
  if (n >= 1) return 2;
  return String(inq && inq.status) === 'draft' ? 0 : 1;
};
// Pre-reveal, customer_api returns a coarse rating BAND ('4.5+', '4.0-4.5', ...) instead of a number.
// Bands are looked up here first so a banded string is never handed to Number() (which yields NaN).
const RATING_BANDS = { '4.5+': 4.75, '4.0-4.5': 4.25, '3.5-4.0': 3.75, 'below 3.5': 3.0 };
const ratingScoreOf = (r) => { if (r == null) return 60; const b = RATING_BANDS[String(r).trim()]; if (b != null) return Math.round((b / 5) * 100); const n = Number(r); return Number.isFinite(n) ? Math.round((n / 5) * 100) : 60; };
const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Umm Al Quwain', 'Fujairah'];
const fileB64 = (f) => new Promise((res) => { const rd = new FileReader(); rd.onloadend = () => res(String(rd.result).split(',')[1] || ''); rd.readAsDataURL(f); });
function ensurePdfjs() { return new Promise((res, rej) => { if (window.pdfjsLib) return res(window.pdfjsLib); const sc = document.createElement('script'); sc.src = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js'; sc.onload = () => { try { window.pdfjsLib.GlobalWorkerOptions.workerSrc = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js'; } catch (_e) {} res(window.pdfjsLib); }; sc.onerror = rej; document.head.appendChild(sc); }); }
async function fileToImages(file) {
  const b64 = await fileB64(file);
  if (file.type && file.type.startsWith('image/')) return { images: [{ mime: file.type, data: b64 }], b64, mime: file.type };
  if (file.type === 'application/pdf') {
    try { const L = await ensurePdfjs(); const raw = atob(b64); const arr = new Uint8Array(raw.length); for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
      const pdf = await L.getDocument({ data: arr }).promise; const out = []; const n = Math.min(pdf.numPages, 6);
      for (let pnum = 1; pnum <= n; pnum++) { const pg = await pdf.getPage(pnum); const vp = pg.getViewport({ scale: 1.8 }); const c = document.createElement('canvas'); c.width = vp.width; c.height = vp.height; await pg.render({ canvasContext: c.getContext('2d'), viewport: vp }).promise; out.push({ mime: 'image/jpeg', data: c.toDataURL('image/jpeg', 0.8).split(',')[1] }); }
      return { images: out, b64, mime: 'application/pdf' };
    } catch (_e) { return { images: [], b64, mime: 'application/pdf' }; }
  }
  return { images: [], b64, mime: file.type || 'application/octet-stream' };
}
function encodeWav(samples, rate) {
  const buffer = new ArrayBuffer(44 + samples.length * 2); const view = new DataView(buffer);
  const ws = (o, str) => { for (let i = 0; i < str.length; i++) view.setUint8(o + i, str.charCodeAt(i)); };
  ws(0, 'RIFF'); view.setUint32(4, 36 + samples.length * 2, true); ws(8, 'WAVE'); ws(12, 'fmt '); view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true); view.setUint32(24, rate, true); view.setUint32(28, rate * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true); ws(36, 'data'); view.setUint32(40, samples.length * 2, true);
  let o = 44; for (let i = 0; i < samples.length; i++) { const x = Math.max(-1, Math.min(1, samples[i])); view.setInt16(o, x < 0 ? x * 0x8000 : x * 0x7FFF, true); o += 2; }
  return buffer;
}
async function blobToWavB64(blob) {
  const AC = window.AudioContext || window.webkitAudioContext; const ac = new AC();
  const buf = await ac.decodeAudioData(await blob.arrayBuffer());
  const rate = 16000; const off = new OfflineAudioContext(1, Math.ceil(buf.duration * rate), rate);
  const src = off.createBufferSource(); src.buffer = buf; src.connect(off.destination); src.start();
  const rendered = await off.startRendering(); const pcm = rendered.getChannelData(0);
  const wav = encodeWav(pcm, rate); const bytes = new Uint8Array(wav); let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

const S = {
  center: 'grid place-items-center min-h-[70vh] p-5',
  h1: 'text-xl font-extrabold text-foreground',
  h2: 'text-[15px] font-bold text-foreground',
  sub: 'text-[13px] leading-relaxed text-muted-foreground',
  hint: 'text-xs text-muted-foreground my-2 leading-relaxed',
  err: 'text-[13px] text-red-300 mt-2',
  note: 'rounded-lg border border-primary/35 bg-primary/10 text-primary px-3.5 py-2.5 mb-3.5 text-[13px] font-semibold',
  wrap: 'max-w-[1040px] mx-auto p-[22px]',
  frow: 'flex gap-2.5 flex-wrap mt-2.5',
  tabsWrap: 'inline-flex flex-wrap gap-1.5 rounded-xl bg-secondary/40 p-1',
  tab: 'rounded-md px-3.5 py-2 text-[13px] font-semibold text-muted-foreground cursor-pointer border-0 bg-transparent',
  tabOn: 'bg-primary/15 text-primary',
  list: 'flex flex-col gap-3',
  field: 'mt-3 flex h-[42px] w-full rounded-md border border-input bg-transparent px-3 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring',
  area: 'mt-3 flex w-full rounded-md border border-input bg-transparent px-3 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring resize-y',
  fileInput: 'text-sm text-muted-foreground file:mr-3 file:rounded-md file:border-0 file:bg-secondary file:px-3 file:py-1.5 file:text-sm file:font-medium file:text-secondary-foreground hover:file:bg-secondary/80',
};

export function CustomerPortal() {
  const [lang, setLangState] = useState('en');
  const [token, setToken] = useState('');
  const [phase, setPhase] = useState('login');
  const [mounted, setMounted] = useState(false);
  // SPEC §21 asks for dark mode as an OPTION. The portal was served under html{color-scheme:dark}
  // with no light branch anywhere in globals.css, so "dark" was a decision made FOR the customer and
  // there was nothing to switch to. The light palette is a data-theme branch on .osx (globals.css);
  // this is the control that sets it, and the choice is remembered per device.
  const [theme, setTheme] = useState('dark');
  useEffect(() => {
    setMounted(true);
    try { const th = localStorage.getItem('qd-theme'); if (th === 'light' || th === 'dark') setTheme(th); } catch (_e) {}
    try { const l = initLang(); if (l !== 'en') setLangState(l); } catch (_e) {}
    try { const tk = localStorage.getItem('qd-cust-token'); if (tk) { setToken(tk); setPhase('app'); } } catch (_e) {}
    SB.auth.getSession().then(({ data }) => { const ss = data.session; if (ss && ss.access_token) { setToken(ss.access_token); try { localStorage.setItem('qd-cust-token', ss.access_token); if (ss.refresh_token) localStorage.setItem('qd-cust-refresh', ss.refresh_token); } catch (_e) {} setPhase('app'); } }).catch(() => {});
  }, []);
  const setLang = (l) => { try { localStorage.setItem('qd-lang', l); } catch (_e) {} setLangState(l); };
  const swapTheme = () => { const next = theme === 'dark' ? 'light' : 'dark'; try { localStorage.setItem('qd-theme', next); } catch (_e) {} setTheme(next); };
  // THE STORED PROFILE LOCALE. customers.locale has existed all along and the portal could not
  // honour it: my_inquiries did not serve it (fixed 5 Aug 2026) and this component decided language
  // from localStorage['qd-lang'] and the NEXT_LOCALE cookie alone. An Arabic customer who set their
  // language once got English on every new device, and the Arabic journey exercised a code path the
  // portal could never reach.
  //
  // PRECEDENCE MATTERS: an explicit choice on THIS device wins. setLang writes qd-lang, so if that
  // key exists the customer has chosen, and a profile field must not override a preference they set
  // seconds ago. Only when they have chosen nothing here does the stored locale apply.
  const onServedLocale = (l) => {
    if (l !== 'ar' && l !== 'en') return;
    try { if (localStorage.getItem('qd-lang')) return; } catch (_e) { return; }
    setLangState(l);
  };
  const onAuth = (access, refresh) => { try { localStorage.setItem('qd-cust-token', access || ''); if (refresh) localStorage.setItem('qd-cust-refresh', refresh); } catch (_e) {} setToken(access || ''); setPhase('app'); if (access) { try { SB.auth.setSession({ access_token: access, refresh_token: refresh || '' }).catch(() => {}); } catch (_e) {} } };
  const doSignOut = () => { try { localStorage.removeItem('qd-cust-token'); localStorage.removeItem('qd-cust-refresh'); } catch (_e) {} setToken(''); setPhase('login'); try { SB.auth.signOut().catch(() => {}); } catch (_e) {} };
  const rtl = lang === 'ar';
  if (!mounted) return null;
  return (<div dir={rtl ? 'rtl' : 'ltr'} data-theme={theme} className="osx min-h-screen bg-background text-foreground" style={{ fontFamily: 'Inter, system-ui, sans-serif' }}>
    <header className="sticky top-0 z-10 flex items-center justify-between px-5 py-3.5 bg-card/70 backdrop-blur border-b border-border">
      <a className="text-base font-extrabold text-foreground no-underline" href="/">QuotesDone <span className="text-primary font-bold">{t(lang, 'brand_sub')}</span></a>
      <div className="flex gap-2 items-center">
        <Button asChild variant="outline" size="sm"><a href="/">{t(lang, 'home')}</a></Button>
        <Button variant="outline" size="sm" onClick={() => setLang(rtl ? 'en' : 'ar')}>{rtl ? 'EN' : 'عربي'}</Button>
        <Button variant="outline" size="sm" onClick={swapTheme} aria-label={theme === 'dark' ? t(lang, 'theme_light') : t(lang, 'theme_dark')} title={theme === 'dark' ? t(lang, 'theme_light') : t(lang, 'theme_dark')}>{theme === 'dark' ? '☀' : '☾'}</Button>
        {phase === 'app' && <Button variant="outline" size="sm" onClick={doSignOut}>{t(lang, 'signout')}</Button>}
      </div>
    </header>
    {!mounted ? <div className={S.center}>{t(lang, 'loading')}</div> : (<>
      {phase === 'login' && <Login onAuth={onAuth} lang={lang} />}
      {phase === 'app' && <Authed token={token} lang={lang} onSignOut={doSignOut} onServedLocale={onServedLocale} />}
    </>)}
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
  return (<div className={S.center}><Card className="w-full max-w-[400px] p-5">
    <div className={cn(S.tabsWrap, 'mb-3.5')}><button className={cn(S.tab, !isSignup && S.tabOn)} onClick={() => swap('signin')}>{t(lang, 'tab_signin')}</button><button className={cn(S.tab, isSignup && S.tabOn)} onClick={() => swap('signup')}>{t(lang, 'tab_signup')}</button></div>
    <div className={S.h1}>{isSignup ? t(lang, 'create_account_title') : t(lang, 'welcome_back')}</div>
    <div className={cn(S.sub, 'mt-1')}>{isSignup ? t(lang, 'signup_sub') : t(lang, 'signin_sub')}</div>
    {step === 'id' ? (<><Input className="mt-3" placeholder={isSignup ? t(lang, 'email_address') : t(lang, 'email_or_mobile')} value={id} onChange={(e) => setId(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && send()} /><Button className="w-full mt-3" disabled={busy} onClick={send}>{busy ? t(lang, 'sending') : (isSignup ? t(lang, 'create_my_account') : t(lang, 'send_code'))}</Button></>)
      : (<><Input className="mt-3" placeholder={t(lang, 'code_placeholder')} value={code} onChange={(e) => setCode(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && verify()} /><div className={S.hint}>{t(lang, 'junk_note')}</div><Button className="w-full mt-3" disabled={busy} onClick={verify}>{busy ? t(lang, 'verifying') : (isSignup ? t(lang, 'verify_continue') : t(lang, 'verify_signin'))}</Button><Button variant="link" className="mt-2 px-0 h-auto" onClick={() => { setStep('id'); setCode(''); setMsg(''); }}>{t(lang, 'use_diff')}</Button></>)}
    {msg && <div className={S.err}>{msg}</div>}
  </Card></div>);
}
function Authed({ token, lang, onSignOut, onServedLocale }) {
  const [k, setK] = useState(null); const [err, setErr] = useState('');
  const load = () => { setErr(''); call('kyc', { action: 'state' }, token).then((j) => { if (j && j.error === 'unauthorized') setErr('unauth'); else setK(j || {}); }).catch(() => setErr('net')); };
  useEffect(() => { load(); }, [token]);
  if (err === 'unauth') return <div className={S.center}><Card className="w-full max-w-[400px] p-5"><div className={S.sub}>{t(lang, 'session_expired')}</div><Button className="w-full mt-3" onClick={onSignOut}>{t(lang, 'tab_signin')}</Button></Card></div>;
  if (err) return <div className={S.center}><Card className="w-full max-w-[400px] p-5"><div className={S.sub}>{t(lang, 'load_failed')}</div><Button className="w-full mt-3" onClick={load}>{t(lang, 'retry')}</Button></Card></div>;
  if (!k) return <div className={S.center}>{t(lang, 'loading')}</div>;
  const complete = k.full_name && k.phone_verified && k.email_verified && k.terms_signed;
  if (!complete) return <ProfileGate token={token} lang={lang} onDone={load} />;
  return <Dashboard token={token} lang={lang} onServedLocale={onServedLocale} />;
}
function ProfileGate({ token, lang, onDone }) {
  const [st, setSt] = useState(null);
  const [full_name, setFullName] = useState(''); const [phone, setPhone] = useState(''); const [dob, setDob] = useState('');
  const [emCode, setEmCode] = useState(''); const [smsCode, setSmsCode] = useState(''); const [sentSms, setSentSms] = useState(false); const [sentEmail, setSentEmail] = useState(false);
  const [terms, setTerms] = useState(false); const [busy, setBusy] = useState(''); const [msg, setMsg] = useState('');
  const load = () => call('kyc', { action: 'state' }, token).then((j) => { setSt(j); setFullName((x) => x || j.full_name || ''); setPhone((x) => x || j.phone || ''); setDob((x) => x || j.dob || ''); }).catch(() => setMsg(t(lang, 'load_failed')));
  useEffect(() => { load(); }, []);
  if (!st) return <div className={S.center}>{t(lang, 'loading')}</div>;
  const saveProfile = async () => { setBusy('save'); setMsg(''); const j = await call('kyc', { action: 'save_customer', full_name, phone, dob }, token); setBusy(''); if (j && j.ok) load(); else setMsg((j && j.error) || t(lang, 'load_failed')); };
  const sendSms = async () => { if (!phone) { setMsg(t(lang, 'enter_mobile_first')); return; } setBusy('sms'); setMsg(''); const j = await call('kyc', { action: 'send_sms', phone }, token); setBusy(''); if (j && j.ok) setSentSms(true); else setMsg((j && j.error) || t(lang, 'err_code_send')); };
  const verifySms = async () => { setBusy('vsms'); setMsg(''); const j = await call('kyc', { action: 'verify_sms', phone, code: smsCode }, token); setBusy(''); if (j && j.ok) load(); else setMsg((j && j.error) || t(lang, 'err_incorrect')); };
  const sendEmailCode = async () => { setBusy('em'); setMsg(''); const j = await call('kyc', { action: 'send_email' }, token); setBusy(''); if (j && j.ok) setSentEmail(true); else setMsg((j && j.error) || t(lang, 'err_code_send')); };
  const verifyEmail = async () => { setBusy('vem'); setMsg(''); const j = await call('kyc', { action: 'verify_email', code: emCode }, token); setBusy(''); if (j && j.ok) load(); else setMsg((j && j.error) || t(lang, 'err_incorrect')); };
  const acceptTerms = async () => { if (!terms) { setMsg(t(lang, 'must_accept')); return; } setBusy('terms'); setMsg(''); const j = await call('kyc', { action: 'accept_terms' }, token); setBusy(''); if (j && j.ok) { onDone(); } else setMsg((j && j.error) || t(lang, 'load_failed')); };
  const profileDone = st.full_name && st.phone && st.dob;
  return (<div className={S.center}><Card className="w-full max-w-[440px] p-5">
    <div className={S.h1}>{t(lang, 'gate_title')}</div>
    <div className={S.sub}>{t(lang, 'gate_sub')}</div>
    <Input className="mt-3" placeholder={t(lang, 'full_name')} value={full_name} onChange={(e) => setFullName(e.target.value)} />
    <Input className="mt-3" placeholder={t(lang, 'mobile_ph')} value={phone} onChange={(e) => setPhone(e.target.value)} />
    <div className={cn(S.sub, 'mt-3 mb-1')}>{t(lang, 'dob_label')}</div>
    <Input type="date" className="mt-0" style={{ colorScheme: 'dark' }} value={dob} onChange={(e) => setDob(e.target.value)} />
    {!profileDone && <Button className="w-full mt-3" disabled={busy === 'save'} onClick={saveProfile}>{busy === 'save' ? t(lang, 'saving') : t(lang, 'save_details')}</Button>}
    {profileDone && <>
      <div className={cn(S.h2, 'mt-4')}>{t(lang, 'verify_mobile')} {st.phone_verified ? <span className="text-primary text-[12px] font-bold ml-1.5">{t(lang, 'verified')}</span> : null}</div>
      {!st.phone_verified && (!sentSms ? <Button size="sm" className="mt-3" disabled={busy === 'sms'} onClick={sendSms}>{busy === 'sms' ? t(lang, 'sending') : t(lang, 'send_sms')}</Button>
        : <><div className={S.hint}>{t(lang, 'junk_note')}</div><div className={S.frow}><Input placeholder={t(lang, 'code_placeholder')} value={smsCode} onChange={(e) => setSmsCode(e.target.value)} /><Button size="sm" disabled={busy === 'vsms'} onClick={verifySms}>{t(lang, 'verify')}</Button></div></>)}
      <div className={cn(S.h2, 'mt-4')}>{t(lang, 'verify_email_h')} {st.email_verified ? <span className="text-primary text-[12px] font-bold ml-1.5">{t(lang, 'verified')}</span> : null}</div>
      {!st.email_verified && (!sentEmail ? <Button size="sm" className="mt-3" disabled={busy === 'em'} onClick={sendEmailCode}>{busy === 'em' ? t(lang, 'sending') : t(lang, 'send_email_code')}</Button>
        : <><div className={S.hint}>{t(lang, 'junk_note')}</div><div className={S.frow}><Input placeholder={t(lang, 'code_placeholder')} value={emCode} onChange={(e) => setEmCode(e.target.value)} /><Button size="sm" disabled={busy === 'vem'} onClick={verifyEmail}>{t(lang, 'verify')}</Button></div></>)}
      {st.phone_verified && st.email_verified && <>
        <label className="flex gap-2 items-center mt-4 text-[13px] text-muted-foreground"><input type="checkbox" checked={terms} onChange={(e) => setTerms(e.target.checked)} /> {t(lang, 'accept_pre')}<a href="/terms" target="_blank" rel="noopener" className="text-primary font-semibold">{t(lang, 'terms_link')}</a>{t(lang, 'accept_post')}</label>
        <Button className="w-full mt-3" disabled={busy === 'terms'} onClick={acceptTerms}>{busy === 'terms' ? t(lang, 'finishing') : t(lang, 'finish_continue')}</Button>
      </>}
    </>}
    {msg && <div className={S.err}>{msg}</div>}
  </Card></div>);
}
function Dashboard({ token, lang, onServedLocale }) {
  const [ov, setOv] = useState(null); const [data, setData] = useState(null); const [err, setErr] = useState(''); const [note, setNote] = useState(''); const [showNew, setShowNew] = useState(false);
  // WHY THIS IS NO LONGER A `view`. Messages and Projects were whole-surface early returns: opening
  // either REPLACED the dashboard, which is the full-page navigation §21 asks the portal not to
  // have — and it also stranded the intake assistant, because a branch that returns before the
  // assistant's mount can never render it. Every module now opens in a window OVER the dashboard,
  // so the KPIs, the alerts and the assistant stay mounted underneath and no module needs a
  // "back to requests" button to undo a navigation that never happened.
  const [view, setView] = useState('');
  // §21: bound to THIS render's overview so the bar re-sorts when the layout does.
  const barOrder = (id) => moduleBarOrder(id, ov && ov.layout);
  const [pd, setPd] = useState(null); const [pdFailed, setPdFailed] = useState(false);
  const [qtext, setQtext] = useState('');
  // my_inquiries carries the customer's stored locale (customer_api, 5 Aug 2026). This is the only
  // call the portal makes that has it — `me` serves it too, but the portal never calls `me`, which
  // is why the field was on the wire for months with nothing listening. The handler upstream
  // decides whether it applies; an explicit choice on this device still wins.
  const loadInq = () => call('customer_api', { action: 'my_inquiries' }, token).then((j) => {
    setData(j);
    if (j && j.locale && onServedLocale) onServedLocale(j.locale);
  });
  const loadOv = () => call('customer_portal', { action: 'overview', lang }, token).then((j) => { if (j && j.ok) setOv(j); else setErr((j && (j.error || j.hint)) || ''); });
  // THE ROLLUP THAT WAS COMPUTED AND THROWN AWAY. project_api action='dashboard' recomputes, on
  // every call, this customer's project_summary rows (each carrying rfq_count, rfq_open,
  // budget_total, timeline_pct and supplier_count) plus an avg_savings_pct measured across the
  // spread of quotes on their own RFQs — and no file in src/ has ever called it. The Command
  // Center the spec asks for in §1 and §4 is made of exactly these numbers.
  const loadPd = () => call('project_api', { action: 'dashboard' }, token)
    .then((j) => { if (j && j.ok && j.dashboard) setPd(j.dashboard); else setPdFailed(true); })
    .catch(() => setPdFailed(true));
  const refresh = () => { loadInq(); loadOv(); loadPd(); };
  useEffect(() => {
    loadOv();
    loadInq();
    loadPd();
    const sid = new URLSearchParams(location.search).get('session_id');
    // Only drop session_id from the URL once the payment is confirmed — it is the customer's
    // only reference for retrying or chasing a payment that did not go through.
    if (sid) { call('stripe_confirm', { session_id: sid }, token).then((j) => { if (j && j.ok) { history.replaceState({}, '', location.pathname); setNote(t(lang, 'payment_confirmed')); loadInq(); } else if (j && j.pending) { setNote(t(lang, 'payment_pending')); } else { setNote(t(lang, 'payment_failed')); } }).catch(() => setNote(t(lang, 'payment_failed'))); }
  }, [token]);
  // QUOTES ARRIVE WHILE THE CUSTOMER IS LOOKING AT THE PAGE. Suppliers answer asynchronously and
  // nothing pushes that to the browser, so until now the only way to see a new quote was to reload
  // — on the one screen whose whole purpose is waiting for quotes. The tab-focus refetch is the
  // one that matters (a customer comes back to the tab after doing something else); the interval
  // is deliberately slow and only reloads the RFQ list, which is where a quote lands. Both are
  // skipped while the tab is hidden, so a backgrounded portal costs nothing.
  useEffect(() => {
    const visible = () => typeof document === 'undefined' || document.visibilityState === 'visible';
    const onVis = () => { if (visible()) { loadInq(); loadOv(); } };
    document.addEventListener('visibilitychange', onVis);
    const iv = setInterval(() => { if (visible()) loadInq(); }, 60000);
    return () => { document.removeEventListener('visibilitychange', onVis); clearInterval(iv); };
  }, [token]);
  if (!ov && !data) return <div className={S.center}>{t(lang, 'loading_requests')}</div>;
  const s = (ov && ov.stats) || {}; const inqs = (data && data.inquiries) || [];
  const alertsCount = Number((ov && ov.alerts_count) ?? ((ov && ov.alerts) || []).length) || 0;
  const projects = (pd && Array.isArray(pd.projects)) ? pd.projects : [];
  const savingsPct = pd ? pd.avg_savings_pct : null;
  // The filter is over the rows already on screen, so it costs no request and cannot disagree with
  // the list it filters. Matching is over the fields a customer would actually recall about their
  // own request — what it was for, where, and its reference.
  const needle = qtext.trim().toLowerCase();
  const shown = needle ? inqs.filter((i) => [i.summary, i.category, i.emirate, i.status, i.rfq_no].some((f) => String(f || '').toLowerCase().includes(needle))) : inqs;
  return (<div className={cn(S.wrap, 'pb-24 sm:pb-6')}>
    {/* §1 asks the opening screen to greet by time of day AND company name. The name was already on
        the wire (customer_portal emits customer.name) and rendered alone; the hour is the client's,
        because the server does not know which timezone the customer is sitting in. */}
    <div className="flex justify-between items-center flex-wrap gap-3 mb-3"><div><div className="text-[22px] font-extrabold text-foreground">{greetingOf(lang) + ((ov && ov.customer && ov.customer.name) ? (', ' + ov.customer.name) : '')}</div><div className={S.sub}>{t(lang, 'my_requests')}</div></div><div className="flex gap-2"><Button size="sm" onClick={() => setShowNew((v) => !v)}>{showNew ? t(lang, 'close') : t(lang, 'new_request')}</Button></div></div>
    {/* THE ATTENTION LINE. customer_portal has returned alerts_count on every overview call since
        the portal was written and nothing read it — the cards were rendered, the sentence that says
        how many decisions are waiting was not. Zero is stated as zero rather than hidden, because
        "nothing needs you right now" is the answer a customer opening the portal wants most. */}
    <div className={cn('rounded-lg border px-3.5 py-2.5 mb-3 text-[13px] font-semibold', alertsCount > 0 ? 'border-primary/35 bg-primary/10 text-primary' : 'border-border bg-secondary/20 text-muted-foreground')}>
      {alertsCount > 0 ? (alertsCount + ' ' + t(lang, alertsCount === 1 ? 'attention_one' : 'attention_many')) : t(lang, 'attention_none')}
    </div>
    {/* §1 THE ASSISTANT'S OWN SENTENCE. The count above says HOW MANY; this says WHICH ONE and why
        it is first. It is written by customer_portal — one line built from the highest-severity
        alert outstanding — rather than assembled here, so the sentence the customer reads is the
        sentence the server can be held to. When nothing is outstanding it says so plainly. */}
    {ov && ov.headline ? (
      <div className="mb-3 flex items-start gap-2 rounded-lg border border-border bg-card px-3.5 py-2.5">
        <span aria-hidden className="mt-[1px] text-[13px]">🤖</span>
        <p className="text-[13.5px] text-foreground">{ov.headline}</p>
      </div>
    ) : null}
    {/* THE MODULE BAR. A row on a desktop, a bottom-anchored bar on a phone — where a thumb is.
        §21 ORDERS IT PER CUSTOMER. customer_portal returns layout.order, ranked by what this
        customer actually has outstanding (approvals blocking work first, then live projects), and
        a panel the customer pinned by hand comes back at the front and is never re-ranked
        underneath them. An unknown key from the server is IGNORED rather than rendered as a dead
        button, and any module the server did not mention is appended in its declared order, so a
        module added to the product later cannot disappear because the layout predates it. */}
    <div className="fixed bottom-0 inset-x-0 z-20 flex gap-1.5 overflow-x-auto border-t border-border bg-card/90 backdrop-blur px-3 py-2 sm:static sm:mb-4 sm:flex-wrap sm:border-0 sm:bg-transparent sm:px-0 sm:py-0 sm:backdrop-blur-none">
      <Button size="sm" variant="secondary" className="shrink-0 transition-colors duration-200" style={{ order: barOrder('home') }} onClick={() => setView('home')}>{t(lang, 'home')}</Button>
      <Button size="sm" variant="secondary" className="shrink-0 transition-colors duration-200" style={{ order: barOrder('projects') }} onClick={() => setView('projects')}>{t(lang, 'projects')}</Button>
      <Button size="sm" variant="secondary" className="shrink-0 transition-colors duration-200" style={{ order: barOrder('spatial') }} onClick={() => setView('spatial')}>{t(lang, 'mod_spatial')}</Button>
      <Button size="sm" variant="secondary" className="shrink-0 transition-colors duration-200" style={{ order: barOrder('documents') }} onClick={() => setView('documents')}>{t(lang, 'mod_documents')}</Button>
      <Button size="sm" variant="secondary" className="shrink-0 transition-colors duration-200" style={{ order: barOrder('messages') }} onClick={() => setView('messages')}>{t(lang, 'messages')}<UnreadBadge token={token} lang={lang} /></Button>
      <Button size="sm" variant="secondary" className="shrink-0 transition-colors duration-200" style={{ order: barOrder('orders') }} onClick={() => setView('orders')}>{t(lang, 'mod_orders')}</Button>
      <Button size="sm" variant="secondary" className="shrink-0 transition-colors duration-200" style={{ order: barOrder('approvals') }} onClick={() => setView('approvals')}>{t(lang, 'mod_approvals')}</Button>
      <Button size="sm" variant="secondary" className="shrink-0 transition-colors duration-200" style={{ order: barOrder('predict') }} onClick={() => setView('predict')}>{t(lang, 'mod_predict')}</Button>
      <Button size="sm" variant="secondary" className="shrink-0 transition-colors duration-200" style={{ order: barOrder('profile') }} onClick={() => setView('profile')}>{t(lang, 'mod_profile')}</Button>
      <Button size="sm" variant="secondary" className="shrink-0 transition-colors duration-200" style={{ order: barOrder('account') }} onClick={() => setView('account')}>{t(lang, 'mod_account')}</Button>
    </div>
    {/* project_api ships seven customer-authed actions and had zero callers in src/. Linking an RFQ
        to a project needs the customer's own RFQ list, which this component already holds —
        top-level rows only, since a child of a combined project is sourced through its parent. */}
    <ModuleWindow id={view} onClose={() => setView('home')} token={token} lang={lang} inqs={inqs} onChanged={refresh} twin={ov && ov.twin} />
    {note && <div className={S.note}>{note}</div>}
    {showNew && <NewRequest token={token} onDone={() => { setShowNew(false); refresh(); setNote(t(lang, 'request_sent')); }} onCancel={() => setShowNew(false)} />}
    {ov && !!(ov.alerts || []).length && <div className="flex flex-col gap-2 mb-4">{ov.alerts.map((a, i) => <div key={i} className={cn('rounded-lg border border-border bg-card px-3.5 py-3 flex flex-col gap-0.5 border-l-4', a.severity === 'high' ? 'border-l-red-500' : a.severity === 'medium' ? 'border-l-amber-400' : 'border-l-primary')}><b className="text-[13.5px] text-foreground">{a.title}</b><span className="text-muted-foreground text-xs">{a.detail}</span></div>)}</div>}
    {ov && <div className="grid grid-cols-2 md:grid-cols-6 gap-2.5 mb-4">
      <Kpi label={t(lang, 'k_requests')} v={s.inquiries_total ?? 0} /><Kpi label={t(lang, 'k_open')} v={s.open_inquiries ?? 0} /><Kpi label={t(lang, 'k_quotes')} v={s.quotes_received ?? 0} />
      <Kpi label={t(lang, 'k_avg')} v={s.avg_quotes_per_inquiry ?? 0} /><Kpi label={t(lang, 'k_hired')} v={s.deals ?? 0} /><Kpi label={t(lang, 'k_spend')} v={aed(s.total_spend)} />
    </div>}
    {/* §2 THE PROFILE, ON THE ENTRY SCREEN. Six KPI tiles say what the customer has DONE; the twin
        says who they ARE — industry, live projects, the suppliers they keep coming back to, the
        categories they actually buy, their approval chain, and how much of that profile we hold.
        It is the same object the Company profile window opens, rendered from the overview payload
        the dashboard already has, so opening the portal costs no extra call. */}
    {ov && ov.twin ? <div className="mb-4"><CompanyTwin twin={ov.twin} lang={lang === 'ar' ? 'ar' : 'en'} /></div> : null}
    {/* ── THE PROJECTS / FINANCIAL / SUPPLIER-NETWORK PANELS (§1, §4) ──────────────────────────
        Every figure below is nullable and every one of them says which absence is true rather than
        printing a zero that reads as a measurement. timeline_pct is null for a project with no
        target date, so no bar is drawn for it; supplier_count is a count and 0 is a real answer;
        avg_savings_pct is null until two quotes have landed on the same RFQ, and printing 0% there
        would tell a customer their price spread is zero when it is simply not yet known. */}
    <div className={cn(S.h2, 'mt-[18px] mb-1')}>{t(lang, 'active_projects')}</div>
    {pdFailed ? <Card className="p-5"><div className={S.sub}>{t(lang, 'projects_failed')}</div></Card>
      : !pd ? <Card className="p-5"><div className={S.sub}>{t(lang, 'loading')}</div></Card>
      : !projects.length ? <Card className="p-5"><div className={S.sub}>{t(lang, 'no_projects')}<button className="text-primary font-semibold" onClick={() => setView('projects')}>{t(lang, 'open_module')}</button></div></Card>
      : (<>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-2.5">
          {projects.map((p) => {
            const openN = Number(p.rfq_open) || 0, totalN = Number(p.rfq_count) || 0;
            const budget = p.budget_total == null ? null : Number(p.budget_total);
            const timeline = p.timeline_pct == null ? null : Math.max(0, Math.min(100, Number(p.timeline_pct)));
            return (<Card key={p.project_id} className="p-3.5 transition-colors duration-200">
              <div className="flex justify-between items-center gap-2"><b className="text-[13.5px] text-foreground">{p.name}</b><span className={cn(S.sub, 'capitalize')}>{p.status}</span></div>
              <div className={cn(S.sub, 'mt-1')}>{openN + ' / ' + totalN + ' ' + t(lang, 'rfqs_open_of')}{' · '}{(Number(p.supplier_count) || 0) + ' ' + t(lang, 'suppliers_engaged')}</div>
              <div className={cn(S.sub, 'mt-0.5')}>{budget == null ? t(lang, 'no_budget_set') : (t(lang, 'budget_label') + ': ' + aed(budget))}</div>
              {timeline == null
                ? <div className={cn(S.sub, 'mt-1 text-muted-foreground/70')}>{t(lang, 'no_target_date')}</div>

                : (<div className="mt-1.5">
                    <div className="h-1.5 rounded-full bg-secondary/60 overflow-hidden"><div className="h-full rounded-full bg-primary transition-[width] duration-500" role="progressbar" aria-valuenow={Math.round(timeline)} aria-valuemin={0} aria-valuemax={100} style={{ width: Math.round(timeline) + '%' }} /></div>
                    <div className={cn(S.sub, 'mt-0.5')}>{Math.round(timeline) + '% ' + t(lang, 'timeline_progress')}</div>
                  </div>)}
            </Card>);
          })}
        </div>
        <div className={cn(S.sub, 'mt-2')}>{savingsPct == null ? t(lang, 'savings_unknown') : (t(lang, 'savings_potential') + ': ' + savingsPct + '%')}</div>
      </>)}
    <div className={cn(S.h2, 'mt-[18px] mb-1')}>{t(lang, 'your_requests')}</div>
    {inqs.length > 0 && <input type="search" className={S.field} placeholder={t(lang, 'search_requests')} aria-label={t(lang, 'search_requests')} value={qtext} onChange={(e) => setQtext(e.target.value)} />}
    {!inqs.length ? <Card className="p-5"><div className={S.sub}>{t(lang, 'no_requests')}<button className="text-primary font-semibold" onClick={() => setShowNew(true)}>{t(lang, 'post_first')}</button>{t(lang, 'describe_job')}</div></Card>
      : !needle ? <div className={S.list}>{inqs.map((i) => <InquiryCard key={i.id} inq={i} token={token} lang={lang} onChange={refresh} />)}</div>
      : !shown.length ? <Card className="p-5"><div className={S.sub}>{t(lang, 'no_search_match')}</div></Card>
      : <div className={S.list}>{shown.map((i) => <InquiryCard key={i.id} inq={i} token={token} lang={lang} onChange={refresh} />)}</div>}
    {/* fn_customer_stats computes history_12m on EVERY overview call and nothing drew it; recharts
        and ui/chart.tsx were installed with no importers, so the customer product contained zero
        charts. Each chart states what is true when there is nothing to draw rather than rendering
        a flat line at zero, which reads as a real but quiet year. */}
    <SpendingIntelligence stats={s} inquiries={inqs} lang={lang === 'ar' ? 'ar' : 'en'} />
  </div>);
}
function InquiryCard({ inq, token, onChange, lang }) {
  if (inq.is_combined && Array.isArray(inq.children)) { return (<Card className="p-4 mb-3.5 border-primary/30"><div className="flex items-center gap-2 flex-wrap mb-1"><span className="text-[11px] font-semibold px-2 py-0.5 rounded-full bg-primary/10 text-primary">{lang === 'ar' ? 'مشروع متعدد التخصصات' : 'Combined project'}</span><span className={S.sub}>{lang === 'ar' ? (inq.children.length + ' طلب منفصل لموردين متخصصين') : (inq.children.length + ' separate requests to specialist suppliers')}</span></div>{inq.summary ? <div className={cn(S.sub, 'mb-2')}>{inq.summary}</div> : null}<div className="space-y-2.5">{inq.children.map((c) => <InquiryCard key={c.id} inq={c} token={token} onChange={onChange} lang={lang} />)}</div></Card>); }
  const [open, setOpen] = useState(false);
  const [canceling, setCanceling] = useState(false);
  const [editing, setEditing] = useState(false);
  const [eSummary, setESummary] = useState(inq.summary || '');
  const [eBudget, setEBudget] = useState(inq.budget || '');
  const [eEmirate, setEEmirate] = useState(inq.emirate || '');
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');
  const quotes = (inq.quotes || []).slice().sort((a, b) => (a.price || 0) - (b.price || 0));
  const concluded = ['completed', 'closed', 'cancelled'].includes(String(inq.status));
  const anyRevealed = quotes.some((qq) => qq.revealed);
  const vmap = (() => { const m = {}; if (!quotes.length) return m; const ps = quotes.map((q) => Number(q.price) || 0).filter((p) => p > 0); const minP = ps.length ? Math.min(...ps) : 0, maxP = ps.length ? Math.max(...ps) : 0; for (const q of quotes) { const p = Number(q.price) || 0; const priceScore = (!p || maxP === minP) ? 70 : Math.round(100 - ((p - minP) / (maxP - minP)) * 55); const ratingScore = ratingScoreOf(q.rating); const compScore = Math.min(100, 50 + (q.scope ? 20 : 0) + (q.warranty ? 10 : 0) + (q.lead_time ? 10 : 0) + (q.verified ? 10 : 0)); m[q.id] = Math.round(priceScore * 0.5 + ratingScore * 0.3 + compScore * 0.2); } return m; })();
  const bestId = quotes.length ? quotes.slice().sort((a, b) => (vmap[b.id] || 0) - (vmap[a.id] || 0))[0].id : null;
  const stepIdx = rfqStageIdx(inq, quotes);
  const doCancel = async (e) => { e.stopPropagation(); if (canceling) return; if (!confirm('Cancel this request? Suppliers will stop quoting.')) return; setCanceling(true); setErr(''); try { const j = await call('customer_api', { action: 'cancel_inquiry', inquiry_id: inq.id }, token); if (j && j.ok) { onChange(); } else { setErr((j && (j.message || j.error)) || 'Could not cancel. Please try again.'); setCanceling(false); } } catch (_e) { setErr('Could not cancel. Please check your connection and try again.'); setCanceling(false); } };
  const saveEdit = async () => { setSaving(true); setErr(''); try { const j = await call('customer_api', { action: 'edit_inquiry', inquiry_id: inq.id, patch: { summary: eSummary, budget: eBudget || null, emirate: eEmirate || null } }, token); if (j && j.ok) { setEditing(false); onChange(); } else { setErr((j && (j.message || j.error)) || 'Could not save changes.'); } } catch (_e) { setErr('Could not save changes. Please try again.'); } setSaving(false); };
  return (<Card className="p-5">
    {/* A11Y (5 Aug 2026). This was a bare <div onClick> - no role, no tabindex, not focusable. It is
        the control that opens a request, so a keyboard or screen-reader user could not open ANY of
        their own quotes: the core journey was unreachable without a mouse. Found by trying to click
        it in a browser; the accessibility tree simply had no node for it.
        role+tabIndex+onKeyDown rather than a real <button> because this element wraps <div>
        children, and <div> inside <button> is an invalid content model - with nothing in this repo
        rendering JSX in a test, that swap is the riskier fix. */}
    <div className="flex justify-between items-center gap-2.5 cursor-pointer" onClick={() => setOpen(!open)}
      role="button" tabIndex={0} aria-expanded={open}
      onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setOpen(!open); } }}>
      {/* rfq_no is on every my_inquiries row and was rendered nowhere, so the customer had no
          reference to quote back to us — only a uuid they never see. */}
      <div><b className="capitalize">{inq.category || 'Request'}</b>{inq.rfq_no ? <span className="ms-1.5 rounded bg-secondary/60 px-1.5 py-0.5 font-mono text-[11px] text-muted-foreground align-middle">{inq.rfq_no}</span> : null} - {inq.emirate || ''}{inq.boq && inq.boq.boq ? ' - BOQ ' + inq.boq.boq.length + ' items' : ''}
        <div className={S.sub}>{quotes.length} quote{quotes.length === 1 ? '' : 's'} - <span className="capitalize">{inq.status}</span>{inq.editable ? ' - editable ' + inq.edit_minutes_left + 'm' : ''}</div></div>
      <div className="text-right"><span className="text-primary font-semibold">{open ? (lang === 'ar' ? 'إخفاء التفاصيل' : 'Hide details') : (quotes.length ? (lang === 'ar' ? 'العروض والتفاصيل' : 'Open project') : (lang === 'ar' ? 'عرض التفاصيل' : 'Open project'))}</span></div>
    </div>
    {inq.summary && !editing && <div className={cn(S.sub, 'mt-1.5')}>{inq.summary}</div>}
    {editing && <div className="mt-2">
      <textarea className={S.area} rows={3} value={eSummary} onChange={(e) => setESummary(e.target.value)} placeholder="Describe your request" />
      <div className={S.frow}>
        <select className={S.field} style={{ colorScheme: 'dark', backgroundColor: 'hsl(205 46% 12%)', color: 'hsl(180 25% 94%)' }} value={eEmirate} onChange={(e) => setEEmirate(e.target.value)}><option value="" style={{ backgroundColor: '#0C2330', color: '#EAF4F2' }}>Emirate (optional)</option>{EMIRATES.map((em) => <option key={em} value={em} style={{ backgroundColor: '#0C2330', color: '#EAF4F2' }}>{em}</option>)}</select>
        <Input placeholder="Budget (optional)" value={eBudget} onChange={(e) => setEBudget(e.target.value)} />
      </div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5">
        <Button disabled={saving} onClick={(e) => { e.stopPropagation(); saveEdit(); }}>{saving ? 'Saving...' : 'Save changes'}</Button>
        <Button variant="link" className="px-0 h-auto" onClick={(e) => { e.stopPropagation(); setEditing(false); setErr(''); }}>Cancel edit</Button>
      </div>
    </div>}
    {!concluded && !anyRevealed && !editing && <div className="flex gap-2.5 flex-wrap items-center mt-2">
      {inq.editable && <Button variant="link" className="px-0 h-auto" onClick={(e) => { e.stopPropagation(); setESummary(inq.summary || ''); setEBudget(inq.budget || ''); setEEmirate(inq.emirate || ''); setEditing(true); }}>Edit request</Button>}
      <Button variant="link" className="px-0 h-auto text-red-400" disabled={canceling} onClick={doCancel}>{canceling ? 'Cancelling...' : 'Cancel request'}</Button>
    </div>}
    {err && <div className={S.err}>{err}</div>}
    <div className="flex items-center gap-1.5 mt-2 text-[11px] flex-wrap">{(lang === 'ar' ? RFQ_STAGES.ar : RFQ_STAGES.en).map((s, si) => (<span key={s} className={cn('flex items-center gap-1', si <= stepIdx ? 'text-primary font-semibold' : 'text-muted-foreground/70')}>{si > 0 ? <span className="text-muted-foreground/40">›</span> : null}<span className={cn('inline-block w-1.5 h-1.5 rounded-full', si <= stepIdx ? 'bg-primary' : 'bg-muted-foreground/40')} />{s}</span>))}</div>
    {open && <div className="mt-3 border-t border-border pt-3 flex flex-col gap-3">
      <Timeline inq={inq} quotes={quotes} anyRevealed={anyRevealed} lang={lang} />
      {/* §3 THE ASSISTANT AFTER THE REQUEST EXISTS. NewRequest unmounts the moment the RFQ is
          created, and the only other door — a chat thread — is gated on a PAID REVEAL, so a
          customer with a live RFQ and no revealed quote had no way to ask anything at all. This
          reopens the same inquiry_intake conversation against this RFQ, which is where a follow-up
          belongs: the assistant answers with the brief in front of it. */}
      <RfqAssistant inq={inq} token={token} lang={lang} onChanged={onChange} />
      <DetailFacts inq={inq} lang={lang} />
      {quotes.length >= 2 && <Comparison inqId={inq.id} token={token} lang={lang} />}
      {/* THE DEFECT THIS REPLACES. What stood here was one fixed sentence — "we matched you with
          suitable suppliers and will alert you the moment the first quote lands" — printed whenever
          quotes.length was 0. It said the same encouraging thing to a customer whose request had
          reached eight suppliers and to one whose request had reached NOBODY, and the second case is
          not a wait, it is a dead end the customer must be told about so they can widen the brief.
          matched_suppliers has been on the wire the whole time, carrying exactly that distinction,
          with a source comment saying so; grep for it in this file returned nothing.
          DiscoveryReachPanel renders reached===0 as its own outcome and never as encouragement. */}
      <DiscoveryReachPanel inquiry={inq} lang={lang === 'ar' ? 'ar' : 'en'} />
      {quotes.length > 0
        ? <div className="flex flex-col gap-2.5"><div className={cn(S.sub, 'font-semibold text-foreground')}>{lang === 'ar' ? ('العروض المستلمة (' + quotes.length + ')') : ('Quotes received (' + quotes.length + ')')}</div>{quotes.map((q) => <QuoteCard key={q.id} q={q} token={token} lang={lang} concluded={concluded} onChange={onChange} vscore={vmap[q.id]} best={q.id === bestId} hired={inq.hired_supplier_id} />)}</div>
        : null}
    </div>}
  </Card>);
}

// §3: the procurement assistant, reachable from a request that already exists.
//
// It calls inquiry_intake — the same routine that built the brief — rather than a second, thinner
// assistant, so the answers a customer gets after sending are answered by the thing that
// understands the brief. Collapsed by default: this sits inside an already-dense open request, and
// a chat box that is always expanded pushes the quotes the customer came to read off the screen.
function RfqAssistant({ inq, token, lang, onChanged }) {
  const [open2, setOpen2] = useState(false);
  const [q, setQ] = useState(''); const [busy, setBusy] = useState(false);
  const [turns, setTurns] = useState([]); const [err, setErr] = useState('');
  const ask = async () => {
    const text = q.trim(); if (!text || busy) return;
    setBusy(true); setErr(''); setQ('');
    setTurns((t) => [...t, { role: 'user', text }]);
    try {
      const j = await call('inquiry_intake', { text, inquiry_id: inq.id, category: inq.category || null }, token);
      if (j && j.error) setErr(String(j.message || j.error));
      else setTurns((t) => [...t, { role: 'ai', text: (j && j.assistant_message) || (lang === 'ar' ? 'تم.' : 'Noted.') }]);
      if (onChanged) onChanged();
    } catch (e) { setErr((e && e.message) || (lang === 'ar' ? 'تعذّر الإرسال.' : 'Could not send that.')); }
    setBusy(false);
  };
  if (!open2) {
    return (<Button variant="link" className="px-0 h-auto self-start" onClick={(e) => { e.stopPropagation(); setOpen2(true); }}>
      {lang === 'ar' ? '🤖 اسأل المساعد عن هذا الطلب' : '🤖 Ask the assistant about this request'}
    </Button>);
  }
  return (<div className="rounded-lg border border-border bg-secondary/20 p-3" onClick={(e) => e.stopPropagation()}>
    <div className={cn(S.sub, 'font-semibold text-foreground')}>{lang === 'ar' ? 'المساعد' : 'Procurement assistant'}</div>
    {turns.map((tn, i) => (
      <div key={i} className={cn(S.sub, 'mt-1', tn.role === 'user' ? 'text-muted-foreground' : 'text-foreground')}>
        {tn.role === 'user' ? '› ' : '🤖 '}{tn.text}
      </div>
    ))}
    {err ? <div className={cn(S.err, 'mt-1')}>{err}</div> : null}
    <div className="mt-2 flex items-end gap-2">
      <Input value={q} onChange={(e) => setQ(e.target.value)} disabled={busy}
        onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); ask(); } }}
        placeholder={lang === 'ar' ? 'اسأل عن المواصفات أو التوقيت أو الموردين…' : 'Ask about specs, timing or suppliers…'} />
      <Button size="sm" disabled={busy || !q.trim()} onClick={ask}>{busy ? '…' : (lang === 'ar' ? 'إرسال' : 'Ask')}</Button>
    </div>
  </div>);
}

function QuotePdfLink({ q, token, lang }) {
  const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const open = async (e) => { e.stopPropagation(); setBusy(true); setMsg(''); const j = await call('customer_api', { action: 'quote_pdf', quote_id: q.id, lang }, token); setBusy(false); if (j && j.ok && j.url) { window.open(j.url, '_blank', 'noopener'); } else setMsg((j && (j.detail || j.error)) || (lang === 'ar' ? 'تعذّر فتح الملف' : 'Could not open the PDF')); };
  return (<><button className="text-primary font-semibold text-[12.5px]" disabled={busy} onClick={open}>{busy ? (lang === 'ar' ? 'جارٍ التحضير…' : 'Preparing…') : (lang === 'ar' ? '📄 عرض السعر (PDF)' : '📄 View quote (PDF)')}</button>{msg ? <span className={cn(S.sub, 'ml-2 text-red-400')}>{msg}</span> : null}</>);
}
function Timeline({ inq, quotes, anyRevealed, lang }) {
  const steps = lang === 'ar' ? RFQ_STAGES.ar : RFQ_STAGES.en;
  const idx = rfqStageIdx(inq, quotes);
  const fmt = (d) => { try { return new Date(d).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }); } catch (_e) { return ''; } };
  return (<div className="rounded-lg border border-border bg-secondary/20 p-3">
    {inq.created_at ? <div className={cn(S.sub, 'mb-2')}>{(lang === 'ar' ? 'أُنشئ في ' : 'Created ') + fmt(inq.created_at)}</div> : null}
    <div className="flex items-center gap-1.5 flex-wrap text-[11px]">{steps.map((sname, si) => (<span key={sname} className={cn('flex items-center gap-1', si <= idx ? 'text-primary font-semibold' : 'text-muted-foreground/60')}>{si > 0 ? <span className="text-muted-foreground/40">›</span> : null}<span className={cn('inline-block w-2 h-2 rounded-full', si <= idx ? 'bg-primary' : 'bg-muted-foreground/30')} />{sname}</span>))}</div>
  </div>);
}
function DetailFacts({ inq, lang }) {
  const rows = [];
  if (inq.budget) rows.push([lang === 'ar' ? 'الميزانية' : 'Budget', String(inq.budget)]);
  if (Array.isArray(inq.trades) && inq.trades.length) rows.push([lang === 'ar' ? 'التخصصات' : 'Trades', inq.trades.join(', ')]);
  if (inq.boq && inq.boq.boq && inq.boq.boq.length) rows.push([lang === 'ar' ? 'عدد البنود' : 'Line items', String(inq.boq.boq.length)]);
  const sp = inq.spec && typeof inq.spec === 'object' ? inq.spec : null;
  if (sp) for (const k of Object.keys(sp)) { const v = sp[k]; if (v && typeof v === 'string' && k !== 'plausibility' && k !== 'provenance') rows.push([k.replace(/_/g, ' '), v]); }
  // How confident the reader was about the BOQ it pulled off the customer's drawing. The customer
  // is the only person who can tell us it read the drawing wrong, and they were never shown it.
  const conf = Number(inq.boq_confidence);
  if (Number.isFinite(conf) && inq.boq && inq.boq.boq) rows.push([lang === 'ar' ? 'دقة قراءة الرسم' : 'Drawing read confidence', Math.round(conf <= 1 ? conf * 100 : conf) + '%']);
  // my_inquiries signs a URL to the customer's OWN uploaded drawing on every call. Nothing read it,
  // so the one person entitled to that file could not open it — only the suppliers could.
  const drawing = inq.drawing_file_url
    ? (<div className="mt-1.5"><a href={inq.drawing_file_url} target="_blank" rel="noopener" className="text-primary font-semibold text-[12.5px]">{lang === 'ar' ? '📐 افتح الرسم الذي رفعته' : '📐 Open the drawing you uploaded'}{inq.drawing_file_name ? ' (' + inq.drawing_file_name + ')' : ''}</a></div>)
    : null;
  if (!rows.length && !drawing) return null;
  return (<div className="rounded-lg border border-border bg-secondary/20 p-3"><div className={cn(S.sub, 'font-semibold mb-1.5 text-foreground')}>{lang === 'ar' ? 'تفاصيل الطلب' : 'Request details'}</div><div className="grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-1">{rows.slice(0, 14).map((r, i) => (<div key={i} className={S.sub}><span className="capitalize text-muted-foreground">{r[0]}: </span><span className="text-foreground">{r[1]}</span></div>))}</div>{drawing}</div>);
}
function Comparison({ inqId, token, lang }) {
  const [a, setA] = useState(null); const [busy, setBusy] = useState(true); const [note, setNote] = useState('');
  useEffect(() => { let on = true; setBusy(true); call('quote_compare', { inquiry_id: inqId, lang }, token).then((j) => { if (!on) return; setBusy(false); if (j && j.ok && j.analysis) setA(j.analysis); else setNote((j && (j.note || j.error)) || ''); }).catch(() => { if (on) { setBusy(false); } }); return () => { on = false; }; }, [inqId, lang]);
  const arr = (x) => Array.isArray(x) ? x : [];
  if (busy) return (<div className="rounded-lg border border-primary/30 bg-primary/5 p-3.5"><div className={cn(S.sub, 'text-primary')}>{lang === 'ar' ? 'يُعدّ خبيرنا تقرير المقارنة…' : 'Our expert is preparing your comparison report…'}</div></div>);
  if (!a) return note ? (<div className="rounded-lg border border-border bg-secondary/20 p-3"><div className={S.sub}>{note}</div></div>) : null;
  return (<div className="rounded-lg border border-primary/30 bg-primary/5 p-3.5">
    <div className={cn(S.sub, 'font-bold text-primary mb-1')}>{(lang === 'ar' ? 'تقرير المقارنة من الخبير' : 'Expert comparison report') + (a.trade ? ' · ' + a.trade : '')}</div>
    {a.bottom_line ? <div className={cn(S.sub, 'text-foreground font-semibold mb-1.5')}>{a.bottom_line}</div> : null}
    {a.overview ? <div className={cn(S.sub, 'mb-2')}>{a.overview}</div> : null}
    {arr(a.top3).length ? <div className="mb-2"><div className={cn(S.sub, 'font-semibold text-foreground')}>{lang === 'ar' ? 'أفضل الخيارات' : 'Top picks'}</div>{arr(a.top3).map((r, i) => (<div key={i} className={cn(S.sub, 'mt-0.5')}><span className="text-primary font-semibold">#{r.rank} {r.label}</span> — {r.why}{r.tradeoff ? (' ' + (lang === 'ar' ? '(الاعتبار: ' : '(catch: ') + r.tradeoff + ')') : ''}</div>))}</div> : null}
    {arr(a.quotes).map((q, i) => (<div key={i} className="mt-2 border-t border-border/60 pt-2"><div className={cn(S.sub, 'font-semibold text-foreground')}>{q.label}{q.price != null ? (' — ' + aed(q.price)) : ''}</div>{/* §10 PER-DIMENSION SCORES. The spec compares Price / Delivery / Quality per supplier as stars;
        the report previously carried one blended "Value n/100" computed in the browser, which is a
        different claim — it hides WHICH dimension a quote is weak on, and that is the whole point
        of a comparison. The three are scored server-side, relative to the other shortlisted quotes
        on this job, and a dimension the quote does not state scores 1 rather than an average. */}
      {(q.price_score != null || q.delivery_score != null || q.quality_score != null) ? (
        <div className="mt-1 flex flex-wrap gap-x-3 gap-y-0.5" title={q.score_reason || ''}>
          {[[lang === 'ar' ? 'السعر' : 'Price', q.price_score], [lang === 'ar' ? 'التسليم' : 'Delivery', q.delivery_score], [lang === 'ar' ? 'الجودة' : 'Quality', q.quality_score]]
            .filter(([, v]) => v != null)
            .map(([label, v]) => (
              <span key={String(label)} className={S.sub}>
                <span className="text-muted-foreground">{label}: </span>
                <span className="text-foreground" aria-label={`${v} ${lang === 'ar' ? 'من 5' : 'out of 5'}`}>{'★'.repeat(Math.max(0, Math.min(5, Number(v) || 0)))}{'☆'.repeat(Math.max(0, 5 - Math.max(0, Math.min(5, Number(v) || 0))))}</span>
              </span>
            ))}
        </div>
      ) : null}
      {q.score_reason ? <div className={cn(S.sub, 'text-muted-foreground')}>{q.score_reason}</div> : null}
      {q.getting ? <div className={S.sub}>{q.getting}</div> : null}{arr(q.missing_from_request).length ? <div className={S.sub} style={{ color: 'hsl(43 68% 64%)' }}>{(lang === 'ar' ? 'ناقص مما طلبت: ' : 'Missing from your request: ') + arr(q.missing_from_request).join('; ')}</div> : null}{arr(q.spec_deviation).length ? <div className={S.sub} style={{ color: 'hsl(43 68% 64%)' }}>{(lang === 'ar' ? 'اختلاف عن المواصفات: ' : 'Spec differences: ') + arr(q.spec_deviation).join('; ')}</div> : null}{arr(q.flags).length ? <div className={cn(S.sub, 'text-red-400')}>{arr(q.flags).join('; ')}</div> : null}</div>))}
    {arr(a.watch_outs).length ? <div className={cn(S.sub, 'text-red-400 mt-2')}>{(lang === 'ar' ? 'انتبه: ' : 'Watch out: ') + arr(a.watch_outs).join(' · ')}</div> : null}
    {a.advice ? <div className={cn(S.sub, 'mt-2 text-foreground')}>{a.advice}</div> : null}
    {/* §10 EXPORT. customer_api action='compare_pdf' has existed, ownership-checked, rendering this
        same analysis as a PDF — with NO caller anywhere a customer could click. A procurement
        decision has to leave the portal to reach a manager or a finance approver; the comparison
        stays on screen (§10 is explicit that it must not be an exported spreadsheet) and the
        document is what the customer takes to the meeting. */}
    <ExportComparison inqId={inqId} token={token} lang={lang} />
    <div className={cn(S.sub, 'mt-2 text-muted-foreground/70 text-[11px]')}>{lang === 'ar' ? 'إرشادي فقط — القرار النهائي لك.' : 'Guidance only — the final decision is yours.'}</div>
  </div>);
}
// The download is its own component because it owns a failure the report must survive: a PDF that
// cannot be built must not blank the analysis the customer is reading.
function ExportComparison({ inqId, token, lang }) {
  const [busy, setBusy] = useState(false); const [err, setErr] = useState('');
  const go = async () => {
    setBusy(true); setErr('');
    try {
      const j = await call('customer_api', { action: 'compare_pdf', inquiry_id: inqId, lang }, token);
      const url = j && (j.url || j.pdf_url || j.file_url);
      if (url) window.open(url, '_blank', 'noopener');
      else setErr((j && (j.message || j.error)) || (lang === 'ar' ? 'تعذّر إنشاء المستند.' : 'Could not build the document.'));
    } catch (e) {
      setErr((e && e.message) || (lang === 'ar' ? 'تعذّر إنشاء المستند.' : 'Could not build the document.'));
    } finally { setBusy(false); }
  };
  return (<div className="mt-2">
    <Button size="sm" variant="secondary" disabled={busy} onClick={go}>
      {busy ? (lang === 'ar' ? 'جارٍ التجهيز…' : 'Preparing…') : (lang === 'ar' ? '⬇ حفظ المقارنة كمستند' : '⬇ Save this comparison as a document')}
    </Button>
    {err ? <div className={cn(S.err, 'mt-1')}>{err}</div> : null}
  </div>);
}
function QuoteCard({ q, token, concluded, onChange, vscore, best, lang, hired }) {
  const [state, setState] = useState(q.revealed ? 'revealed' : 'idle'); const [contact, setContact] = useState(null); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  // Warn, do not block: an expired price is still a supplier worth contacting, and taking the
  // reveal button away would decide that for the customer. The banner tells them to get the price
  // re-confirmed first, which is the actual risk they were never shown.
  const exp = expiryOf(q, lang);
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
  return (<div className="rounded-xl border border-border bg-white/[0.02] p-3">
    <div className="flex justify-between items-center"><div><b>{q.label}</b>{best ? <span className="ml-1.5 rounded-full bg-primary/15 text-primary text-[10px] font-bold px-1.5 py-0.5 align-middle">Best value</span> : ''}{q.verified ? <span className="text-primary text-[11px] font-bold"> ✓ verified</span> : ''}{q.rating != null ? <span className="text-accent text-[12px] font-semibold"> ★ {q.rating} ({q.rating_count})</span> : ''}</div><div className="text-right"><div className="text-[17px] font-extrabold text-foreground">{aed(q.price)}</div>{vscore != null ? <div className="text-[10px] text-muted-foreground" title="Guide only — blends price, rating and quote completeness. Not advice; use your own judgement.">Value {vscore}/100</div> : null}</div></div>
    <div className="text-muted-foreground text-[11.5px] mt-0.5">{q.lead_time ? 'Lead time: ' + q.lead_time + ' · ' : ''}{q.warranty ? 'Warranty: ' + q.warranty + ' · ' : ''}{q.payment_terms ? 'Terms: ' + q.payment_terms : ''}{q.win_rate != null ? ' · win ' + Math.round(q.win_rate) + '%' : ''}</div>
    {q.scope && <div className={cn(S.sub, 'mt-1')}>{q.scope}</div>}
    {q.notes && <div className={cn(S.sub, 'mt-1')}>{(lang === 'ar' ? 'ملاحظة المورّد: ' : "Supplier's note: ") + q.notes}</div>}
    {/* What the price does NOT cover is the part that turns a cheap quote into an expensive job. */}
    {q.exclusions && <div className={cn(S.sub, 'mt-1')} style={{ color: 'hsl(43 68% 64%)' }}>{(lang === 'ar' ? 'غير شامل: ' : 'Not included: ') + q.exclusions}</div>}
    {q.conditions && <div className={cn(S.sub, 'mt-1')}>{(lang === 'ar' ? 'الشروط: ' : 'Conditions: ') + q.conditions}</div>}
    {exp && (exp.tone === 'ok'
      ? <div className={cn(S.sub, 'mt-1')}>{exp.text}{q.validity ? (' · ' + (lang === 'ar' ? 'مدة السريان: ' : 'Validity: ') + q.validity) : ''}</div>
      : <div className={cn('mt-1.5 rounded-md border px-3 py-2 text-[11.5px]', exp.tone === 'expired' ? 'border-red-400/30 bg-red-400/10 text-red-300' : 'border-amber-400/30 bg-amber-400/10 text-amber-300')} role={exp.tone === 'expired' ? 'alert' : undefined}>{exp.text}</div>)}
    {!exp && q.validity && <div className={cn(S.sub, 'mt-1')}>{(lang === 'ar' ? 'مدة السريان: ' : 'Validity: ') + q.validity}</div>}
    {/* inquiry_matches.match_reason — the only record of WHY this supplier was contacted. It was
        rendered nowhere but /os (staff). The API omits the key entirely until this quote is
        revealed, because the reason can name the company; see the note in customer_api. */}
    {q.match_reason && <div className={cn(S.sub, 'mt-1')}>{(lang === 'ar' ? 'سبب مطابقتنا لهذا المورّد: ' : 'Why we matched this supplier: ') + q.match_reason}</div>}
    <div className="mt-1.5"><QuotePdfLink q={q} token={token} lang={lang} /></div>
    <div className="mt-2"><SupplierRelationshipCard quote={q} token={token} lang={lang === 'ar' ? 'ar' : 'en'} /></div>
    {/* §15 Negotiation Assistant, on the quote it is about rather than in a module of its own — the
        guidance is per-quote, and a customer deciding whether to push back on THIS price should not
        have to carry a quote id to another screen. Production holds no quotes, so it answers
        band='insufficient_data' and prints that sentence instead of inventing a target. */}
    <div className="mt-2"><NegotiationAssistant token={token} quoteId={q.id} lang={lang === 'ar' ? 'ar' : 'en'} /></div>
    {state === 'revealed' ? (contact ? <Contact c={contact} q={q} token={token} onChange={onChange} lang={lang} won={hired != null && q.supplier_ref != null && Number(hired) === Number(q.supplier_ref)} /> : <div className={S.sub}>Loading contact…</div>)
      : (<div className="flex justify-between items-center gap-2.5 mt-2.5 flex-wrap">
          <div className={S.sub}>Reveal fee {aed(q.reveal_fee)} — refundable if the supplier doesn't respond in 3 working days.</div>
          <Button size="sm" disabled={busy || concluded} onClick={reveal}>{busy ? 'Please wait…' : 'Reveal & contact'}</Button>
        </div>)}
    {msg && <div className={S.err}>{msg}</div>}
  </div>);
}

function Contact({ c, q, token, onChange, lang, won }) {
  const s = c.supplier || {};
  const [rating, setRating] = useState(0); const [rated, setRated] = useState(!!(q && q.rated)); const [done, setDone] = useState('');
  const rate = async (n) => { setRating(n); const j = await call('customer_api', { action: 'rate_supplier', quote_id: q.id, rating: n }, token); if (j && j.ok) { setRated(true); setDone('Thanks for rating.'); } else setDone((j && j.error) || 'Could not save rating.'); };
  const refund = async () => { if (!confirm('Request a refund of the reveal fee? This is only valid within 3 working days if the supplier did not respond.')) return; const j = await call('customer_api', { action: 'request_refund', quote_id: q.id }, token); setDone(j && j.ok ? 'Refund requested — we will review it.' : ((j && j.error) || 'Could not request refund.')); };
  const hire = async () => { if (!confirm('Mark this supplier as hired for this project?')) return; const j = await call('customer_api', { action: 'complete_inquiry', quote_id: q.id }, token); if (j && j.ok) { setDone('Marked as hired.'); onChange && onChange(); } else setDone((j && j.error) || 'Could not update.'); };
  return (<div className="mt-2.5 rounded-lg border border-primary/30 bg-primary/10 p-3">
    <div className="font-bold">{s.company_name || 'Supplier'}</div>
    {q && q.revealed_at ? <div className={cn(S.sub, 'mt-0.5')}>{(lang === 'ar' ? 'كُشف بتاريخ ' : 'Revealed on ') + new Date(q.revealed_at).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}</div> : null}
    {won ? <div className="text-primary text-[12px] font-bold mt-0.5">🏆 {lang === 'ar' ? 'المورّد المتعاقد معه لهذا المشروع' : 'Hired supplier for this project'}</div> : null}
    <div className={cn(S.sub, 'mt-0.5')}>{(lang === 'ar' ? 'دفعت ' : 'You paid ') + aed(q.reveal_fee) + (lang === 'ar' ? ' لكشف هذا المورّد' : ' to reveal this supplier')}</div>
    <div className="flex gap-3.5 flex-wrap mt-1.5">
      {s.phone && <a href={'tel:' + s.phone} className="text-primary font-semibold">📞 {s.phone}</a>}
      {s.whatsapp && <a href={'https://wa.me/' + String(s.whatsapp).replace(/[^0-9]/g, '')} target="_blank" rel="noopener" className="text-primary font-semibold">WhatsApp</a>}
      {s.email && <a href={'mailto:' + s.email} className="text-primary font-semibold">✉ {s.email}</a>}
      {s.website && <a href={/^https?:/.test(s.website) ? s.website : 'https://' + s.website} target="_blank" rel="noopener" className="text-primary font-semibold">Website</a>}
    </div>
    {c.file_url && <div className="mt-1.5"><a href={c.file_url} target="_blank" rel="noopener" className="text-primary font-semibold">Download their quotation{c.file_name ? ' (' + c.file_name + ')' : ''}</a></div>}
    <div className="flex gap-4 items-center mt-2.5 flex-wrap">
      {/* A11Y (5 Aug 2026). Five <span onClick> stars: rating a supplier was mouse-only and the
          control announced nothing. Each star is now a real <button> carrying its value in an
          aria-label, wrapped in a labelled group. Stars contain only text, so unlike the card
          header above there is no content-model obstacle to using a real button. */}
      {!rated ? <span role="group" aria-label="Rate this supplier" className="text-lg tracking-widest text-muted-foreground/50">{[1, 2, 3, 4, 5].map((n) => <button key={n} type="button" onClick={() => rate(n)} aria-label={`Rate ${n} star${n === 1 ? '' : 's'}`} className={cn('cursor-pointer bg-transparent border-0 p-0 leading-none', n <= rating && 'text-amber-400')}>★</button>)}</span> : <span className={S.sub}>★ Rated</span>}
      <Button variant="link" className="px-0 h-auto" onClick={hire}>I hired this supplier</Button>
      <Button variant="link" className="px-0 h-auto" onClick={refund}>Request refund</Button>
    </div>
    {done && <div className={cn(S.sub, 'mt-1.5 text-primary')}>{done}</div>}
  </div>);
}

function NewRequest({ token, onDone, onCancel }) {
  const GREETING = { role: 'assistant', text: "Hi — I\'m your QuotesDone intake assistant. Tell me what you need done and which emirate it\'s in, and I\'ll ask a couple of quick questions so suppliers can quote accurately. You can type, attach a drawing / photo / your own quotation, or tap the mic. Your identity stays hidden until you choose to reveal a supplier." };
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
  const send = async () => { const t = input.trim(); if (!t) return; push({ role: 'user', text: t }); setInput(''); await runIntake(t); };
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
  return (<Card className="p-0 mb-3.5 flex flex-col" style={{ height: 'min(72vh, 640px)' }}>
    <div className="flex justify-between items-center gap-2.5 px-5 py-3 border-b border-border">
      <div className={S.h2}>New request</div>
      <Button variant="link" className="px-0 h-auto" onClick={onCancel}>Cancel</Button>
    </div>
    <div className="flex-1 overflow-y-auto px-4 py-3 space-y-2.5">
      {messages.map((m, i) => (
        m.chip !== undefined
          ? <div key={i} className="flex justify-end"><div className="rounded-2xl bg-primary/15 border border-primary/30 text-foreground px-3 py-2 text-[13px]">📎 {m.chip}</div></div>
          : <div key={i} className={cn('flex', m.role === 'user' ? 'justify-end' : 'justify-start')}>
              <div className={cn('rounded-2xl px-3.5 py-2 text-[13.5px] leading-relaxed max-w-[85%] whitespace-pre-wrap', m.role === 'user' ? 'bg-primary text-primary-foreground' : 'bg-secondary/60 text-foreground border border-border')}>{m.text}</div>
            </div>
      ))}
      {(thinking || analyzing) && <div className="flex justify-start"><div className="rounded-2xl px-3.5 py-2 text-[13px] bg-secondary/60 text-muted-foreground border border-border">{analyzing ? 'Reading your file…' : 'Typing…'}</div></div>}
      {ready && brief && (
        <div className="rounded-lg border border-primary/30 bg-primary/5 p-3.5">
          <div className={cn(S.sub, 'font-bold capitalize text-foreground')}>{brief.category || 'Request'}{brief.emirate ? ' — ' + brief.emirate : ''}</div>
          <div className={cn(S.sub, 'mt-1')}>{brief.summary || ''}</div>
          {brief.scope ? <div className={cn(S.sub, 'mt-1')}>Scope: {brief.scope}</div> : null}
          {/* §3 THE ESTIMATED QUANTITY. The intake has emitted brief.quantity from the start and
              this card rendered seven brief fields without it, so the customer confirmed a brief
              containing a number they were never shown — and the RFQ-creation path in customer_api
              then dropped it. Both halves are fixed together: shown here, persisted there. */}
          {brief.quantity ? <div className={cn(S.sub, 'mt-1')}>Quantity: {brief.quantity}{brief.provenance && brief.provenance.quantity === 'inferred' ? <span className="text-muted-foreground"> (estimated from your description — correct it below if it is wrong)</span> : null}</div> : null}
          {brief.timeline ? <div className={cn(S.sub, 'mt-1')}>Timeline: {brief.timeline}</div> : null}
          {brief.budget ? <div className={cn(S.sub, 'mt-1')}>Budget: {brief.budget}</div> : null}
          {/* §3 REQUIRED DOCUMENTS, before Send. The category's own compliance checklist — the same
              list the RFQ-creation path copies onto the RFQ — so what the customer agrees to send
              is what the supplier will be held to. A category with no published checklist shows
              nothing rather than three invented lines. */}
          {Array.isArray(brief.required_documents) && brief.required_documents.length ? (
            <div className="mt-2">
              <div className={cn(S.sub, 'font-semibold text-foreground')}>Required documents and approvals</div>
              <ul className="mt-0.5 space-y-0.5" role="list">
                {brief.required_documents.map((d, i) => (
                  <li key={i} className={S.sub}>✓ {d.item}{d.authority ? <span className="text-muted-foreground"> — {d.authority}</span> : null}</li>
                ))}
              </ul>
            </div>
          ) : null}
          {/* §3 HOW FAR THIS WILL REACH, before it is sent. The number comes from the same matcher
              dispatch itself uses, so "12 suppliers" means twelve suppliers get this brief. Zero is
              stated as zero: a customer about to send a request that will reach nobody has to be
              told that BEFORE they press the button, not by silence afterwards. */}
          {brief.supplier_count != null ? (
            <div className={cn(S.sub, 'mt-2 font-semibold', Number(brief.supplier_count) > 0 ? 'text-foreground' : 'text-muted-foreground')}>
              {Number(brief.supplier_count) > 0
                ? `We will send this to ${brief.supplier_count} matching supplier${Number(brief.supplier_count) === 1 ? '' : 's'}.`
                : 'No registered supplier matches this brief yet. You can still send it — it reaches suppliers in this trade as they register.'}
            </div>
          ) : null}
          {trades.length > 1 ? (<div className="mt-2.5 rounded-lg border border-primary/30 bg-primary/5 p-3"><div className={cn(S.sub, 'font-semibold text-primary')}>This project spans several trades: {trades.join(', ')}.</div><div className={cn(S.sub, 'mt-0.5 mb-2')}>How would you like to source it?</div><label className="flex items-start gap-2 cursor-pointer rounded-md p-2 hover:bg-secondary/50"><input type="radio" name="combine" className="mt-1" checked={combineMode === 'multi'} onChange={() => setCombineMode('multi')} /><span className={S.sub}><span className="font-semibold text-foreground">Separate specialists (recommended)</span> — a separate request goes to specialists in each trade, so you get the sharpest price on every part.</span></label><label className="flex items-start gap-2 cursor-pointer rounded-md p-2 hover:bg-secondary/50"><input type="radio" name="combine" className="mt-1" checked={combineMode === 'turnkey'} onChange={() => setCombineMode('turnkey')} /><span className={S.sub}><span className="font-semibold text-foreground">One turnkey company</span> — a single fit-out / decoration company handles the whole project end to end.</span></label></div>) : null}
          {brief.plausibility && brief.plausibility.note ? <div className={cn(S.sub, 'mt-1')} style={{ color: 'hsl(43 68% 64%)' }}>Note: {brief.plausibility.note}</div> : null}
          <Button className="w-full mt-3" disabled={busy} onClick={submit}>{busy ? 'Sending…' : 'Send to suppliers'}</Button>
          <div className={cn(S.sub, 'text-center mt-1.5')}>or keep typing below to add more detail</div>
        </div>
      )}
      <div ref={endRef} />
    </div>
    <div className="border-t border-border px-3 py-2.5">
      {msg && <div className={cn(S.err, 'mb-1.5')}>{msg}</div>}
      <div className="flex items-end gap-2">
        <input ref={fileRef} type="file" accept="image/*,application/pdf" className="hidden" onChange={(e) => onFile(e.target.files[0])} />
        <button type="button" title="Attach a drawing, photo or quotation" className="text-primary text-xl px-1 leading-none disabled:opacity-40" disabled={analyzing || thinking} onClick={() => fileRef.current && fileRef.current.click()}>📎</button>
        <button type="button" title="Speak your request" className={cn('text-xl px-1 leading-none', rec ? 'text-red-400' : 'text-primary')} onClick={rec ? stopRec : startRec}>{voxBusy ? '…' : (rec ? '⏺' : '🎙')}</button>
        <textarea className="flex-1 resize-none rounded-xl bg-secondary/40 border border-border px-3 py-2 text-[13.5px] outline-none focus:border-primary/60" rows={1} placeholder={rec ? 'Listening… tap the mic to stop' : 'Message the assistant…'} value={input} onChange={(e) => setInput(e.target.value)} onKeyDown={onKey} />
        <Button disabled={thinking || analyzing || !input.trim()} onClick={send}>Send</Button>
      </div>
    </div>
  </Card>);
}
// The §22 module list, in the order a customer meets them. The Messages/Thread pair that used to
// live in this file is gone: CommunicationCenter serves the same four messages_api actions and adds
// the documents that belong to each conversation plus an explicit statement of which channels the
// inbox does and does not carry, so keeping both would have been two inboxes disagreeing.
const MODULES = [
  ['projects', 'projects'], ['spatial', 'mod_spatial'], ['documents', 'mod_documents'],
  ['messages', 'messages'], ['approvals', 'mod_approvals'], ['orders', 'mod_orders'],
  ['predict', 'mod_predict'], ['profile', 'mod_profile'], ['account', 'mod_account'],
];
// §21: the server's per-customer panel order, applied to the module bar.
//
// THE DECLARED ORDER IS THE FLOOR, NOT THE DEFAULT. A layout is a REORDERING of what exists, so a
// module the server did not rank is appended rather than dropped — otherwise shipping a new module
// would make it invisible to every customer whose layout was computed before it existed, which is
// the failure mode of every server-driven layout that trusts the payload as a whitelist. An id the
// server sends that this build does not have is ignored for the mirror-image reason.
function orderedModules(layout) {
  const want = (layout && Array.isArray(layout.order)) ? layout.order.map(String) : [];
  const known = new Map(MODULES.map((m) => [m[0], m]));
  const out = want.map((id) => known.get(id)).filter(Boolean);
  for (const m of MODULES) if (!out.includes(m)) out.push(m);
  return out;
}
// THE BUTTONS STAY WRITTEN OUT, AND CSS MOVES THEM.
//
// The obvious implementation is to map orderedModules() straight into buttons, and it is worse in
// two ways that only show up later. Every destination becomes `setView(id)` with no literal
// anywhere, so nothing — no grep, no reviewer, no route audit — can answer "where can this portal
// go" without executing it; and the DOM order then follows the layout, which is the tab order a
// keyboard user gets, so a server-side ranking silently reorders focus. `order` is a flexbox
// property: it changes the visual order and leaves the DOM, and therefore the tab order, alone.
// An unranked module sorts after the ranked ones because indexOf returns -1 → 999.
const moduleBarOrder = (id, layout) => {
  const ids = orderedModules(layout).map((m) => m[0]);
  const i = ids.indexOf(id);
  return i < 0 ? 999 : i;
};
// The unread count is the one fact worth knowing BEFORE opening the inbox, so the module bar asks
// messages_api for it. Failure is silent by design: a badge that cannot load must not put an error
// where a count goes, and the inbox itself reports its own failure when the customer opens it.
function UnreadBadge({ token, lang }) {
  const [unread, setUnread] = useState(0);
  useEffect(() => {
    let on = true;
    call('messages_api', { action: 'threads' }, token)
      .then((j) => { if (on) setUnread(((j && j.threads) || []).reduce((n, th) => n + (Number(th.unread) || 0), 0)); })
      .catch(() => {});
    return () => { on = false; };
  }, [token]);
  if (!unread) return null;
  return <span className="ms-1.5 inline-block rounded-full bg-primary text-primary-foreground px-1.5 text-[10px] font-bold"
    title={unread + ' ' + t(lang, unread === 1 ? 'unread_message' : 'unread_messages')}>{unread}</span>;
}
// One floating window, whichever module is open. Nothing here fetches: each surface owns its own
// endpoint, its own loading state and its own empty state, and this component decides only where
// they appear and what the window is called.
function ModuleWindow({ id, onClose, token, lang, inqs, onChanged, twin }) {
  const l2 = lang === 'ar' ? 'ar' : 'en';
  // 'home' is a real destination in the module bar and it is the dashboard itself, so it opens no
  // window: the guard is the module entry, not a non-empty string.
  const entry = MODULES.find((m) => m[0] === id);
  return (<Dialog open={!!entry} onOpenChange={(o) => { if (!o) onClose(); }}>
    <DialogContent className="max-w-[min(1060px,96vw)] max-h-[88vh] overflow-y-auto bg-card/85 backdrop-blur transition-opacity duration-200">
      <DialogHeader><DialogTitle>{entry ? t(lang, entry[1]) : ''}</DialogTitle></DialogHeader>
      {id === 'projects' && <ProjectsModule token={token} lang={l2} linkableRfqs={inqs.map((i) => ({ id: i.id, summary: i.summary, category: i.category }))} onOpenRfq={onClose} onChanged={onChanged} />}
      {id === 'spatial' && <SpatialModule token={token} lang={l2} inquiries={inqs} onOpenRfq={onClose} />}
      {id === 'documents' && <DocumentVault token={token} lang={l2} />}
      {id === 'messages' && <CommunicationCenter token={token} lang={l2} onOpenRfq={onClose} />}
      {id === 'approvals' && <ApprovalChain token={token} lang={l2} onOpenRfq={onClose} />}
      {id === 'orders' && <OrdersList token={token} lang={l2} onOpenRfq={onClose} />}
      {id === 'predict' && <PredictiveIntelligence token={token} lang={l2} />}
      {/* §2 the twin, §9 discovery and §17 the memory — three surfaces whose backends were complete
          and whose only reader was os_api, the staff console. They share one window because they
          are one subject: what the system knows about this customer and what it does with it. */}
      {id === 'profile' && <div className="flex flex-col gap-3">
        <CompanyTwin twin={twin} lang={l2} />
        <SupplierDiscovery token={token} lang={l2} />
        <CustomerMemory token={token} lang={l2} />
      </div>}
      {id === 'account' && <AccountSettings token={token} lang={lang} />}
    </DialogContent>
  </Dialog>);
}
// customer_api action='me' has served the customer's own row since the portal was written and no
// file in src/ ever called it — the account the customer holds was the one thing they could not
// look at. It is read-only on purpose: there is no endpoint that writes a preference back to the
// profile, so this states which choices are device-local rather than implying they were saved.
function AccountSettings({ token, lang }) {
  const [me, setMe] = useState(null); const [err, setErr] = useState('');
  useEffect(() => {
    let on = true;
    call('customer_api', { action: 'me' }, token)
      .then((j) => { if (!on) return; if (j && j.customer) setMe(j.customer); else setErr(t(lang, 'acct_failed')); })
      .catch(() => { if (on) setErr(t(lang, 'acct_failed')); });
    return () => { on = false; };
  }, [token]);
  if (err) return <div className={S.err}>{err}</div>;
  if (!me) return <div className={S.sub}>{t(lang, 'loading')}</div>;
  const since = me.created_at ? new Date(me.created_at).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : '';
  const profileLocale = me.locale === 'ar' ? 'العربية' : me.locale === 'en' ? 'English' : (me.locale || '—');
  return (<div>
    <div className={cn(S.sub, 'mb-2')}>{t(lang, 'acct_sub')}</div>
    <div className="rounded-lg border border-border bg-secondary/20 p-3 grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-1">
      <div className={S.sub}><span className="text-muted-foreground">{t(lang, 'acct_name')}: </span><span className="text-foreground">{me.full_name || '—'}</span></div>
      <div className={S.sub}><span className="text-muted-foreground">{t(lang, 'acct_email')}: </span><span className="text-foreground">{me.email || '—'}</span></div>
      <div className={S.sub}><span className="text-muted-foreground">{t(lang, 'acct_phone')}: </span><span className="text-foreground">{me.phone || '—'}</span></div>
      <div className={S.sub}><span className="text-muted-foreground">{t(lang, 'acct_locale')}: </span><span className="text-foreground">{profileLocale}</span></div>
      <div className={S.sub}><span className="text-muted-foreground">{t(lang, 'acct_since')}: </span><span className="text-foreground">{since || '—'}</span></div>
    </div>
    <div className={cn(S.hint, 'mt-2')}>{t(lang, 'acct_local_note')}</div>
  </div>);
}
function Kpi({ label, v }) { return <Card className="p-3.5"><div className="text-[19px] font-extrabold text-foreground">{v}</div><div className="text-[11.5px] text-muted-foreground mt-1">{label}</div></Card>; }
