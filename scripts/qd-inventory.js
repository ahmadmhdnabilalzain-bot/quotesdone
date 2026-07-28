// Codebase inventory. Node, no deps. Run: node scripts/qd-inventory.js
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const SKIP = new Set(['node_modules', '.next', '.git', '.vercel', 'graphify-out', '_archive', '.claude']);

function walk(dir, exts, out = []) {
  let ents; try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of ents) {
    if (SKIP.has(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, exts, out);
    else if (exts.some((x) => e.name.endsWith(x))) {
      const s = fs.statSync(p);
      const lines = fs.readFileSync(p, 'utf8').split('\n').length;
      out.push({ p: path.relative(ROOT, p), bytes: s.size, lines });
    }
  }
  return out;
}

function report(label, files) {
  const b = files.reduce((a, f) => a + f.bytes, 0);
  const l = files.reduce((a, f) => a + f.lines, 0);
  console.log(`${label}: ${files.length} files, ${l.toLocaleString()} lines, ${(b / 1024).toFixed(0)} KB`);
}

const edge = walk(path.join(ROOT, 'supabase', 'functions'), ['.ts']);
const src = walk(path.join(ROOT, 'src'), ['.ts', '.tsx']);
report('EDGE FUNCTIONS', edge);
report('NEXT APP (src)', src);
console.log('');
console.log('TOP 30 EDGE FUNCTIONS BY LINES:');
edge.sort((a, b) => b.lines - a.lines).slice(0, 30)
  .forEach((f) => console.log(String(f.lines).padStart(6), f.p.replace('supabase\\functions\\', '').replace('supabase/functions/', '')));
console.log('');
console.log('TOP 20 APP FILES BY LINES:');
src.sort((a, b) => b.lines - a.lines).slice(0, 20)
  .forEach((f) => console.log(String(f.lines).padStart(6), f.p));
console.log('');
console.log('APP ROUTES:');
walk(path.join(ROOT, 'src', 'app'), ['page.tsx', 'route.ts'])
  .forEach((f) => console.log('  ', f.p.replace('src\\app\\', '').replace('src/app/', '')));
