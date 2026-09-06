import { readFileSync } from 'node:fs';
const [file, ...ids] = process.argv.slice(2);
const lines = readFileSync(file, 'utf8').split(/\r?\n/);
const hdr = lines.find(l => l && !l.startsWith('#'));
const cols = hdr.split(',').map(c => c.replace(/^"|"$/g, ''));
const split = (l) => {
  const cells = []; let cur = '', inq = false;
  for (const ch of l) {
    if (ch === '"') inq = !inq;
    else if (ch === ',' && !inq) { cells.push(cur); cur = ''; }
    else cur += ch;
  }
  cells.push(cur); return cells;
};
for (const l of lines) {
  if (!l || l.startsWith('#') || l === hdr) continue;
  const cells = split(l);
  if (!ids.length || ids.some(id => cells.includes(id))) {
    console.log('--- ' + cells[1]);
    cols.forEach((c, i) => console.log(`  ${c} = ${cells[i]}`));
  }
}
