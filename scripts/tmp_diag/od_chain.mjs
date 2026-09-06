import fs from 'node:fs';
const all = JSON.parse(fs.readFileSync(new URL('./allfns.json', import.meta.url)));
const names = new Set(Object.keys(all));
const strip = s => s.replace(/--[^\n]*/g,'').replace(/\/\*[\s\S]*?\*\//g,'');
const info = {};
for (const [k,v] of Object.entries(all)) {
  const src = strip(v);
  const w = new Set();
  for (const m of src.matchAll(/\binsert\s+into\s+((?:public\.)?"?[a-z0-9_]+"?)/gi)) w.add('INSERT '+m[1].replace(/"/g,'').replace(/^public\./,''));
  for (const m of src.matchAll(/\bupdate\s+((?:public\.)?"?[a-z0-9_]+"?)\s+set/gi)) w.add('UPDATE '+m[1].replace(/"/g,'').replace(/^public\./,''));
  for (const m of src.matchAll(/\bdelete\s+from\s+((?:public\.)?"?[a-z0-9_]+"?)/gi)) w.add('DELETE '+m[1].replace(/"/g,'').replace(/^public\./,''));
  const http = /net\.http_(post|get)/i.test(src) ? 'HTTP' : '';
  const calls = new Set();
  for (const m of src.matchAll(/\b([a-z][a-z0-9_]{3,})\s*\(/gi)) { const c=m[1].toLowerCase(); if (names.has(c) && c!==k) calls.add(c); }
  info[k] = { writes:[...w].sort(), http, calls:[...calls] };
}
const seeds = process.argv.slice(2);
const MAXD = Number(process.env.MAXD || 3);
const printed = new Set();
function walk(fn, depth, path) {
  const pad = '  '.repeat(depth);
  const i = info[fn];
  if (!i) { console.log(pad+fn+'  (not a public function)'); return; }
  const tag = [i.http, i.writes.length?i.writes.join(' ; '):'(no direct table write)'].filter(Boolean).join('  ');
  console.log(`${pad}${fn} -> ${tag}`);
  if (depth >= MAXD) { if(i.calls.length) console.log(pad+'  ...(depth cap)'); return; }
  for (const c of i.calls) {
    if (path.includes(c)) { continue; }
    const ci = info[c];
    if (!ci) continue;
    if (!ci.writes.length && !ci.http) continue;   // only show callees that write or POST
    walk(c, depth+1, [...path, c]);
  }
}
for (const s of seeds) { console.log('=== '+s+' ==='); walk(s, 0, [s]); }
