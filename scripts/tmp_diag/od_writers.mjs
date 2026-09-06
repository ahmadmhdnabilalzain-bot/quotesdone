import fs from 'node:fs';
const all = JSON.parse(fs.readFileSync(new URL('./allfns.json', import.meta.url)));
const strip = s => s.replace(/--[^\n]*/g, '').replace(/\/\*[\s\S]*?\*\//g, '');
const targets = process.argv.slice(2);
for (const t of targets) {
  const re = new RegExp('\\b(insert\\s+into|update|delete\\s+from)\\s+(public\\.)?"?' + t + '"?\\b', 'i');
  const hits = Object.entries(all).filter(([k, v]) => re.test(strip(v))).map(([k]) => k);
  console.log(t + ': ' + hits.length + ' writer fn(s): ' + hits.join(', '));
}
