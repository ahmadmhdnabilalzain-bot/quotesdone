import fs from 'node:fs';
const all = JSON.parse(fs.readFileSync(new URL('./allfns.json', import.meta.url)));
const names = new Set(Object.keys(all));
const strip = s => s.replace(/--[^\n]*/g, '').replace(/\/\*[\s\S]*?\*\//g, '');
const TARGETS = ['customers', 'leads', 'inquiries', 'inquiry_matches', 'documents', 'quotes',
  'phase_c_workflow_run', 'phase_c_workflow_step_run', 'workflow_run', 'workflow_step_run',
  'org_tasks', 'notifications', 'company_event', 'doc_backups', 'phase_c_event_outbox'];
const cache = {};
function analyse(fn) {
  if (cache[fn]) return cache[fn];
  const src = strip(all[fn] || '');
  const writes = new Set(), reads = new Set();
  for (const t of TARGETS) {
    if (new RegExp('\\b(insert\\s+into|update|delete\\s+from)\\s+(public\\.)?"?' + t + '"?\\b', 'i').test(src)) writes.add(t);
    else if (new RegExp('\\b(from|join)\\s+(public\\.)?"?' + t + '"?\\b', 'i').test(src)) reads.add(t);
  }
  const http = /net\.http_(post|get)/i.test(src);
  const calls = new Set();
  for (const m of src.matchAll(/\b([a-z][a-z0-9_]{3,})\s*\(/gi)) { const c = m[1].toLowerCase(); if (names.has(c) && c !== fn) calls.add(c); }
  cache[fn] = { writes, reads, http, calls: [...calls] };
  return cache[fn];
}
function deep(fn, depth, seen) {
  const acc = { writes: new Set(), reads: new Set(), http: false, via: new Set() };
  const walk = (f, d) => {
    if (seen.has(f) || !names.has(f)) return;
    seen.add(f);
    const i = analyse(f);
    i.writes.forEach(x => acc.writes.add(x + (d ? '(via ' + f + ')' : '')));
    i.reads.forEach(x => acc.reads.add(x + (d ? '(via ' + f + ')' : '')));
    if (i.http) { acc.http = true; acc.via.add(f); }
    if (d < depth) for (const c of i.calls) walk(c, d + 1);
  };
  walk(fn, 0);
  return acc;
}
for (const fn of process.argv.slice(2)) {
  if (!names.has(fn)) { console.log(fn + '\tNOT_A_PUBLIC_FUNCTION'); continue; }
  const a = deep(fn, Number(process.env.D || 2), new Set());
  console.log(fn + '\n   WRITES: ' + [...a.writes].join(', ') + '\n   READS:  ' + [...a.reads].join(', ') + '\n   NET_HTTP: ' + (a.http ? [...a.via].join(', ') : 'no'));
}
