-- THE PRICE ROUTER STOPPED ANSWERING STRANGERS.
--
-- fn_price_confidence was rewritten today so the sales engineer could judge a quote against the
-- 1,086 UAE benchmarks seeded in the same session. The rewrite was a DROP and CREATE rather than a
-- CREATE OR REPLACE, and a plain CREATE grants EXECUTE to PUBLIC. So the routine came back
-- reachable by `anon` — an unauthenticated visitor could ask the platform what it believes any
-- trade costs, and by walking amounts, binary-search the low/typical/high band the marketplace
-- prices against.
--
-- CREATE OR REPLACE preserves the ACL; CREATE does not. That is the difference between a rewrite
-- that keeps its permissions and one that quietly opens itself, and it is why every SECURITY
-- DEFINER routine in this estate is supposed to carry an explicit revoke in the same file. This one
-- did not, and the standing check caught it within the hour:
--
--   "these SECURITY DEFINER routines answer an unauthenticated caller: [fn_price_confidence]"
--
-- WHAT IT LEAKS, PRECISELY. Not a customer's data — the routine takes a trade and an amount and
-- returns a verdict. What it exposes is the company's own pricing intelligence: the bands, and
-- therefore the position the sales engineer negotiates from. A supplier could calibrate a quote to
-- sit exactly inside "fair" without ever registering.
--
-- WHY NOT ALSO REVOKE FROM authenticated. Because the check names it in a second assertion — the
-- authenticated-executable SECURITY DEFINER set is pinned at exactly the two customer-document
-- routines, and a third arriving breaks it. Both grants go.

-- THERE ARE TWO OVERLOADS, AND THE FIRST ATTEMPT ONLY CLOSED ONE. A revoke names a signature, so
-- revoking (text,numeric,numeric,text) left (text,numeric) wide open — and the assertion below
-- caught it, which is the only reason this file is correct. Both are named explicitly rather than
-- looped, so a third overload appearing later fails the check rather than being silently missed.
revoke execute on function public.fn_price_confidence(text, numeric, numeric, text) from public, anon, authenticated;
revoke execute on function public.fn_price_confidence(text, numeric)                 from public, anon, authenticated;

do $do$
declare v_anon int; v_auth int; v_svc int; v_works jsonb;
begin
  select count(*) into v_anon from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_price_confidence'
     and (has_function_privilege('anon', p.oid, 'execute'));
  select count(*) into v_auth from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_price_confidence'
     and (has_function_privilege('authenticated', p.oid, 'execute'));
  select count(*) into v_svc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_price_confidence'
     and (has_function_privilege('service_role', p.oid, 'execute'));

  if v_anon <> 0 then raise exception 'anon can still execute fn_price_confidence'; end if;
  if v_auth <> 0 then raise exception 'authenticated can still execute fn_price_confidence'; end if;

  -- POSITIVE CONTROL: the seat must NOT have lost it. A revoke that closes the routine to the
  -- people who need it is not a fix, it is an outage with a security story attached.
  -- BOTH overloads must be closed and BOTH must still work for the seat.
  if v_svc < 2 then
    raise exception 'service_role can execute only % of the 2 overloads — the sales engineer lost one', v_svc;
  end if;
  v_works := public.fn_price_confidence('flooring', 12000, 200, 'sqm');
  -- The verdict key is 'band' ('fair' / 'suspiciously_high' / ...), not 'verdict'. My first
  -- assertion asked for the wrong key and failed a routine that was answering correctly — worth
  -- leaving recorded, because an assertion that is wrong about the shape of a healthy answer is
  -- indistinguishable from a broken routine until someone reads the payload.
  if (v_works->>'band') is null then
    raise exception 'the routine no longer answers for the seat: %', v_works::text;
  end if;

  raise notice 'CLOSED. fn_price_confidence: anon %, authenticated %, service_role % (still answering — flooring 12,000 over 200 sqm reads "%").',
    v_anon, v_auth, v_svc, v_works->>'band';
end
$do$;
