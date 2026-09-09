-- A supplier rating comes from QuotesDone customers only (founder, 9 Sep 2026).
--
--   "supplier rating should be from customers after they tried them"
--   "google review shouldnt be counted"
--
-- leads.rating / leads.rating_maps / leads.reviews / leads.reviews_maps are scraped from Google
-- Maps before the supplier ever registered here. 4,477 rows carry one, averaging 4.57. They are
-- kept: they are directory data with other legitimate uses, and dropping a populated column is
-- irreversible. They are simply no longer SHOWN, COUNTED, SCORED or RANKED ON as a QuotesDone
-- rating. The only rating that counts is leads.app_rating / app_reviews, which
-- recompute_supplier_rating() derives from public.reviews — 0 rows today, so every supplier now
-- reports "not yet rated".
--
-- THE TRAP THIS FILE AVOIDS: an absent rating must be ABSENT FROM THE WEIGHTING, never a zero.
-- coalesce(rating,0) turns "unrated" into "terrible" and would rank a good supplier last on the
-- day the Google number stops arriving. Every weighted score below drops the rating term and
-- rescales the remaining weights instead.
--
-- Each routine below is the definition read out of production with pg_get_functiondef and the
-- named lines changed — headers, defaults and ACLs are preserved by CREATE OR REPLACE.

-- supplier_perf.rating was coalesce(app_rating, rating): the Google star, weighted 0.50 of
-- perf_score, and coalesce(...,0) for anyone without one. perf_score feeds fn_ws_supplier_360 and
-- supplier_reputation.responsiveness. rating is now the earned one, and when it is absent the
-- remaining 0.50 of weight is rescaled to fill the scale rather than scoring the supplier zero.
create or replace view public.supplier_perf as
  with base as (
    select l.id as supplier_id, l.company_name,
      l.app_rating as rating,
      (select count(*) from inquiry_matches m where m.supplier_id = l.id) as matched,
      (select count(*) from quotes q where q.supplier_id = l.id) as quoted,
      (select count(*) from inquiries i where i.hired_supplier_id = l.id) as won,
      (select count(*) from reviews r where r.supplier_id = l.id) as review_count
    from leads l
    where l.claimed = true
  )
  select supplier_id, company_name, rating, matched, quoted, won, review_count,
    round(quoted::numeric / nullif(matched, 0)::numeric, 3) as quote_rate,
    round(won::numeric / nullif(quoted, 0)::numeric, 3) as win_rate,
    case when rating is null
      then round((coalesce(won::numeric / nullif(quoted, 0)::numeric, 0) * 0.35
                  + least(quoted, 10)::numeric / 10.0 * 0.15) / 0.50, 3)
      else round(rating / 5.0 * 0.50 + coalesce(won::numeric / nullif(quoted, 0)::numeric, 0) * 0.35
                 + least(quoted, 10)::numeric / 10.0 * 0.15, 3)
    end as perf_score
  from base b;

CREATE OR REPLACE FUNCTION public.match_suppliers_kw(p_keywords text[] DEFAULT '{}'::text[], p_category text DEFAULT NULL::text, p_emirate text DEFAULT NULL::text, p_role text DEFAULT NULL::text, p_min_rating numeric DEFAULT NULL::numeric, p_limit integer DEFAULT 8, p_multi boolean DEFAULT false)
 RETURNS TABLE(id bigint, company_name text, emirate text, business_role text, products text, services text, phone text, email text, whatsapp text, website text, rating numeric, reviews integer, capability_summary text, match_score integer, in_emirate boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with base as (
    select l.id, l.company_name, l.emirate, l.business_role, l.products, l.services,
           l.phone, l.email, l.whatsapp, l.website, l.app_rating as rating, l.app_reviews as reviews, l.capability_summary,
           (select count(*) from unnest(p_keywords) k
              where l.products ilike '%'||k||'%' or l.services ilike '%'||k||'%'
                 or l.categories ilike '%'||k||'%' or l.capability_summary ilike '%'||k||'%') as strong_hits,
           (select count(*) from unnest(p_keywords) k where l.company_name ilike '%'||k||'%') as name_hits,
           (p_category is not null and l.sector = p_category) as cat_match,
           (p_multi and (
                 l.sector='fitout'
                 or l.business_role ilike '%turnkey%' or l.business_role ilike '%contract%' or l.business_role ilike '%fit%out%' or l.business_role ilike '%interior%'
                 or l.capability_summary ilike '%turnkey%' or l.capability_summary ilike '%fit-out%' or l.capability_summary ilike '%fit out%' or l.capability_summary ilike '%fitout%' or l.capability_summary ilike '%renovation%' or l.capability_summary ilike '%general contract%' or l.capability_summary ilike '%main contract%'
                 or l.services ilike '%turnkey%' or l.services ilike '%fit-out%' or l.services ilike '%fit out%' or l.services ilike '%renovation%'
               )) as turnkey_match,
           (coalesce(l.app_reviews,0) > 0) as has_app_rev,
           coalesce(p_emirate is not null and l.emirate ilike p_emirate, false) as in_emirate
    from public.leads l
    where public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                                 l.approval_status, l.permanently_closed, l.chat_strikes)
      and (p_role is null or l.business_role=p_role)
      and (p_min_rating is null or l.app_rating>=p_min_rating)
      and (
            (p_category is not null and l.sector=p_category)
         or exists (select 1 from unnest(p_keywords) k
              where l.products ilike '%'||k||'%' or l.services ilike '%'||k||'%'
                 or l.categories ilike '%'||k||'%' or l.capability_summary ilike '%'||k||'%' or l.company_name ilike '%'||k||'%')
         or (p_multi and (l.sector='fitout' or l.business_role ilike '%turnkey%' or l.business_role ilike '%contract%' or l.business_role ilike '%interior%' or l.capability_summary ilike '%turnkey%' or l.capability_summary ilike '%fit-out%' or l.capability_summary ilike '%fitout%' or l.capability_summary ilike '%renovation%'))
      )
  )
  select id, company_name, emirate, business_role, products, services, phone, email, whatsapp,
         website, rating, reviews, capability_summary,
         ( least(strong_hits,6)*2 + least(name_hits,2)
           + case when cat_match then 3 else 0 end
           + case when turnkey_match then 5 else 0 end
           + case when has_app_rev then 1 else 0 end )::int as match_score,
         in_emirate
  from base
  where cat_match or strong_hits > 0 or turnkey_match
  order by in_emirate desc, match_score desc, rating desc nulls last, reviews desc nulls last
  limit coalesce(p_limit,8);
$function$;

CREATE OR REPLACE FUNCTION public.fn_suppliers_board(p_search text DEFAULT ''::text, p_sector text DEFAULT ''::text, p_limit integer DEFAULT 60, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare out jsonb;
begin
  with base as (
    select l.id, l.company_name,
      coalesce(nullif(trim(l.sector),''),'general') as sector,
      coalesce(nullif(trim(l.emirate),''),'—') as emirate,
      l.app_rating as rating,
      l.verified, (l.approved_at is not null) as approved, l.banned,
      (l.invited_at is not null) as invited, l.claimed, (l.registration_submitted_at is not null) as registered,
      coalesce(l.capability_score,0) as capability_score, l.created_at,
      case when l.approved_at is not null then 'approved' when l.verified then 'verified'
           when l.registration_submitted_at is not null then 'registered' when l.invited_at is not null then 'invited'
           when l.contacted then 'contacted' else 'sourced' end as stage
    from leads l
    where (coalesce(p_search,'') = '' or l.company_name ilike '%'||p_search||'%' or l.sector ilike '%'||p_search||'%' or l.emirate ilike '%'||p_search||'%')
      and (coalesce(p_sector,'') = '' or l.sector = p_sector)
  ),
  ranked as (select *, row_number() over (partition by stage order by created_at desc, id desc) as rn from base),
  stagecounts as (select stage, count(*) as c from base group by stage)
  select jsonb_build_object(
    'total', (select count(*) from base),
    'stages', (
      select jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label,
        'count', coalesce((select c from stagecounts sc where sc.stage=s.key),0),
        'cards', coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'company_name',r.company_name,'sector',r.sector,'emirate',r.emirate,'rating',r.rating,'verified',r.verified,'approved',r.approved,'banned',r.banned,'capability_score',r.capability_score) order by r.rn) from ranked r where r.stage=s.key and r.rn<=12),'[]'::jsonb))
        order by s.ord)
      from (values ('sourced','Sourced',1),('contacted','Contacted',2),('invited','Invited',3),('registered','Registered',4),('verified','Verified',5),('approved','Approved',6)) s(key,label,ord)
    ),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'company_name',b.company_name,'sector',b.sector,'emirate',b.emirate,'rating',b.rating,'verified',b.verified,'approved',b.approved,'banned',b.banned,'invited',b.invited,'registered',b.registered,'stage',b.stage,'capability_score',b.capability_score,'created_at',b.created_at) order by b.created_at desc, b.id desc),'[]'::jsonb)
             from (select * from base order by created_at desc, id desc limit greatest(1,least(p_limit,200)) offset greatest(0,p_offset)) b),
    'sectors', (select coalesce(jsonb_agg(jsonb_build_object('label',x.sector,'n',x.n) order by x.n desc),'[]'::jsonb) from (select sector, count(*) n from base group by sector order by count(*) desc limit 12) x)
  ) into out;
  return out;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_procurement_analysis(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare minp numeric; maxp numeric; medp numeric; nq int;
        matrix jsonb := '[]'::jsonb; r record; rec jsonb := null; best numeric := -1;
        price_score numeric; qual numeric; rep numeric; warr_m int; warr_score numeric;
        lead_w int; lead_score numeric; comp numeric; value numeric; risks text[]; letter text; idx int := 0;
begin
  select count(*), min(quote_amount), max(quote_amount), percentile_cont(0.5) within group (order by quote_amount)
    into nq, minp, maxp, medp
  from public.quotes where inquiry_id=p_id and coalesce(quote_amount,0) > 0
    and coalesce(status,'') not in ('withdrawn','rejected','expired');
  if nq = 0 then return jsonb_build_object('ready',false,'quote_count',0,'note','No priced quotes yet.'); end if;

  for r in
    select q.*, l.company_name,
           rp.reputation_index, rp.review_count as rep_reviews, rp.dispute_rate_pct
    from public.quotes q
    left join public.leads l on l.id=q.supplier_id
    left join public.supplier_reputation rp on rp.supplier_id=q.supplier_id
    where q.inquiry_id=p_id and coalesce(q.quote_amount,0) > 0
      and coalesce(q.status,'') not in ('withdrawn','rejected','expired')
    order by q.quote_amount asc
  loop
    idx := idx + 1; letter := chr(64+idx);  -- A, B, C...
    price_score := case when maxp=minp then 100 else round((maxp - r.quote_amount)/(maxp-minp)*100) end;
    qual := coalesce((r.quality->>'score')::numeric, 0);
    rep := case when coalesce(r.rep_reviews,0) > 0 then r.reputation_index else null end;
    warr_m := coalesce((regexp_match(coalesce(r.warranty,''),'(\d+)'))[1]::int, 0);
    warr_score := case when r.warranty is null then 0 else least(100, warr_m::numeric/24*100) end;
    lead_w := coalesce((regexp_match(coalesce(r.lead_time,''),'(\d+)'))[1]::int, null);
    lead_score := case when lead_w is null then 50 else greatest(0, 100 - lead_w*8) end;
    comp := case when (r.quality->>'mandatory_total') is not null and (r.quality->>'mandatory_total')::numeric>0
                 then round((r.quality->>'mandatory_present')::numeric/(r.quality->>'mandatory_total')::numeric*100) else qual end;
    value := case when rep is null
                  then round((0.35*qual + 0.30*price_score + 0.10*warr_score + 0.10*lead_score)/0.85)
                  else round(0.35*qual + 0.30*price_score + 0.15*rep + 0.10*warr_score + 0.10*lead_score) end;

    risks := '{}';
    if qual < 50 then risks := array_append(risks,'Quote incomplete — low quality score ('||qual||'/100)'); end if;
    if r.expires_at is not null and r.expires_at < now() then risks := array_append(risks,'Quote has expired'); end if;
    if medp>0 and r.quote_amount < 0.75*medp then risks := array_append(risks,'Price well below median — verify the scope is not under-quoted'); end if;
    if r.warranty is null then risks := array_append(risks,'No warranty stated'); end if;
    if coalesce(r.payment_terms,'')='' then risks := array_append(risks,'No payment terms stated'); end if;
    if coalesce(r.dispute_rate_pct,0) > 10 then risks := array_append(risks,'Supplier has a dispute history ('||round(r.dispute_rate_pct)||'%)'); end if;
    if array_length(risks,1) is null then risks := array_append(risks,'No major risks flagged'); end if;

    matrix := matrix || jsonb_build_object(
      'label','Supplier '||letter, 'quote_id',r.id, 'supplier_id',r.supplier_id, 'company_name',r.company_name,
      'price', r.quote_amount, 'price_vs_low_pct', case when minp>0 then round((r.quote_amount-minp)/minp*100,1) else 0 end,
      'lead_time', r.lead_time, 'warranty', r.warranty, 'payment_terms', r.payment_terms, 'validity', r.validity,
      'quality_score', qual, 'completeness_pct', comp, 'reputation', round(rep), 'reputation_basis', case when rep is null then 'not yet rated on QuotesDone' else 'QuotesDone reviews' end,
      'value_score', value, 'risks', to_jsonb(risks));

    if value > best then best := value;
      rec := jsonb_build_object('label','Supplier '||letter,'supplier_id',r.supplier_id,'company_name',r.company_name,
        'value_score',value,'price',r.quote_amount,
        'why','Best overall value: quality '||qual||'/100, price score '||price_score||'/100'
          ||case when qual>=70 then ', well-documented' else ', but confirm the missing quote details' end
          ||case when r.quote_amount=minp then ', and it is the lowest price' else '' end||'.');
    end if;
  end loop;

  return jsonb_build_object(
    'ready', nq>=2, 'quote_count', nq,
    'price_range', jsonb_build_object('low',minp,'median',medp,'high',maxp,'spread_pct',case when minp>0 then round((maxp-minp)/minp*100,1) else 0 end),
    'matrix', matrix,
    'recommendation', rec,
    'note', case when nq=1 then 'Only one quote so far — comparison needs at least two.' else null end
  );
end $function$;

CREATE OR REPLACE FUNCTION public.fn_supplier_stats(p_supplier_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v jsonb; v_quotes int; v_reveals int; v_hired int; v_lost int;
  v_qd_rev numeric; v_deal_val numeric; v_avg_lead numeric;
  v_pos jsonb; v_hist jsonb; v_rating numeric; v_rating_pct numeric; v_resp numeric;
  v_pending_reviews int; v_active_rfqs int;
begin
  select count(*) into v_quotes from quotes where supplier_id=p_supplier_id;
  select count(*) into v_reveals from transactions where supplier_id=p_supplier_id;
  select count(*) into v_hired from inquiries where hired_supplier_id=p_supplier_id;
  select count(*) into v_lost from inquiries i
     where i.hired_supplier_id is not null and i.hired_supplier_id<>p_supplier_id
       and exists (select 1 from quotes q where q.inquiry_id=i.id and q.supplier_id=p_supplier_id);
  select coalesce(sum(coalesce(reveal_fee,0)+coalesce(app_fee,0)),0),
         coalesce(sum(coalesce(quote_amount,0)),0)
    into v_qd_rev, v_deal_val
    from transactions where supplier_id=p_supplier_id and coalesce(refund_status,'')<>'approved';
  select round(avg(nullif(regexp_replace(coalesce(lead_time,''),'[^0-9.]','','g'),'')::numeric),1)
    into v_avg_lead from quotes where supplier_id=p_supplier_id and lead_time ~ '[0-9]';
  select app_rating, rv_response_rate into v_rating, v_resp from leads where id=p_supplier_id;
  if v_rating is not null then
    select round(100.0*(count(*) filter (where l2.app_rating <= v_rating))/nullif(count(*),0),0)
      into v_rating_pct
      from leads l2 where l2.sector = (select sector from leads where id=p_supplier_id) and l2.app_rating is not null;
  end if;
  select count(*) into v_pending_reviews from quotes where supplier_id=p_supplier_id and coalesce(review_status,'')='pending';
  select count(distinct q.inquiry_id) into v_active_rfqs from quotes q join inquiries i on i.id=q.inquiry_id
    where q.supplier_id=p_supplier_id and coalesce(i.status,'') in ('open','active','collecting','live');
  with myq as (select inquiry_id, quote_amount from quotes where supplier_id=p_supplier_id and quote_amount is not null and quote_amount>0),
  peer as (select inquiry_id, min(quote_amount) lo, avg(quote_amount) av, count(*) n
             from quotes where quote_amount is not null and quote_amount>0 group by inquiry_id),
  pos as (select m.quote_amount, p.lo, p.av,
                 case when p.lo>0 then (m.quote_amount-p.lo)/p.lo*100 end pct_low,
                 case when p.av>0 then (m.quote_amount-p.av)/p.av*100 end pct_avg,
                 (m.quote_amount<=p.lo*1.0001) as is_lowest
            from myq m join peer p using(inquiry_id) where p.n>=2)
  select jsonb_build_object('competitive_rfqs', count(*),'times_lowest', count(*) filter (where is_lowest),
    'lowest_rate', round(100.0*count(*) filter (where is_lowest)/nullif(count(*),0),0),
    'avg_pct_above_lowest', round(avg(pct_low)::numeric,1),'avg_pct_vs_average', round(avg(pct_avg)::numeric,1),
    'band', case when count(*)=0 then 'not enough data' when avg(pct_avg) <= -4 then 'below market average'
                 when avg(pct_avg) < 5 then 'around market average' else 'above market average' end
  ) into v_pos from pos;
  with months as (select date_trunc('month', (now() - (n||' month')::interval)) m from generate_series(0,11) n),
  qb as (select date_trunc('month',created_at) m, count(*) c from quotes where supplier_id=p_supplier_id group by 1),
  rb as (select date_trunc('month',revealed_at) m, count(*) c from transactions where supplier_id=p_supplier_id group by 1)
  select jsonb_agg(jsonb_build_object('month', to_char(months.m,'Mon YY'),'quotes', coalesce(qb.c,0), 'reveals', coalesce(rb.c,0)) order by months.m)
    into v_hist from months left join qb on qb.m=months.m left join rb on rb.m=months.m;
  v := jsonb_build_object('supplier_id', p_supplier_id,'quotes_total', v_quotes,'reveals', v_reveals,'hired', v_hired,
    'lost_to_others', v_lost,'win_ratio', round(100.0*v_hired/nullif(v_quotes,0),1),'reveal_ratio', round(100.0*v_reveals/nullif(v_quotes,0),1),
    'qd_revenue', v_qd_rev,'deal_value_awarded', v_deal_val,'avg_lead_time_days', v_avg_lead,'rating', v_rating,
    'rating_percentile', v_rating_pct,'response_rate', v_resp,'pending_reviews', v_pending_reviews,'active_rfqs', v_active_rfqs,
    'price_positioning', v_pos,'history_12m', v_hist,'document_expiries', fn_supplier_expiries(p_supplier_id));
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_ws_suppliers(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_q text := nullif(trim(coalesce(p->>'q','')),'');
  v_emirate text := nullif(p->>'emirate','');
  v_sector text := nullif(p->>'sector','');
  v_approval text := nullif(p->>'approval','');
  v_limit int := least(coalesce((p->>'limit')::int,50),100);
  v_offset int := greatest(coalesce((p->>'offset')::int,0),0);
  v_rows jsonb; v_total bigint;
begin
  select count(*) into v_total from leads
   where coalesce(source,'') <> 'canary'
     and (v_q is null or company_name ilike '%'||v_q||'%' or categories ilike '%'||v_q||'%')
     and (v_emirate is null or emirate=v_emirate)
     and (v_sector is null or sector=v_sector)
     and (v_approval is null or approval_status=v_approval);

  select coalesce(jsonb_agg(r),'[]'::jsonb) into v_rows from (
    select jsonb_build_object('id',id,'company_name',company_name,'sector',sector,'sub_type',sub_type,
      'emirate',emirate,'city',city,'rating',app_rating,'reviews',app_reviews,'categories',categories,
      'approval_status',approval_status,'lifecycle_stage',lifecycle_stage,'verified',verified,
      'verification_status',verification_status,'capability_score',capability_score,'invite_status',invite_status,
      'registration_status',registration_status,'license_expiry',license_expiry,'banned',banned,
      'matching_blocked',matching_blocked,'phone',phone,'website',website,'created_at',created_at) as r
    from leads
    where coalesce(source,'') <> 'canary'
      and (v_q is null or company_name ilike '%'||v_q||'%' or categories ilike '%'||v_q||'%')
      and (v_emirate is null or emirate=v_emirate)
      and (v_sector is null or sector=v_sector)
      and (v_approval is null or approval_status=v_approval)
    order by capability_score desc nulls last, app_reviews desc nulls last
    limit v_limit offset v_offset
  ) x;

  return jsonb_build_object(
    'kpis', jsonb_build_object(
      'total',(select count(*) from leads where coalesce(source,'') <> 'canary'),
      'approved',(select count(*) from leads where approval_status='approved'),
      'pending_review',(select count(*) from leads where coalesce(approval_status,'') in ('submitted','pending','under_review','pending_review')),
      'verified',(select count(*) from leads where verified is true),
      'registered',(select count(*) from leads where registration_paid_at is not null),
      'licenses_expiring',(select count(*) from leads where license_expiry is not null and license_expiry < (now()+interval '30 days')::date and license_expiry >= now()::date),
      'banned',(select count(*) from leads where banned is true),
      'matching_blocked',(select count(*) from leads where matching_blocked is true)
    ),
    'success', jsonb_build_object(
      'kpis', coalesce((select to_jsonb(k) from supplier_kpis k), '{}'::jsonb),
      'open_risk', (select count(*) from agent_actions where kind='supplier_risk' and status in ('pending','needs_review')),
      'attention', coalesce((select jsonb_agg(a) from (
          select jsonb_build_object('id',supplier_id,'company_name',company_name,'health',health,
            'quality',quality,'compliance',compliance,'response',response,'retention',retention,
            'risk_tier',risk_tier,'dormant',dormant) a
          from supplier_health where risk_tier in ('high','medium') order by health asc limit 10) t),'[]'::jsonb),
      'trend', coalesce((select jsonb_agg(jsonb_build_object('d',snapshot_date,'health',(kpis->>'avg_health')) order by snapshot_date)
          from (select snapshot_date, kpis from supplier_kpi_snapshots order by snapshot_date desc limit 14) s),'[]'::jsonb)
    ),
    'kanban', coalesce((select jsonb_agg(jsonb_build_object('key',stg,'count',c) order by c desc) from (
        select coalesce(nullif(lifecycle_stage,''),'directory') stg, count(*) c from leads where coalesce(source,'') <> 'canary' group by 1 order by 2 desc limit 8) k),'[]'::jsonb),
    'sectors', coalesce((select jsonb_agg(jsonb_build_object('key',s,'count',c) order by c desc) from (
        select coalesce(nullif(sector,''),'other') s, count(*) c from leads where coalesce(source,'') <> 'canary' group by 1 order by 2 desc limit 10) s),'[]'::jsonb),
    'emirates', coalesce((select jsonb_agg(jsonb_build_object('key',e,'count',c) order by c desc) from (
        select coalesce(nullif(emirate,''),'—') e, count(*) c from leads where coalesce(source,'') <> 'canary' group by 1 order by 2 desc limit 10) e),'[]'::jsonb),
    'total', v_total, 'limit', v_limit, 'offset', v_offset, 'rows', v_rows
  );
end;
$function$;
