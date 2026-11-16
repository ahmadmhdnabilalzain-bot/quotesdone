-- PROBE: THE WEEKLY SANCTIONS SCREEN CHECKS EVERY MEMBER OF A COMPANY. Seats: customer_support + sales_engineer.
-- Agent: customer_support builder (supplier wave-2 review fixes), 16 Nov 2026. Pure probe: no DDL, never applied; run after
-- the_weekly_sanctions_screen_checks_every_member_of_a_company.sql on a LOCAL Postgres 16 (never on production). It always raises,
-- so every row is rolled back. Every party is a ZZ DEMO fixture on @example.invalid; the screen runs in its rehearsal mode, which
-- reads only 'ZZ DEMO — ' companies.
-- PROBE OK only if
--   1. two colleagues added while the list was clean, whose names both match ONE entry listed later, are two hits, each naming
--      its member (on the old key the second was dropped), and both stop acting for the company;
--   2. a second run of the screen records nothing new (a non-member hit keeps its old key: member_id null, nulls not distinct);
--   3. a person deciding ONE member's hit is not him restores only that member;
--   4. a beneficial-owner hit written on the widened key, twice, is one row (fn_accountant_ubo_rescreen's conflict target).
do $probe$
declare
  fails text := ''; s bigint; r bigint; m1 bigint; m2 bigint; j jsonb; n int; v_owner text := 'zz-demo-wsm-o@example.invalid';
begin
  insert into public.leads (company_name, email, claimed_by, emirate, lifecycle_stage, signatory_name)
  values ('ZZ DEMO — Weekly Screen Co', v_owner, v_owner, 'Dubai', 'registered', 'ZZ DEMO Clean Owner') returning id into s;
  insert into public.supplier_member (lead_id, email, name, role, status, invited_by, accepted_at)
  values (s, 'zz-demo-wsm-1@example.invalid', 'Ivan Petrovich Sidorov', 'estimator', 'active', v_owner, now()) returning id into m1;
  insert into public.supplier_member (lead_id, email, name, role, status, invited_by, accepted_at)
  values (s, 'zz-demo-wsm-2@example.invalid', 'Ivan Sergeyevich Sidorov', 'viewer', 'active', v_owner, now()) returning id into m2;
  if not (public.fn_supplier_member_counts(m1) and public.fn_supplier_member_counts(m2)) then fails := fails || ' 0:setup'; end if;

  -- the listing arrives after they joined; one entry matches both names (every word of the listing is in each name)
  insert into public.screening_run (source, fetched_at, entries, status) values ('zz_wsm', now(), 2, 'ok') returning id into r;
  insert into public.screening_entry (run_id, source, entry_type, reference, name, name_norm, tokens)
  values (r, 'zz_wsm', 'individual', 'WSM-1', 'SIDOROV Ivan', public.fn_screening_normalise('SIDOROV Ivan'), public.fn_screening_tokens('SIDOROV Ivan')),
         (r, 'zz_wsm', 'entity', 'WSM-2', 'Weekly Screen Co', public.fn_screening_normalise('Weekly Screen Co'), public.fn_screening_tokens('Weekly Screen Co'));

  -- 1. both colleagues are recorded and held
  j := public.fn_supplier_sanctions_screen(array[r], 'wsm');
  select count(*) into n from public.supplier_screening_hit where lead_id = s and field = 'member' and entry_reference = 'WSM-1';
  if n <> 2 then fails := fails || ' 1:member_hits(' || n || ')'; end if;
  if (select count(distinct member_id) from public.supplier_screening_hit where lead_id = s and field = 'member') <> 2 then fails := fails || ' 1:hit_names_member'; end if;
  if public.fn_supplier_member_counts(m1) or public.fn_supplier_member_counts(m2) then fails := fails || ' 1:still_counts'; end if;
  if (select count(*) from public.supplier_member where id in (m1, m2) and status = 'screening') <> 2 then fails := fails || ' 1:not_screening'; end if;
  if not exists (select 1 from public.supplier_screening_hit where lead_id = s and field = 'legal_name' and member_id is null) then fails := fails || ' 1:company_hit_missing(' || j::text || ')'; end if;

  -- 2. a second run records nothing new (each real run is its own transaction; its scratch table drops at commit, so here it is
  -- dropped by hand between the two runs of this one transaction)
  drop table if exists pg_temp.tmp_screen_sup;
  j := public.fn_supplier_sanctions_screen(array[r], 'wsm');
  if coalesce((j->>'hits_new')::int, -1) <> 0 then fails := fails || ' 2:rerun_new(' || coalesce(j->>'hits_new', 'null') || ')'; end if;

  -- 3. one decision restores one member
  update public.supplier_screening_hit set status = 'false_positive', decided_by = 'ceo', decided_at = now() where member_id = m1;
  if not public.fn_supplier_member_counts(m1) then fails := fails || ' 3:cleared_not_restored'; end if;
  if public.fn_supplier_member_counts(m2) then fails := fails || ' 3:other_restored'; end if;

  -- 4. the accountant's conflict target is a real key: twice is one row
  insert into public.supplier_screening_hit (run_id, lead_id, field, supplier_value, entry_id, entry_name, entry_source, entry_reference, entry_type, match_kind, score)
  select r, s, 'beneficial_owner', 'Ivan Sidorov', e.id, e.name, e.source, e.reference, e.entry_type, 'token_overlap', 1.0 from public.screening_entry e where e.run_id = r and e.reference = 'WSM-1'
  on conflict (lead_id, entry_source, entry_reference, field, member_id) do nothing;
  insert into public.supplier_screening_hit (run_id, lead_id, field, supplier_value, entry_id, entry_name, entry_source, entry_reference, entry_type, match_kind, score)
  select r, s, 'beneficial_owner', 'Ivan Sidorov', e.id, e.name, e.source, e.reference, e.entry_type, 'token_overlap', 1.0 from public.screening_entry e where e.run_id = r and e.reference = 'WSM-1'
  on conflict (lead_id, entry_source, entry_reference, field, member_id) do nothing;
  select count(*) into n from public.supplier_screening_hit where lead_id = s and field = 'beneficial_owner';
  if n <> 1 then fails := fails || ' 4:owner_rows(' || n || ')'; end if;

  if fails <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK: two colleagues on one listing entry are two hits, each naming him, both held; a rerun records nothing new; one decision restores one member; the beneficial-owner key holds>>';
end $probe$;
