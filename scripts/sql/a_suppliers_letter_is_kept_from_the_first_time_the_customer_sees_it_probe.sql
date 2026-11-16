-- PROBE for a_suppliers_letter_is_kept_from_the_first_time_the_customer_sees_it.sql (15 Nov 2026, sales_engineer).
-- A pure probe: it always raises CHK<<...>>, so everything it writes is rolled back. ZZ DEMO rows only: a demo customer at
-- @example.invalid, five demo suppliers at @example.invalid, and a request it creates itself. It counts every other request's
-- letter rows before and after and fails if one moved. Run on a LOCAL database (never a rehearsal on production, 13 Nov 2026):
--   psql <local> -f scripts/sql/a_suppliers_letter_is_kept_from_the_first_time_the_customer_sees_it.sql
--   psql <local> -f scripts/sql/a_suppliers_letter_is_kept_from_the_first_time_the_customer_sees_it_probe.sql
-- What it proves, each step calling fn_customer_supplier_letters as the portal card or the thread does:
--   1. a draft (held) quote is refused a letter; the live one is A
--   2. review case (a): X's revised upload supersedes its hold and X goes live with an EARLIER created_at: Y stays A, X is B
--   3. review case (b): X is withdrawn: Y stays A, X keeps B (its row is not touched)
--   4. review case (c): Y is re-held (back to draft), Z goes live as C, Y is released: A, B, C unchanged
--   5. the gap: a sanctioned supplier's live quote is refused a letter even when passed, so the letters stay A, B, C
--   6. a supplier met first through its question is lettered D; a supplier with neither a quote nor a question is refused
--   7. letters are unique and contiguous on the request; service_role cannot update or delete a letter
--   8. every other request's letters are unchanged
do $probe$
declare
  f text := ''; v_cust uuid; v_sup bigint[]; v_x bigint; v_y bigint; v_z bigint; v_s bigint; v_q bigint; v_inq uuid;
  v_qx uuid; v_qy uuid; v_qz uuid; v_qs uuid; v_others_before int; v_others_after int; v_got text;
  shown_by_card constant text := 'quote_card';
begin
  select c.id into v_cust from public.customers c where c.is_demo and c.email like '%@example.invalid' order by c.created_at nulls last limit 1;
  if v_cust is null then raise exception 'CHK<<{"verdict":"PROBE FAILED: no demo customer at @example.invalid"}>>'; end if;
  select array_agg(l.id order by l.id) into v_sup from (
    select l.id from public.leads l where l.is_demo and l.email like '%@example.invalid'
       and not exists (select 1 from public.sanctions_ban b where b.lead_id = l.id) order by l.id limit 5) l;
  if coalesce(cardinality(v_sup), 0) < 5 then raise exception 'CHK<<{"verdict":"PROBE FAILED: fewer than five demo suppliers at @example.invalid"}>>'; end if;
  v_x := v_sup[1]; v_y := v_sup[2]; v_z := v_sup[3]; v_s := v_sup[4]; v_q := v_sup[5];
  select count(*) into v_others_before from public.customer_supplier_letter;

  insert into public.inquiries (customer_id, category, summary, status, brief_source)
  values (v_cust, 'hvac', 'ZZ DEMO letter probe', 'sent', 'qd_demo_fixture') returning id into v_inq;
  -- the quotes go in as drafts (the quality gate leaves a draft alone), each with a released hold, so the gate never pulls one
  -- back to draft when the probe moves it live: what the probe tests is the letter, not the gate
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, created_at) values (v_inq, v_x, 41000, 'draft', now() - interval '3 hours') returning id into v_qx;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, created_at) values (v_inq, v_y, 38000, 'draft', now() - interval '2 hours') returning id into v_qy;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, created_at) values (v_inq, v_z, 29500, 'draft', now() - interval '1 hour') returning id into v_qz;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, created_at) values (v_inq, v_s, 20000, 'draft', now() - interval '4 hours') returning id into v_qs;
  insert into public.quote_quality_hold (quote_id, inquiry_id, supplier_id, fixture, flags, release_due, released_at, release_reason, accepted_md5)
  select q, v_inq, s, true, '[]'::jsonb, now(), now(), 'corrected', 'probe' from unnest(array[v_qx, v_qy, v_qz, v_qs], array[v_x, v_y, v_z, v_s]) u(q, s);
  update public.quotes set status = 'submitted' where id = v_qy;
  if (select status from public.quotes where id = v_qy) <> 'submitted' then raise exception 'CHK<<{"verdict":"PROBE FAILED: the probe could not put a demo quote live"}>>'; end if;

  -- 1. X held (draft), Y live: passing both letters Y only
  perform public.fn_customer_supplier_letters(array[v_inq], jsonb_build_array(jsonb_build_object('inquiry_id', v_inq, 'supplier_id', v_x), jsonb_build_object('inquiry_id', v_inq, 'supplier_id', v_y)), shown_by_card);
  select string_agg(supplier_id::text || '=' || letter, ',' order by seq) into v_got from public.customer_supplier_letter where inquiry_id = v_inq;
  if v_got is distinct from v_y || '=A' then f := f || '1: expected only Y=A, got ' || coalesce(v_got, 'nothing') || '; '; end if;

  -- 2. X's revised upload: live with its old, earlier created_at; the card passes them in arrival order, X first
  update public.quotes set status = 'submitted' where id = v_qx;
  perform public.fn_customer_supplier_letters(array[v_inq], jsonb_build_array(jsonb_build_object('inquiry_id', v_inq, 'supplier_id', v_x), jsonb_build_object('inquiry_id', v_inq, 'supplier_id', v_y)), shown_by_card);
  select string_agg(supplier_id::text || '=' || letter, ',' order by seq) into v_got from public.customer_supplier_letter where inquiry_id = v_inq;
  if v_got is distinct from v_y || '=A,' || v_x || '=B' then f := f || '2: a revised upload moved a letter: ' || coalesce(v_got, 'nothing') || '; '; end if;

  -- 3. X withdrawn: nothing moves
  update public.quotes set status = 'withdrawn' where id = v_qx;
  perform public.fn_customer_supplier_letters(array[v_inq], jsonb_build_array(jsonb_build_object('inquiry_id', v_inq, 'supplier_id', v_y)), shown_by_card);
  select string_agg(supplier_id::text || '=' || letter, ',' order by seq) into v_got from public.customer_supplier_letter where inquiry_id = v_inq;
  if v_got is distinct from v_y || '=A,' || v_x || '=B' then f := f || '3: a withdrawal moved a letter: ' || coalesce(v_got, 'nothing') || '; '; end if;

  -- 4. Y re-held, Z live, Y released
  update public.quotes set status = 'draft' where id = v_qy;
  update public.quotes set status = 'submitted' where id = v_qz;
  perform public.fn_customer_supplier_letters(array[v_inq], jsonb_build_array(jsonb_build_object('inquiry_id', v_inq, 'supplier_id', v_z)), shown_by_card);
  update public.quotes set status = 'submitted' where id = v_qy;
  perform public.fn_customer_supplier_letters(array[v_inq], jsonb_build_array(jsonb_build_object('inquiry_id', v_inq, 'supplier_id', v_y), jsonb_build_object('inquiry_id', v_inq, 'supplier_id', v_z)), shown_by_card);
  select string_agg(supplier_id::text || '=' || letter, ',' order by seq) into v_got from public.customer_supplier_letter where inquiry_id = v_inq;
  if v_got is distinct from v_y || '=A,' || v_x || '=B,' || v_z || '=C' then f := f || '4: a re-hold moved a letter: ' || coalesce(v_got, 'nothing') || '; '; end if;

  -- 5. the gap: S is sanctioned and live, and passed FIRST: refused
  insert into public.sanctions_ban (lead_id, decided_by, entry_name) values (v_s, 'probe', 'ZZ DEMO letter probe');
  update public.quotes set status = 'submitted' where id = v_qs;
  perform public.fn_customer_supplier_letters(array[v_inq], jsonb_build_array(jsonb_build_object('inquiry_id', v_inq, 'supplier_id', v_s)), 'comparison');
  if exists (select 1 from public.customer_supplier_letter where inquiry_id = v_inq and supplier_id = v_s) then f := f || '5: a sanctioned supplier was given a letter; '; end if;

  -- 6. Q met through its question; a supplier with nothing on the request is refused
  insert into public.rfq_clarification (inquiry_id, supplier_id, kind, question) values (v_inq, v_q, 'question', 'ZZ DEMO: is the ceiling void at least 300 mm?');
  perform public.fn_customer_supplier_letters(array[v_inq], jsonb_build_array(jsonb_build_object('inquiry_id', v_inq, 'supplier_id', v_q), jsonb_build_object('inquiry_id', v_inq, 'supplier_id', 1)), 'question');
  if (select letter from public.customer_supplier_letter where inquiry_id = v_inq and supplier_id = v_q) is distinct from 'D' then f := f || '6: the supplier met by its question is not D; '; end if;
  if exists (select 1 from public.customer_supplier_letter where inquiry_id = v_inq and supplier_id = 1) then f := f || '6: a supplier never shown was given a letter; '; end if;
  -- the read alone (no one shown) returns the same four letters
  select string_agg(r.letter, '' order by r.seq) into v_got from public.fn_customer_supplier_letters(array[v_inq], '[]'::jsonb, shown_by_card) r;
  if v_got is distinct from 'ABCD' then f := f || '6: the read gave ' || coalesce(v_got, 'nothing') || ' not ABCD; '; end if;

  -- 7. contiguous and fixed
  if (select count(*) <> max(seq) + 1 or count(distinct letter) <> count(*) from public.customer_supplier_letter where inquiry_id = v_inq) then f := f || '7: letters are not unique and contiguous; '; end if;
  if has_table_privilege('service_role', 'public.customer_supplier_letter', 'update') or has_table_privilege('service_role', 'public.customer_supplier_letter', 'delete') then
    f := f || '7: service_role can change a letter; '; end if;
  if not has_table_privilege('service_role', 'public.customer_supplier_letter', 'insert') or not has_table_privilege('service_role', 'public.customer_supplier_letter', 'select') then
    f := f || '7: service_role cannot read or add letters; '; end if;
  begin
    perform public.fn_customer_supplier_letters(array[v_inq], '[]'::jsonb, 'guess');
    f := f || '7: an unknown surface was accepted; ';
  exception when invalid_parameter_value then null; end;

  -- 8. nobody else's letters moved
  select count(*) into v_others_after from public.customer_supplier_letter where inquiry_id <> v_inq;
  if v_others_after <> v_others_before then f := f || '8: other requests'' letters changed: ' || v_others_before || ' -> ' || v_others_after || '; '; end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when f = '' then 'PROBE OK' else 'PROBE FAILED: ' || f end);
end
$probe$;
