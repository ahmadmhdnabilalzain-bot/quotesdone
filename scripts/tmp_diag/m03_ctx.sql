CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_context()
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_raw text := nullif(btrim(current_setting('app.phase_d_fixture_context', true)),'');
  v_id  bigint;
  v_tok text;
  v_exp text;
  g     public.phase_d_test_context_grant%rowtype;
begin
  if v_raw is null then return null; end if;
  begin
    v_id := nullif(split_part(v_raw, '.', 1),'')::bigint;
  exception when others then
    return null;
  end;
  v_tok := nullif(split_part(v_raw, '.', 2),'');
  if v_id is null or v_tok is null then return null; end if;

  select * into g from public.phase_d_test_context_grant where fixture_run_id = v_id;
  if not found then return null; end if;
  -- A grant is only a context inside the transaction it was minted in.
  if g.txid <> txid_current() then return null; end if;

  select encode(extensions.hmac(convert_to(format('%s:%s:%s', g.txid, g.operation_key, g.fixture_run_id),'UTF8'), s.secret, 'sha256'), 'hex')
    into v_exp from public.phase_d_fixture_secret s where s.singleton;

  if v_exp is null or v_exp <> v_tok then return null; end if;
  return v_id;
end
$function$
