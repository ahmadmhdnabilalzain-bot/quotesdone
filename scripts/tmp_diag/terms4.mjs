import { sql } from '../phase_b/lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);console.log(JSON.stringify(await sql(t),null,1).slice(0,4500));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,300)}`)}};
await q('views', `select viewname, definition from pg_views where schemaname='public' and viewname in ('v_obj_supplier_terms_acceptance','v_obj_customer_terms_acceptance')`);
await q('write map terms', `select * from public.phase_d_object_write_map where object_id ilike '%terms_acceptance%'`);
await q('binding terms', `select * from public.phase_d_business_object_binding where object_id ilike '%terms_acceptance%'`);
await q('legal docs', `select slug, version, status, left(encode(sha256(convert_to(coalesce(body_html,''),'UTF8')),'hex'),20) h from public.legal_documents order by slug, version`);
