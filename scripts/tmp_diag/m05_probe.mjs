import { sql } from '../lib/db.mjs';
import { readFileSync } from 'node:fs';
const body = readFileSync('scripts/sql/phase_d_m05_the_rule_that_would_have_refused_the_send_was_never_asked.sql','utf8')
  .replace(/^--[^\n]*\n/gm, '').trim();
const q = `do $emit$
declare v jsonb; v_out text := '';
begin
  execute $m05$${body}$m05$;
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','m05probe'));
  begin
    v := public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W13-S02','idempotency_key','zz-m05-dirty','mock_case','success',
      'approved_payload_ref','zz-approved-m05',
      'approved_payload', jsonb_build_object('body','contact Ahmad at zz.cust@example.invalid / 0501234567')));
    v_out := v_out || 'DIRTY delivered=' || coalesce(v->>'delivered','?') || ' ;; ';
  exception when others then v_out := v_out || 'DIRTY refused: ' || left(SQLERRM,150) || ' ;; ';
  end;
  begin
    v := public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W13-S02','idempotency_key','zz-m05-clean','mock_case','success',
      'approved_payload_ref','zz-approved-m05',
      'approved_payload', jsonb_build_object('body','the supplier-safe brief carries no identity')));
    v_out := v_out || 'CLEAN delivered=' || coalesce(v->>'delivered','?');
  exception when others then v_out := v_out || 'CLEAN refused: ' || left(SQLERRM,150);
  end;
  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;
try { await sql(q); } catch (e) { const m=String(e.message); const i=m.indexOf('PROBE<<'); console.log(i>=0?m.slice(i+7,m.lastIndexOf('>>')).replace(/ ;; /g,'\n'):m.slice(0,1500)); }
