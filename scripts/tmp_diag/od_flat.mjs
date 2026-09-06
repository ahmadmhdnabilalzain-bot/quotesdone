import fs from 'node:fs';
const all = JSON.parse(fs.readFileSync(new URL('./allfns.json', import.meta.url)));
const names = new Set(Object.keys(all));
const strip = s => s.replace(/--[^\n]*/g, '').replace(/\/\*[\s\S]*?\*\//g, '');
const info = {};
for (const [k, v] of Object.entries(all)) {
  const src = strip(v);
  const w = new Set();
  for (const m of src.matchAll(/\binsert\s+into\s+((?:public\.)?"?[a-z0-9_]+"?)/gi)) w.add('INS ' + m[1].replace(/"/g, '').replace(/^public\./, ''));
  for (const m of src.matchAll(/\bupdate\s+((?:public\.)?"?[a-z0-9_]+"?)\s+set/gi)) w.add('UPD ' + m[1].replace(/"/g, '').replace(/^public\./, ''));
  for (const m of src.matchAll(/\bdelete\s+from\s+((?:public\.)?"?[a-z0-9_]+"?)/gi)) w.add('DEL ' + m[1].replace(/"/g, '').replace(/^public\./, ''));
  const http = /net\.http_(post|get)/i.test(src) ? 'NET_HTTP ' : '';
  const calls = new Set();
  for (const m of src.matchAll(/\b([a-z][a-z0-9_]{3,})\s*\(/gi)) { const c = m[1].toLowerCase(); if (names.has(c) && c !== k) calls.add(c); }
  info[k] = { writes: [...w].sort(), http, calls: [...calls] };
}
const seeds = process.argv.slice(2);
for (const s of seeds) {
  const i = info[s];
  if (!i) { console.log(s + '\tNOT_A_PUBLIC_FUNCTION'); continue; }
  const kids = i.calls.filter(c => info[c] && (info[c].writes.length || info[c].http))
    .map(c => c + '{' + info[c].http + info[c].writes.join(',') + '}');
  console.log(s + '\t' + i.http + '[' + i.writes.join(' | ') + ']\tCALLS: ' + kids.join('  '));
}
