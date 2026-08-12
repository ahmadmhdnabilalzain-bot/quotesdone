-- Every recommendation can now say what else was considered
-- =========================================================
--
-- SHIPPED AS A CAPABILITY, NOT AS A CHECK FIX, and the distinction matters.
-- s36-recommendation-seven-fields asks that EVERY recommendation carry evidence, assumptions,
-- risks, alternatives, expected impact, confidence and cost. agent_actions has columns for three -
-- evidence, risk, confidence, all non-null on the population - and NO COLUMN AT ALL for
-- assumptions, alternatives, expected impact or cost, across 41 writing routines. That check is not
-- closable today and this does not close it: adding four columns with defaults would satisfy the
-- letter and defeat the spec, and I cannot honestly author a cost or an assumption on behalf of
-- 1,311 recommendations somebody else wrote.
--
-- What IS available is alternatives, and it is one join away. decision_log.alternatives went from
-- 0 to 67 of 67 rows on 12 Aug - the writer was fixed yesterday and every new decision now records
-- the options it weighed, in a real structure:
--
--   [{"option":"permitted","selected":true,"basis":"fn_should_escalate + fn_authorize on this
--     action's own context"}, ...]
--
-- and agent_actions.decision_log_id already links to it. Measured: of 156 recommendation-carrying
-- actions in the last two days, 101 have a linked decision that carries alternatives. Of all 1,311
-- in 30 days, 346 are linked and 101 of those have them - the gap is age, not plumbing.
--
-- So the column is filled by EXTRACTION from the decision the action already points at, never by
-- authoring. A trigger rather than 41 edits, for the same reason as every other single-point fix
-- this session: patching the writers one at a time leaves the next one broken.
--
-- NULL WHERE THERE IS NOTHING TO EXTRACT, deliberately. An action with no decision link, or one
-- whose decision recorded no alternatives, keeps a NULL - which reads as "we did not record what
-- else was considered", and that is true. Filling it with '[]' would read as "nothing else was
-- considered", which is a different and unsupported claim.

alter table public.agent_actions add column if not exists alternatives jsonb;

comment on column public.agent_actions.alternatives is
  'What else was considered, extracted from the linked decision_log row by trg_agent_actions_alternatives. NULL means no alternatives were recorded, NOT that none existed.';

create or replace function public.fn_agent_actions_fill_alternatives()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  -- Only when the action points at a decision and does not already carry its own.
  if NEW.alternatives is not null then return NEW; end if;
  if NEW.decision_log_id is null then return NEW; end if;

  select d.alternatives into NEW.alternatives
    from public.decision_log d
   where d.id = NEW.decision_log_id
     and d.alternatives is not null
     and d.alternatives::text not in ('null','[]','{}');

  return NEW;
end $$;

revoke all on function public.fn_agent_actions_fill_alternatives() from public;

drop trigger if exists trg_agent_actions_alternatives on public.agent_actions;
create trigger trg_agent_actions_alternatives
  before insert or update of decision_log_id on public.agent_actions
  for each row execute function public.fn_agent_actions_fill_alternatives();

-- Backfill from links that already exist. Extraction of what is on file, not invention.
update public.agent_actions a
   set alternatives = d.alternatives
  from public.decision_log d
 where d.id = a.decision_log_id
   and a.alternatives is null
   and d.alternatives is not null
   and d.alternatives::text not in ('null','[]','{}');
