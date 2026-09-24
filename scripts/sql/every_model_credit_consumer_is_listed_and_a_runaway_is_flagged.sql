-- EVERY MODEL-CREDIT CONSUMER IS LISTED, AND A LOOP OR A REPEAT IS FLAGGED THE HOUR IT STARTS.
-- Seat: it_engineer. 24 Sep 2026, founder_instruction 704 and 705 (open), seat audit GAPS.md IT gap 8, ledger 983.
-- OpenRouter opens once the build is verified (instr 973); the founder is wary of credits "going here and there
-- for nothing" (memory routine-work-is-code-not-llm).
--
-- WHAT WAS MEASURED (production, 24 Sep 2026, public.ai_cost_log, 30 days; the accounting ledger every model call
--   writes): 11 distinct consumers (fn:task_class). quote_compare:quote_comparison made 2,572 calls and
--   inquiry_intake:agent_reasoning 656, with 0 real inquiries in the estate: that traffic is probes and fixtures, and
--   at paid rates it is the first place credit would leak. Waiting in reasoning_held_question for the hold to lift:
--   line_specs.assess 178, sql.trg_quote_quality 52, category.key_for_slug 40, marketing.competitor_change 31 and
--   24 more surfaces; every one of them is replayed the moment OpenRouter opens.
--
-- WHAT THIS ADDS
--   public.it_model_consumer: THE INVENTORY. One row per consumer, its owning seat and why it needs a model rather
--     than code. Seeded below from the measurement above. fn_it_model_consumer_inventory() lists each registered or
--     observed consumer with its 30-day calls, cost, last call and held backlog: the list instr 704 asked for.
--   seat_duty it_engineer.model_spend (1 hour), deterministic, no model:
--     * UNLISTED: a consumer seen in ai_cost_log in 24 h that is not in the inventory -> a finding for the CEO
--       (a model use nobody justified);
--     * RUNAWAY (a loop): a consumer's calls in the last hour over max(30, 5 x its hourly mean of the 7 days
--       before) -> a finding for the owning seat;
--     * REPEATS: the same uncached call (ai_cost_log.cache_hit_key) made 5 or more times in an hour -> a finding
--       for the owning seat: the same question paid for again.
--   The duty FLAGS (instr 705 "flag loops or repeats"); it does not cut a seat's model access, which would stop
--   that seat's work mid-case. The owning seat answers the it.finding handoff.
--
--   node scripts/apply_sql.mjs scripts/sql/every_model_credit_consumer_is_listed_and_a_runaway_is_flagged.sql --apply --ddl

create table if not exists public.it_model_consumer (
  consumer    text primary key check (consumer ~ '^[a-z0-9_]+[:.][a-z0-9_]+$'),   -- fn:task_class, or a think() surface
  owner_seat  text not null references public.org_role (role_id),
  why_a_model text not null check (btrim(why_a_model) <> ''),
  recorded_at timestamptz not null default now()
);
alter table public.it_model_consumer enable row level security;
drop policy if exists it_model_consumer_service_role_only on public.it_model_consumer;
create policy it_model_consumer_service_role_only on public.it_model_consumer as permissive for all to public using (false) with check (false);
revoke all on public.it_model_consumer from anon, authenticated;

insert into public.it_model_consumer (consumer, owner_seat, why_a_model) values
  ('quote_compare:quote_comparison',        'sales_engineer',   'reading free-form supplier quotations line by line against the request'),
  ('inquiry_intake:agent_reasoning',        'sales_engineer',   'understanding a customer request written in any words and language'),
  ('drawing_boq:document_extraction',       'sales_engineer',   'reading quantities off a drawing'),
  ('drawing_redact:document_extraction',    'sales_engineer',   'finding identity marks on a drawing to redact'),
  ('license_extract:document_extraction',   'sales_engineer',   'reading a trade licence document'),
  ('quote_extract:document_extraction',     'sales_engineer',   'reading an uploaded quotation document'),
  ('site_assistant:visitor_chat',           'customer_support', 'answering a website visitor in their own words'),
  ('site_assistant:level0_faq_semantic',    'customer_support', 'matching a visitor question to the FAQ by meaning'),
  ('site_assistant:level0_faq_keyword',     'customer_support', 'legacy FAQ tier; recorded so its calls are not unlisted'),
  ('site_assistant:level0_template',        'customer_support', 'legacy FAQ tier; recorded so its calls are not unlisted'),
  ('resend_inbound:intent_detection',       'customer_support', 'understanding what an inbound email asks'),
  ('founder_directive:json_extraction',     'ceo',              'reading an instruction the founder wrote in free text'),
  -- THINK() HOSTS (review, 24 Sep 2026): think() logs ai_cost_log fn = the function that hosts it and task_class one of
  -- agent_reasoning / knowledge_validation / customer_communication / supplier_communication (_shared/think.ts
  -- taskClassFor). '<fn>:think' lists every such call from that host; without these rows the replay of the held
  -- questions on the day the hold lifts would raise every host as unlisted. Hosts measured by grep of defaultDeps(admin, '<fn>').
  ('accountant:think', 'accountant', 'think(): reasoning where code cannot decide'),
  ('ceo_agent:think', 'ceo', 'think(): reasoning where code cannot decide'),
  ('customer_api:think', 'customer_support', 'think(): reasoning where code cannot decide'),
  ('inbound_email:think', 'customer_support', 'think(): reasoning where code cannot decide'),
  ('inquiry_intake:think', 'sales_engineer', 'think(): reasoning where code cannot decide'),
  ('marketing:think', 'marketing', 'think(): reasoning where code cannot decide'),
  ('marketing_outreach:think', 'marketing', 'think(): reasoning where code cannot decide'),
  ('marketing_social_inbox:think', 'marketing', 'think(): reasoning where code cannot decide'),
  ('public_site:think', 'customer_support', 'think(): reasoning where code cannot decide'),
  ('quote_extract:think', 'sales_engineer', 'think(): reasoning where code cannot decide'),
  ('resend_inbound:think', 'customer_support', 'think(): reasoning where code cannot decide'),
  ('resilience_ping:think', 'it_engineer', 'think(): reasoning where code cannot decide'),
  ('sales_engineer:think', 'sales_engineer', 'think(): reasoning where code cannot decide'),
  ('site_assistant:think', 'customer_support', 'think(): reasoning where code cannot decide'),
  ('supplier_api:think', 'sales_engineer', 'think(): reasoning where code cannot decide'),
  ('supplier_portal:think', 'sales_engineer', 'think(): reasoning where code cannot decide'),
  ('wa_inbound:think', 'customer_support', 'think(): reasoning where code cannot decide')
on conflict (consumer) do update set owner_seat = excluded.owner_seat, why_a_model = excluded.why_a_model;

-- Is this ai_cost_log (fn, task_class) a listed consumer? Its own row, or a think() class from a listed think() host.
create or replace function public.fn_it_model_consumer_listed(p_fn text, p_class text)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp'
as $fn$
  select exists (select 1 from public.it_model_consumer c
                  where c.consumer = p_fn || ':' || coalesce(p_class, 'unclassified')
                     or (c.consumer = p_fn || ':think'
                         and p_class in ('agent_reasoning', 'knowledge_validation', 'customer_communication', 'supplier_communication')))
$fn$;
revoke execute on function public.fn_it_model_consumer_listed(text, text) from public, anon, authenticated;
grant execute on function public.fn_it_model_consumer_listed(text, text) to service_role;

create or replace function public.fn_it_model_consumer_inventory()
returns table(consumer text, owner_seat text, listed boolean, why_a_model text, calls_30d bigint, cost_aed_30d numeric,
              last_call timestamptz, held_waiting bigint)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with seen as (
    select a.fn || ':' || coalesce(a.task_class, 'unclassified') consumer, count(*) n, sum(coalesce(a.cost_aed, 0)) aed,
           max(a.occurred_at) last, max(a.seat) seat, bool_and(public.fn_it_model_consumer_listed(a.fn, a.task_class)) listed
      from public.ai_cost_log a where a.occurred_at > now() - interval '30 days' and a.fn is not null group by 1),
  held as (
    select h.surface consumer, count(*) n, max(h.seat) seat from public.reasoning_held_question h
     where h.applied_at is null and h.status is distinct from 'expired' group by 1),
  keys as (select c.consumer from public.it_model_consumer c union select consumer from seen union select consumer from held)
  select k.consumer, coalesce(c.owner_seat, s.seat, h.seat), c.consumer is not null or h.consumer is not null or coalesce(s.listed, false),
         coalesce(c.why_a_model, case when h.consumer is not null then 'a think() surface: reasoned in its seat''s queue' end),
         coalesce(s.n, 0), coalesce(s.aed, 0), s.last, coalesce(h.n, 0)
    from keys k left join public.it_model_consumer c using (consumer) left join seen s using (consumer) left join held h using (consumer)
   order by coalesce(s.n, 0) + coalesce(h.n, 0) desc, 1;
$fn$;
revoke execute on function public.fn_it_model_consumer_inventory() from public, anon, authenticated;
grant execute on function public.fn_it_model_consumer_inventory() to service_role;

create or replace function public.fn_it_engineer_model_spend()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare x record; v_items jsonb := '[]'::jsonb;
begin
  -- a think() surface is listed by construction (it lives in reasoning_held_question); ai_cost_log fn:task_class must be registered
  for x in select a.fn || ':' || coalesce(a.task_class, 'unclassified') k, count(*) n, max(a.seat) seat from public.ai_cost_log a
            where a.occurred_at > now() - interval '24 hours' and a.fn is not null
              and not public.fn_it_model_consumer_listed(a.fn, a.task_class)
            group by 1 loop
    v_items := v_items || jsonb_build_object('item', 'unlisted:' || x.k, 'owner_seat', 'ceo', 'subject', x.k, 'blast', 'internal', 'affected', x.n,
      'title', x.k || ' called a model ' || x.n || ' time(s) in 24 h and is not in the model-consumer inventory (it_model_consumer)',
      'evidence', jsonb_build_object('calls_24h', x.n, 'seat', x.seat));
  end loop;

  for x in with h as (select a.fn || ':' || coalesce(a.task_class, 'unclassified') k,
                             count(*) filter (where a.occurred_at > now() - interval '1 hour') last_hour,
                             count(*) filter (where a.occurred_at <= now() - interval '1 hour') / 168.0 mean_hour
                        from public.ai_cost_log a where a.occurred_at > now() - interval '7 days 1 hour' and a.fn is not null group by 1)
           select h.*, c.owner_seat from h left join public.it_model_consumer c on c.consumer = h.k
            where h.last_hour > greatest(30, 5 * h.mean_hour) loop
    v_items := v_items || jsonb_build_object('item', 'runaway:' || x.k, 'owner_seat', coalesce(x.owner_seat, 'ceo'), 'subject', x.k,
      'blast', 'internal', 'affected', x.last_hour,
      'title', x.k || ' made ' || x.last_hour || ' model calls in the last hour against a usual ' || round(x.mean_hour, 1) || ' an hour: a loop until shown otherwise',
      'evidence', jsonb_build_object('last_hour', x.last_hour, 'mean_hour_7d', round(x.mean_hour, 2)));
  end loop;

  for x in select a.fn || ':' || coalesce(a.task_class, 'unclassified') k, a.cache_hit_key key, count(*) n, max(c.owner_seat) owner_seat
             from public.ai_cost_log a left join public.it_model_consumer c on c.consumer = a.fn || ':' || coalesce(a.task_class, 'unclassified')
            where a.occurred_at > now() - interval '1 hour' and not a.cached and a.cache_hit_key is not null
            group by 1, 2 having count(*) >= 5 loop
    v_items := v_items || jsonb_build_object('item', 'repeat:' || x.k || ':' || left(md5(x.key), 12), 'owner_seat', coalesce(x.owner_seat, 'ceo'),
      'subject', x.k, 'blast', 'internal', 'affected', x.n,
      'title', x.k || ' paid for the same uncached call ' || x.n || ' times in the last hour',
      'evidence', jsonb_build_object('cache_hit_key', x.key, 'calls', x.n));
  end loop;

  return jsonb_build_object('settled', public.fn_it_duty_settle('model_spend', v_items));
end $fn$;
revoke execute on function public.fn_it_engineer_model_spend() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_model_spend() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('it_engineer.model_spend', 'it_engineer', interval '1 hour', 'fn_it_engineer_model_spend',
   'Model calls by consumer: an unlisted consumer, a loop (5x its usual hour) or a repeated uncached call is a finding for the owning seat.',
   'scripts/sql/every_model_credit_consumer_is_listed_and_a_runaway_is_flagged.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

select case when to_regprocedure('public.fn_it_engineer_model_spend()') is not null
             and to_regprocedure('public.fn_it_model_consumer_inventory()') is not null
             and (select count(*) from public.it_model_consumer) >= 29
             and exists (select 1 from public.seat_duty where duty = 'it_engineer.model_spend')
            then 'PROBE OK' else 'PROBE FAILED: the model-spend duty or its inventory is missing' end as verdict;
