with d as (delete from public.assistant_logs where user_agent like 'qd-latency-probe%' returning 1) select count(*) deleted from d;
