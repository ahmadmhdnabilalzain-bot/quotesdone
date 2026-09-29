-- PROBE: the supplier-target tracker counts by trade and emirate, files one CEO task a day when behind, and the
-- ten-per-category gate opens only when every category in the set has ten. Seat: ceo. 28 Sep 2026.
--
-- Seeds 13 ZZ DEMO / @example.invalid approved suppliers (leads.is_demo is true for every one, asserted) in two
-- active trades: 10 in trade A stating no emirate (so UAE-wide), 3 in trade B stating Dubai only. Every routine is
-- called with p_demo = true, so only these rows are counted. The block always raises: nothing survives it.
--   node scripts/qsql.mjs scripts/sql/the_ceo_tracks_the_supplier_target_by_trade_and_emirate_probe.sql
do $$
declare v_a text; v_b text; v_lead bigint; i int; v_lic text := 'zz-demo/supplier-target-probe-licence.pdf';
  v_prof text := 'zz-demo/supplier-target-probe-profile.pdf'; v_notif0 bigint; v_notif1 bigint;
  a_uae int; a_shj int; b_uae int; b_dxb int; b_shj int; g_a jsonb; g_ab jsonb; s jsonb; r1 jsonb; r2 jsonb; n_task int;
  v_live jsonb; n_real int; v_base int; b0 int[];
begin
  set local statement_timeout = '30s';
  select min(code), max(code) into v_a, v_b from (select code from public.taxonomy_trade where active order by code limit 2) t;
  select count(*) into v_notif0 from public.notifications;
  -- the estate already holds demo suppliers (1 on 28 Sep 2026): every assertion is on the delta this probe adds
  v_base := (public.fn_ceo_supplier_target_status(timestamptz '2026-10-05 08:00+04', true)->>'verified')::int;
  select array[(select verified from public.fn_supplier_target_by_trade_emirate(true) where trade = v_a and emirate = 'UAE'),
               (select verified from public.fn_supplier_target_by_trade_emirate(true) where trade = v_a and emirate = 'Sharjah'),
               (select verified from public.fn_supplier_target_by_trade_emirate(true) where trade = v_b and emirate = 'UAE'),
               (select verified from public.fn_supplier_target_by_trade_emirate(true) where trade = v_b and emirate = 'Dubai'),
               (select verified from public.fn_supplier_target_by_trade_emirate(true) where trade = v_b and emirate = 'Sharjah')] into b0;
  if b0 <> array[0,0,0,0,0] then raise exception 'PROBE FAIL: trades % / % already hold demo suppliers %; pick others', v_a, v_b, b0; end if;
  insert into storage.objects (bucket_id, name) values ('supplier-docs', v_lic), ('supplier-docs', v_prof) on conflict do nothing;

  for i in 1..13 loop
    insert into public.leads (company_name, email, emirate, sector, phone, owner_phone_verified, owner_email_verified,
                              license_doc_path, company_profile_doc_path, signed_terms_path, verified, approval_status)
    values (format('ZZ DEMO supplier target %s', i), format('zz.demo.target.%s@example.invalid', i), 'Dubai',
            case when i <= 10 then v_a else v_b end, '+9715000077' || lpad(i::text, 2, '0'), true, true, v_lic, v_prof,
            'suppliers/zz-demo-target-probe.pdf', true, 'approved')
    returning id into v_lead;
    insert into public.supplier_capabilities (supplier_id, trades, roles, coverage_emirates, confirmed_at)
    values (v_lead, array[case when i <= 10 then v_a else v_b end], array['contractor'],
            case when i <= 10 then '{}'::text[] else array['Dubai'] end, now());
  end loop;

  -- incapable of reaching a real person: every seeded lead is a demo identity
  select count(*) into n_real from public.leads where company_name like 'ZZ DEMO supplier target %' and not is_demo;
  if n_real <> 0 then raise exception 'PROBE FAIL: % seeded lead(s) are not demo identities', n_real; end if;

  select verified into a_uae from public.fn_supplier_target_by_trade_emirate(true) where trade = v_a and emirate = 'UAE';
  select verified into a_shj from public.fn_supplier_target_by_trade_emirate(true) where trade = v_a and emirate = 'Sharjah';
  select verified into b_uae from public.fn_supplier_target_by_trade_emirate(true) where trade = v_b and emirate = 'UAE';
  select verified into b_dxb from public.fn_supplier_target_by_trade_emirate(true) where trade = v_b and emirate = 'Dubai';
  select verified into b_shj from public.fn_supplier_target_by_trade_emirate(true) where trade = v_b and emirate = 'Sharjah';
  if (a_uae, a_shj, b_uae, b_dxb, b_shj) is distinct from (10, 10, 3, 3, 0) then
    raise exception 'PROBE FAIL: counts A uae=% shj=% B uae=% dxb=% shj=%', a_uae, a_shj, b_uae, b_dxb, b_shj;
  end if;

  g_a := public.fn_every_category_has_ten_suppliers(true, array[v_a]);
  g_ab := public.fn_every_category_has_ten_suppliers(true, array[v_a, v_b]);
  if not (g_a->>'gate')::boolean or (g_ab->>'gate')::boolean or (g_ab->>'below_ten')::int <> 1 then
    raise exception 'PROBE FAIL: gate A=% A+B=%', g_a, g_ab;
  end if;

  -- 5 Oct 2026: the path to 50 by 12 Oct expects 25; base + 13 verified is behind, shortfall 50 - (base + 13)
  s := public.fn_ceo_supplier_target_status(timestamptz '2026-10-05 08:00+04', true);
  if (s->>'verified')::int <> v_base + 13 or (s->>'expected_today')::int <> 25 or (s->>'shortfall')::int <> 50 - (v_base + 13) or not (s->>'behind')::boolean then
    raise exception 'PROBE FAIL: status %', s;
  end if;
  r1 := public.fn_ceo_supplier_target(timestamptz '2026-10-05 08:00+04', true);
  r2 := public.fn_ceo_supplier_target(timestamptz '2026-10-05 20:00+04', true);
  select count(*) into n_task from public.ceo_task where title = 'Supplier target behind on 2026-10-05 (demo)';
  if n_task <> 1 or r1->>'task_id' is null or r2->>'task_id' is not null then
    raise exception 'PROBE FAIL: tasks=% first=% second=%', n_task, r1->>'task_id', r2->>'task_id';
  end if;

  -- the live paid path: organic only today, whatever the switches say
  v_live := public.fn_ads_autospend_state();
  if (v_live->>'live_allowed')::boolean or v_live->>'reason' not like 'organic only (ledger 1004)%' then
    raise exception 'PROBE FAIL: paid path not refused: %', v_live;
  end if;

  select count(*) into v_notif1 from public.notifications;
  if v_notif1 <> v_notif0 then raise exception 'PROBE FAIL: % notification row(s) were written', v_notif1 - v_notif0; end if;

  raise exception 'CHK<<A_uae=% A_sharjah=% B_uae=% B_dubai=% B_sharjah=% gate_A=% gate_AB=% below_ten_AB=% base=% verified=% expected=% shortfall=% pace=% tasks=% second_run_task=% live_allowed=% reason=[%] live_below_ten=% notifications_written=%>>',
    a_uae, a_shj, b_uae, b_dxb, b_shj, g_a->>'gate', g_ab->>'gate', g_ab->>'below_ten', v_base, s->>'verified', s->>'expected_today',
    s->>'shortfall', s->>'pace_per_day', n_task, coalesce(r2->>'task_id', 'none'), v_live->>'live_allowed', v_live->>'reason',
    public.fn_every_category_has_ten_suppliers()->>'below_ten', v_notif1 - v_notif0;
end $$;
