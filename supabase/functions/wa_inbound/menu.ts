// The WhatsApp welcome and menu: every word and every rule that decides which option was chosen
// (customer_support, 22 Sep 2026). Pure — no network, no database — so the tests and the Content
// script (scripts/whatsapp/create_menu_content.mjs) read the same text the function sends.
//
// Founder, 22 Sep 2026 (founder_instruction 759): "I texted our WhatsApp number from my WhatsApp,
// said hi, got no response. Even without the LLM there should be automatic replies: a professional
// welcome message and options (general inquiry/information, existing inquiry, new inquiry, report a
// problem) for customers and suppliers, not simple text."
//
// Limits this copy is written to (Twilio twilio/list-picker, WhatsApp interactive list): item title
// <= 24 characters, description <= 72, button <= 20, at most 10 items. menu.test.ts asserts them.

import { CANONICAL_ORIGIN, portalLink } from '../_shared/site_origins.ts';

export type Lang = 'en' | 'ar';
export type Audience = 'customer' | 'supplier' | 'unknown' | 'founder';
export const MENU_IDS = ['qd_new', 'qd_follow', 'qd_supplier', 'qd_general', 'qd_problem', 'qd_person'] as const;
export type MenuId = typeof MENU_IDS[number];
export type MenuItem = { id: MenuId; item: string; description: string };

const AR = /[؀-ۿ]/;
export function langOf(text: string, fallback: Lang = 'en'): Lang {
  const t = String(text || '');
  if (AR.test(t)) return 'ar';
  return /[a-z]/i.test(t) ? 'en' : fallback;
}

// Arabic-Indic and Eastern Arabic-Indic digits read as the Western digit a customer meant.
function westernDigits(s: string): string {
  return s.replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x0660))
          .replace(/[۰-۹]/g, (c) => String(c.charCodeAt(0) - 0x06F0));
}
// Strip tatweel, diacritics and the alef/ya/ta-marbuta variants so a typed greeting matches however it is written.
export function norm(s: string): string {
  return String(s || '').toLowerCase()
    .replace(/[ً-ْـ]/g, '')
    .replace(/[آأإ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه')
    .replace(/[!?.,،؟\s]+/g, ' ').trim();
}

// GREETINGS / MENU_WORDS and isGreeting / isMenuWord / isSalam are DELETED (23 Sep 2026, founder_instruction
// 886-903): whether a message is only a hello, a request for the menu, or a salam is REASONED
// (_shared/reasoned_menus.ts menuMeaning; decision points wa_inbound.greeting_state and wa_inbound.problem_state).

export function menuItems(lang: Lang, audience: Audience): MenuItem[] {
  const sup = audience === 'supplier';
  return lang === 'ar'
    ? [
      { id: 'qd_new', item: 'طلب عرض سعر جديد', description: 'صفوا العمل المطلوب واستلموا عروض الأسعار دون كشف هويتكم' },
      { id: 'qd_follow', item: 'متابعة طلب قائم', description: 'حالة طلباتكم المفتوحة' },
      sup
        ? { id: 'qd_supplier', item: 'حساب المورد', description: 'حالة التحقق من حسابكم ورابط بوابة الموردين' }
        : { id: 'qd_supplier', item: 'انضمام الموردين', description: 'سجلوا شركتكم لاستلام طلبات عروض الأسعار' },
      { id: 'qd_general', item: 'استفسار عام', description: 'طريقة عمل المنصة والرسوم ونطاق التغطية' },
      { id: 'qd_problem', item: 'الإبلاغ عن مشكلة', description: 'أخبرونا بما حدث وسنفتح بلاغًا برقم مرجعي' },
      { id: 'qd_person', item: 'التحدث إلى أحد الموظفين', description: 'يتواصل معكم أحد أعضاء فريقنا' },
    ]
    : [
      { id: 'qd_new', item: 'Request a quotation', description: 'Describe a job and receive anonymous quotes' },
      { id: 'qd_follow', item: 'Follow up my request', description: 'The status of your open requests' },
      sup
        ? { id: 'qd_supplier', item: 'My supplier account', description: 'Your verification status and the supplier portal' }
        : { id: 'qd_supplier', item: 'Suppliers: join us', description: 'Register your company to receive quotation requests' },
      { id: 'qd_general', item: 'General question', description: 'How QuotesDone works, fees and coverage' },
      { id: 'qd_problem', item: 'Report a problem', description: 'Tell us what went wrong; we open a case' },
      { id: 'qd_person', item: 'Talk to a person', description: 'A member of our team will contact you' },
    ];
}
export const MENU_BUTTON: Record<Lang, string> = { en: 'View options', ar: 'عرض الخيارات' };

/** Which option the message chose STRUCTURALLY, or null: the list reply's id, the button payload, or — only right
 *  after we offered the numbered menu — a bare digit (format parsing). A TYPED title or any other free text is not
 *  matched here (23 Sep 2026, decision point wa_inbound.menu_choice): its meaning is reasoned (menuMeaning). */
export function menuChoice(p: { body?: string; listId?: string; buttonPayload?: string; numbers?: boolean }): MenuId | null {
  for (const id of [p.listId, p.buttonPayload]) {
    if (id && (MENU_IDS as readonly string[]).includes(id)) return id as MenuId;
  }
  const body = westernDigits(String(p.body || '')).trim();
  if (p.numbers) {
    const m = body.match(/^\(?([1-6])[).]?$/);
    if (m) return MENU_IDS[Number(m[1]) - 1];
  }
  return null;
}

/** A message that is NOTHING BUT a greeting, taken without a model (customer_support, 2 Nov 2026: a bare "Hi" waited ~15 s on the
 *  classification only to be told 'greeting'). Whole-message tokens only, like FIGURES: "hi, how much is tiling?" is not here and
 *  is reasoned as before. 'salam' is the Islamic greeting, which the welcome answers in kind. */
const GREETINGS = new Set(['hi', 'hello', 'hey', 'hi there', 'hello there', 'good morning', 'good afternoon', 'good evening', 'مرحبا', 'مرحبًا', 'اهلا', 'أهلا', 'هلا']);
const SALAMS = new Set(['salam', 'salaam', 'assalamu alaikum', 'assalamualaikum', 'as salamu alaykum', 'السلام عليكم', 'سلام']);
export function bareGreeting(body: string): 'greeting' | 'salam' | null {
  const t = String(body || '').toLowerCase().replace(/[\s!.,؟?،]+$/u, '').replace(/^[\s!.,]+/u, '').replace(/\s+/g, ' ').trim();
  return GREETINGS.has(t) ? 'greeting' : SALAMS.has(t) ? 'salam' : null;
}

/** The key under which the Content SID of this menu is stored (app_secrets.wa_menu_content_sids). */
export function contentKey(lang: Lang, audience: Audience): string {
  return 'menu_' + lang + '_' + (audience === 'supplier' ? 'supplier' : 'general');
}

// OUR WORKING HOURS are company knowledge, not copy: src/content/company.json "hours", the line the
// footer, the contact page and the About page print. An edge function cannot import from src/, so the
// same words are held here and menu.test.ts fails the moment the two differ (founder, instruction 763:
// "response times / working hours from company knowledge — don't invent").
export const HOURS: Record<Lang, string> = {
  en: 'Monday to Friday, 9am to 6pm (GST), excluding UAE public holidays',
  ar: 'من الاثنين إلى الجمعة، من 9 صباحًا إلى 6 مساءً (بتوقيت الخليج)، باستثناء العطلات الرسمية في الإمارات',
};

/** True inside those hours (Dubai, Monday to Friday, 09:00 to 18:00). Public holidays are not known here. */
export function withinHours(now: Date = new Date()): boolean {
  const d = new Date(now.getTime() + 4 * 3600e3);          // Asia/Dubai is UTC+4 all year
  const day = d.getUTCDay(); const h = d.getUTCHours();
  // Monday(1) to Friday(5) — the founder's working week, the one workingDays.ts counts and the one
  // the whole site now prints (WEB-04, 22 Sep 2026). This read 0–4 (Sunday to Thursday) while it
  // was telling the sender the hours were Sunday to Thursday; both are corrected together, so the
  // "outside those hours" branch fires on the days the sentence names.
  return day >= 1 && day <= 5 && h >= 9 && h < 18;
}

/** A name to greet with, or null. NEVER an address: on 22 Sep the founder was greeted as
 *  "Good day management@quotesdone.com" because fn_identify_contact returns the founder's admin email
 *  as his name. fn_wa_menu_context no longer passes one; this is the second lock. */
export function cleanName(name: string | null | undefined): string | null {
  const who = String(name || '').replace(/\s+/g, ' ').trim().slice(0, 60);
  if (!who || who.includes('@') || /^\+?[\d\s()-]+$/.test(who) || !/\p{L}/u.test(who)) return null;
  return who;
}

/** The one line that changes per person; it is Content variable {{1}}, so it carries no line break. */
export function greetLine(lang: Lang, _audience: Audience, name: string | null, salam = false): string {
  const who = cleanName(name);
  if (lang === 'ar') {
    const open = salam ? 'وعليكم السلام ورحمة الله وبركاته' : 'حيّاكم الله';
    return open + (who ? ' ' + who : '') + '، ونشكر لكم تواصلكم مع QuotesDone.';
  }
  return who ? 'Good day ' + who + ', and thank you for contacting QuotesDone.'
             : 'Good day, and thank you for contacting QuotesDone.';
}

/** The fixed part of the welcome: who we are in one line, what to do, when a person is here, signed.
 *  The Content body is greetLine + this; a list-picker body may hold 1,024 characters (menu test). */
export const WELCOME_TAIL: Record<Lang, string> = {
  // 22 Sep 2026 (documents-language audit, DL-11): "construction procurement" named a sector the
  // product does not confine itself to — every trade is welcome except food and beverage (the
  // founder's exact-trade rule), and a supplier of office furniture or IT reading this line would
  // conclude the platform is not for them.
  en: 'QuotesDone is the UAE sourcing marketplace for every trade except food and beverage: request quotations and compare verified suppliers, with your identity protected until you choose to reveal one.\n\n' +
      'Please choose from the options below, or simply type your question and I will answer it straight away. Our team is available ' + HOURS.en + '.\n\n' +
      'Kind regards,\nQuotesDone Customer Support',
  ar: 'QuotesDone سوق إماراتي لعروض الأسعار في جميع الأنشطة باستثناء الأغذية والمشروبات: اطلبوا عروض الأسعار وقارنوا بين موردين موثّقين، مع حجب هويتكم حتى تختاروا الكشف عن أحدهم.\n\n' +
      'تفضلوا باختيار ما يناسبكم من الخيارات أدناه، أو اكتبوا استفساركم وسنجيبكم عليه فورًا. فريقنا في خدمتكم ' + HOURS.ar + '.\n\n' +
      'مع خالص التحية،\nفريق خدمة العملاء في QuotesDone',
};

/** The same menu as numbered text: the fallback when the interactive list cannot be sent. */
export function menuAsText(lang: Lang, audience: Audience, lead: string): string {
  const lines = menuItems(lang, audience).map((i, n) => (n + 1) + '. ' + i.item);
  const ask = lang === 'ar' ? 'يُرجى الرد برقم الخيار المطلوب.' : 'Please reply with the number of your choice.';
  return (lead ? lead + '\n\n' : '') + lines.join('\n') + '\n\n' + ask;
}

export function welcomeText(lang: Lang, audience: Audience, name: string | null, salam = false): string {
  return greetLine(lang, audience, name, salam) + '\n\n' + WELCOME_TAIL[lang];
}

// THE LAST WORD WHEN NOTHING COULD ANSWER (22 Sep 2026). On wa_messages 271 the founder received
// "I could not reach the company brain ... (agent_brain returned no reply (HTTP 404))" — an internal
// name, a status code and an admission of a fault, sent to the person who asked. What a person hears
// instead: thanks, an honest "no confirmed answer yet", that the question is recorded for the team
// (fn_support_knowledge_gap files it), and the way to a real reply — the "Talk to a person" option is
// on the menu this line leads. One line: it is Content variable {{1}} of the interactive list. If the
// question could not be recorded, the line does not say it was.
// no_internal_text_reaches_a_customer.test.ts scans every reply string for internal wording.
export function sorryLead(lang: Lang, recorded: boolean): string {
  return lang === 'ar'
    ? 'شكرًا لسؤالكم. لا تتوفر لديّ إجابة مؤكدة عنه حتى الآن، وأفضّل ألا أجيب دون تحقق' + (recorded ? '، لذا سجّلته لدى فريقنا' : '') +
      '. وإن رغبتم في أن يرد عليكم أحد أعضاء الفريق هنا، فاختاروا «التحدث إلى أحد الموظفين» من الخيارات أدناه:'
    : 'Thank you for your question. I do not have a confirmed answer to it yet and would rather not guess' + (recorded ? ', so I have recorded it for our team' : '') +
      '. If you would like a member of the team to reply to you here, choose "Talk to a person" below; the other options are here too:';
}

const SITE = CANONICAL_ORIGIN;
export function siteUrl(lang: Lang, path: string): string { return SITE + (lang === 'ar' ? '/ar' : '') + path; }

// WHICH PORTAL (instruction 763). Measured 22 Sep 2026 on https://quotesdone.com: /portal renders
// SupplierPortal for everyone, signed in or not ("Supplier portal — QuotesDone",
// src/app/[locale]/portal/page.tsx), and /me renders the customer portal ("My requests"). The menu sent
// customers to /portal, so "Request a quotation" opened the supplier login. Customers and unknown
// numbers now go to /me (?new=1 opens the new-request form, CustomerPortal.tsx); only a supplier is sent
// to /portal, and a company that is not yet a supplier to /supplier, the page that explains joining.
export function newRequestUrl(lang: Lang): string { return portalLink(lang) + '?new=1'; }
export function requestUrl(lang: Lang, id: string): string { return portalLink(lang, id); }
export function supplierPortalUrl(lang: Lang): string { return siteUrl(lang, '/portal'); }

export type OwnRequest = { id?: string; rfq_no: number | null; status: string; created_at: string };
export type MenuContext = { audience: Audience; name: string | null; approved?: boolean; requests?: OwnRequest[] };

const STATUS: Record<string, [string, string]> = {
  draft: ['Draft, not yet sent', 'مسودة لم تُرسل بعد'],
  new: ['Received, being prepared', 'قيد الإعداد'],
  open: ['Sent to suppliers, awaiting quotes', 'أُرسل إلى الموردين بانتظار العروض'],
  sent: ['Sent to suppliers, awaiting quotes', 'أُرسل إلى الموردين بانتظار العروض'],
  quoted: ['Quotes received', 'وصلت عروض الأسعار'],
  revealed: ['Supplier details revealed', 'كُشفت بيانات المورد'],
  completed: ['Completed', 'مكتمل'],
  closed: ['Closed', 'مغلق'],
  cancelled: ['Cancelled', 'ملغى'],
};
function statusWords(s: string, lang: Lang): string {
  const hit = STATUS[String(s || '').toLowerCase()];
  if (hit) return lang === 'ar' ? hit[1] : hit[0];
  return lang === 'ar' ? 'قيد المعالجة' : String(s || 'in progress').replace(/_/g, ' ');
}

/** The reply to an option that needs no further input (everything except report-a-problem's second turn). */
export function optionReply(id: MenuId, lang: Lang, ctx: MenuContext, now: Date = new Date()): string {
  const ar = lang === 'ar';
  const newReq = newRequestUrl(lang);
  const supplierPortal = supplierPortalUrl(lang);
  const join = siteUrl(lang, '/supplier');
  switch (id) {
    case 'qd_new':
      return ar
        ? 'لطلب عرض سعر، تفضلوا بوصف العمل المطلوب عبر الرابط التالي، ويمكنكم إرفاق صور أو مخططات:\n' + newReq + '\nنشر الطلب ومقارنة العروض مجاني، وتبقى هويتكم محجوبة حتى تختاروا الكشف عن أحد الموردين.'
        : 'To request a quotation, describe the job here (text, photos or drawings all work):\n' + newReq + '\nPosting a request and comparing quotes is free, and your identity stays hidden until you choose to reveal a supplier.';
    case 'qd_follow': {
      if (ctx.audience === 'supplier') return optionReply('qd_supplier', lang, ctx, now);
      const reqs = (ctx.requests || []).slice(0, 5);
      // Said plainly (instruction 763): the founder was told "no open requests on your account" and sent
      // to the supplier portal. Requests are listed only for a CONFIRMED number (fn_wa_menu_context), so
      // "none" is true of this number and of the account email it is confirmed on.
      if (!reqs.length) {
        return ar
          ? 'لا يوجد طلب مسجّل على رقم الجوال هذا أو على البريد الإلكتروني المرتبط به. إن كنتم قد سجّلتم برقم آخر فتفضلوا بتسجيل الدخول ببريدكم الإلكتروني لمتابعة طلباتكم، ولإنشاء طلب جديد:\n' + newReq
          : 'There is no request registered under this mobile number (or its email). If you registered with another number, please sign in with your email to see your requests. To start a new request:\n' + newReq;
      }
      const lines = reqs.map((r) => {
        const day = String(r.created_at || '').slice(0, 10);
        const no = r.rfq_no ? (ar ? 'الطلب رقم ' + r.rfq_no : 'Request ' + r.rfq_no) : (ar ? 'طلب' : 'Request');
        const link = r.id ? '\n' + requestUrl(lang, r.id) : '';
        return '• ' + no + ': ' + statusWords(r.status, lang) + (day ? (ar ? ' (' + day + ')' : ' (opened ' + day + ')') : '') + link;
      });
      return ar ? 'طلباتكم الحالية:\n' + lines.join('\n') : 'Your current requests:\n' + lines.join('\n');
    }
    case 'qd_supplier': {
      if (ctx.audience === 'supplier') {
        const co = ctx.name ? ' (' + ctx.name + ')' : '';
        return ctx.approved
          ? (ar
            ? 'حساب المورد' + co + ' موثّق ومفعّل. تفضلوا بإدارة طلبات عروض الأسعار وعروضكم عبر بوابة الموردين:\n' + supplierPortal
            : 'Your supplier account' + co + ' is verified. You can manage quotation requests and your quotes in the supplier portal:\n' + supplierPortal)
          : (ar
            ? 'تسجيل حسابكم' + co + ' لم يكتمل التحقق منه بعد. تفضلوا باستكمال الخطوات المتبقية في بوابة الموردين، ويستغرق التحقق حتى 3 أيام عمل بعد اكتمال المستندات:\n' + supplierPortal
            : 'Your registration' + co + ' is not verified yet. Please complete the remaining steps in the supplier portal; verification takes up to 3 working days once the documents are complete:\n' + supplierPortal);
      }
      return ar
        ? 'يسجل الموردون مجانًا برخصة تجارية سارية في دولة الإمارات، دون أي عمولة على الأعمال التي يفوزون بها. للتسجيل:\n' + join + '\nيستغرق التحقق حتى 3 أيام عمل.'
        : 'Suppliers register free with a valid UAE trade licence and pay no commission on the work they win. Register here:\n' + join + '\nVerification takes up to 3 working days.';
    }
    case 'qd_general':
      return ar
        ? 'تفضلوا بكتابة سؤالكم، وسأجيبكم من المعلومات المعتمدة لدينا. كما يمكنكم الاطلاع على الأسئلة الشائعة عبر الرابط التالي:\n' + siteUrl(lang, '/faq')
        : 'Please type your question and I will answer it from our published guidance. You can also read the FAQ at ' + siteUrl(lang, '/faq') + '.';
    case 'qd_problem':
      return ar
        ? 'نأسف لذلك. تفضلوا بوصف المشكلة في رسالة واحدة، مع ذكر رقم الطلب إن وُجد، وسنفتح لكم بلاغًا برقم مرجعي.'
        : 'Sorry to hear that. Please describe the problem in one message (with the request number if there is one) and I will open a case with a reference number.';
    case 'qd_person': {
      // Honest timing (instruction 763): the hours are company knowledge (HOURS); outside them the
      // contact is told the reply comes when the team is back, not "shortly".
      const who = cleanName(ctx.name);
      const open = withinHours(now);
      return ar
        ? 'شكرًا لكم' + (who ? ' ' + who : '') + '. أبلغنا فريق خدمة العملاء بطلبكم، وسيتواصل معكم أحد أعضاء الفريق على هذا الرقم. ساعات عملنا ' + HOURS.ar +
          (open ? '.' : '، وسيصلكم الرد مع بداية يوم العمل التالي.') +
          '\nتوقفت الردود الآلية في هذه المحادثة حتى يرد عليكم أحد الموظفين، وكل ما تكتبونه هنا يصل إلى الفريق.'
        : 'Thank you' + (who ? ', ' + who : '') + '. I have passed your request to our customer support team, and a member of the team will reply to you on this number. Our working hours are ' + HOURS.en +
          (open ? '.' : '; it is outside those hours now, so expect the reply when the team is back.') +
          '\nAutomatic replies in this chat are paused until a person answers you, and everything you write here reaches the team.';
    }
  }
}

/** What fn_wa_problem_report answered: the reference, whether the report joined a case already open,
 *  and the first-reply promise in hours (decision_policy support_first_reply_sla_hours). */
export type CaseResult = { ref: string | null; appended?: boolean; slaHours?: number | null };

export function caseConfirm(lang: Lang, c: CaseResult): string {
  const ar = lang === 'ar';
  if (!c.ref) {
    return ar
      ? 'شكرًا لكم، وصلتنا رسالتكم. تعذّر إصدار الرقم المرجعي الآن، وسيراجع فريق الدعم رسالتكم ويرد عليكم على هذا الرقم.'
      : 'Thank you, your message has reached us. A reference number could not be issued just now; our support team will review it and reply on this number.';
  }
  const h = c.slaHours && c.slaHours > 0 ? Math.round(c.slaHours) : null;
  const when = !h ? ''
    : ar ? ' وسيصلكم ردنا خلال ' + h + ' ساعة (ساعات العمل ' + HOURS.ar + ').'
    : ' You will have our answer within ' + h + ' hours (our working hours are ' + HOURS.en + ').';
  if (c.appended) {
    return ar
      ? 'شكرًا لكم. لديكم بلاغ مفتوح برقم ' + c.ref + '، فأضفنا رسالتكم إليه بدل فتح بلاغ جديد.' + when
      : 'Thank you. You already have an open case, ' + c.ref + ', so I have added this message to it rather than opening a new one.' + when;
  }
  return ar
    ? 'شكرًا لكم. الرقم المرجعي لبلاغكم هو ' + c.ref + '، وسيتولى فريق الدعم متابعته.' + when
    : 'Thank you. Your case reference is ' + c.ref + ', and our support team is on it.' + when;
}

/** The reporter hears that their case is closed (nothing is one-way). Sent in-session by the founder's
 *  close command; fn_support_case_closed_tells_the_reporter emails the account address as well. */
export function caseClosedNotice(lang: Lang, ref: string, reason: string): string {
  const why = String(reason || '').replace(/\s+/g, ' ').trim().slice(0, 300);
  return lang === 'ar'
    ? 'نفيدكم بإغلاق البلاغ رقم ' + ref + (why ? '، وملخص المعالجة: ' + why : '') + '.\nإن لم تُحلّ المشكلة فتفضلوا بالرد على هذه الرسالة وسنعيد فتحه.\n\nفريق خدمة العملاء في QuotesDone'
    : 'Your case ' + ref + ' is now closed' + (why ? ': ' + why : '') + '.\nIf the problem is not solved, just reply to this message and we will reopen it.\n\nQuotesDone Customer Support';
}

/** The founder's alert when someone asks for a person: who, which side, what they last wrote, a one-tap
 *  reply link, and how to close it. There is no OS page to link: https://quotesdone.com/os answers 404
 *  (measured 22 Sep 2026), so the conversation itself is carried in the alert. */
export function humanAlert(p: { phone: string; name: string | null; profile: string | null; audience: Audience;
                               lastMessages: string[] }): { event: string; detail: string } {
  const digits = String(p.phone || '').replace(/[^0-9]/g, '');
  const who = cleanName(p.name) || cleanName(p.profile) || ('+' + digits);
  const side = p.audience === 'supplier' ? 'supplier' : p.audience === 'customer' ? 'customer' : p.audience === 'founder' ? 'founder (test)' : 'not yet a registered customer or supplier';
  const said = p.lastMessages.map((m) => String(m || '').replace(/\s+/g, ' ').trim()).filter(Boolean).slice(0, 3)
    .map((m) => '- "' + m.slice(0, 200) + '"');
  return {
    event: 'WhatsApp: ' + who + ' asks to talk to a person',
    detail: [
      'Who: ' + who + (cleanName(p.profile) && cleanName(p.profile) !== who ? ' (WhatsApp name "' + cleanName(p.profile) + '")' : '') + ', +' + digits,
      'Side: ' + side,
      said.length ? 'Last messages:\n' + said.join('\n') : 'Last messages: none besides choosing "Talk to a person".',
      'Reply now: https://wa.me/' + digits,
      'They were told a member of the team will reply on this number, working hours ' + HOURS.en + ', and automatic replies to them are paused until you close this or 23 hours pass.',
      'When you have answered them, send DONE +' + digits + ' to the QuotesDone WhatsApp number to close it.',
    ].join('\n'),
  };
}

/** A command only the founder's number may give: close a support case, or close a human request.
 *  Decision point wa_inbound.founder_command: this is FORMAT PARSING of an exact-token grammar, not a reading of
 *  meaning — the whole message must be CLOSE/اغلاق + a case reference (QD-S-XXXXXX), or DONE/تم + a phone number,
 *  anchored at both ends; the reason after a case reference is stored verbatim, never interpreted. Anything else is
 *  null and goes to the founder's reasoned command channel. menu_flow calls it only for his number. */
export type FounderCommand = { kind: 'close_case'; ref: string; reason: string } | { kind: 'close_human'; phone: string };
export function founderCommand(body: string): FounderCommand | null {
  const t = westernDigits(String(body || '')).trim();
  const c = t.match(/^(?:close|اغلاق|إغلاق)\s+(QD-S-[23456789A-HJ-NP-Z]{6})\b[\s:,-]*([\s\S]*)$/i);
  if (c) return { kind: 'close_case', ref: c[1].toUpperCase(), reason: c[2].trim() };
  const h = t.match(/^(?:done|تم)\s+(\+?[\d\s-]{9,20})$/i);
  if (h) return { kind: 'close_human', phone: h[1].replace(/[^0-9]/g, '') };
  return null;
}

export const MENU_HINT: Record<Lang, string> = {
  en: '\n\nReply MENU at any time to see the options.',
  ar: '\n\nللاطلاع على الخيارات في أي وقت، يُرجى إرسال كلمة «قائمة».',
};
