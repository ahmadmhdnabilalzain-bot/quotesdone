-- REORGANISING THE AGENT COMPANY — compatibility gaps found by executing the resolvers.
--
-- fn_org_agent_resolve returned NULL for the four merged identities, because its first two arms
-- both require an ACTIVE org_agents row and a merged employee is deliberately inactive. A null
-- addressee is not harmless: fn_agent_action_resolve_addressee rewrites it to 'brief' and marks the
-- action escalated, so every historical caller still addressing analytics_director would have
-- quietly become an escalation to the Chief of Staff instead of reaching the surviving desk.

begin;

insert into public.org_agent_alias (alias, agent_key, reason) values
 ('analytics_director','intel_director',
  'merged 14 Aug 2026 into the Data & Intelligence Director; the row stays inactive for history and every caller resolves here'),
 ('supplier_intel_analyst','supplier_analyst',
  'merged 14 Aug 2026 into the Supplier Intelligence Analyst'),
 ('notification_ops','channel_specialist',
  'merged 14 Aug 2026 into Lifecycle Channel Operations'),
 ('marketing_copy','marketing_content',
  'merged 14 Aug 2026 into Content Strategy & Copy')
on conflict (alias) do update set agent_key = excluded.agent_key, reason = excluded.reason;

-- The OS -> department map must cover all ten, or fn_owning_os falls through to a substring guess.
insert into public.os_department (os_key, dept_key)
select o.os_key, d.dept_key
  from public.org_departments d
  join lateral (select od.os_key from public.os_department od
                 join public.org_departments s on s.dept_key = od.dept_key
                where s.merged_into = d.dept_key limit 1) o on true
 where d.active and not exists (select 1 from public.os_department x where x.dept_key = d.dept_key)
on conflict do nothing;

commit;
