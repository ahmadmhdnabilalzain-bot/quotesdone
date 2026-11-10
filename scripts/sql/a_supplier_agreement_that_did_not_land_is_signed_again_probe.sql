-- PROBE (pure, no DDL, aborted transaction) for a_supplier_agreement_that_did_not_land_is_signed_again.sql. Seat: sales_engineer.
-- Run AFTER the definition, in the same transaction (scripts/ci/rehearse_sql.mjs <file> <this probe>). It always ends in
-- raise exception 'CHK<<...>>', so every row it writes - the leads, the audit rows and the pg_net request rows - rolls back.
-- Every subject is a ZZ DEMO lead at @example.invalid created here, and the sweep is called with that one lead's id, so it
-- cannot see, post for or audit anyone else.
--   u  accepted 6 minutes ago, no certificate     -> posted once (attempt 1, one pg_net request), then not again within 5 minutes
--   s  accepted 6 minutes ago, certificate after  -> untouched
--   y  accepted 1 minute ago, no certificate      -> untouched (the first post still has its 5 minutes)
--   x  as u, with 3 earlier re-signs on file      -> no post; ONE needs_review row, and still one after a second run
do $p$
declare
  r jsonb := '{}'::jsonb; k text; ids jsonb := '{}'::jsonb; lid bigint; g jsonb; z text := 'zz-demo-resign';
  real_before int; real_after int; q0 bigint; q1 bigint;
begin
  select count(*) into real_before from public.leads where not coalesce(is_demo, false) and company_name !~* '^\s*zz\s*demo';
  foreach k in array array['u', 's', 'y', 'x'] loop
    insert into public.leads (approval_status, verified, claimed, claimed_by, company_name, email, owner_email_verified,
                              accepted_terms_at, signed_terms_path, signed_terms_at, emirate, city, source, tags)
    values (null, false, true, z || '-' || k || '@example.invalid', 'ZZ DEMO RESIGN ' || upper(k) || ' LLC', z || '-' || k || '@example.invalid', true,
            now() - case when k = 'y' then interval '1 minute' else interval '6 minutes' end,
            case when k = 's' then 'terms/' || z || '/s.pdf' end, case when k = 's' then now() - interval '1 minute' end,
            'Dubai', 'Dubai', 'probe', array['qd_demo'])
    returning id into lid;
    ids := ids || jsonb_build_object(k, lid);
  end loop;
  lid := (ids ->> 'x')::bigint;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  select 'sales_engineer', 'supplier_agreement_resign', 'auto_done', 'low', 'ZZ DEMO probe: an earlier re-sign',
         jsonb_build_object('supplier_id', lid, 'accepted_terms_at', l.accepted_terms_at, 'attempt', n), 'leads', lid::text
    from public.leads l, generate_series(1, 3) n where l.id = lid;

  select count(*) into q0 from net.http_request_queue;
  foreach k in array array['u', 's', 'y', 'x'] loop
    g := public.fn_sales_engineer_resigns_unsigned_agreements((ids ->> k)::bigint);
    r := r || jsonb_build_object(k || '1', g);
  end loop;
  select count(*) into q1 from net.http_request_queue;
  -- second pass: u must wait its 5 minutes, x must not file a second review
  r := r || jsonb_build_object('u2', public.fn_sales_engineer_resigns_unsigned_agreements((ids ->> 'u')::bigint),
                               'x2', public.fn_sales_engineer_resigns_unsigned_agreements((ids ->> 'x')::bigint),
                               'posts_queued', q1 - q0);
  -- counted in a statement of their own: the one above cannot see the rows its own calls wrote
  r := r || jsonb_build_object('u_audit', (select count(*) from public.agent_actions where kind = 'supplier_agreement_resign' and target_id = ids ->> 'u' and status = 'auto_done'),
                               'x_reviews', (select count(*) from public.agent_actions where kind = 'supplier_agreement_resign' and target_id = ids ->> 'x' and status = 'needs_review'));
  select count(*) into real_after from public.leads where not coalesce(is_demo, false) and company_name !~* '^\s*zz\s*demo';
  r := r || jsonb_build_object('real_leads_before', real_before, 'real_leads_after', real_after);
  if (r #>> '{u1,posted}')::int = 1 and (r #>> '{s1,posted}')::int = 0 and (r #>> '{y1,posted}')::int = 0
     and (r #>> '{x1,posted}')::int = 0 and (r #>> '{x1,escalated}')::int = 1
     and (r #>> '{u2,posted}')::int = 0 and (r #>> '{u2,waiting}')::int = 1 and (r #>> '{x2,escalated}')::int = 0
     and (r ->> 'posts_queued')::int = 1 and (r ->> 'u_audit')::int = 1 and (r ->> 'x_reviews')::int = 1
     and real_before = real_after then
    raise exception 'CHK<<PROBE OK %>>', r::text;
  end if;
  raise exception 'CHK<<PROBE FAILED %>>', r::text;
end $p$;
