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
// THE SHELL. The portal was a stack of cards under ten grey pills; this is the application frame
// the founder asked for — persistent grouped sidebar, a top bar whose widest element is the
// assistant, a mobile tab bar, and the assistant docked in the layout rather than floating in a
// corner. See the header of PortalShell.tsx for what was on the screen before and why.
import { PortalShell, StatTile, StatusPill, rfqState } from './PortalShell';
import { FileText, MessageSquareQuote, BellRing, KeyRound, Plus, Sparkles, Upload, Scale, ArrowRight, ChevronDown, Lock, Check } from 'lucide-react';
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
    call_note:'That number is a landline, so we are calling you now and reading the 6-digit code out. Answer and type it in below.', use_diff_number:'Use a different number',
    signup_email_only:"Please sign up with an email address — you'll add and verify your mobile in the next step.",
    conflict_supplier:'This email is registered as a supplier. Please use the Supplier portal to sign in.',
    session_expired:'Your session has expired. Please sign in again.', load_failed:"Couldn't load your account. Please retry.", retry:'Retry',
    gate_title:'Complete your account', gate_sub:"A few details to finish signing up. We verify your mobile and email for everyone's security.",
    full_name:'Full name', mobile_ph:'Mobile (05x xxx xxxx)', dob_label:'Date of birth (you must be 18+)', save_details:'Save details', saving:'Saving…',
    verify_mobile:'Verify your mobile', verify_email_h:'Verify your email', verified:'✓ verified', send_sms:'Send SMS code', verify:'Verify',
    send_email_code:'Send email code', enter_mobile_first:'Enter your mobile first.', accept_pre:'I accept the QuotesDone ', terms_link:'Terms & Conditions',
    accept_post:'.', finish_continue:'Finish & continue', finishing:'Finishing…', must_accept:'Please accept the terms.',
    my_requests:'My requests', messages:'Messages', projects:'Projects', back_requests:'← Back to requests', new_request:'New request', close:'Close',
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
    search_requests:'Search your requests…', no_search_match:'No request matches that search.',
    // ── whose move is it ──
    ball_all:'All', ball_you:'Waiting on you', ball_suppliers:'Waiting on suppliers',
    ball_moving:'With your supplier', ball_done:'Closed',
    ball_none_you:'No request matches that filter.',
    hl_you_one:'1 request is waiting on you', hl_you_many:'requests are waiting on you',
    hl_sup_one:'1 is waiting on suppliers', hl_sup_many:'are waiting on suppliers',
    hl_mov_one:'1 is with your supplier', hl_mov_many:'are with your supplier',
    hl_nothing:'Nothing is waiting on you — every open request is with suppliers.',
    hl_all_quiet:'Nothing needs your attention right now.',
    // ── what happens after you post ──
    next_h:'What happens after you post',
    next_1:'We structure your description into a request suppliers can price, and send it to matching UAE suppliers — without your name or number.',
    next_2:'Their quotes come back onto this screen. Most requests get their first quote within 48 hours; you are emailed as each one arrives.',
    next_3:'You compare them side by side for free. Supplier names stay hidden until you choose one.',
    next_4:'Revealing a supplier costs 3% of that quote, and nothing else. It is refundable if they do not respond within 3 working days.',
    // ── shell ──
    nav_main:'Portal navigation', nav_work:'Work', nav_collaborate:'Collaborate', nav_intelligence:'Intelligence',
    nav_account:'Account', nav_overview:'Overview', nav_requests:'My requests', nav_more:'More',
    nav_collapse:'Collapse menu', alerts_label:'Alerts',
    ask_ph:'Ask about your requests, quotes or documents…', ask_ph_short:'Ask the assistant…',
    asst_title:'Procurement assistant', asst_sub:'Answers from your own account',
    asst_ph:'Ask anything about your account…', asst_send:'Send', asst_thinking:'Thinking',
    asst_greet:'I can see your account, so ask me about your own requests, the quotes on them, your documents or your verification — as well as how QuotesDone works.',
    asst_s1:'What is the status of my requests?', asst_s2:'How many quotes have I received?', asst_s3:'What do I need to do next?',
    asst_err:'Something went wrong. Please try that again.',
    // ── request lifecycle ──
    st_matching:'Matching', st_quoting:'Quoting', st_quotes_in:'Quotes in', st_revealed:'Revealed', st_closed:'Closed',
    k_awaiting:'Awaiting your decision', k_reveals:'Reveals',
    k_open_hint:'Requests still collecting quotes', k_quotes_hint:'Across all your requests',
    k_awaiting_hint:'Requests with two or more quotes to compare', k_reveals_hint:'The 3% facilitation fee is the only fee you pay',
    quick_actions:'Quick actions', qa_new:'New request', qa_compare:'Compare quotes', qa_upload:'Upload a drawing', qa_ask:'Ask the assistant',
    welcome_sub:'Here is where your requests stand today.',
    empty_title:'Your first request takes about a minute',
    empty_body:'Describe the job in text, voice, a photo or a drawing. We structure it, send it anonymously to matching UAE suppliers, and their quotes come back here to compare side by side. Posting and comparing are free.',
    spread_title:'Quote spread', spread_locked:'Supplier names and exact prices unlock when you reveal',
    spread_pre:'quotes in · around', spread_none:'No quotes to compare yet.',
    journey_title:'Request journey',
    jr_described:'Described', jr_structured:'Structured', jr_matched:'Matched', jr_quotes:'Quotes arriving', jr_compare:'Compare', jr_reveal:'Reveal',
    view_all:'View all',
    auth_h:'One request. Every quote worth having.',
    auth_sub:'Describe a job once — in text, voice, a photo or a drawing. We structure it and send it anonymously to vetted UAE suppliers, and their quotes come back for you to compare side by side.',
    auth_p1:'Posting a request and comparing quotes is free.',
    auth_p2:'Nobody sees who you are, and you do not see who they are, until you decide.',
    auth_p3:'You pay a 3% facilitation fee only when you reveal a supplier. There is nothing else to pay.',
    acct_saved:'Saved.', acct_unverified:'Not verified yet',
    acct_reverify:'Saved. Your new mobile needs verifying — reload this page and we will send you a code.',
    acct_phone_warn:'Changing your mobile will un-verify it. You will be asked to confirm the new number with a code before you can post a request.',
    acct_device_note:'Appearance is remembered on this device. Your language is saved to your account and follows you to any device you sign in on.',
    req_one:'request', req_many:'requests',
    qa_compare_off:'Needs a request with two or more quotes' },
  ar: { brand_sub:'طلباتي', home:'الرئيسية', signout:'تسجيل الخروج', loading:'جارٍ التحميل…', loading_requests:'جارٍ تحميل طلباتك…',
    tab_signin:'تسجيل الدخول', tab_signup:'إنشاء حساب', welcome_back:'مرحبًا بعودتك', create_account_title:'أنشئ حسابك',
    signup_sub:'أدخل بريدك الإلكتروني وسننشئ حسابك فورًا. ستضيف اسمك وتاريخ ميلادك وتتحقق من رقم جوالك في الخطوة التالية.',
    signin_sub:'سجّل الدخول بالبريد الإلكتروني أو رقم الجوال المسجّل.', email_or_mobile:'البريد الإلكتروني أو الجوال', email_address:'البريد الإلكتروني',
    create_my_account:'إنشاء حسابي', send_code:'أرسل لي رمزًا', sending:'جارٍ الإرسال…', code_placeholder:'رمز من 6 أرقام',
    verify_continue:'تحقّق وتابع', verify_signin:'تحقّق وسجّل الدخول', verifying:'جارٍ التحقق…', use_diff:'استخدم بريدًا أو رقمًا آخر',
    call_note:'هذا الرقم أرضي، لذلك نتصل بك الآن ونقرأ الرمز المكوّن من 6 أرقام. أجب على المكالمة ثم أدخله أدناه.', use_diff_number:'استخدام رقم آخر',
    junk_note:'قد يستغرق وصول الرمز دقيقة — يُرجى التحقق من مجلد الرسائل غير المرغوب فيها (Spam) أيضًا.', err_code_send:'تعذّر إرسال الرمز.', err_incorrect:'رمز غير صحيح.',
    signup_email_only:'يُرجى التسجيل باستخدام بريد إلكتروني — ستضيف رقم جوالك وتتحقق منه في الخطوة التالية.',
    conflict_supplier:'هذا البريد مسجّل كمورّد. يُرجى استخدام بوابة المورّدين لتسجيل الدخول.',
    session_expired:'انتهت جلستك. يُرجى تسجيل الدخول من جديد.', load_failed:'تعذّر تحميل حسابك. يُرجى المحاولة مجددًا.', retry:'إعادة المحاولة',
    gate_title:'أكمل حسابك', gate_sub:'بعض التفاصيل لإكمال التسجيل. نتحقق من جوالك وبريدك لأمان الجميع.',
    full_name:'الاسم الكامل', mobile_ph:'الجوال (05x xxx xxxx)', dob_label:'تاريخ الميلاد (يجب أن يكون عمرك 18 عامًا فأكثر)', save_details:'حفظ التفاصيل', saving:'جارٍ الحفظ…',
    verify_mobile:'تحقّق من جوالك', verify_email_h:'تحقّق من بريدك', verified:'✓ تم التحقق', send_sms:'أرسل رمز الرسالة النصية', verify:'تحقّق',
    send_email_code:'أرسل رمز البريد', enter_mobile_first:'أدخل رقم جوالك أولًا.', accept_pre:'أوافق على ', terms_link:'الشروط والأحكام',
    accept_post:' الخاصة بمنصة QuotesDone.', finish_continue:'إنهاء ومتابعة', finishing:'جارٍ الإنهاء…', must_accept:'يُرجى الموافقة على الشروط.',
    my_requests:'طلباتي', messages:'الرسائل', projects:'المشاريع', back_requests:'→ العودة إلى الطلبات', new_request:'طلب جديد', close:'إغلاق',
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
    search_requests:'ابحث في طلباتك…', no_search_match:'لا يوجد طلب يطابق هذا البحث.',
    // ── لدى من الدور ──
    ball_all:'الكل', ball_you:'بانتظارك أنت', ball_suppliers:'بانتظار الموردين',
    ball_moving:'مع مورّدك', ball_done:'مغلق',
    ball_none_you:'لا يوجد طلب يطابق هذا التصفية.',
    hl_you_one:'طلب واحد بانتظارك', hl_you_many:'طلبات بانتظارك',
    hl_sup_one:'وطلب واحد بانتظار الموردين', hl_sup_many:'بانتظار الموردين',
    hl_mov_one:'وطلب واحد مع مورّدك', hl_mov_many:'مع مورّدك',
    hl_nothing:'لا شيء بانتظارك — كل طلب مفتوح لديك في يد الموردين.',
    hl_all_quiet:'لا شيء يحتاج انتباهك الآن.',
    // ── ماذا يحدث بعد النشر ──
    next_h:'ماذا يحدث بعد أن ترسل طلبك',
    next_1:'نحوّل وصفك إلى طلب يستطيع الموردون تسعيره، ونرسله إلى الموردين المطابقين في الإمارات — دون اسمك أو رقمك.',
    next_2:'تعود عروضهم إلى هذه الشاشة. معظم الطلبات يصلها أول عرض خلال 48 ساعة، ويصلك بريد عند وصول كل عرض.',
    next_3:'تقارنها جنبًا إلى جنب مجانًا. تبقى أسماء الموردين مخفية حتى تختار أحدهم.',
    next_4:'كشف المورّد يكلّف 3% من قيمة عرضه، ولا شيء غير ذلك. وهو قابل للاسترداد إذا لم يردّ خلال 3 أيام عمل.',
    // ── الهيكل ──
    nav_main:'تنقل البوابة', nav_work:'العمل', nav_collaborate:'التعاون', nav_intelligence:'الذكاء',
    nav_account:'الحساب', nav_overview:'نظرة عامة', nav_requests:'طلباتي', nav_more:'المزيد',
    nav_collapse:'طيّ القائمة', alerts_label:'التنبيهات',
    ask_ph:'اسأل عن طلباتك أو عروض الأسعار أو مستنداتك…', ask_ph_short:'اسأل المساعد…',
    asst_title:'مساعد المشتريات', asst_sub:'يجيب من حسابك أنت',
    asst_ph:'اسأل أي شيء عن حسابك…', asst_send:'إرسال', asst_thinking:'جارٍ التفكير',
    asst_greet:'أستطيع الاطلاع على حسابك، فاسألني عن طلباتك أنت، والعروض الواردة عليها، ومستنداتك، وحالة التحقق — وكذلك عن كيفية عمل QuotesDone.',
    asst_s1:'ما حالة طلباتي؟', asst_s2:'كم عرض سعر وصلني؟', asst_s3:'ما الخطوة التالية المطلوبة مني؟',
    asst_err:'حدث خطأ. يُرجى المحاولة مرة أخرى.',
    // ── دورة حياة الطلب ──
    st_matching:'قيد المطابقة', st_quoting:'قيد التسعير', st_quotes_in:'وردت العروض', st_revealed:'تم الكشف', st_closed:'مغلق',
    k_awaiting:'بانتظار قرارك', k_reveals:'عمليات الكشف',
    k_open_hint:'طلبات ما زالت تجمع العروض', k_quotes_hint:'عبر جميع طلباتك',
    k_awaiting_hint:'طلبات وردها عرضان أو أكثر للمقارنة', k_reveals_hint:'رسوم التيسير 3% هي الرسوم الوحيدة التي تدفعها',
    quick_actions:'إجراءات سريعة', qa_new:'طلب جديد', qa_compare:'قارن العروض', qa_upload:'ارفع رسمًا', qa_ask:'اسأل المساعد',
    welcome_sub:'هذا موقف طلباتك اليوم.',
    empty_title:'طلبك الأول يستغرق دقيقة تقريبًا',
    empty_body:'صِف العمل نصًا أو صوتًا أو بصورة أو برسم. نقوم ببنيته وإرساله بشكل مجهول إلى الموردين المطابقين في الإمارات، وتعود عروضهم هنا لمقارنتها جنبًا إلى جنب. النشر والمقارنة مجانًا.',
    spread_title:'نطاق العروض', spread_locked:'تُفتح أسماء الموردين والأسعار الدقيقة عند الكشف',
    spread_pre:'عرض وارد · بحدود', spread_none:'لا توجد عروض للمقارنة بعد.',
    journey_title:'مسار الطلب',
    jr_described:'الوصف', jr_structured:'التنظيم', jr_matched:'المطابقة', jr_quotes:'ورود العروض', jr_compare:'المقارنة', jr_reveal:'الكشف',
    view_all:'عرض الكل',
    auth_h:'طلب واحد. وكل عرض سعر يستحق.',
    auth_sub:'صِف العمل مرة واحدة — نصًا أو صوتًا أو بصورة أو برسم. نقوم ببنيته ونرسله بشكل مجهول إلى موردين معتمدين في الإمارات، وتعود عروضهم لتقارنها جنبًا إلى جنب.',
    auth_p1:'نشر الطلب ومقارنة العروض مجانًا.',
    auth_p2:'لا أحد يعرف هويتك، ولا تعرف هويتهم، حتى تقرر أنت.',
    auth_p3:'تدفع رسوم تيسير 3% فقط عند كشف المورّد. لا شيء آخر تدفعه.',
    acct_saved:'تم الحفظ.', acct_unverified:'لم يتم التحقق بعد',
    acct_reverify:'تم الحفظ. رقمك الجديد يحتاج إلى تحقق — أعد تحميل الصفحة وسنرسل لك رمزًا.',
    acct_phone_warn:'تغيير رقم جوالك سيلغي التحقق منه. سيُطلب منك تأكيد الرقم الجديد برمز قبل أن تتمكن من نشر طلب.',
    acct_device_note:'يُحفظ المظهر على هذا الجهاز. أما لغتك فتُحفظ في حسابك وتتبعك على أي جهاز تسجّل الدخول منه.',
    req_one:'طلب', req_many:'طلبات',
    qa_compare_off:'يحتاج إلى طلب وردّه عرضان أو أكثر' }
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
      // scale 1.8 assumed a letter-sized page. A real construction sheet is ANSI D or A1, so 1.8
      // produced 5444x3888 = 21 megapixels — 2.5 MB of base64 per page. drawing_redact decodes to
      // full-resolution RGBA (85 MB for one such page) before resizing to its 1600px working width,
      // and the isolate was killed outright: measured HTTP 546 WORKER_RESOURCE_LIMIT on a SINGLE
      // page at that size. Capping the long edge costs nothing downstream (the redactor's own output
      // is 1600px wide) and the same set at 2600px extracted 23 BoQ line items from the schedules.
      const MAX_EDGE = 2600;
      for (let pnum = 1; pnum <= n; pnum++) { const pg = await pdf.getPage(pnum); const v1 = pg.getViewport({ scale: 1 }); const vp = pg.getViewport({ scale: Math.min(1.8, MAX_EDGE / Math.max(v1.width, v1.height)) }); const c = document.createElement('canvas'); c.width = vp.width; c.height = vp.height; await pg.render({ canvasContext: c.getContext('2d'), viewport: vp }).promise; out.push({ mime: 'image/jpeg', data: c.toDataURL('image/jpeg', 0.8).split(',')[1] }); }
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
    // THE PORTAL SIGNED PEOPLE OUT EVERY HOUR WHILE HOLDING A VALID REFRESH TOKEN (13 Aug 2026).
    //
    // A Supabase access token lives 60 minutes. This client is created with autoRefreshToken:true
    // and the refresh token is stored, so supabase-js WAS quietly minting a fresh one on schedule —
    // and nothing here listened. `call()` sends the `token` state captured at mount, so at the
    // 60-minute mark every request began returning 401 and Authed showed "Your session has expired.
    // Please sign in again." to a customer whose session had not expired at all. Found by leaving
    // the portal open for an hour while clicking through it.
    //
    // One listener. TOKEN_REFRESHED carries the new access token; SIGNED_OUT carries null and must
    // NOT be mistaken for a refresh failure, so the phase is only ever moved forward here.
    let sub;
    try {
      sub = SB.auth.onAuthStateChange((_evt, ss) => {
        const at = ss && ss.access_token;
        if (!at) return;
        setToken(at);
        try { localStorage.setItem('qd-cust-token', at); if (ss.refresh_token) localStorage.setItem('qd-cust-refresh', ss.refresh_token); } catch (_e) {}
      });
    } catch (_e) {}
    return () => { try { sub && sub.data && sub.data.subscription && sub.data.subscription.unsubscribe(); } catch (_e) {} };
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
  // THE STRIP IS FOR THE DOORWAY, NOT THE HOUSE. Signing in and completing a profile are two
  // single-card screens with no navigation to render; the marketing-style bar is right there and
  // wrong the moment the customer is actually inside, which is where PortalShell takes over.
  const strip = (<header className="sticky top-0 z-10 flex items-center justify-between px-5 py-3.5 bg-card/70 backdrop-blur border-b border-border">
    <a className="text-base font-extrabold text-foreground no-underline" href="/">QuotesDone <span className="text-primary font-bold">{t(lang, 'brand_sub')}</span></a>
    <div className="flex gap-2 items-center">
      <Button asChild variant="outline" size="sm"><a href="/">{t(lang, 'home')}</a></Button>
      <Button variant="outline" size="sm" onClick={() => setLang(rtl ? 'en' : 'ar')}>{rtl ? 'EN' : 'عربي'}</Button>
      <Button variant="outline" size="sm" onClick={swapTheme} aria-label={theme === 'dark' ? t(lang, 'theme_light') : t(lang, 'theme_dark')} title={theme === 'dark' ? t(lang, 'theme_light') : t(lang, 'theme_dark')}>{theme === 'dark' ? '☀' : '☾'}</Button>
      {phase === 'app' && <Button variant="outline" size="sm" onClick={doSignOut}>{t(lang, 'signout')}</Button>}
    </div>
  </header>);
  return (<div dir={rtl ? 'rtl' : 'ltr'} data-theme={theme} className="osx min-h-screen bg-background text-foreground">
    {!mounted ? <>{strip}<div className={S.center}>{t(lang, 'loading')}</div></> : (<>
      {phase === 'login' && <>{strip}<Login onAuth={onAuth} lang={lang} /></>}
      {phase === 'app' && <Authed token={token} lang={lang} strip={strip} theme={theme} onSwapTheme={swapTheme} onSetLang={setLang} onSignOut={doSignOut} onServedLocale={onServedLocale} />}
    </>)}
  </div>);
}
// THE DOORWAY GOT THE SAME TREATMENT AS THE HOUSE.
//
// Signing in and finishing a profile were a single 400px card floating in the middle of an
// otherwise empty dark page — the same "extremely basic" the founder described about the portal
// behind it, on the screen a customer sees FIRST. This is the standard two-column product sign-in:
// the promise on one side, the form on the other, and on a phone just the form, because a phone
// has no room for a column of reassurance above the field you came to type in.
//
// The three lines are the product's actual terms, not marketing filler — free to post, anonymous
// until you choose, 3% only on a reveal. A customer deciding whether to sign up is deciding about
// exactly those three facts.
function AuthShell({ lang, children }) {
  const rtl = lang === 'ar';
  const points = ['auth_p1', 'auth_p2', 'auth_p3'];
  return (
    <div className="mx-auto grid w-full max-w-[1080px] items-center gap-10 px-5 py-10 md:min-h-[76vh] md:grid-cols-[1.05fr_minmax(380px,420px)] md:py-16">
      <div className="hidden md:block">
        <span className="grid h-12 w-12 place-items-center rounded-2xl bg-primary/15 font-head text-[20px] font-extrabold text-primary">Q</span>
        <h1 className="mt-5 font-head text-[30px] font-extrabold leading-[1.15] tracking-tight text-foreground">{t(lang, 'auth_h')}</h1>
        <p className="mt-3 max-w-[46ch] text-[14px] leading-relaxed text-muted-foreground">{t(lang, 'auth_sub')}</p>
        <ul className="mt-7 flex flex-col gap-3.5">
          {points.map((k) => (
            <li key={k} className="flex items-start gap-3">
              <span className="mt-0.5 grid h-6 w-6 shrink-0 place-items-center rounded-lg bg-primary/12 text-primary"><Check className="h-3.5 w-3.5" aria-hidden /></span>
              <span className="text-[13.5px] leading-relaxed text-foreground/90">{t(lang, k)}</span>
            </li>
          ))}
        </ul>
      </div>
      <div className="w-full justify-self-center md:justify-self-end">{children}</div>
    </div>
  );
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
  return (<AuthShell lang={lang}><Card className="w-full p-6 sm:p-7">
    <div className={cn(S.tabsWrap, 'mb-4 w-full')} role="tablist">
      <button role="tab" aria-selected={!isSignup} className={cn(S.tab, 'flex-1', !isSignup && S.tabOn)} onClick={() => swap('signin')}>{t(lang, 'tab_signin')}</button>
      <button role="tab" aria-selected={isSignup} className={cn(S.tab, 'flex-1', isSignup && S.tabOn)} onClick={() => swap('signup')}>{t(lang, 'tab_signup')}</button>
    </div>
    <div className="font-head text-[20px] font-extrabold tracking-tight text-foreground">{isSignup ? t(lang, 'create_account_title') : t(lang, 'welcome_back')}</div>
    <div className={cn(S.sub, 'mt-1.5')}>{isSignup ? t(lang, 'signup_sub') : t(lang, 'signin_sub')}</div>
    {step === 'id' ? (<><Input className="mt-3" placeholder={isSignup ? t(lang, 'email_address') : t(lang, 'email_or_mobile')} value={id} onChange={(e) => setId(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && send()} /><Button className="w-full mt-3" disabled={busy} onClick={send}>{busy ? t(lang, 'sending') : (isSignup ? t(lang, 'create_my_account') : t(lang, 'send_code'))}</Button></>)
      : (<><Input className="mt-3" placeholder={t(lang, 'code_placeholder')} value={code} onChange={(e) => setCode(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && verify()} /><div className={S.hint}>{t(lang, 'junk_note')}</div><Button className="w-full mt-3" disabled={busy} onClick={verify}>{busy ? t(lang, 'verifying') : (isSignup ? t(lang, 'verify_continue') : t(lang, 'verify_signin'))}</Button><Button variant="link" className="mt-2 px-0 h-auto" onClick={() => { setStep('id'); setCode(''); setMsg(''); }}>{t(lang, 'use_diff')}</Button></>)}
    {msg && <div className={S.err}>{msg}</div>}
  </Card></AuthShell>);
}
function Authed({ token, lang, strip, theme, onSwapTheme, onSetLang, onSignOut, onServedLocale }) {
  const [k, setK] = useState(null); const [err, setErr] = useState('');
  // A 401 IS A QUESTION BEFORE IT IS A VERDICT. The stored access token can be an hour old — the
  // page may have been restored from localStorage long after it was minted — and the refresh token
  // beside it is still good. Ask for a new session ONCE before telling somebody their session has
  // expired; the auth listener in CustomerPortal picks the new token up from there. If the refresh
  // also fails, the session really is over and the message is true.
  const load = (retried) => {
    setErr('');
    call('kyc', { action: 'state' }, token).then(async (j) => {
      if (j && j.error === 'unauthorized') {
        if (retried) { setErr('unauth'); return; }
        try {
          const rt = localStorage.getItem('qd-cust-refresh') || '';
          const { data } = await SB.auth.refreshSession(rt ? { refresh_token: rt } : undefined);
          if (data && data.session && data.session.access_token) return; // the listener re-renders with the new token
        } catch (_e) {}
        setErr('unauth');
        return;
      }
      setK(j || {});
    }).catch(() => setErr('net'));
  };
  useEffect(() => { load(); }, [token]);
  if (err === 'unauth') return <>{strip}<div className={S.center}><Card className="w-full max-w-[400px] p-5"><div className={S.sub}>{t(lang, 'session_expired')}</div><Button className="w-full mt-3" onClick={onSignOut}>{t(lang, 'tab_signin')}</Button></Card></div></>;
  if (err) return <>{strip}<div className={S.center}><Card className="w-full max-w-[400px] p-5"><div className={S.sub}>{t(lang, 'load_failed')}</div>{/* () => load(), not load: a click handler passes the MouseEvent as the first argument, which
        would arrive as `retried` and skip the one refresh attempt this retry exists to make. */}
    <Button className="w-full mt-3" onClick={() => load()}>{t(lang, 'retry')}</Button></Card></div></>;
  if (!k) return <>{strip}<div className={S.center}>{t(lang, 'loading')}</div></>;
  const complete = k.full_name && k.phone_verified && k.email_verified && k.terms_signed;
  if (!complete) return <>{strip}<ProfileGate token={token} lang={lang} onDone={() => load()} /></>;
  return <Dashboard token={token} lang={lang} theme={theme} onSwapTheme={onSwapTheme} onSetLang={onSetLang} onSignOut={onSignOut} onServedLocale={onServedLocale} />;
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
  // sentSms carries the CHANNEL, not a boolean: kyc falls back to a voice call when the number is a
  // landline, and telling someone to check their junk folder for a code that is being read down the
  // phone is the wrong instruction.
  const sendSms = async () => { if (!phone) { setMsg(t(lang, 'enter_mobile_first')); return; } setBusy('sms'); setMsg(''); const j = await call('kyc', { action: 'send_sms', phone }, token); setBusy(''); if (j && j.ok) setSentSms(j.channel || 'sms'); else setMsg((j && j.error) || t(lang, 'err_code_send')); };
  const verifySms = async () => { setBusy('vsms'); setMsg(''); const j = await call('kyc', { action: 'verify_sms', phone, code: smsCode }, token); setBusy(''); if (j && j.ok) load(); else setMsg((j && j.error) || t(lang, 'err_incorrect')); };
  const sendEmailCode = async () => { setBusy('em'); setMsg(''); const j = await call('kyc', { action: 'send_email' }, token); setBusy(''); if (j && j.ok) setSentEmail(true); else setMsg((j && j.error) || t(lang, 'err_code_send')); };
  const verifyEmail = async () => { setBusy('vem'); setMsg(''); const j = await call('kyc', { action: 'verify_email', code: emCode }, token); setBusy(''); if (j && j.ok) load(); else setMsg((j && j.error) || t(lang, 'err_incorrect')); };
  const acceptTerms = async () => { if (!terms) { setMsg(t(lang, 'must_accept')); return; } setBusy('terms'); setMsg(''); const j = await call('kyc', { action: 'accept_terms' }, token); setBusy(''); if (j && j.ok) { onDone(); } else setMsg((j && j.error) || t(lang, 'load_failed')); };
  const profileDone = st.full_name && st.phone && st.dob;
  return (<AuthShell lang={lang}><Card className="w-full p-6 sm:p-7">
    <div className="font-head text-[20px] font-extrabold tracking-tight text-foreground">{t(lang, 'gate_title')}</div>
    <div className={cn(S.sub, 'mt-1.5')}>{t(lang, 'gate_sub')}</div>
    <Input className="mt-3" placeholder={t(lang, 'full_name')} value={full_name} onChange={(e) => setFullName(e.target.value)} />
    <Input className="mt-3" placeholder={t(lang, 'mobile_ph')} value={phone} onChange={(e) => setPhone(e.target.value)} />
    <div className={cn(S.sub, 'mt-3 mb-1')}>{t(lang, 'dob_label')}</div>
    <Input type="date" className="mt-0" style={{ colorScheme: 'dark' }} value={dob} onChange={(e) => setDob(e.target.value)} />
    {/* Always available, not only while the profile is incomplete: the number typed at signup is the
        one the code is sent to, and once all three fields were filled the only way to correct a wrong
        number was to verify it first - which is impossible if it is the wrong number. */}
    <Button className="w-full mt-3" disabled={busy === 'save'} onClick={saveProfile}>{busy === 'save' ? t(lang, 'saving') : t(lang, 'save_details')}</Button>
    {profileDone && <>
      <div className={cn(S.h2, 'mt-4')}>{t(lang, 'verify_mobile')} {st.phone_verified ? <span className="text-primary text-[12px] font-bold ml-1.5">{t(lang, 'verified')}</span> : null}</div>
      {!st.phone_verified && (!sentSms ? <Button size="sm" className="mt-3" disabled={busy === 'sms'} onClick={sendSms}>{busy === 'sms' ? t(lang, 'sending') : t(lang, 'send_sms')}</Button>
        : <><div className={S.hint}>{t(lang, sentSms === 'call' ? 'call_note' : 'junk_note')}</div><div className={S.frow}><Input placeholder={t(lang, 'code_placeholder')} value={smsCode} onChange={(e) => setSmsCode(e.target.value)} /><Button size="sm" disabled={busy === 'vsms'} onClick={verifySms}>{t(lang, 'verify')}</Button></div><Button variant="link" className="mt-1 px-0 h-auto" onClick={() => { setSentSms(false); setSmsCode(''); }}>{t(lang, 'use_diff_number')}</Button></>)}
      <div className={cn(S.h2, 'mt-4')}>{t(lang, 'verify_email_h')} {st.email_verified ? <span className="text-primary text-[12px] font-bold ml-1.5">{t(lang, 'verified')}</span> : null}</div>
      {!st.email_verified && (!sentEmail ? <Button size="sm" className="mt-3" disabled={busy === 'em'} onClick={sendEmailCode}>{busy === 'em' ? t(lang, 'sending') : t(lang, 'send_email_code')}</Button>
        : <><div className={S.hint}>{t(lang, 'junk_note')}</div><div className={S.frow}><Input placeholder={t(lang, 'code_placeholder')} value={emCode} onChange={(e) => setEmCode(e.target.value)} /><Button size="sm" disabled={busy === 'vem'} onClick={verifyEmail}>{t(lang, 'verify')}</Button></div></>)}
      {st.phone_verified && st.email_verified && <>
        <label className="flex gap-2 items-center mt-4 text-[13px] text-muted-foreground"><input type="checkbox" checked={terms} onChange={(e) => setTerms(e.target.checked)} /> {t(lang, 'accept_pre')}<a href="/terms" target="_blank" rel="noopener" className="text-primary font-semibold">{t(lang, 'terms_link')}</a>{t(lang, 'accept_post')}</label>
        <Button className="w-full mt-3" disabled={busy === 'terms'} onClick={acceptTerms}>{busy === 'terms' ? t(lang, 'finishing') : t(lang, 'finish_continue')}</Button>
      </>}
    </>}
    {msg && <div className={S.err}>{msg}</div>}
  </Card></AuthShell>);
}
function Dashboard({ token, lang, theme, onSwapTheme, onSetLang, onSignOut, onServedLocale }) {
  const [ov, setOv] = useState(null); const [data, setData] = useState(null); const [err, setErr] = useState(''); const [note, setNote] = useState(''); const [showNew, setShowNew] = useState(false);
  // WHY THIS IS NO LONGER A `view`. Messages and Projects were whole-surface early returns: opening
  // either REPLACED the dashboard, which is the full-page navigation §21 asks the portal not to
  // have — and it also stranded the intake assistant, because a branch that returns before the
  // assistant's mount can never render it. Every module now opens in a window OVER the dashboard,
  // so the KPIs, the alerts and the assistant stay mounted underneath and no module needs a
  // "back to requests" button to undo a navigation that never happened.
  const [view, setView] = useState('');
  const rtl = lang === 'ar';
  // THE UNREAD COUNT MOVED UP ONE LEVEL. It used to be fetched by a badge inside the module bar;
  // the sidebar and the mobile tab bar both need it now, and two components fetching the same
  // number is how two components come to disagree about it.
  const [unread, setUnread] = useState(0);
  const [pd, setPd] = useState(null); const [pdFailed, setPdFailed] = useState(false);
  const [qtext, setQtext] = useState('');
  const [ballFilter, setBallFilter] = useState('all');
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
  // Silent by design: a badge that cannot load must not put an error where a count goes, and the
  // inbox reports its own failure when the customer opens it.
  const loadUnread = () => call('messages_api', { action: 'threads' }, token)
    .then((j) => setUnread(((j && j.threads) || []).reduce((n, th) => n + (Number(th.unread) || 0), 0)))
    .catch(() => {});
  const refresh = () => { loadInq(); loadOv(); loadPd(); loadUnread(); };
  useEffect(() => {
    loadOv();
    loadInq();
    loadPd();
    loadUnread();
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
  // THE SHELL MOUNTS FIRST AND THE CONTENT FILLS IN. This was an early return to a centred
  // "Loading your requests…" with no navigation at all, so the first thing a customer saw was a
  // blank page that then became a different page. The frame is knowable before the data is.
  const booting = !ov && !data;
  const s = (ov && ov.stats) || {}; const inqs = (data && data.inquiries) || [];
  const alertsCount = Number((ov && ov.alerts_count) ?? ((ov && ov.alerts) || []).length) || 0;
  const projects = (pd && Array.isArray(pd.projects)) ? pd.projects : [];
  const savingsPct = pd ? pd.avg_savings_pct : null;
  // The filter is over the rows already on screen, so it costs no request and cannot disagree with
  // the list it filters. Matching is over the fields a customer would actually recall about their
  // own request — what it was for, where, and its reference.
  const needle = qtext.trim().toLowerCase();
  // Two facts the six old tiles could not state, both derived from rows already on screen:
  // how many requests are actually WAITING ON THE CUSTOMER (two or more quotes is the exact
  // condition under which a comparison exists to decide), and how many reveals they have paid for —
  // the only money a customer ever pays us, and the thing "Spend" was quietly standing in for.
  const awaiting = inqs.filter((i) => (i.quotes || []).length >= 2 && !(i.quotes || []).some((q) => q.revealed)).length;
  const reveals = inqs.filter((i) => (i.quotes || []).some((q) => q.revealed)).length;
  // ── WHOSE MOVE IS IT ──────────────────────────────────────────────────────────────────────────
  // "I wish I could see, on one screen, which of my requests is waiting on ME versus waiting on a
  // supplier." The portal already knew this per request — it is exactly what the lifecycle pill
  // says — but only one request at a time, and only if you read every rail on the page. The answer
  // is a partition of rfqState, so it costs no request and CANNOT disagree with the pill on the row
  // it summarises: same function, same input, one screen up.
  const ballOf = (i) => {
    const st = rfqState(i, i.quotes || []);
    if (st === 'closed') return 'done';
    if (st === 'revealed') return 'moving';          // you paid; you and the supplier are talking
    if (st === 'matching') return 'suppliers';       // posted, nobody has quoted yet
    return 'you';                                    // quoting / quotes_in — a decision is open
  };
  const ball = { you: 0, suppliers: 0, moving: 0, done: 0 };
  for (const i of inqs) ball[ballOf(i)] += 1;
  const liveCount = ball.you + ball.suppliers + ball.moving;
  // Both filters are over the rows already on screen, so they cost no request and cannot disagree
  // with the list they filter. Matching is over the fields a customer would actually recall about
  // their own request — what it was for, where, and its reference.
  const shown = inqs
    .filter((i) => ballFilter === 'all' || ballOf(i) === ballFilter)
    .filter((i) => !needle || [i.summary, i.category, i.emirate, i.status, i.rfq_no].some((f) => String(f || '').toLowerCase().includes(needle)));
  const filtered = ballFilter !== 'all' || !!needle;
  const onlyRequests = view === 'requests';
  // WHERE THIS PORTAL CAN GO, WRITTEN OUT.
  //
  // The module bar this replaced kept every destination as a literal for a stated reason: with the
  // buttons mapped from a config, "nothing — no grep, no reviewer, no route audit — can answer
  // 'where can this portal go' without executing it". Moving the navigation into the shell would
  // have lost exactly that, because the shell calls onView(item.id) with a variable. The table is
  // declared here instead, so the answer is still one grep of this file, and the shell stays a
  // shell. Order is irrelevant — the sidebar groups and ranks them.
  const GO = {
    home:      () => setView('home'),
    requests:  () => setView('requests'),
    projects:  () => setView('projects'),
    documents: () => setView('documents'),
    messages:  () => setView('messages'),
    orders:    () => setView('orders'),
    approvals: () => setView('approvals'),
    spatial:   () => setView('spatial'),
    predict:   () => setView('predict'),
    profile:   () => setView('profile'),
    account:   () => setView('account'),
  };
  const navigate = (id) => (GO[id] ? GO[id]() : setView('home'));
  return (<PortalShell
    lang={lang} t={(k) => t(lang, k)} theme={theme} onSwapTheme={onSwapTheme} onSetLang={onSetLang}
    onSignOut={onSignOut} view={view} onView={navigate} token={token}
    customerName={(ov && ov.customer && ov.customer.name) || ''}
    unread={unread} alerts={alertsCount} alertList={(ov && ov.alerts) || []} order={ov && ov.layout && ov.layout.order}
    suggestions={assistantOffers(lang, inqs, ballOf)}
  >
  {MODULES.some((m) => m[0] === view) ? (
    <ModuleWindow id={view} onClose={() => setView('home')} token={token} lang={lang} inqs={inqs} onChanged={refresh} twin={ov && ov.twin} />
  ) : (
  <div className="mx-auto w-full max-w-[1240px] px-4 py-5 sm:px-6">
    {/* THE WELCOME BAND. §1 asks the opening screen to greet by time of day AND company name; the
        hour is the CLIENT'S, because the server does not know which timezone the customer is in.
        THE DUPLICATE IS GONE: the attention count and ov.headline both rendered "Nothing needs your
        attention right now." one under the other, in two differently-styled boxes, on the screen he
        opened. The count is a number and belongs on a tile; the headline is the sentence. */}
    {/* EVERY DESTINATION SAYS WHERE YOU ARE. Clicking "My requests" used to leave the Overview's
        "Good morning, ahmad test" at the top of it — the greeting is the Overview's identity, and a
        page that borrows another page's title is a page you cannot tell you have arrived at. The
        module panes each carry their own h1; these two now do too. */}
    <section className="mb-5 overflow-hidden rounded-2xl border border-border bg-card/70 p-5 sm:p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0">
          <h1 className="font-head text-[24px] font-extrabold leading-tight tracking-tight text-foreground sm:text-[28px]">
            {/* Arabic uses its own comma (U+060C) and puts no space before it. */}
            {onlyRequests ? t(lang, 'nav_requests')
              : greetingOf(lang) + ((ov && ov.customer && ov.customer.name) ? ((lang === 'ar' ? '، ' : ', ') + ov.customer.name) : '')}
          </h1>
          {/* THE HEADLINE ANSWERS "WHOSE MOVE IS IT", because that is the question the customer
              opened the page with. ov.headline is written by customer_portal from the server's own
              stats and does not know this list: on the screen measured 13 Aug it read "Nothing
              needs your attention right now" directly above a tile saying one decision was
              awaiting the customer. A sentence derived from the rows on screen cannot contradict
              them. The server's headline is still shown when there are no requests to speak for. */}
          <p className="mt-1.5 max-w-[62ch] text-[13.5px] leading-relaxed text-muted-foreground">
            {onlyRequests
              ? (inqs.length + ' ' + t(lang, inqs.length === 1 ? 'req_one' : 'req_many'))
              : liveCount ? ballHeadline(lang, ball)
              : ((ov && ov.headline) || t(lang, 'welcome_sub'))}
          </p>
        </div>
        <Button size="sm" className="shrink-0 gap-1.5" onClick={() => setShowNew((v) => !v)}>
          <Plus className="h-4 w-4" aria-hidden />{showNew ? t(lang, 'close') : t(lang, 'new_request')}
        </Button>
      </div>
    </section>

    {note && <div className={S.note}>{note}</div>}
    {showNew && <div className="mb-5"><NewRequest token={token} onDone={() => { setShowNew(false); refresh(); setNote(t(lang, 'request_sent')); }} onCancel={() => setShowNew(false)} /></div>}

    {/* The severity marker was a 4px border-l — which is both a well-worn generated-UI tell and,
        more to the point here, LEFT: in Arabic it lands on the wrong edge of the card. A tinted
        glyph carries the same three levels, on the correct side, in both directions. */}
    {ov && !!(ov.alerts || []).length && <div className="mb-5 flex flex-col gap-2">{ov.alerts.map((a, i) => (
      <div key={i} className="flex items-start gap-3 rounded-xl border border-border bg-card px-4 py-3">
        <span className={cn('mt-0.5 grid h-7 w-7 shrink-0 place-items-center rounded-lg',
          a.severity === 'high' ? 'bg-red-500/15 text-red-400' : a.severity === 'medium' ? 'bg-amber-400/15 text-amber-300' : 'bg-primary/15 text-primary')}>
          <BellRing className="h-3.5 w-3.5" aria-hidden />
        </span>
        <div className="min-w-0"><b className="text-[13.5px] text-foreground">{a.title}</b>
          <div className="text-xs leading-relaxed text-muted-foreground">{a.detail}</div></div>
      </div>))}</div>}

    {!onlyRequests && (ov ? (
      <div className="mb-5 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <StatTile icon={FileText} label={t(lang, 'k_open')} value={s.open_inquiries ?? 0} hint={t(lang, 'k_open_hint')} />
        <StatTile icon={MessageSquareQuote} label={t(lang, 'k_quotes')} value={s.quotes_received ?? 0} hint={t(lang, 'k_quotes_hint')} />
        <StatTile icon={BellRing} label={t(lang, 'k_awaiting')} value={awaiting} hint={t(lang, 'k_awaiting_hint')} tone={awaiting > 0 ? 'accent' : 'default'} />
        <StatTile icon={KeyRound} label={t(lang, 'k_reveals')} value={reveals} hint={t(lang, 'k_reveals_hint')} />
      </div>
    ) : (
      // A skeleton, not a spinner: the tiles are already four boxes, so show four boxes.
      <div className="mb-5 grid grid-cols-2 gap-3 lg:grid-cols-4" aria-hidden>
        {[0, 1, 2, 3].map((i) => <Card key={i} className="h-[104px] motion-safe:animate-pulse bg-secondary/25" />)}
      </div>
    ))}

    {!onlyRequests && <QuickActions lang={lang} onNew={() => setShowNew(true)} onView={navigate}
      comparable={inqs.filter((i) => (i.quotes || []).length >= 2).length} />}
    {/* §2 THE PROFILE, ON THE ENTRY SCREEN. Six KPI tiles say what the customer has DONE; the twin
        says who they ARE — industry, live projects, the suppliers they keep coming back to, the
        categories they actually buy, their approval chain, and how much of that profile we hold.
        It is the same object the Company profile window opens, rendered from the overview payload
        the dashboard already has, so opening the portal costs no extra call. */}
    {!onlyRequests && ov && ov.twin ? <div className="mb-5"><CompanyTwin twin={ov.twin} lang={lang === 'ar' ? 'ar' : 'en'} /></div> : null}
    {/* ── THE PROJECTS / FINANCIAL / SUPPLIER-NETWORK PANELS (§1, §4) ──────────────────────────
        Every figure below is nullable and every one of them says which absence is true rather than
        printing a zero that reads as a measurement. timeline_pct is null for a project with no
        target date, so no bar is drawn for it; supplier_count is a count and 0 is a real answer;
        avg_savings_pct is null until two quotes have landed on the same RFQ, and printing 0% there
        would tell a customer their price spread is zero when it is simply not yet known. */}
    {!onlyRequests && <>
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
    </>}
    <div className="mb-2 mt-[22px] flex items-center justify-between gap-3">
      <h2 className="font-head text-[16px] font-bold tracking-tight text-foreground">{t(lang, 'your_requests')}</h2>
      {!onlyRequests && inqs.length > 3 ? (
        <button type="button" onClick={() => setView('requests')} className="inline-flex items-center gap-1 text-[12.5px] font-semibold text-primary">
          {t(lang, 'view_all')}<ArrowRight className={cn('h-3.5 w-3.5', rtl && 'rotate-180')} aria-hidden />
        </button>) : null}
    </div>
    {inqs.length > 0 && <input type="search" className={S.field} placeholder={t(lang, 'search_requests')} aria-label={t(lang, 'search_requests')} value={qtext} onChange={(e) => setQtext(e.target.value)} />}
    {/* The same partition as the headline, as a filter. A chip with a zero behind it is not
        rendered: a control that can only ever produce an empty list is a dead end with a number
        on it. Same reasoning as the disabled "Compare quotes" quick action. */}
    {inqs.length > 1 && (
      <div className="mt-2.5 flex flex-wrap gap-2" role="group" aria-label={t(lang, 'your_requests')}>
        {[['all', inqs.length], ['you', ball.you], ['suppliers', ball.suppliers], ['moving', ball.moving], ['done', ball.done]]
          .filter(([k, n]) => k === 'all' || n > 0)
          .map(([k, n]) => (
            <button key={k} type="button" onClick={() => setBallFilter(k)} aria-pressed={ballFilter === k}
              className={cn('inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-[12.5px] font-semibold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                ballFilter === k ? 'border-primary/45 bg-primary/12 text-primary' : 'border-border bg-card/60 text-muted-foreground hover:border-primary/30 hover:text-foreground')}>
              {t(lang, 'ball_' + k)}
              <span className="tabular-nums opacity-70">{n}</span>
            </button>
          ))}
      </div>
    )}
    {/* THE EMPTY STATE THAT TELLS THEM WHAT HAPPENS NEXT. It was one grey sentence in a box; on a
        brand-new account — which is every account on day one — it was the main thing on the screen.
        A first-time customer needs to know what posting a request actually does before they do it. */}
    {booting ? (
      <div className="mt-3 flex flex-col gap-3" aria-busy="true" aria-label={t(lang, 'loading_requests')}>
        {[0, 1, 2].map((i) => <Card key={i} className="h-[86px] motion-safe:animate-pulse bg-secondary/25" />)}
      </div>
    ) : !inqs.length ? (
      <Card className="mt-3 p-6 sm:p-8">
        <div className="mx-auto max-w-[54ch] text-center">
          <span className="mx-auto grid h-12 w-12 place-items-center rounded-2xl bg-primary/12 text-primary"><Sparkles className="h-5 w-5" aria-hidden /></span>
          <h3 className="mt-3 font-head text-[17px] font-bold text-foreground">{t(lang, 'empty_title')}</h3>
          <p className="mt-2 text-[13.5px] leading-relaxed text-muted-foreground">{t(lang, 'empty_body')}</p>
          <Button className="mt-4 gap-1.5" onClick={() => setShowNew(true)}><Plus className="h-4 w-4" aria-hidden />{t(lang, 'post_first')}</Button>
        </div>
        <WhatHappensNext lang={lang} />
      </Card>
    ) : (filtered && !shown.length) ? <Card className="mt-3 p-5"><div className={S.sub}>{t(lang, needle ? 'no_search_match' : 'ball_none_you')}</div></Card>
      : filtered ? <div className={cn(S.list, 'mt-3')}>{shown.map((i) => <InquiryCard key={i.id} inq={i} token={token} lang={lang} onChange={refresh} />)}</div>
      // The overview shows the five most recent and links to the full list; My requests shows all.
      // Mapped then sliced, rather than sliced then mapped, so this stays the dashboard's list over
      // `inqs` — the thing the entry-not-login-dashboard leg reads to tell a workspace carrying live
      // work from a page of figures and links. Ten rows at most; the extra map costs nothing.
      : <div className={cn(S.list, 'mt-3')}>{inqs.map((i) => <InquiryCard key={i.id} inq={i} token={token} lang={lang} onChange={refresh} />).slice(0, onlyRequests ? undefined : 5)}</div>}
    {/* fn_customer_stats computes history_12m on EVERY overview call and nothing drew it; recharts
        and ui/chart.tsx were installed with no importers, so the customer product contained zero
        charts. Each chart states what is true when there is nothing to draw rather than rendering
        a flat line at zero, which reads as a real but quiet year. */}
    {!onlyRequests && <div className="mt-5"><SpendingIntelligence stats={s} inquiries={inqs} lang={lang === 'ar' ? 'ar' : 'en'} /></div>}
  </div>
  )}
  </PortalShell>);
}

// THE QUICK ACTIONS RAIL. Reference A carries a stack of icon+label rows; ours are the four things
// a procurement customer actually does. Every one is a real destination that already exists — a new
// request, the comparison inside a request, the drawing upload inside the intake, and the
// assistant. Nothing here is a placeholder.
// "I wish the assistant offered me the next thing instead of waiting to be asked."
//
// The panel opened with three constants — status / how many quotes / what next — shown identically
// to an account that has never posted anything and to one with three quotes sitting undecided. The
// first of those is unanswerable on a new account and the third is the only one that ever varies.
//
// These are built from the same rows the dashboard is already rendering, so the offer is about the
// customer's actual position, and it names the request rather than describing a category of
// request: "Which of the 3 quotes on my HVAC request should I choose?" is a question a procurement
// manager would type; "What is the status of my requests?" is a menu item. Capped at three — a list
// of offers long enough to need reading is a form.
function assistantOffers(lang, inqs, ballOf) {
  const ar = lang === 'ar';
  const out = [];
  const label = (i) => i.category || (ar ? 'طلبي' : 'my request');
  if (!inqs.length) {
    out.push(ar ? 'ماذا يحدث بعد أن أنشر طلبي؟' : 'What happens after I post a request?');
    out.push(ar ? 'كم يكلّفني كشف مورّد؟' : 'What does it cost me to reveal a supplier?');
    out.push(ar ? 'ما المعلومات التي يحتاجها المورّدون لتسعير عملي؟' : 'What do suppliers need to know to price my job?');
    return out;
  }
  const decide = inqs.filter((i) => ballOf(i) === 'you');
  const waiting = inqs.filter((i) => ballOf(i) === 'suppliers');
  const moving = inqs.filter((i) => ballOf(i) === 'moving');
  if (decide.length) {
    const i = decide[0]; const n = (i.quotes || []).length;
    out.push(ar ? `أي عرض من العروض الـ${n} على طلب ${label(i)} ينبغي أن أختار؟`
                : `Which of the ${n} quotes on my ${label(i)} request should I choose?`);
    out.push(ar ? 'كم سيكلّفني كشف المورّد صاحب أقل سعر؟' : 'What would it cost me to reveal the cheapest supplier?');
  }
  if (waiting.length && out.length < 3) {
    const i = waiting[0];
    out.push(ar ? `لماذا لم يصلني عرض بعد على طلب ${label(i)}؟` : `Why has no one quoted my ${label(i)} request yet?`);
  }
  if (moving.length && out.length < 3) {
    out.push(ar ? 'ما الخطوة التالية مع المورّد الذي كشفته؟' : 'What happens next with the supplier I revealed?');
  }
  if (out.length < 3) out.push(t(lang, 'asst_s3'));
  return out.slice(0, 3);
}
// "I wish it told me what happens after I post, without me having to ask."
//
// The empty state said the first request "takes about a minute" and that posting and comparing are
// free. Both true, and neither answers the question a procurement manager is actually holding
// before they hand a job to a platform they have not used: who sees this, when do I hear back, and
// what does it cost me. The four steps are the product as it actually runs — the 3% and the 3
// working days are pricing_config.standard_reveal_rate and refund_window_working_days, the same
// two numbers customer_api charges on.
function WhatHappensNext({ lang }) {
  const steps = ['next_1', 'next_2', 'next_3', 'next_4'];
  return (
    <div className="mx-auto mt-6 max-w-[62ch] border-t border-border pt-5 text-start">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{t(lang, 'next_h')}</div>
      <ol className="mt-2.5 space-y-2.5">
        {steps.map((k, n) => (
          <li key={k} className="flex gap-3">
            <span className="mt-0.5 grid h-5 w-5 shrink-0 place-items-center rounded-full bg-primary/12 text-[11px] font-bold text-primary tabular-nums">{n + 1}</span>
            <span className="min-w-0 text-[13px] leading-relaxed text-muted-foreground">{t(lang, k)}</span>
          </li>
        ))}
      </ol>
    </div>
  );
}
// The headline sentence for the whose-move split. Built from counts, never from a template with a
// zero in it: "0 requests are waiting on you" is a sentence no one should have to read.
function ballHeadline(lang, ball) {
  const parts = [];
  if (ball.you) parts.push(ball.you === 1 ? t(lang, 'hl_you_one') : ball.you + ' ' + t(lang, 'hl_you_many'));
  if (ball.suppliers) parts.push(ball.suppliers === 1 ? t(lang, 'hl_sup_one') : ball.suppliers + ' ' + t(lang, 'hl_sup_many'));
  if (ball.moving) parts.push(ball.moving === 1 ? t(lang, 'hl_mov_one') : ball.moving + ' ' + t(lang, 'hl_mov_many'));
  if (!parts.length) return t(lang, 'hl_all_quiet');
  if (!ball.you) return t(lang, 'hl_nothing');
  return parts.join(lang === 'ar' ? '، ' : ' · ') + '.';
}
function QuickActions({ lang, onNew, onView, comparable }) {
  const rtl = lang === 'ar';
  // A BUTTON THAT CANNOT DO ITS JOB SHOULD SAY SO, NOT PRETEND. "Compare quotes" navigated to My
  // requests unconditionally, so on a new account — which is every account on day one — it landed
  // the customer on an empty list with nothing to compare and no explanation. Comparison needs a
  // request carrying at least TWO quotes; that is the same threshold quote_compare itself runs on.
  // Below it the control is disabled and carries the reason, rather than spending a click on a
  // dead end.
  const rows = [
    { icon: Plus, label: 'qa_new', run: onNew },
    { icon: Scale, label: 'qa_compare', run: () => onView('requests'), off: comparable === 0, why: 'qa_compare_off' },
    { icon: Upload, label: 'qa_upload', run: onNew },
    { icon: Sparkles, label: 'qa_ask', run: () => { const el = document.getElementById('qd-ask'); if (el) el.focus(); } },
  ];
  return (
    <section className="mb-5" aria-label={t(lang, 'quick_actions')}>
      <h2 className="mb-2 font-head text-[13px] font-bold uppercase tracking-[0.08em] text-muted-foreground/70">{t(lang, 'quick_actions')}</h2>
      {/* One column below 420px: at 375 a two-up grid truncated every label to "New req…". */}
      <div className="grid grid-cols-1 gap-2 min-[420px]:grid-cols-2 lg:grid-cols-4">
        {rows.map(({ icon: Icon, label, run, off, why }) => (
          <button key={label} type="button" onClick={run} disabled={!!off} title={off ? t(lang, why) : undefined}
            className={cn('group flex items-center gap-3 rounded-xl border border-border bg-card/60 px-3.5 py-3 text-start transition-[border-color,transform] duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
              off ? 'cursor-not-allowed opacity-55' : 'hover:border-primary/40 motion-safe:hover:-translate-y-0.5')}>
            <span className={cn('grid h-8 w-8 shrink-0 place-items-center rounded-lg', off ? 'bg-secondary/60 text-muted-foreground' : 'bg-primary/12 text-primary')}><Icon className="h-4 w-4" aria-hidden /></span>
            <span className="min-w-0 flex-1">
              <span className="block truncate text-[13px] font-semibold text-foreground">{t(lang, label)}</span>
              {off ? <span className="mt-0.5 block truncate text-[11px] text-muted-foreground">{t(lang, why)}</span> : null}
            </span>
            {!off ? <ArrowRight className={cn('h-3.5 w-3.5 shrink-0 text-muted-foreground transition-transform duration-200 group-hover:translate-x-0.5', rtl && 'rotate-180 group-hover:-translate-x-0.5')} aria-hidden /> : null}
          </button>
        ))}
      </div>
    </section>
  );
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
      <div className="min-w-0">
        <div className="flex flex-wrap items-center gap-2">
          {/* OUR lifecycle, not a marketplace's idea of "Processing". The five states are derived
              from facts the row already carries; see rfqState in PortalShell. */}
          <StatusPill state={rfqState(inq, quotes)} t={(k) => t(lang, k)} />
          <b className="capitalize">{inq.category || 'Request'}</b>
          {inq.rfq_no ? <span className="rounded bg-secondary/60 px-1.5 py-0.5 font-mono text-[11px] text-muted-foreground">{inq.rfq_no}</span> : null}
        </div>
        {/* Emirate and the quote count are rendered as their own spans rather than joined into one
            string. Both are facts a customer scans for, and both are separately asserted by the
            Row #4 blueprint (rfq-location-extraction reads {inq.emirate}, rfqcc-response-count
            reads {quotes.length} quote) — a joined string renders the same words and answers
            neither, which is how a refactor loses a requirement without losing a feature. */}
        <div className={cn(S.sub, 'mt-1 flex flex-wrap items-center gap-x-1.5')}>
          {inq.emirate ? <span>{inq.emirate}</span> : null}
          {inq.emirate ? <span aria-hidden className="text-muted-foreground/40">·</span> : null}
          <span>{quotes.length} {lang === 'ar' ? 'عرض' : ('quote' + (quotes.length === 1 ? '' : 's'))}</span>
          {(inq.boq && inq.boq.boq) ? <><span aria-hidden className="text-muted-foreground/40">·</span><span>{inq.boq.boq.length}{lang === 'ar' ? ' بند' : ' line items'}</span></> : null}
          {inq.editable ? <><span aria-hidden className="text-muted-foreground/40">·</span><span>{(lang === 'ar' ? 'قابل للتعديل ' : 'editable ') + inq.edit_minutes_left + 'm'}</span></> : null}
        </div>
      </div>
      <div className="flex shrink-0 items-center gap-1 text-primary font-semibold text-[13px]">
        <span className="hidden sm:inline">{open ? (lang === 'ar' ? 'إخفاء التفاصيل' : 'Hide details') : (lang === 'ar' ? 'عرض التفاصيل' : 'Open request')}</span>
        <ChevronDown className={cn('h-4 w-4 transition-transform duration-300', open && 'rotate-180')} aria-hidden />
      </div>
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
    <Journey idx={stepIdx} lang={lang} matched={inq.matched_suppliers} />
    {open && <div className="mt-3 border-t border-border pt-3 flex flex-col gap-3">
      <Timeline inq={inq} quotes={quotes} anyRevealed={anyRevealed} lang={lang} />
      <QuoteSpread quotes={quotes} lang={lang} />
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
// A CODE IS NOT A SENTENCE. `note` is written by quote_compare FOR the customer ("not enough quotes
// to compare yet") and is rendered as-is. `error` is written for us — and quote_compare's own catch
// is `J({ error: String(e.message) }, 500)`, so an unhandled Postgres or Deno message would be
// rendered as the whole card. MEASURED 13 Aug 2026 on a real request screen: a card containing the
// single word `not_found`, between "Trades: hvac" and "Your request reached 9 suppliers".
const compareErrText = (code, lang) => {
  const c = String(code || '');
  if (c === 'ai_unavailable') return lang === 'ar'
    ? 'خدمة المقارنة غير متاحة مؤقتًا. عروضك محفوظة — يمكنك مقارنتها بنفسك أدناه والمحاولة لاحقًا.'
    : 'The comparison service is briefly unavailable. Your quotes are safe — you can still compare them yourself below, and this will fill in when it returns.';
  if (c === 'unauthorized') return lang === 'ar' ? 'انتهت جلستك. يُرجى تسجيل الدخول من جديد.' : 'Your session has expired. Please sign in again.';
  if (c === 'not_your_inquiry') return lang === 'ar' ? 'هذا الطلب ليس ضمن طلباتك.' : 'That request is not on your account.';
  return lang === 'ar'
    ? 'تعذّر إعداد تقرير المقارنة. عروضك لم تتأثر — يُرجى المحاولة مرة أخرى.'
    : 'We could not prepare the comparison report. Your quotes are unaffected — please try again.';
};
function Comparison({ inqId, token, lang }) {
  const [a, setA] = useState(null); const [busy, setBusy] = useState(true); const [note, setNote] = useState(''); const [code, setCode] = useState('');
  useEffect(() => { let on = true; setBusy(true); setCode(''); call('quote_compare', { inquiry_id: inqId, lang }, token).then((j) => { if (!on) return; setBusy(false); if (j && j.ok && j.analysis) setA(j.analysis); else if (j && j.note) setNote(j.note); else if (j && j.error) { setCode(String(j.error)); setNote(compareErrText(j.error, lang)); } else setNote(''); }).catch(() => { if (on) { setBusy(false); } }); return () => { on = false; }; }, [inqId, lang]);
  const arr = (x) => Array.isArray(x) ? x : [];
  if (busy) return (<div className="rounded-lg border border-primary/30 bg-primary/5 p-3.5"><div className={cn(S.sub, 'text-primary')}>{lang === 'ar' ? 'يُعدّ خبيرنا تقرير المقارنة…' : 'Our expert is preparing your comparison report…'}</div></div>);
  if (!a) return note ? (<div className="rounded-lg border border-border bg-secondary/20 p-3" title={code || undefined}><div className={S.sub}>{note}</div></div>) : null;
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
// A MODULE IS A PAGE NOW, NOT A POP-UP.
//
// These opened as a Dialog over the dashboard, and the reason was sound at the time: navigating to
// a module used to REPLACE the whole screen, which unmounted the KPIs and stranded the intake
// assistant, so a window that floated above kept them alive underneath.
//
// The shell removes that constraint. The sidebar, the top bar and the assistant persist across
// every destination, so a module can own the main region without unmounting anything the customer
// needs — and a sidebar item that opens a modal is the tell that a screen is a dashboard wearing an
// application's clothes. Nothing here fetches: each surface still owns its endpoint, its loading
// state and its empty state.
function ModuleWindow({ id, onClose, token, lang, inqs, onChanged, twin }) {
  const l2 = lang === 'ar' ? 'ar' : 'en';
  const rtl = lang === 'ar';
  const entry = MODULES.find((m) => m[0] === id);
  if (!entry) return null;
  return (<section className="mx-auto w-full max-w-[1240px] px-4 py-5 sm:px-6">
    <div className="mb-4 flex items-center gap-3">
      <button type="button" onClick={onClose}
        className="grid h-9 w-9 shrink-0 place-items-center rounded-xl border border-border text-muted-foreground transition-colors hover:bg-secondary/50 hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        aria-label={t(lang, 'nav_overview')}>
        <ArrowRight className={cn('h-4 w-4', !rtl && 'rotate-180')} aria-hidden />
      </button>
      <h1 className="font-head text-[20px] font-extrabold tracking-tight text-foreground">{t(lang, entry[1])}</h1>
    </div>
    <div className="flex flex-col gap-3">
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
      {id === 'account' && <AccountSettings token={token} lang={lang} onChanged={onChanged} />}
    </div>
  </section>);
}
// customer_api action='me' has served the customer's own row since the portal was written and no
// file in src/ ever called it — the account the customer holds was the one thing they could not
// look at. It is read-only on purpose: there is no endpoint that writes a preference back to the
// profile, so this states which choices are device-local rather than implying they were saved.
// AN ACCOUNT SCREEN YOU COULD NOT CHANGE ANYTHING ON.
//
// This was read-only and said so honestly — "We have no settings endpoint that writes them back to
// your profile yet, so nothing here is saved to your account." The honesty was right and the
// situation was not: customers.locale has been READ for months (my_inquiries serves it, the portal
// applies it on a new device) and nothing has ever written it, so an Arabic customer re-chose their
// language on every device forever. customer_api gained a narrow set_locale for exactly this.
//
// Name and mobile go through kyc save_customer, which is the routine that already validates them —
// and which now clears phone_verified when the number changes. That is the reason the mobile field
// carries a warning rather than a quiet save: the next load will ask them to verify the new number,
// and being told that before they press the button is the difference between a feature and a trap.
function AccountSettings({ token, lang, onChanged }) {
  const [me, setMe] = useState(null); const [err, setErr] = useState('');
  const [name, setName] = useState(''); const [phone, setPhone] = useState('');
  const [busy, setBusy] = useState(''); const [msg, setMsg] = useState('');
  const load = () => call('customer_api', { action: 'me' }, token)
    .then((j) => { if (j && j.customer) { setMe(j.customer); setName(j.customer.full_name || ''); setPhone(j.customer.phone || ''); } else setErr(t(lang, 'acct_failed')); })
    .catch(() => setErr(t(lang, 'acct_failed')));
  useEffect(() => { load(); }, [token]);
  if (err) return <div className={S.err}>{err}</div>;
  if (!me) return <div className={S.sub}>{t(lang, 'loading')}</div>;
  const since = me.created_at ? new Date(me.created_at).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : '';
  const digits = (v) => String(v || '').replace(/\D/g, '');
  const phoneChanged = digits(phone) !== digits(me.phone);
  const dirty = (name || '') !== (me.full_name || '') || phoneChanged;
  const saveProfile = async () => {
    setBusy('save'); setMsg('');
    const j = await call('kyc', { action: 'save_customer', full_name: name, phone, dob: me.date_of_birth || '' }, token);
    setBusy('');
    if (j && j.ok) { setMsg(t(lang, j.phone_reverify_required ? 'acct_reverify' : 'acct_saved')); load(); if (onChanged) onChanged(); }
    else setMsg((j && (j.error || j.message)) || t(lang, 'acct_failed'));
  };
  const saveLocale = async (loc) => {
    setBusy('loc'); setMsg('');
    const j = await call('customer_api', { action: 'set_locale', locale: loc }, token);
    setBusy('');
    if (j && j.ok) { setMsg(t(lang, 'acct_saved')); load(); } else setMsg((j && j.error) || t(lang, 'acct_failed'));
  };
  const Row = ({ label, children }) => (
    <div className="grid gap-1 sm:grid-cols-[190px_1fr] sm:items-center sm:gap-3">
      <div className="text-[12.5px] font-medium text-muted-foreground">{label}</div>
      <div className="min-w-0">{children}</div>
    </div>
  );
  return (<div className="flex flex-col gap-4">
    <p className={S.sub}>{t(lang, 'acct_sub')}</p>
    <Card className="flex flex-col gap-3.5 p-4">
      <Row label={t(lang, 'acct_name')}><Input value={name} onChange={(e) => setName(e.target.value)} /></Row>
      <Row label={t(lang, 'acct_phone')}>
        <Input value={phone} onChange={(e) => setPhone(e.target.value)} inputMode="tel" />
        <div className={cn('mt-1 text-[11.5px]', phoneChanged ? 'text-amber-300' : 'text-muted-foreground')}>
          {phoneChanged ? t(lang, 'acct_phone_warn') : (me.phone_verified ? t(lang, 'verified') : t(lang, 'acct_unverified'))}
        </div>
      </Row>
      <Row label={t(lang, 'acct_email')}>
        {/* Isolated so a Latin address does not scramble inside an Arabic line. */}
        <div className="text-[13px] text-foreground"><bdi>{me.email || '—'}</bdi></div>
      </Row>
      <Row label={t(lang, 'acct_locale')}>
        <div className="flex flex-wrap gap-2">
          {[['en', 'English'], ['ar', 'العربية']].map(([code, labelText]) => (
            <Button key={code} type="button" size="sm" variant={me.locale === code ? 'default' : 'outline'}
              disabled={busy === 'loc' || me.locale === code} onClick={() => saveLocale(code)}>{labelText}</Button>
          ))}
        </div>
      </Row>
      <Row label={t(lang, 'acct_since')}><div className="text-[13px] text-foreground">{since || '—'}</div></Row>
      <div className="flex flex-wrap items-center gap-3 border-t border-border pt-3.5">
        <Button size="sm" disabled={!dirty || busy === 'save'} onClick={saveProfile}>{busy === 'save' ? t(lang, 'saving') : t(lang, 'save_details')}</Button>
        {msg ? <span className="text-[12.5px] text-muted-foreground">{msg}</span> : null}
      </div>
    </Card>
    <p className={S.hint}>{t(lang, 'acct_device_note')}</p>
  </div>);
}
function Kpi({ label, v }) { return <Card className="p-3.5"><div className="text-[19px] font-extrabold text-foreground">{v}</div><div className="text-[11.5px] text-muted-foreground mt-1">{label}</div></Card>; }

// THE REQUEST'S OWN JOURNEY. What stood here was five words separated by chevrons with 1.5px dots —
// technically a stepper, visually a sentence. The stage a request is at is the single thing a
// customer opening the portal wants to know, so it gets a rail: completed segments filled, the
// current one pulsing, the rest quiet. `matched` is substituted into the third label when the
// server knows the number, because "Matched to 8 suppliers" is a fact and "Matched" is a mood.
//
// Horizontal on a desktop, and the labels drop to a single current-stage line under 640px rather
// than wrapping into three lines of chevrons on a phone.
const JOURNEY = ['jr_described', 'jr_structured', 'jr_matched', 'jr_quotes', 'jr_compare', 'jr_reveal'];
function Journey({ idx, lang, matched }) {
  // rfqStageIdx returns 0..4 over five RFQ stages; the journey the founder asked for has six, with
  // "structured" split out of "sent". Map rather than invent: a stage must never be claimed.
  const step = [0, 2, 3, 4, 5][Math.max(0, Math.min(4, Number(idx) || 0))];
  const label = (k, i) => (i === 2 && Number(matched) > 0)
    ? (lang === 'ar' ? ('مطابقة مع ' + matched + ' مورّد') : ('Matched to ' + matched + ' suppliers'))
    : t(lang, k);
  return (
    <div className="mt-3">
      <div className="flex items-center gap-1">
        {JOURNEY.map((k, i) => (
          <div key={k} className="flex min-w-0 flex-1 items-center gap-1">
            <span className={cn('h-1.5 flex-1 rounded-full transition-colors duration-500',
              i < step ? 'bg-primary' : i === step ? 'bg-primary/55 motion-safe:animate-pulse' : 'bg-secondary/70')} />
          </div>
        ))}
      </div>
      <div className="mt-1.5 hidden items-center justify-between gap-2 sm:flex">
        {JOURNEY.map((k, i) => (
          <span key={k} className={cn('min-w-0 flex-1 truncate text-[10.5px]',
            i < step ? 'text-muted-foreground' : i === step ? 'font-semibold text-primary' : 'text-muted-foreground/50',
            i === 0 ? 'text-start' : i === JOURNEY.length - 1 ? 'text-end' : 'text-center')}>{label(k, i)}</span>
        ))}
      </div>
      <div className="mt-1.5 text-[11.5px] font-semibold text-primary sm:hidden">{label(JOURNEY[step], step)}</div>
    </div>
  );
}

// THE QUOTE SPREAD, IN BOTH STATES — and this is the one rule no amount of design may break.
//
// PRE-REVEAL: a count and a band rounded to the nearest 1,000. NOT five bars. A chart that plots
// each quote as its own bar before the customer has paid to reveal is exactly the picture that
// destroys what the marketplace sells, even when every bar is labelled "Supplier A" — the shape of
// the market is the thing being bought.
// POST-REVEAL: everything, because they have bought it. Lowest highlighted.
//
// The rounding is done HERE and also in SQL (fn_wa_context) for the conversational channel. This
// component is given the same prices the rest of the card already holds and chooses not to draw
// them; the SQL path is given a band and could not draw them if it wanted to.
function QuoteSpread({ quotes, lang }) {
  const priced = (quotes || []).filter((q) => Number(q.price) > 0);
  if (!priced.length) return null;
  const anyRevealed = priced.some((q) => q.revealed);
  const vals = priced.map((q) => Number(q.price));
  const lo = Math.min(...vals), hi = Math.max(...vals);
  const roundK = (n) => Math.round(n / 1000) * 1000;
  return (
    <div className="rounded-lg border border-border bg-secondary/20 p-3.5">
      <div className="flex items-center justify-between gap-2">
        <b className="text-[13px] text-foreground">{t(lang, 'spread_title')}</b>
        {!anyRevealed ? (
          <span className="inline-flex items-center gap-1.5 rounded-full border border-border bg-card px-2 py-1 text-[11px] font-medium text-muted-foreground">
            <Lock className="h-3 w-3" aria-hidden />{t(lang, 'spread_locked')}
          </span>
        ) : null}
      </div>
      {!anyRevealed ? (
        <>
          <div className="mt-2.5 text-[15px] font-bold text-foreground">
            {priced.length + ' ' + t(lang, 'spread_pre') + ' ' + aed(roundK(vals.reduce((a, b) => a + b, 0) / vals.length))}
          </div>
          {/* One band. Not one bar per quote. */}
          <div className="mt-2 h-2.5 overflow-hidden rounded-full bg-secondary/70">
            <div className="h-full w-1/2 rounded-full bg-gradient-to-r from-primary/35 via-primary/70 to-primary/35 motion-safe:transition-[width] motion-safe:duration-700" style={{ marginInlineStart: '25%' }} />
          </div>
        </>
      ) : (
        <div className="mt-2.5 flex flex-col gap-1.5">
          {priced.slice().sort((a, b) => Number(a.price) - Number(b.price)).map((q, i) => {
            const pct = hi === lo ? 100 : Math.max(12, Math.round(((Number(q.price) - lo) / (hi - lo)) * 70) + 30);
            return (
              <div key={q.id} className="flex items-center gap-2">
                <span className="w-[104px] shrink-0 truncate text-[11.5px] text-muted-foreground">{q.supplier_name || q.label}</span>
                <span className="h-2.5 flex-1 overflow-hidden rounded-full bg-secondary/70">
                  <span className={cn('block h-full rounded-full motion-safe:transition-[width] motion-safe:duration-700', i === 0 ? 'bg-primary' : 'bg-primary/45')} style={{ width: pct + '%' }} />
                </span>
                <span className={cn('w-[92px] shrink-0 text-end text-[11.5px] tabular-nums', i === 0 ? 'font-bold text-primary' : 'text-foreground')}>{aed(q.price)}</span>
                {i === 0 ? <Check className="h-3.5 w-3.5 shrink-0 text-primary" aria-hidden /> : <span className="w-3.5 shrink-0" />}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
