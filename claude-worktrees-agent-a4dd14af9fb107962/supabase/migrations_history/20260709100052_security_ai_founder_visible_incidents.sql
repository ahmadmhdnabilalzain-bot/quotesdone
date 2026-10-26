-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709100052   name: security_ai_founder_visible_incidents
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- material security items must stay founder-visible (not auto-cleared like 'incident')
delete from agent_actions where agent='security_ai' and kind='incident';

create or replace function public.sec_incident(p_sig text, p_cond boolean, p_sev text, p_title text, p_reco text)
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if p_cond and not exists (select 1 from agent_actions where kind='security_incident' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
    values ('security_ai','security_incident','pending',p_sev,p_title,p_reco,jsonb_build_object('signal',p_sig),'security',p_sig);
  end if;
end $$;

-- point KPI counters at the new kind
create or replace view public.security_kpis as
select
  (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r') as tables,
  (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relrowsecurity) as rls_enabled,
  round(100.0*(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relrowsecurity)
        / nullif((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'),0),1) as rls_coverage_pct,
  (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relrowsecurity and not exists (select 1 from pg_policy pol where pol.polrelid=c.oid)) as rls_deny_default,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and (p.proconfig is null or not exists (select 1 from unnest(p.proconfig) cc where cc like 'search_path=%'))) as secdef_mutable_searchpath,
  (select count(*) from security_events where severity in ('high','critical') and created_at>=now()-interval '7 days') as high_sev_events_7d,
  (select count(*) from security_events where created_at>=now()-interval '7 days') as events_7d,
  (select count(*) from fraud_flags where coalesce(status,'') not in ('resolved','dismissed')) as open_fraud_flags,
  (select count(*) from agent_actions where kind='security_incident' and status in ('pending','needs_review')) as open_incidents,
  (select count(*) from error_events where created_at>=now()-interval '24 hours') as errors_24h,
  (select count(*) from auth.users where banned_until is not null) as banned_users,
  (select count(*) from auth.users where last_sign_in_at>=now()-interval '7 days') as active_users_7d,
  coalesce((select count(*) from auth.audit_log_entries where created_at>=now()-interval '7 days' and payload->>'action' ilike '%fail%'),0) as failed_logins_7d,
  (select count(*) from app_secrets) as secrets_count;
revoke all on public.security_kpis from anon, authenticated;

create or replace function public.fn_security_ai()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare k record; v_score numeric; n int;
begin
  select * into k from security_kpis;
  v_score := round(greatest(0, 100
    - (100-coalesce(k.rls_coverage_pct,100))
    - coalesce(k.secdef_mutable_searchpath,0)*4
    - coalesce(k.high_sev_events_7d,0)*12
    - coalesce(k.open_fraud_flags,0)*6
    - (case when coalesce(k.errors_24h,0)>200 then 10 when coalesce(k.errors_24h,0)>50 then 5 else 0 end)
    - (case when coalesce(k.failed_logins_7d,0)>50 then 10 else 0 end)),1);
  insert into security_kpi_snapshots(snapshot_date,kpis) values (current_date, to_jsonb(k)||jsonb_build_object('security_score',v_score))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();
  perform sec_incident('rls_gap', coalesce(k.rls_coverage_pct,100) < 100, 'high', 'RLS coverage gap',
    'Row-Level Security is not enabled on every public table ('||k.rls_coverage_pct||'%). The auto-RLS trigger should prevent this — investigate immediately.');
  perform sec_incident('mutable_searchpath', coalesce(k.secdef_mutable_searchpath,0) > 0, 'medium', 'Functions with mutable search_path',
    k.secdef_mutable_searchpath||' SECURITY DEFINER function(s) do not pin search_path — a privilege-escalation risk. Pin search_path on each.');
  perform sec_incident('high_sev_events', coalesce(k.high_sev_events_7d,0) > 0, 'high', 'High-severity security events',
    k.high_sev_events_7d||' high/critical security event(s) in the last 7 days (malware/dangerous uploads etc.). Review and quarantine.');
  perform sec_incident('open_fraud', coalesce(k.open_fraud_flags,0) > 0, 'high', 'Open fraud flags',
    k.open_fraud_flags||' unresolved fraud flag(s). Review the flagged accounts/transactions.');
  perform sec_incident('error_spike', coalesce(k.errors_24h,0) > 200, 'medium', 'Application error spike',
    k.errors_24h||' application errors in 24h — investigate for abuse or a fault.');
  perform sec_incident('failed_login_spike', coalesce(k.failed_logins_7d,0) > 50, 'high', 'Failed-login spike',
    k.failed_logins_7d||' failed logins in 7 days — possible credential-stuffing/brute force. Consider rate-limiting/MFA.');
  perform sec_incident('auth_hardening', true, 'low', 'Auth hardening review',
    'Confirm in Supabase Auth settings: leaked-password protection ON, MFA enforced for admin, sensible OTP expiry, least-privilege API keys.');
  select count(*) into n from agent_actions where agent='security_ai' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'security_score',v_score,'kpis',to_jsonb(k),'open_incidents',n);
end $fn$;
revoke all on function public.fn_security_ai() from anon, authenticated, public;
