"select (select count(*) from public.ceo_plan_month) m, (select count(*) from public.ceo_daily_digest) d, (select max(said_at) from public.founder_instruction) fi;"  
