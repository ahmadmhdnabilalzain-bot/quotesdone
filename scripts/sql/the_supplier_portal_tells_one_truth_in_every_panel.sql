-- THE SUPPLIER PORTAL TELLS ONE TRUTH IN EVERY PANEL (21 Sep 2026, it_engineer).
--
-- Supplier-portal audit of 21 Sep 2026 (ZZ DEMO Interiors gypsum founderdemo, read-only), findings
-- 17, 18, 19, 21, 22, 23 and 24. Each is the same defect wearing a different label: a panel read a
-- subject other than the supplier's own rows, and told the supplier something false about itself.
--
-- MEASURED (the audit's screenshots, against the routines below as they were):
--   * 17  An ISO certificate uploaded as a SUPPORTING document (public.documents, ref_table
--         'supplier_supporting', kind 'supporting:certificate') counted as "ISO certification
--         MISSING" in the unlock panel, Company health, Certifications and the Sales-engineer panel,
--         because all four read only leads.iso_doc_path. Two homes for one subject.
--   * 18  fn_supplier_certifications called the EGR "Establishment card"; the portal called it
--         "EGR (Emirates Green Building) certificate"; the hint said "immigration establishment
--         card". The estate's own profile field is "Economic Register (EGR) no." and the knowledge
--         canon lists "EGR" beside insurance and ISO as an optional company document. It is the
--         establishment card issued with the trade licence; it is not a green-building certificate.
--   * 19  Certifications listed "VAT certificate" and "Bank details (IBAN)" with "Upload in
--         Documents" while the Documents tab deliberately has no slot for either (the TRN is read
--         off the licence; money moves through Stripe both ways). IBAN is removed estate-wide by
--         PR #766; VAT is dropped here.
--   * 21  fn_supplier_market counted competitors as leads with the same leads.sector string. A
--         self-registered supplier's sector is a taxonomy code and a scraped lead's is prose, so the
--         supplier saw "0 competitors" while fn_customer_decision_support — which counts through
--         supplier_capabilities.trades — told the customer 153 cover the trade. demand_mine compared
--         inquiries.category to leads.sector the same way, so "no enquiries in your category yet"
--         sat beside "Most requested: Gypsum, 2 enquiries", and "nothing in your category has been
--         priced" after this supplier priced 3.
--   * 22  fn_supplier_knowledge_graph read lead_category (the scraped taxonomy) only, so a supplier
--         with two CONFIRMED trades in supplier_capabilities was "not listed in any category".
--   * 23  fn_supplier_advisor read quotes_submitted from public.supplier_score, a cache last
--         refreshed 16 Aug 2026 (#761 measured this for fn_supplier_tier): "You have not quoted on
--         anything yet" with 3 quotations in public.quotes; "response rate 0%" from the same cache.
--   * 24  fn_supplier_twin returned service_emirates under the key `countries`, and risk_level 'LOW'
--         for a supplier with no licence on file, no score row and no history — a verdict with no
--         measurement behind it. health.quotes_submitted / quotes_won came from the stale cache too.
--
-- WHAT THIS CHANGES
--   1. public.fn_supplier_document_home(bigint) — NEW. The one answer to "is this document on file":
--      the leads column first, and for a certificate kind (ISO, insurance, manufacturer authorisation)
--      the newest live supporting document whose label names it. Every routine below reads it, and
--      supplier_portal `documents` overlays it, so the four panels cannot disagree again.
--   2. fn_supplier_certifications — reads (1); drops vat and bank_iban; EGR is "Establishment card
--      (EGR)"; every label and reason now carries an Arabic twin (label_ar, impact_why_ar).
--   3. fn_supplier_document_impact — reads (1).
--   4. fn_supplier_twin — quotes from public.quotes (the #761 rule), documents from (1), `emirates`
--      instead of `countries` (the old key is kept, same value, for older clients), and risk_level is
--      NULL with risk_basis when nothing has been measured.
--   5. fn_supplier_market — peers and demand through supplier_capabilities.trades, the same rows
--      fn_customer_decision_support counts; sector equality is kept as a second leg.
--   6. fn_supplier_knowledge_graph — my_categories is the confirmed trades plus lead_category.
--   7. fn_supplier_advisor — quotes from public.quotes, response rate from leads.rv_response_rate,
--      the "capability summary" gap (a machine-filled column with no field) becomes the real gate
--      (services unconfirmed → Services tab); Arabic twins (action_ar, why_ar, headline_ar).
--
-- NOT CHANGED: supplier_score and its refresh; every threshold; fn_supplier_tier (#761); the demo
-- fence predicate in fn_supplier_market; the supporting-documents writer (nothing here writes).
--
-- PROOF: the verdict row at the end calls each routine for a lead that does not exist (every key
-- present, nothing raised) and checks the certification keys. Nothing is written.

-- ── 1. ONE HOME FOR EACH DOCUMENT SUBJECT ─────────────────────────────────────────────────────────
create or replace function public.fn_supplier_document_home(p_lead_id bigint)
returns table(key text, path text, name text, expiry date, source text)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (select * from public.leads where id = p_lead_id),
  -- A live supporting document whose LABEL names the subject. The label is the supplier's own
  -- words for the file ("ISO 9001:2015", "شهادة الأيزو", "Public liability insurance").
  supp as (
    select d.path, d.file_name, d.created_at,
           case
             when d.file_name ~* '(^|[^a-z])iso([^a-z]|$)|أيزو|ايزو|آيزو' then 'iso'
             when d.file_name ~* 'insurance|liability|all[- ]?risk|تأمين|تامين' then 'insurance'
             when d.file_name ~* 'manufacturer|authori[sz]|dealer|distributor|agency letter|وكالة|تفويض|توزيع' then 'manufacturer_auth'
           end as subject
    from public.documents d
    where d.ref_table = 'supplier_supporting' and d.ref_id = p_lead_id::text
      and coalesce(d.status, '') <> 'withdrawn'
  ),
  best as (
    select distinct on (subject) subject, path, file_name from supp
    where subject is not null order by subject, created_at desc
  ),
  fixed(key, path, name, expiry) as (
    select 'trade_licence',     (select license_doc_path from me),           (select license_doc_name from me), (select license_expiry from me)::date
    union all select 'company_profile',   (select company_profile_doc_path from me),   null, null::date
    union all select 'insurance',         (select insurance_doc_path from me),         null, (select insurance_expiry from me)::date
    union all select 'iso',               (select iso_doc_path from me),               null, (select iso_expiry from me)::date
    union all select 'manufacturer_auth', (select manufacturer_auth_doc_path from me), null, (select manufacturer_auth_expiry from me)::date
    union all select 'establishment',     (select egr_doc_path from me),               (select egr_doc_name from me), null::date
  )
  select f.key,
         coalesce(f.path, b.path)                                  as path,
         coalesce(f.name, case when f.path is null then b.file_name end, regexp_replace(coalesce(f.path, b.path, ''), '^.*/', '')) as name,
         case when f.path is not null then f.expiry end            as expiry,
         case when f.path is not null then 'leads' when b.path is not null then 'supporting' end as source
  from fixed f left join best b on b.subject = f.key;
$function$;
revoke execute on function public.fn_supplier_document_home(bigint) from public, anon, authenticated;
comment on function public.fn_supplier_document_home(bigint) is
  'The one answer to "is this document on file" for a supplier: the leads column, else (for ISO, insurance, manufacturer authorisation) the newest live supporting document whose label names it. Read by fn_supplier_certifications, fn_supplier_document_impact, fn_supplier_twin and supplier_portal documents. Seat: it_engineer, 21 Sep 2026.';

-- ── 2. CERTIFICATIONS ─────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_certifications(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with docs(key, label, label_ar, impact, impact_why, impact_why_ar) as (values
      ('trade_licence',     'Trade licence',              'الرخصة التجارية',           'critical', 'Approval is impossible without it — the licence gate refuses every profile that has none.', 'لا يمكن اعتماد الحساب بدونها — بوابة الرخصة ترفض كل ملف لا يحملها.'),
      ('insurance',         'Insurance',                  'التأمين',                   'high',     'Many customers will not award work to an uninsured supplier.', 'كثير من العملاء لا يرسون العمل على مورّد غير مؤمَّن.'),
      ('iso',               'ISO certification',          'شهادة ISO',                 'medium',   'Strengthens your capability score and unlocks quality-gated requests.', 'تقوّي تقييم قدراتك وتفتح الطلبات المشروطة بالجودة.'),
      ('manufacturer_auth', 'Manufacturer authorisation', 'تفويض الشركة المصنّعة',     'medium',   'Proves you are authorised for the brands you carry.', 'تثبت أنك معتمد للعلامات التجارية التي تورّدها.'),
      ('establishment',     'Establishment card (EGR)',   'بطاقة المنشأة (EGR)',       'low',      'Administrative record. Does not gate work.', 'سجل إداري. لا يؤثر في استلام الأعمال.')
  ),
  held as (
    select d.*, h.path, h.expiry, h.source
    from docs d left join public.fn_supplier_document_home(p_lead_id) h on h.key = d.key
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'certifications', coalesce((select jsonb_agg(jsonb_build_object(
        'key', h.key, 'label', h.label, 'label_ar', h.label_ar,
        'held', h.path is not null,
        'source', h.source,
        'expiry', h.expiry,
        'days_left', case when h.expiry is null then null else (h.expiry - current_date) end,
        'document_status', case
          when h.path is null then 'missing'
          when h.expiry is null then 'valid'
          when h.expiry < current_date then 'expired'
          when h.expiry < current_date + 60 then 'expiring'
          else 'valid' end,
        'impact_level', h.impact,
        'impact_why', h.impact_why, 'impact_why_ar', h.impact_why_ar)
      order by case h.impact when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end, h.label)
      from held h), '[]'::jsonb),
    'impact_basis', 'impact_level is a stated QuotesDone policy about what each document gates — not a number derived from your history',
    'impact_basis_ar', 'مستوى الأثر سياسة معلنة لدى QuotesDone عمّا يفتحه كل مستند — وليس رقمًا مشتقًا من سجلك',
    'summary', jsonb_build_object(
      'held', (select count(*) from held where path is not null),
      'total', (select count(*) from held),
      'expired', (select count(*) from held where path is not null and expiry is not null and expiry < current_date),
      'expiring', (select count(*) from held where path is not null and expiry is not null
                     and expiry >= current_date and expiry < current_date + 60),
      'blocking_missing', (select count(*) from held where path is null and impact = 'critical'))
  );
$function$;

-- ── 3. WHAT EACH DOCUMENT UNLOCKS ─────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_document_impact(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (select * from public.leads where id = p_lead_id),
  flag as (select coalesce((select source from me), '') = 'qd_demo_fixture' as is_demo),
  mine as (select coalesce(sc.trades, '{}'::text[]) trades from public.supplier_capabilities sc where sc.supplier_id = p_lead_id),
  reachable as (
    select count(*) n from public.inquiries i, me, flag
    where i.status = 'open'
      and ((me.sector is not null and i.category = me.sector)
           or exists (select 1 from mine where i.trades && mine.trades))
      and (coalesce(i.brief_source, '') = 'qd_demo_fixture') = flag.is_demo
  ),
  priced as (
    select count(distinct q.inquiry_id) n from public.quotes q, flag
    where q.supplier_id = p_lead_id
      and (coalesce(q.source, '') = 'qd_demo_fixture') = flag.is_demo
  ),
  docs as (
    select h.key, case h.key when 'trade_licence' then 'Trade licence' when 'iso' then 'ISO certification'
                             when 'insurance' then 'Insurance' when 'manufacturer_auth' then 'Manufacturer authorisation'
                             when 'company_profile' then 'Company profile' end as label,
           h.path, h.expiry, h.source, h.key = 'trade_licence' as gates_matching
    from public.fn_supplier_document_home(p_lead_id) h
    where h.key in ('trade_licence', 'iso', 'insurance', 'manufacturer_auth', 'company_profile')
  ),
  scored as (
    select d.key, d.label, d.gates_matching, d.source,
           d.path is not null as on_file,
           d.expiry,
           coalesce(d.expiry < current_date, false) as expired,
           (d.path is not null and not coalesce(d.expiry < current_date, false)) as effective
    from docs d
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'open_in_my_trade', (select n from reachable),
    'basis', 'open enquiries in your trade, and the enquiries you have already priced',
    'documents', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'key', s.key, 'label', s.label, 'on_file', s.on_file, 'source', s.source,
        'expiry', s.expiry, 'expired', s.expired,
        'unlocked', case when s.effective then (select n from priced) else 0 end,
        'would_unlock', case when s.effective then 0 when s.gates_matching then (select n from reachable) else 0 end,
        'note', case
          when s.effective then 'On file and in force.'
          when s.expired and s.gates_matching then 'Expired. Renewing it reopens every open enquiry in your trade.'
          when s.expired then 'Expired. Customers see this as a gap when comparing you.'
          when s.gates_matching then 'Missing. It is the document that decides whether you can be matched at all.'
          else 'Missing. It is optional, but it is what a customer looks for when comparing two similar quotes.'
          end
      ) order by s.gates_matching desc, s.key), '[]'::jsonb)
      from scored s)
  );
$function$;

-- ── 4. THE TWIN ───────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_twin(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with l as (select * from public.leads where id = p_lead_id),
  s as (select *, quality_rating as q_pct from public.supplier_score where lead_id = p_lead_id),
  -- THE SUPPLIER'S OWN QUOTES, not the cache (#761): counted from public.quotes every time.
  q as (
    select count(*)::int submitted,
           greatest(count(*) filter (where status = 'won')::int,
                    (select count(*)::int from public.inquiries where hired_supplier_id = p_lead_id)) won
    from public.quotes where supplier_id = p_lead_id
  ),
  home as (select * from public.fn_supplier_document_home(p_lead_id)),
  caps as (
    select
      (select coalesce(jsonb_array_length(case when jsonb_typeof(l.machinery)='array' then l.machinery else '[]'::jsonb end), 0) > 0
              or l.capability_summary ilike '%manufactur%' from l)          as manufacturing,
      (select coalesce(l.engineers_count, 0) > 0
              or l.capability_summary ilike '%install%' from l)             as installation,
      (select l.capability_summary ilike '%maintenance%'
              or l.capability_summary ilike '%service%' from l)             as maintenance,
      (select l.capability_summary ilike '%design%' from l)                 as design
  ),
  conf as (
    select round(100.0 * (
        (case when l.company_name       is not null then 1 else 0 end)
      + (case when l.sector             is not null then 1 else 0 end)
      + (case when l.capability_summary is not null then 1 else 0 end)
      + (case when l.founded_year        is not null then 1 else 0 end)
      + (case when l.employee_count      is not null or l.team_size is not null then 1 else 0 end)
      + (case when coalesce(array_length(l.service_emirates, 1), 0) > 0 then 1 else 0 end)
      + (case when coalesce(l.certifications, '') <> ''
                or (jsonb_typeof(l.iso_certifications)='array' and jsonb_array_length(l.iso_certifications) > 0) then 1 else 0 end)
      + (case when l.products is not null and l.products <> '' then 1 else 0 end)
      + (case when l.website is not null then 1 else 0 end)
      + (case when l.description is not null then 1 else 0 end)
      ) / 10.0) as pct
    from l
  ),
  -- RISK IS A VERDICT, so it needs a measurement: a licence on file (its expiry is the estate's own
  -- block reason), a ban or a block, a strike, or a computed reliability. With none of these the
  -- honest answer is NULL, and risk_basis says what would produce one.
  risk as (
    select case
      when l.banned then 'BANNED'
      when l.matching_blocked then 'BLOCKED'
      when (select path from home where key = 'trade_licence') is null
           and coalesce(l.chat_strikes, 0) = 0 and (select reliability from s) is null then null
      when l.license_expiry is not null and l.license_expiry < current_date then 'HIGH'
      when (select expiry from home where key = 'iso') < current_date then 'HIGH'
      when l.license_expiry is not null and l.license_expiry < current_date + 60 then 'MEDIUM'
      when coalesce(l.chat_strikes, 0) > 0 then 'MEDIUM'
      when (select reliability from s) is not null and (select reliability from s) < 60 then 'MEDIUM'
      else 'LOW' end as level
    from l
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'company_name', (select company_name from l),
    'verified', (select coalesce(verified, false) from l),
    'approval_status', (select approval_status from l),
    'intelligence_score', (
      select round(avg(v)) from (
        select (select q_pct from s) as v
        union all select (select reliability    from s)
        union all select (select response_rate  from s)
        union all select (select price_index    from s)
      ) t where v is not null
    ),
    'star_rating', (
      select case when avg(v) is null then null else greatest(1, least(5, round(avg(v) / 20.0))) end
      from (
        select (select q_pct from s) as v
        union all select (select reliability   from s)
        union all select (select response_rate from s)
      ) t where v is not null
    ),
    'health', jsonb_build_object(
      'quality', (select q_pct from s),
      'quality_raw',   (select quality_rating from s),
      'quality_scale', (select case when quality_rating is null then 'unrated' else 'earned_pct' end from s),
      'delivery', (select reliability    from s),
      'response', coalesce((select response_rate from s), (select rv_response_rate from l)),
      'pricing',  (select price_index    from s),
      'overall', (
        select round(avg(v)) from (
          select (select q_pct from s) as v
          union all select (select reliability   from s)
          union all select (select response_rate from s)
          union all select (select price_index   from s)
        ) t where v is not null
      ),
      'computed_at',        (select computed_at        from s),
      'avg_response_hours', (select avg_response_hours from s),
      'quotes_submitted',   (select submitted from q),
      'quotes_won',         (select won from q)
    ),
    'company_strength', (select capability_score from l),
    'capabilities', (
      select jsonb_build_array(
        jsonb_build_object('name', 'Manufacturing', 'has', (select manufacturing from caps)),
        jsonb_build_object('name', 'Installation',  'has', (select installation  from caps)),
        jsonb_build_object('name', 'Maintenance',   'has', (select maintenance   from caps)),
        jsonb_build_object('name', 'Design',        'has', (select design        from caps))
      )
    ),
    'product_count', (
      select case when l.products is null or l.products = '' then 0
             else array_length(string_to_array(l.products, ','), 1) end from l
    ),
    'certifications', (
      select (case when jsonb_typeof(l.iso_certifications)='array' then l.iso_certifications else '[]'::jsonb end)
          || (case when coalesce(l.certifications,'') = '' then '[]'::jsonb
                   else to_jsonb(string_to_array(l.certifications, ',')) end) from l
    ),
    'production_capacity', (
      select jsonb_build_object(
        'estimated', case
          when l.team_size is null and l.engineers_count is null and l.warehouse_area is null then null
          else coalesce(l.team_size, 0) * 40 + coalesce(l.engineers_count, 0) * 120
               + coalesce(round(nullif(regexp_replace(coalesce(l.warehouse_area,''), '[^0-9]', '', 'g'), '')::numeric / 10.0), 0) end,
        'is_estimate', true,
        'basis', jsonb_build_object('team_size', l.team_size, 'engineers', l.engineers_count,
                                    'warehouse_area', l.warehouse_area,
                                    'machinery_lines', coalesce(jsonb_array_length(case when jsonb_typeof(l.machinery)='array' then l.machinery else '[]'::jsonb end), 0))
      ) from l
    ),
    'best_opportunities', (
      select case when coalesce(l.categories,'') = '' then '[]'::jsonb
                  else to_jsonb(string_to_array(l.categories, ',')) end from l
    ),
    'risk_level', (select level from risk),
    'risk_basis', case when (select level from risk) is null
                       then 'not assessed: no trade licence on file and no history yet'
                       else 'trade licence and certificate expiry, bans, strikes and computed reliability' end,
    'established_year', (select founded_year from l),
    'employee_count',   (select coalesce(l.employee_count, l.team_size) from l),
    -- The emirates the supplier serves. `countries` is kept for older clients; same value.
    'emirates',         (select coalesce(to_jsonb(coalesce(l.service_emirates, '{}'::text[])), '[]'::jsonb) from l),
    'countries',        (select coalesce(to_jsonb(coalesce(l.service_emirates, '{}'::text[])), '[]'::jsonb) from l),
    'ai_confidence',    (select pct from conf),
    'capability_map', (
      select jsonb_build_object(
        'root', coalesce(l.sector, 'Supplier'),
        'children', (
          select jsonb_agg(jsonb_build_object('name', c.name))
          from (
            select 'Manufacturing' as name where (select manufacturing from caps)
            union all select 'Installation' where (select installation from caps)
            union all select 'Maintenance'  where (select maintenance  from caps)
            union all select 'Design'       where (select design       from caps)
          ) c
        )
      ) from l
    ),
    -- Per-document status from the ONE home, so this cannot disagree with Documents or Certifications.
    'documents', (
      select jsonb_agg(jsonb_build_object(
        'kind', case h.key when 'trade_licence' then 'Trade licence' when 'iso' then 'ISO certification' else 'Manufacturer authorisation' end,
        'key', h.key, 'expiry', h.expiry, 'source', h.source,
        'doc_status', case when h.path is null then 'MISSING'
                           when h.expiry is null then 'UNDATED'
                           when h.expiry < current_date then 'EXPIRED'
                           else 'VALID' end)
        order by case h.key when 'trade_licence' then 0 when 'iso' then 1 else 2 end)
      from home h where h.key in ('trade_licence', 'iso', 'manufacturer_auth')
    ),
    'is_demo', (select coalesce(l.matching_blocked, false)
                       and coalesce(array_to_string(l.tags, ','), '') ilike '%demo%' from l),
    'matchable', (select public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                          l.approval_status, l.permanently_closed, l.chat_strikes) from l)
  );
$function$;

-- ── 5. THE MARKET, THROUGH THE ROWS MATCHING READS ────────────────────────────────────────────────
create or replace function public.fn_supplier_market(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (select * from public.leads where id = p_lead_id),
  flag as (select coalesce((select source from me), '') = 'qd_demo_fixture' as is_demo),
  -- This supplier's trades: what it CONFIRMED in supplier_capabilities, plus its sector code.
  mine as (
    select array_remove(array_cat(coalesce((select trades from public.supplier_capabilities where supplier_id = p_lead_id), '{}'::text[]),
                                  array[(select sector from me)]), null) as trades
  ),
  -- Competitors: any lead whose confirmed trades overlap this supplier's (the population
  -- fn_customer_decision_support counts as "suppliers covering this trade"), or whose sector string
  -- equals this supplier's. Same side of the demo fence, never self.
  peers as (
    select l.*
    from public.leads l, me, flag, mine
    where l.id <> me.id
      and coalesce(l.permanently_closed, false) = false
      and (coalesce(l.source, '') = 'qd_demo_fixture') = flag.is_demo
      and ((l.sector is not null and me.sector is not null and l.sector = me.sector)
           or exists (select 1 from public.supplier_capabilities sc where sc.supplier_id = l.id and sc.trades && mine.trades))
  ),
  peers_here as (
    select p.* from peers p, me
    where me.service_emirates is null
       or coalesce(array_length(me.service_emirates, 1), 0) = 0
       or p.emirate is null
       or exists (select 1 from unnest(me.service_emirates) e where p.emirate ilike '%' || e || '%')
  ),
  demand_all as (
    select i.* from public.inquiries i, flag
    where (coalesce(i.brief_source, '') = 'qd_demo_fixture') = flag.is_demo
      and i.created_at >= now() - interval '28 days'
  ),
  -- An enquiry in this supplier's category: its trades overlap, or its category names one of them.
  demand_mine as (
    select d.* from demand_all d, mine, me
    where (d.trades is not null and d.trades && mine.trades)
       or (d.category is not null and (d.category = any (mine.trades) or public.fn_norm_trades(d.category) && mine.trades))
  ),
  priced as (
    select q.quote_amount amt
    from public.quotes q join demand_mine d on d.id = q.inquiry_id, flag
    where (coalesce(q.source, '') = 'qd_demo_fixture') = flag.is_demo
      and q.quote_amount is not null and q.quote_amount > 0
  ),
  figures as (
    select
      (with c as (
         select count(*) filter (where created_at >= now() - interval '14 days') as recent,
                count(*) filter (where created_at <  now() - interval '14 days') as earlier
         from demand_mine)
       select case when c.recent = 0 and c.earlier = 0
         then jsonb_build_object(
                'available', false, 'value', null, 'direction', null,
                'basis', 'enquiries in your category over the last 28 days',
                'population', 0,
                'note', 'no enquiries in your category yet, so there is no series to trend')
         else jsonb_build_object(
                'available', true,
                'category', (select sector from me),
                'value', c.recent,
                'prior', c.earlier,
                'direction', case when c.recent > c.earlier then 'up'
                                  when c.recent < c.earlier then 'down' else 'flat' end,
                'pct', case when c.earlier > 0
                            then round(((c.recent - c.earlier)::numeric / c.earlier) * 100, 1)
                            else null end,
                'from_zero', c.earlier = 0,
                'share_pct', case when (select count(*) from demand_all) > 0
                             then round((c.recent::numeric
                                  / nullif((select count(*) from demand_all), 0)) * 100, 1)
                             else null end,
                'series', (
                  select coalesce(jsonb_agg(jsonb_build_object('week', w.wk, 'count', w.c) order by w.wk), '[]'::jsonb)
                  from (select date_trunc('week', created_at)::date wk, count(*) c
                        from demand_mine group by 1) w),
                'basis', 'enquiries in your category, two 14-day halves',
                'population', (select count(*) from demand_mine),
                'note', case when c.earlier = 0
                        then 'first activity in this window, so there is no prior period to take a percentage against'
                        else null end)
         end from c) as trend_obj,
      (with r as (select category cat, count(*) c from demand_all
                  where category is not null group by 1 order by count(*) desc limit 1)
       select case when not exists (select 1 from r)
         then jsonb_build_object(
                'available', false, 'value', null,
                'basis', 'enquiries over the last 28 days',
                'population', (select count(*) from demand_all),
                'note', 'that is a fact about requests, and none have been made')
         else jsonb_build_object(
                'available', true,
                'value', (select cat from r),
                'count', (select c from r),
                'basis', 'enquiries over the last 28 days, grouped by category',
                'population', (select count(*) from demand_all))
         end) as topcat_obj,
      (with s as (
         select count(*) n, round(avg(amt)) mean,
                round(percentile_cont(0.5)  within group (order by amt)) mid,
                round(percentile_cont(0.25) within group (order by amt)) lo,
                round(percentile_cont(0.75) within group (order by amt)) hi,
                min(amt) lowest, max(amt) highest
         from priced)
       select case when s.n = 0
         then jsonb_build_object(
                'available', false, 'value', null, 'currency', 'AED',
                'basis', 'quotes on enquiries in your category',
                'population', 0,
                'note', 'nothing in your category has been priced, so there is no market price')
         else jsonb_build_object(
                'available', true, 'currency', 'AED',
                'value', s.mean, 'median', s.mid, 'p25', s.lo, 'p75', s.hi,
                'low', s.lowest, 'high', s.highest,
                'basis', 'quotes on enquiries in your category over the last 28 days',
                'population', s.n)
         end from s) as money_obj
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'sector', (select sector from me),
    'trades', (select to_jsonb(trades) from mine),
    'population', case when (select is_demo from flag) then 'demo' else 'live' end,
    'competitors', jsonb_build_object(
      'available', true,
      'basis', 'suppliers whose confirmed trades overlap yours, or share your sector',
      'total', (select count(*) from peers),
      'in_my_area', (select count(*) from peers_here),
      'matchable', (
        select count(*) from peers p
        where public.fn_is_matchable(p.verified, p.banned, p.matching_blocked,
                                     p.approval_status, p.permanently_closed, p.chat_strikes)
          and exists (select 1 from public.supplier_capabilities sc
                      where sc.supplier_id = p.id and sc.confirmed_at is not null)
      ),
      'me_matchable', (
        select public.fn_is_matchable(m.verified, m.banned, m.matching_blocked,
                                      m.approval_status, m.permanently_closed, m.chat_strikes)
           and exists (select 1 from public.supplier_capabilities sc
                       where sc.supplier_id = m.id and sc.confirmed_at is not null)
        from public.leads m where m.id = p_lead_id
      ),
      'by_emirate', (
        select coalesce(jsonb_agg(jsonb_build_object('emirate', s.em, 'count', s.c) order by s.c desc), '[]'::jsonb)
        from (
          select p.emirate as em, count(*) as c
          from peers p where p.emirate is not null
          group by p.emirate order by count(*) desc limit 8
        ) s
      )
    ),
    'market_composition', jsonb_build_object(
      'available', true,
      'basis', 'competitors, grouped by category',
      'segments', (
        select coalesce(jsonb_agg(jsonb_build_object('name', s.nm, 'count', s.c) order by s.c desc), '[]'::jsonb)
        from (
          select coalesce(nullif(btrim(split_part(p.categories, ',', 1)), ''), coalesce(p.sector, 'Uncategorised')) as nm,
                 count(*) as c
          from peers p group by 1 order by count(*) desc limit 8
        ) s
      )
    ),
    'demand_trend',     (select trend_obj  from figures),
    'most_requested',   (select topcat_obj from figures),
    'avg_market_price', (select money_obj  from figures)
  );
$function$;

-- ── 6. THE KNOWLEDGE GRAPH KNOWS THE CONFIRMED TRADES ─────────────────────────────────────────────
create or replace function public.fn_supplier_knowledge_graph(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with mine as (
    select lc.slug, lc.is_primary, lc.score, 'lead_category' as src
    from lead_category lc where lc.lead_id = p_lead_id
    union
    select t, false, null::numeric, 'confirmed_trade'
    from public.supplier_capabilities sc, unnest(coalesce(sc.trades, '{}'::text[])) t
    where sc.supplier_id = p_lead_id
      and not exists (select 1 from lead_category lc where lc.lead_id = p_lead_id and lc.slug = t)
  ),
  neigh as (
    select case when e.src_ref = m.slug then e.dst_ref else e.src_ref end as slug,
           (e.props->>'companies')::int as companies
    from graph_edges e join mine m on m.slug in (e.src_ref, e.dst_ref)
    where e.rel = 'adjacent_to' and e.src_kind = 'category'
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'basis', 'the trades this company confirmed and the categories it is listed in, and the categories its competitors also serve',
    'my_categories', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'slug', m.slug,
        'label', coalesce((select n.label from graph_nodes n where n.kind='category' and n.ref_id=m.slug),
                          (select t.label from public.taxonomy_trade t where t.code = m.slug),
                          replace(m.slug, '_', ' ')),
        'label_ar', (select t.label_ar from public.taxonomy_trade t where t.code = m.slug),
        'companies', coalesce((select (n.props->>'companies')::int from graph_nodes n where n.kind='category' and n.ref_id=m.slug),
                              (select count(*)::int from public.supplier_capabilities sc where sc.trades && array[m.slug])),
        'primary', m.is_primary, 'source', m.src) order by m.is_primary desc nulls last, m.slug), '[]'::jsonb)
      from mine m),
    'adjacent', (
      select coalesce(jsonb_agg(x order by x->'shared_companies' desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'slug', nb.slug,
          'label', (select n.label from graph_nodes n where n.kind='category' and n.ref_id=nb.slug),
          'shared_companies', max(nb.companies),
          'companies', (select (n.props->>'companies')::int from graph_nodes n where n.kind='category' and n.ref_id=nb.slug)
        ) x
        from neigh nb
        where nb.slug not in (select slug from mine)
        group by nb.slug
        order by max(nb.companies) desc
        limit 12) s),
    'population', jsonb_build_object(
      'category_nodes', (select count(*) from graph_nodes where kind='category'),
      'adjacency_edges', (select count(*) from graph_edges where rel='adjacent_to' and src_kind='category'),
      'listed_companies', (select count(distinct lead_id) from lead_category))
  );
$function$;

-- ── 7. THE ADVISOR READS THE SUPPLIER'S REAL QUOTES ───────────────────────────────────────────────
create or replace function public.fn_supplier_advisor(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with l as (select * from public.leads where id = p_lead_id),
  s as (select * from public.supplier_score where lead_id = p_lead_id),
  q as (
    select count(*)::int submitted,
           greatest(count(*) filter (where status = 'won')::int,
                    (select count(*)::int from public.inquiries where hired_supplier_id = p_lead_id)) won,
           count(*) filter (where status in ('rejected', 'lost', 'declined'))::int rejected
    from public.quotes where supplier_id = p_lead_id
  ),
  rr as (select coalesce((select rv_response_rate from l), (select response_rate from s)) rate),
  home as (select * from public.fn_supplier_document_home(p_lead_id)),
  cap as (select confirmed_at from public.supplier_capabilities where supplier_id = p_lead_id),
  live_inq as (
    select count(*) as n from public.inquiries i
    where coalesce(i.status, '') not in ('closed', 'cancelled', 'expired')
  ),
  gaps as (
    select g.* from (
      select 'trade_licence' as key, 'Upload your trade licence' as action, 'ارفع رخصتك التجارية' as action_ar,
             'You cannot be matched to any opportunity without a current trade licence.' as why,
             'لا يمكن مطابقتك مع أي فرصة بدون رخصة تجارية سارية.' as why_ar,
             'high' as severity, 'documents' as goes_to, 1 as sort
      where (select path from home where key = 'trade_licence') is null
      union all
      select 'licence_expired', 'Replace your expired trade licence', 'استبدل رخصتك التجارية المنتهية',
             'Your trade licence expired on ' || to_char(l.license_expiry, 'DD Mon YYYY') || '.',
             'انتهت رخصتك التجارية في ' || to_char(l.license_expiry, 'DD Mon YYYY') || '.',
             'high', 'documents', 2
      from l where (select path from home where key = 'trade_licence') is not null
                and l.license_expiry is not null and l.license_expiry < current_date
      union all
      select 'iso_certificate', 'Upload an ISO certificate', 'ارفع شهادة ISO',
             'Buyers filter on ISO 9001 and 14001. Adding one opens the projects that require it.',
             'يرشّح المشترون على ISO 9001 و14001. إضافتها تفتح المشاريع التي تشترطها.',
             'medium', 'documents', 3
      where (select path from home where key = 'iso') is null
      union all
      select 'iso_expired', 'Renew your ISO certificate', 'جدّد شهادة ISO',
             'Your ISO certificate expired on ' || to_char((select expiry from home where key = 'iso'), 'DD Mon YYYY') || '.',
             'انتهت شهادة ISO في ' || to_char((select expiry from home where key = 'iso'), 'DD Mon YYYY') || '.',
             'high', 'documents', 4
      where (select expiry from home where key = 'iso') < current_date
      union all
      select 'not_verified', 'Complete verification', 'أكمل التحقق',
             'Unverified suppliers are excluded from matching entirely.',
             'المورّدون غير المتحقَّق منهم مستبعدون من المطابقة كليًا.',
             'high', 'profile', 5
      from l where not coalesce(l.verified, false)
      union all
      -- The gate matching actually opens on (fn_match_capability: confirmed_at), pointed at the tab
      -- where it is confirmed. This replaced a "capability summary" gap that named a machine-filled
      -- column the supplier has no field for (audit 21 Sep 2026, finding 20).
      select 'services_unconfirmed', 'Confirm your services', 'أكّد خدماتك',
             'Requests are matched on the services you confirm. Nothing reaches you until they are confirmed.',
             'تُطابَق الطلبات على الخدمات التي تؤكّدها. لا يصلك شيء قبل تأكيدها.',
             'high', 'services', 6
      where (select confirmed_at from cap) is null
      union all
      select 'no_products', 'Upload a product catalogue', 'ارفع كتالوج المنتجات',
             'Your catalogue is what buyers search. Without it you compete on company name alone.',
             'الكتالوج هو ما يبحث فيه المشترون. بدونه تنافس باسم الشركة فقط.',
             'medium', 'products', 7
      from l where not exists (select 1 from public.supplier_product sp where sp.supplier_id = l.id)
      union all
      select 'no_service_area', 'Set the emirates you serve', 'حدّد الإمارات التي تخدمها',
             'Opportunities are filtered by location before anything else is considered.',
             'تُرشَّح الفرص حسب الموقع قبل أي اعتبار آخر.',
             'medium', 'profile', 8
      from l where coalesce(array_length(l.service_emirates, 1), 0) = 0
      union all
      select 'slow_response', 'Improve your response time', 'حسّن سرعة استجابتك',
             'Your response rate is ' || round((select rate from rr))::text || '%. Buyers see it, and it is 55% of your reliability score.',
             'معدل استجابتك ' || round((select rate from rr))::text || '%. يراه المشترون، وهو 55% من تقييم موثوقيتك.',
             'medium', 'twin', 9
      where (select rate from rr) is not null and (select rate from rr) < 60
    ) g
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'loss_analysis', jsonb_build_object(
      'quotes_submitted', (select submitted from q),
      'quotes_won',       (select won from q),
      'rejections',       (select rejected from q),
      'response_rate',    (select rate from rr),
      'loss_reasons', case
        when (select submitted from q) = 0 then '[]'::jsonb
        else jsonb_build_array(
          jsonb_build_object('reason', 'Rejected after quoting', 'reason_ar', 'رُفض بعد التسعير', 'count', (select rejected from q),
            'pct', round(100.0 * (select rejected from q) / nullif((select submitted from q), 0)))
        ) end,
      'basis', case when (select submitted from q) = 0 then 'no_completed_opportunities' else 'quotes_submitted' end
    ),
    'recommendations', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'key', g.key, 'action', g.action, 'action_ar', g.action_ar, 'why', g.why, 'why_ar', g.why_ar,
        'severity', g.severity, 'goes_to', g.goes_to,
        'impact_rfqs', (select n from live_inq)
      ) order by g.sort), '[]'::jsonb) from gaps g
    ),
    'gap_count', (select count(*) from gaps),
    'impact_basis', jsonb_build_object(
      'live_inquiries', (select n from live_inq),
      'note', 'impact_rfqs counts live inquiries a closed gap would let this supplier compete for'
    ),
    'headline', (
      select case
        when (select count(*) from gaps) = 0
          then 'Your profile is complete. You are eligible for every opportunity we can match.'
        when (select n from live_inq) = 0
          then 'You have ' || (select count(*) from gaps)::text
               || ' gap(s) blocking you from being matched at all. Start with: '
               || (select g.action from gaps g order by g.sort limit 1)
               || '. There are no live opportunities right now, so there is time to fix them.'
        else 'Your profile can qualify for ' || (select n from live_inq)::text
             || ' more opportunities if you close ' || (select count(*) from gaps)::text
             || ' gap(s), starting with: ' || (select g.action from gaps g order by g.sort limit 1) || '.'
      end
    ),
    'headline_ar', (
      select case
        when (select count(*) from gaps) = 0
          then 'ملفك مكتمل. أنت مؤهّل لكل فرصة يمكننا مطابقتها.'
        when (select n from live_inq) = 0
          then 'لديك ' || (select count(*) from gaps)::text
               || ' ثغرة (ثغرات) تمنع مطابقتك أصلًا. ابدأ بـ: '
               || (select g.action_ar from gaps g order by g.sort limit 1)
               || '. لا توجد فرص حية الآن، فهناك وقت لمعالجتها.'
        else 'يمكن لملفك التأهّل لـ ' || (select n from live_inq)::text
             || ' فرصة إضافية إذا أغلقت ' || (select count(*) from gaps)::text
             || ' ثغرة (ثغرات)، بدءًا بـ: ' || (select g.action_ar from gaps g order by g.sort limit 1) || '.'
      end
    )
  );
$function$;

-- ── PROOF ─────────────────────────────────────────────────────────────────────────────────────────
-- A lead id that cannot exist: every routine must answer with its keys present and nothing raised.
with probe as (
  select public.fn_supplier_certifications(-1) c, public.fn_supplier_document_impact(-1) d,
         public.fn_supplier_twin(-1) t, public.fn_supplier_market(-1) m,
         public.fn_supplier_knowledge_graph(-1) k, public.fn_supplier_advisor(-1) a,
         (select count(*) from public.fn_supplier_document_home(-1)) h
)
select case
  when h = 6
   and (select jsonb_agg(x->>'key' order by x->>'key') from jsonb_array_elements(c->'certifications') x)
       = '["establishment","insurance","iso","manufacturer_auth","trade_licence"]'::jsonb
   and c ? 'summary' and d ? 'documents' and t ? 'risk_basis' and t ? 'emirates'
   and (t->>'risk_level') is null
   and m ? 'competitors' and m ? 'trades' and k ? 'my_categories'
   and a ? 'headline_ar' and (a->'loss_analysis'->>'quotes_submitted') = '0'
  then 'PROBE OK: 7 routines answer for a non-existent lead; certifications carry the five document subjects and neither VAT nor IBAN; risk_level is null with no measurement'
  else 'PROBE FAILED: ' || jsonb_build_object('home', h, 'certs', c->'certifications', 'twin_risk', t->'risk_level', 'twin_keys', t ? 'emirates', 'market', m ? 'trades', 'kg', k ? 'my_categories', 'advisor', a ? 'headline_ar')::text
end as verdict
from probe;
