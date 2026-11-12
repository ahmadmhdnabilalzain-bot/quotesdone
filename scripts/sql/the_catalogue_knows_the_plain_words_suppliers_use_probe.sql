-- PROBE (pure, no DDL, aborted transaction) for the_catalogue_knows_the_plain_words_suppliers_use.sql.
-- Seat: sales_engineer. 12 Nov 2026, founder ruling 1647.
-- Run AFTER the file, or with it, rolled back:
--   node scripts/ci/rehearse_sql.mjs scripts/sql/the_catalogue_knows_the_plain_words_suppliers_use.sql scripts/sql/the_catalogue_knows_the_plain_words_suppliers_use_probe.sql
-- It always ends in raise exception 'CHK<<json>>', so every row it writes rolls back; session_replication_role = replica
-- stops every trigger for this transaction only, so nothing it writes queues a message.
--
-- ITS SUBJECT CANNOT REACH A PERSON: the words it reads are a ZZ DEMO manpower and fit-out profile's own (below); the one
-- supplier it matches is a matchable ZZ DEMO lead at @example.invalid built by scripts/lib/demo_factory.mjs, whose
-- capability row is rewritten here and rolls back; no inquiry is created, nothing is matched into inquiry_matches. The one
-- queue row it files names that ZZ DEMO lead and rolls back.
--
-- WHAT IT ASKS:
--   1. the words of the ZZ DEMO profile name exactly the service expected through fn_service_alias_owners, the queue's own
--      name comparison over the column the reading's code mapping reads (taxonomy_trade_service.aliases; the reading's
--      nameIndex is proved on the same names by the check's offline test), and the bare words name nothing;
--   2. a collision is refused: "office staff" (now labour_supply.office_admin_staff's) filed for its twin
--      hr_outsourcing.office_staff_outsourcing cannot be approved (fn_service_alias_decide: alias_names_another_service);
--   3. a roof-insulation specialist is reached for a request keyed waterproofing.thermal, and not for waterproofing.roof;
--   4. the two moved Arabic names are rejected under deep_cleaning and name cleaning.residential only;
--   5. nothing a real supplier holds changed: no supplier_capabilities, leads or real queue row was written in this
--      transaction before the probe's own ZZ DEMO writes (rehearsed with the file, this covers the file).
do $probe$
declare
  f text := ''; o jsonb; r record; v_owners text[]; v_a bigint; v_id bigint; v jsonb;
  v_real_caps int; v_real_leads int; v_real_queue int;
  -- "ZZ DEMO Gulf Manpower & Interiors: we supply office staff, site supervisors, truck drivers, chefs, nurses and static
  --  guards; we build mall kiosks and fit gypsum cornices; we clean villas weekly (تنظيف فلل)." Each phrase -> its key; a
  --  phrase mapped to null must name NO service (a bare profession or trade word the review and the guard keep out; bare
  --  "supervisors" is not asked: it is the code of labour_supply.supervisors itself, which this file does not change).
  words jsonb := $w${
    "office staff": "labour_supply.office_admin_staff", "site supervisors": "labour_supply.supervisors",
    "truck drivers": "labour_supply.drivers_operators", "chefs": "labour_supply.hospitality_staff",
    "professional staff": "labour_supply.professional_staff", "nurses": "occupational_health.onsite_clinic_nurse",
    "static guards": "security_guarding.manned_guarding", "mall kiosks": "exhibition_stands.kiosks_pop_ups",
    "cornices": "gypsum.decorative", "smdb panels": "electrical.db_panels", "steel fixers": "labour_supply.skilled",
    "outsourced bookkeeping": "accounting_bookkeeping.monthly_bookkeeping",
    "تنظيف فلل": "cleaning.residential", "تنظيف شقق": "cleaning.residential", "عبايات": "apparel_fashion_wholesale.abayas_kanduras",
    "security guard": "security_systems.guarding", "office staff supply": "hr_outsourcing.office_staff_outsourcing",
    "professionals": null, "drivers": null, "kiosks": null, "vending machines": null}$w$::jsonb;
begin
  set local session_replication_role = replica;
  -- 5 first: rows this transaction wrote before the probe (the file's, when rehearsed with it)
  select count(*) into v_real_caps from public.supplier_capabilities c
   where c.xmin = (txid_current() % 4294967296)::text::xid;
  select count(*) into v_real_leads from public.leads l where l.xmin = (txid_current() % 4294967296)::text::xid;
  select count(*) into v_real_queue from public.service_alias_proposal q
   where q.xmin = (txid_current() % 4294967296)::text::xid and cardinality(coalesce(q.supplier_ids, '{}'::bigint[])) > 0;
  if v_real_caps + v_real_leads + v_real_queue > 0 then
    f := f || format('the file wrote real rows (capabilities %s, leads %s, supplier queue rows %s); ', v_real_caps, v_real_leads, v_real_queue);
  end if;

  -- 1. the words name exactly the service expected
  for r in select key as w, value as want from jsonb_each_text(words) loop
    v_owners := public.fn_service_alias_owners(public.fn_service_alias_norm(r.w));
    if r.want is null then
      if cardinality(v_owners) > 0 then f := f || '"' || r.w || '" names ' || array_to_string(v_owners, '+') || ', and must name nothing; '; end if;
    elsif v_owners is distinct from array[r.want] then
      f := f || '"' || r.w || '" names ' || coalesce(nullif(array_to_string(v_owners, '+'), ''), 'nothing') || ', not ' || r.want || '; ';
    end if;
  end loop;

  -- the ZZ DEMO supplier (matchable, @example.invalid)
  select l.id into v_a from public.leads l
   where l.is_demo and l.company_name ~* '^\s*(zz|qd)\s*demo' and l.email like '%@example.invalid'
     and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
   order by l.id limit 1;
  if v_a is null then raise exception 'CHK<<{"verdict":"PROBE FAILED: no matchable ZZ DEMO supplier at @example.invalid"}>>'; end if;

  -- 2. a collision is refused through the queue's own decision routine
  insert into public.service_alias_proposal (phrase, phrase_norm, trade_code, code, source, supplier_ids)
  values ('office staff', public.fn_service_alias_norm('office staff'), 'hr_outsourcing', 'office_staff_outsourcing', 'supplier_confirmed', array[v_a])
  returning id into v_id;
  v := public.fn_service_alias_decide(v_id, 'approved', 'sales_engineer', 'ZZ probe: a name owned by another key');
  if coalesce((v->>'ok')::boolean, true) or v->>'code' is distinct from 'alias_names_another_service'
     or not (v->'other') ? 'labour_supply.office_admin_staff' then
    f := f || 'a name another key owns was approved: ' || v::text || '; ';
  end if;
  if exists (select 1 from public.taxonomy_trade_service where trade_code = 'hr_outsourcing' and code = 'office_staff_outsourcing'
               and 'office staff' = any(aliases)) then
    f := f || '"office staff" reached the twin key; ';
  end if;

  -- 3. the reverse implications: a roof-insulation specialist is reached for waterproofing.thermal, not for waterproofing.roof
  delete from public.supplier_availability where supplier_id = v_a;
  insert into public.supplier_capabilities (supplier_id, trades, roles, services, confirmed_at, confirmed_version)
  values (v_a, array['thermal_insulation'], array['contractor'], array['thermal_insulation.roof_insulation'], now(), 1)
  on conflict (supplier_id) do update set trades = array['thermal_insulation'], roles = array['contractor'],
    services = array['thermal_insulation.roof_insulation'], services_removed = '{}', excluded_trades = '{}', coverage_emirates = '{}',
    authority_approvals = '{}'::jsonb, min_project_value = null, max_project_value = null, confirmed_at = now();
  if not exists (select 1 from public.fn_match_capability(array['waterproofing'], 'executes', p_limit := 100000,
                   p_services := array['waterproofing.thermal']) m where m.supplier_id = v_a) then
    f := f || 'a roof-insulation specialist was not reached for waterproofing.thermal; ';
  end if;
  if exists (select 1 from public.fn_match_capability(array['waterproofing'], 'executes', p_limit := 100000,
               p_services := array['waterproofing.roof']) m where m.supplier_id = v_a) then
    f := f || 'a roof-insulation specialist was reached for roof waterproofing (control); ';
  end if;
  update public.supplier_capabilities set services = array['thermal_insulation.wall_insulation'] where supplier_id = v_a;
  if not exists (select 1 from public.fn_match_capability(array['waterproofing'], 'executes', p_limit := 100000,
                   p_services := array['waterproofing.thermal']) m where m.supplier_id = v_a) then
    f := f || 'a wall-insulation specialist was not reached for waterproofing.thermal; ';
  end if;

  -- 4. the two moved names
  if exists (select 1 from public.service_alias_proposal where id in (205, 206) and status <> 'rejected') then
    f := f || 'a moved name is still approved under deep_cleaning; ';
  end if;

  -- the file's own verdict, re-read
  if (select count(*) from public.service_alias_proposal q
       where q.source = 'curated' and q.status = 'approved'
         and q.reason = 'curated 12 Nov 2026 (founder ruling 1647): the catalogue knows the plain words suppliers use'
         and cardinality(coalesce(q.supplier_ids, '{}'::bigint[])) = 0
         and exists (select 1 from public.taxonomy_trade_service s where s.active and s.trade_code = q.trade_code and s.code = q.code
                       and lower(btrim(q.phrase)) = any(s.aliases))) <> 3501 then
    f := f || 'not every curated name of the file is on its service; ';
  end if;

  o := jsonb_build_object('words', (select count(*) from jsonb_object_keys(words)),
    'services_without_a_name', (select count(*) from public.taxonomy_trade_service where active and coalesce(cardinality(aliases), 0) = 0),
    'real_suppliers_reached_by_the_reverse_rows', (select count(*) from public.supplier_capabilities c join public.leads l on l.id = c.supplier_id
       where not l.is_demo and c.services && array['thermal_insulation.roof_insulation', 'thermal_insulation.wall_insulation']));
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when f = '' then 'PROBE OK' else 'PROBE FAILED: ' || f end) || o;
end $probe$;
