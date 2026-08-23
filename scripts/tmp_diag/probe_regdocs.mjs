import { sql } from '../phase_b/lib/db.mjs';
const q = `do $p$
declare v_id bigint; v_out text := ''; n0 int; n1 int; n2 int;
begin
  select count(*) into n0 from public.documents;
  insert into public.leads (company_name, email, claimed, claimed_by, verified, approval_status, source, business_role)
  values ('ZZ DEMO — regdocs probe', 'zz-regdocs@example.invalid', true, 'zz-regdocs@example.invalid', false, 'pending', 'zz_probe', 'supplier')
  returning id into v_id;
  select count(*) into n1 from public.documents;
  update public.leads set iban_doc_path = 'zz-probe/iban.pdf' where id = v_id;
  select count(*) into n2 from public.documents;
  v_out := 'before=' || n0 || ' after_insert=' || n1 || ' after_iban_update=' || n2
        || ' | new=' || coalesce((select string_agg(path, ' ; ') from public.documents where path like 'zz-probe%'),'(none)');
  update public.leads set license_doc_path = 'zz-probe/lic.pdf' where id = v_id;
  v_out := v_out || ' | after_license_update=' || (select count(*) from public.documents)::text;
  raise exception 'DBG<<%>>', v_out;
end $p$;`;
try { await sql(q); } catch (e) {
  const m = String(e.message); const a = m.indexOf('DBG<<');
  console.log(a>=0 ? m.slice(a+5, m.indexOf('>>', a)) : m.slice(0,1500));
}
