-- EVERY ANSWER SAYS EVERY TRADE BUT FOOD AND BEVERAGE, AND THAT A JOB NEEDING A SITE VISIT SENDS PHOTOS.
--
-- Assigned: ceo (company knowledge; the published FAQ). Agent: simplify_build_D, 16 Nov 2026. Founder ledgers 1714/1715.
-- Audit: scratchpad audit_simplify/STALE.md S4 and S11.
--
-- THE RULINGS (public.founder_instruction, quoted):
--   1586 (10 Nov): "QuotesDone is a general procurement system for EVERY trade in the UAE except food and beverage ... and
--     anything else."  1704 (15 Nov): "For stuff that requires a site visit. The sales engineer should ask for photos."
-- MEASURED (16 Nov 2026, SELECT on production):
--   * company_faq 5 / 621 ("What sectors ... does QuotesDone cover?") answer "Construction and the built-environment services
--     around it"; 2 ("Why was QuotesDone created?") "construction and services buying"; 4 / 704 ("Who is QuotesDone for?")
--     "need to buy construction, fit-out, MEP and related products"; 174 / 788 ("Will more industries be supported?")
--     "extends across more construction, fit-out, MEP ... (with human approval before that knowledge goes live)".
--   * app_secrets keys excluded_job_scopes ("... any service that requires an on-site visit to price"),
--     job_eligibility_note, min_job_value_aed (all 17 Jul 2026), supplier_subscription_term ("Free for all suppliers until
--     31 July 2027 ...", superseded by the 6 Sep 2026 ruling: free for the first 1,000, no date) and supplier_subscription_start
--     (blank since 6 Sep 2026). Nothing reads them: no production routine body (pg_proc.prosrc, every schema), no view, no
--     cron.job command and no seat_duty names any of the five; in the repository only
--     supabase/functions/_shared/integration_registry.json names them (removed in the same change). subscription_honour_12m
--     is NOT deleted: the view v_supplier_billing reads it.
-- prevented by: the verdict row at the end of this file.
set local lock_timeout = '3s';

update public.company_faq set answer =
  'Every trade in the UAE except food & beverage: construction, fit-out and interiors, MEP and HVAC, lifts and escalators, pools, '
  || 'scaffolding, flooring and marble, sanitary ware, kitchens, packaging, custom manufacturing, decoration panels, transport and '
  || 'rentals, cleaning, facilities management and more — with new trades added automatically as suppliers register them. A job '
  || 'that needs a site visit is covered too: send photos of the site so suppliers can quote; a final price may still need the visit. '
  || 'Each request is sent only to suppliers of that exact trade, never to a neighbouring one.', updated_at = now()
 where id = 5 and answer like 'Construction and the built-environment services around it%';
update public.company_faq set answer =
  'جميع التخصصات في الإمارات باستثناء الأغذية والمشروبات: الإنشاءات، والتشطيبات والتصميم الداخلي، والأعمال الكهروميكانيكية والتكييف، '
  || 'والمصاعد والسلالم المتحركة، وحمامات السباحة، والسقالات، والأرضيات والرخام، والأدوات الصحية، والمطابخ، ومواد التغليف، والتصنيع حسب الطلب، '
  || 'وألواح الديكور، والنقل والتأجير، والتنظيف وإدارة المرافق وغيرها، مع إضافة تخصصات جديدة تلقائيًا كلما سجّلها الموردون. وتشمل التغطية '
  || 'الأعمال التي تحتاج إلى زيارة موقع: أرسلوا صورًا للموقع ليتمكن الموردون من التسعير، وقد يحتاج السعر النهائي إلى الزيارة نفسها. '
  || 'ويُرسل كل طلب إلى موردي التخصص المطلوب نفسه فقط، ولا يُرسل إلى تخصص قريب منه.', updated_at = now()
 where id = 621 and answer like 'الإنشاءات وخدمات البيئة المبنية%';
update public.company_faq set answer =
  'QuotesDone already covers every trade in the UAE except food & beverage. When a supplier registers a trade QuotesDone has not seen, '
  || 'the Smart Engine can stand up a new category agent with the right qualification questions and knowledge (reviewed before that '
  || 'knowledge goes live), so coverage deepens without losing quality — always grounded in real, verified requirements for each field.', updated_at = now()
 where id = 174 and answer like '%more construction, fit-out, MEP%';
update public.company_faq set answer =
  'يغطي QuotesDone اليوم جميع التخصصات في الإمارات باستثناء الأغذية والمشروبات. وعندما يسجّل مورّد تخصصًا لم يمرّ على QuotesDone من قبل، '
  || 'يستطيع المحرك الذكي إنشاء وكيل فئة جديد بأسئلة التأهيل والمعرفة المناسبة (مع مراجعة تلك المعرفة قبل تفعيلها)، فتتعمق التغطية دون المساس '
  || 'بالجودة، مستندةً دائمًا إلى متطلبات حقيقية وموثّقة لكل مجال.', updated_at = now()
 where id = 788 and answer like '%مزيد من أعمال البناء%';
update public.company_faq set answer = replace(answer,
    'QuotesDone was created to fix how construction and services buying works in the UAE:',
    'QuotesDone was created to fix how buying works in the UAE, in every trade:'), updated_at = now()
 where id = 2 and answer like '%construction and services buying%';
update public.company_faq set answer = replace(answer,
    'who need to buy construction, fit-out, MEP and related products or services and want',
    'who need to buy products or services in any trade except food & beverage and want'), updated_at = now()
 where id = 4 and answer like '%need to buy construction, fit-out, MEP%';
update public.company_faq set answer = replace(answer,
    'يحتاجون إلى شراء منتجات أو خدمات البناء والتشطيبات والأعمال الكهروميكانيكية وما يتصل بها، ويريدون',
    'يحتاجون إلى شراء منتجات أو خدمات في أي تخصص عدا الأغذية والمشروبات، ويريدون'), updated_at = now()
 where id = 704 and answer like '%خدمات البناء والتشطيبات%';

-- the five keys nothing reads (keys only; their values are never printed)
delete from public.app_secrets
 where key in ('excluded_job_scopes', 'job_eligibility_note', 'min_job_value_aed', 'supplier_subscription_term', 'supplier_subscription_start');

select case
  when exists (select 1 from public.company_faq where id in (2, 4, 5, 174, 621, 704, 788)
                and answer ~ '(built-environment|construction and services buying|need to buy construction|more construction, fit-out|human approval|البيئة المبنية|مزيد من أعمال البناء|خدمات البناء والتشطيبات|باعتماد بشري)')
    then 'PROBE FAILED: a scope answer still says construction only'
  when exists (select 1 from public.app_secrets where key in ('excluded_job_scopes', 'job_eligibility_note', 'min_job_value_aed', 'supplier_subscription_term', 'supplier_subscription_start'))
    then 'PROBE FAILED: an unread superseded key is still there'
  when not exists (select 1 from public.company_faq where id = 5 and answer like '%site visit is covered%') and exists (select 1 from public.company_faq where id = 5)
    then 'PROBE FAILED: the scope answer does not say a site-visit job is covered'
  else 'PROBE OK: the scope answers say every trade but food and beverage, a site-visit job sends photos; the five unread keys are gone' end as verdict;
