import { sql } from '../phase_b/lib/db.mjs';
const p = (t, r) => { console.log('=== ' + t + ' (' + (r ? r.length : 0) + ') ==='); console.log(JSON.stringify(r, null, 1)); };

p('legal_documents supplier-agreement', await sql(`select slug, version, encode(sha256(convert_to(coalesce(body_html,''),'UTF8')),'hex') as body_sha from public.legal_documents where slug in ('supplier-agreement','customer-terms') order by slug, version`));

p('BR-025 with CATALOGUE fixture values (the fallback the strict harness gets)', await sql(`
select * from public.fn_phase_d_rule_check('BR-025', jsonb_build_object(
  'terms_version','phase-d-fixture-terms-v1',
  'terms_hash','5d31c13d1f0fd16a280c0ca62541a0be11c8536dba64ac55e5d6c09a03a1e8ff'))`));

p('BR-025 with the REAL supplier-agreement pair (what the acceptance record carries)', await sql(`
select * from public.fn_phase_d_rule_check('BR-025', (
  select jsonb_build_object('terms_version', d.version,
    'terms_hash', encode(sha256(convert_to(coalesce(d.body_html,''),'UTF8')),'hex'))
  from public.legal_documents d where d.slug='supplier-agreement' order by d.version desc limit 1))`));

p('pk / constraints on phase_d_context_key_object', await sql(`
select con.conname, pg_get_constraintdef(con.oid) as def
  from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relname='phase_d_context_key_object'`));

p('every rule required_context key vs a fixture stage contributes_ref (subject resolvability)', await sql(`
select e.rule_id, r.workflow_scope, e.required_context,
       (select array_agg(distinct st.object_id) from public.phase_d_fixture_stage st
         where st.contributes_ref = any(e.required_context)) as subject_resolved_to,
       (select array_agg(distinct cko.object_id) from public.phase_d_context_key_object cko
         where cko.context_key = any(e.required_context)) as context_key_object
  from public.phase_d_rule_enforcement e
  join public.phase_b_business_rule r using (rule_id)
 where e.required_context is not null and cardinality(e.required_context)>0
 order by e.rule_id`));

p('all fixture stages contributes_ref', await sql(`select stage_no, stage_key, object_id, contributes_ref, contributes_kind from public.phase_d_fixture_stage order by stage_no`));
