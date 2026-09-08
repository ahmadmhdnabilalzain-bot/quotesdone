import { sql } from '../lib/db.mjs';
const q = async (label, s) => { try { const r = await sql(s); console.log('=== ' + label); console.log(JSON.stringify(r).slice(0, 9000)); } catch(e){ console.log('=== '+label+' ERR '+String(e).slice(0,700)); } };

await q('overlay bindings', `select * from public.phase_c_overlay_binding limit 20`);
await q('overlay roles', `select role_id, runtime_mode, status from public.org_role where runtime_mode='knowledge_overlay' order by 1 limit 20`);
await q('rule enforcement for BR-048 001 005 002 030 031 037 038', `select rule_id, status, refusal_code from public.phase_d_rule_enforcement where rule_id in ('BR-048','BR-001','BR-005','BR-002','BR-030','BR-031','BR-037','BR-038') order by 1`);
await q('rule names', `select rule_id, rule_name, rule_type from public.phase_b_business_rule where rule_id in ('BR-048','BR-001','BR-005','BR-002','BR-030','BR-031','BR-037','BR-038') order by 1`);
await q('overlay trigger attachment', `select c.relname, t.tgname from pg_trigger t join pg_class c on c.oid=t.tgrelid where t.tgfoid='public.fn_phase_c_overlay_may_not_dispatch'::regproc`);
await q('founder_approval_request cols+cons', `select (select json_agg(column_name order by ordinal_position) from information_schema.columns where table_schema='public' and table_name='founder_approval_request') cols,
 (select json_agg(json_build_object('n',conname,'d',pg_get_constraintdef(oid))) from pg_constraint where conrelid='public.founder_approval_request'::regclass) cons,
 (select json_agg(json_build_object('n',tgname,'f',tgfoid::regproc::text)) from pg_trigger where tgrelid='public.founder_approval_request'::regclass and not tgisinternal) trg,
 (select count(*) from public.founder_approval_request) n`);
