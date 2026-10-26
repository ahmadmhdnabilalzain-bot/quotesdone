-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260629215302   name: matching_feedback_and_wa_flush
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


-- AI feedback loop: blend supplier performance into match ordering (relevance stays primary)
create or replace function public.match_suppliers(query_embedding vector, match_count integer default 10, p_emirate text default null, p_role text default null, p_product text default null, p_min_rating numeric default null)
returns table(id bigint, company_name text, emirate text, business_role text, products text, services text, phone text, email text, whatsapp text, website text, rating numeric, reviews integer, capability_summary text, similarity double precision)
language sql stable set search_path to 'public','pg_temp'
as $function$
  select l.id, l.company_name, l.emirate, l.business_role, l.products, l.services,
         l.phone, l.email, l.whatsapp, l.website, l.rating, l.reviews, l.capability_summary,
         1 - (l.embedding <=> query_embedding) as similarity
  from public.leads l
  left join public.supplier_perf sp on sp.supplier_id = l.id
  where l.embedding is not null
    and (p_emirate is null or l.emirate ilike p_emirate)
    and (p_role    is null or l.business_role = p_role)
    and (p_product is null or l.products ilike '%'||p_product||'%' or l.capability_summary ilike '%'||p_product||'%')
    and (p_min_rating is null or l.rating >= p_min_rating)
  order by ( (1 - (l.embedding <=> query_embedding))
             + 0.05 * coalesce(sp.perf_score,0)
             + case when l.claimed then 0.03 else 0 end
             + case when l.approval_status = 'approved' then 0.02 else 0 end ) desc
  limit match_count;
$function$;

-- Auto-flush queued WhatsApp notifications every 2 min (no-op until a WA sender is configured)
select cron.schedule('wa_flush','*/2 * * * *', $$
  select net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/send_whatsapp',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := '{"__secret":"e9a57a9422fd48bea19e4780508f17ee9141cf1ae55e4a5594f4c4ab6e39205c"}'::jsonb
  );
$$);

