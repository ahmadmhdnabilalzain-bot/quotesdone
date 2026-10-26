select key, left(value::text,80) v from public.app_secrets where key ilike '%paid_ai%';
select count(*) filter (where open_until > now()) held, count(*) total from public.llm_route_health;
