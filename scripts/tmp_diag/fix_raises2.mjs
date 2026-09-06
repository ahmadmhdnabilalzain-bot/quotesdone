// RAISE's format string takes % per argument; %s is not a specifier, so plpgsql emitted each value
// followed by a literal 's'. The six payload raises are rewritten as a single '%' with one
// concatenated argument — no format string left to get wrong.
import { readFileSync, writeFileSync } from 'node:fs';

const p = 'scripts/sql/phase_d_o08_the_nine_that_remained_executed.sql';
let s = readFileSync(p, 'utf8');

// Split an argument list on top-level commas (parens and single-quoted strings are not separators).
function splitArgs(txt) {
  const out = []; let depth = 0, q = false, cur = '';
  for (let i = 0; i < txt.length; i++) {
    const c = txt[i];
    if (q) { cur += c; if (c === "'") { if (txt[i + 1] === "'") { cur += "'"; i++; } else q = false; } continue; }
    if (c === "'") { q = true; cur += c; continue; }
    if (c === '(') depth++;
    if (c === ')') depth--;
    if (c === ',' && depth === 0) { out.push(cur.trim()); cur = ''; continue; }
    cur += c;
  }
  if (cur.trim()) out.push(cur.trim());
  return out;
}

let fixed = 0;
const re = /raise exception '(PD[A-Z0-9]+)((?:%s)+(?:\|%s)*)',([\s\S]*?);\n/g;
s = s.replace(re, (m, tag, _fmt, args) => {
  const a = splitArgs(args);
  fixed++;
  const joined = a.map((x, i) => (i === 0 ? x : `'|' || ${x}`)).join(' || ');
  return `raise exception '%', '${tag}' || ${joined};\n`;
});

if (fixed !== 6) { console.error(`rewrote ${fixed} raise(s), expected 6`); process.exit(1); }
writeFileSync(p, s);
console.log('rewrote', fixed, 'raise statements');
