-- customer_support, 12 Oct 2026 (founder rulings 1195-1200; requested by sales_engineer for its daily knowledge-gap check).
--
-- WHY. Every conversation reply is written by a model, and a reply the figure check, the policy check or the reply
-- guard refuses goes back to the model for a rewrite (_shared/ai_reply.ts, _shared/brief_answer.ts). Each rewrite is
-- a sign that the knowledge or the prompt is missing something. Until now those attempts lived only in the function's
-- memory. sales_engineer's knowledge-gap sweep reads reply_attempts::text ~ 'rewrite:' as a guard_rewrite gap.
--
-- WHAT. One nullable jsonb column on each table the replies are logged in. The edge functions write it through
-- _shared/reply_attempts.ts logWithAttempts, which writes the row WITHOUT the column until this file is applied.
--
-- SECURITY. Both tables already have RLS enabled with their policies and their grants; adding a nullable column changes
-- neither (no new table, no new routine, so no new policy and no revoke). The probe confirms RLS is still on.
alter table public.assistant_logs add column if not exists reply_attempts jsonb;
alter table public.social_message add column if not exists reply_attempts jsonb;

comment on column public.assistant_logs.reply_attempts is
  'Every model attempt behind this reply and what each rewrite corrected (attempts[], rewrites, images). Read by the sales_engineer knowledge-gap sweep.';
comment on column public.social_message.reply_attempts is
  'Every model attempt behind this reply and what each rewrite corrected (attempts[]). Read by the sales_engineer knowledge-gap sweep.';

select case
  when (select count(*) from information_schema.columns where table_schema = 'public' and column_name = 'reply_attempts'
          and table_name in ('assistant_logs', 'social_message') and data_type = 'jsonb') <> 2 then 'PROBE FAILED: reply_attempts missing'
  when (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname in ('assistant_logs', 'social_message') and c.relrowsecurity) <> 2 then 'PROBE FAILED: RLS is not on'
  else 'PROBE OK'
end as verdict;
