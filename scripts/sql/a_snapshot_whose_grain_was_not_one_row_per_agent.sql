-- A SNAPSHOT TABLE WHOSE GRAIN IS NOT ONE ROW PER AGENT, AND A MEAN OF PERCENTAGES.
--
-- MEASURED ON PRODUCTION, 13 Aug 2026, while asking why ai_quality_snapshots holds duplicate agent
-- names inside a single snapshot instant — `onboarding` three times at 03:40, with actions_30d of
-- 1, 5 and 162, byte-identical names, one INSERT, one now():
--
--   ai_quality_snapshots carries a BEFORE INSERT trigger, trg_quality_snapshot_resolve_agent,
--   which rewrites NEW.agent to its canonical org_agents key via fn_org_agent_resolve. It fires
--   PER ROW, so N distinct view agents that share a canonical key become N rows all claiming that
--   one identity. Of the 52 rows fn_ai_quality_watch writes each night:
--
--       28  already canonical — the trigger leaves them alone
--       17  renamed by the trigger to a different canonical key
--        7  resolve to nothing and keep their raw name
--
--   Today that is 52 rows carrying 37 distinct agents. Anything that reads a night's snapshot as
--   "the agents" double-counts fifteen of them. That is why this table still has no screen: a
--   dashboard built over it would have shown a wrong number, confidently.
--
-- A HYPOTHESIS THAT DIED, RECORDED BECAUSE IT LOOKED RIGHT. The obvious next thought is that the
-- spike detector must be broken too: `cur` reads v_ai_agent_health (raw names), `hist` reads
-- ai_quality_snapshots (canonical names), and they are joined on agent — so the 17 renamed agents
-- should never match their own history. PROBED IT BEFORE BELIEVING IT, in an aborted transaction:
--
--     agents_matchable_before=18  after=18  newly_matchable=0  lost=0
--
--   The two sets are IDENTICAL. The snapshot contains both vocabularies — historical rows predate
--   the trigger and the unresolved seven keep their raw names — so the join already matched
--   everything it can match. There is no broken join here and this file does not claim one.
--
-- WHAT IS ACTUALLY WRONG, AND FIXED HERE:
--
--   1. THE GRAIN. The INSERT now aggregates to the canonical key BEFORE writing, so a snapshot
--      holds one row per agent per night — the grain the table's name has always implied. The
--      trigger stays as a safety net and becomes a no-op for this caller.
--   2. THE AVERAGE. `hist` took a FLAT avg(override_pct) across those duplicate rows, letting an
--      agent with one action in thirty days move the trailing average exactly as much as one with
--      a hundred and sixty. An override percentage is a ratio; the mean of ratios over wildly
--      different denominators is not the rate. Both sides are now weighted by actions_30d, and the
--      current rate is recomputed from the underlying counts rather than averaged from percentages.
--
-- WHAT IS DELIBERATELY NOT DONE: the 1,219 historical rows are left exactly as they are. They were
-- written by the behaviour described above and rewriting them would be back-dating data to make a
-- new rule look like it always held. `hist` reads them with the weighted average, which is the
-- honest way to read what is there. Expect the first few nights of trailing averages to shift as
-- single-grain snapshots accumulate — that is the correction landing, not a regression.
--
--   node scripts/apply_sql.mjs scripts/sql/a_snapshot_whose_grain_was_not_one_row_per_agent.sql --promote

create or replace function public.fn_ai_quality_watch()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_regs int:=0; v_spikes int:=0; v_detail jsonb; v_open int; v_owner text; v_t0 timestamptz := now();
begin
  -- ONE ROW PER AGENT PER NIGHT. Resolved to the canonical key here rather than left to the BEFORE
  -- INSERT trigger, because the trigger fires per row and therefore turns N raw agents into N rows
  -- that all claim the same identity. The rate is recomputed from the underlying counts, never
  -- averaged from the per-row percentages.
  insert into public.ai_quality_snapshots(agent, override_pct, actions_30d)
  select k.agent,
         round(100.0 * sum(v.rejected_30d)::numeric / nullif(sum(v.actions_30d), 0), 1),
         sum(v.actions_30d)::int
    from public.v_ai_agent_health v
    cross join lateral (select case
             when exists (select 1 from public.org_agents o where o.agent_key = v.agent and o.active)
               then v.agent
             else coalesce(public.fn_org_agent_resolve(v.agent), v.agent)
           end as agent) k
   where v.override_pct is not null
   group by k.agent
  having sum(v.actions_30d) > 0;

  with ranked as (
    select prompt_key, score, created_at,
           row_number() over(partition by prompt_key order by created_at desc) rn
    from public.prompt_eval_runs
  ),
  reg as (
    select c.prompt_key, c.score cur, p.score prev
    from ranked c join ranked p on p.prompt_key=c.prompt_key and p.rn=2
    where c.rn=1 and (c.score < p.score - 5 or c.score < 70)
  ),
  ins as (
    insert into public.security_events(kind,severity,source,subject,detail)
    select 'eval_regression', case when cur<70 then 'high' else 'medium' end, 'ai_quality_watch', prompt_key,
           jsonb_build_object('current',cur,'previous',prev)
    from reg returning 1
  )
  select count(*) into v_regs from ins;

  with cur as (
    -- Same resolution rule as the insert above, so `cur` and `hist` speak one vocabulary. Before
    -- this, 17 of 52 agents carried a raw name here and a canonical one in the snapshot, and the
    -- join below could not match them at all.
    select k.agent,
           round(100.0 * sum(v.rejected_30d)::numeric / nullif(sum(v.actions_30d), 0), 1) as override_pct,
           sum(v.actions_30d)::int as actions_30d
      from public.v_ai_agent_health v
      cross join lateral (select case
               when exists (select 1 from public.org_agents o where o.agent_key = v.agent and o.active)
                 then v.agent
               else coalesce(public.fn_org_agent_resolve(v.agent), v.agent)
             end as agent) k
     where v.override_pct is not null
     group by k.agent
    having sum(v.actions_30d) >= 5
       and k.agent not in ('security','onboarding','email')
  ),
  hist as (
    -- Weighted by actions, not a flat mean of percentages: the historical rows still contain the
    -- pre-fix duplicates, and a flat avg lets an agent with one action in a month move the trailing
    -- average as much as one with a hundred and sixty.
    select agent,
           sum(override_pct * greatest(actions_30d, 1))::numeric / nullif(sum(greatest(actions_30d, 1)), 0) as avg_prev,
           count(*) n
    from public.ai_quality_snapshots where at < now()-interval '12 hours' group by agent
  ),
  spike as (
    select c.agent, c.override_pct, round(h.avg_prev,1) avg_prev
    from cur c join hist h on h.agent=c.agent
    where h.n>=1 and c.override_pct > coalesce(h.avg_prev,0)+20
  ),
  ins2 as (
    insert into public.security_events(kind,severity,source,subject,detail)
    select 'override_spike','medium','ai_quality_watch', agent,
           jsonb_build_object('override_pct',override_pct,'trailing_avg',avg_prev)
    from spike returning 1
  )
  select count(*) into v_spikes from ins2;

  v_detail := jsonb_build_object('eval_regressions',v_regs,'override_spikes',v_spikes);

  -- Added 10 Aug 2026: this routine has detected quality falling since it was written and never
  -- emitted an event, so nothing downstream could react to it.
  if v_regs + v_spikes > 0 then
    perform fn_emit('ai.confidence_dropped',
                    case when se.kind='eval_regression' then 'prompt' else 'agent' end,
                    se.subject, 'ai_quality_watch',
                    se.detail || jsonb_build_object('finding', se.kind, 'severity', se.severity))
       from public.security_events se
      where se.source='ai_quality_watch' and se.kind in ('eval_regression','override_spike')
        and se.created_at >= v_t0;
  end if;

  if v_regs+v_spikes > 0 then
    select count(*) into v_open from public.agent_actions
      where kind='ai_quality_alert' and coalesce(status,'') in ('pending','needs_review')
        and created_at > now()-interval '24 hours';
    if v_open = 0 then
      insert into public.agent_actions(agent,kind,status,risk,title,recommendation,target_table,detail)
      values('ai_trainer','ai_quality_alert','pending','medium',
        'AI quality alert: '||v_regs||' eval regression(s), '||v_spikes||' override spike(s)',
        'Open the AI Observability dashboard and review security_events of kind eval_regression / override_spike. Consider rolling back the regressed prompt version, or investigating why a human-facing agent''s suggestions are being rejected.',
        'security_events', v_detail);
      select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner
        from public.app_secrets where key='admin_emails';
      insert into public.notifications(type,to_email,to_role,channel,subject,body,status)
      values('ai_quality_alert', v_owner,'admin','email','QuotesDone: AI quality alert',
        'The AI quality watch flagged '||v_regs||' eval regression(s) and '||v_spikes||' override spike(s). Open the AI Observability dashboard and check security_events (kind eval_regression / override_spike).','queued');
    end if;
  end if;
  return v_detail;
end
$function$;
