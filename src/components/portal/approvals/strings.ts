// English/Arabic copy for the Approvals (§12) and Orders (§22) surfaces. The customer portal picks
// language at the shell level, so both components take `lang` and fall back to English per key.
//
// THE EMPTY STATES ARE THE POINT OF THIS FILE. Production has zero customers, zero organizations,
// zero policies, zero approval requests and zero orders, so every string below marked `empty_` is
// what a real person actually reads today. Each one says which of several DIFFERENT absences is
// true — no organization is not the same fact as no policy, and neither is the same as no purchase
// having needed approval yet. The worst defect this portal has shipped was an empty state that read
// identically whether or not anything had happened; none of these may repeat it.
import type { Lang, StepStatus } from './model';

const EN = {
  /* approvals */
  approvals: 'Approvals',
  approvals_sub: 'Purchases routed through your organisation’s approval chain.',
  loading_approvals: 'Loading your approval requests…',
  retry: 'Retry',
  err_load: 'Could not load your approvals.',
  err_session: 'Your session has expired. Please sign in again.',
  err_decide: 'Could not record that decision.',

  empty_no_org_title: 'This account is not part of an organisation',
  empty_no_org_body:
    'Approval chains belong to organisation accounts: a policy names the people who sign off, and awards above its threshold are routed to them in order. Nothing you buy on this account is routed for approval, so there is nothing to show here.',
  empty_no_policy_title: 'No approval policy is configured',
  empty_no_policy_body:
    'Your organisation exists but has no approval policy, so awards are not routed to anyone for sign-off. A policy defines the threshold and the named steps — Engineer, Project Manager, Finance, and so on — and this page fills in from the first award that matches one.',
  empty_no_requests_title: 'No purchase has needed approval yet',
  empty_no_requests_body:
    'Nothing has been routed for sign-off. When you award a quote that matches one of the policies below, its chain is raised here and each step shows whether it is approved, pending or still waiting.',
  policies_title: 'Your approval chains',
  policies_note: 'The steps a matching award would be routed through, in order.',
  policy_inactive: 'Inactive',
  policy_threshold: 'Applies when',
  policy_no_conditions: 'Applies to every award.',
  policy_no_steps: 'This policy names no steps, so nothing would be routed through it.',

  req_title: 'Purchase request',
  req_for: 'Raised on',
  req_step_of: (a: number, b: number) => `Step ${a} of ${b}`,
  req_progress: (a: number, b: number) => `${a} of ${b} step${b === 1 ? '' : 's'} approved`,
  req_waiting_on: 'Waiting on',
  req_finished: 'This chain is complete.',
  req_stopped: 'This chain was stopped by a rejection.',
  decided_at: 'Decided',
  decide_approve: 'Approve',
  decide_reject: 'Reject',
  decide_busy: 'Saving…',
  decide_note_ph: 'Add a note (optional)',
  decide_confirm_reject: 'Reject this purchase request? The chain stops here and no later step is asked.',
  decide_not_yours:
    'This step is decided by someone else in your organisation. You can see its state but not act on it.',
  open_rfq: 'Open the awarded RFQ',

  st_approved: 'Approved',
  st_rejected: 'Rejected',
  st_pending: 'Pending',
  st_waiting: 'Waiting',
  st_blocked: 'Not reached',

  /* orders */
  orders: 'Orders',
  orders_sub: 'Purchase orders raised against the quotes you awarded.',
  loading_orders: 'Loading your orders…',
  err_load_orders: 'Could not load your orders.',
  empty_orders_title: 'You have no orders yet',
  empty_orders_body:
    'An order appears here once a purchase order is raised against a quote you awarded. Nothing has been raised on this account, so there is nothing to track — no order has been placed, delivered or invoiced on your behalf.',
  k_ordered: 'Ordered',
  k_expected: 'Expected',
  k_value: 'Order value',
  k_status: 'Status',
  k_lines: 'Lines',
  k_received: 'Received',
  value_unknown: 'Not priced',
  value_unknown_note: 'This order carries no total and not every line is priced, so no value is shown.',
  received_unknown: 'No receipts recorded',
  date_unknown: 'Not set',
  no_lines: 'This order has no line items recorded.',
  linked_project: 'Project',
  linked_rfq: 'From RFQ',
  approved_on: 'Approved',
  qty_of: (got: string, ordered: string) => `${got} of ${ordered} received`,
} as const;

type Key = keyof typeof EN;

/**
 * Per-key typing, so a translation can never be a different SHAPE from the English it replaces — a
 * key that takes (a: number, b: number) still takes them in Arabic. `as const` also gives every
 * English string a literal type, and a translation is a different string rather than a different
 * key, so the string arms are widened and only the shape is enforced.
 */
type Widen<T> = T extends string ? string : T;
type Translations = { [K in Key]?: Widen<(typeof EN)[K]> };

const AR: Translations = {
  approvals: 'الموافقات',
  approvals_sub: 'المشتريات المُوجَّهة عبر سلسلة الموافقات في مؤسستك.',
  loading_approvals: 'جارٍ تحميل طلبات الموافقة…',
  retry: 'إعادة المحاولة',
  err_load: 'تعذّر تحميل الموافقات.',
  err_session: 'انتهت الجلسة. الرجاء تسجيل الدخول مجددًا.',
  err_decide: 'تعذّر تسجيل القرار.',

  empty_no_org_title: 'هذا الحساب غير مرتبط بمؤسسة',
  empty_no_org_body:
    'سلاسل الموافقة خاصة بحسابات المؤسسات: تحدّد السياسة الأشخاص الذين يوقّعون، وتُوجَّه إليهم الترسيات التي تتجاوز الحد المقرر بالترتيب. لا شيء تشتريه على هذا الحساب يمرّ عبر موافقة، لذلك لا يوجد ما يُعرض هنا.',
  empty_no_policy_title: 'لا توجد سياسة موافقات مُهيّأة',
  empty_no_policy_body:
    'مؤسستك موجودة لكن دون سياسة موافقات، لذلك لا تُوجَّه الترسيات لأي شخص للتوقيع. تحدّد السياسة الحد المالي والخطوات المسمّاة — المهندس، مدير المشروع، المالية وغيرها — وتمتلئ هذه الصفحة من أول ترسية تطابق إحداها.',
  empty_no_requests_title: 'لم تحتج أي عملية شراء إلى موافقة بعد',
  empty_no_requests_body:
    'لم يُوجَّه أي شيء للتوقيع. عندما ترسّي عرضًا يطابق إحدى السياسات أدناه، تُرفع سلسلته هنا وتُظهر كل خطوة ما إذا كانت مُعتمدة أو قيد الانتظار أو لم يحن دورها بعد.',
  policies_title: 'سلاسل الموافقة لديك',
  policies_note: 'الخطوات التي ستمرّ عبرها الترسية المطابِقة، بالترتيب.',
  policy_inactive: 'غير مفعّلة',
  policy_threshold: 'تنطبق عندما',
  policy_no_conditions: 'تنطبق على كل ترسية.',
  policy_no_steps: 'لا تحدّد هذه السياسة أي خطوات، لذلك لن يمرّ عبرها شيء.',

  req_title: 'طلب شراء',
  req_for: 'مرفوع على',
  req_step_of: (a: number, b: number) => `الخطوة ${a} من ${b}`,
  req_progress: (a: number, b: number) => `${a} من ${b} خطوة مُعتمدة`,
  req_waiting_on: 'بانتظار',
  req_finished: 'اكتملت هذه السلسلة.',
  req_stopped: 'تم إيقاف هذه السلسلة برفض.',
  decided_at: 'تاريخ القرار',
  decide_approve: 'اعتماد',
  decide_reject: 'رفض',
  decide_busy: 'جارٍ الحفظ…',
  decide_note_ph: 'أضف ملاحظة (اختياري)',
  decide_confirm_reject: 'رفض طلب الشراء هذا؟ تتوقف السلسلة هنا ولن تُطلب أي خطوة لاحقة.',
  decide_not_yours: 'يقرّر هذه الخطوة شخص آخر في مؤسستك. يمكنك رؤية حالتها دون اتخاذ إجراء عليها.',
  open_rfq: 'فتح الطلب المُرسّى',

  st_approved: 'مُعتمدة',
  st_rejected: 'مرفوضة',
  st_pending: 'قيد الانتظار',
  st_waiting: 'لم يحن دورها',
  st_blocked: 'لم تُبلَغ',

  orders: 'الطلبات',
  orders_sub: 'أوامر الشراء الصادرة مقابل العروض التي رسّيتها.',
  loading_orders: 'جارٍ تحميل طلباتك…',
  err_load_orders: 'تعذّر تحميل طلباتك.',
  empty_orders_title: 'لا توجد لديك طلبات بعد',
  empty_orders_body:
    'يظهر الطلب هنا بمجرد صدور أمر شراء مقابل عرض رسّيته. لم يصدر أي أمر على هذا الحساب، لذلك لا يوجد ما يُتابَع — لم يُطلب أو يُسلَّم أو يُفوتر أي شيء نيابةً عنك.',
  k_ordered: 'تاريخ الطلب',
  k_expected: 'التسليم المتوقع',
  k_value: 'قيمة الطلب',
  k_status: 'الحالة',
  k_lines: 'البنود',
  k_received: 'المستلم',
  value_unknown: 'غير مُسعّر',
  value_unknown_note: 'لا يحمل هذا الطلب إجماليًا وليست كل البنود مُسعّرة، لذلك لا تُعرض قيمة.',
  received_unknown: 'لا توجد استلامات مسجّلة',
  date_unknown: 'غير محدّد',
  no_lines: 'لا توجد بنود مسجّلة على هذا الطلب.',
  linked_project: 'المشروع',
  linked_rfq: 'من الطلب',
  approved_on: 'تاريخ الاعتماد',
  qty_of: (got: string, ordered: string) => `تم استلام ${got} من ${ordered}`,
};

export function tr<K extends Key>(lang: Lang, key: K): Widen<(typeof EN)[K]> {
  return ((lang === 'ar' ? AR[key] : undefined) ?? EN[key]) as Widen<(typeof EN)[K]>;
}

/** The label for a v_approval_trace step_status. An unknown value is printed as it came. */
export function stepLabel(lang: Lang, status: string): string {
  const map: Record<StepStatus, Key> = {
    approved: 'st_approved',
    rejected: 'st_rejected',
    pending: 'st_pending',
    waiting: 'st_waiting',
    blocked: 'st_blocked',
  };
  const key = map[status as StepStatus];
  return key ? (tr(lang, key) as string) : status;
}

/** Error codes the endpoints actually emit. Anything else is shown verbatim, never dressed up. */
export function errText(lang: Lang, code: string): string {
  if (code === 'unauthorized') return tr(lang, 'err_session') as string;
  return code;
}
