import { sql } from '../lib/db.mjs';
console.log(JSON.stringify(await sql(`select * from public.phase_d_object_reference_strategy where object_id='notification'`)));
console.log('--- notifications columns ---');
console.log(JSON.stringify(await sql(`select column_name, is_nullable, column_default from information_schema.columns where table_name='notifications' and table_schema='public' order by ordinal_position`)).slice(0,2500));
console.log('--- ref_resolve for a notification ref (aborted insert) ---');
const q = `do $emit$
declare v_id bigint; v_ref jsonb; v_res jsonb; v_out text := '';
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','notif'));
  insert into public.notifications (to_role, type, channel, to_email, subject, body, status)
  values ('phase_d_fixture','phase_d_fixture','none','PHASE_D_FIXTURE_DO_NOT_PUBLISH@example.invalid','ZZ','ZZ','suppressed')
  returning id into v_id;
  v_out := v_out || 'inserted id=' || v_id || chr(10);
  v_ref := public.fn_phase_d_ref(jsonb_build_object('object_id','notification','identity', v_id::text, 'owner_ref','phase_d_fixture'));
  v_out := v_out || 'ref=' || v_ref::text || chr(10);
  begin v_res := public.fn_phase_d_ref_resolve(v_ref); v_out := v_out || 'resolved=' || left(v_res::text,400); exception when others then v_out := v_out || 'resolve ERR ' || left(SQLERRM,200); end;
  raise exception 'NT<<%>>', v_out;
end $emit$;`;
try { await sql(q); } catch (e) { const m = String(e.message); const a = m.indexOf('NT<<'); console.log(a<0?m.slice(0,900):m.slice(a+4, m.lastIndexOf('>>')).replace(/\n/g,'\n')); }
