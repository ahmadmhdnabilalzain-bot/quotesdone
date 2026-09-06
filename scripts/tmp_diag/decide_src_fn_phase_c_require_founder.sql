CREATE OR REPLACE FUNCTION public.fn_phase_c_require_founder(p_actor text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_sub    uuid;
  v_id     text;
  v_ev     bigint;
  v_route  text;
begin
  -- ---- ROUTE A: a bearer token PostgREST already verified -------------------------------------
  -- auth.uid() is null for a service_role connection and for anything that did not arrive with a
  -- user JWT. It cannot be set by a caller.
  begin
    v_sub := auth.uid();
  exception when others then
    v_sub := null;
  end;
  if v_sub is not null then
    select f.identity into v_id
      from public.phase_c_founder_identity f
     where f.auth_user_id = v_sub and f.active and f.kind = 'email';
    v_route := 'auth.uid()';
  end if;

  -- ---- ROUTE B: the server path bound a subject it verified ------------------------------------
  if v_id is null then
    v_ev := nullif(btrim(current_setting('app.phase_c_founder_auth_event', true)),'')::bigint;
    if v_ev is not null then
      select e.identity, e.auth_subject into v_id, v_sub
        from public.phase_c_founder_auth_event e
        join public.phase_c_founder_identity f on f.identity = e.identity
       where e.event_id = v_ev
         -- BOUND TO THIS TRANSACTION. A GUC pointing at an event from another transaction is not a
         -- session: it is a value a caller typed.
         and e.txid = txid_current()
         and f.active and f.kind = 'email';
      v_route := 'fn_phase_c_founder_subject_bind';
    end if;
  end if;

  if v_id is null then
    -- E39's vector, refused: knowing the email is no longer being the founder.
    raise exception 'not the founder: no verified auth subject on this call. The founder is resolved from auth.uid() or from a subject os_api verified and bound with fn_phase_c_founder_subject_bind; a caller-supplied identity is not authentication. (PCCR-003)'
      using errcode = '28000',
            hint = 'Call with the founder''s bearer token so auth.uid() resolves, or verify the JWT in os_api and bind the verified subject first.';
  end if;

  -- p_actor is now an ASSERTION, not a source. Supplying one that disagrees with the verified
  -- identity is a caller claiming to be someone else and is refused; supplying none is fine.
  if coalesce(btrim(p_actor),'') <> '' and lower(btrim(p_actor)) <> lower(v_id) then
    raise exception 'not the founder: the call asserts identity % and the verified auth subject resolves to %',
      lower(btrim(p_actor)), v_id using errcode = '28000';
  end if;

  return v_id;
end $function$
