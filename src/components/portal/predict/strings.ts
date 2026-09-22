// English/Arabic copy for the Predictive Intelligence (§20) surface. The customer portal picks
// language at the shell level, so the component takes `lang` and falls back to English per key.
// (§15 Negotiation Assistant copy lived here until 21 Sep 2026 — founder instruction 526.)
//
// THE EMPTY STATES ARE THE POINT OF THIS FILE. Production holds zero customers, zero inquiries and
// zero quotes, so both routines behind these surfaces answer with an `empty_reason` sentence and no
// figures — every string below marked `empty_` is what a real person reads today. Each says which
// of several DIFFERENT absences is true: never having raised a request is not the same fact as
// having raised some but too few to project from, and neither is the same as having nothing to
// predict because no open project carries a target date. A prediction the portal cannot make must
// read as an absence, never as "nothing is coming up".
import type { Lang, Urgency } from './model';
import { arDays } from '@/lib/durationLabel';

const EN = {
  /* §20 predictive */
  predict: 'What you will need next',
  predict_sub:
    'Predicted from your own history: the trades you have procured on your other projects, offset by the lead time you have actually needed for them.',
  loading_predict: 'Working out what your projects will need…',
  retry: 'Retry',
  err_load: 'Could not load your forecast.',
  err_session: 'Your session has expired. Please sign in again.',
  err_unexpected: 'Something went wrong at our end. Your requests are unaffected — please try again.',

  empty_no_history_title: 'Nothing to predict from yet',
  empty_no_predictions_title: 'No upcoming requirement could be predicted',
  empty_no_predictions_body:
    'A prediction needs an open project with a target open date and a trade you have already procured on another project. Nothing on this account meets both yet, so no requirement is being claimed — this is an absence of evidence, not a quiet period.',

  p_within: (d: number) => (d <= 0 ? 'Needed now' : `Within ${d} day${d === 1 ? '' : 's'}`),
  p_for: 'For',
  p_by: 'Raise by',
  p_confidence: 'Confidence',
  p_why: 'Why',
  p_action: 'Recommended',
  c_high: 'High',
  c_medium: 'Medium',
  c_low: 'Low',
  u_now: 'Act now',
  u_soon: 'Soon',
  u_planned: 'Planned',

  fc_title: 'Next-year procurement forecast',
  fc_sub: (d: number) => `Projected over the next ${d} days from your own run rate. Actuals are your posted requests.`,
  fc_rfqs: 'Projected requests',
  fc_spend: 'Projected spend',
  fc_observed: 'Requests so far',
  fc_observed_spend: 'Spend so far',
  fc_by_category: 'By trade',
  fc_share: 'of your requests',
  fc_not_projected: 'Not projected',
} as const;

type Key = keyof typeof EN;

/**
 * Per-key typing, so a translation can never be a different SHAPE from the English it replaces — a
 * key that takes (d: number) still takes (d: number) in Arabic. `as const` also gives every English
 * string a literal type, and a translation is a different string rather than a different key, so
 * the string arms are widened and only the shape is enforced.
 */
type Widen<T> = T extends string ? string : T;
type Translations = { [K in Key]?: Widen<(typeof EN)[K]> };

const AR: Translations = {
  predict: 'ما ستحتاجه لاحقًا',
  predict_sub:
    'تقديرات مبنية على سجلك وحده: التخصصات التي اشتريتها في مشاريعك الأخرى، بعد خصم المهلة التي احتجتها فعليًا لكل منها.',
  loading_predict: 'جارٍ حساب ما ستحتاجه مشاريعك…',
  retry: 'إعادة المحاولة',
  err_load: 'تعذّر تحميل التوقعات.',
  err_session: 'انتهت الجلسة. يُرجى تسجيل الدخول مجددًا.',
  err_unexpected: 'حدث خطأ من جهتنا، ولم تتأثر طلباتك. يُرجى المحاولة مرة أخرى.',

  empty_no_history_title: 'لا توجد بيانات كافية للتوقع بعد',
  empty_no_predictions_title: 'تعذّر التنبؤ بأي احتياج قادم',
  empty_no_predictions_body:
    'يتطلب التوقع مشروعًا مفتوحًا له تاريخ افتتاح مستهدف، وتخصصًا سبق أن اشتريته في مشروع آخر. لا يستوفي هذا الحساب الشرطين بعد، لذا لا نعرض أي احتياج؛ فغياب التوقع هنا يعني نقص البيانات لا قلة الطلب.',

  p_within: (d: number) => (d <= 0 ? 'مطلوب الآن' : `خلال ${arDays(d, { genitive: true })}`),
  p_for: 'لمشروع',
  p_by: 'يُطرح الطلب قبل',
  p_confidence: 'درجة الثقة',
  p_why: 'السبب',
  p_action: 'التوصية',
  c_high: 'مرتفعة',
  c_medium: 'متوسطة',
  c_low: 'منخفضة',
  u_now: 'تصرّف الآن',
  u_soon: 'قريبًا',
  u_planned: 'مُخطَّط',

  fc_title: 'توقعات المشتريات للعام القادم',
  fc_sub: (d: number) => `تقديرات للأيام الـ${d} القادمة بناءً على معدلك وحده، أما الأرقام الفعلية فهي طلباتك المنشورة.`,
  fc_rfqs: 'الطلبات المتوقعة',
  fc_spend: 'الإنفاق المتوقع',
  fc_observed: 'الطلبات حتى الآن',
  fc_observed_spend: 'الإنفاق حتى الآن',
  fc_by_category: 'حسب التخصص',
  fc_share: 'من طلباتك',
  fc_not_projected: 'غير متوقَّع',

};

export function tr<K extends Key>(lang: Lang, key: K): Widen<(typeof EN)[K]> {
  return ((lang === 'ar' ? AR[key] : undefined) ?? EN[key]) as Widen<(typeof EN)[K]>;
}

export function confidenceLabel(lang: Lang, c: string): string {
  if (c === 'high') return tr(lang, 'c_high') as string;
  if (c === 'medium') return tr(lang, 'c_medium') as string;
  if (c === 'low') return tr(lang, 'c_low') as string;
  return c;
}

export function urgencyLabel(lang: Lang, u: Urgency): string {
  if (u === 'now') return tr(lang, 'u_now') as string;
  if (u === 'soon') return tr(lang, 'u_soon') as string;
  return tr(lang, 'u_planned') as string;
}

/**
 * Error codes the endpoints actually emit, in the customer's language.
 *
 * THE FALLBACK USED TO BE `return code`, and the comment above it said "shown verbatim, never
 * dressed up". Honest in intent, and the intent is kept — a failure is still stated, never
 * swallowed. But `code` is whatever the edge function put in `error`, and those functions return
 * raw exception text: quote_compare's own catch is `J({ error: String(e.message) }, 500)`.
 * MEASURED 13 Aug 2026 on a customer's own request screen, in the browser:
 *
 *     Could not load negotiation guidance. invalid input syntax for type uuid: "q-b-1"
 *
 * A Postgres parse error, in a red box, on the screen where a procurement manager is deciding
 * which supplier to pay. Verbatim is the right rule for a sentence WE wrote for the customer;
 * it is the wrong rule for a string the database wrote for us. Unknown codes now get a human
 * sentence, and the raw code rides along in `title` so support can still read it.
 */
export function errText(lang: Lang, code: string): string {
  if (code === 'unauthorized') return tr(lang, 'err_session') as string;
  return tr(lang, 'err_unexpected') as string;
}
