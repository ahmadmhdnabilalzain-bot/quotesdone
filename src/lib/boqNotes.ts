// The BOQ card's notes and confidence words, in the customer's language.
//
// MEASURED 22 SEP 2026 (production walk, /ar customer portal, a BOQ read from a PDF): the card's
// "Missing information" read "Read from the PDF text layer only: no drawing geometry was measured…"
// and the confidence column read "medium" — English on an Arabic screen. The readers that fill
// missing_info and assumptions (supabase/functions/drawing_boq/*, _shared/doc_read/*,
// _shared/pdf_measure.ts) write fixed English sentences, and those same sentences travel to suppliers
// with the RFQ, so they stay English at the source. The customer's screen translates them here, one
// pattern per sentence the readers can write. Values inside a sentence (counts, page numbers, file
// names) are carried over as they are.
//
// Prevented by: src/lib/boqNotes.test.mjs, which pulls every sentence those readers can push out of
// their source and fails on any that has no Arabic here — a new reader sentence needs a line below.
type Rule = [RegExp, (m: RegExpMatchArray) => string];
const R = (re: RegExp, f: (m: RegExpMatchArray) => string): Rule => [re, f];

const RULES: Rule[] = [
  // drawing_boq/boq_from_document.ts
  R(/^The drawing was read by OCR in the customer’s browser and by rules on our side; quantities we could not read are shown to the customer as our count to confirm, or marked for the supplier to verify\.$/, () => 'قُرئ المخطط بتقنية التعرّف الضوئي على النصوص في متصفحك وبقواعد من جانبنا؛ والكميات التي تعذّرت قراءتها تُعرض عليك بوصفها عدًّا منّا لتؤكده، أو يُطلب من المورّد التحقق منها.'),
  R(/^The photo was read by OCR in the customer’s browser; OCR can misread digits, so every quantity is marked low confidence\.$/, () => 'قُرئت الصورة بتقنية التعرّف الضوئي على النصوص في متصفحك؛ وقد تُخطئ هذه التقنية في قراءة الأرقام، لذا وُسمت كل كمية بدقة قراءة منخفضة.'),
  R(/^Only the first (.+?) lines were kept\.$/, (m) => `احتُفظ بأول ${m[1]} بندًا فقط.`),
  R(/^No line stating a quantity was found in the document\.$/, () => 'لم يُعثر في المستند على أي بند يذكر كمية.'),
  R(/^Every line is exactly as written in the customer’s document; nothing was re-measured, and no price was read\.$/, () => 'كل بند مطابق تمامًا لما كُتب في مستندك؛ لم يُعَد قياس أي شيء، ولم يُقرأ أي سعر.'),
  // drawing_boq/boq_from_sheet.ts
  R(/^Quantities and units are exactly as written in the customer’s BOQ; nothing was re-measured or recalculated\.$/, () => 'الكميات والوحدات مطابقة تمامًا لما كُتب في جدول كمياتك؛ لم يُعَد قياس أي شيء ولا حسابه.'),
  R(/^No header row naming a quantity column and a description or item column was found in the first 30 rows\.$/, () => 'لم يُعثر في أول 30 صفًا على صف عناوين يحدد عمود الكمية وعمود الوصف أو البند.'),
  R(/^Rate, price and amount columns were not read, so no prices are passed to suppliers\.$/, () => 'لم تُقرأ أعمدة السعر والمبلغ، فلا تُرسل أي أسعار إلى المورّدين.'),
  R(/^A header row was found, but no item lines with a description under it\.$/, () => 'عُثر على صف العناوين، لكن لا توجد تحته بنود تحمل وصفًا.'),
  R(/^(.+?) line\(s\) have no quantity written\.$/, (m) => `عدد البنود التي لا تُذكر لها كمية: ${m[1]}.`),
  R(/^Only the first (.+?) lines were read; the rest of the file was not\.$/, (m) => `قُرئ أول ${m[1]} بندًا فقط، ولم يُقرأ باقي الملف.`),
  // drawing_boq/boq_from_text.ts
  R(/^Read from the PDF text layer only: no drawing geometry was measured and no scale was applied\.$/, () => 'قُرئ من طبقة النص في ملف PDF فقط: لم تُقَس هندسة المخطط ولم يُطبَّق أي مقياس رسم.'),
  R(/^The file is not a PDF we could open \(encrypted, damaged or not a PDF\)\.$/, () => 'تعذّر فتح الملف بصيغة PDF (فهو مشفّر أو تالف أو ليس ملف PDF).'),
  R(/^The PDF has no readable text layer \(a scan, or CAD exported as lines\), so no quantities could be read without the drawing reader\.$/, () => 'لا يحتوي ملف PDF على طبقة نص قابلة للقراءة (فهو مستند ممسوح ضوئيًا، أو ملف CAD مُصدَّر كخطوط)، لذا تعذّرت قراءة الكميات من دون قارئ المخططات.'),
  R(/^Text was found, but no line stated a quantity with a unit or looked like a schedule row\.$/, () => 'عُثر على نص، لكن لم يذكر أي سطر كمية مع وحدتها، ولم يظهر أي سطر كصف في جدول.'),
  R(/^Items are exactly as printed; totals, wastage and anything drawn but not written are not included\.$/, () => 'البنود مطابقة لما طُبع تمامًا؛ ولا تشمل المجاميع ولا نسب الهدر ولا أي شيء مرسوم غير مكتوب.'),
  // drawing_boq/drawing_from_ocr.ts
  R(/^Address tags read as (.+?) sit far above the rest of the loop and were treated as misreads\.$/, (m) => `أرقام العناوين المقروءة ${m[1]} أعلى بكثير من بقية أرقام الدائرة، فعُدّت قراءات خاطئة.`),
  R(/^No legend could be read, so device types are not listed\.$/, () => 'تعذّرت قراءة مفتاح الرموز، لذا لم تُدرج أنواع الأجهزة.'),
  R(/^The sheet is marked not to scale: cable and containment lengths cannot be measured from it\.$/, () => 'اللوحة موسومة بأنها غير مرسومة بمقياس رسم، لذا لا يمكن قياس أطوال الكابلات ومساراتها منها.'),
  R(/^Per-type device counts are our estimate from the drawing and are confirmed with the customer or verified by the supplier; nothing here is a certified take-off\.$/, () => 'أعداد الأجهزة لكل نوع تقدير منّا من المخطط، يؤكده العميل أو يتحقق منه المورّد؛ ولا شيء هنا حصرُ كميات معتمد.'),
  // drawing_boq/drawing_set.ts
  R(/^Duct and pipe LENGTHS are not printed on the drawing and were not measured: those lines carry the sizes and ask for the length at the printed scale\.$/, () => 'أطوال مجاري الهواء والأنابيب غير مطبوعة على المخطط ولم تُقَس: تحمل تلك البنود المقاسات، ويُطلب فيها الطول وفق مقياس الرسم المطبوع.'),
  R(/^Symbols drawn without a tag \(an untagged grille, a valve symbol\) are not counted; only tags, keyed-note bubbles and labelled sizes are\.$/, () => 'الرموز المرسومة بلا وسم (كفتحة تهوية بلا وسم أو رمز صمام) لا تُحتسب؛ وتُحتسب الوسوم وفقاعات الملاحظات المرقّمة والمقاسات الموسومة فقط.'),
  R(/^Schedule sheet\(s\) (.+?) were not read \(their tables are images\); make and model are therefore not on the lines\.$/, (m) => `لم تُقرأ لوحات الجداول ${m[1]} (جداولها صور)، لذا لا تظهر العلامة التجارية والطراز في البنود.`),
  R(/^Lines marked "to confirm" are our own count \(keyed-note bubbles, a letter continuing a series, or a schedule read by OCR\); they are shown to you to confirm before suppliers price them\.$/, () => 'البنود الموسومة «للتأكيد» عدٌّ منّا (من فقاعات الملاحظات المرقّمة، أو حرف يُكمل سلسلة، أو جدول قُرئ بالتعرّف الضوئي)، وتُعرض عليك لتؤكدها قبل أن يسعّرها المورّدون.'),
  R(/^Counted from the drawing set's own text: one unit per equipment tag id; fixtures at their largest count on one plan \(the same fixture is drawn on each system's plan\); air devices by their tag letters\.$/, () => 'حُصرت من نص مجموعة المخططات نفسها: وحدة واحدة لكل رقم وسم لمعدّة؛ والتركيبات بأكبر عدد لها على مخطط واحد (إذ تُرسم التركيبة نفسها على مخطط كل نظام)؛ وفتحات الهواء بحروف وسومها.'),
  // drawing_boq/length_notes.ts (22 Sep 2026, #821: lengths measured from the CAD layers)
  R(/^Duct and pipe LENGTHS are not printed on the drawing and this file carries no CAD layers to measure them from: those lines carry the sizes and ask for the length at the printed scale\.$/, () => 'أطوال مجاري الهواء والأنابيب غير مطبوعة على المخطط، ولا يحتوي هذا الملف على طبقات CAD يمكن قياسها منها: تحمل تلك البنود المقاسات، ويُطلب فيها الطول وفق مقياس الرسم المطبوع.'),
  R(/^Duct and pipe lengths are measured in plan from the drawing's CAD layers at its printed scale; vertical risers and drops are not in plan and are not included\.$/, () => 'قيست أطوال مجاري الهواء والأنابيب في المسقط الأفقي من طبقات CAD في المخطط وفق مقياس الرسم المطبوع؛ ولا تشمل الصواعد والنوازل الرأسية لأنها لا تظهر في المسقط.'),
  R(/^Duct and pipe lengths could not be measured on this upload \(the measuring step did not finish\): those lines carry the sizes and ask for the length at the printed scale\.$/, () => 'تعذّر قياس أطوال مجاري الهواء والأنابيب في هذا الرفع (لم تكتمل خطوة القياس): تحمل تلك البنود المقاسات، ويُطلب فيها الطول وفق مقياس الرسم المطبوع.'),
  R(/^Duct and pipe lengths for this drawing set are being measured in the background; the lines below carry the sizes until the lengths arrive\.$/, () => 'تجري في الخلفية قراءة أطوال مجاري الهواء والأنابيب لمجموعة المخططات هذه؛ وتحمل البنود أدناه المقاسات إلى أن تصل الأطوال.'),
  R(/^Sheet\(s\) (.+?) carry more than (.+?) duct or pipe lines, more than one reading measures; their lengths were not measured and must be taken off by hand\.$/, (m) => `تتضمن اللوحات ${m[1]} أكثر من ${m[2]} خط لمجاري الهواء أو الأنابيب، وهو أكثر مما تقيسه قراءة واحدة؛ لذا لم تُقَس أطوالها ويجب حصرها يدويًا.`),
  // _shared/doc_read/dwg.ts and index.ts (DWG, binary DXF, RVT, DGN)
  R(/^Save the drawing as DXF \(File > Save As > AutoCAD DXF\) or PDF and upload that\.$/, () => 'يُرجى حفظ المخطط بصيغة DXF (ملف > حفظ باسم > AutoCAD DXF) أو PDF ثم رفعه.'),
  R(/^This DWG \((.+?), (.+?) KB\) is larger than the (.+?) KB read directly\.$/, (m) => `ملف DWG هذا (${m[1]}، ${m[2]} كيلوبايت) أكبر من الحد المقروء مباشرةً وهو ${m[3]} كيلوبايت.`),
  R(/^The DWG reader could not run \((.+)\)\.$/, (m) => `تعذّر تشغيل قارئ ملفات DWG (${m[1]}).`),
  R(/^Read from DWG \((.+?)\) by LibreDWG: (.+?) entities\.$/, (m) => `قُرئ من ملف DWG (${m[1]}) بواسطة LibreDWG: ${m[2]} عنصر.`),
  R(/^Not measured \(counted only\): (.+)\.$/, (m) => `لم تُقَس (أُحصيت فقط): ${m[1]}.`),
  // _shared/doc_read/cad.ts: binary DXF (read since 22 Sep 2026)
  R(/^Read from binary DXF: (.+?) group-code pairs\.$/, (m) => `قُرئ من ملف DXF ثنائي: ${m[1]} زوجًا من رموز المجموعات وقيمها.`),
  R(/^The binary DXF has more than (.+?) group-code pairs; reading stopped there, so totals are partial\.$/, (m) => `يتضمن ملف DXF الثنائي أكثر من ${m[1]} زوج من رموز المجموعات؛ وتوقفت القراءة عند هذا الحد، لذا المجاميع جزئية.`),
  // _shared/doc_read/rvt.ts (22 Sep 2026)
  R(/^This Revit file was saved in Revit (.+?)\.$/, (m) => `حُفظ ملف ريفيت هذا بإصدار ريفيت ${m[1]}.`),
  R(/^The Revit version could not be read from this file\.$/, () => 'تعذّرت قراءة إصدار ريفيت من هذا الملف.'),
  R(/^This Revit file is a family \(\.rfa\), not a project model\.$/, () => 'ملف ريفيت هذا عائلة عناصر (.rfa) وليس نموذج مشروع.'),
  R(/^This Revit model is workshared \(part of a team model\)\.$/, () => 'نموذج ريفيت هذا مشترك العمل (جزء من نموذج فريق).'),
  R(/^(.+?) line\(s\) of the drawing's take-off were withheld because they still named a party after redaction; please add them by hand if they are needed\.$/, (m) => `حُجب ${m[1]} من بنود حصر الكميات في المخطط لأنها بقيت تذكر اسم جهة بعد إخفاء البيانات؛ يُرجى إضافتها يدويًا إن لزم.`),
  R(/^A (.+?) x (.+?) pixel preview image was extracted from the file\.$/, (m) => `استُخرجت من الملف صورة معاينة بأبعاد ${m[1]} × ${m[2]} بكسل.`),
  R(/^The building elements and quantities inside a Revit file are not read here\. Please export it from Revit as IFC \(File > Export > IFC, then Modify setup, and on the Property Sets tab tick "Export base quantities" so areas and volumes come through\) and upload the \.ifc file; its quantities are then read directly\.$/, () => 'لا تُقرأ هنا عناصر المبنى وكمياته داخل ملف ريفيت. يُرجى تصديره من ريفيت بصيغة IFC (ملف > تصدير > IFC، ثم «تعديل الإعداد» Modify setup، ومن تبويب «مجموعات الخصائص» Property Sets يُرجى تحديد خيار «تصدير الكميات الأساسية» Export base quantities لتظهر المساحات والأحجام)، ثم رفع ملف ‎.ifc، وعندها تُقرأ كمياته مباشرةً.'),
  R(/^A DWG or DXF export of the plans \(File > Export > CAD Formats\) or a PDF of the drawing sheets can be uploaded instead\.$/, () => 'ويمكن بدلًا من ذلك رفع المساقط مُصدَّرةً بصيغة DWG أو DXF (ملف > تصدير > صيغ CAD) أو رفع لوحات المخطط بصيغة PDF.'),
  // _shared/doc_read/index.ts: DGN (22 Sep 2026)
  R(/^This is a MicroStation DGN V8 file\.$/, () => 'هذا ملف مايكروستيشن DGN بإصدار V8.'),
  R(/^This is a MicroStation DGN V7 \((.+?)\) file\.$/, (m) => `هذا ملف مايكروستيشن DGN بإصدار V7 (${m[1] === '3D' ? 'ثلاثي الأبعاد' : m[1] === '2D' ? 'ثنائي الأبعاد' : m[1]}).`),
  R(/^A MicroStation DGN drawing cannot be read here yet\. Save it from MicroStation as DWG or DXF \(File > Save As\) or print it to PDF and upload that; its quantities are then read directly\.$/, () => 'لا يمكن قراءة مخطط مايكروستيشن (DGN) هنا حاليًا. يُرجى حفظه من مايكروستيشن بصيغة DWG أو DXF (ملف > حفظ باسم) أو طباعته بصيغة PDF ثم رفعه، وعندها تُقرأ كمياته مباشرةً.'),
  R(/^A photo or scan has no text layer; its words are read by OCR in the customer’s browser, or by a vision model when inference is allowed\.$/, () => 'لا تحتوي الصورة أو المستند الممسوح ضوئيًا على طبقة نص؛ فتُقرأ كلماته بتقنية التعرّف الضوئي على النصوص في متصفحك، أو بنموذج رؤية حين يُسمح بذلك.'),
  R(/^The PDF could not be opened \(encrypted, damaged or not a PDF\)\.$/, () => 'تعذّر فتح ملف PDF (فهو مشفّر أو تالف أو ليس ملف PDF).'),
  // _shared/pdf_measure.ts and _shared/doc_read/pdf.ts
  R(/^No readable PDF pages \(not a PDF, encrypted, or no page tree found\); nothing was measured\.$/, () => 'لا توجد صفحات PDF قابلة للقراءة (فالملف ليس PDF، أو مشفّر، أو بلا شجرة صفحات)؛ لم يُقَس شيء.'),
  R(/^Page (.+?) is marked not to scale; nothing was measured\.$/, (m) => `الصفحة ${m[1]} موسومة بأنها بلا مقياس رسم؛ لم يُقَس شيء.`),
  R(/^Page (.+?): no drawing scale found in the page text; nothing was measured\.$/, (m) => `الصفحة ${m[1]}: لم يُعثر على مقياس رسم في نص الصفحة؛ لم يُقَس شيء.`),
  R(/^Page (.+?) prints several scales \((.+?)\); its views cannot be told apart, so nothing was measured\.$/, (m) => `الصفحة ${m[1]} تحمل عدة مقاييس رسم (${m[2]})؛ ويتعذّر التمييز بين مساقطها، لذا لم يُقَس شيء.`),
  R(/^Page (.+?) has more than (.+?) drawing operators; it was not measured rather than measured in part\.$/, (m) => `الصفحة ${m[1]} تتضمن أكثر من ${m[2]} أمر رسم؛ فلم تُقَس بدلًا من قياسها جزئيًا.`),
  R(/^Page (.+?): scale (.+?) found, but no vector paths were drawn on the page itself \(it may be a scanned image or use Form XObjects\)\.$/, (m) => `الصفحة ${m[1]}: عُثر على مقياس الرسم ${m[2]}، لكن لا توجد مسارات متجهية مرسومة على الصفحة نفسها (قد تكون صورة ممسوحة ضوئيًا أو تستخدم Form XObjects).`),
  R(/^The drawing geometry could not be measured\.$/, () => 'تعذّر قياس هندسة المخطط.'),
  // _shared/doc_read/cad.ts
  R(/^The drawing states no unit \(\$INSUNITS (.+?)\); coordinates reach (.+?), so millimetres were assumed\. Check every length and area\.$/, (m) => `لا يذكر المخطط وحدة القياس ($INSUNITS ${m[1]})؛ وتصل الإحداثيات إلى ${m[2]}، لذا افتُرض أنها بالمليمتر. تحقّق من كل طول ومساحة.`),
  R(/^The drawing states no unit \(\$INSUNITS (.+?)\); metres were assumed\. Check every length and area\.$/, (m) => `لا يذكر المخطط وحدة القياس ($INSUNITS ${m[1]})؛ لذا افتُرض أنها بالمتر. تحقّق من كل طول ومساحة.`),
  R(/^(.+?) quantities found; the first (.+?) are kept\.$/, (m) => `عُثر على ${m[1]} كمية؛ واحتُفظ بأول ${m[2]} منها.`),
  R(/^(.+?) anonymous block inserts \(dimensions, hatches, dynamic blocks\) were not counted\.$/, (m) => `لم تُحتسب الكتل غير المسمّاة (الأبعاد والتظليل والكتل الديناميكية)، وعددها ${m[1]}.`),
  R(/^The drawing has more than (.+?) entities; reading stopped there, so totals are partial\.$/, (m) => `يتضمن المخطط أكثر من ${m[1]} عنصر؛ وتوقفت القراءة عند هذا الحد، لذا المجاميع جزئية.`),
  R(/^Lengths are per layer as drawn; block contents are not exploded and viewport scales are not applied\.$/, () => 'الأطوال محسوبة لكل طبقة كما رُسمت؛ ولم تُفكَّك محتويات الكتل ولم تُطبَّق مقاييس نوافذ العرض.'),
  // _shared/doc_read/email.ts and ole.ts
  R(/^attachment (.+?) could not be read: (.+)$/, (m) => `تعذّرت قراءة المرفق ${m[1]}: ${m[2]}`),
  R(/^attachment (.+?) was not read: (.+)$/, (m) => `لم يُقرأ المرفق ${m[1]}: ${m[2]}`),
  R(/^attachment (.+?) is an embedded message or object and was not read$/, (m) => `المرفق ${m[1]} رسالة أو كائن مضمَّن، ولم يُقرأ`),
  R(/^text truncated at (.+?) characters$/, (m) => `اقتُطع النص عند ${m[1]} حرف`),
  R(/^only the first (.+?) MIME parts were read$/, (m) => `قُرئ أول ${m[1]} جزء من أجزاء الرسالة فقط`),
  R(/^multipart nesting deeper than (.+?) levels was not read$/, (m) => `لم يُقرأ ما يتجاوز ${m[1]} مستويات من تداخل أجزاء الرسالة`),
  R(/^(.+?) inline part\(s\) without a filename \(such as embedded images\) were not read$/, (m) => `لم تُقرأ الأجزاء المضمَّنة التي لا تحمل اسم ملف (مثل الصور المضمَّنة)، وعددها ${m[1]}`),
  R(/^the piece table could not be read; text was recovered from printable runs and the reading is approximate \(order and tables may be lost\)$/, () => 'تعذّرت قراءة بنية المستند؛ فاستُعيد النص من المقاطع القابلة للطباعة، والقراءة تقريبية (قد يضيع الترتيب والجداول)'),
  R(/^the message body is stored only as compressed RTF, which is not read$/, () => 'نص الرسالة محفوظ بصيغة RTF مضغوطة فقط، وهي صيغة لا تُقرأ'),
  // _shared/doc_read/gaeb.ts
  R(/^No BoQ items were found in the file\.$/, () => 'لم يُعثر في الملف على أي بنود لجدول الكميات.'),
  R(/^(.+?) items found; the first (.+?) are kept\.$/, (m) => `عُثر على ${m[1]} بند؛ واحتُفظ بأول ${m[2]} منها.`),
  // _shared/doc_read/ifc.ts ("…instances read." or "…instances read; units m, m2.")
  R(/^IFC schema (.+?); (.+?) instances read(.*)\.$/, (m) => {
    const units = m[3].replace(/^; units /, '').trim();
    return `مخطط IFC ‏${m[1]}؛ قُرئ ${m[2]} سجل${units ? `؛ الوحدات ${units}` : ''}.`;
  }),
  R(/^The model contains no building elements this reader counts\.$/, () => 'لا يحتوي النموذج على عناصر بناء يحصيها هذا القارئ.'),
  R(/^The model states no IfcElementQuantity \(exported without base quantities\): element counts only; areas and volumes would need its geometry measured\.$/, () => 'لا يذكر النموذج IfcElementQuantity (صُدِّر من دون الكميات الأساسية): أعداد العناصر فقط؛ وتتطلب المساحات والأحجام قياس هندسته.'),
  R(/^(.+?) malformed instances were skipped\.$/, (m) => `تُركت السجلات التالفة دون قراءة، وعددها ${m[1]}.`),
  R(/^The model has more than (.+?) instances; reading stopped there, so counts are partial\.$/, (m) => `يتضمن النموذج أكثر من ${m[1]} سجل؛ وتوقفت القراءة عند هذا الحد، لذا الأعداد جزئية.`),
  // _shared/doc_read/office.ts, text.ts, zip.ts
  R(/^a table of (.+?) rows stopped at (.+?)$/, (m) => `توقفت قراءة جدول من ${m[1]} صفًا عند الصف ${m[2]}`),
  R(/^(.+?) sheets; only the first 20 were read$/, (m) => `عدد أوراق العمل ${m[1]}؛ قُرئت أول 20 منها فقط`),
  R(/^text stopped at (.+?) characters; the rest of the file was not read$/, (m) => `توقفت قراءة النص عند ${m[1]} حرف، ولم يُقرأ باقي الملف`),
  R(/^table stopped at (.+?) rows$/, (m) => `توقفت قراءة الجدول عند ${m[1]} صفًا`),
  R(/^an RTF table stopped at (.+?) rows$/, (m) => `توقفت قراءة جدول RTF عند ${m[1]} صفًا`),
  R(/^(.+?): (.+?) bytes is over the (.+?) byte entry cap; not read$/, (m) => `${m[1]}: حجمه ${m[2]} بايت ويتجاوز الحد المسموح للملف الواحد (${m[3]} بايت)؛ لم يُقرأ`),
  R(/^(.+?): listed, not read \(no reader supplied\)$/, (m) => `${m[1]}: مُدرج ولم يُقرأ (لا يوجد قارئ لهذا النوع)`),
  // zip.ts's two error lines name a FILE then the reader's own error; anchored on a file name so no
  // other sentence with a colon is ever read as one of them.
  R(/^([^\s:]+\.[A-Za-z0-9]{1,5}): (.+)$/, (m) => `${m[1]}: تعذّرت قراءته (${m[2]})`),
];

/** The Arabic for one reader sentence, or null when there is none. */
export function boqNoteAr(s: string): string | null {
  const t = String(s || '').trim();
  for (const [re, f] of RULES) { const m = t.match(re); if (m) return f(m); }
  return null;
}
/** A note as the customer reads it: Arabic where a rule exists, the sentence as written otherwise. */
export const boqNote = (s: string, lang: string): string => (lang === 'ar' ? boqNoteAr(s) ?? s : s);

const CONF_AR: Record<string, string> = { low: 'منخفضة', medium: 'متوسطة', high: 'عالية' };
/** A confidence value (0..1, 0..100, or low/medium/high) as the column shows it. */
export function confidenceWord(c: unknown, lang: string): string {
  const n = Number(c);
  if (c !== null && c !== '' && Number.isFinite(n)) return Math.round(n <= 1 ? n * 100 : n) + '%';
  if (!c) return '—';
  const w = String(c).toLowerCase();
  return lang === 'ar' ? CONF_AR[w] ?? String(c) : String(c);
}
