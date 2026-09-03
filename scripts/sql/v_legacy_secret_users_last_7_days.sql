-- A FINDING WITH NO WINDOW IS A FINDING FOREVER (3 Sep 2026).
--
-- v_legacy_secret_users lists callers that authenticated with the legacy shared secret. It had no
-- time window, so three callers whose last legacy use was 6-13 Aug 2026 (ai_gateway, postiz_publish,
-- knowledge_exam — all moved to scoped credentials since) were reported by fn_resilience_watch on
-- every pass, and "Resilience: the platform needs attention" reached the founder three times in the
-- 24 hours measured on 3 Sep with nothing in it he could act on. The view now covers the last seven
-- days: a caller still on the legacy secret THIS WEEK is a finding; one that used it a month ago is
-- history, and the audit table keeps that history.

create or replace view public.v_legacy_secret_users as
  select function_name, count(*) as uses, min(at) as first_seen, max(at) as last_seen
    from public.internal_credential_audit
   where reason = 'legacy_secret_used'
     and at > now() - interval '7 days'
   group by function_name
   order by count(*) desc;

comment on view public.v_legacy_secret_users is
  'Callers that authenticated with the legacy shared secret in the LAST 7 DAYS (windowed 3 Sep 2026; it was all-time and fn_resilience_watch paged the founder about August forever).';
