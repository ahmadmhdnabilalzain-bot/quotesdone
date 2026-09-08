import { sql } from '../lib/db.mjs';
console.log(JSON.stringify(await sql(`select entity, doc_type, attempts, left(coalesce(error,''),70) err, created_at from public.doc_backups where status='error' order by created_at desc limit 5`), null, 1));
console.log(JSON.stringify(await sql(`select count(*) n, max(created_at) newest from public.doc_backups where status='error' and created_at > now() - interval '24 hours'`)));
