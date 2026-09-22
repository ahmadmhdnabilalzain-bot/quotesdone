// English/Arabic strings for the Projects module. The customer portal is bilingual and decides
// language at the shell level, so these components take `lang` and fall back to English per key.
import type { Lang } from './model';

const EN = {
  projects: 'Projects',
  projects_sub: 'Group your requests under the job they belong to.',
  new_project: 'New project',
  create_project: 'Create project',
  edit_project: 'Edit project',
  save_changes: 'Save changes',
  saving: 'Saving…',
  cancel: 'Cancel',
  back: '← Back to projects',
  loading: 'Loading…',
  loading_projects: 'Loading your projects…',
  loading_project: 'Loading this project…',
  retry: 'Retry',
  err_session: 'Your session has expired. Please sign in again.',
  err_not_found: 'That project no longer exists.',
  err_unexpected: 'Something went wrong at our end. Nothing was changed — please try again.',
  err_load: 'Could not load your projects.',
  err_save: 'Could not save this project.',

  empty_title: 'You have no projects yet',
  empty_body:
    'A project is a container for the requests that belong to one job — a tower, a fit-out, a shipment. Create one, then link your requests to it.',

  no_rfqs_title: 'No requests are linked to this project yet',
  no_rfqs_body:
    'Nothing has been linked, so the figures below that come from requests have nothing to count. Link a request to this project and they will fill in.',

  k_budget: 'Budget',
  k_pipeline: 'Pipeline value',
  k_active_rfqs: 'Active requests',
  k_rfqs: 'Requests',
  k_awarded: 'Awarded',
  k_categories: 'Categories sourced',
  k_suppliers: 'Suppliers awarded',
  k_timeline: 'Time to target date',

  budget_not_set: 'Not set',
  budget_used: 'of budget committed',
  budget_over: 'over budget',
  no_target_date: 'No target date set',
  target_date: 'Target date',
  created: 'Created',
  elapsed_note: 'Elapsed since the project was created. This is time, not work completed.',
  pipeline_note: 'Sum of the expected value of every linked request.',
  categories_note: 'Taken from the trade of each linked request.',
  suppliers_note: 'Suppliers hired on a linked request.',
  no_suppliers_yet: 'No supplier hired yet',
  no_categories_yet: 'No categories yet',
  not_from_rfqs: 'No linked requests',

  f_name: 'Project name',
  f_name_ph: 'e.g. Dubai Marina tower — fit-out',
  f_description: 'Description',
  f_description_ph: 'What is this project, and what will you be buying for it?',
  f_target: 'Target open date',
  f_budget: 'Total budget (AED)',
  f_status: 'Status',
  f_name_required: 'Please give the project a name.',

  st_active: 'Active',
  st_completed: 'Completed',
  st_archived: 'Archived',

  linked_rfqs: 'Linked requests',
  link_rfq: 'Link a request',
  link: 'Link',
  linking: 'Linking…',
  unlink: 'Unlink',
  unlinking: 'Unlinking…',
  choose_rfq: 'Choose a request to link',
  no_linkable: 'No unlinked requests available.',

  th_rfq: 'Request',
  th_category: 'Category',
  th_emirate: 'Emirate',
  th_value: 'Expected value',
  th_status: 'Status',
  th_created: 'Created',
  th_actions: 'Actions',
  rfq_table_caption: 'Requests linked to this project',
  open_rfq: 'Open',
  untitled_rfq: 'Untitled request',
  awarded_badge: 'Awarded',
};

type Key = keyof typeof EN;

const AR: Partial<Record<Key, string>> = {
  projects: 'المشاريع',
  projects_sub: 'رتّب طلباتك حسب المشروع الذي تتبعه.',
  new_project: 'مشروع جديد',
  create_project: 'إنشاء المشروع',
  edit_project: 'تعديل المشروع',
  save_changes: 'حفظ التغييرات',
  saving: 'جارٍ الحفظ…',
  cancel: 'إلغاء',
  back: '→ العودة إلى المشاريع',
  loading: 'جارٍ التحميل…',
  loading_projects: 'جارٍ تحميل مشاريعك…',
  loading_project: 'جارٍ تحميل المشروع…',
  retry: 'إعادة المحاولة',
  err_session: 'انتهت جلستك. يُرجى تسجيل الدخول من جديد.',
  err_not_found: 'هذا المشروع لم يعد موجودًا.',
  err_unexpected: 'حدث خطأ من جهتنا ولم يتغيّر أي شيء. يُرجى المحاولة مرة أخرى.',
  err_load: 'تعذّر تحميل مشاريعك.',
  err_save: 'تعذّر حفظ هذا المشروع.',
  empty_title: 'لا توجد لديك مشاريع بعد',
  empty_body:
    'يجمع المشروع طلباتك لعمل واحد، كبرج أو تجهيز داخلي أو شحنة. أنشئ مشروعًا ثم اربط به طلباتك.',
  no_rfqs_title: 'لا توجد طلبات مرتبطة بهذا المشروع بعد',
  no_rfqs_body:
    'لم يُربط أي طلب بعد، لذا تبقى الأرقام المستمدة من الطلبات أدناه فارغة. اربط طلبًا بهذا المشروع لتظهر القيم.',
  k_budget: 'الميزانية',
  k_pipeline: 'قيمة الطلبات',
  k_active_rfqs: 'الطلبات النشطة',
  k_rfqs: 'الطلبات',
  k_awarded: 'تمت ترسيتها',
  k_categories: 'الفئات المطلوبة',
  k_suppliers: 'المورّدون المتعاقد معهم',
  k_timeline: 'الوقت حتى التاريخ المستهدف',
  budget_not_set: 'غير محددة',
  budget_used: 'من الميزانية مخصّصة لطلبات',
  budget_over: 'تجاوز الميزانية',
  no_target_date: 'لم يُحدَّد تاريخ مستهدف',
  target_date: 'التاريخ المستهدف',
  created: 'تاريخ الإنشاء',
  elapsed_note: 'الوقت المنقضي منذ إنشاء المشروع، وهو مدة زمنية لا نسبة إنجاز.',
  pipeline_note: 'مجموع القيمة المتوقعة لكل طلب مرتبط.',
  categories_note: 'مستمدة من فئة كل طلب مرتبط.',
  suppliers_note: 'المورّدون المتعاقد معهم ضمن الطلبات المرتبطة.',
  no_suppliers_yet: 'لم يُتعاقد مع أي مورّد بعد',
  no_categories_yet: 'لا توجد فئات بعد',
  not_from_rfqs: 'لا توجد طلبات مرتبطة',
  f_name: 'اسم المشروع',
  f_name_ph: 'مثال: برج مرسى دبي — التجهيز الداخلي',
  f_description: 'الوصف',
  f_description_ph: 'ما طبيعة المشروع، وما الذي ستشتريه له؟',
  f_target: 'التاريخ المستهدف للافتتاح',
  f_budget: 'إجمالي الميزانية (درهم)',
  f_status: 'الحالة',
  f_name_required: 'يُرجى إدخال اسم للمشروع.',
  st_active: 'نشط',
  st_completed: 'مكتمل',
  st_archived: 'مؤرشف',
  linked_rfqs: 'الطلبات المرتبطة',
  link_rfq: 'ربط طلب',
  link: 'ربط',
  linking: 'جارٍ الربط…',
  unlink: 'إلغاء الربط',
  unlinking: 'جارٍ إلغاء الربط…',
  choose_rfq: 'اختر طلبًا لربطه',
  no_linkable: 'لا توجد طلبات غير مرتبطة.',
  th_rfq: 'الطلب',
  th_category: 'الفئة',
  th_emirate: 'الإمارة',
  th_value: 'القيمة المتوقعة',
  th_status: 'الحالة',
  th_created: 'تاريخ الإنشاء',
  th_actions: 'إجراءات',
  rfq_table_caption: 'الطلبات المرتبطة بهذا المشروع',
  open_rfq: 'فتح',
  untitled_rfq: 'طلب بلا عنوان',
  awarded_badge: 'تمت الترسية',
};

export const tr = (lang: Lang | undefined, k: Key): string => (lang === 'ar' ? AR[k] || EN[k] : EN[k]);

/**
 * Maps the raw `error` string project_api returns to human text.
 *
 * The fallback used to be `code`, which puts whatever the edge function or Postgres wrote into a
 * customer-facing box — see the note on the same fallback in ../predict/strings.ts, which was
 * measured on screen as `invalid input syntax for type uuid`. Callers keep the raw code in `title`.
 */
export const errText = (lang: Lang | undefined, code: string): string =>
  code === 'unauthorized' ? tr(lang, 'err_session')
    : code === 'not_found' ? tr(lang, 'err_not_found')
    : tr(lang, 'err_unexpected');

export const statusLabel = (lang: Lang | undefined, status: string): string =>
  status === 'completed' ? tr(lang, 'st_completed') : status === 'archived' ? tr(lang, 'st_archived') : tr(lang, 'st_active');
