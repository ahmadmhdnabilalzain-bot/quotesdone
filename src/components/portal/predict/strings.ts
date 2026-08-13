// English/Arabic copy for the Predictive Intelligence (§20) and Negotiation Assistant (§15)
// surfaces. The customer portal picks language at the shell level, so both components take `lang`
// and fall back to English per key.
//
// THE EMPTY STATES ARE THE POINT OF THIS FILE. Production holds zero customers, zero inquiries and
// zero quotes, so both routines behind these surfaces answer with an `empty_reason` sentence and no
// figures — every string below marked `empty_` is what a real person reads today. Each says which
// of several DIFFERENT absences is true: never having raised a request is not the same fact as
// having raised some but too few to project from, and neither is the same as having nothing to
// predict because no open project carries a target date. A prediction the portal cannot make must
// read as an absence, never as "nothing is coming up".
import type { Lang, Urgency } from './model';

const EN = {
  /* §20 predictive */
  predict: 'What you will need next',
  predict_sub:
    'Predicted from your own history: the trades you have procured on your other projects, offset by the lead time you have actually needed for them.',
  loading_predict: 'Working out what your projects will need…',
  retry: 'Retry',
  err_load: 'Could not load your forecast.',
  err_session: 'Your session has expired. Please sign in again.',

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

  /* §15 negotiation */
  neg: 'Negotiation assistant',
  neg_sub: 'Your quote against the market, the action the house policy recommends, and a message you can send as written.',
  loading_neg: 'Comparing this quote to the market…',
  err_load_neg: 'Could not load negotiation guidance.',
  err_not_your_quote: 'That quote is not on one of your requests.',
  err_unexpected: 'Something went wrong at our end. Your quotes are unaffected — please try again.',
  empty_no_quote_title: 'Open a quote to compare it',
  empty_no_quote_body:
    'Pick one of the quotes on your requests and this panel shows where it sits against the market, what the house policy recommends, and a message drafted for the supplier.',

  n_quote: 'This quote',
  n_market: 'Market average',
  n_sample: (n: number) => `median of ${n} comparable quote${n === 1 ? '' : 's'}`,
  n_above: 'above the market median',
  n_below: 'below the market median',
  n_level: 'level with the market median',
  n_action: 'Recommended action',
  n_target: 'Target price',
  n_no_target: 'No target price is proposed',
  n_message: 'Suggested message',
  n_message_ar: 'Arabic version',
  n_copy: 'Copy',
  n_copied: 'Copied',
  n_no_benchmark_title: 'No market benchmark yet',
  n_policy_scope: 'Policy',
  n_supplier_locked: 'Supplier name appears once you reveal this quote.',
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
    'متوقَّع من سجلك أنت: التخصصات التي اشتريتها في مشاريعك الأخرى، مطروحًا منها المهلة الزمنية التي احتجتها فعليًا لها.',
  loading_predict: 'جارٍ حساب ما ستحتاجه مشاريعك…',
  retry: 'إعادة المحاولة',
  err_load: 'تعذّر تحميل التوقعات.',
  err_session: 'انتهت الجلسة. الرجاء تسجيل الدخول مجددًا.',

  empty_no_history_title: 'لا يوجد ما يمكن التنبؤ منه بعد',
  empty_no_predictions_title: 'تعذّر التنبؤ بأي احتياج قادم',
  empty_no_predictions_body:
    'يحتاج التنبؤ إلى مشروع مفتوح له تاريخ افتتاح مستهدف، وإلى تخصص سبق أن اشتريته في مشروع آخر. لا يوجد على هذا الحساب ما يستوفي الشرطين، لذلك لا يُدّعى أي احتياج — هذا غياب دليل، وليس فترة هدوء.',

  p_within: (d: number) => (d <= 0 ? 'مطلوب الآن' : `خلال ${d} يومًا`),
  p_for: 'لمشروع',
  p_by: 'يُرفع قبل',
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
  fc_sub: (d: number) => `متوقَّعة خلال ${d} يومًا القادمة بناءً على معدلك أنت. الأرقام الفعلية هي طلباتك المنشورة.`,
  fc_rfqs: 'الطلبات المتوقعة',
  fc_spend: 'الإنفاق المتوقع',
  fc_observed: 'الطلبات حتى الآن',
  fc_observed_spend: 'الإنفاق حتى الآن',
  fc_by_category: 'حسب التخصص',
  fc_share: 'من طلباتك',
  fc_not_projected: 'غير متوقَّع',

  neg: 'مساعد التفاوض',
  neg_sub: 'عرضك مقارنةً بالسوق، والإجراء الذي توصي به سياسة الشركة، ورسالة جاهزة للإرسال كما هي.',
  loading_neg: 'جارٍ مقارنة هذا العرض بالسوق…',
  err_load_neg: 'تعذّر تحميل إرشادات التفاوض.',
  err_not_your_quote: 'هذا العرض ليس ضمن طلباتك.',
  err_unexpected: 'حدث خطأ لدينا. عروضك لم تتأثر — يُرجى المحاولة مرة أخرى.',
  empty_no_quote_title: 'افتح عرضًا لمقارنته',
  empty_no_quote_body:
    'اختر أحد العروض على طلباتك، وستعرض هذه اللوحة موقعه مقابل السوق، وما توصي به سياسة الشركة، ورسالة مصاغة للمورّد.',

  n_quote: 'هذا العرض',
  n_market: 'متوسط السوق',
  n_sample: (n: number) => `وسيط ${n} عرضًا مماثلًا`,
  n_above: 'أعلى من وسيط السوق',
  n_below: 'أدنى من وسيط السوق',
  n_level: 'مساوٍ لوسيط السوق',
  n_action: 'الإجراء الموصى به',
  n_target: 'السعر المستهدف',
  n_no_target: 'لا يُقترح سعر مستهدف',
  n_message: 'الرسالة المقترحة',
  n_message_ar: 'النسخة العربية',
  n_copy: 'نسخ',
  n_copied: 'تم النسخ',
  n_no_benchmark_title: 'لا يوجد مرجع سوقي بعد',
  n_policy_scope: 'السياسة',
  n_supplier_locked: 'يظهر اسم المورّد بعد كشف هذا العرض.',
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
  if (code === 'not_your_quote') return tr(lang, 'err_not_your_quote') as string;
  return tr(lang, 'err_unexpected') as string;
}
