-- For the next 2-3 months the ONLY product is supplier acquisition. The goal is 10 approved
-- suppliers in each of 86 categories = 860 approved. At a realistic 5% cold-invite-to-approved
-- conversion that needs ~200 sendable leads per category. Today only 25 of 86 categories have
-- 200+, 3 have ZERO, and only 3 new leads were scraped in the last 30 days.
-- The binding constraint is NOT invite speed. It is lead supply. This makes the company
-- measure that, and fix it without being asked.

create or replace view public.v_supply_gap as
with pool as (
  select c.slug, c.name, c.num,
    count(distinct lc.lead_id) filter (where l.email is not null and l.email<>'' and coalesce(l.banned,false)=false) as sendable,
    count(distinct lc.lead_id) filter (where l.invite_status is not null)                                            as invited,
    count(distinct lc.lead_id) filter (where l.claimed)                                                              as claimed,
    count(distinct lc.lead_id) filter (where l.approval_status='approved')                                           as approved
  from catalog_supplier_categories c
  left join lead_category lc on lc.slug = c.slug
  left join leads l on l.id = lc.lead_id
  group by c.slug, c.name, c.num
)
select slug, name, num, sendable, invited, claimed, approved,
       greatest(0, 10 - approved)                       as gap_to_target,
       ceil(greatest(0, 10 - approved) / 0.05)::int     as sendable_needed_at_5pct,
       greatest(0, ceil(greatest(0, 10 - approved) / 0.05)::int - sendable) as sendable_shortfall,
       case
         when approved >= 10                                                   then 'TARGET MET'
         when sendable = 0                                                     then 'NO POOL - must source from scratch'
         when sendable < ceil(greatest(0,10-approved)/0.05)::int               then 'POOL TOO THIN - scrape more'
         when invited = 0                                                      then 'READY - not yet invited'
         else 'IN PROGRESS'
       end as status
from pool;

comment on view public.v_supply_gap is
  'Per category: how much supplier supply exists, how much is needed to reach 10 approved at a 5% conversion assumption, and what the blocking condition is.';

create or replace function public.fn_supply_gap_scan()
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare r record; n_scrape int:=0; n_invite int:=0; n_source int:=0; v_uncat int; v_met int; v_total int;
begin
  select count(*) into v_total from v_supply_gap;
  select count(*) into v_met   from v_supply_gap where status='TARGET MET';

  -- 1. Categories that cannot reach the target from the existing pool
  for r in select * from v_supply_gap where status in ('POOL TOO THIN - scrape more','NO POOL - must source from scratch') order by sendable asc limit 25
  loop
    insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
    select 'procurement',
           'Supply gap: '||r.slug,
           r.name||' has '||r.sendable||' sendable lead(s) but needs about '||r.sendable_needed_at_5pct
           ||' to reach 10 approved suppliers at a 5% conversion assumption (shortfall '||r.sendable_shortfall||'). '
           ||'Source more UAE suppliers in this category before inviting - inviting a thin pool burns it without reaching the target.',
           'proposed','advisory', false, 'knowledge_acquire'
    where not exists (select 1 from org_tasks t where t.title='Supply gap: '||r.slug and t.status<>'done');
    if found then if r.sendable=0 then n_source:=n_source+1; else n_scrape:=n_scrape+1; end if; end if;
  end loop;

  -- 2. Categories with enough pool and no invites sent yet
  for r in select * from v_supply_gap where status='READY - not yet invited' order by sendable desc limit 25
  loop
    insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
    select 'procurement','Start invites: '||r.slug,
           r.name||' has '||r.sendable||' sendable leads and no invitations sent. Pool is sufficient for the 10-approved target. Queue it into the invite ramp.',
           'proposed','advisory', false, 'invite'
    where not exists (select 1 from org_tasks t where t.title='Start invites: '||r.slug and t.status<>'done');
    if found then n_invite:=n_invite+1; end if;
  end loop;

  -- 3. Free supply: uncategorised leads are unusable until classified
  select count(*) into v_uncat from leads l
   where not exists (select 1 from lead_category lc where lc.lead_id=l.id)
     and l.email is not null and l.email<>'' and coalesce(l.banned,false)=false;

  if v_uncat > 500 then
    insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
    select 'knowledge','Classify '||v_uncat||' uncategorised leads',
           v_uncat||' sendable leads carry no category, so they cannot be targeted and count toward no category''s supply. '
           ||'Classifying them is free supply - it costs no acquisition spend and will partly fill the thin categories. '
           ||'Run the category classifier over the unmapped set.',
           'proposed','advisory', false, 'route_category'
    where not exists (select 1 from org_tasks where title like 'Classify % uncategorised leads' and status<>'done');
  end if;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('supply_gap_scan', now(), now(), 'ok',
          jsonb_build_object('categories',v_total,'target_met',v_met,'scrape_tasks',n_scrape,
                             'source_tasks',n_source,'invite_tasks',n_invite,'uncategorised',v_uncat),
          'Supply gap scan: '||v_met||' of '||v_total||' categories at 10 approved. '
          ||n_scrape||' need more scraping, '||n_source||' have no pool at all, '||n_invite
          ||' ready to invite, '||v_uncat||' leads unclassified.');

  return jsonb_build_object('categories',v_total,'target_met',v_met,'scrape',n_scrape,'source',n_source,'invite',n_invite,'uncategorised',v_uncat);
end $fn$;

revoke execute on function public.fn_supply_gap_scan() from public, anon, authenticated;