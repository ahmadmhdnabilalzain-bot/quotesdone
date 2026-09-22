// English/Arabic copy for the Orders (§22) surface. The customer portal picks language at the shell
// level, so the component takes `lang` and falls back to English per key.
//
// 14 SEP 2026 — THE APPROVALS COPY IS GONE WITH THE APPROVALS TAB. Founder: "i think its better
// just to remove the approvals tab. cause even if a company signed up, we don't wanna interfere in
// their approvals process and they are treated like normal individuals". This folder keeps its name
// because Orders lives here and Orders was not part of that decision; see ./index.ts.
//
// THE EMPTY STATE IS THE POINT OF THIS FILE. Production has zero orders, so `empty_orders_*` is
// what a real person actually reads today, and it says plainly that nothing has been placed.
import type { Lang } from './model';

const EN = {
  retry: 'Retry',
  err_session: 'Your session has expired. Please sign in again.',

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
  linked_rfq: 'From request',

  /* purchase_orders.status, said in words. The raw enum was rendered on the Orders row and on the
     supply-chain map (CP-I18N-04, 22 Sep 2026); ORDER_TONE in OrdersList.tsx colours these same
     seven values. */
  ost_draft: 'Draft',
  ost_sent: 'Sent',
  ost_open: 'Open',
  ost_approved: 'Approved',
  ost_received: 'Received',
  ost_closed: 'Closed',
  ost_cancelled: 'Cancelled',
  approved_on: 'Approved',
  qty_of: (got: string, ordered: string) => `${got} of ${ordered} received`,
} as const;

type Key = keyof typeof EN;

/**
 * Per-key typing, so a translation can never be a different SHAPE from the English it replaces — a
 * key that takes (got: string, ordered: string) still takes them in Arabic. `as const` also gives
 * every English string a literal type, and a translation is a different string rather than a
 * different key, so the string arms are widened and only the shape is enforced.
 */
type Widen<T> = T extends string ? string : T;
type Translations = { [K in Key]?: Widen<(typeof EN)[K]> };

const AR: Translations = {
  retry: 'إعادة المحاولة',
  err_session: 'انتهت الجلسة. يُرجى تسجيل الدخول مجددًا.',

  orders: 'أوامر الشراء',
  orders_sub: 'أوامر الشراء الصادرة بناءً على العروض التي أرسيتَها.',
  loading_orders: 'جارٍ تحميل أوامر الشراء…',
  err_load_orders: 'تعذّر تحميل أوامر الشراء.',
  empty_orders_title: 'لا توجد لديك أوامر شراء بعد',
  empty_orders_body:
    'يظهر أمر الشراء هنا فور إصداره على عرض أرسيتَه. لم يصدر أي أمر شراء على هذا الحساب حتى الآن، فلا شيء قيد المتابعة، ولم يُطلب أو يُسلَّم أو يُفوتر أي شيء باسمك.',
  k_ordered: 'تاريخ أمر الشراء',
  k_expected: 'التسليم المتوقع',
  k_value: 'قيمة أمر الشراء',
  k_status: 'الحالة',
  k_lines: 'البنود',
  k_received: 'المستلم',
  value_unknown: 'غير مُسعّر',
  value_unknown_note: 'لا يتضمن أمر الشراء هذا مبلغًا إجماليًا، وبعض بنوده غير مُسعّرة، لذا لا تُعرض له قيمة.',
  received_unknown: 'لم يُسجَّل أي استلام',
  date_unknown: 'غير محدّد',
  no_lines: 'لا توجد بنود مسجّلة على أمر الشراء هذا.',
  linked_project: 'المشروع',
  linked_rfq: 'من الطلب',

  ost_draft: 'مسودة',
  ost_sent: 'مُرسَل',
  ost_open: 'مفتوح',
  ost_approved: 'معتمد',
  ost_received: 'مُستلَم',
  ost_closed: 'مغلق',
  ost_cancelled: 'ملغى',
  approved_on: 'تاريخ الاعتماد',
  qty_of: (got: string, ordered: string) => `تم استلام ${got} من ${ordered}`,
};

export function tr<K extends Key>(lang: Lang, key: K): Widen<(typeof EN)[K]> {
  return ((lang === 'ar' ? AR[key] : undefined) ?? EN[key]) as Widen<(typeof EN)[K]>;
}

/** purchase_orders.status in the reader's language; an unknown value is shown as it came. */
export function orderStatus(lang: Lang, status: string | null | undefined): string {
  const k = ('ost_' + String(status || '').toLowerCase()) as Key;
  return (k in EN ? (tr(lang, k) as string) : String(status || ''));
}

/** Error codes the endpoint actually emits. Anything else is shown verbatim, never dressed up. */
export function errText(lang: Lang, code: string): string {
  if (code === 'unauthorized') return tr(lang, 'err_session') as string;
  return code;
}
