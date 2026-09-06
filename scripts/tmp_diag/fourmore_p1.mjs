import { sql } from '../phase_b/lib/db.mjs';
const P = `
do $emit$
declare v_out text := ''; v_fx jsonb; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','fourmore-p1'));
  v_out := v_out || E'\ninquiries before: ' || (select count(*) from public.inquiries)::text;
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','fourmore','execution_context','test'));
  v_out := v_out || E'\ninquiries=' || (select count(*) from public.inquiries)::text
        || ' leads=' || (select count(*) from public.leads)::text
        || ' quotes=' || (select count(*) from public.quotes)::text
        || ' objrec=' || (select count(*) from public.phase_d_object_record)::text
        || ' notif=' || (select count(*) from public.notifications)::text
        || ' im=' || (select count(*) from public.inquiry_matches)::text;
  for r in select id::text as id, status, rfq_ready::text as rr from public.inquiries limit 3 loop
    v_out := v_out || E'\nINQ ' || r.id || ' status=' || coalesce(r.status,'(null)') || ' rfq_ready=' || coalesce(r.rr,'(null)');
  end loop;
  for r in select id::text as id, coalesce(approval_status,'(null)') ast, coalesce(verified::text,'-') vf,
      coalesce(banned::text,'-') b, coalesce(matching_blocked::text,'-') mb, coalesce(permanently_closed::text,'-') pc,
      coalesce(license_expiry::text,'-') le, coalesce(email,'(null)') em, coalesce(company_name,'') cn
      from public.leads where company_name ilike 'ZZ%' or email ilike '%example.invalid' limit 5 loop
    v_out := v_out || E'\nLEAD ' || r.id || ' appr=' || r.ast || ' ver=' || r.vf || ' banned=' || r.b || ' mblk=' || r.mb || ' pclosed=' || r.pc || ' lic=' || r.le || ' em=' || r.em || ' cn=' || r.cn;
  end loop;
  for r in select object_id, business_key, state, version::text v, owner_ref, payload::text p from public.phase_d_object_record where object_id like '%terms%' loop
    v_out := v_out || E'\nOBJ ' || r.object_id || ' bk=' || r.business_key || ' st=' || r.state || ' v=' || r.v || ' own=' || r.owner_ref || ' pay=' || left(r.p,300);
  end loop;
  v_out := v_out || E'\nFXKEYS: ' || (select string_agg(k,',' order by k) from jsonb_object_keys(v_fx) k);
  v_out := v_out || E'\nFXREFS: ' || left(coalesce(v_fx->'parent_refs','{}'::jsonb)::text, 2000);
  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;
try { await sql(P); console.log('NO RAISE?!'); } catch(e) { console.log(e.message.split('\n').join('\n')); }
