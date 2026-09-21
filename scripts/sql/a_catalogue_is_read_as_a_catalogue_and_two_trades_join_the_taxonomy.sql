-- A CATALOGUE IS READ AS A CATALOGUE, AND TWO TRADES JOIN THE TAXONOMY. Seat: sales_engineer. 21 Sep 2026.
--
-- MEASURED (production + the platform's own deterministic path on a real IT/electronics importer's
-- 7-page catalogue, 21 Sep 2026): taxonomy_trade 40 active codes, taxonomy_trade_service 201 active
-- rows, service_implication 113. The catalogue sells laptops, desktops, all-in-ones, printers,
-- photocopiers, toners, projectors, UPS (17 mentions), POS terminals, receipt printers, barcode readers,
-- money counters, CCTV kits and cable. Nothing in the taxonomy named printers, photocopiers, toners,
-- desktops, POS, receipt printers or barcode scanners; power_generators.ups only knew "ups system/unit/
-- battery"; no directory table carries all 40 trades (lead_trade_map 26, intake 20, seo 9), so a new
-- trade has no directory row to add.
-- WRONG: office equipment and point-of-sale technology had no trade, so an importer of them could be
-- matched to nothing it sells; UPS in a catalogue named nothing.
-- WHAT THIS CHANGES
--   1. taxonomy_trade: office_equipment (Office equipment & printing / المعدات المكتبية والطباعة) and
--      pos_retail (Point-of-sale & retail technology / أنظمة نقاط البيع وتقنيات التجزئة), with EN+AR
--      aliases for fn_norm_trades — exact word-start, like every other trade (founder: categories are
--      open; exact trade or none).
--   2. taxonomy_trade_service: five services each, EN+AR, as every trade has.
--   3. taxonomy_trade_service.aliases for those ten and for power_generators.ups (+ "ups", whole word in
--      the TS matcher), it_services.hardware_supply (+ desktop, all in one, computers, peripherals) and
--      security_systems.cctv (+ dvr, nvr). The same rows are supabase/functions/_shared/
--      service_aliases.json (scripts/checks/the_implication_map_has_one_seed.test.mjs holds them equal).
--   4. taxonomy_trade_service.embedding_gte vector(384) — the service names as the free in-region
--      gte-small model sees them, for the meaning layer (_shared/service_meaning.ts). Written by
--      scripts/kb/embed_taxonomy_services.mjs AFTER this file; NULL until then, and the layer says so.
--   5. decision_policy supplier_catalogue_model_enabled and supplier_photo_vision_enabled, both
--      {"enabled": false}: the model paths for what code cannot read (a catalogue with no text, a photo's
--      content) go through ai_gateway on the sales_engineer route only when switched on, and OpenRouter
--      is on hold.
-- NOT CHANGED: service_implication (CCTV -> intruder alarms stays, with its EN+AR reason; the rewrite no
-- longer applies any implication to a supply-only company, see _shared/catalogue_read.ts), fn_norm_trades,
-- fn_match_capability, fn_services_effective, any supplier's saved capabilities. No routine is created.
-- PROBE: the last statement returns one verdict row.

insert into public.taxonomy_trade (code, label, label_ar, aliases, authority_required, sort, active)
values
  ('office_equipment', 'Office equipment & printing', 'المعدات المكتبية والطباعة',
   array['office equipment','office automation','office machines','photocopier','copier machine','printer','toner','معدات مكتبية','أجهزة مكتبية','طابعات','آلات تصوير','أحبار طابعات']::text[],
   '{}'::text[], 41, true),
  ('pos_retail', 'Point-of-sale & retail technology', 'أنظمة نقاط البيع وتقنيات التجزئة',
   array['point of sale','pos system','pos terminal','cash register','barcode scanner','receipt printer','retail technology','نقاط بيع','نقطة بيع','أجهزة كاشير','باركود']::text[],
   '{}'::text[], 42, true)
on conflict (code) do update
   set label = excluded.label, label_ar = excluded.label_ar, aliases = excluded.aliases, active = true;

insert into public.taxonomy_trade_service (trade_code, code, label_en, label_ar, sort)
values
  ('office_equipment','printers_mfp','Printers & multifunction printers','الطابعات والطابعات متعددة الوظائف',10),
  ('office_equipment','photocopiers','Photocopiers & copiers','آلات التصوير والنسخ',20),
  ('office_equipment','toners_cartridges','Toners & ink cartridges','الأحبار والخراطيش',30),
  ('office_equipment','office_machines','Office machines (shredders, laminators, binders)','الآلات المكتبية (فرّامات الورق والتغليف الحراري والتجليد)',40),
  ('office_equipment','printer_service','Printer & copier servicing','صيانة الطابعات وآلات التصوير',50),
  ('pos_retail','pos_terminals','POS terminals & systems','أجهزة وأنظمة نقاط البيع',10),
  ('pos_retail','receipt_printers','Receipt & label printers','طابعات الإيصالات والملصقات',20),
  ('pos_retail','barcode_scanners','Barcode scanners & readers','قارئات وماسحات الباركود',30),
  ('pos_retail','cash_handling','Cash drawers & money counters','أدراج النقد وعدّادات النقود',40),
  ('pos_retail','retail_software','POS & retail software','برامج نقاط البيع والتجزئة',50)
on conflict (trade_code, code) do nothing;

with seed(trade_code, code, aliases) as (values
  ('power_generators','ups', array['ups system','ups unit','ups battery','uninterruptible power','ups','battery backup','power backup','يو بي اس','طاقة غير منقطعة','مزود طاقة احتياطي','يوبي اس','طاقة احتياطية','بطارية احتياطية']::text[]),
  ('it_services','hardware_supply', array['hardware supply','computer supply','laptop','server supply','it hardware','desktop','all in one','computers','peripherals','computer accessories','توريد اجهزة كمبيوتر','توريد حواسيب','اجهزة كمبيوتر','لابتوب','كمبيوتر مكتبي','كمبيوترات مكتبية','حاسوب مكتبي','كل في واحد','ملحقات كمبيوتر']::text[]),
  ('security_systems','cctv', array['cctv','camera','surveillance','security camera','dvr','nvr','كاميرات مراقبة','كاميرات','كاميرا','كاميرات أمنية']::text[]),
  ('office_equipment','printers_mfp', array['printer','laser printer','inkjet printer','multifunction printer','mfp','طابعة','طابعات','طابعة ليزر','طابعات ليزر','طابعة متعددة الوظائف']::text[]),
  ('office_equipment','photocopiers', array['photocopier','photocopy machine','copier','copy machine','آلة تصوير','آلات تصوير','ماكينة تصوير','ماكينات تصوير','آلة نسخ','فوتوكوبي']::text[]),
  ('office_equipment','toners_cartridges', array['toner','ink cartridge','printer cartridge','cartridge','printer ink','حبر طابعة','أحبار طابعات','خرطوشة','خراطيش','تونر']::text[]),
  ('office_equipment','office_machines', array['shredder','paper shredder','laminator','laminating machine','binding machine','office automation','office equipment','آلة تمزيق ورق','فرامة ورق','آلة تغليف حراري','آلة تجليد','أجهزة مكتبية','معدات مكتبية']::text[]),
  ('office_equipment','printer_service', array['printer repair','printer maintenance','printer service','copier maintenance','copier service','photocopier repair','صيانة طابعات','صيانة طابعة','تصليح طابعات','صيانة آلات تصوير']::text[]),
  ('pos_retail','pos_terminals', array['pos','pos terminal','pos system','point of sale','cash register','epos','نقاط بيع','نقطة بيع','جهاز كاشير','أجهزة كاشير','كاشير']::text[]),
  ('pos_retail','receipt_printers', array['receipt printer','thermal printer','label printer','barcode printer','طابعة إيصالات','طابعات إيصالات','طابعة فواتير','طابعة حرارية','طابعة باركود','طابعة ملصقات']::text[]),
  ('pos_retail','barcode_scanners', array['barcode scanner','barcode reader','barcode','qr scanner','قارئ باركود','ماسح باركود','باركود']::text[]),
  ('pos_retail','cash_handling', array['cash drawer','money counter','money counting machine','cash counter','note counter','currency counter','counterfeit detector','درج نقود','درج كاشير','عداد نقود','عدادة نقود','ماكينة عد نقود','كاشف عملات مزيفة']::text[]),
  ('pos_retail','retail_software', array['pos software','retail software','billing software','برنامج نقاط بيع','برامج نقاط بيع','برنامج كاشير','برنامج فواتير']::text[])
)
update public.taxonomy_trade_service t
   set aliases = s.aliases
  from seed s
 where t.trade_code = s.trade_code and t.code = s.code
   and t.aliases is distinct from s.aliases;

-- Every key the seed names must be a live service, or the rewrite would name something that is not on
-- the platform. Raises (and so rolls this whole file back) rather than skipping.
do $$
declare v_missing text;
begin
  select string_agg(k, ', ') into v_missing
  from unnest(array['power_generators.ups','it_services.hardware_supply','security_systems.cctv',
    'office_equipment.printers_mfp','office_equipment.photocopiers','office_equipment.toners_cartridges',
    'office_equipment.office_machines','office_equipment.printer_service','pos_retail.pos_terminals',
    'pos_retail.receipt_printers','pos_retail.barcode_scanners','pos_retail.cash_handling',
    'pos_retail.retail_software']) k
  where not exists (select 1 from public.taxonomy_trade_service s where s.trade_code || '.' || s.code = k and s.active);
  if v_missing is not null then
    raise exception 'seeded services not active in taxonomy_trade_service: %', v_missing;
  end if;
end $$;

alter table public.taxonomy_trade_service add column if not exists embedding_gte vector(384);
comment on column public.taxonomy_trade_service.embedding_gte is
  'gte-small (free, in-region, NOT OpenRouter) vector of the service''s EN+AR names and its trade''s name, written by scripts/kb/embed_taxonomy_services.mjs. Read by _shared/service_meaning.ts, which proposes a service from a line''s meaning only when a word of the line or a second line corroborates it. NULL = not yet embedded. Seat: sales_engineer.';

insert into public.decision_policy (key, value, description, updated_at)
select v.key, '{"enabled": false}'::jsonb, v.description, now()
from (values
  ('supplier_catalogue_model_enabled',
   'Supplier catalogue model path (_shared/catalogue_model.ts): a catalogue or description code could not read (no text layer, free-form prose) sent to ai_gateway on the sales_engineer route for {product_types, services, confidence, reason}. OFF while the OpenRouter hold stands; switching it on is the founder''s spend decision.'),
  ('supplier_photo_vision_enabled',
   'Supplier photo vision path (_shared/catalogue_model.ts): what a product photo SHOWS, sent to ai_gateway on the sales_engineer route. The text IN a photo is read free in the supplier''s browser (tesseract.js) whatever this says. OFF while the OpenRouter hold stands.')
) as v(key, description)
where not exists (select 1 from public.decision_policy d where d.key = v.key);

-- PROBE: one verdict row.
select case
  when (select count(*) from public.taxonomy_trade where code in ('office_equipment','pos_retail') and active) = 2
   and (select count(*) from public.taxonomy_trade_service where trade_code in ('office_equipment','pos_retail') and active) = 10
   and (select count(*) from public.taxonomy_trade_service where trade_code in ('office_equipment','pos_retail') and cardinality(aliases) >= 4) = 10
   and exists (select 1 from public.taxonomy_trade_service where trade_code = 'power_generators' and code = 'ups' and 'ups' = any(aliases))
   and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'taxonomy_trade_service' and column_name = 'embedding_gte')
   and (select count(*) from public.decision_policy where key in ('supplier_catalogue_model_enabled','supplier_photo_vision_enabled') and value = '{"enabled": false}'::jsonb) = 2
  then 'PROBE OK' else 'PROBE FAILED' end as verdict;
