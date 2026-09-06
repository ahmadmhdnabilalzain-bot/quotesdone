CREATE OR REPLACE FUNCTION public.fn_phase_d_test_context_open(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_op    text := nullif(btrim(coalesce(p_input->>'operation_key','')),'');
  v_label text := nullif(btrim(coalesce(p_input->>'label','')),'');
  v_id    bigint;
  v_tok   text;
begin
  if v_op is null or v_label is null then
    raise exception 'fn_phase_d_test_context_open: operation_key and label are both required (pd_test_context_input_invalid)'
      using errcode = '22023';
  end if;

  -- The frontend and an ordinary signed-in user are refused before anything else is read. This is
  -- the same refusal fn_phase_d_fixture_scenario already made; it is repeated here because this
  -- routine is now the only door and a door must carry its own lock.
  if current_user in ('anon','authenticated') then
    raise exception 'fn_phase_d_test_context_open: % may not open a Phase D test context (pd_test_context_untrusted_caller)',
      current_user using errcode = '42501';
  end if;

  if not exists (select 1 from public.phase_d_test_operation o
                  where o.operation_key = v_op and o.enabled) then
    raise exception 'fn_phase_d_test_context_open: % is not an enabled approved Phase D test operation. A service-role caller with no approved audit context may not build fixtures. (pd_test_context_operation_unapproved)',
      v_op using errcode = '42501';
  end if;

  insert into public.phase_d_test_context_grant
    (operation_key, label, txid, backend_pid, granted_to, session_user_name)
  values (v_op, v_label, txid_current(), pg_backend_pid(), current_user, session_user)
  returning fixture_run_id into v_id;

  -- BOUND TO THE TRANSACTION. A token minted here does not verify in any other transaction, so it
  -- cannot be lifted out of a log, a query plan or an error message and replayed.
  select encode(extensions.hmac(convert_to(format('%s:%s:%s', txid_current(), v_op, v_id),'UTF8'), s.secret, 'sha256'), 'hex')
    into v_tok from public.phase_d_fixture_secret s where s.singleton;

  perform set_config('app.phase_d_fixture_context', format('%s.%s', v_id, v_tok), true);

  return jsonb_build_object(
    'ok', true, 'fixture_run_id', v_id, 'operation_key', v_op, 'label', v_label,
    'txid', txid_current(),
    'note', 'transaction-local; abort this transaction when finished. The token is bound to this '
         || 'txid and to nothing else.');
end
$function$
