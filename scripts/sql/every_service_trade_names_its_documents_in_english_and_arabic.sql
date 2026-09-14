-- every_service_trade_names_its_documents_in_english_and_arabic.sql
--
-- WHAT WAS MEASURED (14 Sep 2026, public.category_specs, the 22 public service categories):
--   7 categories carry compliance_checklist = {"list":[{item, notes, authority}]}, 3 or 4 items each:
--     aluminium 3, flooring 3, gypsum 3, landscaping 3, painting 3, security 4, signage 3.
--   15 carry compliance_checklist = NULL:
--     blinds-curtains, cleaning, electrical, general-services-other, hvac, interior-design,
--     kitchens, movers, pest, plumbing, smart-home, solar, swimming-pools, tiling, waterproofing.
--
-- WHAT WAS WRONG:
--   The public service pages show a trade's required documents from this list, and public_site
--   reads item_ar when lang = 'ar'. Every existing item is English only, so the Arabic pages had
--   nothing to show; and 15 of 22 trades show no documents in either language.
--
-- WHAT CHANGES (data only):
--   * The 7 existing lists: item_ar and authority_ar (and notes_ar where notes is not null) are
--     added to every item. item, authority and notes are written back byte-for-byte as measured.
--   * The 15 empty categories get 3-4 items each in the shape {item, item_ar, authority, authority_ar}.
--     Only requirements well established for the trade in the UAE are listed. Where the authority
--     differs by emirate the item names "the relevant emirate authority" rather than guessing one.
--     No permit numbers, fees or invented permit names. general-services-other is generic only.
--   * Each UPDATE sets coalesce(compliance_checklist,'{}') || {'list': <array>}, so any other key
--     already in the object is kept, and re-running writes the identical value (idempotent).
--
-- WHAT IT DELIBERATELY DOES NOT CHANGE:
--   The English wording of any existing item, authority or note; any category outside the 22;
--   no routines, no schema, no grants.
--
-- The guard at the end raises if any of the 22 is left with fewer than 3 items or any item
-- without item_ar, so the whole file rolls back. The file has no DDL, so the exception is safe.

begin;

-- ===================== the 7 existing lists, Arabic added =====================

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Facade/cladding structural & fire compliance","item_ar":"مطابقة الواجهات والكسوة لمتطلبات السلامة الإنشائية والحماية من الحريق","notes":null,"authority":"Dubai Municipality / Civil Defence","authority_ar":"بلدية دبي / الدفاع المدني"},
  {"item":"Approved profiles & thermal break where required","item_ar":"مقاطع ألمنيوم معتمدة مع عازل حراري حيث يُشترط","notes":null,"authority":"ESMA","authority_ar":"وزارة الصناعة والتكنولوجيا المتقدمة"},
  {"item":"Anchoring & wind-load design","item_ar":"تصميم التثبيت وأحمال الرياح","notes":null,"authority":"Dubai Municipality","authority_ar":"بلدية دبي"}
]$j$::jsonb)
 where category = 'aluminium';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Slip-resistance & material standards","item_ar":"مقاومة الانزلاق ومطابقة المواد للمواصفات","notes":null,"authority":"ESMA","authority_ar":"وزارة الصناعة والتكنولوجيا المتقدمة"},
  {"item":"Screed prep & waterproofing for wet areas","item_ar":"تجهيز طبقة التسوية والعزل المائي في المناطق الرطبة","notes":null,"authority":"Dubai Municipality","authority_ar":"بلدية دبي"},
  {"item":"Low-VOC adhesives","item_ar":"مواد لاصقة منخفضة المركبات العضوية المتطايرة","notes":"Green building","notes_ar":"المباني الخضراء","authority":"Dubai Municipality","authority_ar":"بلدية دبي"}
]$j$::jsonb)
 where category = 'flooring';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Fire-rated partition/ceiling systems where required","item_ar":"أنظمة قواطع وأسقف مقاومة للحريق حيث يُشترط","notes":null,"authority":"Dubai Civil Defence","authority_ar":"الدفاع المدني بدبي"},
  {"item":"Approved boards & systems","item_ar":"ألواح وأنظمة جبس معتمدة","notes":null,"authority":"ESMA","authority_ar":"وزارة الصناعة والتكنولوجيا المتقدمة"},
  {"item":"Access panels & MEP coordination","item_ar":"فتحات الصيانة والتنسيق مع الأعمال الكهروميكانيكية","notes":null,"authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'gypsum';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Irrigation & water-use efficiency","item_ar":"أنظمة الري وكفاءة استهلاك المياه","notes":"Estidama where in Abu Dhabi","notes_ar":"استدامة في أبوظبي","authority":"Dubai Municipality","authority_ar":"بلدية دبي"},
  {"item":"Municipality landscaping/soft-scape approvals","item_ar":"موافقات البلدية على أعمال تنسيق الحدائق والزراعة","notes":null,"authority":"Dubai Municipality","authority_ar":"بلدية دبي"},
  {"item":"Approved plants & materials","item_ar":"نباتات ومواد معتمدة","notes":null,"authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'landscaping';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Low-VOC paints","item_ar":"دهانات منخفضة المركبات العضوية المتطايرة","notes":"Green building","notes_ar":"المباني الخضراء","authority":"Dubai Municipality","authority_ar":"بلدية دبي"},
  {"item":"Surface prep & work-at-height safety","item_ar":"تجهيز الأسطح والسلامة عند العمل على ارتفاعات","notes":null,"authority":"OSH","authority_ar":"السلامة والصحة المهنية"},
  {"item":"Approved fire/structural coatings where required","item_ar":"طلاءات معتمدة مقاومة للحريق أو إنشائية حيث يُشترط","notes":null,"authority":"Dubai Civil Defence","authority_ar":"الدفاع المدني بدبي"}
]$j$::jsonb)
 where category = 'painting';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"SIRA design approval & inspection","item_ar":"اعتماد التصميم والتفتيش من مؤسسة تنظيم الصناعة الأمنية","notes":"Required for regulated premises","notes_ar":"مطلوب للمنشآت الخاضعة للتنظيم","authority":"SIRA","authority_ar":"مؤسسة تنظيم الصناعة الأمنية"},
  {"item":"Minimum recording retention (commonly 31 days)","item_ar":"الحد الأدنى لمدة الاحتفاظ بالتسجيلات (عادةً 31 يوماً)","notes":null,"authority":"SIRA","authority_ar":"مؤسسة تنظيم الصناعة الأمنية"},
  {"item":"TDRA type-approved equipment","item_ar":"أجهزة حاصلة على اعتماد الطراز من هيئة تنظيم الاتصالات والحكومة الرقمية","notes":null,"authority":"TDRA","authority_ar":"هيئة تنظيم الاتصالات والحكومة الرقمية"},
  {"item":"Warranty & AMC","item_ar":"شهادة الضمان وعقد الصيانة السنوي","notes":null,"authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'security';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Municipality signage/outdoor advertising permit","item_ar":"تصريح البلدية للوحات الإعلانية والإعلانات الخارجية","notes":null,"authority":"Dubai Municipality","authority_ar":"بلدية دبي"},
  {"item":"Structural & electrical safety","item_ar":"السلامة الإنشائية والكهربائية","notes":null,"authority":"Dubai Municipality / DEWA","authority_ar":"بلدية دبي / هيئة كهرباء ومياه دبي"},
  {"item":"Content & dimension rules","item_ar":"الالتزام بضوابط المحتوى والمقاسات","notes":null,"authority":"Dubai Municipality","authority_ar":"بلدية دبي"}
]$j$::jsonb)
 where category = 'signage';

-- ===================== the 15 empty categories =====================

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Valid trade licence covering blinds and curtains supply and installation","item_ar":"رخصة تجارية سارية تشمل توريد وتركيب الستائر","authority":"the relevant emirate authority","authority_ar":"السلطة المختصة في الإمارة"},
  {"item":"Fire-retardant fabric certificate where required for the premises","item_ar":"شهادة مقاومة الأقمشة للاشتعال حيث تشترطها طبيعة المنشأة","authority":"Civil Defence (the relevant emirate authority)","authority_ar":"الدفاع المدني (السلطة المختصة في الإمارة)"},
  {"item":"Product data sheets for fabrics and motors","item_ar":"نشرات البيانات الفنية للأقمشة والمحركات","authority":null,"authority_ar":null},
  {"item":"Warranty certificate","item_ar":"شهادة الضمان","authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'blinds-curtains';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Valid trade licence covering cleaning services","item_ar":"رخصة تجارية سارية تشمل خدمات التنظيف","authority":"the relevant emirate authority","authority_ar":"السلطة المختصة في الإمارة"},
  {"item":"Staff hold valid UAE residence and work permits","item_ar":"حصول العاملين على إقامات وتصاريح عمل سارية في الدولة","authority":"MoHRE","authority_ar":"وزارة الموارد البشرية والتوطين"},
  {"item":"Material safety data sheets for cleaning chemicals","item_ar":"نشرات بيانات السلامة لمواد التنظيف الكيميائية","authority":null,"authority_ar":null},
  {"item":"Insurance certificate for work on the client site","item_ar":"شهادة تأمين للعمل في موقع العميل","authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'cleaning';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Valid trade licence covering electrical works","item_ar":"رخصة تجارية سارية تشمل الأعمال الكهربائية","authority":"the relevant emirate authority","authority_ar":"السلطة المختصة في الإمارة"},
  {"item":"Contractor approved by DEWA or the relevant emirate utility","item_ar":"مقاول معتمد لدى هيئة كهرباء ومياه دبي أو هيئة الكهرباء المختصة في الإمارة","authority":"DEWA / the relevant emirate authority","authority_ar":"هيئة كهرباء ومياه دبي / السلطة المختصة في الإمارة"},
  {"item":"Utility NOC and connection approval for new or modified supply","item_ar":"شهادة عدم ممانعة وموافقة التوصيل من هيئة الكهرباء للتغذية الجديدة أو المعدّلة","authority":"DEWA / the relevant emirate authority","authority_ar":"هيئة كهرباء ومياه دبي / السلطة المختصة في الإمارة"},
  {"item":"Test and inspection certificate on completion","item_ar":"شهادة الفحص والاختبار عند إنجاز الأعمال","authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'electrical';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Valid trade licence covering the activity","item_ar":"رخصة تجارية سارية تشمل النشاط المطلوب","authority":null,"authority_ar":null},
  {"item":"Insurance certificate where the job is on a client site","item_ar":"شهادة تأمين عندما يُنفّذ العمل في موقع العميل","authority":null,"authority_ar":null},
  {"item":"Method statement for work at height","item_ar":"بيان منهجية العمل للأعمال على ارتفاعات","authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'general-services-other';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Valid trade licence covering air-conditioning works","item_ar":"رخصة تجارية سارية تشمل أعمال التكييف","authority":"the relevant emirate authority","authority_ar":"السلطة المختصة في الإمارة"},
  {"item":"Energy-efficiency label on air-conditioning units","item_ar":"بطاقة كفاءة الطاقة على وحدات التكييف","authority":"ESMA/MoIAT","authority_ar":"وزارة الصناعة والتكنولوجيا المتقدمة"},
  {"item":"Civil Defence approval where fire or smoke-control systems are touched","item_ar":"موافقة الدفاع المدني عند المساس بأنظمة الحريق أو التحكم بالدخان","authority":"Civil Defence (the relevant emirate authority)","authority_ar":"الدفاع المدني (السلطة المختصة في الإمارة)"},
  {"item":"Warranty certificate and equipment data sheets","item_ar":"شهادة الضمان ونشرات البيانات الفنية للمعدات","authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'hvac';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Valid trade licence covering interior design or fit-out","item_ar":"رخصة تجارية سارية تشمل التصميم الداخلي أو أعمال التجهيز","authority":"the relevant emirate authority","authority_ar":"السلطة المختصة في الإمارة"},
  {"item":"Fit-out approval from the building management and the relevant authority","item_ar":"موافقة إدارة المبنى والجهة المختصة على أعمال التجهيز الداخلي","authority":"the relevant emirate authority","authority_ar":"السلطة المختصة في الإمارة"},
  {"item":"Civil Defence approval where fire systems are touched","item_ar":"موافقة الدفاع المدني عند المساس بأنظمة الحريق","authority":"Civil Defence (the relevant emirate authority)","authority_ar":"الدفاع المدني (السلطة المختصة في الإمارة)"},
  {"item":"Material data sheets for finishes and furniture","item_ar":"نشرات البيانات الفنية لمواد التشطيب والأثاث","authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'interior-design';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Valid trade licence covering kitchen supply and installation","item_ar":"رخصة تجارية سارية تشمل توريد وتركيب المطابخ","authority":"the relevant emirate authority","authority_ar":"السلطة المختصة في الإمارة"},
  {"item":"Civil Defence approval where gas or fire-suppression systems are installed or altered","item_ar":"موافقة الدفاع المدني عند تركيب أو تعديل أنظمة الغاز أو إطفاء الحريق","authority":"Civil Defence (the relevant emirate authority)","authority_ar":"الدفاع المدني (السلطة المختصة في الإمارة)"},
  {"item":"Material data sheets for cabinets, worktops and appliances","item_ar":"نشرات البيانات الفنية للخزائن وأسطح العمل والأجهزة","authority":null,"authority_ar":null},
  {"item":"Warranty certificate","item_ar":"شهادة الضمان","authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'kitchens';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Valid trade licence covering moving and removal services","item_ar":"رخصة تجارية سارية تشمل خدمات نقل الأثاث","authority":"the relevant emirate authority","authority_ar":"السلطة المختصة في الإمارة"},
  {"item":"Goods-in-transit insurance certificate","item_ar":"شهادة تأمين على البضائع أثناء النقل","authority":null,"authority_ar":null},
  {"item":"Move-in/move-out permit from the building management where required","item_ar":"تصريح الانتقال من إدارة المبنى حيث يُشترط","authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'movers';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Valid trade licence covering pest control","item_ar":"رخصة تجارية سارية تشمل مكافحة الآفات","authority":"the relevant emirate authority","authority_ar":"السلطة المختصة في الإمارة"},
  {"item":"Municipality pest-control permit","item_ar":"تصريح البلدية لمزاولة مكافحة الآفات","authority":"Dubai Municipality / the relevant emirate authority","authority_ar":"بلدية دبي / السلطة المختصة في الإمارة"},
  {"item":"Only approved, registered pesticides used","item_ar":"استخدام مبيدات معتمدة ومسجلة فقط","authority":"Dubai Municipality / the relevant emirate authority","authority_ar":"بلدية دبي / السلطة المختصة في الإمارة"},
  {"item":"Material safety data sheets and a treatment report","item_ar":"نشرات بيانات السلامة للمبيدات وتقرير المعالجة","authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'pest';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Valid trade licence covering plumbing works","item_ar":"رخصة تجارية سارية تشمل أعمال السباكة","authority":"the relevant emirate authority","authority_ar":"السلطة المختصة في الإمارة"},
  {"item":"Utility approval for new or modified water connections","item_ar":"موافقة هيئة المياه على التوصيلات الجديدة أو المعدّلة","authority":"DEWA / the relevant emirate authority","authority_ar":"هيئة كهرباء ومياه دبي / السلطة المختصة في الإمارة"},
  {"item":"Pressure test record on completion","item_ar":"سجل اختبار الضغط عند إنجاز الأعمال","authority":null,"authority_ar":null},
  {"item":"Material data sheets and warranty certificate","item_ar":"نشرات البيانات الفنية للمواد وشهادة الضمان","authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'plumbing';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Valid trade licence covering smart-home or low-current systems","item_ar":"رخصة تجارية سارية تشمل أنظمة المنازل الذكية أو التيار الخفيف","authority":"the relevant emirate authority","authority_ar":"السلطة المختصة في الإمارة"},
  {"item":"TDRA type-approved wireless devices","item_ar":"أجهزة لاسلكية حاصلة على اعتماد الطراز من هيئة تنظيم الاتصالات والحكومة الرقمية","authority":"TDRA","authority_ar":"هيئة تنظيم الاتصالات والحكومة الرقمية"},
  {"item":"Electrical connections by an approved electrical contractor","item_ar":"تنفيذ التوصيلات الكهربائية بواسطة مقاول كهرباء معتمد","authority":"DEWA / the relevant emirate authority","authority_ar":"هيئة كهرباء ومياه دبي / السلطة المختصة في الإمارة"},
  {"item":"Warranty certificate and device data sheets","item_ar":"شهادة الضمان ونشرات البيانات الفنية للأجهزة","authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'smart-home';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Valid trade licence covering solar installation","item_ar":"رخصة تجارية سارية تشمل تركيب أنظمة الطاقة الشمسية","authority":"the relevant emirate authority","authority_ar":"السلطة المختصة في الإمارة"},
  {"item":"DEWA-enrolled Shams Dubai contractor for rooftop solar in Dubai","item_ar":"مقاول مسجّل لدى هيئة كهرباء ومياه دبي ضمن مبادرة شمس دبي لأنظمة الأسطح في دبي","authority":"DEWA","authority_ar":"هيئة كهرباء ومياه دبي"},
  {"item":"Utility NOC and grid-connection approval","item_ar":"شهادة عدم ممانعة وموافقة الربط بالشبكة من هيئة الكهرباء","authority":"DEWA / the relevant emirate authority","authority_ar":"هيئة كهرباء ومياه دبي / السلطة المختصة في الإمارة"},
  {"item":"Panel and inverter data sheets and warranty certificates","item_ar":"نشرات البيانات الفنية للألواح والعاكس وشهادات الضمان","authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'solar';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Valid trade licence covering swimming-pool construction or maintenance","item_ar":"رخصة تجارية سارية تشمل إنشاء أو صيانة المسابح","authority":"the relevant emirate authority","authority_ar":"السلطة المختصة في الإمارة"},
  {"item":"Building permit for new pool construction","item_ar":"رخصة بناء لإنشاء مسبح جديد","authority":"the relevant emirate authority","authority_ar":"السلطة المختصة في الإمارة"},
  {"item":"Pool safety barrier and water-quality requirements","item_ar":"متطلبات حواجز السلامة وجودة المياه في المسبح","authority":"the relevant emirate authority","authority_ar":"السلطة المختصة في الإمارة"},
  {"item":"Equipment data sheets and warranty certificate","item_ar":"نشرات البيانات الفنية للمعدات وشهادة الضمان","authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'swimming-pools';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Valid trade licence covering tiling works","item_ar":"رخصة تجارية سارية تشمل أعمال التبليط","authority":"the relevant emirate authority","authority_ar":"السلطة المختصة في الإمارة"},
  {"item":"Waterproofing completed in wet areas before tiling","item_ar":"إنجاز العزل المائي في المناطق الرطبة قبل التبليط","authority":null,"authority_ar":null},
  {"item":"Material data sheets for tiles and adhesives","item_ar":"نشرات البيانات الفنية للبلاط والمواد اللاصقة","authority":null,"authority_ar":null},
  {"item":"Warranty certificate","item_ar":"شهادة الضمان","authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'tiling';

update public.category_specs
   set compliance_checklist = coalesce(compliance_checklist, '{}'::jsonb) || jsonb_build_object('list', $j$[
  {"item":"Valid trade licence covering waterproofing works","item_ar":"رخصة تجارية سارية تشمل أعمال العزل المائي","authority":"the relevant emirate authority","authority_ar":"السلطة المختصة في الإمارة"},
  {"item":"Material data sheets for the waterproofing system","item_ar":"نشرات البيانات الفنية لنظام العزل المائي","authority":null,"authority_ar":null},
  {"item":"Flood test record on completion","item_ar":"سجل اختبار الغمر بالماء عند إنجاز الأعمال","authority":null,"authority_ar":null},
  {"item":"Warranty certificate","item_ar":"شهادة الضمان","authority":null,"authority_ar":null}
]$j$::jsonb)
 where category = 'waterproofing';

-- ===================== guard: roll back if anything is incomplete =====================

do $guard$
declare
  v_bad text;
begin
  select string_agg(c.category, ', ' order by c.category) into v_bad
    from unnest(array[
      'aluminium','blinds-curtains','cleaning','electrical','flooring','general-services-other',
      'gypsum','hvac','interior-design','kitchens','landscaping','movers','painting','pest',
      'plumbing','security','signage','smart-home','solar','swimming-pools','tiling','waterproofing'
    ]) as c(category)
    left join public.category_specs s on s.category = c.category
   where s.category is null
      or jsonb_typeof(s.compliance_checklist -> 'list') is distinct from 'array'
      or jsonb_array_length(s.compliance_checklist -> 'list') < 3
      or exists (
           select 1 from jsonb_array_elements(s.compliance_checklist -> 'list') e
            where coalesce(btrim(e ->> 'item_ar'), '') = ''
         );
  if v_bad is not null then
    raise exception 'compliance_checklist incomplete (missing, < 3 items, or an item without item_ar): %', v_bad;
  end if;
end
$guard$;

commit;
