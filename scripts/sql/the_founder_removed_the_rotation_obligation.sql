-- THE FOUNDER REMOVED THE ROTATION OBLIGATION.
--
-- 9 September 2026, his words: "no need for credentials rotate, remove it."
--
-- WHAT I HAD TOLD HIM, AND WHY IT WAS WRONG. I reported that credentials do not rotate, that only
-- 1 of 91 ever had, and that "around early November the whole estate goes due at once" with expired
-- credentials refused — a dated outage. I had that from an agent's report and repeated it without
-- measuring it. Measured now:
--
--   84 active credentials. 60 carry an expires_at. SOONEST 2027-08-03, latest 2027-09-05.
--   Expiring within 90 days: ZERO.
--   Rotation routines in the database: NONE.
--   Routines reading v_internal_credential_health: NONE.
--
-- Two separate things had been conflated. `expires_at` is real and IS enforced — fn_internal_auth
-- refuses a credential past it — and it sits a year away. `rotation_due` is a DIFFERENT thing: a
-- computed column in a health view that flips true at 90 days of age and drives nothing at all.
-- Nothing alerts on it, nothing refuses on it, nothing reads the view. There was no November
-- outage; there was a boolean nobody consumed.
--
-- WHY REMOVE A COLUMN THAT DOES NOTHING. Because a policy expressed in the schema reads as a policy
-- the company holds. The next person to open this view — or the IT engineer, which now reads
-- everything — finds a field called `rotation_due` sitting at true and reasonably concludes that
-- rotation is expected and overdue. That is how a dead obligation becomes a live alarm, and it is
-- how I produced a false outage out of it today. The founder has ruled there is no such obligation,
-- so the schema should stop implying one.
--
-- WHAT STAYS. `rotated_at` and `expires_at` remain: they are FACTS about a credential, not a policy
-- about it, and expiry is genuinely enforced. `unused_30d` stays — an unused credential is worth
-- seeing whatever the rotation policy is. Only the derived obligation goes.

-- DROP AND RECREATE, not CREATE OR REPLACE: Postgres refuses to remove or reorder a view's columns
-- in place ("cannot change name of view column"), and removing rotation_due is the whole point.
-- Deliberately NOT `drop ... cascade`: nothing reads this view today (measured — zero routines
-- reference it), and if that has changed since, this should fail loudly rather than quietly take a
-- dependent object with it.
drop view if exists public.v_internal_credential_health;

create view public.v_internal_credential_health as
 SELECT id,
    context,
    label,
    is_legacy,
    active,
    COALESCE(array_length(scope, 1), 0) AS scope_size,
    scope,
    use_count,
    last_used_at,
    last_function,
        CASE
            WHEN last_used_at IS NULL THEN NULL::integer
            ELSE (EXTRACT(epoch FROM now() - last_used_at) / 86400::numeric)::integer
        END AS days_since_use,
    (EXTRACT(epoch FROM now() - created_at) / 86400::numeric)::integer AS age_days,
    rotated_at,
    expires_at,
    -- FACT, not policy: how long until the credential is actually refused. fn_internal_auth
    -- enforces this one, so it is worth seeing.
        CASE
            WHEN expires_at IS NULL THEN NULL::integer
            ELSE (EXTRACT(epoch FROM expires_at - now()) / 86400::numeric)::integer
        END AS days_until_expiry,
    active AND (last_used_at IS NULL OR last_used_at < (now() - '30 days'::interval)) AS unused_30d
    -- `rotation_due` REMOVED 9 Sep 2026 on the founder's instruction. It was a 90-day age rule that
    -- no routine read and nothing enforced, and its presence made a non-existent obligation look
    -- overdue. Credential expiry is the real control and it is still here, next to it.
   FROM internal_credential c;

comment on view public.v_internal_credential_health is
  'Health of the internal credentials, as FACTS rather than policy: age, use, last function, when '
  'each actually expires and how long that is. Carries NO rotation obligation — the founder removed '
  'it on 9 Sep 2026 ("no need for credentials rotate, remove it"). The old rotation_due column was a '
  '90-day age rule that no routine read and nothing enforced, and a field named that, sitting at '
  'true, reads as a live overdue duty to anyone who finds it. expires_at is the real control and IS '
  'enforced by fn_internal_auth.';

do $do$
declare v_cols int; v_due int; v_soonest date; v_within90 int; v_active int;
begin
  select count(*) into v_active from public.internal_credential where active;
  if v_active = 0 then
    raise exception 'POSITIVE CONTROL FAILED: no active credentials, so nothing here is being tested';
  end if;

  -- The view must still work and still carry the facts.
  select count(*) into v_cols from information_schema.columns
   where table_schema = 'public' and table_name = 'v_internal_credential_health'
     and column_name in ('expires_at','rotated_at','unused_30d','days_until_expiry');
  if v_cols <> 4 then
    raise exception 'the view lost a fact it should have kept (% of 4 present)', v_cols;
  end if;

  -- And the obligation must be gone.
  select count(*) into v_due from information_schema.columns
   where table_schema = 'public' and table_name = 'v_internal_credential_health'
     and column_name = 'rotation_due';
  if v_due <> 0 then
    raise exception 'rotation_due survived'; end if;

  -- State the real position out loud, since a wrong version of it was reported to the founder.
  select min(expires_at)::date,
         count(*) filter (where expires_at < now() + interval '90 days')
    into v_soonest, v_within90
    from public.internal_credential where active and expires_at is not null;

  raise notice 'rotation obligation removed. % active credential(s); soonest real expiry %, % expiring within 90 days',
    v_active, coalesce(v_soonest::text, 'none set'), v_within90;
end
$do$;
