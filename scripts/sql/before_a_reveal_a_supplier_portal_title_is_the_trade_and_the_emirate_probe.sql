-- before_a_reveal_a_supplier_portal_title_is_the_trade_and_the_emirate_probe.sql — a PURE probe: it always raises CHK<<...>>,
-- so everything it does rolls back. Assigned: sales_engineer. Run after before_a_reveal_a_supplier_portal_title_is_the_trade_and_the_emirate.sql.
-- 1. It plants its OWN customer file on one unrevealed match (a public.documents row named after a ZZ DEMO customer and site,
--    rolled back with the rest; second review of F2: with no such document in production the file-name branch could never fail).
-- 2. It reads every live match with NO reveal (no transactions row with revealed_at for that supplier and inquiry) and asks
--    fn_supplier_workspaces and fn_supplier_opportunities what that supplier is shown: every title must be the trade, emirate
--    and job number label (the same string as supabase/functions/supplier_portal/before_reveal.ts portalTitle), no requirement
--    or estimated value may be served, and no customer file name.
-- It changes no real row: the planted document is counted before and after inside the probe and dies with the raise.
do $probe$
declare
  r record; w jsonb; o jsonb; v_bad text := ''; v_checked int := 0; v_label text; v_doc bigint; v_target uuid; v_files int := 0;
begin
  select m.inquiry_id into v_target from public.inquiry_matches m
   where not exists (select 1 from public.transactions t where t.inquiry_id = m.inquiry_id and t.supplier_id = m.supplier_id and t.revealed_at is not null)
   limit 1;
  if v_target is null then raise exception 'CHK<<PROBE FAILED: no unrevealed match to plant the file on>>'; end if;
  insert into public.documents (bucket, path, file_name, kind, ref_table, ref_id, status)
    values ('drawing-files', 'zz-demo/probe/ZZ DEMO Omar Haddad Villa 15 Al Barsha 2.pdf', 'ZZ DEMO Omar Haddad Villa 15 Al Barsha 2.pdf', 'drawing', 'inquiries', v_target::text, 'pending')
    returning id into v_doc;
  for r in select distinct m.supplier_id, i.id, i.rfq_no, i.category, i.emirate
             from public.inquiry_matches m join public.inquiries i on i.id = m.inquiry_id
            where not exists (select 1 from public.transactions t where t.inquiry_id = i.id and t.supplier_id = m.supplier_id and t.revealed_at is not null)
            limit 200 loop
    v_label := upper(left(btrim(replace(replace(coalesce(r.category, 'general'), '_', ' '), '-', ' ')), 1)) || substr(btrim(replace(replace(coalesce(r.category, 'general'), '_', ' '), '-', ' ')), 2)
               || ' work' || coalesce(' in ' || r.emirate, '') || ' · Job ' || coalesce(r.rfq_no::text, upper(left(r.id::text, 8)));
    w := (select x from jsonb_array_elements(public.fn_supplier_workspaces(r.supplier_id)->'workspaces') x where x->>'inquiry_id' = r.id::text limit 1);
    if w is not null then
      v_checked := v_checked + 1;
      if w->'project'->>'title' is distinct from v_label then v_bad := v_bad || ' workspace title ' || r.id || ';'; end if;
      v_files := v_files + jsonb_array_length(coalesce(w->'files', '[]'::jsonb));
      if exists (select 1 from jsonb_array_elements(coalesce(w->'files', '[]'::jsonb)) f where f->>'name' !~ '^Job file \(') then v_bad := v_bad || ' file name ' || r.id || ';'; end if;
    end if;
    o := (select x from jsonb_array_elements(public.fn_supplier_opportunities(r.supplier_id)->'opportunities') x where x->>'inquiry_id' = r.id::text limit 1);
    if o is not null then
      v_checked := v_checked + 1;
      if o->>'project_title' is distinct from v_label or o->>'requirement' is not null or o->>'estimated_value' is not null then v_bad := v_bad || ' opportunity ' || r.id || ';'; end if;
    end if;
  end loop;
  if v_files = 0 then v_bad := v_bad || ' the planted file was not listed, so its name was never tested;'; end if;
  if v_bad <> '' then raise exception 'CHK<<PROBE FAILED: a supplier is served customer text before a reveal:%>>', left(v_bad, 400); end if;
  raise exception 'CHK<<PROBE OK: % unrevealed workspace/opportunity entries read and % file(s), the planted one included; every title is the trade, emirate and job number, no requirement, no value, no file name>>', v_checked, v_files;
end
$probe$;
