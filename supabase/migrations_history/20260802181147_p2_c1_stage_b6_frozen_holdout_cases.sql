-- P2-C1 STAGE B.6 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802181147   name: p2_c1_stage_b6_frozen_holdout_cases
-- SHA-256 of the applied SQL: e785329adb291c1efb69e6d38b00f56c9551f256105187c9cd1fe4a38b5c6beb
-- Recovered by scripts/recover_stage_b6.mjs. The body below is byte-for-byte as applied;
-- only this header was added, and it is excluded from the checksum.

-- 54 paired cases. Expectations written from the MEANING of each sentence, before any
-- disposition code exists. expect_components lists only non-included component dispositions.

insert into public.p2c1_holdout_case
 (case_key, category, text_en, text_ar, expect_active, expect_dispositions, expect_components, expect_clarify, expect_conflict, note) values
('x01','exclusion','Complete fit-out; MEP by others.','تشطيب كامل؛ الأعمال الكهروميكانيكية من قبل الغير.','{}','{"hvac":"by_others","electrical":"by_others","plumbing":"by_others"}','{}',true,false,'Umbrella by_others. No core workstream may activate.'),
('x02','exclusion','Complete MEP package; coordination by others.','حزمة كهروميكانيكية كاملة؛ التنسيق من قبل الغير.','{electrical,hvac,plumbing}','{}','{"coordination":"by_others"}',false,false,'Component-level exclusion must NOT kill the trade scope.'),
('x03','exclusion','HVAC by others; electrical and plumbing included.','التكييف من قبل الغير؛ الكهرباء والسباكة مشمولة.','{electrical,plumbing}','{"hvac":"by_others"}','{}',false,false,null),
('x04','exclusion','MEP excluded except plumbing.','الأعمال الكهروميكانيكية مستثناة عدا السباكة.','{plumbing}','{"hvac":"excluded","electrical":"excluded"}','{}',false,false,'Carve-out: specific trade inclusion beats umbrella exclusion.'),
('x05','exclusion','Fire alarm not required; CCTV required.','إنذار الحريق غير مطلوب؛ كاميرات المراقبة مطلوبة.','{elv}','{"fire":"excluded"}','{}',false,false,null),
('x06','exclusion','MEP by main contractor. Electrical included in this package.','الأعمال الكهروميكانيكية من قبل المقاول الرئيسي. الكهرباء مشمولة في هذه الحزمة.','{electrical}','{"hvac":"by_others","plumbing":"by_others"}','{}',false,false,null),
('x07','exclusion','Electrical works. Plumbing excluded.','أعمال الكهرباء. السباكة مستثناة.','{electrical}','{"plumbing":"excluded"}','{}',false,false,null),
('x08','exclusion','HVAC and electrical; no ELV.','التكييف والكهرباء؛ بدون تيار خفيف.','{electrical,hvac}','{"elv":"excluded"}','{}',false,false,null),
('x09','exclusion','Fire fighting is not in our scope.','مكافحة الحريق ليست ضمن نطاق عملنا.','{}','{"fire":"excluded"}','{}',true,false,null),
('x10','exclusion','MEP package excluding HVAC.','حزمة كهروميكانيكية باستثناء التكييف.','{electrical,plumbing}','{"hvac":"excluded"}','{}',false,false,null),
('x11','exclusion','Plumbing installation only; supply by others.','تركيب السباكة فقط؛ التوريد من قبل الغير.','{plumbing}','{}','{"supply":"by_others"}',false,false,null),
('x12','exclusion','Electrical works; design by others.','أعمال الكهرباء؛ التصميم من قبل الغير.','{electrical}','{}','{"design":"by_others"}',false,false,null),
('x13','exclusion','HVAC works; authority approvals by others.','أعمال التكييف؛ موافقات الجهات من قبل الغير.','{hvac}','{}','{"authority_approvals":"by_others"}',false,false,null),
('x14','exclusion','Electrical package; maintenance excluded.','حزمة كهرباء؛ الصيانة مستثناة.','{electrical}','{}','{"maintenance":"excluded"}',false,false,null),
('x15','exclusion','Plumbing works; testing and commissioning by others.','أعمال السباكة؛ الاختبار والتشغيل من قبل الغير.','{plumbing}','{}','{"testing":"by_others","commissioning":"by_others"}',false,false,null),
('x16','exclusion','All MEP works are excluded from this tender.','جميع الأعمال الكهروميكانيكية مستثناة من هذه المناقصة.','{}','{"hvac":"excluded","electrical":"excluded","plumbing":"excluded"}','{}',true,false,null),
('x17','exclusion','Omit fire fighting scope.','استبعاد نطاق مكافحة الحريق.','{}','{"fire":"excluded"}','{}',true,false,null),
('x18','exclusion','ELV by the client.','التيار الخفيف من قبل العميل.','{}','{"elv":"by_others"}','{}',true,false,null),
('x19','exclusion','HVAC excluded. Electrical included.','التكييف مستثنى. الكهرباء مشمولة.','{electrical}','{"hvac":"excluded"}','{}',false,false,null),
('x20','exclusion','MEP package without plumbing.','حزمة كهروميكانيكية بدون سباكة.','{electrical,hvac}','{"plumbing":"excluded"}','{}',false,false,null),
('x21','exclusion','MEP by others except electrical.','الأعمال الكهروميكانيكية من قبل الغير عدا الكهرباء.','{electrical}','{"hvac":"by_others","plumbing":"by_others"}','{}',false,false,null),
('o01','optional','ELV optional.','التيار الخفيف اختياري.','{}','{"elv":"optional"}','{}',true,false,null),
('o02','optional','Electrical works; fire fighting if required.','أعمال الكهرباء؛ مكافحة الحريق إن لزم.','{electrical}','{"fire":"optional"}','{}',false,false,null),
('f01','future','HVAC is planned for a future phase.','التكييف مخطط لمرحلة لاحقة.','{}','{"hvac":"future_phase"}','{}',true,false,null),
('f02','future','Electrical now; ELV in phase 2.','الكهرباء الآن؛ التيار الخفيف في المرحلة الثانية.','{electrical}','{"elv":"future_phase"}','{}',false,false,null),
('c01','client_supplied','AHUs supplied by client; installation by contractor.','وحدات مناولة الهواء توريد العميل؛ التركيب من قبل المقاول.','{hvac}','{}','{"supply":"client_supplied"}',false,false,'Component split within an active trade.'),
('c02','client_supplied','Chillers are client supplied. Plumbing included.','الشيلرات توريد العميل. السباكة مشمولة.','{hvac,plumbing}','{}','{"supply":"client_supplied"}',false,false,null),
('e01','existing','Existing fire alarm to remain with modifications.','إنذار الحريق الحالي يبقى مع تعديلات.','{fire}','{"fire":"existing_only"}','{}',false,false,'Active: modifications are work.'),
('e02','existing','Existing HVAC retained; electrical upgrade required.','التكييف الحالي يبقى؛ ترقية الكهرباء مطلوبة.','{electrical,hvac}','{"hvac":"existing_only"}','{}',false,false,null),
('k01','conflict','HVAC included. HVAC excluded.','التكييف مشمول. التكييف مستثنى.','{}','{"hvac":"conflicted"}','{}',true,true,'Equal specificity, contradictory. Must not be resolved by whichever sentence is last.'),
('k02','conflict','CCTV required. CCTV not required.','كاميرات المراقبة مطلوبة. كاميرات المراقبة غير مطلوبة.','{}','{"elv":"conflicted"}','{}',true,true,null),
('k03','conflict','Plumbing by others. Plumbing included.','السباكة من قبل الغير. السباكة مشمولة.','{}','{"plumbing":"conflicted"}','{}',true,true,null),
('m01','multi_clause','Full fit-out of offices. MEP coordination by others.','تشطيب كامل للمكاتب. تنسيق الأعمال الكهروميكانيكية من قبل الغير.','{}','{}','{"coordination":"by_others"}',true,false,'Anchor and modifier in different sentences: no full-MEP activation.'),
('m02','multi_clause','Complete MEP package; HVAC by others; testing by others.','حزمة كهروميكانيكية كاملة؛ التكييف من قبل الغير؛ الاختبار من قبل الغير.','{electrical,plumbing}','{"hvac":"by_others"}','{"testing":"by_others"}',false,false,null),
('m03','multi_clause','Electrical, plumbing and fire fighting required; ELV excluded.','الكهرباء والسباكة ومكافحة الحريق مطلوبة؛ التيار الخفيف مستثنى.','{electrical,fire,plumbing}','{"elv":"excluded"}','{}',false,false,null),
('m04','multi_clause','The building is complete. MEP works required.','المبنى مكتمل. الأعمال الكهروميكانيكية مطلوبة.','{}','{}','{}',true,false,'"complete" belongs to the building, not to MEP. Must ask.'),
('g01','gulf','Central AC units and electrical panels.','مكيفات مركزية ولوحات كهربائية.','{electrical,hvac}','{}','{}',false,false,null),
('g02','gulf','Drainage works only.','أعمال الصرف الصحي فقط.','{plumbing}','{}','{}',false,false,null),
('g03','spelling','Fire fighting works.','اعمال مكافحه الحريق.','{fire}','{}','{}',false,false,'Plain alef and ha-for-ta-marbuta.'),
('g04','spelling','Electrical works excluded.','الاعمال الكهربائيه مستثناه.','{}','{"electrical":"excluded"}','{}',true,false,null),
('i01','mixed','MEP package required.','مطلوب MEP package.','{electrical,hvac,plumbing}','{}','{}',false,false,null),
('i02','mixed','HVAC by others.','HVAC من قبل الغير.','{}','{"hvac":"by_others"}','{}',true,false,null),
('i03','mixed','CCTV required, fire alarm excluded.','CCTV مطلوب، إنذار الحريق مستثنى.','{elv}','{"fire":"excluded"}','{}',false,false,null),
('i04','mixed','AHU supply by client.','توريد AHU من قبل العميل.','{hvac}','{}','{"supply":"client_supplied"}',false,false,null),
('i05','mixed','ELV optional.','ELV اختياري.','{}','{"elv":"optional"}','{}',true,false,null),
('i06','mixed','Chiller supply.','توريد chillers.','{hvac}','{}','{}',false,false,null),
('i07','mixed','Electrical now, ELV future phase.','الكهرباء الآن، ELV مرحلة لاحقة.','{electrical}','{"elv":"future_phase"}','{}',false,false,null),
('i08','mixed','MEP by others except electrical.','MEP من قبل الغير عدا الكهرباء.','{electrical}','{"hvac":"by_others","plumbing":"by_others"}','{}',false,false,null),
('i09','mixed','Plumbing works; testing by others.','أعمال السباكة؛ testing من قبل الغير.','{plumbing}','{}','{"testing":"by_others"}',false,false,null),
('i10','mixed','Complete MEP works.','أعمال MEP كاملة.','{electrical,hvac,plumbing}','{}','{}',false,false,null),
('a01','adversarial','Complete furniture package for the office.','حزمة أثاث كاملة للمكتب.','{}','{}','{}',true,false,null),
('a02','adversarial','Landscaping and irrigation works.','أعمال تنسيق الحدائق والري.','{}','{}','{}',true,false,'Arabic تنسيق means coordination AND landscaping. Must not raise a coordination disposition with no trade.'),
('a03','adversarial','Office IT support contract.','عقد دعم تقنية المعلومات للمكتب.','{}','{}','{}',true,false,null),
('a04','adversarial','Complete cleaning package.','حزمة تنظيف كاملة.','{}','{}','{}',true,false,null)
on conflict (case_key) do nothing;

insert into public.p2c1_holdout_seal (id, case_count, checksum_sha, sealed_by, note)
select 1, count(*), public.fn_p2c1_holdout_checksum(), 'claude:stage_b6',
       'Sealed before any scope-disposition interpretation code was written. Any later drift in this checksum means the holdout was edited, and the results stop being evidence.'
  from public.p2c1_holdout_case
on conflict (id) do nothing;
;