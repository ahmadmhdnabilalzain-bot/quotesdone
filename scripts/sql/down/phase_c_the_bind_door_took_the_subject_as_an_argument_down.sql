-- DOWN for phase_c_the_bind_door_took_the_subject_as_an_argument.sql.
--
-- READ THIS BEFORE RUNNING IT. Applying this file REOPENS a founder-impersonation path: it restores
-- the bind door that accepted the subject as an argument without comparing it to auth.uid(), and
-- gives service_role EXECUTE on it again. A service_role call carrying the founder's auth_user_id
-- then binds his subject with no bearer token in existence. It exists because the deployment ledger
-- requires every applied file to have a stated reversal, not because reversing this one is safe.
--
-- Removing the kernel_write_authority row returns fn_phase_c_governance_decide to refusing every
-- call with 42501 at the point where it mints its purpose-bound session. Any governance decision
-- already written stays written: public.phase_c_governance_decision is append-only and
-- a00_phase_c_governance_decision_is_session_backed refuses UPDATE and DELETE, so this file cannot
-- and does not unwind a decision the founder made.

create or replace function public.fn_phase_c_founder_subject_bind(p_subject uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_id text; v_ev bigint;
begin
  if session_user <> 'authenticator' then
    raise exception 'fn_phase_c_founder_subject_bind: this is the server path. A founder subject may only be bound on the PostgREST connection that verified the bearer token (session_user authenticator); this call arrives as session_user % / current_user %. (pccr_founder_bind_untrusted_connection)',
      session_user, current_user using errcode = '28000';
  end if;
  if current_user = 'anon' then
    raise exception 'fn_phase_c_founder_subject_bind: anon may not bind a founder subject (pd_founder_bind_untrusted_caller)'
      using errcode = '42501';
  end if;
  if p_subject is null then
    raise exception 'fn_phase_c_founder_subject_bind: a verified auth subject is required, and null is not one'
      using errcode = '28000';
  end if;

  select f.identity into v_id
    from public.phase_c_founder_identity f
   where f.auth_user_id = p_subject and f.active and f.kind = 'email';
  if v_id is null then
    raise exception 'not the founder: auth subject % does not resolve to an enabled founder identity', p_subject
      using errcode = '28000';
  end if;

  insert into public.phase_c_founder_auth_event
    (auth_subject, identity, route, txid, bound_by)
  values (p_subject, v_id, 'server_verified_subject', txid_current(), current_user)
  returning event_id into v_ev;

  perform set_config('app.phase_c_founder_auth_event', v_ev::text, true);
  return jsonb_build_object('ok', true, 'identity', v_id, 'event_id', v_ev,
    'note','transaction-local; the verifier requires this event to name the current txid');
end
$function$;

revoke execute on function public.fn_phase_c_founder_subject_bind(uuid) from authenticated;
grant  execute on function public.fn_phase_c_founder_subject_bind(uuid) to service_role;

-- The governance door already held `authenticated` before the up file; only the service_role grant
-- was removed, so only the service_role grant is restored here.
grant execute on function public.fn_phase_c_governance_decide(jsonb) to service_role;

delete from public.kernel_write_authority
 where routine_name = 'fn_phase_c_governance_decide'
   and table_name   = 'phase_c_founder_auth_event';
