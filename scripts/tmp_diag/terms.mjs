import { sql } from '../phase_b/lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);console.log(JSON.stringify(await sql(t),null,1).slice(0,5000));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,300)}`)}};
await q('catalogue terms rows', `select scope, field_key, value, note from public.phase_d_fixture_catalogue where field_key ilike '%terms%' or (value #>> '{}') ilike '%terms%'`);
await q('legal_documents', `select id, slug, version, left(encode(sha256(convert_to(coalesce(body_html,''),'UTF8')),'hex'),16) hash16, length(coalesce(body_html,'')) len, status from public.legal_documents order by slug, version`);
await q('BR-025 predicate', `select substring(prosrc from position('BR-025' in prosrc)-200 for 3000) src from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname='fn_phase_d_rule_check'`);
