-- Assigned: customer_support (built by it_engineer). 12 Nov 2026.
-- PURE PROBE (no DDL): raises at the end, so the request and log rows it writes are rolled back. Run AFTER
-- a_burst_of_data_copy_requests_is_counted_one_at_a_time.sql is applied (and after the #1986 file it builds on).
--
-- WHAT IT CAN AND CANNOT SHOW. A race needs two sessions; one rolled-back transaction is one session, so a parallel burst
-- cannot be reproduced here deterministically (and the probe must not commit rows to stage one). It therefore proves
-- the two things a single session can: (1) the live body takes pg_advisory_xact_lock on the person's e-mail immediately
-- before the count (read from pg_get_functiondef), and (2) signed in as the ZZ DEMO customer (@example.invalid, is_demo,
-- a verified e-mail), the 4th export inside 10 minutes is refused with 'too_many_exports' while the 3rd is served
-- (earlier exports of that address in the window are counted too, so it asks until the refusal and checks the count).
-- It needs that ZZ DEMO customer row and fails closed without it.
do $$
declare v_em text; v_r jsonb; v_served int := 0; v_before int; i int;
begin
  if pg_get_functiondef('public.pdpl_request_me(text)'::regprocedure) !~ 'pg_advisory_xact_lock\(hashtext\(''pdpl_export:'' \|\| v_em\)\);\s+if \(select count'
    then raise exception 'CHK<<PROBE FAILED: pdpl_request_me does not lock the person''s e-mail right before the count>>'; end if;
  select lower(email) into v_em from public.customers
   where is_demo and email like '%@example.invalid' and email_verified order by created_at limit 1;
  if v_em is null then raise exception 'CHK<<PROBE FAILED: no verified ZZ DEMO customer to probe>>'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('email', v_em, 'role', 'authenticated')::text, true);
  select count(*) into v_before from public.pdpl_requests where email = v_em and kind = 'export' and created_at > now() - interval '10 minutes';
  for i in 1..4 loop
    v_r := public.pdpl_request_me('export');
    if coalesce((v_r->>'ok')::boolean, false) then v_served := v_served + 1;
    elsif v_r->>'code' = 'too_many_exports' then exit;
    else raise exception 'CHK<<PROBE FAILED: an export was refused for another reason: %>>', v_r->>'code'; end if;
  end loop;
  if v_r->>'code' is distinct from 'too_many_exports' then raise exception 'CHK<<PROBE FAILED: four exports in a row were all served>>'; end if;
  if v_before + v_served <> 3 then raise exception 'CHK<<PROBE FAILED: % served after % in the window: the ceiling is not 3>>', v_served, v_before; end if;
  raise exception 'CHK<<PROBE OK: the lock is taken before the count, and the 4th copy in 10 minutes is refused>>';
end $$;
