-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727015727   name: regulatory_change_propagation
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ================================================================
-- Layer-4 remediation, part 5: the regulatory_change scenario.
-- Found: nothing ever wrote agent_knowledge.review_due, so the
-- stale-knowledge self-review could never be triggered by a regulation
-- change, and no event told the affected specialists.
-- ================================================================

create or replace function public.fn_regulation_propagate() returns trigger
language plpgsql security definer set search_path = public as $fn$
declare v_cat text; v_flagged integer := 0; v_changed boolean;
begin
  v_changed := (tg_op = 'INSERT')
    or (coalesce(old.body,'')             is distinct from coalesce(new.body,''))
    or (coalesce(old.key_requirements,'{}'::jsonb) is distinct from coalesce(new.key_requirements,'{}'::jsonb))
    or (coalesce(old.summary,'')          is distinct from coalesce(new.summary,''))
    or (coalesce(old.effective_date, 'epoch'::date) is distinct from coalesce(new.effective_date, 'epoch'::date))
    or (coalesce(old.status,'')           is distinct from coalesce(new.status,''))
    or (coalesce(old.categories, '{}')    is distinct from coalesce(new.categories, '{}'));

  if not v_changed then return new; end if;

  -- Flag every affected knowledge base for review. This is what makes the
  -- change reach the specialists' knowledge rather than sitting in a table.
  if new.categories is not null then
    foreach v_cat in array new.categories loop
      update agent_knowledge
        set review_due = current_date
      where agent_key = 'cat:' || v_cat;
      get diagnostics v_flagged = row_count;

      insert into company_event (event_type, entity_type, entity_id, actor, payload)
      values ('regulation.changed','category', v_cat, coalesce(new.approved_by,'compliance_mgr'),
              jsonb_build_object('authority', new.authority, 'title', new.title,
                                 'doc_ref', new.doc_ref, 'effective_date', new.effective_date,
                                 'source_url', new.source_url, 'knowledge_rows_flagged', v_flagged,
                                 'regulation_id', new.id));
    end loop;
  end if;

  return new;
end; $fn$;

drop trigger if exists trg_regulation_propagate on public.regulations;
create trigger trg_regulation_propagate after insert or update on public.regulations
for each row execute function public.fn_regulation_propagate();

revoke execute on function public.fn_regulation_propagate() from anon, authenticated, public;

-- The specialists and the compliance manager must be told, or the flag is a private note.
insert into public.event_subscription (agent_key, event_type, reason, active)
select a.agent_key, 'regulation.changed',
       'Owns knowledge that a UAE regulator change can invalidate.', true
from org_agents a
where a.active and a.department in ('knowledge','legal','procurement')
  and fn_seniority_rank(a.seniority) <= 3
on conflict do nothing;

create or replace view public.v_knowledge_review_due as
select k.agent_key,
       replace(k.agent_key, 'cat:', '') as catalog_slug,
       count(*) as modules_due,
       min(k.review_due) as due_since
from agent_knowledge k
where k.review_due is not null and k.review_due <= current_date
group by k.agent_key
order by 4, 1;
