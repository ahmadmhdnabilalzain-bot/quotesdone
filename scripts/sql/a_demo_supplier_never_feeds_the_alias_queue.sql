-- A DEMO SUPPLIER NEVER FEEDS THE ALIAS QUEUE (12 Nov 2026, sales_engineer; built by it_engineer).
-- Seat: sales_engineer. Founder rulings 1647 / 1628 (a supplier's own words become names only through review) and the
-- estate's rule that demo and real never meet.
--
-- MEASURED (production htdblwldjkcgjvmqkbeh, read-only, 12 Nov 2026): public.service_alias_proposal held 28 rows with
-- status 'proposed'. 26 of them were filed by the registration certification's ZZ DEMO fixtures of 11 Nov 2026, among them
-- "equipment" for musical_pro_audio.studio_equipment, "800 m2 office floor" for real_estate_services.office_warehouse_leasing
-- and "frames" for optical_eyewear.spectacle_frames. How each is known to be demo: each phrase is in the
-- service_alias_review agent_action of the supplier who filed it (detail.pairs), that supplier's lead no longer exists
-- (leads 157151, 157176, 157177, 157178, 157180, 157181, 157296, 157297, 157454, 157456: torn down, their actions
-- dismissed), and the line each phrase was read from (licence_scope_check detail.line, e.g. "Bus and coach rental with
-- driver, 14 to 65 seats") is a line of scripts/e2e/registration_fixtures.mjs, whose every company is "ZZ DEMO ...".
-- The other 2 (ids 475 "Machinery servicing", 476 "PIPE extension") belong to lead 19398, a REAL supplier: they are NOT
-- touched here (the analysis counted all 28 as demo; they are the sales engineer's to decide on the real supplier's words).
--
-- WHAT THIS CHANGES:
--   1. fn_service_alias_propose refuses a demo supplier (public.fn_supplier_is_demo: leads.is_demo, the generated marker:
--      'ZZ DEMO' / 'QD Demo' names, demo e-mail and phone, the demo sources). It files nothing and answers
--      {ok: true, proposed: 0, refused: 'demo_supplier'}, so the caller's confirm never fails (supplier_services.ts
--      recordOwnPhrases logs an error and carries on; ok true means no error is logged). CREATE OR REPLACE keeps the ACL
--      (service_role only, revoked again below); it has ONE overload, fn_service_alias_propose(bigint,jsonb,text), read from
--      pg_proc on 12 Nov 2026. The body is otherwise the one of
--      a_suppliers_own_words_reach_every_customer_who_asks_for_the_same_work.sql, byte for byte (compared with the
--      production definition in supabase/schema/full_schema/09_functions_fn_s.sql).
--   2. The 26 demo rows are REJECTED through fn_service_alias_decide (kept, so the same phrase is not asked again; never
--      approved). A row is rejected only while it is still 'proposed' and no supplier it names is a real lead.
--
-- prevented by: scripts/sql/a_demo_supplier_never_feeds_the_alias_queue_probe.sql (a ZZ DEMO supplier files nothing; a
--               supplier with no lead still files; the 26 are rejected and lead 19398's 2 are untouched) and
--               scripts/checks/a_demo_supplier_never_feeds_the_alias_queue.test.mjs.

create or replace function public.fn_service_alias_propose(p_supplier_id bigint, p_pairs jsonb, p_source text default 'supplier_confirmed')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r record; v_norm text; v_trade text; v_code text; v_new int := 0; v_seen int := 0; v_skip int := 0; v_id bigint;
begin
  if p_source not in ('supplier_confirmed', 'profile') then raise exception 'fn_service_alias_propose: source % is not a supplier source', p_source; end if;
  -- 12 Nov 2026: a demo supplier's words never become a real name (26 of 28 open proposals were ZZ DEMO fixtures').
  if p_supplier_id is not null and public.fn_supplier_is_demo(p_supplier_id) then
    return jsonb_build_object('ok', true, 'proposed', 0, 'seen_again', 0,
      'skipped', jsonb_array_length(case when jsonb_typeof(p_pairs) = 'array' then p_pairs else '[]'::jsonb end), 'refused', 'demo_supplier');
  end if;
  for r in select btrim(coalesce(x->>'phrase', '')) as phrase, btrim(coalesce(x->>'key', '')) as key
             from jsonb_array_elements(case when jsonb_typeof(p_pairs) = 'array' then p_pairs else '[]'::jsonb end) x
            limit 40
  loop
    v_trade := split_part(r.key, '.', 1); v_code := split_part(r.key, '.', 2);
    v_norm := public.fn_service_alias_norm(r.phrase);
    if char_length(r.phrase) not between 3 and 120 or v_code = ''
       or not exists (select 1 from public.taxonomy_trade_service s where s.active and s.trade_code = v_trade and s.code = v_code)
       or (v_trade || '.' || v_code) = any(public.fn_service_alias_owners(v_norm)) then
      v_skip := v_skip + 1; continue;
    end if;
    insert into public.service_alias_proposal (phrase, phrase_norm, trade_code, code, source, supplier_ids)
    values (r.phrase, v_norm, v_trade, v_code, p_source, case when p_supplier_id is null then '{}'::bigint[] else array[p_supplier_id] end)
    on conflict (phrase_norm, trade_code, code) do nothing
    returning id into v_id;
    if v_id is not null then v_new := v_new + 1;
    else
      update public.service_alias_proposal
         set seen = seen + 1,
             supplier_ids = case when p_supplier_id is null or p_supplier_id = any(supplier_ids) then supplier_ids else supplier_ids || p_supplier_id end
       where phrase_norm = v_norm and trade_code = v_trade and code = v_code;
      v_seen := v_seen + 1;
    end if;
    v_id := null;
  end loop;
  return jsonb_build_object('ok', true, 'proposed', v_new, 'seen_again', v_seen, 'skipped', v_skip);
end
$fn$;
revoke execute on function public.fn_service_alias_propose(bigint, jsonb, text) from public, anon, authenticated;
grant execute on function public.fn_service_alias_propose(bigint, jsonb, text) to service_role;

-- The 26 demo proposals, rejected by the sales engineer's own decision routine.
do $reject$
declare v_id bigint; v jsonb;
begin
  for v_id in
    select p.id from public.service_alias_proposal p
     where p.id = any(array[431,432,433,434,435,436,437,438,440,441,442,443,444,445,447,448,449,450,452,453,481,483,486,487,511,512]::bigint[])
       and p.status = 'proposed'
       and not exists (select 1 from public.leads l where l.id = any(p.supplier_ids) and not l.is_demo)
     order by p.id
  loop
    v := public.fn_service_alias_decide(v_id, 'rejected', 'sales_engineer',
           'filed by a ZZ DEMO registration fixture (11 Nov 2026), not a real supplier''s words');
    if not coalesce((v->>'ok')::boolean, false) then raise exception 'rejecting demo alias % failed: %', v_id, v; end if;
  end loop;
end
$reject$;

-- Verdict row (a routine is defined here, so no raise).
select case
  when position('fn_supplier_is_demo' in pg_get_functiondef('public.fn_service_alias_propose(bigint,jsonb,text)'::regprocedure)) > 0
   and not exists (select 1 from public.service_alias_proposal where status = 'proposed'
                     and id = any(array[431,432,433,434,435,436,437,438,440,441,442,443,444,445,447,448,449,450,452,453,481,483,486,487,511,512]::bigint[]))
   and (select count(*) from public.service_alias_proposal where id in (475, 476) and status = 'proposed') = 2
   and not has_function_privilege('anon', 'public.fn_service_alias_propose(bigint,jsonb,text)', 'execute')
   and not has_function_privilege('authenticated', 'public.fn_service_alias_propose(bigint,jsonb,text)', 'execute')
  then 'PROBE OK the alias queue refuses demo suppliers; the 26 demo proposals are rejected; the real supplier''s 2 are untouched'
  else 'PROBE FAILED: the demo refusal, a rejection or a grant is wrong' end as verdict;
