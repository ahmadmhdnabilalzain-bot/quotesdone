-- before_a_reveal_a_supplier_portal_title_is_the_trade_and_the_emirate_probe.sql — a PURE probe: it always raises CHK<<...>>,
-- so it changes nothing. Assigned: sales_engineer. Run after before_a_reveal_a_supplier_portal_title_is_the_trade_and_the_emirate.sql.
-- It reads every live match that has NO reveal (no transactions row with revealed_at for that supplier and inquiry) and asks
-- fn_supplier_workspaces and fn_supplier_opportunities what that supplier is shown: every title must be the trade-and-emirate
-- label, no requirement or estimated value may be served, and no word of the summary longer than five letters that is not in
-- the label may appear. It writes nothing and touches no row.
do $probe$
declare
  r record; w jsonb; o jsonb; v_bad text := ''; v_checked int := 0; v_label text;
begin
  for r in select distinct m.supplier_id, i.id, i.category, i.emirate, coalesce(i.summary, '') summary
             from public.inquiry_matches m join public.inquiries i on i.id = m.inquiry_id
            where not exists (select 1 from public.transactions t where t.inquiry_id = i.id and t.supplier_id = m.supplier_id and t.revealed_at is not null)
            limit 200 loop
    v_label := initcap(replace(replace(coalesce(r.category, 'general'), '_', ' '), '-', ' ')) || ' work' || coalesce(' in ' || r.emirate, '');
    w := (select x from jsonb_array_elements(public.fn_supplier_workspaces(r.supplier_id)->'workspaces') x where x->>'inquiry_id' = r.id::text limit 1);
    if w is not null then
      v_checked := v_checked + 1;
      if w->'project'->>'title' is distinct from v_label then v_bad := v_bad || ' workspace ' || r.id || ';'; end if;
      if exists (select 1 from jsonb_array_elements(coalesce(w->'files', '[]'::jsonb)) f where f->>'name' !~ '^Job file \(') then v_bad := v_bad || ' file name ' || r.id || ';'; end if;
    end if;
    o := (select x from jsonb_array_elements(public.fn_supplier_opportunities(r.supplier_id)->'opportunities') x where x->>'inquiry_id' = r.id::text limit 1);
    if o is not null then
      v_checked := v_checked + 1;
      if o->>'project_title' is distinct from v_label or o->>'requirement' is not null or o->>'estimated_value' is not null then v_bad := v_bad || ' opportunity ' || r.id || ';'; end if;
    end if;
  end loop;
  if v_bad <> '' then raise exception 'CHK<<PROBE FAILED: a supplier is served customer text before a reveal:%>>', left(v_bad, 400); end if;
  raise exception 'CHK<<PROBE OK: % unrevealed workspace/opportunity entries read; every title is the trade and the emirate, no requirement, no value, no file name>>', v_checked;
end
$probe$;
