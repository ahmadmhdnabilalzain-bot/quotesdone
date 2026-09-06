import { sql } from '../phase_b/lib/db.mjs';
const q = async (l,s)=>{try{const r=await sql(s);console.log('=== '+l);console.log(JSON.stringify(r).slice(0,2500));}catch(e){console.log('=== '+l+' ERR '+String(e).slice(0,300));}};
await q('render routine names', `select p.proname from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname like 'fn_phase_d%' and p.prosrc ~* 'render|pdf|exif|docx' order by 1`);
await q('legal_documents', `select count(*) n from public.legal_documents`);
await q('kb tax docs', `select count(*) n from public.legal_documents where doc_key ~* 'tax|vat' or title ~* 'tax|vat'`);
