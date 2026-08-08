-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708131849   name: procurement_analysis
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_procurement_analysis(p_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
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
    select q.*, l.company_name, l.rating,
           rp.reputation_index, rp.dispute_rate_pct
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
    rep := coalesce(r.reputation_index, r.rating*20, 50);
    warr_m := coalesce((regexp_match(coalesce(r.warranty,''),'(\d+)'))[1]::int, 0);
    warr_score := case when r.warranty is null then 0 else least(100, warr_m::numeric/24*100) end;
    lead_w := coalesce((regexp_match(coalesce(r.lead_time,''),'(\d+)'))[1]::int, null);
    lead_score := case when lead_w is null then 50 else greatest(0, 100 - lead_w*8) end;
    comp := case when (r.quality->>'mandatory_total') is not null and (r.quality->>'mandatory_total')::numeric>0
                 then round((r.quality->>'mandatory_present')::numeric/(r.quality->>'mandatory_total')::numeric*100) else qual end;
    value := round(0.35*qual + 0.30*price_score + 0.15*rep + 0.10*warr_score + 0.10*lead_score);

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
      'quality_score', qual, 'completeness_pct', comp, 'reputation', round(rep),
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
end $$;
revoke execute on function public.fn_procurement_analysis(uuid) from anon, authenticated, public;
