import { sql } from '../phase_b/lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);console.log(JSON.stringify(await sql(t),null,1).slice(0,3500));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,300)}`)}};
await q('legal_documents cols', `select column_name, data_type from information_schema.columns where table_schema='public' and table_name='legal_documents' order by ordinal_position`);
await q('legal_documents rows', `select slug, version, left(encode(sha256(convert_to(coalesce(body_html,''),'UTF8')),'hex'),16) h from public.legal_documents order by slug, version`);
await q('ctx key object constraints', `select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid='public.phase_d_context_key_object'::regclass`);
await q('rules using acceptance objects', `select rule_id, required_context from public.phase_d_rule_enforcement where required_context && array['terms_version','terms_hash','acceptance_ref']`);
