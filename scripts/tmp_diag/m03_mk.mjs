// usage: node m03_mk.mjs <headFile> <nHeadLines> <bodyFile> <outFile> [replacements as a=b pairs]
import fs from 'node:fs';
const [h,n,b,o,...rep] = process.argv.slice(2);
let head = fs.readFileSync(h,'utf8').split('\n').slice(0,Number(n)).join('\n');
for (const r of rep) { const [a,c] = r.split('=>'); head = head.split(a).join(c); }
fs.writeFileSync(o, head + '\n' + fs.readFileSync(b,'utf8'));
console.log('wrote', o);
