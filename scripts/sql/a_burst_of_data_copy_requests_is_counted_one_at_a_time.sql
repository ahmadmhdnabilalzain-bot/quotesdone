-- A BURST OF DATA-COPY REQUESTS IS COUNTED ONE AT A TIME.
--
-- Assigned: customer_support (built by it_engineer). 12 Nov 2026. Second review of PR #1986, follow-up 2.
-- a_copy_of_a_persons_data_holds_their_own_records_and_nobody_elses.sql limited pdpl_request_me('export') to 3 copies
-- per person in 10 minutes by counting pdpl_requests and then inserting, with no lock: N calls in parallel each count
-- before any of them inserts, so the ceiling is "3 + however many arrive at once". A transaction-scoped advisory lock on
-- the person's verified e-mail, taken BEFORE the count, makes the second call wait until the first has inserted (or
-- rolled back), so each counts what the one before it wrote. Different people never wait for each other.
--
-- THE BODY BELOW IS #1986's, with only the lock added. By the time this file is applied that body is live: right before
-- applying, compare `select pg_get_functiondef('public.pdpl_request_me(text)'::regprocedure)` with this file's body; any
-- other difference is a change made since, and this file must be rebased on it rather than undo it.
-- CREATE OR REPLACE keeps the ACL; the one overload (pdpl_request_me(text), enumerated live 12 Nov 2026) is restated:
-- revoked from public and anon, granted to authenticated, as live.
-- Probe: a_burst_of_data_copy_requests_is_counted_one_at_a_time_probe.sql.

create or replace function public.pdpl_request_me(p_kind text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_em text := public.fn_pdpl_my_verified_email(); v_id uuid;
begin
  if v_em is null then
    return jsonb_build_object('ok', false, 'code', 'email_not_verified',
      'message', 'Verify your email address in your account first.', 'message_ar', 'يُرجى توثيق بريدكم الإلكتروني في حسابكم أولًا.');
  end if;
  if p_kind not in ('export', 'delete') then return jsonb_build_object('ok', false, 'code', 'bad_kind'); end if;
  -- ERASE NEEDS A SECOND VERIFIED ACTION: a code is emailed and the clock starts only at pdpl_confirm_me.
  if p_kind = 'delete' then
    return public.fn_pdpl_open(v_em, 'delete', 'self_service') || jsonb_build_object('next', 'pdpl_confirm_me(request_id, code)');
  end if;
  -- 12 Nov 2026 (review of #1986): at most 3 copies in 10 minutes. The PDF, the data file and one retry fit; a loop
  -- of signed-in calls does not write unbounded request and log rows or renders. The lock (second review): one
  -- person's requests are counted one at a time, so a parallel burst cannot all pass the count before any inserts.
  perform pg_advisory_xact_lock(hashtext('pdpl_export:' || v_em));
  if (select count(*) from public.pdpl_requests q where q.email = v_em and q.kind = 'export'
       and q.created_at > now() - interval '10 minutes') >= 3 then
    return jsonb_build_object('ok', false, 'code', 'too_many_exports');
  end if;
  insert into public.pdpl_requests (kind, email, role, details, status, verified_via, verified_at, handled_by)
  values (p_kind, v_em, 'self_service', 'signed-in, email verified by code', 'received', 'session+email_verified', now(), 'self_service')
  returning id into v_id;
  return public.fn_pdpl_carry_out(v_id);
end $function$;
revoke execute on function public.pdpl_request_me(text) from public, anon;
grant execute on function public.pdpl_request_me(text) to authenticated;

select case
  when has_function_privilege('anon', 'public.pdpl_request_me(text)', 'execute') then 'PROBE FAILED: anonymous callers reach pdpl_request_me'
  when not has_function_privilege('authenticated', 'public.pdpl_request_me(text)', 'execute') then 'PROBE FAILED: signed-in people lost the self-service door'
  when pg_get_functiondef('public.pdpl_request_me(text)'::regprocedure) !~ 'pg_advisory_xact_lock\(hashtext\(''pdpl_export:'' \|\| v_em\)\);\s+if \(select count'
    then 'PROBE FAILED: the lock is not taken right before the count'
  else 'PROBE OK: one person''s export requests are counted one at a time'
end as verdict;
