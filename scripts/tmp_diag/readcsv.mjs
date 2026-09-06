import { readFileSync } from 'node:fs';
export function readCsv(path) {
  const t = readFileSync(path, 'utf8');
  const lines = t.split('\n');
  const hi = lines.findIndex(l => !l.startsWith('#') && l.includes(','));
  const cols = lines[hi].split(',');
  const body = lines.slice(hi + 1).join('\n');
  const rows = []; let row = [], cur = '', q = false;
  for (let i = 0; i < body.length; i++) { const c = body[i];
    if (q) { if (c === '"' && body[i+1] === '"') { cur += '"'; i++; } else if (c === '"') q = false; else cur += c; }
    else if (c === '"') q = true; else if (c === ',') { row.push(cur); cur = ''; }
    else if (c === '\n') { row.push(cur); rows.push(row); row = []; cur = ''; }
    else if (c !== '\r') cur += c; }
  if (row.length > 3) rows.push(row);
  return rows.filter(r => r.length > 3).map(r => Object.fromEntries(cols.map((c, i) => [c, r[i]])));
}
