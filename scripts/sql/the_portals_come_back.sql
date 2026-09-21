-- THE PORTALS COME BACK. The sweep took eight edge functions the live product calls.
--
-- PR #530 deleted 137 edge functions under the founder's rule that what belongs to neither the CEO,
-- the customer-support agent nor the website does not exist. Eight of them belong to the WEBSITE, and
-- that rule protected them: they are the customer and supplier portals' entire backend.
--
-- HOW THE MISTAKE WAS MADE, because it should not be repeatable. Ownership was taken from
-- public.function_owner, and function_owner was built by reading the LIVE DEPLOYMENT LIST. By the
-- time it was written those eight were already deleted, so they had no row, so nothing was unowned,
-- so the check that exists to catch exactly this confirmed a set that had already lost them. A
-- registry derived from the thing it is meant to check cannot catch the thing being missing.
--
-- MEASURED, not inferred. curl against production returns 404 for customer_api, supplier_api and
-- messages_api, and 401 for customer_portal -- the 401 is what proves the 404s are genuine absence
-- rather than an auth artefact. A customer on /me today cannot post an RFQ, see a quote, reveal a
-- supplier, pay, or ask for a refund: every one of those buttons POSTs to a 404.
--
--     customer_api              19 call sites in CustomerPortal.tsx
--     supplier_api              19 call sites in SupplierPortal.tsx
--     supplier_portal           23 call sites across components/portal/supplier/*
--     messages_api              18 call sites across both portals
--     inquiry_intake            the RFQ brief
--     quote_compare             the comparison screen
--     supplier_onboard          supplier registration
--     supplier_catalog_ingest   supplier catalogue upload
--
-- PR #531 then retired twelve routines those functions call, for the same reason and by the same
-- mistake: with their callers already deleted they measured as unreachable. This file brings the
-- routines back; the eight functions are restored from 182308b^ in the same change.
--
-- The bodies are the exact text from supabase/schema/full_schema.sql at 7f94006^ -- the mirror of
-- production as it stood before the drop -- so nothing here is rewritten from memory.
--
-- The founder's instruction, twice on 8 September: "website content shouldnt be touched", and
-- website content "remains". The portals are the website.
--
--   node scripts/apply_sql.mjs scripts/sql/the_portals_come_back.sql --apply --ddl

begin;

-- fn_category_expert_ref -- called by a portal edge function that PR #530 deleted and this change restores
CREATE OR REPLACE FUNCTION public.fn_category_expert_ref(p_category text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_slug text; v_txt text;
begin
  v_slug := case
    when p_category ~* 'cctv|security|surveillance' then 'cctv-security'
    when p_category ~* 'hvac|air.?con|ac-' then 'ac-maintenance'
    when p_category ~* 'duct' then 'ac-duct-cleaning'
    when p_category ~* 'glass|glaz|alumin' then 'aluminium-glass'
    when p_category = 'carpentry' then 'carpentry-joinery'
    when p_category ~* 'joinery|kitchen' then 'joinery-kitchens'
    when p_category ~* 'tiling|tile|marble|granite' then 'tiling-marble'
    when p_category ~* 'gypsum|false.?ceiling|ceiling' then 'false-ceiling'
    when p_category ~* 'upholstery|blind|curtain' then 'curtains-blinds'
    when p_category ~* 'fit.?out' then 'commercial-retail-fitout'
    when p_category ~* 'combined.?mep|^mep$' then 'combined-mep'
    when p_category ~* 'steel|fabrication' then 'structural-steel-fabrication'
    when p_category ~* 'pest' then 'pest-control'
    when p_category ~* 'tent|shade' then 'tents-and-shade-structures'
    when p_category ~* 'general|other|handyman|facilit' then coalesce(
        (select 'general-services-other' where exists (select 1 from agent_knowledge where agent_key='cat:general-services-other')), p_category)
    else p_category end;
  select string_agg('## '||topic||E'\n'||content, E'\n\n')
    into v_txt from agent_knowledge
    where agent_key = 'cat:'||v_slug
      and topic in ('Pricing benchmarks & red flags','Quote analysis & comparison',
                    'Standards, materials & specifications','Field expertise — UAE codes, standards & specs');
  return left(coalesce(v_txt,''), 4500);
end $function$;

-- kb_query -- called by a portal edge function that PR #530 deleted and this change restores
CREATE OR REPLACE FUNCTION public.kb_query(p_query text, p_category text DEFAULT NULL::text, p_limit integer DEFAULT 8)
 RETURNS TABLE(source_kind text, category text, title text, snippet text, citation text, effective_date date, rank real)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with q as (select websearch_to_tsquery('english', coalesce(p_query,'')) as tsq)
  select c.source_kind, c.category, c.title, left(c.content, 700) as snippet, c.citation, c.effective_date,
    (ts_rank(c.fts, q.tsq) + case when p_category is not null and c.category = p_category then 0.4 else 0 end)::real as rank
  from kb_chunks c, q
  where coalesce(p_query,'') = '' or c.fts @@ q.tsq
  order by rank desc nulls last, c.effective_date desc nulls last
  limit greatest(1, least(coalesce(p_limit,8), 25));
$function$;

-- fn_edit_inquiry -- called by a portal edge function that PR #530 deleted and this change restores
CREATE OR REPLACE FUNCTION public.fn_edit_inquiry(p_inquiry uuid, p_customer uuid, p_patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v inquiries%rowtype; v_paid boolean; v_deadline timestamptz;
  v_material boolean := false; v_reason text; v_stale int := 0; v_notified int := 0;
  v_cust_email text; v_admin text;
begin
  select * into v from inquiries where id=p_inquiry;
  if not found then return jsonb_build_object('error','inquiry_not_found'); end if;
  if p_customer is not null and v.customer_id is distinct from p_customer then
    return jsonb_build_object('error','not_your_inquiry'); end if;
  select exists(select 1 from transactions where inquiry_id=p_inquiry) into v_paid;
  if v_paid or v.status in ('revealed','completed','cancelled','closed') or v.pipeline_stage in ('revealed','won','cancelled') then
    return jsonb_build_object('error','not_editable','status',v.status,
      'message','This request can no longer be edited.'); end if;
  v_deadline := v.created_at + interval '1 hour';
  if now() > v_deadline then
    return jsonb_build_object('error','edit_window_closed','editable_until',v_deadline,
      'message','Inquiries can be edited within 1 hour of submitting. Please create a new request for changes after that.'); end if;

  -- Decide materiality BEFORE the update, while the old row is still in hand.
  v_material :=
       (p_patch ? 'spec'       and (p_patch->'spec')       is distinct from v.spec)
    or (p_patch ? 'boq'        and (p_patch->'boq')        is distinct from v.boq)
    or (p_patch ? 'budget'     and (p_patch->>'budget')    is distinct from v.budget)
    or (p_patch ? 'scope_type' and (p_patch->>'scope_type') is distinct from v.scope_type)
    or (p_patch ? 'emirate'    and (p_patch->>'emirate')   is distinct from v.emirate)
    or (p_patch ? 'trades'     and array(select jsonb_array_elements_text(p_patch->'trades')) is distinct from v.trades);

  update inquiries set
    summary   = coalesce(p_patch->>'summary', summary),
    raw_input = coalesce(p_patch->>'raw_input', raw_input),
    budget    = coalesce(p_patch->>'budget', budget),
    emirate   = coalesce(p_patch->>'emirate', emirate),
    scope_type= coalesce(p_patch->>'scope_type', scope_type),
    spec      = case when p_patch ? 'spec' then p_patch->'spec' else spec end,
    boq       = case when p_patch ? 'boq' then p_patch->'boq' else boq end,
    trades    = case when p_patch ? 'trades' then array(select jsonb_array_elements_text(p_patch->'trades')) else trades end,
    keywords  = case when p_patch ? 'keywords' then array(select jsonb_array_elements_text(p_patch->'keywords')) else keywords end
    where id=p_inquiry;

  if v_material then
    v_reason := 'The customer changed the requirements of this request on '
             || to_char(now() at time zone 'Asia/Dubai','DD Mon YYYY HH24:MI')
             || ' (Dubai), after this quote was submitted.';

    -- Stale the live quotes and tell each supplier, in one statement so a quote can never be
    -- reverted without its supplier being told.
    with staled as (
      update quotes q
         set stale_at = now(), stale_reason = v_reason, status = 'draft'
       where q.inquiry_id = p_inquiry
         and q.stale_at is null
         and coalesce(q.status,'') in ('submitted','draft')
      returning q.id, q.supplier_id
    ),
    told as (
      insert into notifications(type, to_email, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status)
      select 'quote_requirements_changed',
             coalesce(l.claimed_by, l.email), 'supplier', s.supplier_id, p_inquiry, s.id, 'email',
             'The customer changed this request — please re-quote',
             'Hello ' || coalesce(l.company_name,'') || ',' || chr(10) || chr(10) ||
             'A customer has changed the requirements of a request you had already quoted, so your quote has been set back to draft and is no longer being shown to them.' || chr(10) || chr(10) ||
             v_reason || chr(10) || chr(10) ||
             'Please open the request in your supplier portal, review what changed, and submit an updated quote. Your original figures are still there — nothing has been deleted.' || chr(10) || chr(10) ||
             'QuotesDone',
             'queued'
        from staled s join leads l on l.id = s.supplier_id
       where coalesce(l.claimed_by, l.email) is not null
      returning 1
    )
    select (select count(*) from staled), (select count(*) from told) into v_stale, v_notified;

    if v_stale > 0 then
      select email into v_cust_email from customers where id = v.customer_id;
      v_admin := coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),
                          'management@quotesdone.com');

      -- The customer must know their edit cost them their quotes, or they will wait for prices
      -- that are never coming back on their own.
      if v_cust_email is not null then
        insert into notifications(type, to_email, to_role, inquiry_id, channel, subject, body, status)
        values ('inquiry_edit_staled_quotes', v_cust_email, 'customer', p_inquiry, 'email',
                'Your change means we have asked for fresh prices',
                'Hello,' || chr(10) || chr(10) ||
                'You changed the requirements on your request, so the ' || v_stale ||
                ' quote(s) already submitted no longer match what you are asking for. We have asked those suppliers to re-quote against your updated requirements.' || chr(10) || chr(10) ||
                'You do not need to do anything — the new prices will appear as they arrive.' || chr(10) || chr(10) ||
                'QuotesDone', 'queued');
      end if;

      insert into agent_actions(agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
      values ('procurement','requote_required','needs_review','medium',
              'Requirements changed after ' || v_stale || ' quote(s) were submitted',
              'Watch that the invited suppliers actually re-quote. If they do not, the customer is left with a request that had prices and now has none.',
              jsonb_build_object('inquiry_id', p_inquiry, 'quotes_staled', v_stale,
                                 'suppliers_notified', v_notified, 'changed_at', now()),
              'inquiries', p_inquiry::text);
    end if;
  end if;

  return jsonb_build_object('ok',true,'edited',true,'editable_until',v_deadline,
                            'material_change', v_material,
                            'quotes_staled', v_stale,
                            'suppliers_notified', v_notified);
end $function$;

-- fn_supplier_advisor -- called by a portal edge function that PR #530 deleted and this change restores
CREATE OR REPLACE FUNCTION public.fn_supplier_advisor(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with l as (select * from public.leads where id = p_lead_id),
  s as (select * from public.supplier_score where lead_id = p_lead_id),
  -- The opportunity population a closed gap would unlock. Counted, never assumed.
  live_inq as (
    select count(*) as n from public.inquiries i
    where coalesce(i.status, '') not in ('closed', 'cancelled', 'expired')
  ),
  gaps as (
    select g.* from (
      select 'trade_licence' as key, 'Upload your trade licence' as action,
             'You cannot be matched to any opportunity without a current trade licence.' as why,
             'high' as severity, 'documents' as goes_to, 1 as sort
      from l where l.license_doc_path is null
      union all
      select 'licence_expired', 'Replace your expired trade licence',
             'Your trade licence expired on ' || to_char(l.license_expiry, 'DD Mon YYYY') || '.',
             'high', 'documents', 2
      from l where l.license_doc_path is not null and l.license_expiry is not null
                and l.license_expiry < current_date
      union all
      select 'iso_certificate', 'Upload an ISO certificate',
             'Buyers filter on ISO 9001 and 14001. Adding one opens the projects that require it.',
             'medium', 'documents', 3
      from l where l.iso_doc_path is null
      union all
      select 'iso_expired', 'Renew your ISO certificate',
             'Your ISO certificate expired on ' || to_char(l.iso_expiry, 'DD Mon YYYY') || '.',
             'high', 'documents', 4
      from l where l.iso_doc_path is not null and l.iso_expiry is not null and l.iso_expiry < current_date
      union all
      select 'not_verified', 'Complete verification',
             'Unverified suppliers are excluded from matching entirely.',
             'high', 'profile', 5
      from l where not coalesce(l.verified, false)
      union all
      select 'capability_summary', 'Describe what you actually do',
             'Requests are matched on your capability summary. An empty one matches nothing.',
             'high', 'profile', 6
      from l where l.capability_summary is null or btrim(l.capability_summary) = ''
      union all
      select 'no_products', 'Upload a product catalogue',
             'Your catalogue is what buyers search. Without it you compete on company name alone.',
             'medium', 'products', 7
      from l where not exists (select 1 from public.supplier_product sp where sp.supplier_id = l.id)
      union all
      select 'no_service_area', 'Set the emirates you serve',
             'Opportunities are filtered by location before anything else is considered.',
             'medium', 'profile', 8
      from l where coalesce(array_length(l.service_emirates, 1), 0) = 0
      union all
      select 'slow_response', 'Improve your response time',
             'Your response rate is ' || coalesce((select response_rate from s)::text, '0')
               || '%. Buyers see it, and it is 55% of your reliability score.',
             'medium', 'twin', 9
      from l where coalesce((select response_rate from s), 0) < 60
    ) g
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,

    -- ── §15's LOSS BREAKDOWN — empty, and saying why ────────────────────────────────────────────
    'loss_analysis', jsonb_build_object(
      'quotes_submitted', coalesce((select quotes_submitted from s), 0),
      'quotes_won',       coalesce((select quotes_won from s), 0),
      'rejections',       coalesce((select rejection_count from s), 0),
      'loss_reasons', case
        when coalesce((select quotes_submitted from s), 0) = 0 then '[]'::jsonb
        else jsonb_build_array(
          jsonb_build_object('reason', 'Rejected after quoting', 'count', coalesce((select rejection_count from s), 0),
            'pct', round(100.0 * coalesce((select rejection_count from s), 0)
                         / nullif((select quotes_submitted from s), 0)))
        ) end,
      -- The evidence for an EMPTY breakdown, so nobody mistakes it for a computation that failed.
      'basis', case when coalesce((select quotes_submitted from s), 0) = 0
                    then 'no_completed_opportunities' else 'quotes_submitted' end
    ),

    -- ── §15's RECOMMENDATIONS, and §4's actionable assistant line ───────────────────────────────
    'recommendations', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'key', g.key, 'action', g.action, 'why', g.why,
        'severity', g.severity, 'goes_to', g.goes_to,
        -- Quantified upside, counted from the live population. 0 when there is nothing live, and
        -- the basis says so rather than the number standing alone.
        'impact_rfqs', (select n from live_inq)
      ) order by g.sort), '[]'::jsonb) from gaps g
    ),
    'gap_count', (select count(*) from gaps),
    'impact_basis', jsonb_build_object(
      'live_inquiries', (select n from live_inq),
      'note', 'impact_rfqs counts live inquiries a closed gap would let this supplier compete for'
    ),

    -- The one-line headline §4's command centre shows. Names a concrete gap and its upside, or says
    -- plainly that there is nothing to fix — never a vague "improve your profile".
    -- Three cases, because "can qualify for 0 more opportunities" is TRUE and reads as though
    -- closing the gaps were pointless. When nothing is live the honest statement is that the gaps
    -- block eligibility — the supplier still needs to fix them, they just cannot be told a number
    -- yet. Quoting an upside of 0 would discourage exactly the action the advisor is recommending.
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
    )
  );
$function$;

-- fn_supplier_certifications -- called by a portal edge function that PR #530 deleted and this change restores
create or replace function public.fn_supplier_certifications(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (select * from public.leads where id = p_lead_id),
  docs as (
    select * from (values
      ('trade_licence',      'Trade licence',              'critical', 'Approval is impossible without it — the licence gate refuses every profile that has none.'),
      ('insurance',          'Insurance',                  'high',     'Many customers will not award work to an uninsured supplier.'),
      ('vat',                'VAT certificate',            'high',     'Needed before you can invoice with VAT.'),
      ('iso',               'ISO certification',           'medium',   'Strengthens your capability score and unlocks quality-gated requests.'),
      ('manufacturer_auth', 'Manufacturer authorisation',  'medium',   'Proves you are authorised for the brands you carry.'),
      ('establishment',     'Establishment card',          'low',      'Administrative record. Does not gate work.')
      -- 'bank_iban' ("We cannot pay you without it.") was a row here until 21 Sep 2026. It was false: money
      -- moves both directions through Stripe and the estate never holds a supplier's bank details
      -- (founder instruction 527; scripts/sql/the_founder_removed_bank_details_from_the_estate.sql).
    ) d(key, label, impact, impact_why)
  ),
  held as (
    select d.key, d.label, d.impact, d.impact_why,
      case d.key
        when 'trade_licence'      then (select license_doc_path from me)
        when 'insurance'          then (select insurance_doc_path from me)
        when 'vat'                then (select vat_doc_path from me)
        when 'iso'                then (select iso_doc_path from me)
        when 'manufacturer_auth'  then (select manufacturer_auth_doc_path from me)
        when 'establishment'      then (select egr_doc_path from me)
      end as path,
      case d.key
        when 'trade_licence'     then (select license_expiry from me)
        when 'insurance'         then (select insurance_expiry from me)
        when 'iso'               then (select iso_expiry from me)
        when 'manufacturer_auth' then (select manufacturer_auth_expiry from me)
        else null
      end::date as expiry
    from docs d
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'certifications', coalesce((select jsonb_agg(jsonb_build_object(
        'key', h.key, 'label', h.label,
        'held', h.path is not null,
        'expiry', h.expiry,
        'days_left', case when h.expiry is null then null else (h.expiry - current_date) end,
        -- THE FIELD §16 ASKS FOR. A document with no expiry column is 'valid' when held: it does
        -- not expire, so calling it 'unknown' would invent a problem the supplier cannot fix.
        'document_status', case
          when h.path is null then 'missing'
          when h.expiry is null then 'valid'
          when h.expiry < current_date then 'expired'
          when h.expiry < current_date + 60 then 'expiring'
          else 'valid' end,
        'impact_level', h.impact,
        'impact_why', h.impact_why)
      order by case h.impact when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end, h.label)
      from held h), '[]'::jsonb),
    'impact_basis', 'impact_level is a stated QuotesDone policy about what each document gates — not a number derived from your history',
    'summary', jsonb_build_object(
      'held', (select count(*) from held where path is not null),
      'total', (select count(*) from held),
      'expired', (select count(*) from held where path is not null and expiry is not null and expiry < current_date),
      'expiring', (select count(*) from held where path is not null and expiry is not null
                     and expiry >= current_date and expiry < current_date + 60),
      -- The one number that decides whether they can trade at all, surfaced on its own.
      'blocking_missing', (select count(*) from held where path is null and impact = 'critical'))
  );
$function$;

-- fn_supplier_exception_close -- called by a portal edge function that PR #530 deleted and this change restores
CREATE OR REPLACE FUNCTION public.fn_supplier_exception_close(p_lead_id bigint, p_outcome text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update public.leads
     set exception_closed_at = now(),
         exception_outcome = p_outcome,
         licence_gate_reason = case when p_outcome = 'resolved' then null else licence_gate_reason end
   where id = p_lead_id and exception_closed_at is null;
$function$;

-- fn_supplier_negotiation -- called by a portal edge function that PR #530 deleted and this change restores
CREATE OR REPLACE FUNCTION public.fn_supplier_negotiation(p_quote_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with q as (
    select id, inquiry_id, supplier_id, quote_amount, margin_rate, app_fee, customer_price, lead_time, warranty
      from public.quotes where id = p_quote_id
  ),
  -- The inbound side of the conversation only. What the supplier said is not evidence of pressure.
  inbound as (
    select m.id, m.body, m.created_at
      from public.messages m join q on q.inquiry_id = m.inquiry_id and q.supplier_id = m.supplier_id
     where m.sender = 'customer' order by m.created_at desc limit 10
  ),
  scen as (
    select v.pct,
           round((select quote_amount from q) * (1 - v.pct / 100.0), 2) new_quote,
           round((select quote_amount from q) * (1 - v.pct / 100.0)
                 * (1 + coalesce((select margin_rate from q), 0)), 2) new_customer_price,
           round((select quote_amount from q) * (v.pct / 100.0), 2) you_give_up
      from (values (3), (5), (10)) v(pct)
  )
  select jsonb_build_object(
    'quote_id', p_quote_id,
    -- The thread this quote belongs to. Returned because the drafted reply has to be SENDABLE, and
    -- messages_api keys a thread on (inquiry_id, supplier_id) — without both, the draft is a
    -- suggestion the supplier has to retype somewhere else.
    'inquiry_id', (select inquiry_id from q),
    'supplier_id', (select supplier_id from q),
    'quote_amount', (select quote_amount from q),
    'customer_price', (select customer_price from q),
    -- THE PLATFORM'S margin, named as such. app_fee / quote_amount is QuotesDone's cut, and calling
    -- it "your margin" would be a lie by label.
    'margin', jsonb_build_object(
      'whose', 'platform',
      'app_fee', (select app_fee from q),
      'margin_rate', (select margin_rate from q),
      'note', 'This is the QuotesDone fee on the reveal, not your profit.'),
    'supplier_cost_known', false,
    'possible_reduction', jsonb_build_object(
      'available', false,
      'why', 'QuotesDone does not know what this job costs you to deliver, so it cannot tell you how far you can go. The scenarios below are arithmetic, not advice.',
      'scenarios', coalesce((select jsonb_agg(jsonb_build_object(
          'reduction_pct', s.pct, 'you_receive', s.new_quote,
          'customer_pays', s.new_customer_price, 'you_give_up', s.you_give_up)
        order by s.pct) from scen s), '[]'::jsonb)),
    'inbound_messages', coalesce((select jsonb_agg(jsonb_build_object(
        'id', i.id, 'body', i.body, 'created_at', i.created_at) order by i.created_at desc)
      from inbound i), '[]'::jsonb),
    'population', jsonb_build_object(
      'customer_messages', (select count(*) from inbound),
      'note', case when (select count(*) from inbound) = 0
                   then 'the customer has not written anything yet, so there is no discount request to read'
                   else null end),
    'terms', jsonb_build_object('lead_time', (select lead_time from q), 'warranty', (select warranty from q))
  );
$function$;

-- fn_supplier_network_map -- called by a portal edge function that PR #530 deleted and this change restores
CREATE OR REPLACE FUNCTION public.fn_supplier_network_map()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with centroid(emirate, lat, lng) as (
    values ('Dubai', 25.2048, 55.2708),
           ('Abu Dhabi', 24.4539, 54.3773),
           ('Sharjah', 25.3463, 55.4209),
           ('Ajman', 25.4052, 55.5136),
           ('Ras Al Khaimah', 25.7895, 55.9432),
           ('Umm Al Quwain', 25.5647, 55.5552),
           ('Fujairah', 25.1288, 56.3265)
  ),
  -- Emirate names arrive in several spellings across 20,464 scraped rows, so they are normalised
  -- to the centroid table's keys. A row that matches nothing is counted as unplaced rather than
  -- dropped: silently discarding rows would make the map look tidier than the data is.
  norm as (
    select case
             when l.emirate ilike '%dubai%'      then 'Dubai'
             when l.emirate ilike '%abu%dhabi%'  then 'Abu Dhabi'
             when l.emirate ilike '%sharjah%'    then 'Sharjah'
             when l.emirate ilike '%ajman%'      then 'Ajman'
             when l.emirate ilike '%ras%khaim%'  then 'Ras Al Khaimah'
             when l.emirate ilike '%umm%quwain%' then 'Umm Al Quwain'
             when l.emirate ilike '%fujairah%'   then 'Fujairah'
             else null end as emirate,
           l.id, l.verified, l.matching_blocked
    from public.leads l
  )
  select jsonb_build_object(
    'generated_for', 'row5-section-19',

    -- ── LAYER 1: SUPPLIERS. Real, and the only populated one. ──────────────────────────────────
    'suppliers', jsonb_build_object(
      'basis', 'leads.emirate',
      'count', (select count(*) from norm where emirate is not null),
      'unplaced', (select count(*) from norm where emirate is null),
      'markers', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'name', c.emirate, 'lat', c.lat, 'lng', c.lng,
          'count', (select count(*) from norm n where n.emirate = c.emirate),
          -- Kept separate because they are different claims: how many companies we KNOW OF versus
          -- how many can actually receive an RFQ. On production the second is 0 and the map must
          -- not let the first stand in for it.
          'matchable', (select count(*) from norm n where n.emirate = c.emirate
                          and coalesce(n.verified, false) and not coalesce(n.matching_blocked, false))
        ) order by c.emirate), '[]'::jsonb)
        from centroid c
      )
    ),

    -- ── LAYERS 2-4: EMPTY, each saying so in its own words ─────────────────────────────────────
    'demand', jsonb_build_object(
      'basis', 'inquiries',
      'count', (select count(*) from public.inquiries),
      'markers', '[]'::jsonb,
      'note', 'no inquiries exist yet, so no demand is plotted'
    ),
    'projects', jsonb_build_object(
      'basis', 'inquiries with a project',
      'count', (select count(*) from public.inquiries),
      'markers', '[]'::jsonb,
      'note', 'no projects exist yet'
    ),
    'shipments', jsonb_build_object(
      'basis', 'none',
      'count', 0,
      'markers', '[]'::jsonb,
      'note', 'there is no shipments relation in this schema; nothing is tracked to plot'
    ),

    'totals', jsonb_build_object(
      'leads', (select count(*) from public.leads),
      'placed', (select count(*) from norm where emirate is not null),
      'matchable', (select count(*) from norm
                    where coalesce(verified, false) and not coalesce(matching_blocked, false))
    )
  );
$function$;

-- fn_supplier_product_match -- called by a portal edge function that PR #530 deleted and this change restores
CREATE OR REPLACE FUNCTION public.fn_supplier_product_match(p_inquiry_id uuid, p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with inq as (
    -- EVERYTHING THE CUSTOMER SAID, not the first field that happens to be non-empty. The first
    -- version preferred raw_input and fell back to summary, and on the demo enquiry that discarded
    -- the only line describing the work — every product scored 0% while the store held a curtain
    -- wall profile and the enquiry was for curtain walling. A brief's title carries meaning too,
    -- and dropping it to honour a precedence rule loses signal for nothing.
    select lower(coalesce(category, '')) cat,
           lower(concat_ws(' ', coalesce(summary, ''), coalesce(raw_input, ''), coalesce(category, ''))) want
      from public.inquiries where id = p_inquiry_id
  ),
  -- Words worth matching on. Anything under four characters is noise ("we", "for", "the"), and a
  -- stop list would be a maintenance burden for no gain at this size.
  terms as (
    select distinct w from inq, unnest(regexp_split_to_array(inq.want, '[^a-z0-9]+')) w
     where length(w) >= 4
  ),
  prod as (
    select p.id, p.name, p.brand, p.model, p.category_slug,
           lower(concat_ws(' ', p.name, p.brand, p.model, p.description, p.category_slug)) hay
      from public.supplier_product p
     where p.supplier_id = p_lead_id
  ),
  -- ── THE DENOMINATOR IS THE PRODUCT, NOT THE BRIEF ──────────────────────────────────────────────
  -- Scoring matched-terms over ALL the brief's words made the exactly-right product read 6%:
  -- "Aluminium curtain wall profile" matched 2 of 32 words in a paragraph that also discussed
  -- square metres, retail units and powder coating. That understates as badly as an inflated score
  -- overstates, and a supplier seeing 6% on their best product would conclude the matching is
  -- broken — which it would be.
  --
  -- The question is not "how much of the brief does this product cover" (no single product covers
  -- a brief) but "how much of THIS PRODUCT does the brief ask for". Aluminium ✓ curtain ✓ wall ✓
  -- profile ✗ is a strong match, and reads as one.
  pterms as (
    select pr.id pid, w from prod pr,
      unnest(regexp_split_to_array(lower(concat_ws(' ', pr.name, pr.category_slug)), '[^a-z0-9]+')) w
     where length(w) >= 4
  ),
  hit as (
    select pr.id, pr.name, pr.brand, pr.model, pr.category_slug, pr.hay,
           (select count(*) from pterms pt, inq where pt.pid = pr.id and position(pt.w in inq.want) > 0) matched_terms,
           (select count(*) from pterms pt where pt.pid = pr.id) total_terms,
           (pr.category_slug is not null and pr.category_slug = (select cat from inq)) cat_hit,
           ((select cat from inq) <> '' and pr.category_slug is not null) cat_askable
      from prod pr
  ),
  scored as (
    select h.*,
      round(100.0 * (
          (case when h.cat_hit then 40 else 0 end)
        + (case when h.total_terms > 0 then 60.0 * h.matched_terms / h.total_terms else 0 end)
      ) / nullif((case when h.cat_askable then 40 else 0 end)
               + (case when h.total_terms > 0 then 60 else 0 end), 0)) match_pct
      from hit h
  )
  select jsonb_build_object(
    'inquiry_id', p_inquiry_id,
    'supplier_id', p_lead_id,
    'basis', 'lexical: the enquiry''s own words against the product record. Not semantic — supplier_product carries no embedding, so a synonym will not match.',
    'population', jsonb_build_object(
      'products', (select count(*) from prod),
      'terms_from_enquiry', (select count(*) from terms),
      'note', case when (select count(*) from prod) = 0
                   then 'you have no products yet — upload a catalog and these become matchable'
                   when (select count(*) from terms) = 0
                   then 'the enquiry has no description to match against, so only category could be asked'
                   else null end),
    'matches', coalesce((
      select jsonb_agg(jsonb_build_object(
          'product_id', s.id, 'name', s.name, 'brand', s.brand, 'model', s.model,
          'match_pct', s.match_pct,
          'matched_terms', s.matched_terms, 'terms_considered', s.total_terms,
          'category_match', s.cat_hit)
        order by s.match_pct desc nulls last, s.name)
      from scored s), '[]'::jsonb)
  );
$function$;

-- fn_supplier_products -- called by a portal edge function that PR #530 deleted and this change restores
CREATE OR REPLACE FUNCTION public.fn_supplier_products(p_lead_id bigint, p_query text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with base as (
    select p.*
    from public.supplier_product p
    where p.supplier_id = p_lead_id
      and coalesce(p.status, 'active') <> 'archived'
  ),
  -- §7 "Searchable: YES". Matched over name, brand, model, category and the ATTRIBUTE VALUES, so a
  -- search for "5000 CFM" finds the unit whose spec says so rather than only matching its title.
  filtered as (
    select b.* from base b
    where p_query is null or btrim(p_query) = '' or (
         b.name              ilike '%' || btrim(p_query) || '%'
      or coalesce(b.brand, '')          ilike '%' || btrim(p_query) || '%'
      or coalesce(b.model, '')          ilike '%' || btrim(p_query) || '%'
      or coalesce(b.category_slug, '')  ilike '%' || btrim(p_query) || '%'
      or coalesce(b.subcategory_slug,'')ilike '%' || btrim(p_query) || '%'
      or coalesce(b.description, '')    ilike '%' || btrim(p_query) || '%'
      or exists (
           select 1 from jsonb_each_text(coalesce(b.attributes, '{}'::jsonb)) a
           where a.value ilike '%' || btrim(p_query) || '%'
              or a.key   ilike '%' || btrim(p_query) || '%')
      -- Certifications are a jsonb ARRAY and were unreachable by the attribute scan above, so
      -- "show me my Eurovent-certified units" returned nothing. A supplier searching their own
      -- catalogue by certification is the obvious case for §7's "Searchable: YES".
      or exists (
           select 1 from jsonb_array_elements_text(
             case when jsonb_typeof(b.certifications) = 'array' then b.certifications else '[]'::jsonb end) c
           where c ilike '%' || btrim(p_query) || '%')
    )
  )
  select jsonb_build_object(
    'supplier_id', p_lead_id,
    'query', p_query,

    -- ── §7's THREE COUNTS, over the supplier's whole catalogue, not the filtered page ───────────
    'product_count',  (select count(*) from base),
    -- coalesce(SUBcategory, category), not the reverse. category_slug is the broad family ('hvac')
    -- and is identical across a whole catalogue, so coalescing to it FIRST collapsed four distinct
    -- product categories into 1. The spec's "Categories: 18" means product categories, not sectors.
    'category_count', (select count(distinct coalesce(subcategory_slug, category_slug))
                       from base where coalesce(subcategory_slug, category_slug) is not null),
    -- The real number of specification keys the platform holds. Counted, never estimated.
    'attribute_count', (
      select coalesce(sum((select count(*) from jsonb_object_keys(coalesce(b.attributes, '{}'::jsonb)))), 0)
      from base b
    ),
    'searchable', true,

    -- ── §5's WAREHOUSE PANEL: the three quantities, over the SUPPLIER's own stock ────────────────
    -- inv_items is NOT this, and the distinction matters. Measured: inv_items has no supplier_id at
    -- all, and carries inventory_account / cogs_account / reorder_point — it is QuotesDone's OWN
    -- accounting ledger. A supplier's warehouse could never appear in it, so scoring §5 against it
    -- would have been unsatisfiable by any correct implementation.
    -- A supplier's stock lives on the variant, which is also where §8's "Available: 120" comes from.
    'stock', (
      select jsonb_build_object(
        'available',     coalesce(sum(nullif(v.attributes ->> 'available_units', '')::numeric), 0),
        'reserved',      coalesce(sum(nullif(v.attributes ->> 'reserved_units', '')::numeric), 0),
        'in_production', coalesce(sum(nullif(v.attributes ->> 'in_production_units', '')::numeric), 0),
        'skus', count(*)
      )
      from public.supplier_product_variant v
      join base b2 on b2.id = v.product_id
      where v.active
    ),

    'match_count', (select count(*) from filtered),

    'catalogs', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'status', c.status, 'version', c.version,
        'extracted_at', c.extracted_at, 'source', c.source_document_path
      ) order by c.created_at desc), '[]'::jsonb)
      from public.supplier_catalog c where c.supplier_id = p_lead_id
    ),

    -- ── §8 AI PRODUCT CARDS ─────────────────────────────────────────────────────────────────────
    -- Every field the spec draws on a card, from real columns. `ai_match` is NOT invented: it is
    -- null unless the product carries a computed match in its attributes, because §8's "AI Match
    -- 96%" is a claim about a specific opportunity and there are 0 inquiries on production. A card
    -- showing a confident percentage against nothing would be the exact fabrication this row's
    -- scorer exists to catch.
    'products', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', f.id,
        'name', f.name,
        'category', coalesce(f.subcategory_slug, f.category_slug),
        'brand', f.brand,
        'model', f.model,
        'description', f.description,
        'attributes', coalesce(f.attributes, '{}'::jsonb),
        'attribute_count', (select count(*) from jsonb_object_keys(coalesce(f.attributes, '{}'::jsonb))),
        'certifications', coalesce(f.certifications, '[]'::jsonb),
        'documents', coalesce(f.documents, '[]'::jsonb),
        'status', f.status,
        -- Availability comes from the variants, which is where stock policy lives.
        'variants', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'sku', v.sku, 'attributes', v.attributes,
            'price_policy', v.price_policy, 'lead_time_policy', v.lead_time_policy,
            'active', v.active) order by v.sku), '[]'::jsonb)
          from public.supplier_product_variant v where v.product_id = f.id
        ),
        'reserved_units', (
          select sum(nullif(v.attributes ->> 'reserved_units', '')::numeric)
          from public.supplier_product_variant v where v.product_id = f.id and v.active
        ),
        'in_production_units', (
          select sum(nullif(v.attributes ->> 'in_production_units', '')::numeric)
          from public.supplier_product_variant v where v.product_id = f.id and v.active
        ),
        'available_units', (
          select sum((v.attributes ->> 'available_units')::numeric)
          from public.supplier_product_variant v
          where v.product_id = f.id and v.active
            and (v.attributes ->> 'available_units') ~ '^[0-9]+$'
        ),
        -- §8's "Compatible Projects". Real when the extractor recorded it, null otherwise.
        'compatible_projects', coalesce(f.attributes -> 'compatible_projects', 'null'::jsonb),
        'ai_match', (f.attributes ->> 'ai_match')::numeric,
        'evidence_refs', coalesce(f.evidence_refs, '[]'::jsonb)
      ) order by f.name), '[]'::jsonb)
      from (select * from filtered order by name limit 200) f
    )
  );
$function$;

-- fn_supplier_tier -- called by a portal edge function that PR #530 deleted and this change restores
CREATE OR REPLACE FUNCTION public.fn_supplier_tier(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with s as (
    select coalesce(quotes_submitted, 0) submitted, coalesce(quotes_won, 0) won,
           response_rate, quality_rating, reliability
      from public.supplier_score where lead_id = p_lead_id
  ),
  -- ACTIVITY IS THE GATE, and it is checked before the score is consulted. A supplier who has never
  -- quoted has no performance to measure, and averaging nulls into a number would manufacture one.
  a as (select coalesce((select submitted from s), 0) > 0 active),
  t as (
    select case
      when not (select active from a) then 'unranked'
      when (select won from s) >= 10 and coalesce((select quality_rating from s), 0) >= 85 then 'platinum'
      when (select won from s) >= 5  and coalesce((select quality_rating from s), 0) >= 70 then 'gold'
      when (select won from s) >= 1                                                        then 'silver'
      else 'bronze'
    end tier
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'tier', (select tier from t),
    -- available:false is the difference between "we ranked you low" and "we cannot rank you yet".
    -- The supplier must never read the first when the second is true.
    'available', (select active from a),
    'basis', case when (select active from a)
                  then 'quotes won and quality rating, from supplier_score'
                  else 'no quote has been submitted yet, so there is nothing to rank — this is not a low score' end,
    'ladder', jsonb_build_array(
      jsonb_build_object('tier','bronze',  'needs','submit your first quote'),
      jsonb_build_object('tier','silver',  'needs','win 1 job'),
      jsonb_build_object('tier','gold',    'needs','win 5 jobs and hold a 70% quality rating'),
      jsonb_build_object('tier','platinum','needs','win 10 jobs and hold an 85% quality rating')
    ),
    'progress', jsonb_build_object(
      'quotes_submitted', (select submitted from s),
      'quotes_won', (select won from s),
      -- NULL, not 0. A rating is earned; nobody has earned one, and 0 would read as "rated badly".
      'quality_rating', (select quality_rating from s),
      'response_rate', (select response_rate from s)
    ),
    -- ── THE TIER DOES NOT AFFECT MATCHING. FOUNDER DECISION, 2026-08-08, VERBATIM: ──────────────
    --     "no cancel that totally. a tier shouldnt effect a match."
    --
    -- §20 asks for a tier that changes RFQ distribution, preferred status and search visibility.
    -- The founder has refused it, and the refusal is the correct call: a score computed by this
    -- platform deciding which real companies get sent work would quietly sort suppliers into
    -- winners and losers on a number none of them agreed to.
    --
    -- This field used to say "not YET" — which was a promise, and is now a false one. A supplier
    -- reading "not yet" waits for an advantage that is never coming and may chase the ladder for
    -- it. So the payload states the settled position instead, and the three §20 benefit
    -- requirements stay permanently unmet BY DECISION rather than by omission.
    'benefits_active', false,
    'affects_matching', false,
    'benefits_note', 'Your tier never affects which work you are matched to, how you rank in search, '
      || 'or whether you are shown as preferred. Every supplier is matched on fit alone. '
      || 'This is a record of your track record, not a queue position.'
  );
$function$;

-- fn_supplier_workspaces -- called by a portal edge function that PR #530 deleted and this change restores
CREATE OR REPLACE FUNCTION public.fn_supplier_workspaces(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with rel as (
    -- One row per customer relationship this supplier actually has: an inquiry they were matched
    -- to, or one they have exchanged messages about.
    select distinct i.id as inquiry_id
    from public.inquiries i
    where exists (select 1 from public.inquiry_matches m
                  where m.inquiry_id = i.id and m.supplier_id = p_lead_id)
       or exists (select 1 from public.messages g
                  where g.inquiry_id = i.id and g.supplier_id = p_lead_id)
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'count', (select count(*) from rel),
    -- The populations behind an empty list, so nobody has to guess whether the query worked.
    'population', jsonb_build_object(
      'inquiries', (select count(*) from public.inquiries),
      'matches_for_me', (select count(*) from public.inquiry_matches where supplier_id = p_lead_id)
    ),
    'note', case when (select count(*) from rel) = 0
                 then 'no customer relationships yet — nothing has been matched or messaged'
                 else null end,
    'workspaces', (
      select coalesce(jsonb_agg(w order by w->>'last_activity' desc nulls last), '[]'::jsonb)
      from (
        select jsonb_build_object(
          'inquiry_id', i.id,
          -- §18's project identity.
          'project', jsonb_build_object(
            -- inquiries has no `title` column. The human-readable name is the summary, then the
            -- category, then the RFQ number — falling through in that order means a workspace
            -- always has a name rather than rendering as blank.
            'title', coalesce(nullif(btrim(coalesce(i.summary, '')), ''), i.category,
                              'RFQ ' || coalesce(i.rfq_no::text, i.id::text)),
            'category', i.category,
            'emirate', i.emirate,
            'status', i.status,
            'created_at', i.created_at
          ),
          -- §18's files, CATEGORISED. The spec names drawings, specifications and contracts, so the
          -- bucket is derived from the document's own kind rather than left as one undifferentiated
          -- pile — a workspace whose files are a flat list is the thing §18 replaces.
          'files', (
            select coalesce(jsonb_agg(jsonb_build_object(
              'name', d.file_name, 'kind', d.kind, 'created_at', d.created_at,
              'category', case
                when d.kind ~* 'drawing|dwg|plan|layout'        then 'drawings'
                when d.kind ~* 'spec|datasheet|boq|schedule'    then 'specifications'
                when d.kind ~* 'contract|agreement|po|purchase' then 'contracts'
                else 'other' end
            ) order by d.created_at desc), '[]'::jsonb)
            from public.documents d
            where d.ref_table = 'inquiries' and d.ref_id = i.id::text
          ),
          'file_categories', (
            select jsonb_build_object(
              'drawings', count(*) filter (where d.kind ~* 'drawing|dwg|plan|layout'),
              'specifications', count(*) filter (where d.kind ~* 'spec|datasheet|boq|schedule'),
              'contracts', count(*) filter (where d.kind ~* 'contract|agreement|po|purchase'),
              'other', count(*) filter (where d.kind !~* 'drawing|dwg|plan|layout|spec|datasheet|boq|schedule|contract|agreement|po|purchase')
            )
            from public.documents d
            where d.ref_table = 'inquiries' and d.ref_id = i.id::text
          ),
          -- §18's message count, and the unread split a supplier actually acts on.
          'message_count', (
            select count(*) from public.messages g
            where g.inquiry_id = i.id and g.supplier_id = p_lead_id and not coalesce(g.blocked, false)
          ),
          'unread', (
            select count(*) from public.messages g
            where g.inquiry_id = i.id and g.supplier_id = p_lead_id
              and g.sender = 'customer' and not coalesce(g.read_by_supplier, false)
              and not coalesce(g.blocked, false)
          ),
          'last_activity', (
            select max(g.created_at) from public.messages g
            where g.inquiry_id = i.id and g.supplier_id = p_lead_id
          ),
          -- §18's timeline percentage. Derived from the stages the relationship has actually
          -- passed, so it moves for a real reason and is null before anything has happened rather
          -- than sitting at a meaningless 0%.
          'timeline', (
            select jsonb_build_object(
              'pct', case when total = 0 then null else round(100.0 * hit / total) end,
              'stages', jsonb_build_object(
                'matched', matched, 'messaged', messaged, 'quoted', quoted, 'awarded', awarded)
            )
            from (
              select 4 as total,
                (exists (select 1 from public.inquiry_matches m where m.inquiry_id = i.id and m.supplier_id = p_lead_id))::int
                  as matched,
                (exists (select 1 from public.messages g where g.inquiry_id = i.id and g.supplier_id = p_lead_id))::int
                  as messaged,
                (exists (select 1 from public.quotes q where q.inquiry_id = i.id and q.supplier_id = p_lead_id))::int
                  as quoted,
                (exists (select 1 from public.quotes q where q.inquiry_id = i.id and q.supplier_id = p_lead_id
                         and q.status = 'won'))::int as awarded
            ) s, lateral (select (s.matched + s.messaged + s.quoted + s.awarded) as hit) h
          )
        ) as w
        from rel r join public.inquiries i on i.id = r.inquiry_id
      ) t
    )
  );
$function$;

-- A DROP TAKES THE ACL WITH IT, and CREATE grants EXECUTE to PUBLIC. PUBLIC is revoked first:
-- revoking anon alone is a silent no-op while the grant is still held through PUBLIC.
revoke all on function public.fn_category_expert_ref from public;
revoke all on function public.fn_category_expert_ref from anon;
revoke all on function public.kb_query from public;
revoke all on function public.kb_query from anon;
revoke all on function public.fn_edit_inquiry from public;
revoke all on function public.fn_edit_inquiry from anon;
revoke all on function public.fn_supplier_advisor from public;
revoke all on function public.fn_supplier_advisor from anon;
revoke all on function public.fn_supplier_certifications from public;
revoke all on function public.fn_supplier_certifications from anon;
revoke all on function public.fn_supplier_exception_close from public;
revoke all on function public.fn_supplier_exception_close from anon;
revoke all on function public.fn_supplier_negotiation from public;
revoke all on function public.fn_supplier_negotiation from anon;
revoke all on function public.fn_supplier_network_map from public;
revoke all on function public.fn_supplier_network_map from anon;
revoke all on function public.fn_supplier_product_match from public;
revoke all on function public.fn_supplier_product_match from anon;
revoke all on function public.fn_supplier_products from public;
revoke all on function public.fn_supplier_products from anon;
revoke all on function public.fn_supplier_tier from public;
revoke all on function public.fn_supplier_tier from anon;
revoke all on function public.fn_supplier_workspaces from public;
revoke all on function public.fn_supplier_workspaces from anon;

commit;
