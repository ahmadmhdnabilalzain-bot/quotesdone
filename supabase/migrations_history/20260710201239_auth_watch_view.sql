-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710201239   name: auth_watch_view
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

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
select created_at, 'admin_login', coalesce(severity,'info'),
       coalesce(subject,''), coalesce(detail,'{}'::jsonb)
from public.security_events
where kind='admin_login' and created_at > now()-interval '30 days';
revoke all on public.v_auth_watch from anon, authenticated;

select count(*) as rows_now from public.v_auth_watch;
