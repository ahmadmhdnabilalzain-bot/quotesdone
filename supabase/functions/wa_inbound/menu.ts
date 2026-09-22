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
function norm(s: string): string {
  return String(s || '').toLowerCase()
    .replace(/[ً-ْـ]/g, '')
    .replace(/[آأإ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه')
    .replace(/[!?.,،؟\s]+/g, ' ').trim();
}

const GREETINGS = [
  'hi', 'hii', 'hey', 'hello', 'hallo', 'salam', 'salaam', 'marhaba', 'good morning', 'good afternoon', 'good evening',
  'السلام عليكم', 'سلام عليكم', 'السلام عليكم ورحمه الله', 'السلام عليكم ورحمه الله وبركاته', 'سلام', 'مرحبا', 'مرحبا بكم',
  'اهلا', 'اهلا وسهلا', 'هلا', 'صباح الخير', 'مساء الخير',
].map(norm);
const MENU_WORDS = ['menu', 'options', 'start', 'main menu', 'قائمه', 'القائمه', 'الخيارات', 'خيارات'].map(norm);

/** A greeting on its own, or with "there"/"team"/"QuotesDone" after it. */
export function isGreeting(text: string): boolean {
  const n = norm(text).replace(/\b(there|team|quotesdone)\b/g, '').trim();
  return n.length > 0 && GREETINGS.includes(n);
}
export function isMenuWord(text: string): boolean { return MENU_WORDS.includes(norm(text)); }
export function isSalam(text: string): boolean { return /^(ال)?سلام/.test(norm(text)); }

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

/** Which option the message chose, or null. `numbers` is true only right after we offered the menu. */
export function menuChoice(p: { body?: string; listId?: string; buttonPayload?: string; numbers?: boolean }): MenuId | null {
  for (const id of [p.listId, p.buttonPayload]) {
    if (id && (MENU_IDS as readonly string[]).includes(id)) return id as MenuId;
  }
  const body = westernDigits(String(p.body || '')).trim();
  if (p.numbers) {
    const m = body.match(/^\(?([1-6])[).]?$/);
    if (m) return MENU_IDS[Number(m[1]) - 1];
  }
  // A list reply also carries the item's title as Body; so does a customer who types it.
  const n = norm(body);
  if (!n) return null;
  for (const lang of ['en', 'ar'] as Lang[]) {
    for (const aud of ['unknown', 'supplier'] as Audience[]) {
      const hit = menuItems(lang, aud).find((i) => norm(i.item) === n);
      if (hit) return hit.id;
    }
  }
  return null;
}

/** The key under which the Content SID of this menu is stored (app_secrets.wa_menu_content_sids). */
export function contentKey(lang: Lang, audience: Audience): string {
  return 'menu_' + lang + '_' + (audience === 'supplier' ? 'supplier' : 'general');
}

/** The one line that changes per person; it is Content variable {{1}}, so it carries no line break. */
export function greetLine(lang: Lang, audience: Audience, name: string | null, salam = false): string {
  const who = String(name || '').replace(/\s+/g, ' ').trim().slice(0, 60);
  if (lang === 'ar') {
    const open = salam ? 'وعليكم السلام ورحمة الله وبركاته' : 'أهلًا وسهلًا';
    if (who) return open + ' ' + who + '، يسعدنا تواصلكم مع QuotesDone.';
    return open + '، مرحبًا بكم في QuotesDone، منصة عروض الأسعار في دولة الإمارات.';
  }
  if (who) return 'Good day ' + who + ', and welcome back to QuotesDone.';
  return audience === 'founder'
    ? 'Good day, and welcome to QuotesDone.'
    : "Good day, and welcome to QuotesDone, the UAE's anonymous quotation marketplace.";
}

/** The fixed part of the welcome, signed as QuotesDone. The Content body is greetLine + this. */
export const WELCOME_TAIL: Record<Lang, string> = {
  en: 'Please choose one of the options below, or simply type your question.\n\nQuotesDone team',
  ar: 'يُرجى اختيار ما يناسبكم من القائمة أدناه، أو كتابة استفساركم مباشرة.\n\nفريق QuotesDone',
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

export const SORRY_LEAD: Record<Lang, string> = {
  en: 'Sorry, I could not match that to an answer. These are the ways I can help:',
  ar: 'عذرًا، لم أجد إجابة مناسبة لرسالتكم. يمكنني مساعدتكم في ما يلي:',
};

const SITE = 'https://quotesdone.com';
export function siteUrl(lang: Lang, path: string): string { return SITE + (lang === 'ar' ? '/ar' : '') + path; }

export type OwnRequest = { rfq_no: number | null; status: string; created_at: string };
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
export function optionReply(id: MenuId, lang: Lang, ctx: MenuContext): string {
  const ar = lang === 'ar';
  const portal = siteUrl(lang, '/portal');
  const supplierUrl = siteUrl(lang, '/supplier');
  switch (id) {
    case 'qd_new':
      return ar
        ? 'لطلب عرض سعر، يُرجى وصف العمل المطلوب عبر الرابط التالي:\n' + portal + '\nيمكنكم إرفاق صور أو مخططات. نشر الطلب ومقارنة العروض مجاني، وتبقى هويتكم محجوبة حتى تختاروا كشف بيانات أحد الموردين.'
        : 'To request a quotation, describe the job at ' + portal + ' (text, photos or drawings all work). Posting a request and comparing quotes is free, and your identity stays hidden until you choose to reveal a supplier.';
    case 'qd_follow': {
      if (ctx.audience === 'supplier') return optionReply('qd_supplier', lang, ctx);
      if (ctx.audience !== 'customer' && ctx.audience !== 'founder') {
        return ar
          ? 'حرصًا على خصوصيتكم، لا نعرض تفاصيل الطلبات إلا لرقم واتساب مؤكد في حساب على المنصة. يُرجى تسجيل الدخول عبر الرابط التالي لمتابعة طلباتكم، أو تأكيد هذا الرقم في ملفكم الشخصي:\n' + portal
          : 'To protect your privacy, request details are shared only with a WhatsApp number confirmed on a QuotesDone account. Please sign in at ' + portal + ' to see your requests, or confirm this number in your profile.';
      }
      const reqs = (ctx.requests || []).slice(0, 5);
      if (!reqs.length) {
        return ar
          ? 'لا توجد طلبات مفتوحة في حسابكم حاليًا. يمكنكم إنشاء طلب جديد عبر الرابط التالي:\n' + portal
          : 'There are no open requests on your account at the moment. You can start a new one at ' + portal + '.';
      }
      const lines = reqs.map((r) => {
        const day = String(r.created_at || '').slice(0, 10);
        const no = r.rfq_no ? (ar ? 'الطلب رقم ' + r.rfq_no : 'Request ' + r.rfq_no) : (ar ? 'طلب' : 'Request');
        return '• ' + no + ': ' + statusWords(r.status, lang) + (day ? (ar ? ' (' + day + ')' : ' (opened ' + day + ')') : '');
      });
      return ar
        ? 'طلباتكم الحالية:\n' + lines.join('\n') + '\n\nالتفاصيل الكاملة عبر الرابط التالي:\n' + portal
        : 'Your current requests:\n' + lines.join('\n') + '\n\nFull details: ' + portal;
    }
    case 'qd_supplier': {
      if (ctx.audience === 'supplier') {
        const co = ctx.name ? (ar ? ' (' + ctx.name + ')' : ' (' + ctx.name + ')') : '';
        return ctx.approved
          ? (ar
            ? 'حساب المورد' + co + ' موثّق ومفعّل. يمكنكم إدارة طلبات عروض الأسعار وعروضكم عبر الرابط التالي:\n' + supplierUrl
            : 'Your supplier account' + co + ' is verified. You can manage quotation requests and your quotes at ' + supplierUrl + '.')
          : (ar
            ? 'تسجيل حسابكم' + co + ' لم يكتمل التحقق منه بعد. يُرجى استكمال الخطوات المتبقية عبر الرابط التالي، ويستغرق التحقق حتى 3 أيام عمل بعد اكتمال المستندات:\n' + supplierUrl
            : 'Your registration' + co + ' is not verified yet. Please complete the remaining steps at ' + supplierUrl + '; verification takes up to 3 working days once the documents are complete.');
      }
      return ar
        ? 'يسجل الموردون مجانًا برخصة تجارية سارية في دولة الإمارات، دون أي عمولة على الأعمال التي يفوزون بها. للتسجيل:\n' + supplierUrl + '\nيستغرق التحقق حتى 3 أيام عمل.'
        : 'Suppliers register free with a valid UAE trade licence and pay no commission on the work they win. Register at ' + supplierUrl + '; verification takes up to 3 working days.';
    }
    case 'qd_general':
      return ar
        ? 'تفضلوا بكتابة سؤالكم، وسأجيبكم من المعلومات المعتمدة لدينا. كما يمكنكم الاطلاع على الأسئلة الشائعة عبر الرابط التالي:\n' + siteUrl(lang, '/faq')
        : 'Please type your question and I will answer it from our published guidance. You can also read the FAQ at ' + siteUrl(lang, '/faq') + '.';
    case 'qd_problem':
      return ar
        ? 'نأسف لذلك. يُرجى وصف المشكلة في رسالة واحدة، مع ذكر رقم الطلب إن وُجد، وسنفتح لكم بلاغًا برقم مرجعي.'
        : 'Sorry to hear that. Please describe the problem in one message (with the request number if there is one) and I will open a case with a reference number.';
    case 'qd_person':
      return ar
        ? 'شكرًا لكم. طلبنا من أحد أعضاء فريقنا التواصل معكم على هذا الرقم خلال ساعات العمل، من الأحد إلى الخميس من 9 صباحًا حتى 6 مساءً بتوقيت الإمارات.'
        : 'Thank you. I have asked a member of our team to contact you on this number during working hours (Sunday to Thursday, 9am to 6pm UAE time).';
  }
}

export function caseConfirm(lang: Lang, ref: string | null): string {
  if (!ref) {
    return lang === 'ar'
      ? 'شكرًا لكم، وصلتنا رسالتكم. تعذّر إصدار الرقم المرجعي الآن، وسيراجع فريق الدعم رسالتكم ويرد عليكم على هذا الرقم.'
      : 'Thank you, your message has reached us. A reference number could not be issued just now; our support team will review it and reply on this number.';
  }
  return lang === 'ar'
    ? 'شكرًا لكم. الرقم المرجعي لبلاغكم هو ' + ref + '، وسيراجعه فريق الدعم ويرد عليكم على هذا الرقم.'
    : 'Thank you. Your case reference is ' + ref + '. Our support team will review it and reply on this number.';
}

export const MENU_HINT: Record<Lang, string> = {
  en: '\n\nReply MENU at any time to see the options.',
  ar: '\n\nللاطلاع على الخيارات في أي وقت، يُرجى إرسال كلمة «قائمة».',
};
