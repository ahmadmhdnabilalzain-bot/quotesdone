import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`select * from public.legal_documents limit 15`);
console.log(JSON.stringify(r.map(x=>({k:x.slug||x.document_slug||x.key, t:x.title, v:x.version, u:x.updated_at||x.published_at})),null,0).slice(0,1500));
const c = await sql(`select column_name from information_schema.columns where table_schema='public' and table_name='legal_documents' order by ordinal_position`);
console.log(c.map(x=>x.column_name).join(','));
