-- before_a_reveal_a_supplier_portal_title_is_the_trade_and_the_emirate.sql
-- Assigned: sales_engineer. 13 Nov 2026, anonymity fix round (founder ruling 1683; independent review of F2, item 3).
--
-- MEASURED on production (SELECT only, review of F2): the supplier portal's `workspaces` (supplier_portal dashboard.ts:89,
-- market.ts:166 -> CollaborationWorkspace.tsx:195) shows every MATCHED supplier, before any reveal, a title made by
-- fn_supplier_safe_text(summary_masked). That SQL mask returned "Kitchen fit-out in Al Nahda, Sharjah; villa 15 Al Barsha 2
-- near Mall of the Emirates; existing quote AED 32,816.70" unchanged. Its reveal test was `exists transactions` with no
-- revealed_at. fn_supplier_opportunities served raw_input_masked (the customer's whole chat) as `requirement` the same way;
-- latent (it lists status 'open', which no inquiry has) but the same door.
--
-- WHAT CHANGES: before a reveal both routines give the trade and the emirate only ("Fitout work in Sharjah"), no requirement,
-- no estimated value, and a neutral name for a customer's file; a reveal is a transactions row WITH revealed_at. Nothing else
-- in either body changes (copied from production's pg_get_functiondef, 13 Nov 2026). CREATE OR REPLACE keeps the existing ACL
-- (EXECUTE revoked from public, anon, authenticated; verified has_function_privilege false for both), and the revokes are
-- restated below for the exact signatures (one overload each, enumerated on production).
-- The supplier_portal edge function applies the same rule at its door (supplier_portal/actions/market.ts, dashboard.ts), so
-- the title is safe from the deploy whichever lands first.
-- Probe: before_a_reveal_a_supplier_portal_title_is_the_trade_and_the_emirate_probe.sql (pure, raises CHK<<...>>).

CREATE OR REPLACE FUNCTION public.fn_supplier_workspaces(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with rel as (
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
    -- MATCHED TO ME, and nothing about the estate (review of #854: the same estate-wide count that was
    -- removed from fn_supplier_opportunities was still published here).
    'population', jsonb_build_object(
      'matches_for_me', (select count(*) from public.inquiry_matches where supplier_id = p_lead_id),
      'messaged_me', (select count(distinct inquiry_id) from public.messages where supplier_id = p_lead_id)
    ),
    'note', case when (select count(*) from rel) = 0
                 then 'no customer relationships yet — nothing has been matched or messaged'
                 else null end,
    'workspaces', (
      select coalesce(jsonb_agg(w order by w->>'last_activity' desc nulls last), '[]'::jsonb)
      from (
        select jsonb_build_object(
          'inquiry_id', i.id,
          'project', jsonb_build_object(
            -- THE TITLE IS A CUSTOMER'S OWN SENTENCE (22 Sep 2026, SP-N-05). It used to be i.summary,
            -- the raw column, printed at the top of the workspace before the reveal was paid for —
            -- the one place in the portal that read around the masking and the reveal gate at once.
            -- Post-reveal this supplier has paid for the customer's identity, so the unmasked summary
            -- is theirs to read; before it, the masked column through the inbox's seed scrub.
            -- BEFORE A REVEAL THE TITLE IS THE TRADE AND THE EMIRATE ONLY (13 Nov 2026, sales_engineer; founder ruling 1683; review
            -- of F2 item 3): fn_supplier_safe_text(summary_masked) kept "Al Nahda", "Villa 15 Al Barsha 2 near Mall of the
            -- Emirates" and "AED 32,816.70", measured on production. No customer sentence passes a SQL mask to a supplier any
            -- more; the gated summary is supplier_api's inbox. And a reveal is a transactions row WITH revealed_at.
            'title', case when exists (select 1 from public.transactions t where t.inquiry_id = i.id and t.supplier_id = p_lead_id and t.revealed_at is not null)
                          then coalesce(nullif(btrim(coalesce(i.summary, '')), ''), i.category,
                                        'RFQ ' || coalesce(i.rfq_no::text, i.id::text))
                          else initcap(replace(replace(coalesce(i.category, 'general'), '_', ' '), '-', ' ')) || ' work' || coalesce(' in ' || i.emirate, '') end,
            'category', i.category,
            'emirate', i.emirate,
            'status', i.status,
            'created_at', i.created_at
          ),
          'files', (
            select coalesce(jsonb_agg(jsonb_build_object(
              -- a customer's file name can carry his name, his site or his old supplier's: before a reveal it is not served
              'name', case when exists (select 1 from public.transactions t where t.inquiry_id = i.id and t.supplier_id = p_lead_id and t.revealed_at is not null) then d.file_name else 'Job file (' || coalesce(d.kind, 'document') || ')' end, 'kind', d.kind, 'created_at', d.created_at,
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

CREATE OR REPLACE FUNCTION public.fn_supplier_opportunities(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (
    select l.id, lower(coalesce(l.sector, '')) sector, l.emirate,
           coalesce(l.service_emirates, '{}'::text[]) service_emirates,
           (select sc.trades from public.supplier_capabilities sc
             where sc.supplier_id = l.id and sc.confirmed_at is not null) confirmed_trades,
           l.verified
      from public.leads l where l.id = p_lead_id
  ),
  -- ONLY THE ENQUIRIES WE SENT THIS SUPPLIER (public.inquiry_matches is the answer to "what may this
  -- supplier quote for"; matching is exact trade or none).
  cand as (
    select i.id, i.category, i.emirate, i.summary_masked as summary, i.scope_type, i.created_at, i.budget_masked as budget,
           nullif(btrim(coalesce(i.raw_input_masked, '')), '') requirement,
           lower(coalesce(i.category, '')) cat
      from public.inquiries i
     where coalesce(i.status, 'open') = 'open'
       and exists (select 1 from public.inquiry_matches m
                    where m.inquiry_id = i.id and m.supplier_id = p_lead_id)
  ),
  scored as (
    select c.*,
      (c.cat = me.sector and me.sector <> '')                                    as trade_hit,
      (c.emirate is not null and (c.emirate = me.emirate
        or c.emirate = any(me.service_emirates)))                                as location_hit,
      (coalesce(cardinality(me.confirmed_trades), 0) > 0)                        as capacity_known,
      -- KEYED, NOT READ: the trades the supplier ticked against the enquiry's trade codes.
      (coalesce(cardinality(me.confirmed_trades), 0) > 0 and c.category is not null
        and public.fn_taxonomy_trades_for(array[c.category]) && me.confirmed_trades) as capacity_hit,
      (select count(*) from public.quotes q
         join public.inquiries qi on qi.id = q.inquiry_id
        where q.supplier_id = p_lead_id and lower(coalesce(qi.category,'')) = c.cat) as similar_jobs
      from cand c cross join me
  ),
  ranked as (
    select s.*,
      round(100.0 * (
        (case when s.trade_hit then 40 else 0 end)
      + (case when s.location_hit then 30 else 0 end)
      + (case when s.capacity_known and s.capacity_hit then 30 else 0 end)
      ) / nullif(40 + 30 + (case when s.capacity_known then 30 else 0 end), 0)) as fit_score
      from scored s
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'count', (select count(*) from ranked),
    'ordered_by', 'fit_score desc — a ranked list, never chronological',
    'population', jsonb_build_object(
      'matched_to_me', (select count(*) from public.inquiry_matches where supplier_id = p_lead_id),
      'open_for_me', (select count(*) from cand),
      'my_quotes', (select count(*) from public.quotes where supplier_id = p_lead_id)
    ),
    'note', case when (select count(*) from ranked) = 0
                 then 'no open opportunities yet — nothing has been matched to you'
                 else null end,
    'opportunities', coalesce((
      select jsonb_agg(x order by x->>'fit_score' desc) from (
        select jsonb_build_object(
          'inquiry_id', r.id,
          -- before a reveal: the trade and the emirate only, never the customer's sentence or his whole chat (13 Nov 2026)
          'project_title', case when exists (select 1 from public.transactions t where t.inquiry_id = r.id and t.supplier_id = p_lead_id and t.revealed_at is not null) then coalesce(nullif(btrim(coalesce(r.summary, '')), ''), r.category, 'Untitled project') else initcap(replace(replace(coalesce(r.category, 'general'), '_', ' '), '-', ' ')) || ' work' || coalesce(' in ' || r.emirate, '') end,
          'category', r.category,
          'emirate', r.emirate,
          'requirement', case when exists (select 1 from public.transactions t where t.inquiry_id = r.id and t.supplier_id = p_lead_id and t.revealed_at is not null) then r.requirement end,
          'estimated_value', case when exists (select 1 from public.transactions t where t.inquiry_id = r.id and t.supplier_id = p_lead_id and t.revealed_at is not null) then r.budget end,
          'fit_score', r.fit_score,
          'match_pct', r.fit_score,
          'reasons', jsonb_build_array(
            jsonb_build_object('key', 'trade', 'applies', r.trade_hit,
              'text', case when r.trade_hit then 'This is your trade — ' || coalesce(r.category,'the same category')
                           else 'Matched to you on capability rather than on your registered sector' end),
            jsonb_build_object('key', 'location', 'applies', r.location_hit,
              'text', case when r.location_hit then 'Nearby location — ' || coalesce(r.emirate,'your service area')
                           else 'Outside the emirates you serve' end),
            jsonb_build_object('key', 'capacity', 'applies', r.capacity_known and r.capacity_hit, 'available', r.capacity_known,
              'text', case when not r.capacity_known
                           then 'Your capacity fits: not assessable — you have not confirmed your services yet'
                           when r.capacity_hit
                           then 'Your capacity fits — this trade is among the services you confirmed'
                           else 'Not among the services you confirmed' end),
            jsonb_build_object('key', 'history', 'applies', r.similar_jobs > 0,
              'available', (select count(*) from public.quotes where supplier_id = p_lead_id) > 0,
              'similar_jobs', r.similar_jobs,
              'text', case when (select count(*) from public.quotes where supplier_id = p_lead_id) = 0
                           then 'Previous similar project: you have not quoted on QuotesDone yet'
                           when r.similar_jobs > 0
                           then 'You worked on ' || r.similar_jobs || ' previous similar project(s)'
                           else 'No previous similar project on record' end)
          )
        ) x from ranked r
      ) s
    ), '[]'::jsonb)
  )
$function$;

revoke execute on function public.fn_supplier_workspaces(bigint) from public, anon, authenticated;
revoke execute on function public.fn_supplier_opportunities(bigint) from public, anon, authenticated;
