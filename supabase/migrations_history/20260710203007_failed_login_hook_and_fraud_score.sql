-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710203007   name: failed_login_hook_and_fraud_score
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- 1) Supabase password-verification-attempt auth hook: log failed password logins.
create or replace function public.hook_password_verification_attempt(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare v_uid uuid; v_valid boolean; v_email text; v_recent int;
begin
  begin v_uid := (event->'user_id')::text::uuid; exception when others then v_uid := null; end;
  v_valid := coalesce((event->>'valid')::boolean, true);
  if not v_valid then
    begin select email into v_email from auth.users where id = v_uid; exception when others then v_email := null; end;
    -- count this actor's failures in the last 15 min to grade severity
    select count(*) into v_recent from public.security_events
      where kind='login_failed' and subject = coalesce(v_email,'')
        and created_at > now() - interval '15 minutes';
    insert into public.security_events(kind, severity, source, subject, detail)
    values ('login_failed',
            case when v_recent >= 4 then 'high' else 'medium' end,
            'password',
            coalesce(v_email,''),
            jsonb_build_object('user_id', v_uid, 'recent_15m', v_recent + 1,
                               'why', 'password verification failed'));
  end if;
  return '{}'::jsonb;   -- tracking only; never blocks
end $$;

revoke execute on function public.hook_password_verification_attempt(jsonb) from anon, authenticated, public;
grant  execute on function public.hook_password_verification_attempt(jsonb) to supabase_auth_admin;

-- 2) Refresh v_auth_watch to also surface failed password logins.
create or replace view public.v_auth_watch as
select created_at as at, 'otp_high_attempts'::text as signal,
       case when attempts>=5 then 'high' else 'medium' end::text as severity,
       coalesce(phone,'')::text as subject,
       jsonb_build_object('table','customer_phone_otps','attempts',attempts,
                          'consumed',consumed,'customer_id',customer_id) as detail
from public.customer_phone_otps
where attempts>=3 and created_at > now()-interval '30 days'
union all
select created_at, 'verify_high_attempts',
       case when attempts>=5 then 'high' else 'medium' end,
       coalesce(email, phone,''),
       jsonb_build_object('table','phone_verifications','attempts',attempts,
                          'user_kind',user_kind,'used',(used_at is not null))
from public.phone_verifications
where attempts>=3 and created_at > now()-interval '30 days'
union all
select created_at, kind,
       coalesce(severity, case when kind='login_failed' then 'medium' else 'info' end),
       coalesce(subject,''), coalesce(detail,'{}'::jsonb)
from public.security_events
where kind in ('admin_login','login_failed') and created_at > now()-interval '30 days';
revoke all on public.v_auth_watch from anon, authenticated;

-- 3) Unified per-actor fraud score (0-100) from open fraud_flags.
create or replace view public.v_fraud_score as
select subject_type, subject_id, open_flags, latest_flag, reasons,
       least(100, raw)::int as score,
       case when least(100,raw) >= 60 then 'high'
            when least(100,raw) >= 25 then 'medium' else 'low' end as tier
from (
  select subject_type, subject_id,
         count(*) as open_flags,
         max(created_at) as latest_flag,
         array_agg(distinct kind) as reasons,
         sum(case lower(severity)
               when 'critical' then 60 when 'high' then 40
               when 'medium' then 15 when 'low' then 5 else 10 end) as raw
  from public.fraud_flags
  where coalesce(status,'open') not in ('resolved','dismissed','closed','false_positive')
  group by subject_type, subject_id
) s
order by score desc;
revoke all on public.v_fraud_score from anon, authenticated;
