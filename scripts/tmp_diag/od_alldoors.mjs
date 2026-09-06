import { sql } from '../phase_b/lib/db.mjs';
import fs from 'node:fs';
const all = JSON.parse(fs.readFileSync(new URL('./allfns.json', import.meta.url)));
const names = new Set(Object.keys(all));
const strip = s => s.replace(/--[^\n]*/g, '').replace(/\/\*[\s\S]*?\*\//g, '');
const direct = {}, calls = {};
for (const [k, v] of Object.entries(all)) {
  const src = strip(v);
  direct[k] = /net\.http_(post|get)\s*\(/i.test(src);
  const c = new Set();
  for (const m of src.matchAll(/\b([a-z][a-z0-9_]{3,})\s*\(/gi)) { const x = m[1].toLowerCase(); if (names.has(x) && x !== k) c.add(x); }
  calls[k] = [...c];
}
function pathToHttp(fn, seen = new Set(), path = []) {
  if (seen.has(fn) || !names.has(fn)) return null;
  seen.add(fn);
  if (direct[fn]) return [...path, fn];
  for (const c of calls[fn]) { const r = pathToHttp(c, seen, [...path, fn]); if (r) return r; }
  return null;
}
const trgs = await sql(`
select c.relname as tbl, tg.tgname as trg, p.proname as fn
  from pg_trigger tg join pg_class c on c.oid=tg.tgrelid
  join pg_namespace n on n.oid=c.relnamespace join pg_proc p on p.oid=tg.tgfoid
 where not tg.tgisinternal and n.nspname='public' order by 1,2`);
const doors = await sql(`select relation, trigger_name from public.phase_d_outbound_door`);
const reg = new Set(doors.map(d => d.relation + '|' + d.trigger_name));
console.log('total public triggers: ' + trgs.length);
for (const t of trgs) {
  const p = pathToHttp(t.fn);
  if (!p) continue;
  const registered = reg.has('public.' + t.tbl + '|' + t.trg);
  console.log([registered ? 'REGISTERED' : 'NOT_REGISTERED', 'public.' + t.tbl, t.trg, p.join(' -> ')].join('\t'));
}
