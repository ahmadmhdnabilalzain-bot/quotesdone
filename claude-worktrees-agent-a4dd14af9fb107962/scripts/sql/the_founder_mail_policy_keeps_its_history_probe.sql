-- PROBE: THE FOUNDER MAIL POLICY KEEPS ITS HISTORY, AND A COSMETIC EDIT CANNOT HIDE A VIOLATION.
--
-- Assigned: it_engineer. 22 Sep 2026. Pure probe: no DDL, nothing survives it. Run AFTER
-- the_founder_mail_policy_keeps_its_history.sql, as ONE query through the Management API; it is never applied.
--
-- WHAT IT RUNS, inside a block that always raises so every write is rolled back:
--   a ZZ DEMO kind 'zz_demo_probe_founder_mail_history' is registered allowed; a founder-bound row of that
--   kind is planted (to_role founder, no address, status 'suppressed', rolled back -- it cannot reach anyone);
--   the kind is flipped to NOT allowed; then its reason is edited and updated_at pushed past the planted row
--   -- the exact shape that hid a violation from #825's updated_at exemption.
-- VERDICT: PROBE OK only if
--   1. the insert wrote 1 history row, a reason-only edit and a same-value SET wrote none, the flip wrote 1;
--   2. the planted row is judged by fn_founder_mail_policy_at as NOT allowed (the check flags it) although the
--      old rule (created_at < updated_at) would have exempted it;
--   3. a moment before the kind's first history row is NULL (not judged) and a never-registered kind is false;
--   4. on real data: it_new_bug was allowed at 21 Sep 12:00 UTC and not at 22 Sep 00:00 UTC, and every
--      policy kind's latest history value equals its current allowed_to_email.
create temp table zz_probe_verdict (verdict text, detail text) on commit drop;
do $probe$
declare
  k constant text := 'zz_demo_probe_founder_mail_history';
  n_ins int; n_cos int; n_same int; n_flip int; n_cos2 int;
  t_row timestamptz; v_new boolean; v_old_exempt boolean; v_planted int; v_pre boolean; v_never boolean;
  v_real_before boolean; v_real_after boolean; v_drift int; v_err text;
begin
  begin
    insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role, updated_at)
    values (k, true, 'ZZ DEMO probe', 'it_engineer', clock_timestamp());
    select count(*) into n_ins from public.founder_mail_policy_history where kind = k;

    update public.founder_mail_policy set reason = 'ZZ DEMO probe, reworded', updated_at = clock_timestamp() where kind = k;
    select count(*) into n_cos from public.founder_mail_policy_history where kind = k;
    update public.founder_mail_policy set allowed_to_email = true where kind = k;           -- in the SET list, unchanged
    select count(*) into n_same from public.founder_mail_policy_history where kind = k;

    t_row := clock_timestamp() + interval '1 hour';
    insert into public.notifications (type, kind, to_role, channel, sender, subject, body, status, created_at)
    values (k, k, 'founder', 'email', 'customer_support', 'ZZ DEMO probe', 'ZZ DEMO probe', 'suppressed', t_row);
    select count(*) into v_planted from public.notifications where kind = k and created_at = t_row;

    update public.founder_mail_policy set allowed_to_email = false, updated_at = clock_timestamp() where kind = k;
    select count(*) into n_flip from public.founder_mail_policy_history where kind = k;
    -- the cosmetic edit AFTER the violation, pushing updated_at past it
    update public.founder_mail_policy set reason = 'ZZ DEMO probe, reworded again', owner_role = 'ceo',
           updated_at = t_row + interval '1 hour' where kind = k;
    select count(*) into n_cos2 from public.founder_mail_policy_history where kind = k;

    v_new := public.fn_founder_mail_policy_at(k, t_row);
    select t_row < p.updated_at into v_old_exempt from public.founder_mail_policy p where p.kind = k;
    v_pre := public.fn_founder_mail_policy_at(k, clock_timestamp() - interval '1 day');
    v_never := public.fn_founder_mail_policy_at('zz_demo_probe_never_registered', now());
    raise exception 'zz_probe_rollback';
  exception when others then
    if sqlerrm <> 'zz_probe_rollback' then v_err := sqlstate || ' ' || sqlerrm; end if;
  end;
  if v_err is not null then
    insert into zz_probe_verdict values ('PROBE FAILED', 'the planted sequence raised ' || v_err);
    return;
  end if;

  v_real_before := public.fn_founder_mail_policy_at('it_new_bug', '2026-09-21 12:00:00+00');
  v_real_after  := public.fn_founder_mail_policy_at('it_new_bug', '2026-09-22 00:00:00+00');
  select count(*) into v_drift from public.founder_mail_policy p
   where public.fn_founder_mail_policy_at(p.kind, 'infinity') is distinct from p.allowed_to_email;

  insert into zz_probe_verdict values (
    case when n_ins = 1 and n_cos = 1 and n_same = 1 and n_flip = 2 and n_cos2 = 2
          and v_planted = 1 and v_new = false and v_old_exempt = true
          and v_pre is null and v_never = false
          and v_real_before = true and v_real_after = false and v_drift = 0
         then 'PROBE OK' else 'PROBE FAILED' end,
    'history rows: insert ' || n_ins || ', after reason edit ' || n_cos || ', after same-value SET ' || n_same
      || ', after flip ' || n_flip || ', after cosmetic edit past the violation ' || n_cos2 || ' (want 1,1,1,2,2)'
      || '; planted rows ' || v_planted || ' judged allowed=' || coalesce(v_new::text, 'null') || ' (want false)'
      || ', old updated_at rule exempted it=' || coalesce(v_old_exempt::text, 'null') || ' (want true: the bug)'
      || '; pre-history ' || coalesce(v_pre::text, 'null') || ' (want null), never registered '
      || coalesce(v_never::text, 'null') || ' (want false)'
      || '; it_new_bug 21 Sep 12:00 ' || coalesce(v_real_before::text, 'null') || ' / 22 Sep 00:00 '
      || coalesce(v_real_after::text, 'null') || ' (want true/false); kinds whose history disagrees with the policy '
      || v_drift || ' (want 0); all planted writes rolled back');
end
$probe$;
select verdict, detail from zz_probe_verdict;
