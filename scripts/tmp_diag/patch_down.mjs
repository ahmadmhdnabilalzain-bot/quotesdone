import { readFileSync, writeFileSync, existsSync } from 'node:fs';
const p = 'scripts/phase_d/build_missing_down_scripts.mjs';
let s = readFileSync(p, 'utf8');
const rep = (o, n) => { const c = s.split(o).length - 1; if (c !== 1) throw new Error(`anchor ${c}: ${o.slice(0, 60)}`); s = s.replace(o, n); };

rep(`import { FILES, classify } from './build_migration_rollback_classification.mjs';`,
`import { FILES, classify, introducedBy } from './build_migration_rollback_classification.mjs';`);

rep(`  const rev = reversals(readFileSync(\`\${DIR}/\${r.file}\`, 'utf8'));`,
`  const rev = reversals(readFileSync(\`\${DIR}/\${r.file}\`, 'utf8'));
  // A routine no other Phase D file defines was INTRODUCED here, and dropping it is the only
  // reversal there is — re-applying a predecessor cannot restore what had none.
  for (const fn of introducedBy(r.file)) {
    rev.push({ what: \`routine \${fn.name}(\${fn.args}) — introduced by this file\`,
               down: \`drop function if exists \${fn.name}(\${fn.args});\` });
  }`);

rep(`  const firstTable = (dropable.find(x => x.what.startsWith('table ')) || {}).what;
  const guardOn = firstTable ? firstTable.slice(6)
    : (dropable[0].down.match(/on ([a-z0-9_.]+);/) || dropable[0].down.match(/alter table ([a-z0-9_.]+)/) || [])[1];`,
`  const firstTable = (dropable.find(x => x.what.startsWith('table ')) || {}).what;
  const guardOn = firstTable ? firstTable.slice(6)
    : (dropable.map(x => x.down.match(/on ([a-z0-9_.]+);/) || x.down.match(/alter table ([a-z0-9_.]+)/))
        .find(Boolean) || [])[1];`);

rep(`do $pre$
begin
  if to_regclass('\${guardOn}') is null then
    raise exception '\${stem} down: \${guardOn} does not exist; there is nothing here to revert.';
  end if;
end $pre$;`,
`\${guardOn ? \`do $pre$
begin
  if to_regclass('\${guardOn}') is null then
    raise exception '\${stem} down: \${guardOn} does not exist; there is nothing here to revert.';
  end if;
end $pre$;\` : '-- Nothing to guard on: this file introduced routines and created no relation.'}`);

writeFileSync(p, s);
console.log('patched');
