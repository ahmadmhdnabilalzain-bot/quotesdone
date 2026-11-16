// WHERE DOES "THE SAME CASE" END, FOR EACH EMBEDDER? The measurement behind fn_case_recall's floor.
// Seat: it_engineer. 23 Sep 2026.
//
// fn_case_recall's floor (0.84) was measured for gte-small: paraphrases of one case 0.847-0.924, unrelated
// cases 0.760-0.816. A different model has a different similarity scale, so the multilingual path cannot
// inherit that number; it is measured here on the same kind of pairs, plus the pair gte-small could never
// score — the same case asked in Arabic. Each row: a case situation as the estate records it, the same case
// said differently in English, the same case in Arabic, and a DIFFERENT case framed alike.
//
//   node scripts/archive/eval/case_recall_floor_calibration.mjs
//
// The floor is the highest different-case score rounded UP to 0.01, leaving out the pair marked 'other_trade':
// a different trade framed alike ("40 windows for a villa" vs "200 chairs for an office") is separated by
// fn_case_recall's exact-trade rule, not by similarity (the gte-small measurement found the same, 0.913).
// Ten pairs is a small sample: the floor is a measured starting point, re-measured as cases accumulate.
// Local ONNX (`npm i --no-save @huggingface/transformers@3.8.1` first); nothing is written to production (the multilingual model files are read from its public Storage bucket).
//
// RUN 23 Sep 2026. multilingual-e5-small: same case EN 0.876-0.954, AR 0.803-0.899; different case
// 0.759-0.849 (0.873 for the other-trade pair) -> floor 0.85, 13/20 same-case pairs clear it (EN 10/10,
// AR 3/10). gte-small: AR 0.722-0.849, so an Arabic situation never clears its deployed 0.84 floor.
import { ML_MODEL, mlQueryText, modelHost } from '../../kb/ml_embed_recipe.mjs';
import { PROJECT_REF } from '../../lib/db.mjs';

export const PAIRS = [
  ['6 sign-in codes in an hour to one UAE mobile number | IT engineer duty: otp | blast: security',
   'the same phone number requested six OTP login codes within sixty minutes',
   'تم طلب ستة رموز دخول خلال ساعة واحدة لنفس رقم الهاتف الإماراتي',
   'the nightly database backup did not complete and no export file was written'],
  ['resilience_ping step failed: not run, the tick passed its 110s deadline | IT engineer duty: heartbeat',
   'the heartbeat tick ran out of time before it reached a step, so the step never ran',
   'تجاوزت نبضة المراقبة مهلتها الزمنية فلم تُنفَّذ الخطوة',
   'a supplier uploaded a trade licence that expired last month'],
  ['Stripe test took AED 3728.30 in a checkout session and no transaction records it | IT engineer duty: payment',
   'a card payment succeeded at Stripe but our transactions table has no row for it',
   'تم تحصيل مبلغ عبر سترايب ولكن لا يوجد سجل للمعاملة في قاعدة البيانات',
   'an email to a customer bounced because the mailbox does not exist'],
  ['vendor Resend | USD 20 | receipt from the expenses mailbox | monthly subscription',
   'the monthly 20 dollar Resend email service receipt forwarded to expenses',
   'إيصال الاشتراك الشهري في خدمة البريد Resend بقيمة 20 دولاراً',
   'the founder transferred AED 1,000 of his own money into the company account'],
  ['vendor Dubai Economy and Tourism (DET) e-Trader licence | AED 1200 | paid by a PRO agent, reimbursed in cash',
   'the trade licence fee to DET, paid through a PRO and repaid to him in cash, no receipt',
   'رسوم الرخصة التجارية لدائرة الاقتصاد والسياحة دفعها مندوب وتمت تسويتها نقداً',
   'the Apify scraping subscription invoice of 29 US dollars'],
  ['Decision requested (invite): which approved flooring suppliers should be invited to quote first?',
   'which of the approved flooring companies do we invite first for this quote',
   'أي موردي الأرضيات المعتمدين ندعوهم أولاً لتقديم عروض الأسعار؟',
   'which agent owns signage and printing work when a request for quotation arrives?'],
  ['target_is_reachable | AT_RISK (1 measured / 1 assumed rates)',
   'the revenue target is at risk because only one of the rates is measured',
   'الهدف معرض للخطر لأن معدلاً واحداً فقط مقاس والآخر مفترض',
   'a supplier asked to change the bank account the refund is paid into'],
  ['We need 40 aluminium windows supplied and installed for a private villa in Dubai Marina, double glazed, powder coated white',
   'supply and fit forty double-glazed white aluminium windows at a Dubai Marina villa',
   'توريد وتركيب أربعين نافذة ألمنيوم بزجاج مزدوج لفيلا في دبي مارينا',
   'We need 200 office chairs supplied and delivered for a two-floor office in Dubai', 'other_trade'],
  ['40 split AC units for a two-floor office in Business Bay, supply and install',
   'install forty split air conditioners across a two storey office in Business Bay',
   'تركيب أربعين وحدة تكييف سبليت لمكتب من طابقين في الخليج التجاري',
   'waterproofing of a villa roof in Arabian Ranches before the summer'],
  ['customer asked why the reveal fee is 3% and whether it is refundable if the supplier does not respond',
   'is the 3 percent reveal fee returned when the supplier never answers',
   'هل تُسترد رسوم الكشف البالغة 3٪ إذا لم يرد المورد؟',
   'customer asked how to upload a drawing to an existing inquiry'],
];

const { pipeline, env } = await import('@huggingface/transformers');
const dot = (a, b) => a.reduce((s, x, i) => s + x * b[i], 0);
const MODELS = [
  { model: 'Supabase/gte-small', q: (t) => t },
  { model: ML_MODEL, q: (t) => mlQueryText(t) },
];
for (const m of MODELS) {
  Object.assign(env, modelHost(m.model, `https://${PROJECT_REF}.supabase.co`));
  const f = await pipeline('feature-extraction', m.model, { dtype: 'q8' });
  const e = async (ts) => (await f(ts, { pooling: 'mean', normalize: true })).tolist();
  const anchors = await e(PAIRS.map((r) => m.q(r[0])));   // a case is compared with a case: symmetric, both sides "query: "
  const [en, ar, other] = await Promise.all([1, 2, 3].map((i) => e(PAIRS.map((r) => m.q(r[i])))));
  const s = (vs) => vs.map((v, i) => dot(v, anchors[i]));
  const r = { en: s(en), ar: s(ar), other: s(other) };
  const rng = (a) => `${Math.min(...a).toFixed(3)}-${Math.max(...a).toFixed(3)}`;
  const floor = Math.ceil(Math.max(...r.other.filter((_, i) => PAIRS[i][4] !== 'other_trade')) * 100) / 100;
  const same = [...r.en, ...r.ar];
  console.log(`${m.model}\n  same case EN ${rng(r.en)}   same case AR ${rng(r.ar)}   different case ${rng(r.other)}`
    + `\n  floor ${floor.toFixed(2)}: same-case pairs clearing it ${same.filter((x) => x >= floor).length}/${same.length}`);
}
