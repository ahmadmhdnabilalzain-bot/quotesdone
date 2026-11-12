-- PROBE for a_quote_that_went_to_the_customer_is_never_coached.sql (sales_engineer, 12 Nov 2026; final audit
-- customer_journey B3). A pure probe: it always ends by raising 'PROBE OK ...' or 'PROBE FAILED: ...', so every row it
-- writes rolls back. Before the apply, run it after the file it proves (node scripts/ci/rehearse_sql.mjs <file> <probe>);
-- after, alone. Run alone against the routine of 12 Nov 2026 it answers PROBE FAILED (the live quote is coached).
--
-- Its customer and supplier are ZZ DEMO fixtures at .invalid addresses, which fn_email_sendable refuses. Two quotes with
-- no line items (so fn_quote_structured_score says "not submittable" on both):
--   1. a quote the customer has (status submitted): fn_quote_coach writes no quote_coaching row;
--   2. a draft the accept rule refused: coached, ONE row, naming what the score finds missing;
--   3. the same draft coached again: still one row.
do $probe$
declare
  v_tag text := substr(md5(clock_timestamp()::text), 1, 8);
  c1 uuid; i1 uuid; s1 bigint; q_live uuid := gen_random_uuid(); q_draft uuid := gen_random_uuid(); v jsonb; n int; v_bad text := '';
  v_sup text;
begin
  v_sup := 'zz-coach-' || v_tag || '@example.invalid';
  insert into public.customers (email, full_name, locale) values ('zz-coach-c-' || v_tag || '@example.invalid', 'ZZ DEMO Coach customer', 'en') returning id into c1;
  insert into public.leads (company_name, email, claimed, claimed_by) values ('ZZ DEMO Coach supplier ' || v_tag, v_sup, true, v_sup) returning id into s1;
  insert into public.inquiries (customer_id, category, emirate, summary, status, lang, scope_type)
    values (c1, 'joinery', 'Dubai', 'ZZ DEMO coach probe', 'quoted', 'en', 'single') returning id into i1;
  insert into public.quotes (id, inquiry_id, supplier_id, option_no, quote_amount, status, warranty, lead_time, validity)
    values (q_live, i1, s1, 1, 4500, 'draft', '1 year', '2 weeks', '30 days'),
           (q_draft, i1, s1, 2, 3900, 'draft', '1 year', '2 weeks', '30 days');
  -- the live one went to the customer: the gate holds it (no lines), the hold desk releases it, and it goes out
  -- (z40_quote_quality_gate never pulls back a quote whose hold was released), as all 8 of the audit's quotes did
  update public.quotes set status = 'submitted' where id = q_live;
  update public.quote_quality_hold set released_at = now(), release_reason = 'corrected' where quote_id = q_live;
  update public.quotes set status = 'submitted' where id = q_live and status <> 'submitted';
  if (select status from public.quotes where id = q_live) is distinct from 'submitted' then
    v_bad := v_bad || 'set-up: the live quote could not be made submitted (' || coalesce((select status from public.quotes where id = q_live), 'null') || '); ';
  end if;

  v := public.fn_quote_coach(q_live);
  select count(*) into n from public.notifications where type = 'quote_coaching' and to_email = v_sup and body like '%' || q_live::text || '%';
  if n <> 0 then v_bad := v_bad || n || ' coaching notice(s) for a quote the customer already has (' || v::text || '); '; end if;

  v := public.fn_quote_coach(q_draft);
  v := public.fn_quote_coach(q_draft);
  select count(*) into n from public.notifications where type = 'quote_coaching' and to_email = v_sup and body like '%' || q_draft::text || '%';
  if n <> 1 then v_bad := v_bad || n || ' coaching notice(s) for the refused draft, want exactly 1 (' || v::text || '); '; end if;
  if not exists (select 1 from public.notifications where type = 'quote_coaching' and to_email = v_sup and body like '%' || q_draft::text || '%'
                    and body like '%an itemised breakdown%') then
    v_bad := v_bad || 'the draft''s notice does not name what is missing; ';
  end if;

  if v_bad <> '' then raise exception 'PROBE FAILED: %', v_bad; end if;
  raise exception 'PROBE OK: a quote with the customer is never coached; a refused draft is coached once with what is missing';
end $probe$;
