// EVAL A's FIXED SET: 40 scripted customer, supplier and visitor turns, 10 per register (English; Gulf, Egyptian and Levantine
// Arabic, with Arabizi and code-switching). Scripted, never simulated: no model writes the customer's side, so runs compare.
// Seat: it_engineer (cost). 10 Nov 2026. Design docs/reports/2026-11-10-design-model-routing.md section 5c.
// Every party is ZZ DEMO; every number is the fixture block 9715000000NN; nothing here is a real person or a real request.
//   12 status, 4 invoice-copy, 4 "is my comparison ready?", 4 "my code didn't come", 8 support, 4 supplier thread (English),
//   4 visitor.
export type Register = 'en' | 'gulf' | 'egy' | 'lev';
export type Kind = 'status' | 'invoice' | 'report' | 'code' | 'support' | 'supplier' | 'visitor';
export interface CaseA {
  id: string; register: Register; kind: Kind; lang: 'en' | 'ar'; message: string;
  history?: { role: 'customer' | 'seat'; text: string }[];
  /** what code decided (fn_wa_answer's answer, the sender's own record): the facts the reply must convey */
  facts?: string;
  must?: string[];
  /** a fact the reply must convey (checked by the judge, listed for it) */
  expect: string;
}

const RECORD = (o: Record<string, unknown>) => 'THIS SENDER\'S OWN RECORD (read live; it is theirs, so you may state it back to them, and you must never state anyone else\'s):\n' + JSON.stringify(o);
const DB = (t: string) => 'OUR DATABASE ANSWER FOR THIS MESSAGE (facts to use; the words are yours):\n' + t;
const CUST = 'AUDIENCE: this number belongs to a REGISTERED CUSTOMER. Treat them as a customer.';
const SUP = 'AUDIENCE: this number belongs to a REGISTERED SUPPLIER (ZZ DEMO Eval Gypsum Works LLC), already verified. Their OWN record is supplied below and you may state it back to them plainly.';
const facts = (...p: string[]) => p.join('\n\n');

const INVOICE = 'A customer\'s invoice and payment receipt for a revealed quote are in the customer portal, https://quotesdone.com/me : My requests, open the request, then "Invoice (PDF)" or "Receipt (PDF)" on the revealed quote (an Arabic invoice is offered there too). A payment that has not completed has no invoice or receipt yet.';
const CODE = 'A new sign-in code can be asked for on the sign-in page, and asking for a new one cancels every earlier code, so only the newest code works. A code sent on WhatsApp that has not arrived within a minute can be sent by SMS instead with the "Send it by SMS instead" button. Nobody from QuotesDone asks for a code.';

const status = (id: string, register: Register, lang: 'en' | 'ar', message: string, req: number, quotes: number, suppliers: number, history?: CaseA['history']): CaseA => ({
  id, register, kind: 'status', lang, message, history,
  facts: facts(CUST, RECORD({ name: 'ZZ DEMO Eval Customer ' + id, requests: [{ ref: '#' + req, trade: 'gypsum partitions', status: 'open, quotes being collected', suppliers_invited: suppliers, quotes_received: quotes }] }),
    DB(`Request #${req} (gypsum partitions) is open: ${suppliers} matched suppliers received it and ${quotes} quote${quotes === 1 ? ' has' : 's have'} come in so far. The comparison report is prepared once the quotes are in.`)),
  must: ['#' + req], expect: `request #${req} is open, ${suppliers} suppliers received it, ${quotes} quotes so far`,
});
const report = (id: string, register: Register, lang: 'en' | 'ar', message: string, req: number): CaseA => ({
  id, register, kind: 'report', lang, message,
  facts: facts(CUST, RECORD({ name: 'ZZ DEMO Eval Customer ' + id, requests: [{ ref: '#' + req, trade: 'aluminium windows', status: 'comparison report ready', quotes_received: 3 }] }),
    DB(`The comparison report for request #${req} (aluminium windows) is ready: 3 quotes are compared side by side in the customer portal, https://quotesdone.com/me , under My requests. Suppliers stay anonymous until the customer chooses one to reveal.`)),
  must: ['#' + req], expect: `the comparison report for #${req} is ready, 3 quotes, in My requests`,
});
const invoice = (id: string, register: Register, lang: 'en' | 'ar', message: string): CaseA => ({
  id, register, kind: 'invoice', lang, message, facts: facts(CUST, DB(INVOICE)), must: ['https://quotesdone.com/me'],
  expect: 'invoice and receipt are in the portal: My requests > the request > Invoice (PDF) / Receipt (PDF)',
});
const code = (id: string, register: Register, lang: 'en' | 'ar', message: string): CaseA => ({
  id, register, kind: 'code', lang, message, facts: facts(CUST, DB(CODE)), expect: 'ask for a new code on the sign-in page (it cancels older codes); WhatsApp code -> "Send it by SMS instead"',
});
const support = (id: string, register: Register, lang: 'en' | 'ar', message: string, expect: string, history?: CaseA['history']): CaseA => ({
  id, register, kind: 'support', lang, message, history, facts: CUST, expect,
});
const supplier = (id: string, register: Register, message: string, expect: string): CaseA => ({
  id, register, kind: 'supplier', lang: 'en', message,
  facts: facts(SUP, RECORD({ company: 'ZZ DEMO Eval Gypsum Works LLC', status: 'verified', open_jobs: [{ job: 'Job 7731', trade: 'gypsum partitions', quote_due: 'quotes accepted until the customer selects a supplier' }] })),
  expect,
});
const visitor = (id: string, register: Register, lang: 'en' | 'ar', message: string, expect: string): CaseA => ({ id, register, kind: 'visitor', lang, message, expect });

export const CASES_A: CaseA[] = [
  // ── English ──
  status('en-s1', 'en', 'en', 'Hi, any update on my request?', 5101, 2, 5),
  status('en-s2', 'en', 'en', 'how many quotes did i get so far', 5102, 0, 4),
  status('en-s3', 'en', 'en', 'Is anyone working on my partition job? Its been 2 days', 5103, 1, 3),
  invoice('en-i1', 'en', 'en', 'Can you send me my invoice again please, I deleted the email'),
  report('en-r1', 'en', 'en', 'Is my comparison ready yet?', 5104),
  code('en-c1', 'en', 'en', 'my verification code didnt come'),
  support('en-p1', 'en', 'en', 'What does it cost me to use QuotesDone?', 'posting and comparing are free; 3% reveal fee of the chosen quote, no card fee, no VAT on it'),
  support('en-p2', 'en', 'en', 'If I pay the reveal fee and the supplier does not answer, do I get a refund?', 'states the refund position from the brief without promising a refund'),
  supplier('en-x1', 'en', 'I want to submit a revised quote for Job 7731, how?', 'revise in the portal: open the job, attach a revised file / submit again replaces the earlier quote for that option'),
  visitor('en-v1', 'en', 'en', 'How does QuotesDone work?', 'post a request free, verified suppliers quote anonymously, compare, reveal fee 3%'),
  // ── Gulf (Emirati / Saudi) ──
  status('gu-s1', 'gulf', 'ar', 'السلام عليكم، شلون طلبي؟ أبي أعرف وين وصل', 5201, 3, 6),
  status('gu-s2', 'gulf', 'ar', 'كم عرض وصلني لين الحين؟', 5202, 1, 4),
  status('gu-s3', 'gulf', 'ar', 'wayed t2a5art, shu sar 3la tlabi?', 5203, 0, 5, [{ role: 'customer', text: 'هلا، عندي طلب جبس بورد' }, { role: 'seat', text: 'هلا والله، كيف أقدر أساعدك؟' }]),
  invoice('gu-i1', 'gulf', 'ar', 'أبي نسخة من الفاتورة لو سمحت'),
  report('gu-r1', 'gulf', 'ar', 'المقارنة جاهزة ولا بعد؟', 5204),
  code('gu-c1', 'gulf', 'ar', 'الكود ما وصلني، شو أسوي؟'),
  support('gu-p1', 'gulf', 'ar', 'كم رسوم الكشف عن المورد؟ وفي ضريبة؟', 'reveal fee 3% of the chosen quote, no card fee, no VAT charged on it'),
  support('gu-p2', 'gulf', 'ar', 'زين، والموردين عندكم موثوقين؟ شلون تتأكدون منهم؟', 'suppliers are verified (licence and documents checked) before they receive requests; no count of suppliers'),
  supplier('gu-x1', 'gulf', 'Hello, Job 7731 deadline when? I want to send my price', 'quotes accepted until the customer selects a supplier; submit in the portal on the job'),
  visitor('gu-v1', 'gulf', 'ar', 'وش هي كويتس دن؟ أبي أفهم الخدمة', 'what QuotesDone is: free request, anonymous verified quotes, compare, 3% reveal fee'),
  // ── Egyptian ──
  status('eg-s1', 'egy', 'ar', 'لو سمحت عايز أعرف طلبي وصل لفين', 5301, 2, 4),
  status('eg-s2', 'egy', 'ar', 'هو في عروض جت ولا لسه؟', 5302, 0, 3),
  status('eg-s3', 'egy', 'ar', '3ayez a3raf el status beta3 el talab bta3i', 5303, 4, 6, [{ role: 'customer', text: 'أنا عملت طلب تقسيمات جبس' }, { role: 'seat', text: 'أهلاً بك، تحت أمرك.' }]),
  invoice('eg-i1', 'egy', 'ar', 'ممكن تبعتلي الفاتورة تاني؟ مش لاقيها'),
  report('eg-r1', 'egy', 'ar', 'المقارنة بتاعتي خلصت ولا لسه؟', 5304),
  code('eg-c1', 'egy', 'ar', 'كود التفعيل مجاش، أعمل إيه؟'),
  support('eg-p1', 'egy', 'ar', 'هو أنا هدفع كام عشان أشوف بيانات المورد؟', 'reveal fee 3% of the chosen quote, no card fee, no VAT on it'),
  support('eg-p2', 'egy', 'ar', 'إزاي بتختاروا الموردين اللي بيبعتولي عروض؟', 'requests go to verified suppliers in the exact trade; matched by trade; no supplier names'),
  supplier('eg-x1', 'egy', 'Hi, I am supplier, how I add another option to my quote for Job 7731?', 'a quote may carry separate options; submit again for that option in the portal'),
  visitor('eg-v1', 'egy', 'ar', 'هو الموقع ده بيعمل إيه بالظبط؟', 'what QuotesDone does'),
  // ── Levantine ──
  status('lv-s1', 'lev', 'ar', 'مرحبا، بدي أعرف شو صار بطلبي', 5401, 1, 5),
  status('lv-s2', 'lev', 'ar', 'كم عرض إجاني لهلق؟', 5402, 3, 3),
  status('lv-s3', 'lev', 'ar', 'marhaba, badde a3ref eza fi 3orood 3a talabi, yalla', 5403, 2, 4, [{ role: 'customer', text: 'عندي طلب قواطع جبس' }, { role: 'seat', text: 'أهلين، كيف فيني ساعدك؟' }]),
  invoice('lv-i1', 'lev', 'ar', 'فيك تبعتلي الفاتورة مرة تانية؟'),
  report('lv-r1', 'lev', 'ar', 'المقارنة صارت جاهزة؟', 5404),
  code('lv-c1', 'lev', 'ar', 'ما وصلني رمز التحقق، شو بعمل؟'),
  support('lv-p1', 'lev', 'ar', 'قديش الرسوم عندكن؟ في رسوم على البطاقة؟', 'free to post and compare; 3% reveal fee; no card fee; no VAT on it'),
  support('lv-p2', 'lev', 'ar', 'إذا ما عجبني ولا عرض، لازم أدفع شي؟', 'nothing to pay unless they reveal a supplier'),
  supplier('lv-x1', 'lev', 'Good morning, for Job 7731 can I submit price without drawing details?', 'a supplier answers what it can; questions about the job go through the job in the portal; no promise of details'),
  visitor('lv-v1', 'lev', 'ar', 'كيف بشتغل الموقع؟ ببلش من وين؟', 'how it works and where to start (post a request free)'),
];
