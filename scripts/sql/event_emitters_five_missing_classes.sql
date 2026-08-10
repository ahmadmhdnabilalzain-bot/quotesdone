-- Five of the nine named event classes had no emitter anywhere: the fact happened and the bus never
-- heard about it. Measured 2026-08-10 06:00 UTC on production: customer registered, supplier
-- approved, campaign launched, AI confidence dropped, competitor pricing change — none emitted, none
-- named as a literal in any routine. Production subscribes to names it never emits; this is the
-- other half of that gap.
--
-- Every emitter below fires at the point the fact BECOMES TRUE, in the database, so it covers every
-- caller instead of the one code path that happened to be looked at. None of them can fire without a
-- real change: no backfill, no seed, no schedule. Four of the five will sit silent until the company
-- registers a customer / approves a supplier / launches a campaign — that silence is honest, and the
-- emitter is what makes the eventual first one visible.

-- ── 1. customer.registered ────────────────────────────────────────────────────────────────────────
-- public.customers is written by inquiry_intake (v21) and by the customer API. A trigger covers both
-- and anything added later.
create or replace function public.fn_emit_customer_registered()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  perform fn_emit('customer.registered', 'customer', new.id::text, 'system',
    jsonb_build_object('locale', new.locale, 'industry', new.industry,
                       'email_verified', new.email_verified, 'phone_verified', new.phone_verified));
  return null;
end $$;
drop trigger if exists trg_emit_customer_registered on public.customers;
create trigger trg_emit_customer_registered after insert on public.customers
  for each row execute function public.fn_emit_customer_registered();

-- ── 2. supplier.approved ──────────────────────────────────────────────────────────────────────────
-- supplier.applied is already emitted on registration_submitted_at. Approval — the state that
-- actually lets a supplier receive an RFQ — was not. Guarded on the TRANSITION, so a re-save of an
-- already-approved lead is silent.
-- The transition test lives in the body, not a WHEN clause: an INSERT trigger's WHEN cannot
-- reference OLD, and leads DO arrive already approved (the match_eval fixtures insert that way).
create or replace function public.fn_emit_supplier_approved()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if coalesce(new.approval_status,'') <> 'approved' then return null; end if;
  if tg_op = 'UPDATE' and coalesce(old.approval_status,'') = 'approved' then return null; end if;
  perform fn_emit('supplier.approved', 'lead', new.id::text, 'system',
    jsonb_build_object('company', new.company_name, 'city', new.city,
                       'verified', new.verified, 'lifecycle_stage', new.lifecycle_stage));
  return null;
end $$;
drop trigger if exists trg_emit_supplier_approved on public.leads;
create trigger trg_emit_supplier_approved after insert or update of approval_status on public.leads
  for each row execute function public.fn_emit_supplier_approved();

-- ── 3. campaign.launched ──────────────────────────────────────────────────────────────────────────
-- There is no campaigns table; meta_insights is the sync of what Meta reports, and effective_status
-- is where a campaign going live becomes visible to this company. Both current campaigns are PAUSED,
-- so this stays silent until one is actually launched. Emitted once per campaign_id: the sync
-- rewrites these rows on every poll and a per-poll event would be noise, not news.
create or replace function public.fn_emit_campaign_launched()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if new.campaign_id is not null and not exists (
       select 1 from company_event
        where event_type = 'campaign.launched' and entity_id = new.campaign_id) then
    perform fn_emit('campaign.launched', 'campaign', new.campaign_id, 'marketing',
      jsonb_build_object('name', new.campaign_name, 'objective', new.objective,
                         'status', new.effective_status));
  end if;
  return null;
end $$;
drop trigger if exists trg_emit_campaign_launched on public.meta_insights;
create trigger trg_emit_campaign_launched after insert or update on public.meta_insights
  for each row when (new.effective_status ~* '^active$')
  execute function public.fn_emit_campaign_launched();

-- ── 4. competitor.pricing_changed ─────────────────────────────────────────────────────────────────
-- 25 of the 27 competitor rows carry pricing-relevant prose (fee, commission, %, subscription,
-- free), captured once on 2026-07-27. Nothing compares a refresh against what was there before, so
-- a competitor moving its commission would overwrite the old figure silently. Fires only when the
-- pricing prose actually differs.
create or replace function public.fn_emit_competitor_pricing_changed()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  perform fn_emit('competitor.pricing_changed', 'competitor', new.id::text, 'competitive',
    jsonb_build_object('name', new.name,
                       'was', left(coalesce(old.business_model,''), 400),
                       'now', left(coalesce(new.business_model,''), 400),
                       'what_they_do_changed',
                         coalesce(old.what_they_do,'') is distinct from coalesce(new.what_they_do,'')));
  return null;
end $$;
drop trigger if exists trg_emit_competitor_pricing_changed on public.competitor;
create trigger trg_emit_competitor_pricing_changed after update on public.competitor
  for each row
  when ((coalesce(old.business_model,'') is distinct from coalesce(new.business_model,'')
         or coalesce(old.what_they_do,'') is distinct from coalesce(new.what_they_do,''))
        and (coalesce(new.business_model,'')||coalesce(new.what_they_do,''))
              ~* '(price|pricing|fee|commission|%|subscription|free)')
  execute function public.fn_emit_competitor_pricing_changed();

-- ── 5. ai.confidence_dropped ──────────────────────────────────────────────────────────────────────
-- fn_ai_quality_watch already DETECTS the drop — an eval score that fell more than five points or
-- sits below 70, and a human-override rate more than 20 points above its own trailing average. It
-- wrote security_events and a founder alert and told the bus nothing, so nothing could react to a
-- model getting worse. Emitted from the rows it just wrote, one per finding.
create or replace function public.fn_ai_quality_watch()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_regs int:=0; v_spikes int:=0; v_detail jsonb; v_open int; v_owner text; v_t0 timestamptz := now();
begin
  -- 1. snapshot current per-agent override rate (builds history for spike detection)
  insert into public.ai_quality_snapshots(agent,override_pct,actions_30d)
    select agent, override_pct, actions_30d from public.v_ai_agent_health where override_pct is not null;

  -- 2. eval regressions: latest run worse than previous, or below 70 absolute
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

  -- 3. override spikes: human-facing agents whose override jumped >20pts above their trailing average
  with cur as (
    select agent, override_pct, actions_30d from public.v_ai_agent_health
    where override_pct is not null and actions_30d>=5 and agent not in ('security','onboarding','email')
  ),
  hist as (
    select agent, avg(override_pct) avg_prev, count(*) n
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

  -- 3b. tell the bus. Added 10 Aug 2026: this routine has detected quality falling since it was
  -- written and never emitted an event, so nothing downstream could react to it.
  if v_regs + v_spikes > 0 then
    perform fn_emit('ai.confidence_dropped',
                    case when se.kind='eval_regression' then 'prompt' else 'agent' end,
                    se.subject, 'ai_quality_watch',
                    se.detail || jsonb_build_object('finding', se.kind, 'severity', se.severity))
       from public.security_events se
      where se.source='ai_quality_watch' and se.kind in ('eval_regression','override_spike')
        and se.created_at >= v_t0;
  end if;

  -- 4. surface + email the founder (deduped, mirrors fn_backup_watch), only if something fired
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
end $$;
