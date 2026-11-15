// @ts-nocheck
'use client';
import { useState } from 'react';
import { call } from '../api';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { cn } from '@/lib/utils';
import { t } from './copy';
import { srvMsg } from '../serverCopy';
import { S } from './styles';

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
export const ARCHIVED_AGREEMENTS = ['v10', 'v11', 'v12', 'v13', 'v14', 'v15', 'v16'];
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
  // v13, 23 Sep 2026 (ceo; founder: every legal document at full UAE compliance, penalties at the lawful maximum).
  // The figures are src/content/company_facts.json's; company_facts_agree_everywhere keeps them equal.
  13: {
    en: [
      'Taking a customer introduced through the Platform off the Platform: agreed compensation of AED 20,000 per incident or five (5) times the fee avoided, whichever is higher; the sum includes the fee on that job (clause 24). Sharing contact details during anonymised stages stays AED 10,000 per incident, and never on top of clause 24 (clause 10).',
      'Reusing or reselling Platform data: agreed compensation of AED 25,000 per incident (clause 25).',
      'The administrative fee for a non-response refund is AED 500 for a customer who reveals you after you accept this version (clause 33).',
      'New: fake, duplicate or impersonating accounts and fraudulent quotations — AED 20,000 per account or incident, closure of the accounts and a report to the authorities (clause 36).',
      'New: every agreed sum is a genuine pre-estimate of loss, charged once for any one act, and the court keeps its powers over it (clause 37). Nothing limits liability for fraud or gross negligence (clause 18).',
    ],
    ar: [
      'التعامل خارج المنصة مع عميل جرى التعريف به من خلالها: تعويض اتفاقي قدره 20,000 درهم إماراتي عن كل واقعة أو خمسة (5) أضعاف الرسوم التي تم تجنّبها، أيهما أعلى، ويشمل المبلغ رسوم ذلك العمل (البند 24). وتبقى مشاركة بيانات الاتصال خلال المراحل مجهولة الهوية بمبلغ 10,000 درهم إماراتي عن كل واقعة، ولا تُضاف أبدًا إلى البند 24 (البند 10).',
      'إعادة استخدام بيانات المنصة أو بيعها: تعويض اتفاقي قدره 25,000 درهم إماراتي عن كل واقعة (البند 25).',
      'الرسم الإداري عن الاسترداد بسبب عدم الاستجابة 500 درهم إماراتي إذا كشف عنكم عميل بعد قبولكم هذا الإصدار (البند 33).',
      'جديد: الحسابات الوهمية أو المكررة أو المنتحلة وعروض الأسعار الاحتيالية — 20,000 درهم إماراتي عن كل حساب أو واقعة، وإغلاق الحسابات، وإبلاغ السلطات (البند 36).',
      'جديد: كل مبلغ متفق عليه تقدير حقيقي مسبق للضرر، ويُستحق مرة واحدة عن الفعل الواحد، وتحتفظ المحكمة بصلاحياتها بشأنه (البند 37). ولا يحدّ أي حكم من المسؤولية عن الغش أو الخطأ الجسيم (البند 18).',
    ],
  },
  // v14, 24 Sep 2026 (ceo; founder instruction 990: the non-response charge at the maximum UAE law safely allows).
  // Reasoning and citations: docs/legal/NONRESPONSE_MAX_V14.md. Never retroactive (clause 33, last sentence).
  14: {
    en: [
      'Non-response refund (clause 33): the payment processor fee on the refunded reveal that we could not recover is now charged at its recorded amount, in addition to the refunded amount and the AED 500 administrative fee.',
      'Interest on any overdue amount is simple interest at 12% a year, the rate agreed under the Commercial Transactions Law, never compounded (clauses 31 and 33). An amount that fell due under an earlier version keeps that version\x27s rate.',
      'If a charge stays unpaid, the official fees of recovering it (court, payment-order, execution and notary fees) are added at cost; we may set off what you owe against anything we owe you (clauses 9 and 33).',
    ],
    ar: [
      'الاسترداد بسبب عدم الاستجابة (البند 33): تُحتسب الآن رسوم مزوّد خدمة الدفع على رسوم الكشف المستردّة التي لم نتمكن من استردادها بمبلغها المسجَّل، إضافةً إلى المبلغ المستردّ والرسم الإداري البالغ 500 درهم إماراتي.',
      'تُحتسب على أي مبلغ متأخر فائدة بسيطة بنسبة 12% سنويًا، وهو السعر المتفق عليه وفقًا لقانون المعاملات التجارية، ولا تُركَّب (البندان 31 و33). ويبقى على المبلغ الذي استُحق في ظل إصدار سابق سعرُ ذلك الإصدار.',
      'إذا بقي رسم دون سداد، تُضاف بالتكلفة الرسوم الرسمية لتحصيله (رسوم المحكمة وأمر الأداء والتنفيذ والتوثيق)، ويجوز لنا إجراء المقاصة بين ما تدينون به وأي مبلغ ندين به لكم (البندان 9 و33).',
    ],
  },
  // v15, 6 Oct 2026 (ceo; founder rulings 1155 and the addendum: QuotesDone is a portal and introducer only).
  // Legal basis: CTL 50/2022 Arts 252, 258, 265; Civil Transactions Law 25/2025 Arts 236, 257, 334(2), 443.
  15: {
    en: [
      'QuotesDone is a portal and introducer only. It gives no warranty on leads, inquiries, Customers or results, and is not a party to your contract with a Customer (clauses 17 and 18).',
      'To the fullest extent UAE law permits, QuotesDone is not liable to you. Only if a court refuses that exclusion is its liability capped, at the greater of the fees you paid in the last 12 months or AED 5,000. Fraud, gross fault and harmful acts are never excluded (clause 18).',
      'You indemnify QuotesDone for claims caused by your quotations, statements, licences, goods, works or people (clause 18(c)).',
      'New clause 38: third-party services, a 90-day notice of any claim (late notice never bars it), suspension or removal of unlawful or misleading content, and the entire agreement. Force majeure now names its examples (clause 20). No fee or charge changes.',
    ],
    ar: [
      'QuotesDone بوابة ووسيط تعريف فقط، ولا تقدّم أي ضمان بشأن الفرص أو الطلبات أو العملاء أو النتائج، وليست طرفًا في عقدكم مع العميل (البندان 17 و18).',
      'إلى أقصى حد يجيزه قانون دولة الإمارات، لا تُسأل QuotesDone تجاهكم. وإذا رفضت محكمةٌ هذا الاستبعاد فقط، تُحدَّد مسؤوليتها بالمبلغ الأعلى من الرسوم التي دفعتموها خلال آخر 12 شهرًا أو 5,000 درهم إماراتي. ولا تُستبعد أبدًا المسؤولية عن الغش أو الخطأ الجسيم أو الفعل الضار (البند 18).',
      'تعوّضون QuotesDone عن المطالبات الناشئة عن عروض أسعاركم أو بياناتكم أو رخصكم أو سلعكم أو أعمالكم أو العاملين لديكم (البند 18(ج)).',
      'بند جديد 38: خدمات الغير، والإخطار بأي مطالبة خلال 90 يومًا (ولا يُسقط التأخيرُ المطالبة)، وتعليق المحتوى المخالف أو المضلل أو إزالته، وكامل الاتفاق. ويذكر بند القوة القاهرة أمثلتها الآن (البند 20). لا تغيير في أي رسم.',
    ],
  },
  // v16, 19 Oct 2026 (ceo; legal risk review of 19 Oct 2026, findings 1, 2, 7, 8, 9 and 18).
  16: {
    en: [
      'A new or increased fee applies to you only after you expressly accept it on the Platform; continued use is no longer acceptance (clause 6).',
      'Promotional messages are sent only if you tick a separate box to agree, and your name or logo is used as a reference only with your prior written consent (clause 32).',
      'Decisions made by automated processing are part of the service and you agree to them; an objection goes to QuotesDone Customer Support, then the QuotesDone operations team (clause 27). On day 5 of a silent reveal QuotesDone makes a final contact attempt by phone, WhatsApp or email (clauses 11 and 33).',
      'Acceptance is by ticking the box or clicking to accept, and our records are evidence rather than conclusive evidence (clause 30). The governing law now names the Modern Technology-Based Trade Law, Federal Decree-Law No. 14 of 2023 (clause 34). No fee or charge changes.',
    ],
    ar: [
      'لا تسري عليكم أي رسوم مستحدثة أو مزيدة إلا بعد قبولكم الصريح لها على المنصة؛ ولم يعد استمرار الاستخدام قبولًا (البند 6).',
      'لا تُرسل الرسائل الترويجية إلا إذا وضعتم علامة في مربع مستقل للموافقة عليها، ولا يُستخدم اسمكم أو شعاركم مرجعًا إلا بموافقتكم الكتابية المسبقة (البند 32).',
      'القرارات الصادرة بالمعالجة الآلية جزء من الخدمة وتوافقون عليها، ويُقدَّم الاعتراض إلى فريق دعم العملاء في QuotesDone ثم إلى فريق العمليات فيها (البند 27). وفي اليوم الخامس من عدم الاستجابة بعد الكشف تجري QuotesDone محاولة اتصال أخيرة عبر الهاتف أو واتساب أو البريد الإلكتروني (البندان 11 و33).',
      'يكون القبول بوضع علامة في المربع أو النقر للقبول، وتُعدّ سجلاتنا دليلًا لا دليلًا قاطعًا (البند 30). ويذكر بند القانون الواجب التطبيق الآن قانون التجارة عبر وسائل التقنية الحديثة، المرسوم بقانون اتحادي رقم 14 لسنة 2023 (البند 34). لا تغيير في أي رسم.',
    ],
  },
  // v17, 2 Nov 2026 (ceo; ledger 1482): the contact line only. Shown to a supplier asked to accept v17 who last accepted v15 or earlier;
  // a v16 supplier is not asked (needsReaccept above).
  17: {
    en: ['The contact line (clause 35) now gives +971 56 791 8605 for calls and +1 218 316 6814 for WhatsApp. No clause, fee or charge changes.'],
    ar: ['يذكر سطر التواصل (البند 35) الآن الرقم +971 56 791 8605 للاتصال والرقم +1 218 316 6814 لواتساب. لا تغيير في أي بند أو رسم أو مبلغ.'],
  },
};
export function agreementChanges(accepted, current, ar) {
  const n = (v) => Number(String(v || '').replace(/\D/g, '')) || 0;
  const from = n(accepted), to = n(current);
  return Object.keys(AGREEMENT_CHANGES).map(Number).sort((a, b) => a - b)
    .filter((v) => v > from && v <= to).flatMap((v) => AGREEMENT_CHANGES[v][ar ? 'ar' : 'en']);
}
// 2 Nov 2026 (ceo; ledger 1482): terms_stands is the server's answer to 'does this supplier's acceptance still stand?'. It is true
// for the current version AND for a version the current one carries because it differs in the contact line only (v16 -> v17), so
// a contact-only revision never sends a signed supplier back to this card. Absent (an older server) falls back to the plain compare.
export function needsReaccept(me) {
  if (!(me && me.accepted_terms_at && me.terms_current)) return false;
  if (typeof me.terms_stands === 'boolean') return !me.terms_stands;
  return me.accepted_terms_version !== me.terms_current;
}
function ReacceptTerms({ token, lang, me, onDone }) {
  const ar = lang === 'ar'; const pre = ar ? '/ar' : '';
  const [ok, setOk] = useState(false); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const accept = async () => {
    if (!ok) { setMsg(t(lang, 'must_accept')); return; }
    setBusy(true); setMsg('');
    const j = await call('supplier_api', { action: 'accept_terms' }, token).catch(() => null);
    // the server's own sentence (terms_not_recorded: "We could not record your acceptance just now ... press the button again"),
    // never only "Something went wrong." (15 Nov 2026, third review of the certificate branch, item 6)
    if (!j || !j.ok) { setBusy(false); setMsg(srvMsg(lang, j, t(lang, 'err_generic'))); return; }
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
export { ReacceptTerms };
