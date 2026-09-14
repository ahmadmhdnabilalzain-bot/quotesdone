-- THE INTAKE ASKS EVERY QUESTION IN PLAIN WORDS, IN ENGLISH AND ARABIC.
--
-- Subject: category_specs.fields — a plain-language sibling beside every field's trade question.
-- Owner seat: ceo. Written 14 Sep 2026 from the website audit of the same day (findings 1, 5, 22).
--
-- MEASURED ON PRODUCTION, 14 Sep 2026: category_specs holds 56 categories and 396 fields, 252 of
-- them required. Every field carries `question` written in trade language for our own desks ("Sizes
-- (W x H mm) per unit and quantity (or total m²)?", "Target U-value or thickness?") and nothing a
-- customer who is not technical can answer at a glance. With every model route held there is no model
-- translating them, so the deterministic interview (inquiry_intake/interview.ts) would read them out
-- verbatim. The code recorded the fix as "data, not code: a plain-language sibling for each of its
-- 396 fields". This is that data.
--
-- WHAT IT WRITES. Two attributes inside each field object: question_plain_en and question_plain_ar.
-- `question`, `key`, `required` and `options` are NOT touched — `key` is the contract
-- fn_rfq_required_check scores and dispatch is gated on, so a changed key would silently stop RFQs
-- being sent. The Arabic is Gulf-neutral Modern Standard Arabic in procurement vocabulary: عرض سعر
-- (never اقتباس), طلب / مشروع (never وظيفة).
--
-- MATCHING. 358 fields are matched on (category, key). The other 38 — every field of epoxy-flooring,
-- interior-design, it-networking, kitchens, marble-granite, roofing, smart-home, solar and
-- swimming-pools — carry no key at all, so they are matched on (category, question) exactly as
-- stored.
--
-- THE GUARD at the end is a property, not a count of business rows: after the update, no field may
-- be left without both siblings. If a field was added or a question reworded since 14 Sep, the guard
-- raises, the whole file rolls back, and the new field gets its text written before this is re-run.
-- Idempotent: re-running rewrites the same values.

with plain(category, fkey, fquestion, en, ar) as (values
  ('acrylic','product',null,'What are you after — letters or a sign, a display stand, a box or holder, or plain acrylic sheets?','ما الذي تحتاجه — حروف أو لوحة، أم حامل عرض، أم صندوق أو حامل، أم ألواح أكريليك خام؟'),
  ('acrylic','size',null,'Roughly how big should each piece be?','ما الحجم التقريبي لكل قطعة؟'),
  ('acrylic','quantity',null,'How many pieces do you need?','كم قطعة تحتاج؟'),
  ('acrylic','color',null,'Any colour in mind — clear, frosted, or a particular colour?','هل لديك لون مفضل — شفاف أم مصنفر أم لون محدد؟'),
  ('acrylic','thickness',null,'Do you know how thick it should be? If not, the supplier can suggest one.','هل تعرف السماكة المطلوبة؟ إن لم تكن متأكداً، يمكن للمورد اقتراحها.'),
  ('acrylic','indoor_outdoor',null,'Will it be used inside or outside?','هل سيُستخدم داخل المبنى أم خارجه؟'),
  ('acrylic','illuminated',null,'Should it light up?','هل تريده مضاءً؟'),
  ('acrylic','location',null,'Which emirate should it be delivered to?','إلى أي إمارة سيتم التوصيل؟'),

  ('aluminium','element',null,'What do you need in aluminium — windows, doors, railings, cladding or something else?','ما الأعمال المطلوبة بالألمنيوم — نوافذ أم أبواب أم درابزين أم تكسية أم غير ذلك؟'),
  ('aluminium','dimensions_qty',null,'How many pieces, and roughly how wide and tall is each one?','كم قطعة تحتاج، وما العرض والارتفاع التقريبي لكل قطعة؟'),
  ('aluminium','system_finish',null,'Any preference for the frame colour or finish? The supplier can recommend one.','هل لديك تفضيل للون الإطار أو تشطيبه؟ يمكن للمورد أن يقترح.'),
  ('aluminium','glazing',null,'Will there be glass in it — plain, double, tinted or frosted?','هل سيحتوي على زجاج — عادي أم مزدوج أم ملون أم مصنفر؟'),
  ('aluminium','scope',null,'Should the supplier also install it, or only deliver it?','هل تريد من المورد التوريد والتركيب، أم التوريد فقط؟'),
  ('aluminium','location',null,'What kind of property is it, and which emirate and area?','ما نوع العقار، وفي أي إمارة ومنطقة؟'),
  ('aluminium','timeline',null,'When would you like it done?','متى تريد إنجاز العمل؟'),

  ('av-systems','use',null,'What is the space used for — meetings, a hall, a shop, or a home cinema?','لأي غرض تُستخدم المساحة — اجتماعات أم قاعة أم متجر أم سينما منزلية؟'),
  ('av-systems','rooms',null,'How many rooms need screens or sound, and roughly how many people sit in each?','كم غرفة تحتاج إلى شاشات أو صوت، وكم شخصاً تقريباً في كل منها؟'),
  ('av-systems','display',null,'What kind of screen do you picture — a video wall, one big screen, or a projector?','ما نوع الشاشة التي تتصورها — جدار شاشات، أم شاشة كبيرة واحدة، أم جهاز عرض؟'),
  ('av-systems','audio_pa',null,'What do you need for sound — full speakers and announcements, or just basic speakers?','ما احتياجك من الصوت — نظام سماعات وإعلانات متكامل، أم سماعات بسيطة فقط؟'),
  ('av-systems','video_conf',null,'Do you hold video calls in the room? If so, on Teams, Zoom or both?','هل تعقد اجتماعات مرئية في الغرفة؟ وإن كان كذلك، عبر Teams أم Zoom أم كليهما؟'),
  ('av-systems','control',null,'Would you like to control everything from one touch panel?','هل تريد التحكم بكل شيء من لوحة لمس واحدة؟'),
  ('av-systems','location',null,'What kind of property is it, and which emirate and area?','ما نوع العقار، وفي أي إمارة ومنطقة؟'),

  ('blinds-curtains','type',null,'What would you like — roller blinds, curtains, blackout, or motorised?','ماذا تريد — ستائر رول، أم ستائر قماش، أم معتمة، أم بمحرك؟'),
  ('blinds-curtains','windows',null,'How many windows, and roughly how big is each one?','كم نافذة، وما الحجم التقريبي لكل منها؟'),
  ('blinds-curtains','operation',null,'Should they open by hand or with a remote?','هل تُفتح يدوياً أم بجهاز تحكم؟'),
  ('blinds-curtains','fabric',null,'How much light should they block — fully dark, dimmed, or see-through?','ما مقدار الضوء الذي تريد حجبه — إعتام كامل، أم تخفيف، أم شفافة؟'),
  ('blinds-curtains','measurement',null,'Do you already have exact window sizes, or should the supplier come and measure?','هل لديك مقاسات دقيقة للنوافذ، أم تريد أن يحضر المورد للقياس؟'),
  ('blinds-curtains','scope',null,'Should the supplier also install them, or only deliver them?','هل تريد من المورد التوريد والتركيب، أم التوريد فقط؟'),
  ('blinds-curtains','location',null,'What kind of property is it, and which emirate and area?','ما نوع العقار، وفي أي إمارة ومنطقة؟'),

  ('carpentry','item',null,'What do you need made — doors, a wardrobe, kitchen cabinets, furniture or wall panels?','ما الذي تريد تصنيعه — أبواب أم خزانة ملابس أم خزائن مطبخ أم أثاث أم تكسية جدران؟'),
  ('carpentry','dimensions',null,'How many pieces, and roughly how big?','كم قطعة، وما حجمها التقريبي؟'),
  ('carpentry','material_finish',null,'What should it look like — laminate, wood veneer, solid wood, or painted?','كيف تريد مظهرها — لامينيت أم قشرة خشب أم خشب طبيعي أم مطلية؟'),
  ('carpentry','design',null,'Do you have a design, drawing or photo of what you want?','هل لديك تصميم أو رسم أو صورة لما تريده؟'),
  ('carpentry','location',null,'Which emirate and area is it for?','في أي إمارة ومنطقة؟'),
  ('carpentry','supply_install',null,'Should the supplier also fit it, or only make and deliver it?','هل تريد من المورد التركيب أيضاً، أم التصنيع والتوصيل فقط؟'),
  ('carpentry','timeline',null,'When would you like it ready?','متى تريد أن يكون جاهزاً؟'),

  ('carpentry-joinery','item_type',null,'What do you need made — kitchen cabinets, wardrobes, a TV unit, wall panels, doors or a counter?','ما الذي تريد تصنيعه — خزائن مطبخ أم خزائن ملابس أم وحدة تلفاز أم تكسية جدران أم أبواب أم كاونتر؟'),
  ('carpentry-joinery','quantity_size',null,'How many units, and roughly how big — or how many metres of wall they cover?','كم وحدة، وما حجمها التقريبي — أو كم متراً من الجدار ستغطي؟'),
  ('carpentry-joinery','finish',null,'What finish would you like — laminate, gloss acrylic, painted, or natural wood look?','ما التشطيب الذي تفضله — لامينيت أم أكريليك لامع أم مطلي أم بمظهر الخشب الطبيعي؟'),
  ('carpentry-joinery','carcass_material',null,'Is any of it going in a wet area like a kitchen or bathroom? That decides the board used inside.','هل سيوضع أي جزء منها في مكان رطب كالمطبخ أو الحمام؟ فهذا يحدد نوع الألواح الداخلية.'),
  ('carpentry-joinery','hardware_level',null,'Would you like soft-closing doors and drawers, or standard ones?','هل تفضل أبواباً وأدراجاً بإغلاق هادئ، أم عادية؟'),
  ('carpentry-joinery','scope',null,'Should the supplier make and install it, or only make it?','هل تريد من المورد التصنيع والتركيب، أم التصنيع فقط؟'),
  ('carpentry-joinery','extras',null,'Should it include a worktop, built-in lighting, glass doors or removing the old units?','هل يشمل ذلك سطح عمل، أم إضاءة مدمجة، أم أبواباً زجاجية، أم إزالة الوحدات القديمة؟'),
  ('carpentry-joinery','location_floor',null,'Which emirate and area, and which floor is it on?','في أي إمارة ومنطقة، وفي أي طابق؟'),
  ('carpentry-joinery','timeline',null,'When would you like it finished?','متى تريد إنجازه؟'),

  ('carpets','type',null,'Would you like carpet tiles or one continuous carpet from a roll?','هل تفضل بلاطات سجاد أم سجاداً متصلاً من لفافة؟'),
  ('carpets','area',null,'Roughly how big is the area — in square metres, or the size of the rooms?','ما المساحة التقريبية — بالمتر المربع أو بمقاسات الغرف؟'),
  ('carpets','usage',null,'Is it for a home, an office, or a busy commercial space?','هل هو لمنزل أم مكتب أم مساحة تجارية مزدحمة؟'),
  ('carpets','fibre',null,'Any preference for the material? If not, the supplier can recommend.','هل لديك تفضيل للخامة؟ إن لم يكن، يمكن للمورد أن يقترح.'),
  ('carpets','scope',null,'Should the supplier also lay it, or only deliver it?','هل تريد من المورد التوريد والتركيب، أم التوريد فقط؟'),
  ('carpets','subfloor',null,'What is on the floor now — tiles, bare concrete, or a raised floor?','ما الموجود على الأرضية حالياً — بلاط أم خرسانة أم أرضية مرتفعة؟'),
  ('carpets','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),

  ('cleaning','service_type',null,'What kind of cleaning — a deep clean, move-in or move-out, regular, after building work, or something specific?','ما نوع التنظيف — تنظيف عميق، أم عند الانتقال، أم دوري، أم بعد أعمال البناء، أم شيء محدد؟'),
  ('cleaning','property',null,'What kind of property is it?','ما نوع العقار؟'),
  ('cleaning','size',null,'How big is it — number of bedrooms, or the area in square metres?','ما حجمه — عدد غرف النوم أو المساحة بالمتر المربع؟'),
  ('cleaning','frequency',null,'Is this a one-off, or regular — weekly or monthly?','هل هي مرة واحدة، أم بشكل دوري — أسبوعياً أو شهرياً؟'),
  ('cleaning','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),
  ('cleaning','timeline',null,'Which day and time suits you?','ما اليوم والوقت المناسبان لك؟'),

  ('combined-mep','scope_disciplines',null,'Which do you need — air conditioning, electrical, plumbing, or all three?','ماذا تحتاج — التكييف أم الكهرباء أم السباكة أم الثلاثة معاً؟'),
  ('combined-mep','work_type',null,'Is this a brand-new installation, work in a finished space, an upgrade, or a repair?','هل هو تركيب جديد بالكامل، أم عمل في مساحة مشطبة، أم تحديث، أم إصلاح؟'),
  ('combined-mep','property_type',null,'What kind of property is it?','ما نوع العقار؟'),
  ('combined-mep','area_sqft',null,'Roughly how big is the space?','ما المساحة التقريبية للمكان؟'),
  ('combined-mep','hvac_detail',null,'If air conditioning is included, how many rooms need cooling, or what system is there now?','إذا كان التكييف ضمن الأعمال، كم غرفة تحتاج إلى تبريد، أو ما النظام الموجود حالياً؟'),
  ('combined-mep','authority_approvals',null,'Do you need the supplier to handle the drawings and approvals (electricity, water and Civil Defence), or are they already done?','هل تريد من المورد إعداد المخططات واستخراج الموافقات (الكهرباء والماء والدفاع المدني)، أم أنها جاهزة؟'),
  ('combined-mep','emirate_location',null,'Which emirate and area is the site in?','في أي إمارة ومنطقة يقع الموقع؟'),
  ('combined-mep','access_constraints',null,'Is the place in use during the work, or does the work need to happen at night or on a high floor?','هل المكان مشغول أثناء العمل، أم يلزم العمل ليلاً أو في طابق مرتفع؟'),
  ('combined-mep','timeline',null,'When do you need the work done?','متى تحتاج إلى إنجاز العمل؟'),

  ('commercial-retail-fitout','space_type',null,'What kind of space is it — an office, a shop, a restaurant or café, a clinic, or a warehouse?','ما نوع المساحة — مكتب أم متجر أم مطعم أو مقهى أم عيادة أم مستودع؟'),
  ('commercial-retail-fitout','area_sqm',null,'Roughly how big is it, in square metres?','ما مساحتها التقريبية بالمتر المربع؟'),
  ('commercial-retail-fitout','emirate_building',null,'Which emirate is it in, and is it in a mall, a tower or free zone, or a standalone building?','في أي إمارة تقع، وهل هي في مول أم برج أو منطقة حرة أم مبنى مستقل؟'),
  ('commercial-retail-fitout','current_condition',null,'What does the space look like now — completely bare, basic ceiling and floor already in, or an old fit-out to remove?','ما حالة المساحة الآن — فارغة تماماً، أم فيها سقف وأرضية أساسيان، أم فيها تجهيزات قديمة يجب إزالتها؟'),
  ('commercial-retail-fitout','finish_standard',null,'What level of finish are you aiming for — basic, standard, premium or luxury?','ما مستوى التشطيب الذي تريده — أساسي أم قياسي أم مميز أم فاخر؟'),
  ('commercial-retail-fitout','mep_scope',null,'Does the air conditioning, electrics and plumbing need doing from scratch, changing, or only small touches?','هل يحتاج التكييف والكهرباء والسباكة إلى تنفيذ كامل، أم تعديل، أم لمسات بسيطة فقط؟'),
  ('commercial-retail-fitout','rooms_needed',null,'Which areas do you need — open workspace, offices or meeting rooms, reception, pantry, toilets, storage?','ما المساحات التي تحتاجها — مساحة عمل مفتوحة، مكاتب أو غرف اجتماعات، استقبال، مطبخ صغير، دورات مياه، مخزن؟'),
  ('commercial-retail-fitout','extra_scope',null,'Should the price include furniture, IT cabling, security cameras or signage?','هل يشمل السعر الأثاث، أو تمديدات الشبكة، أو كاميرات المراقبة، أو اللافتات؟'),
  ('commercial-retail-fitout','deadline',null,'Is there a date it must be finished by?','هل هناك موعد يجب الانتهاء قبله؟'),

  ('custom-furniture','item_type',null,'What would you like made — a wardrobe, kitchen, TV unit, bed, table, seating or a vanity?','ما الذي تريد تصنيعه — خزانة ملابس أم مطبخ أم وحدة تلفاز أم سرير أم طاولة أم جلسة أم وحدة مغسلة؟'),
  ('custom-furniture','quantity',null,'How many pieces in total?','كم قطعة إجمالاً؟'),
  ('custom-furniture','fixed_or_freestanding',null,'Will it be fixed to the wall, or free-standing?','هل ستُثبت على الجدار، أم ستكون قائمة بذاتها؟'),
  ('custom-furniture','dimensions',null,'Roughly how wide, tall and deep is the main piece?','ما العرض والارتفاع والعمق التقريبي للقطعة الرئيسية؟'),
  ('custom-furniture','finish',null,'What finish would you like — laminate, painted, wood veneer, solid wood, or high-gloss?','ما التشطيب الذي تفضله — لامينيت أم مطلي أم قشرة خشب أم خشب طبيعي أم لامع؟'),
  ('custom-furniture','hardware',null,'Would you like soft-closing doors and drawers, or standard ones?','هل تفضل أبواباً وأدراجاً بإغلاق هادئ، أم عادية؟'),
  ('custom-furniture','emirate_access',null,'Which emirate is it going to, and is there a lift or any tight access?','إلى أي إمارة سيتم التوصيل، وهل يوجد مصعد أو أي صعوبة في الوصول؟'),
  ('custom-furniture','installation',null,'Should the supplier also install it, or only deliver it?','هل تريد من المورد التركيب أيضاً، أم التوصيل فقط؟'),
  ('custom-furniture','reference',null,'Do you have a photo or drawing of what you want? You can attach it here.','هل لديك صورة أو رسم لما تريده؟ يمكنك إرفاقه هنا.'),

  ('demolition','type',null,'What needs taking down — the whole building, part of it, or only the inside finishes?','ما الذي يلزم هدمه — المبنى بالكامل، أم جزء منه، أم التشطيبات الداخلية فقط؟'),
  ('demolition','property',null,'What kind of property is it?','ما نوع العقار؟'),
  ('demolition','area',null,'Roughly how big is it, and how many floors?','ما مساحته التقريبية، وكم عدد طوابقه؟'),
  ('demolition','disposal',null,'Should the supplier take away the rubble, or will you arrange that?','هل تريد من المورد نقل المخلفات، أم ستتولى ذلك بنفسك؟'),
  ('demolition','utilities',null,'Have the electricity and water been disconnected yet?','هل تم فصل الكهرباء والماء؟'),
  ('demolition','permit',null,'Who will get the demolition permit — the supplier or you?','من سيستخرج تصريح الهدم — المورد أم أنت؟'),
  ('demolition','timeline',null,'When would you like to start?','متى تريد البدء؟'),

  ('electrical','scope',null,'What electrical work do you need — new wiring, lighting, sockets, a new board, or a new or bigger electricity connection?','ما الأعمال الكهربائية المطلوبة — تمديدات جديدة، أم إنارة، أم مقابس، أم لوحة توزيع جديدة، أم توصيل كهرباء جديد أو زيادة الحمل؟'),
  ('electrical','property_area',null,'What kind of property is it, roughly how big, and how many rooms?','ما نوع العقار، وما مساحته التقريبية، وكم عدد غرفه؟'),
  ('electrical','supply_phase',null,'Do you know whether the power supply is single-phase or three-phase? "Not sure" is fine.','هل تعرف إن كان التيار الكهربائي أحادي الطور أم ثلاثي الطور؟ يمكنك الإجابة بـ«لا أعرف».'),
  ('electrical','point_counts',null,'Roughly how many lights and sockets, and any big appliances like a cooker, water heater or AC?','كم عدد الإنارات والمقابس تقريباً، وهل توجد أجهزة كبيرة مثل موقد أو سخان ماء أو مكيف؟'),
  ('electrical','load_additions',null,'Are you adding anything that uses a lot of power — air conditioning, water heaters, a cooker or an EV charger?','هل ستضيف أجهزة تستهلك طاقة عالية — مكيفات، أو سخانات ماء، أو موقد، أو شاحن سيارة كهربائية؟'),
  ('electrical','dewa_works',null,'Do you need anything from the electricity authority — a new connection, more power, or moving the meter?','هل تحتاج إلى أي خدمة من هيئة الكهرباء — توصيل جديد، أم زيادة الحمل، أم نقل العداد؟'),
  ('electrical','concealment',null,'Should the wiring be hidden inside the walls, or run on the surface?','هل تريد التمديدات مخفية داخل الجدران، أم ظاهرة على السطح؟'),
  ('electrical','certification',null,'Do you need an inspection certificate from the electricity authority?','هل تحتاج إلى شهادة فحص من هيئة الكهرباء؟'),
  ('electrical','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),
  ('electrical','timeline',null,'When would you like it done?','متى تريد إنجاز العمل؟'),

  ('elevators','type',null,'What kind of lift — for people, a home lift, for goods, or a glass lift?','ما نوع المصعد — للركاب، أم منزلي، أم للبضائع، أم زجاجي؟'),
  ('elevators','stops',null,'How many floors does it need to stop at?','كم طابقاً يجب أن يتوقف عندها؟'),
  ('elevators','capacity',null,'Roughly how many people or how much weight should it carry?','كم شخصاً أو ما الوزن التقريبي الذي يجب أن يحمله؟'),
  ('elevators','new_mod',null,'Is this a new lift, or replacing an old one?','هل هو مصعد جديد، أم استبدال لمصعد قديم؟'),
  ('elevators','mrl',null,'Is there space for a machine room above the shaft? "Not sure" is fine.','هل توجد مساحة لغرفة محركات فوق البئر؟ يمكنك الإجابة بـ«لا أعرف».'),
  ('elevators','brand',null,'Would you like a premium brand, mid-range, or no preference?','هل تفضل علامة تجارية فاخرة، أم متوسطة، أم لا تفضيل لديك؟'),
  ('elevators','amc',null,'Would you like a yearly maintenance contract included?','هل تريد تضمين عقد صيانة سنوي؟'),

  ('engineering-and-architectural-consultancies','service',null,'What do you need from the consultant — design, supervision on site, or both? Or a study or inspection?','ما الذي تحتاجه من الاستشاري — التصميم، أم الإشراف في الموقع، أم كليهما؟ أم دراسة أو فحصاً؟'),
  ('engineering-and-architectural-consultancies','project_type',null,'What are you building — a villa, a residential building, offices, a shop, a warehouse, or something else?','ما الذي تبنيه — فيلا أم مبنى سكني أم مكاتب أم متجراً أم مستودعاً أم غير ذلك؟'),
  ('engineering-and-architectural-consultancies','location',null,'Where is the plot — which emirate and community? The plot number helps if you have it.','أين تقع قطعة الأرض — في أي إمارة ومنطقة؟ ويفيد رقم القطعة إن كان متوفراً.'),
  ('engineering-and-architectural-consultancies','jurisdiction',null,'Which authority is the plot under — the municipality, a free zone or development authority? "Not sure" is fine.','لأي جهة تتبع قطعة الأرض — البلدية أم منطقة حرة أم سلطة تطوير؟ يمكنك الإجابة بـ«لا أعرف».'),
  ('engineering-and-architectural-consultancies','plot_gfa',null,'How big is the plot, how much do you want to build, and how many floors?','ما مساحة قطعة الأرض، وما المساحة التي تريد بناءها، وكم عدد الطوابق؟'),
  ('engineering-and-architectural-consultancies','documents',null,'What papers do you already have — the plot plan, a land survey, old drawings, or nothing yet?','ما المستندات المتوفرة لديك — مخطط الأرض، أم رفع مساحي، أم مخططات قديمة، أم لا شيء حتى الآن؟'),
  ('engineering-and-architectural-consultancies','authority_scope',null,'Should the consultant also submit the drawings to the authorities and follow up the approvals?','هل تريد أن يتولى الاستشاري تقديم المخططات للجهات المختصة ومتابعة الموافقات؟'),
  ('engineering-and-architectural-consultancies','supervision',null,'Do you want someone on site full-time, occasional visits, or no supervision?','هل تريد مشرفاً في الموقع بدوام كامل، أم زيارات دورية، أم لا تحتاج إلى إشراف؟'),
  ('engineering-and-architectural-consultancies','timeline',null,'When do you hope to have the permit, and when do you want to start building?','متى تأمل الحصول على التصريح، ومتى تريد بدء البناء؟'),
  ('engineering-and-architectural-consultancies','budget',null,'Do you have a rough budget for the construction? This is optional.','هل لديك ميزانية تقريبية للبناء؟ هذا اختياري.'),

  ('epoxy-flooring',null,'Area (sqm)','Roughly how big is the floor, in square metres?','ما المساحة التقريبية للأرضية بالمتر المربع؟'),
  ('epoxy-flooring',null,'Location (warehouse, garage, kitchen, gym)','Where is the floor — a warehouse, garage, kitchen, gym, or somewhere else?','أين تقع الأرضية — مستودع أم مرآب أم مطبخ أم صالة رياضية أم مكان آخر؟'),
  ('epoxy-flooring',null,'Existing floor condition','What is the floor like now — bare concrete, tiles, or damaged?','ما حالة الأرضية الآن — خرسانة عارية أم بلاط أم بها تلف؟'),
  ('epoxy-flooring',null,'Finish (matte, gloss, anti-slip)','Would you like it shiny, matte, or non-slip?','هل تريدها لامعة أم مطفأة أم مانعة للانزلاق؟'),
  ('epoxy-flooring',null,'Emirate / area','Which emirate and area?','في أي إمارة ومنطقة؟'),

  ('facade-cleaning','height',null,'How tall is the building — how many floors?','ما ارتفاع المبنى — كم عدد طوابقه؟'),
  ('facade-cleaning','facade_type',null,'What is the outside of the building — glass, panels or stone, or painted walls?','ما نوع واجهة المبنى — زجاج أم ألواح أو حجر أم جدران مطلية؟'),
  ('facade-cleaning','access',null,'Any preference for how the cleaners reach it — ropes or a hanging platform?','هل لديك تفضيل لطريقة الوصول — بالحبال أم بمنصة معلقة؟'),
  ('facade-cleaning','bmu',null,'Does the building already have a cleaning cradle on the roof? "Not sure" is fine.','هل يوجد في المبنى منصة تنظيف معلقة مثبتة على السطح؟ يمكنك الإجابة بـ«لا أعرف».'),
  ('facade-cleaning','frequency',null,'Is this a one-off, or regular — every few months or a yearly contract?','هل هي مرة واحدة، أم بشكل دوري — كل بضعة أشهر أو بعقد سنوي؟'),
  ('facade-cleaning','area',null,'Do you know roughly how big the outside walls are?','هل تعرف المساحة التقريبية للواجهات الخارجية؟'),
  ('facade-cleaning','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),

  ('fitout','space',null,'What kind of space is it — an office, a shop, a home, a restaurant, a clinic, or a warehouse?','ما نوع المساحة — مكتب أم متجر أم منزل أم مطعم أم عيادة أم مستودع؟'),
  ('fitout','area_sqm',null,'Roughly how big is it, in square metres?','ما مساحتها التقريبية بالمتر المربع؟'),
  ('fitout','scope',null,'Do you want everything done start to finish, only part of it, or design and build together?','هل تريد تنفيذ كل شيء من البداية إلى النهاية، أم جزءاً منه فقط، أم التصميم والتنفيذ معاً؟'),
  ('fitout','design',null,'Do you already have drawings, or do you need a design?','هل لديك مخططات جاهزة، أم تحتاج إلى تصميم؟'),
  ('fitout','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),
  ('fitout','timeline',null,'When would you like it finished?','متى تريد إنجازه؟'),
  ('fitout','budget',null,'Do you have a budget in mind? This is optional.','هل لديك ميزانية في ذهنك؟ هذا اختياري.'),

  ('flooring','floor_type',null,'What kind of floor would you like — SPC or vinyl, parquet or laminate, tiles, marble, epoxy or carpet?','ما نوع الأرضية التي تريدها — SPC أو فينيل، أم باركيه أو لامينيت، أم بلاط، أم رخام، أم إيبوكسي، أم سجاد؟'),
  ('flooring','area_sqm',null,'Roughly how big is the area — in square metres, or the size of the rooms?','ما المساحة التقريبية — بالمتر المربع أو بمقاسات الغرف؟'),
  ('flooring','areas',null,'Which rooms is it for?','لأي غرف؟'),
  ('flooring','supply_install',null,'Should the supplier also lay it, or only deliver it?','هل تريد من المورد التوريد والتركيب، أم التوريد فقط؟'),
  ('flooring','removal_levelling',null,'Is there an old floor to remove, or is the floor uneven?','هل توجد أرضية قديمة يجب إزالتها، أم أن الأرضية غير مستوية؟'),
  ('flooring','thickness_wear',null,'For vinyl or SPC, any preference on thickness? The supplier can recommend.','بالنسبة للفينيل أو SPC، هل لديك تفضيل للسماكة؟ يمكن للمورد أن يقترح.'),
  ('flooring','color_finish',null,'Any colour or look you like?','هل لديك لون أو مظهر تفضله؟'),
  ('flooring','skirting',null,'Do you want matching skirting along the walls?','هل تريد وزرات مطابقة على طول الجدران؟'),
  ('flooring','timeline',null,'When would you like to start, and will the place be empty?','متى تريد البدء، وهل سيكون المكان خالياً؟'),

  ('garage-doors','type',null,'What would you like — a rolling shutter, a garage door, a grille, or a fire-rated shutter?','ماذا تريد — باباً دوّاراً (رول)، أم باب مرآب، أم شبكاً، أم باباً مقاوماً للحريق؟'),
  ('garage-doors','dimensions',null,'Roughly how wide and tall is the opening?','ما العرض والارتفاع التقريبي للفتحة؟'),
  ('garage-doors','operation',null,'Should it open by hand, or with a motor and remote?','هل يُفتح يدوياً، أم بمحرك وجهاز تحكم؟'),
  ('garage-doors','material',null,'Any preference for the material — steel, aluminium or stainless steel?','هل لديك تفضيل للخامة — حديد أم ألمنيوم أم ستانلس ستيل؟'),
  ('garage-doors','units',null,'How many doors?','كم باباً؟'),
  ('garage-doors','scope',null,'Should the supplier also install it, or only deliver it?','هل تريد من المورد التوريد والتركيب، أم التوريد فقط؟'),
  ('garage-doors','location',null,'What kind of property is it, and which emirate and area?','ما نوع العقار، وفي أي إمارة ومنطقة؟'),

  ('general','describe',null,'Tell me in your own words what you need done.','صف لنا بكلماتك ما الذي تحتاج إنجازه.'),
  ('general','property',null,'What kind of property is it, and which emirate?','ما نوع العقار، وفي أي إمارة؟'),
  ('general','scope',null,'Roughly how big is the job — the area, or how many of something?','ما حجم العمل تقريباً — المساحة أو العدد؟'),
  ('general','supply_install',null,'Should the supplier provide the materials, do the work, or both?','هل تريد من المورد توفير المواد، أم تنفيذ العمل، أم كليهما؟'),
  ('general','timeline',null,'When would you like to start?','متى تريد البدء؟'),

  ('general-building-contracting','project_type',null,'What are you building — a villa, a residential or commercial building, a warehouse, or an extension?','ما الذي تبنيه — فيلا أم مبنى سكني أو تجاري أم مستودعاً أم توسعة؟'),
  ('general-building-contracting','location',null,'Where is the plot — which emirate and community? The plot number helps if you have it.','أين تقع قطعة الأرض — في أي إمارة ومنطقة؟ ويفيد رقم القطعة إن كان متوفراً.'),
  ('general-building-contracting','jurisdiction',null,'Which authority is the plot under — the municipality, a free zone or development authority? "Not sure" is fine.','لأي جهة تتبع قطعة الأرض — البلدية أم منطقة حرة أم سلطة تطوير؟ يمكنك الإجابة بـ«لا أعرف».'),
  ('general-building-contracting','bua_sqm',null,'Roughly how much floor area will be built, in square metres?','ما مساحة البناء التقريبية بالمتر المربع؟'),
  ('general-building-contracting','floors',null,'How many floors?','كم عدد الطوابق؟'),
  ('general-building-contracting','drawings',null,'Where are the drawings — approved with a permit, submitted, only a concept, or nothing yet?','ما وضع المخططات — معتمدة مع تصريح، أم مقدمة للاعتماد، أم تصور مبدئي فقط، أم لا شيء بعد؟'),
  ('general-building-contracting','scope',null,'Do you need build only, design and build, or everything handed over ready to use?','هل تحتاج إلى التنفيذ فقط، أم التصميم والتنفيذ، أم تسليم المشروع جاهزاً بالكامل؟'),
  ('general-building-contracting','mep_scope',null,'Should the contractor also do the air conditioning, electrics and plumbing?','هل تريد أن ينفذ المقاول أعمال التكييف والكهرباء والسباكة أيضاً؟'),
  ('general-building-contracting','timeline',null,'When do you want to start, and when should it be finished?','متى تريد البدء، ومتى يجب الانتهاء؟'),
  ('general-building-contracting','budget',null,'Do you have a budget in mind? This is optional.','هل لديك ميزانية في ذهنك؟ هذا اختياري.'),

  ('general-services-other','task_description',null,'Tell me in your own words what you need done.','صف لنا بكلماتك ما الذي تحتاج إنجازه.'),
  ('general-services-other','emirate',null,'Which emirate and area is the job in?','في أي إمارة ومنطقة يقع العمل؟'),
  ('general-services-other','property_type',null,'What kind of property is it?','ما نوع العقار؟'),
  ('general-services-other','job_frequency',null,'Is this a one-off job, or something regular?','هل هو عمل لمرة واحدة، أم عمل دوري؟'),
  ('general-services-other','materials_supply',null,'Should the supplier bring the materials, or will you provide them?','هل يوفر المورد المواد، أم ستوفرها أنت؟'),
  ('general-services-other','quantity_size',null,'Roughly how big is the job, or how many of something?','ما حجم العمل تقريباً، أو كم العدد؟'),
  ('general-services-other','access',null,'Anything the supplier should know about getting in — a high floor, no lift, no parking, or a building permit?','هل هناك ما يجب أن يعرفه المورد عن الوصول — طابق مرتفع، أو عدم وجود مصعد أو مواقف، أو تصريح من المبنى؟'),
  ('general-services-other','timing',null,'When do you need it done?','متى تحتاج إلى إنجازه؟'),
  ('general-services-other','waste_removal',null,'Will there be old items or waste to take away?','هل توجد أغراض قديمة أو مخلفات يلزم نقلها؟'),

  ('generators','application',null,'What is the generator for — backup when the power cuts, running all the time, or temporary site power?','لأي غرض المولد — احتياطي عند انقطاع الكهرباء، أم تشغيل مستمر، أم كهرباء مؤقتة للموقع؟'),
  ('generators','rating',null,'Do you know how much power you need? If not, tell me what it must run and the supplier will size it.','هل تعرف القدرة المطلوبة؟ إن لم تكن تعرف، أخبرنا بما يجب تشغيله وسيحدد المورد الحجم.'),
  ('generators','enclosure',null,'Should it be in a quiet soundproof box, open, or in a container?','هل تريده داخل غطاء عازل للصوت، أم مكشوفاً، أم داخل حاوية؟'),
  ('generators','ats',null,'Should it switch on by itself when the power goes off?','هل تريده أن يعمل تلقائياً عند انقطاع الكهرباء؟'),
  ('generators','fuel',null,'How long should it run on one tank of fuel?','كم ساعة يجب أن يعمل بخزان وقود واحد؟'),
  ('generators','scope',null,'Should the supplier only deliver it, install it, or also maintain it afterwards?','هل تريد من المورد التوريد فقط، أم التركيب، أم الصيانة بعد ذلك أيضاً؟'),
  ('generators','location',null,'What kind of property is it, and which emirate and area?','ما نوع العقار، وفي أي إمارة ومنطقة؟'),

  ('glass','element',null,'What do you need in glass — a glass front, windows, a partition, a railing, a skylight or glass doors?','ما الأعمال الزجاجية المطلوبة — واجهة زجاجية، أم نوافذ، أم قاطع، أم درابزين، أم فتحة سقفية، أم أبواب زجاجية؟'),
  ('glass','dimensions_qty',null,'How many pieces, roughly how big is each, and which floor is it on?','كم قطعة، وما الحجم التقريبي لكل منها، وفي أي طابق؟'),
  ('glass','glazing_performance',null,'What kind of glass — plain, double for heat and noise, safety glass, or should the supplier recommend?','ما نوع الزجاج — عادي، أم مزدوج للعزل الحراري والصوتي، أم زجاج أمان، أم يقترح المورد؟'),
  ('glass','aluminium_system',null,'Any preferred frame brand? If not, the supplier can recommend.','هل لديك علامة تجارية مفضلة للإطارات؟ إن لم يكن، يمكن للمورد أن يقترح.'),
  ('glass','finish',null,'Any colour or finish for the frames?','هل لديك لون أو تشطيب للإطارات؟'),
  ('glass','safety_context',null,'Where will the glass be — near a door, as a railing, in a bathroom, overhead, or a normal wall or window?','أين سيكون الزجاج — قرب باب، أم كدرابزين، أم في حمام، أم في السقف، أم في جدار أو نافذة عادية؟'),
  ('glass','scope',null,'Should the supplier also install it, or only deliver it?','هل تريد من المورد التوريد والتركيب، أم التوريد فقط؟'),
  ('glass','location',null,'What kind of property is it, which emirate and area, and is it hard to reach (high up or needing a crane)?','ما نوع العقار، وفي أي إمارة ومنطقة، وهل يصعب الوصول إليه (مرتفع أو يحتاج إلى رافعة)؟'),
  ('glass','timeline',null,'When would you like it done?','متى تريد إنجاز العمل؟'),

  ('gypsum','work',null,'What do you need — a false ceiling, a gypsum wall, plastering, or decorative work?','ماذا تحتاج — سقفاً معلقاً، أم جداراً من الجبس، أم لياسة، أم أعمالاً زخرفية؟'),
  ('gypsum','area_sqm',null,'Roughly how big is the area, in square metres?','ما المساحة التقريبية بالمتر المربع؟'),
  ('gypsum','design',null,'Plain, with hidden lighting, or decorative?','عادي، أم بإضاءة مخفية، أم زخرفي؟'),
  ('gypsum','paint_included',null,'Should painting be included?','هل تريد تضمين الدهان؟'),
  ('gypsum','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),
  ('gypsum','timeline',null,'When would you like it done?','متى تريد إنجاز العمل؟'),

  ('hvac','system_type',null,'What kind of air conditioning — wall split units, hidden ducted, ceiling cassettes, a central system, or should the supplier survey and advise?','ما نوع التكييف — وحدات سبليت جدارية، أم مخفية بمجارٍ، أم كاسيت سقفي، أم نظام مركزي، أم يعاين المورد وينصح؟'),
  ('hvac','application_area',null,'What is the space used for, and roughly how big is it?','لأي غرض تُستخدم المساحة، وما حجمها التقريبي؟'),
  ('hvac','new_or_replace',null,'Is this a new installation, replacing old units, adding more, or a repair?','هل هو تركيب جديد، أم استبدال وحدات قديمة، أم إضافة، أم إصلاح؟'),
  ('hvac','load_basis',null,'Do you have engineering drawings for the cooling, or should the supplier work out the size?','هل لديك مخططات هندسية للتبريد، أم يحدد المورد الحجم المطلوب؟'),
  ('hvac','brand_tier',null,'Would you like a premium brand, mid-range, economy, or the best value?','هل تفضل علامة فاخرة، أم متوسطة، أم اقتصادية، أم الأفضل قيمة؟'),
  ('hvac','electrical_supply',null,'Do you know whether the power supply is single-phase or three-phase? "Not sure" is fine.','هل تعرف إن كان التيار الكهربائي أحادي الطور أم ثلاثي الطور؟ يمكنك الإجابة بـ«لا أعرف».'),
  ('hvac','scope',null,'Should the supplier only deliver, install, or do everything including ducts and testing?','هل تريد من المورد التوريد فقط، أم التركيب، أم تنفيذ كل شيء بما في ذلك المجاري والاختبار؟'),
  ('hvac','amc',null,'Would you like a yearly maintenance contract included?','هل تريد تضمين عقد صيانة سنوي؟'),
  ('hvac','location',null,'Which emirate and area, which floor, and where can the outdoor unit go — roof, wall or ground?','في أي إمارة ومنطقة، وفي أي طابق، وأين يمكن وضع الوحدة الخارجية — على السطح أم الجدار أم الأرض؟'),
  ('hvac','timeline',null,'When do you need it done?','متى تحتاج إلى إنجازه؟'),

  ('insulation','location',null,'Where does the insulation go — outside walls, the roof, air ducts, or several places?','أين سيوضع العزل — الجدران الخارجية، أم السطح، أم مجاري الهواء، أم عدة أماكن؟'),
  ('insulation','area',null,'Roughly how big is the area to insulate?','ما المساحة التقريبية المطلوب عزلها؟'),
  ('insulation','target',null,'Has an engineer specified a thickness, or should it just meet the municipality minimum? "Not sure" is fine.','هل حدد مهندس سماكة معينة، أم يكفي الحد الأدنى المطلوب من البلدية؟ يمكنك الإجابة بـ«لا أعرف».'),
  ('insulation','material',null,'Any preference for the material? If not, the supplier can recommend.','هل لديك تفضيل للخامة؟ إن لم يكن، يمكن للمورد أن يقترح.'),
  ('insulation','fire',null,'Does it need to be fire-resistant?','هل يجب أن يكون مقاوماً للحريق؟'),
  ('insulation','new_retro',null,'Is this a new building, or an existing one?','هل هو مبنى جديد، أم مبنى قائم؟'),
  ('insulation','location_area',null,'What kind of building is it, and which emirate and area?','ما نوع المبنى، وفي أي إمارة ومنطقة؟'),

  ('interior-design',null,'Space type (villa, apartment, office, retail)','What kind of space is it — a villa, apartment, office or shop?','ما نوع المساحة — فيلا أم شقة أم مكتب أم متجر؟'),
  ('interior-design',null,'Approx area (sqft)','Roughly how big is it?','ما مساحتها التقريبية؟'),
  ('interior-design',null,'Design only, or design + build?','Do you want the design only, or the design and the work done too?','هل تريد التصميم فقط، أم التصميم والتنفيذ معاً؟'),
  ('interior-design',null,'Style / references','Is there a style you like? Photos help a lot.','هل هناك طراز تفضله؟ الصور تساعد كثيراً.'),
  ('interior-design',null,'Emirate / area','Which emirate and area?','في أي إمارة ومنطقة؟'),

  ('it-networking',null,'Service (structured cabling, WiFi, servers, CCTV network)','What do you need — network cabling, Wi-Fi, a server setup, or a camera network?','ماذا تحتاج — تمديدات شبكة، أم واي فاي، أم إعداد خوادم، أم شبكة كاميرات؟'),
  ('it-networking',null,'Number of points / approx area','How many network points, or roughly how big is the space?','كم نقطة شبكة، أو ما المساحة التقريبية؟'),
  ('it-networking',null,'Property type','What kind of property is it?','ما نوع العقار؟'),
  ('it-networking',null,'Emirate / area','Which emirate and area?','في أي إمارة ومنطقة؟'),
  ('it-networking',null,'Timeline','When would you like it done?','متى تريد إنجاز العمل؟'),

  ('job-shop-manufacturing','process',null,'What kind of making do you need — moulding, sheet metal, machining, cutting, coating or welding? Or should the supplier advise?','ما نوع التصنيع المطلوب — قولبة، أم صفائح معدنية، أم تشغيل آلي، أم قص، أم طلاء، أم لحام؟ أم يقترح المورد؟'),
  ('job-shop-manufacturing','part_description',null,'What is the part, and what does it do?','ما هي القطعة، وما وظيفتها؟'),
  ('job-shop-manufacturing','drawings',null,'What do you have to show the part — drawings, a 3D file, a sample or a photo?','ما الذي لديك لتوضيح القطعة — رسومات، أم ملف ثلاثي الأبعاد، أم عينة، أم صورة؟'),
  ('job-shop-manufacturing','material',null,'What should it be made of? A rough answer like "stainless steel" or "plastic" is fine.','من أي مادة يجب أن تُصنع؟ تكفي إجابة تقريبية مثل «ستانلس ستيل» أو «بلاستيك».'),
  ('job-shop-manufacturing','quantity',null,'How many do you need now, and roughly how many a year after that?','كم قطعة تحتاج الآن، وكم تقريباً في السنة بعد ذلك؟'),
  ('job-shop-manufacturing','tolerance',null,'Does it need to fit very precisely with other parts, or is standard accuracy fine?','هل يجب أن تتطابق بدقة عالية مع قطع أخرى، أم تكفي الدقة القياسية؟'),
  ('job-shop-manufacturing','finish',null,'Does it need a coating or colour?','هل تحتاج إلى طلاء أو لون؟'),
  ('job-shop-manufacturing','certification',null,'Do you need any test reports or certificates with it?','هل تحتاج إلى تقارير فحص أو شهادات معها؟'),
  ('job-shop-manufacturing','timeline',null,'When do you need it delivered?','متى تحتاج إلى استلامها؟'),
  ('job-shop-manufacturing','location',null,'Which emirate should it be delivered to?','إلى أي إمارة سيتم التوصيل؟'),

  ('kitchens',null,'New or renovation?','Is this a new kitchen, or renovating an existing one?','هل هو مطبخ جديد، أم تجديد لمطبخ قائم؟'),
  ('kitchens',null,'Approx size (linear m or layout)','Roughly how big is the kitchen, or how long are the cabinet runs?','ما الحجم التقريبي للمطبخ، أو كم طول الخزائن؟'),
  ('kitchens',null,'Material (laminate, acrylic, solid wood)','What look would you like for the cabinets — laminate, gloss acrylic, or wood?','ما المظهر الذي تفضله للخزائن — لامينيت أم أكريليك لامع أم خشب؟'),
  ('kitchens',null,'Appliances included?','Should the price include appliances?','هل يشمل السعر الأجهزة المنزلية؟'),
  ('kitchens',null,'Emirate / area','Which emirate and area?','في أي إمارة ومنطقة؟'),

  ('landscaping','scope',null,'What do you need — plants and lawn, paving, irrigation, a pool, artificial grass, a water feature, or maintenance?','ماذا تحتاج — نباتات وعشب، أم رصف، أم ري، أم مسبح، أم عشب صناعي، أم نافورة، أم صيانة؟'),
  ('landscaping','area_sqm',null,'Roughly how big is the area, in square metres?','ما المساحة التقريبية بالمتر المربع؟'),
  ('landscaping','design',null,'Do you already have a design, or do you need one?','هل لديك تصميم جاهز، أم تحتاج إلى تصميم؟'),
  ('landscaping','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),
  ('landscaping','timeline',null,'When would you like it done?','متى تريد إنجاز العمل؟'),

  ('marble-granite',null,'Application (flooring, wall cladding, countertops, stairs)','Where will the stone go — floors, walls, worktops or stairs?','أين سيُستخدم الحجر — الأرضيات أم الجدران أم أسطح العمل أم الدرج؟'),
  ('marble-granite',null,'Approx area (sqm)','Roughly how big is the area, in square metres?','ما المساحة التقريبية بالمتر المربع؟'),
  ('marble-granite',null,'Material preference','Any stone or colour you like?','هل لديك نوع حجر أو لون تفضله؟'),
  ('marble-granite',null,'Polishing / restoration needed?','Is there existing stone that needs polishing or repairing?','هل يوجد حجر قائم يحتاج إلى تلميع أو إصلاح؟'),
  ('marble-granite',null,'Emirate / area','Which emirate and area?','في أي إمارة ومنطقة؟'),

  ('masonry','work_type',null,'What building work do you need — block walls, plastering, concrete, a boundary wall, or a repair?','ما أعمال البناء المطلوبة — جدران بلوك، أم لياسة، أم خرسانة، أم سور، أم إصلاح؟'),
  ('masonry','scale',null,'Roughly how big is the job?','ما حجم العمل تقريباً؟'),
  ('masonry','property',null,'What kind of property is it?','ما نوع العقار؟'),
  ('masonry','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),
  ('masonry','timeline',null,'When would you like to start?','متى تريد البدء؟'),

  ('mep','disciplines',null,'Which do you need — air conditioning, electrical, plumbing, or all of them?','ماذا تحتاج — التكييف أم الكهرباء أم السباكة أم جميعها؟'),
  ('mep','project_type',null,'Is this a new building, a fit-out, maintenance, or an upgrade?','هل هو مبنى جديد، أم تجهيز داخلي، أم صيانة، أم تحديث؟'),
  ('mep','property',null,'What kind of property is it?','ما نوع العقار؟'),
  ('mep','scale',null,'Roughly how big is the space or the job?','ما حجم المساحة أو العمل تقريباً؟'),
  ('mep','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),

  ('movers','move_type',null,'What are you moving — a home, an apartment, an office, a single item, or abroad?','ما الذي تنقله — منزل أم شقة أم مكتب أم قطعة واحدة أم إلى خارج الدولة؟'),
  ('movers','from_to',null,'Where are you moving from and to?','من أين وإلى أين تنتقل؟'),
  ('movers','size',null,'How big is it — number of bedrooms, or office size?','ما حجمه — عدد غرف النوم أو مساحة المكتب؟'),
  ('movers','services',null,'Do you need packing, taking furniture apart, or storage?','هل تحتاج إلى تغليف، أو فك الأثاث، أو تخزين؟'),
  ('movers','date',null,'Which date would you like to move?','ما التاريخ الذي تريد الانتقال فيه؟'),

  ('painting','scope',null,'Inside, outside, or both?','داخلي أم خارجي أم كلاهما؟'),
  ('painting','area',null,'How many rooms, or roughly how big is the area?','كم غرفة، أو ما المساحة التقريبية؟'),
  ('painting','surface_prep',null,'What are the walls like now — new, already painted, or with cracks to fix?','ما حالة الجدران الآن — جديدة، أم مطلية سابقاً، أم بها تشققات تحتاج إلى إصلاح؟'),
  ('painting','finish',null,'Would you like a flat, soft sheen, glossy or textured finish? The supplier can recommend.','هل تفضل تشطيباً مطفأً أم نصف لامع أم لامعاً أم محبباً؟ يمكن للمورد أن يقترح.'),
  ('painting','occupied',null,'Will people be living or working there during the painting?','هل سيكون المكان مشغولاً أثناء الدهان؟'),
  ('painting','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),
  ('painting','timeline',null,'When would you like it done?','متى تريد إنجاز العمل؟'),

  ('pest','pest_type',null,'What pest is it — cockroaches, termites, bed bugs, rodents, ants, mosquitoes, or something else?','ما نوع الآفة — صراصير أم نمل أبيض أم بق الفراش أم قوارض أم نمل أم بعوض أم غير ذلك؟'),
  ('pest','property',null,'What kind of property is it?','ما نوع العقار؟'),
  ('pest','size',null,'How big is it — number of bedrooms, or the area?','ما حجمه — عدد غرف النوم أو المساحة؟'),
  ('pest','frequency',null,'Is this a one-off treatment, or a regular contract?','هل هي معالجة لمرة واحدة، أم عقد دوري؟'),
  ('pest','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),

  ('plumbing','scope',null,'What plumbing work do you need — water pipes, drains, bathroom fittings, a tank, a water heater or a pump?','ما أعمال السباكة المطلوبة — أنابيب المياه، أم الصرف، أم تركيبات الحمام، أم خزان، أم سخان، أم مضخة؟'),
  ('plumbing','fixture_count',null,'How many bathrooms and kitchens are involved?','كم حماماً ومطبخاً يشمل العمل؟'),
  ('plumbing','water_source',null,'Where does the water come from now — the mains, a tank, or is a new connection needed?','من أين يأتي الماء حالياً — من الشبكة العامة، أم من خزان، أم يلزم توصيل جديد؟'),
  ('plumbing','hot_water',null,'How do you want hot water — one central system, a heater per bathroom, or solar?','كيف تريد الماء الساخن — نظام مركزي، أم سخان لكل حمام، أم بالطاقة الشمسية؟'),
  ('plumbing','fixtures_grade',null,'Should the supplier provide the taps, toilets and basins? If so, premium, mid-range or economy?','هل يوفر المورد الخلاطات والمراحيض والمغاسل؟ وإن كان كذلك، ففاخرة أم متوسطة أم اقتصادية؟'),
  ('plumbing','booster',null,'Is the water pressure weak, so you need a pump?','هل ضغط الماء ضعيف بحيث تحتاج إلى مضخة؟'),
  ('plumbing','tank',null,'Do you need a new water tank, or will the existing one stay?','هل تحتاج إلى خزان ماء جديد، أم سيبقى الخزان الحالي؟'),
  ('plumbing','scope_mode',null,'Should the supplier provide and fit everything, only supply, or only fit?','هل تريد من المورد التوريد والتركيب، أم التوريد فقط، أم التركيب فقط؟'),
  ('plumbing','location',null,'What kind of property is it, and which emirate and area?','ما نوع العقار، وفي أي إمارة ومنطقة؟'),
  ('plumbing','timeline',null,'When would you like it done?','متى تريد إنجاز العمل؟'),

  ('roofing',null,'Roof type (concrete, GI sheet, tiles, membrane)','What is the roof made of — concrete, metal sheets, tiles, or something else?','مم يتكون السطح — خرسانة أم ألواح معدنية أم قرميد أم غير ذلك؟'),
  ('roofing',null,'Approx roof area (sqm)','Roughly how big is the roof?','ما المساحة التقريبية للسطح؟'),
  ('roofing',null,'New install, repair, or waterproofing?','Is this a new roof, a repair, or stopping leaks?','هل هو سطح جديد، أم إصلاح، أم معالجة تسربات؟'),
  ('roofing',null,'Emirate / area','Which emirate and area?','في أي إمارة ومنطقة؟'),
  ('roofing',null,'Timeline','When would you like it done?','متى تريد إنجاز العمل؟'),

  ('safety','occupancy',null,'What is the building used for — offices, shops, a hall or mosque, a warehouse, a factory, homes, or a hotel or restaurant?','لأي غرض يُستخدم المبنى — مكاتب، أم محلات، أم قاعة أو مسجد، أم مستودع، أم مصنع، أم سكن، أم فندق أو مطعم؟'),
  ('safety','building',null,'Roughly how big is the building, how many floors, and about how many people use it?','ما الحجم التقريبي للمبنى، وكم عدد طوابقه، وكم شخصاً يستخدمه تقريباً؟'),
  ('safety','scope',null,'Which fire safety items do you need — alarms, sprinklers, fire pumps, hose points, extinguishers, kitchen or server-room systems, or emergency lights?','ما أنظمة السلامة من الحريق المطلوبة — إنذار، أم رشاشات، أم مضخات حريق، أم نقاط خراطيم، أم طفايات، أم أنظمة للمطبخ أو غرفة الخوادم، أم إنارة طوارئ؟'),
  ('safety','project_stage',null,'Is this a new building, a fit-out, or an upgrade — and do you already have Civil Defence approval?','هل هو مبنى جديد، أم تجهيز داخلي، أم تحديث — وهل لديك موافقة الدفاع المدني؟'),
  ('safety','special_hazards',null,'Is there a commercial kitchen, a server or electrical room, chemical storage, or high racking?','هل يوجد مطبخ تجاري، أم غرفة خوادم أو كهرباء، أم تخزين مواد كيميائية، أم رفوف تخزين عالية؟'),
  ('safety','hassantuk',null,'Is the building in Dubai and used commercially? If so it must be linked to Civil Defence monitoring (Hassantuk).','هل المبنى في دبي ويُستخدم تجارياً؟ إن كان كذلك فيجب ربطه بنظام مراقبة الدفاع المدني (حصانتك).'),
  ('safety','amc',null,'Would you like a yearly maintenance contract included? Civil Defence asks for one before the final inspection.','هل تريد تضمين عقد صيانة سنوي؟ يطلبه الدفاع المدني قبل الفحص النهائي.'),
  ('safety','location',null,'What kind of property is it, and which emirate and area?','ما نوع العقار، وفي أي إمارة ومنطقة؟'),
  ('safety','timeline',null,'When do you need it done?','متى تحتاج إلى إنجازه؟'),

  ('scaffolding','type',null,'What do you need — steel or aluminium scaffolding, a mobile tower, or supports for concrete work?','ماذا تحتاج — سقالات حديد أم ألمنيوم، أم برجاً متنقلاً، أم دعامات لأعمال الخرسانة؟'),
  ('scaffolding','quantity_area',null,'How high does it need to go, and roughly how long a wall does it cover?','ما الارتفاع المطلوب، وما الطول التقريبي للجدار الذي ستغطيه؟'),
  ('scaffolding','purpose',null,'Do you want to buy it, or rent it?','هل تريد شراءها أم استئجارها؟'),
  ('scaffolding','duration',null,'If renting, for how long?','إذا كان استئجاراً، فلأي مدة؟'),
  ('scaffolding','delivery_erection',null,'Should the supplier also put it up, or only deliver it?','هل تريد من المورد تركيبها أيضاً، أم التوصيل فقط؟'),
  ('scaffolding','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),

  ('security','system',null,'What do you need — cameras, door access control, an intercom, an alarm, or all of these together?','ماذا تحتاج — كاميرات، أم نظام تحكم بالدخول، أم إنتركم، أم إنذار، أم جميعها معاً؟'),
  ('security','num_cameras',null,'Roughly how many cameras, and where — entrances, counters, inside, parking?','كم كاميرا تقريباً، وأين — المداخل، أم الكاونترات، أم الداخل، أم المواقف؟'),
  ('security','indoor_outdoor',null,'How many of the cameras will be outside?','كم كاميرا منها ستكون في الخارج؟'),
  ('security','coverage_intent',null,'In the key spots, is it enough to see what happens, or must you recognise faces or read number plates?','في الأماكن المهمة، هل يكفي رؤية ما يحدث، أم يجب التعرف على الوجوه أو قراءة لوحات السيارات؟'),
  ('security','retention',null,'How many days of recordings do you need kept? Most businesses must keep 31 days; banks and gold traders 90.','كم يوماً يجب الاحتفاظ بالتسجيلات؟ معظم المنشآت ملزمة بـ31 يوماً، والبنوك وتجار الذهب بـ90 يوماً.'),
  ('security','access_control',null,'Do you want doors opened by a code, a card or a fingerprint? If so, how many doors?','هل تريد فتح الأبواب برمز أم ببطاقة أم ببصمة؟ وإن كان كذلك، فكم باباً؟'),
  ('security','intercom',null,'Do you need an intercom at the door, with or without video?','هل تحتاج إلى إنتركم عند الباب، بالفيديو أم بدونه؟'),
  ('security','network_power',null,'Should the supplier provide all the cabling, or use the network you already have?','هل يوفر المورد جميع التمديدات، أم يستخدم الشبكة الموجودة لديك؟'),
  ('security','property_location',null,'What kind of property is it, which emirate and area, and which floor?','ما نوع العقار، وفي أي إمارة ومنطقة، وفي أي طابق؟'),
  ('security','scope',null,'Should the supplier provide and install it, only supply, or only install?','هل تريد من المورد التوريد والتركيب، أم التوريد فقط، أم التركيب فقط؟'),

  ('signage','sign_type',null,'What kind of sign — lit, 3D letters, neon, printed, a billboard, acrylic, or direction signs?','ما نوع اللافتة — مضاءة، أم حروف بارزة، أم نيون، أم مطبوعة، أم لوحة إعلانية، أم أكريليك، أم لافتات إرشادية؟'),
  ('signage','dimensions',null,'Roughly how big should it be?','ما الحجم التقريبي المطلوب؟'),
  ('signage','quantity',null,'How many signs?','كم لافتة؟'),
  ('signage','indoor_outdoor',null,'Will it be inside or outside?','هل ستكون في الداخل أم في الخارج؟'),
  ('signage','illuminated',null,'Should it light up?','هل تريدها مضاءة؟'),
  ('signage','install_access',null,'How high will it be mounted, and is it easy to reach?','على أي ارتفاع ستُركّب، وهل يسهل الوصول إليها؟'),
  ('signage','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),
  ('signage','supply_install',null,'Should the supplier also install it, or only make and deliver it?','هل تريد من المورد التركيب أيضاً، أم التصنيع والتوصيل فقط؟'),

  ('smart-home',null,'Which systems (lighting, AC, curtains, security, audio)','What would you like to control — lights, air conditioning, curtains, security or sound?','ما الذي تريد التحكم به — الإنارة، أم التكييف، أم الستائر، أم الأمن، أم الصوت؟'),
  ('smart-home',null,'Property size (bedrooms / sqft)','How big is the home — how many bedrooms?','ما حجم المنزل — كم غرفة نوم؟'),
  ('smart-home',null,'Wired or wireless preference','Is the home still being built, or already finished? That decides wired or wireless.','هل المنزل قيد الإنشاء، أم مكتمل؟ فهذا يحدد إن كان النظام سلكياً أم لاسلكياً.'),
  ('smart-home',null,'Emirate / area','Which emirate and area?','في أي إمارة ومنطقة؟'),
  ('smart-home',null,'Timeline','When would you like it done?','متى تريد إنجاز العمل؟'),

  ('solar',null,'Property type (villa, warehouse, commercial)','What kind of property is it — a villa, a warehouse, or a commercial building?','ما نوع العقار — فيلا أم مستودع أم مبنى تجاري؟'),
  ('solar',null,'Roof area (sqm) or target system size (kW)','Roughly how big is the roof, or how much of your bill do you want solar to cover?','ما المساحة التقريبية للسطح، أو ما نسبة الفاتورة التي تريد أن تغطيها الطاقة الشمسية؟'),
  ('solar',null,'On-grid (DEWA/ADDC) or off-grid?','Should the panels connect to the electricity grid, or run on their own with batteries?','هل تُربط الألواح بشبكة الكهرباء، أم تعمل بشكل مستقل مع بطاريات؟'),
  ('solar',null,'Emirate / area','Which emirate and area?','في أي إمارة ومنطقة؟'),
  ('solar',null,'Timeline','When would you like it done?','متى تريد إنجاز العمل؟'),

  ('steel','product',null,'What do you need in steel — a railing, a gate or fence, a shade, a structure, stairs, or something custom?','ما الأعمال المطلوبة بالحديد — درابزين، أم بوابة أو سور، أم مظلة، أم هيكل، أم درج، أم تصنيع خاص؟'),
  ('steel','material',null,'Plain steel, stainless steel, galvanised, or should the supplier recommend?','حديد عادي، أم ستانلس ستيل، أم مجلفن، أم يقترح المورد؟'),
  ('steel','dimensions',null,'How many pieces, and roughly how big?','كم قطعة، وما حجمها التقريبي؟'),
  ('steel','finish',null,'How should it be finished — painted, powder-coated, galvanised, or polished?','كيف تريد التشطيب — مطلي، أم دهان بودرة، أم مجلفن، أم ملمّع؟'),
  ('steel','drawings',null,'Do you have a drawing or photo, or do you need help with the design?','هل لديك رسم أو صورة، أم تحتاج إلى مساعدة في التصميم؟'),
  ('steel','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),
  ('steel','supply_install',null,'Should the supplier also install it, or only make and deliver it?','هل تريد من المورد التركيب أيضاً، أم التصنيع والتوصيل فقط؟'),

  ('structural-steel-fabrication','structure_type',null,'What do you need built in steel — a mezzanine floor, a warehouse frame, stairs, a shade, or a railing or gate?','ما الهيكل الحديدي المطلوب — طابق ميزانين، أم هيكل مستودع، أم درج، أم مظلة، أم درابزين أو بوابة؟'),
  ('structural-steel-fabrication','dimensions',null,'Roughly how long, wide and high, in metres?','ما الطول والعرض والارتفاع التقريبي بالأمتار؟'),
  ('structural-steel-fabrication','loading',null,'What will it hold — people walking, light or heavy storage, or vehicles?','ما الذي سيحمله — أشخاصاً يمشون عليه، أم تخزيناً خفيفاً أو ثقيلاً، أم مركبات؟'),
  ('structural-steel-fabrication','finish',null,'How should it be finished — primer, painted, galvanised, or fire-protective coating?','كيف تريد التشطيب — طبقة أساس، أم دهان، أم جلفنة، أم طلاء مقاوم للحريق؟'),
  ('structural-steel-fabrication','scope',null,'Should the supplier also install it, or only deliver it?','هل تريد من المورد التوريد والتركيب، أم التوريد فقط؟'),
  ('structural-steel-fabrication','design_approval',null,'Should the supplier do the engineering design and get the approvals, or do you have approved drawings already?','هل يتولى المورد التصميم الإنشائي واستخراج الموافقات، أم لديك مخططات معتمدة؟'),
  ('structural-steel-fabrication','location',null,'Which emirate or free zone is the site in?','في أي إمارة أو منطقة حرة يقع الموقع؟'),
  ('structural-steel-fabrication','flooring',null,'For a mezzanine or platform, what should people walk on — steel plate, concrete, or open grating?','بالنسبة للميزانين أو المنصة، ما الأرضية المطلوبة — ألواح حديد، أم خرسانة، أم شبك مفتوح؟'),
  ('structural-steel-fabrication','timeline',null,'When do you need it finished?','متى تحتاج إلى إنجازه؟'),

  ('swimming-pools',null,'New build, renovation, or maintenance?','Is this a new pool, renovating an existing one, or maintenance?','هل هو مسبح جديد، أم تجديد لمسبح قائم، أم صيانة؟'),
  ('swimming-pools',null,'Approx size (LxWxD or sqm)','Roughly how long, wide and deep is it?','ما الطول والعرض والعمق التقريبي؟'),
  ('swimming-pools',null,'Type (overflow, skimmer)','Would you like the water to spill over the edge (infinity style), or a standard pool?','هل تريد أن يفيض الماء فوق الحافة (مسبح لا متناهٍ)، أم مسبحاً عادياً؟'),
  ('swimming-pools',null,'Features (heating, lighting, jacuzzi)','Any extras — heating, lights, or a jacuzzi?','هل تريد إضافات — تدفئة، أم إنارة، أم جاكوزي؟'),
  ('swimming-pools',null,'Emirate / area','Which emirate and area?','في أي إمارة ومنطقة؟'),

  ('tents-and-shade-structures','engagement_type',null,'Do you want to rent it for an event, or have it built permanently?','هل تريد استئجارها لمناسبة، أم تركيبها بشكل دائم؟'),
  ('tents-and-shade-structures','application',null,'What is it for — an event or wedding, a Ramadan tent, car park shade, an entrance canopy, or storage?','لأي غرض — مناسبة أو حفل زفاف، أم خيمة رمضانية، أم مظلة مواقف، أم مظلة مدخل، أم تخزين؟'),
  ('tents-and-shade-structures','dimensions',null,'Roughly how long and wide, in metres — or how many cars should it cover?','ما الطول والعرض التقريبي بالأمتار — أو كم سيارة يجب أن تغطي؟'),
  ('tents-and-shade-structures','emirate',null,'Which emirate and area is the site in?','في أي إمارة ومنطقة يقع الموقع؟'),
  ('tents-and-shade-structures','mounting_surface',null,'What is the ground like where it goes — concrete, asphalt, paving, or sand?','ما طبيعة الأرض في مكان التركيب — خرسانة، أم أسفلت، أم بلاط، أم رمل؟'),
  ('tents-and-shade-structures','duration',null,'If renting, for which dates?','إذا كان استئجاراً، ففي أي تواريخ؟'),
  ('tents-and-shade-structures','fabric',null,'Any preference for the fabric? The supplier can recommend.','هل لديك تفضيل لنوع القماش؟ يمكن للمورد أن يقترح.'),
  ('tents-and-shade-structures','accessories',null,'Do you need extras — air conditioning, flooring, side walls, lighting, or branding?','هل تحتاج إلى إضافات — تكييف، أم أرضيات، أم جدران جانبية، أم إنارة، أم طباعة شعارات؟'),
  ('tents-and-shade-structures','permits',null,'Who will get the permits and Civil Defence approval — the supplier or you?','من سيستخرج التصاريح وموافقة الدفاع المدني — المورد أم أنت؟'),

  ('tiling','tile_type',null,'What kind of tiles — ceramic, porcelain, marble, granite or mosaic? Or should the supplier recommend?','ما نوع البلاط — سيراميك أم بورسلان أم رخام أم جرانيت أم موزاييك؟ أم يقترح المورد؟'),
  ('tiling','area_sqm',null,'Roughly how big is the area, in square metres?','ما المساحة التقريبية بالمتر المربع؟'),
  ('tiling','areas',null,'Which rooms, and is it floors, walls or both?','أي غرف، وهل هي أرضيات أم جدران أم كلاهما؟'),
  ('tiling','supply_install',null,'Should the supplier provide and lay the tiles, only lay them, or remove old tiles too?','هل يوفر المورد البلاط ويركبه، أم يركبه فقط، أم يزيل البلاط القديم أيضاً؟'),
  ('tiling','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),

  ('upholstery','item',null,'What needs doing — a sofa, curtains, blinds, majlis seating, a headboard, or cushions?','ما المطلوب — كنبة، أم ستائر، أم ستائر رول، أم جلسة مجلس، أم ظهر سرير، أم وسائد؟'),
  ('upholstery','quantity',null,'How many pieces, and roughly how big?','كم قطعة، وما حجمها التقريبي؟'),
  ('upholstery','fabric',null,'Any fabric you like — leather, velvet, linen — or will you provide the fabric?','هل لديك قماش تفضله — جلد، أم مخمل، أم كتان — أم ستوفر القماش بنفسك؟'),
  ('upholstery','pickup_site',null,'Should the supplier take it to their workshop, or do it at your place?','هل ينقلها المورد إلى ورشته، أم ينفذ العمل في مكانك؟'),
  ('upholstery','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),
  ('upholstery','timeline',null,'When would you like it done?','متى تريد إنجاز العمل؟'),

  ('wallpaper','coverage',null,'How many walls or rooms, or roughly how big is the area?','كم جداراً أو غرفة، أو ما المساحة التقريبية؟'),
  ('wallpaper','style',null,'What style — plain or textured, patterned, 3D panels, or a custom picture?','ما الطراز — سادة أو محبب، أم منقوش، أم ألواح ثلاثية الأبعاد، أم صورة مخصصة؟'),
  ('wallpaper','supply_install',null,'Should the supplier provide and hang it, only provide it, or only hang it?','هل يوفر المورد ورق الجدران ويركبه، أم يوفره فقط، أم يركبه فقط؟'),
  ('wallpaper','surface',null,'Are the walls smooth, or do they need some repair first?','هل الجدران ناعمة، أم تحتاج إلى إصلاح أولاً؟'),
  ('wallpaper','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),
  ('wallpaper','timeline',null,'When would you like it done?','متى تريد إنجاز العمل؟'),

  ('water-tank-cleaning','tank_type',null,'Is the tank on the roof, underground, or both?','هل الخزان على السطح، أم تحت الأرض، أم كلاهما؟'),
  ('water-tank-cleaning','capacity',null,'How many tanks, and roughly how big are they?','كم خزاناً، وما حجمها التقريبي؟'),
  ('water-tank-cleaning','property',null,'What kind of property is it?','ما نوع العقار؟'),
  ('water-tank-cleaning','certificate',null,'Do you need a municipality-approved cleaning certificate?','هل تحتاج إلى شهادة تنظيف معتمدة من البلدية؟'),
  ('water-tank-cleaning','water_test',null,'Would you like the water tested in a lab?','هل تريد فحص الماء في مختبر؟'),
  ('water-tank-cleaning','frequency',null,'Is this a one-off, or regular — every six months or yearly?','هل هي مرة واحدة، أم بشكل دوري — كل ستة أشهر أو سنوياً؟'),
  ('water-tank-cleaning','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟'),

  ('waterproofing','area',null,'Where is the problem — the roof, a bathroom, a balcony, a basement, a tank, a pool or an outside wall?','أين المشكلة — السطح، أم الحمام، أم الشرفة، أم القبو، أم الخزان، أم المسبح، أم جدار خارجي؟'),
  ('waterproofing','issue',null,'Is there a leak now, or is this to prevent one?','هل يوجد تسرب حالياً، أم هي وقاية من التسرب؟'),
  ('waterproofing','area_sqm',null,'Roughly how big is the area, in square metres?','ما المساحة التقريبية بالمتر المربع؟'),
  ('waterproofing','supply_install',null,'Should the supplier provide the materials and apply them, or only apply?','هل يوفر المورد المواد وينفذ العزل، أم ينفذ فقط؟'),
  ('waterproofing','location',null,'Which emirate and area?','في أي إمارة ومنطقة؟')
)
update public.category_specs c
   set fields = (
         select jsonb_agg(
                  case when p.en is null then e.f
                       else e.f || jsonb_build_object('question_plain_en', p.en, 'question_plain_ar', p.ar) end
                  order by e.o)
           from jsonb_array_elements(c.fields) with ordinality as e(f, o)
           left join plain p
             on p.category = c.category
            and ((coalesce(e.f->>'key','') <> '' and p.fkey = e.f->>'key')
              or (coalesce(e.f->>'key','') = '' and p.fkey is null and p.fquestion = e.f->>'question'))
       ),
       updated_at = now()
 where c.category in (select category from plain);

-- GUARD: every field now carries both plain-language siblings. A field with neither means it was
-- added or reworded after 14 Sep 2026; the exception rolls the whole file back so the new field is
-- written first rather than silently asked in trade language.
do $$
declare v_missing int; v_sample text;
begin
  select count(*), string_agg(c.category || ':' || coalesce(f->>'key', f->>'question'), ', ')
    into v_missing, v_sample
    from public.category_specs c, jsonb_array_elements(c.fields) f
   where coalesce(f->>'question_plain_en','') = '' or coalesce(f->>'question_plain_ar','') = '';
  if v_missing > 0 then
    raise exception 'plain-language siblings missing on % field(s): %', v_missing, left(v_sample, 800);
  end if;
end $$;
