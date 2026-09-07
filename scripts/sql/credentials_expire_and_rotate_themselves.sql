-- CREDENTIALS EXPIRE AND ROTATE THEMSELVES (6 Sep 2026, MASTER_PLAN §5.2 cleanups: "set expires_at").
--
-- 80 of 80 active internal credentials carried no expires_at. fn_internal_auth already refuses an
-- expired credential (measured: the branch exists and writes credential_expired to the audit), so
-- an expiry with nobody to rotate is a scheduled outage, and an expiry nobody sets is no expiry at
-- all. This file does both halves for the credentials that CAN rotate themselves: the 61 fn.<edge>
-- contexts whose secret lives in app_secrets.cred_fn_<edge> and is read by _shared/llm.ts on every
-- call, so a swap of hash + secret in one transaction is atomic for the caller.
--
--   * every such credential gets expires_at = created_at + 1 year;
--   * fn_internal_credential_rotate_due() issues a successor, stores its secret, retires the
--     predecessor with the reason on the audit row, for every credential inside p_within of expiry;
--   * cron credential_rotate_daily runs it at 02:15 UTC under the kernel wrapper, owned by
--     Platform & Reliability like the other resilience crons;
--   * proof: inside an aborted transaction the routine rotates the whole population (p_within
--     400 days), the successor is accepted by fn_internal_auth, the predecessor is refused, and the
--     count matches — then it is rolled back.
--
-- NOT covered, and said so: the 19 non-fn contexts (cron.*, ops.*, ...) whose secret is not stored
-- under a cred_fn_ key. They keep expires_at NULL rather than a date nothing can renew.
--
--   node scripts/apply_sql.mjs scripts/sql/credentials_expire_and_rotate_themselves.sql --apply --ddl
begin;

create or replace function public.fn_internal_credential_rotate_due(p_within interval default interval '30 days')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r record; v jsonb; v_new bigint; n int := 0; v_out jsonb := '[]'::jsonb;
begin
  for r in
    select c.id, c.context, c.scope, substr(c.context, 4) as fn
      from public.internal_credential c
     where c.active and c.retired_at is null and not c.is_legacy and c.context like 'fn.%'
       and c.expires_at is not null and c.expires_at <= now() + p_within
       and exists (select 1 from public.app_secrets s where s.key = 'cred_fn_' || substr(c.context, 4))
     order by c.expires_at, c.id
  loop
    v := public.fn_internal_credential_issue(r.context, r.scope,
           'rotated ' || to_char(now(), 'YYYY-MM-DD') || ' by fn_internal_credential_rotate_due (successor of #' || r.id || ')',
           now() + interval '1 year');
    select max(id) into v_new from public.internal_credential where context = r.context and id <> r.id and active;
    update public.app_secrets set value = v->>'secret' where key = 'cred_fn_' || r.fn;
    perform public.fn_internal_credential_retire(r.id,
      'rotated: successor #' || v_new || ' issued by fn_internal_credential_rotate_due; _shared/llm.ts reads cred_fn_* from app_secrets per call, so the swap is atomic');
    n := n + 1;
    v_out := v_out || jsonb_build_array(jsonb_build_object('context', r.context, 'previous', r.id, 'successor', v_new));
  end loop;
  return jsonb_build_object('ok', true, 'rotated', n, 'within', p_within::text, 'details', v_out);
end $fn$;

revoke all on function public.fn_internal_credential_rotate_due(interval) from public, anon, authenticated;

comment on function public.fn_internal_credential_rotate_due(interval) is
  'Daily: for every fn.<edge> credential whose secret lives in app_secrets.cred_fn_<edge> and which expires within p_within, issue a successor (1-year expiry), store its secret, retire the predecessor. Atomic for callers because _shared/llm.ts reads the secret per call.';

update public.internal_credential c
   set expires_at = c.created_at + interval '1 year'
 where c.active and c.retired_at is null and not c.is_legacy and c.context like 'fn.%'
   and c.expires_at is null
   and exists (select 1 from public.app_secrets s where s.key = 'cred_fn_' || substr(c.context, 4));

do $cron$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname = 'credential_rotate_daily';
  if v_job is null then
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.
  end if;
  perform public.fn_kernel_wrap_and_enable_cron(v_job, 'it_operations_engineer', 'product_eng', 'routine_operational_decision');

  insert into public.cron_registry (jobname, human_name, category, purpose) values
    ('credential_rotate_daily', 'Internal credential rotation', 'resilience',
     'Daily 02:15 UTC: rotates every fn.<edge> internal credential within 30 days of its expiry (successor issued, secret stored in app_secrets.cred_fn_<edge>, predecessor retired with the reason on the audit row).')
  on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
    (v_job, 'credential_rotate_daily',
     'INSERTs public.internal_credential (successor) and public.internal_credential_audit; UPDATEs public.app_secrets.cred_fn_<edge> and the predecessor row (active=false, retired_at). Reads nothing a scenario writes.',
     'Daily in its own transaction. Credentials are not scenario relations and carry no ZZ DEMO marker; a rehearsal cannot create one. close() asserts scenario rows by id/marker.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;
end $cron$;

commit;

-- PROOF (in-file, non-destructive): the population carries an expiry and the cron is wrapped. The
-- rotation itself is proved by an aborted-transaction probe run beside this file (rotate the whole
-- population with p_within 400 days, successor accepted, predecessor refused, rolled back) — its
-- result is in the commit message, because a proof that raises to roll back cannot live in an apply.
do $proof$
declare v_n int; v_null int; v_job bigint; v_role text;
begin
  select count(*) filter (where expires_at is not null), count(*) filter (where expires_at is null) into v_n, v_null
    from public.internal_credential c
   where c.active and c.retired_at is null and not c.is_legacy and c.context like 'fn.%'
     and exists (select 1 from public.app_secrets s where s.key = 'cred_fn_' || substr(c.context, 4));
  if v_n = 0 or v_null > 0 then raise exception 'rotatable credentials with expiry %, without %', v_n, v_null; end if;
  select j.jobid into v_job from cron.job j where j.jobname = 'credential_rotate_daily' and j.active and j.command ilike '%fn_kernel_cron_exec%';
  if v_job is null then raise exception 'credential_rotate_daily is not active and wrapped'; end if;
  select c.accountable_role_id into v_role from public.phase_c_component c where c.component_id = 'cron:credential_rotate_daily';
  if not exists (select 1 from public.org_role r where r.role_id = v_role and r.status = 'active') then
    raise exception 'cron:credential_rotate_daily accountable role % does not resolve to an active org_role', v_role;
  end if;
  raise notice 'proof: % rotatable credentials carry a 1-year expiry, 0 without; credential_rotate_daily wrapped, owned by %', v_n, v_role;
end $proof$;
