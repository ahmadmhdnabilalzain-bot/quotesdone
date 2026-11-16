-- PROBE: A SUPPLIER MEMBER IS KNOWN BY HIS E-MAIL ON EVERY CHANNEL. Seats: customer_support + sales_engineer. Agent: W3_PEOPLE,
-- 16 Nov 2026. Pure probe: no DDL, never applied; run after a_supplier_member_is_known_by_his_email_on_every_channel.sql on a LOCAL
-- Postgres 16. It always raises, so every row is rolled back. Every party is a ZZ DEMO fixture on @example.invalid.
-- PROBE OK only if
--   1. fn_wa_context('supplier', <an active member's e-mail>) answers with HIS company (known, its name) and says who is asking
--      (asker: his role and name), exactly as the owner's address does (asker: owner);
--   2. a member found by his confirmed WhatsApp number is named as the asker too;
--   3. an invited member who has not accepted, and a removed member, are not known by their e-mail.
do $probe$
declare
  fails text := ''; s bigint; j jsonb; v_owner text := 'zz-demo-w3m-owner@example.invalid'; v_est text := 'zz-demo-w3m-est@example.invalid';
  v_inv text := 'zz-demo-w3m-inv@example.invalid'; v_gone text := 'zz-demo-w3m-gone@example.invalid';
begin
  insert into public.leads (company_name, email, claimed_by, claimed, emirate, phone, owner_email_verified)
  values ('ZZ DEMO W3M Company', v_owner, v_owner, true, 'Dubai', '+971500000761', true) returning id into s;
  insert into public.supplier_member (lead_id, email, name, phone, role, status, invited_by, accepted_at, email_verified_at, phone_confirmed_at)
  values (s, v_est, 'ZZ DEMO Estimator', '+971500000762', 'estimator', 'active', v_owner, now(), now(), now()),
         (s, v_inv, 'ZZ DEMO Invited', null, 'viewer', 'invited', v_owner, null, null, null),
         (s, v_gone, 'ZZ DEMO Removed', null, 'viewer', 'removed', v_owner, now() - interval '9 days', now() - interval '9 days', null);

  -- 1. the member's e-mail names his company and him
  j := public.fn_wa_context('supplier', v_est);
  if not coalesce((j->>'known')::boolean, false) then fails := fails || ' 1:member_unknown';
  else
    if j->>'company' is distinct from 'ZZ DEMO W3M Company' then fails := fails || ' 1:company(' || coalesce(j->>'company', 'none') || ')'; end if;
    if j->'asker'->>'role' is distinct from 'estimator' or j->'asker'->>'name' is distinct from 'ZZ DEMO Estimator' then
      fails := fails || ' 1:asker(' || coalesce((j->'asker')::text, 'none') || ')'; end if;
  end if;
  j := public.fn_wa_context('supplier', upper(v_owner));
  if not coalesce((j->>'known')::boolean, false) or j->'asker'->>'role' is distinct from 'owner' then fails := fails || ' 1:owner(' || coalesce((j->'asker')::text, 'none') || ')'; end if;

  -- 2. his confirmed number
  j := public.fn_wa_context('supplier', 'whatsapp:+971500000762');
  if not coalesce((j->>'known')::boolean, false) or j->'asker'->>'role' is distinct from 'estimator' then
    fails := fails || ' 2:phone(' || coalesce((j->'asker')::text, j::text, 'none') || ')'; end if;

  -- 3. not yet accepted, and removed
  if coalesce((public.fn_wa_context('supplier', v_inv)->>'known')::boolean, false) then fails := fails || ' 3:invited_known'; end if;
  if coalesce((public.fn_wa_context('supplier', v_gone)->>'known')::boolean, false) then fails := fails || ' 3:removed_known'; end if;

  if coalesce(fails, 'a check wrote null') <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK: an active member is known by his e-mail and by his confirmed number, named as the asker with his role; the owner is the asker as owner; an invited or removed member is not known>>';
end $probe$;
