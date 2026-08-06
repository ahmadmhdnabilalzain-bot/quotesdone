// EN/AR copy for the spatial surfaces, in one place so a sentence cannot drift between the 3D
// legend and the panel that explains it.
//
// The empty and caveat strings are the load-bearing ones. Production holds ZERO projects, ZERO
// RFQs and ZERO orders, so on the day this ships EVERY customer sees an empty state — and an empty
// state that implies something happened is the exact defect ("we matched you with suitable
// suppliers", shown to customers who had been matched with nobody) this portal is being repaired
// for. Each string below says what is true and nothing more.
import type { Lang } from './model';

const EN = {
  room_title: 'Project room',
  room_sub: 'Your project, its trades, its suppliers, its documents and its dates in one place.',
  pick_project: 'Choose a project',
  no_projects: 'You have no projects yet. Create one from the Projects screen and link your requests to it — this room is built from what is linked.',
  loading: 'Loading…',
  retry: 'Retry',
  err_load: 'Could not load this project.',

  model_title: '3D project model',
  // The caveat that keeps the viewer honest. Printed on the surface, not only in a comment.
  model_from_meta: 'Levels come from the storey model uploaded on this project.',
  model_from_trades: 'No floor plan or storey model has been uploaded for this project, so these bands are trade packages, not floors. Each block is one real request.',
  model_empty_title: 'No project geometry to show yet',
  model_empty_body: 'Nothing is linked to this project, so there is nothing to place. Link a request to the project and it appears here as a block you can click.',
  model_hint: 'Drag to orbit · scroll to zoom · click a block to open it',
  webgl_missing: 'This browser or device did not give us a 3D context, so the model cannot be drawn. Everything below is the same data as a list.',

  legend: 'Status',
  blocks_one: 'block',
  blocks_many: 'blocks',
  level_one: 'band',
  level_many: 'bands',

  sel_none: 'Select a block to open its request, suppliers, documents, costs and dates.',
  sel_rfqs: 'Request',
  sel_suppliers: 'Suppliers',
  sel_documents: 'Documents',
  sel_costs: 'Costs',
  sel_timeline: 'Timeline',
  sel_open_rfq: 'Open this request',
  quotes_n: 'quotes received',
  quotes_none: 'No quotes have arrived for this request yet.',
  quotes_unknown: 'Quote counts are not loaded on this screen.',
  sup_awarded: 'Awarded supplier',
  sup_hidden: 'Supplier names appear once a quote is revealed.',
  docs_none: 'No documents are filed against this request yet.',
  costs_budget: 'Budget',
  costs_expected: 'Expected value',
  costs_ordered: 'Ordered',
  costs_none: 'No cost has been recorded for this request yet.',
  tl_created: 'Requested',
  tl_ordered: 'Order placed',
  tl_expected: 'Expected on site',
  tl_target: 'Project target open',
  tl_elapsed: 'of the project window has passed',
  tl_no_target: 'This project has no target open date, so there is no window to measure against.',

  chain_title: 'Supply chain map',
  chain_sub: 'Every order you have placed, from the supplier to your site.',
  // The precise, measured statement of what is missing. Do not soften this.
  chain_caveat: 'No table in QuotesDone stores a shipping origin, a destination or a warehouse, so this is a stage map built from each order’s own status and received quantities — not a geographic route. The warehouse hop the specification draws has no data behind it and is not invented here.',
  chain_empty: 'You have no orders yet, so there is nothing in transit. An order appears here when a purchase order is raised against one of your requests.',
  chain_node_supplier: 'Supplier',
  chain_node_transit: 'In transit',
  chain_node_site: 'Your site',
  chain_received: 'received',
  chain_expected: 'Expected',
  chain_lines: 'lines',
  chain_no_qty: 'This order carries no quantities, so how much has arrived cannot be computed.',
};

const AR: typeof EN = {
  room_title: 'غرفة المشروع',
  room_sub: 'مشروعك وتخصصاته ومورّدوه ومستنداته وتواريخه في مكان واحد.',
  pick_project: 'اختر مشروعًا',
  no_projects: 'لا توجد لديك مشاريع بعد. أنشئ مشروعًا من شاشة المشاريع واربط طلباتك به — تُبنى هذه الغرفة مما تم ربطه.',
  loading: 'جارٍ التحميل…',
  retry: 'إعادة المحاولة',
  err_load: 'تعذّر تحميل هذا المشروع.',

  model_title: 'نموذج المشروع ثلاثي الأبعاد',
  model_from_meta: 'الطوابق مأخوذة من نموذج الطوابق المرفوع على هذا المشروع.',
  model_from_trades: 'لم يُرفع مخطط أو نموذج طوابق لهذا المشروع، لذا فإن هذه الشرائح هي حزم تخصصات وليست طوابق. كل مكعّب هو طلب حقيقي واحد.',
  model_empty_title: 'لا توجد بيانات هندسية لعرضها بعد',
  model_empty_body: 'لا يوجد شيء مرتبط بهذا المشروع، لذا لا يوجد ما يُعرض. اربط طلبًا بالمشروع ليظهر هنا كمكعّب يمكنك الضغط عليه.',
  model_hint: 'اسحب للتدوير · مرّر للتكبير · اضغط على مكعّب لفتحه',
  webgl_missing: 'لم يوفّر هذا المتصفح أو الجهاز سياقًا ثلاثي الأبعاد، لذا تعذّر رسم النموذج. كل ما بالأسفل هو نفس البيانات في صورة قائمة.',

  legend: 'الحالة',
  blocks_one: 'مكعّب',
  blocks_many: 'مكعّبات',
  level_one: 'شريحة',
  level_many: 'شرائح',

  sel_none: 'اختر مكعّبًا لفتح طلبه ومورّديه ومستنداته وتكاليفه وتواريخه.',
  sel_rfqs: 'الطلب',
  sel_suppliers: 'المورّدون',
  sel_documents: 'المستندات',
  sel_costs: 'التكاليف',
  sel_timeline: 'الجدول الزمني',
  sel_open_rfq: 'افتح هذا الطلب',
  quotes_n: 'عرض سعر مستلم',
  quotes_none: 'لم تصل أي عروض أسعار لهذا الطلب بعد.',
  quotes_unknown: 'عدد عروض الأسعار غير محمّل في هذه الشاشة.',
  sup_awarded: 'المورّد المتعاقد معه',
  sup_hidden: 'تظهر أسماء المورّدين بعد كشف عرض السعر.',
  docs_none: 'لا توجد مستندات مرتبطة بهذا الطلب بعد.',
  costs_budget: 'الميزانية',
  costs_expected: 'القيمة المتوقعة',
  costs_ordered: 'المطلوب',
  costs_none: 'لم تُسجَّل أي تكلفة لهذا الطلب بعد.',
  tl_created: 'تاريخ الطلب',
  tl_ordered: 'تاريخ إصدار أمر الشراء',
  tl_expected: 'الوصول المتوقع للموقع',
  tl_target: 'الافتتاح المستهدف للمشروع',
  tl_elapsed: 'من مدة المشروع قد انقضت',
  tl_no_target: 'لا يوجد تاريخ افتتاح مستهدف لهذا المشروع، لذا لا توجد مدة تُقاس عليها.',

  chain_title: 'خريطة سلسلة التوريد',
  chain_sub: 'كل أمر شراء أصدرته، من المورّد إلى موقعك.',
  chain_caveat: 'لا يوجد جدول في QuotesDone يخزّن نقطة شحن أو وجهة أو مستودعًا، لذا فهذه خريطة مراحل مبنية على حالة كل أمر شراء والكميات المستلمة فيه — وليست مسارًا جغرافيًا. مرحلة المستودع الواردة في المواصفات لا توجد بيانات تدعمها ولم تُختلق هنا.',
  chain_empty: 'لا توجد لديك أوامر شراء بعد، لذا لا يوجد شيء قيد الشحن. يظهر أمر الشراء هنا عند إصداره مقابل أحد طلباتك.',
  chain_node_supplier: 'المورّد',
  chain_node_transit: 'قيد الشحن',
  chain_node_site: 'موقعك',
  chain_received: 'مستلم',
  chain_expected: 'متوقع',
  chain_lines: 'بند',
  chain_no_qty: 'لا يحمل أمر الشراء هذا كميات، لذا يتعذّر حساب ما وصل منه.',
};

export const tx = (lang: Lang, k: keyof typeof EN): string => (lang === 'ar' ? AR : EN)[k];
