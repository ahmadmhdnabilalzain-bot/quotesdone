-- Assigned: customer_support
-- PURE PROBE (no DDL) for an_email_is_proven_only_by_a_code_that_was_verified.sql. It always ends in raise exception
-- 'CHK<<...>>', so every row it writes rolls back. Run it with the file in one rolled-back transaction
-- (node scripts/ci/rehearse_sql.mjs <file> <this>) or after the file is applied. Its subjects are two addresses at
-- @example.invalid that it creates codes and one lead for; every real code row is counted before and after and must not move.
--   resend  : two codes sent, none entered                      -> not proven (used_at was enough before)
--   burned  : five wrong guesses, then the cap                  -> not proven
--   verify  : a fresh code entered right                        -> proven
--   trigger : a lead claimed by the unproven address            -> owner_email_verified false; by the proven one -> true
do $$
declare a text := 'zz-demo-proof-a@example.invalid'; b text := 'zz-demo-proof-b@example.invalid';
        p_resend boolean; p_burned boolean; p_verified boolean; v text; i int; burned text; la bigint; lb bigint;
        ea boolean; eb boolean; real_before bigint; real_after bigint; fail text := '';
begin
  select count(*) into real_before from public.email_verifications where email not like '%@example.invalid';
  perform public.fn_login_otp_email_issue(a, 'PROBE-H1', 'supplier', 600);
  perform public.fn_login_otp_email_issue(a, 'PROBE-H2', 'supplier', 600);
  p_resend := public.fn_email_proven(a);
  for i in 1 .. 5 loop v := public.fn_login_otp_email_verify(a, 'PROBE-WRONG', '000000', 5); end loop;
  burned := public.fn_login_otp_email_verify(a, 'PROBE-WRONG', '000000', 5);
  p_burned := public.fn_email_proven(a);
  perform public.fn_login_otp_email_issue(b, 'PROBE-H3', 'supplier', 600);
  v := public.fn_login_otp_email_verify(b, 'PROBE-H3', '000000', 5);
  p_verified := public.fn_email_proven(b);
  insert into public.leads (company_name, email, claimed, claimed_by) values ('ZZ DEMO Email Proof Probe A LLC', a, true, a) returning id, owner_email_verified into la, ea;
  insert into public.leads (company_name, email, claimed, claimed_by) values ('ZZ DEMO Email Proof Probe B LLC', b, true, b) returning id, owner_email_verified into lb, eb;
  select count(*) into real_after from public.email_verifications where email not like '%@example.invalid';
  if p_resend then fail := fail || 'two sends proved the address; '; end if;
  if burned <> 'burned' then fail := fail || 'the cap did not burn the code (' || burned || '); '; end if;
  if p_burned then fail := fail || 'a burned code proved the address; '; end if;
  if v <> 'ok' or not p_verified then fail := fail || format('a verified code (%s) did not prove the address; ', v); end if;
  if coalesce(ea, false) then fail := fail || 'the trigger granted owner_email_verified to an unproven address; '; end if;
  if not coalesce(eb, false) then fail := fail || 'the trigger did not grant owner_email_verified to a proven address; '; end if;
  if real_before <> real_after then fail := fail || 'real code rows moved; '; end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'resend_proves', p_resend, 'burned', burned, 'burned_proves', p_burned, 'verified_proves', p_verified,
    'lead_unproven_verified', ea, 'lead_proven_verified', eb, 'real_codes', real_after);
end $$;
