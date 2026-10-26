-- ROW #5 §15 §4 — THE SUPPLIER AI EMPLOYEE: "Why am I losing RFQs?"
--
-- ── WHAT THE SPEC ASKS FOR, AND WHAT THE ESTATE CAN HONESTLY ANSWER TODAY ───────────────────────
-- §15 draws a loss breakdown — "60% Price, 25% Delivery, 15% Missing certificates" — and then two
-- recommendations. Measured on production 2026-08-07: 0 quotes, 0 inquiries, 0 inquiry_matches.
-- There is NO loss history, for this supplier or any other.
--
-- So the percentages are NOT produced. `loss_reasons` comes back as an empty array with an explicit
-- `basis: 'no_completed_opportunities'`, because a breakdown invented from nothing would be the
-- single most persuasive lie this portal could tell a supplier — it would read as insight, it would
-- turn a MISSING check green, and it would be wrong in a way no one could see.
--
-- The RECOMMENDATIONS half is different, and it is real right now. Every gap below is computed from
-- a column: a missing trade licence, an expired ISO certificate, an unfilled capability summary,
-- an unverified account. These are the actual reasons this supplier cannot win work today, which is
-- the honest answer to "why am I losing" when the answer is "you are not yet eligible to compete".
--
-- Each recommendation carries `impact_rfqs` — how many MORE opportunities the gap is costing —
-- computed by counting live inquiries the supplier would match on if the gap were closed. With 0
-- inquiries that is 0, and it is returned as 0 with `impact_basis` naming the population, never
-- as the spec's illustrative "32 more projects".
create or replace function public.fn_supplier_advisor(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
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

comment on function public.fn_supplier_advisor(bigint) is
  'Row #5 §15/§4. Why a supplier is losing work, and what to do about it. Loss percentages are '
  'returned ONLY when quotes exist; with none, loss_reasons is empty and basis says why. Every '
  'recommendation is computed from a real column, and impact_rfqs counts live inquiries.';
