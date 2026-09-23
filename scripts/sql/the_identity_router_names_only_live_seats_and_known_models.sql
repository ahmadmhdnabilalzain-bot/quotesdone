-- The identity router names only live seats, and only models the catalogue and the hold know.
--
-- WHAT WAS WRONG, measured on production 23 September 2026.
--
-- public.model_policy_by_identity is the second routing table fn_ai_route reads. Its branch fires
-- only when v_generic is true (the calling function has no fn_task_class row, or the named class
-- has no policy) AND the caller passed p_agent_key, and it reads scope = 'current_agent' only:
--
--     if v_generic and p_agent_key is not null then
--       select * into v_idp from model_policy_by_identity
--        where scope = 'current_agent' and (identity_key = p_agent_key
--              or (identity_key = 'cat:*' and p_agent_key like 'cat:%'))
--
-- Two measurements decided this file.
--
-- 1. THE IDENTITIES ARE MOSTLY GONE. 122 rows: 96 scope 'target_employee' and 26 'current_agent'.
--    Exactly 3 of the 122 resolve to a row in public.org_agents — accountant, it_engineer,
--    marketing. The other 119 name the organisation the founder deleted on 7 September 2026
--    ("actually remove the whole organization chart that you made cause its trash" … "not archive.
--    remove totally"): cfo, cpo, bd, collections, intel_director, knowledge_director, org_designer,
--    'cat:*' for "All 86 category experts", and 96 target_employee rows for the 93-employee chart.
--    Those keys can never match p_agent_key again, because no such agent exists to pass one.
--    scope 'target_employee' is read by nothing at all: fn_ai_route is the only routine whose source
--    names this table (1 row from pg_proc), and it filters scope = 'current_agent'.
--
-- 2. THE MODELS ARE NOT IN THE CATALOGUE. Five model ids appear here and in neither
--    public.model_registry nor public.llm_route_health:
--      primary:  deepseek/deepseek-v4-flash 60, google/gemini-3.5-flash-lite 6,
--                anthropic/claude-sonnet-5:batch 3, qwen/qwen3.7-flash 2, google/gemini-3.6-flash 1
--      fallback: deepseek/deepseek-v4-flash 50, qwen/qwen3.7-flash 46,
--                google/gemini-3.5-flash-lite 6, google/gemini-3.6-flash 3,
--                anthropic/claude-sonnet-5:batch 1
--    fn_ai_route does not refuse an unregistered model: it SUBSTITUTES the cheapest model in the
--    tier and writes "WARNING: policy model ... is not in model_registry; substituted ..." into its
--    `why`, which nothing reads. fn_llm_preflight (rewritten in PR #861) refuses them outright with
--    class_key 'route_not_registered'. So a route through this table is either silently a different
--    model or a refusal — never the model the row names.
--
-- WHY NOT REGISTER THE FIVE. anthropic/claude-sonnet-5:batch is the ASYNCHRONOUS batch id; the
-- registry note on openai/gpt-5.6-luna already records that trap, and both seats that named :batch
-- here (knowledge_director, knowledge_validator) are deleted identities, so nothing interactive
-- wanted it. The other four are cheap-tier models no seat's work was chosen for in
-- every_seat_gets_the_model_its_own_work_needs.sql. Registering five models so that 119 dead rows
-- can name them would be catalogue debt taken on for rows that can never be read.
--
-- WHAT THIS FILE DOES.
--   a. Deletes the 119 rows whose identity_key resolves to no live seat — by predicate on
--      org_agents, not by a list of names, so it cannot delete a row that still has an owner.
--   b. Rewrites the 3 surviving rows onto the models their seat already runs, with the reason in
--      the note column, matching every_seat_gets_the_model_its_own_work_needs.sql:
--        accountant  — money: opus-5.5 primary, sonnet-5 fallback
--        it_engineer — diagnosis and drafting: sonnet-5 primary, haiku-latest fallback
--        marketing   — speaks in the company's name: sonnet-5 primary, haiku-latest fallback
--   c. Adds trg_identity_policy_is_a_live_seat_and_a_known_model: an insert or update naming an
--      identity that is not a live seat, or a model absent from model_registry or llm_route_health,
--      is refused. That guard FAILS on the original input — every one of the 119 deleted rows and
--      every one of the five unregistered ids.
--
-- APPLY ORDER: after scripts/sql/the_catalogue_names_every_model_the_seats_run_and_the_hold_covers_all_of_them.sql
-- (PR #861), which is what puts opus-5.5, sonnet-5 and haiku-latest in the registry and the breaker.
-- This file's own guard refuses its own rewrite if that file has not been applied.
--
-- Seat: it_engineer.

begin;

-- (c) first, so the guard is in force for this file's own writes.
create or replace function public.fn_identity_policy_is_a_live_seat_and_a_known_model()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_bad text;
begin
  if not exists (select 1 from public.org_agents a where a.agent_key = new.identity_key) then
    raise exception
      'model_policy_by_identity.identity_key % is not a live seat. The router can only be reached with an agent key a live seat passes; a row for anything else is a route nobody can take.',
      new.identity_key;
  end if;

  for v_bad in
    select m from unnest(array[new.primary_model, new.fallback_model, new.escalation_model]) m
    where m is not null and m <> 'none/deterministic'
  loop
    if not exists (select 1 from public.model_registry r where r.model_id = v_bad) then
      raise exception
        'model_policy_by_identity names % which is not in model_registry. fn_ai_route would silently substitute another model and write the warning into a `why` nobody reads.',
        v_bad;
    end if;
    if not exists (select 1 from public.llm_route_health h where h.model_id = v_bad) then
      raise exception
        'model_policy_by_identity names % which has no llm_route_health row, so the founder''s hold does not cover it.',
        v_bad;
    end if;
  end loop;

  return new;
end;
$fn$;

revoke execute on function public.fn_identity_policy_is_a_live_seat_and_a_known_model() from public, anon, authenticated;

drop trigger if exists trg_identity_policy_is_a_live_seat_and_a_known_model on public.model_policy_by_identity;
create trigger trg_identity_policy_is_a_live_seat_and_a_known_model
  before insert or update on public.model_policy_by_identity
  for each row execute function public.fn_identity_policy_is_a_live_seat_and_a_known_model();

-- (a) the rows whose identity no longer exists.
delete from public.model_policy_by_identity i
where not exists (select 1 from public.org_agents a where a.agent_key = i.identity_key);

-- (b) the three that survive, on the models their seat already runs.
update public.model_policy_by_identity set
  primary_model     = 'anthropic/claude-opus-5.5',
  fallback_model    = 'anthropic/claude-sonnet-5',
  escalation_model  = null,
  max_output_tokens = 1400,
  note              = 'Money. The accountant''s own work decides refunds and reconciliations, so the role default is the same reasoning model finance_analysis runs on; sonnet-5 behind it. Set 23 Sep 2026 with every_seat_gets_the_model_its_own_work_needs.sql.'
where identity_key = 'accountant' and scope = 'current_agent';

update public.model_policy_by_identity set
  primary_model     = 'anthropic/claude-sonnet-5',
  fallback_model    = '~anthropic/claude-haiku-latest',
  escalation_model  = null,
  max_output_tokens = 2200,
  note              = 'Diagnosis and drafting, never money or permissions. sonnet-5 reads a failure and says what it is; haiku behind it. Set 23 Sep 2026 with every_seat_gets_the_model_its_own_work_needs.sql.'
where identity_key = 'it_engineer' and scope = 'current_agent';

update public.model_policy_by_identity set
  primary_model     = 'anthropic/claude-sonnet-5',
  fallback_model    = '~anthropic/claude-haiku-latest',
  escalation_model  = null,
  max_output_tokens = 1200,
  note              = 'Everything this seat writes is published in the company''s name, so the role default is the model the marketing classes run on; haiku behind it. Set 23 Sep 2026 with every_seat_gets_the_model_its_own_work_needs.sql.'
where identity_key = 'marketing' and scope = 'current_agent';

-- The verdict row. No `raise exception` in a file that carries DDL: the exception would roll the
-- trigger back with it.
select case
  when (select count(*) from public.model_policy_by_identity) = 3
   and (select count(*) from public.model_policy_by_identity
         where not exists (select 1 from public.org_agents a where a.agent_key = identity_key)) = 0
   and (select count(*) from public.model_policy_by_identity i
         where exists (
           select 1 from unnest(array[i.primary_model, i.fallback_model, i.escalation_model]) m
           where m is not null and m <> 'none/deterministic'
             and (not exists (select 1 from public.model_registry r where r.model_id = m)
               or not exists (select 1 from public.llm_route_health h where h.model_id = m)))) = 0
   and (select count(*) from pg_trigger
         where tgrelid = 'public.model_policy_by_identity'::regclass
           and tgname = 'trg_identity_policy_is_a_live_seat_and_a_known_model') = 1
  then 'PROBE OK :: 3 rows left, every identity a live seat, every model in the catalogue and under the hold, guard in force'
  else 'PROBE FAILED :: ' ||
       (select count(*) from public.model_policy_by_identity)::text || ' rows; ' ||
       (select count(*) from public.model_policy_by_identity
         where not exists (select 1 from public.org_agents a where a.agent_key = identity_key))::text ||
       ' with a dead identity'
end as verdict;

commit;
