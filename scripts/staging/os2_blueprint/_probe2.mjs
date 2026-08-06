import { mgmtRead, PROD_REF } from '../qd_guard.mjs';
import { browserEdgeFunctions, edgeSeeds } from './ui_closure.mjs';
const q = async (sql) => await mgmtRead(PROD_REF, sql);
const efs = browserEdgeFunctions(process.cwd());
const seeds = edgeSeeds(process.cwd(), efs);
console.log('seed sample:', seeds.join(' '));
const target = process.argv[2] || 'fn_graph_rebuild';
console.log('is seed?', seeds.includes(target));
const r = await q(`select p.proname n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> '${target}'
    and pg_get_functiondef(p.oid) ~* '\\y${target}\\y'`);
console.log('named by:', r.map(x => x.n).join(','));
