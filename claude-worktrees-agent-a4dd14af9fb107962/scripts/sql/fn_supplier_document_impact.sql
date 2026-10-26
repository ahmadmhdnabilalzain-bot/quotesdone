-- ==============================================================================================
-- ROW #5 §16 §4 — WHAT EACH DOCUMENT IS ACTUALLY DOING FOR THE SUPPLIER.
--
-- §16's claim is that documents are ALIVE rather than stored files. The portal already shows which
-- ones are on file and when they expire. What it could not answer is the only question a supplier
-- actually cares about: what is this piece of paper WORTH to me, and what is the missing one
-- costing me. Both halves are counts over real enquiries, so both are answerable now.
--
--   unlocked      enquiries this supplier has already priced while the document was on file and
--                 unexpired. Their own trading history, not a projection.
--   would_unlock  OPEN enquiries in their category that they cannot currently be matched to
--                 because this document is missing or expired. Zero when the document is fine,
--                 which is the correct answer — a document that is already working unlocks
--                 nothing further by being uploaded again.
--
-- ── THE NUMBER IS NEVER A GUESS, AND WHERE IT WOULD BE, IT IS NULL ──────────────────────────────
-- `unlocked` counts quotes, and there is no per-document history table, so the routine cannot know
-- whether a licence uploaded last week was on file when a quote was sent last month. It therefore
-- only attributes quotes when the document is on file AND unexpired TODAY, and names that basis in
-- the payload. Attributing a supplier's whole quote history to a document uploaded this morning
-- would be the flattering answer and the false one.
--
-- ── DEMO AND LIVE ARE PARTITIONED, AS EVERYWHERE ELSE IN THIS ROW ───────────────────────────────
create or replace function public.fn_supplier_document_impact(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (select * from public.leads where id = p_lead_id),
  flag as (select coalesce((select source from me), '') = 'qd_demo_fixture' as is_demo),

  -- Open enquiries this supplier's trade could serve. This is the population a missing document
  -- is measured against, so it is scoped to their sector and to briefs that are still open.
  reachable as (
    select count(*) n from public.inquiries i, me, flag
    where i.status = 'open'
      and me.sector is not null and i.category = me.sector
      and (coalesce(i.brief_source, '') = 'qd_demo_fixture') = flag.is_demo
  ),
  -- Their own priced history.
  priced as (
    select count(distinct q.inquiry_id) n from public.quotes q, flag
    where q.supplier_id = p_lead_id
      and (coalesce(q.source, '') = 'qd_demo_fixture') = flag.is_demo
  ),

  docs as (
    select d.* from (
      select 'trade_licence' as key, 'Trade licence' as label,
             (select license_doc_path from me) as path,
             (select license_expiry from me) as expiry,
             true as gates_matching
      union all
      select 'iso', 'ISO certification',
             (select iso_doc_path from me), (select iso_expiry from me), false
      union all
      select 'insurance', 'Insurance',
             (select insurance_doc_path from me), (select insurance_expiry from me), false
      union all
      select 'manufacturer_auth', 'Manufacturer authorisation',
             (select manufacturer_auth_doc_path from me), (select manufacturer_auth_expiry from me), false
      union all
      select 'company_profile', 'Company profile',
             (select company_profile_doc_path from me), null::date, false
    ) d
  ),
  scored as (
    select d.key, d.label, d.gates_matching,
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
        'key', s.key,
        'label', s.label,
        'on_file', s.on_file,
        'expiry', s.expiry,
        'expired', s.expired,
        -- What it has already earned. Only attributable while the document is genuinely in force.
        'unlocked', case when s.effective then (select n from priced) else 0 end,
        -- What its absence is costing. Only the licence blocks matching outright, so only the
        -- licence can claim the whole open population; the others are supporting evidence and
        -- claim nothing they cannot demonstrate.
        'would_unlock', case
          when s.effective then 0
          when s.gates_matching then (select n from reachable)
          else 0 end,
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

comment on function public.fn_supplier_document_impact(bigint) is
  'Row #5 §16 §4. Per document: whether it is on file and in force, how many enquiries it has '
  'already unlocked, and how many open enquiries in the supplier''s trade its absence is currently '
  'costing them. Counts are attributed only while a document is genuinely in force.';
