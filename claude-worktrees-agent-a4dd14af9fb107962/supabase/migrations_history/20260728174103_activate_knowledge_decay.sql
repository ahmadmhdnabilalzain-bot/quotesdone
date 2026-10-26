-- 786 of 1,789 knowledge rows carried confidence and review_due; the rest had no expiry at
-- all, so stale knowledge was indistinguishable from fresh. Backfill, then let it decay.

update agent_knowledge
   set confidence = coalesce(confidence, 0.7),
       review_due = coalesce(review_due, coalesce(updated_at, created_at, now()) + interval '90 days'),
       validation_status = coalesce(validation_status, 'unreviewed')
 where confidence is null or review_due is null or validation_status is null;

-- Decay: past its review date, confidence falls. Below 0.35 the item is quarantined and
-- stops being served, rather than being quietly wrong forever.
create or replace function public.fn_knowledge_decay()
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare n_decayed int; n_quarantined int; n_tasks int := 0;
begin
  update agent_knowledge
     set confidence = greatest(0.10, round((confidence - (0.05 * greatest(1, floor(extract(epoch from (now() - review_due))/(30*86400)))))::numeric, 2)),
         validation_status = 'stale'
   where review_due < now()
     and coalesce(validation_status,'') <> 'quarantined'
     and confidence > 0.10;
  get diagnostics n_decayed = row_count;

  update agent_knowledge
     set validation_status = 'quarantined'
   where confidence < 0.35 and coalesce(validation_status,'') <> 'quarantined';
  get diagnostics n_quarantined = row_count;

  -- a quarantined expert is a capability gap, so it becomes work
  insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
  select 'knowledge',
         'Knowledge quarantined: '||agent_key,
         count(*)||' knowledge item(s) for '||agent_key||' fell below the confidence floor and are no longer served. '
         ||'Refresh from source and re-validate, or retire the topic.',
         'proposed','advisory', false, 'knowledge_fill'
    from agent_knowledge
   where validation_status='quarantined'
   group by agent_key
  having not exists (select 1 from org_tasks t where t.title='Knowledge quarantined: '||agent_knowledge.agent_key and t.status<>'done');
  get diagnostics n_tasks = row_count;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('knowledge_decay', now(), now(), 'ok',
          jsonb_build_object('decayed',n_decayed,'quarantined',n_quarantined,'tasks',n_tasks),
          'Knowledge decay: '||n_decayed||' item(s) past review lost confidence, '||n_quarantined
          ||' quarantined below the floor, '||n_tasks||' refresh task(s) opened.');

  return jsonb_build_object('decayed',n_decayed,'quarantined',n_quarantined,'tasks',n_tasks);
end $fn$;

revoke execute on function public.fn_knowledge_decay() from public, anon, authenticated;

create index if not exists agent_knowledge_review_due_idx on public.agent_knowledge (review_due)
  where validation_status <> 'quarantined';