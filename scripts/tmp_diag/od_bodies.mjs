import fs from 'node:fs';
const all = JSON.parse(fs.readFileSync(new URL('./allfns.json', import.meta.url)));
for (const fn of process.argv.slice(2)) {
  console.log('======== ' + fn + ' ========');
  console.log((all[fn] || '(missing)').trim());
}
