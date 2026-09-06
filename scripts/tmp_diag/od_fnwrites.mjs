import { sql } from '../phase_b/lib/db.mjs';
const seeds = process.argv.slice(2);
const seen = new Map();
const q = [...seeds];
const strip = s => s.replace(/--[^\n]*/g,'').replace(/\/\*[\s\S]*?\*\//g,'');
while (q.length) {
  const fn = q.shift();
  if (seen.has(fn)) continue;
  const r = await sql(`select p.proname, p.prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='${fn}'`);
  if (!r.length) { seen.set(fn, {missing:true}); continue; }
  const src = strip(r.map(x=>x.prosrc).join('\n'));
  const w = new Set();
  for (const m of src.matchAll(/\binsert\s+into\s+((?:public\.)?[a-z0-9_]+)/gi)) w.add('INSERT '+m[1]);
  for (const m of src.matchAll(/\bupdate\s+((?:public\.)?[a-z0-9_]+)\s+set/gi)) w.add('UPDATE '+m[1]);
  for (const m of src.matchAll(/\bdelete\s+from\s+((?:public\.)?[a-z0-9_]+)/gi)) w.add('DELETE '+m[1]);
  const http = /net\.http_(post|get)/i.test(src);
  const calls = new Set();
  for (const m of src.matchAll(/\b((?:fn|trg|qd)_[a-z0-9_]+)\s*\(/gi)) calls.add(m[1].toLowerCase());
  calls.delete(fn.toLowerCase());
  seen.set(fn, {writes:[...w].sort(), http, calls:[...calls].sort()});
  for (const c of calls) if (!seen.has(c)) q.push(c);
}
for (const [k,v] of seen) {
  if (v.missing) { console.log(`${k}\tNOT_A_PUBLIC_FUNCTION`); continue; }
  console.log(`${k}\thttp=${v.http}\twrites=[${v.writes.join(' | ')}]\tcalls=[${v.calls.join(',')}]`);
}
