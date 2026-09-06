import { readFileSync, writeFileSync } from 'node:fs';
const p = 'scripts/phase_d/prove_object_reference_round_trip.mjs';
let s = readFileSync(p, 'utf8');
const rep = (o, n) => { const c = s.split(o).length - 1; if (c !== 1) throw new Error(`anchor ${c}: ${o.slice(0, 60)}`); s = s.replace(o, n); };

rep(`const rows = strategy.map((s, i) => {
  const v = verdictAt(i);
  return [s.object_id, s.storage_kind, s.canonical_identity_type, s.physical_relation,
    s.physical_pk_column, decode(v), flag(v, 'O'), flag(v, 'I'), flag(v, 'V')];
});`,
`const rows = strategy.map((s, i) => {
  const v = verdictAt(i);
  // An object the stage arm could not create, and the intent arm did, carries the intent arm's
  // verdict under its own name. The stage arm's 'N' is left in place for anything the intent arm
  // did not settle, so an unproved object is never silently upgraded.
  const iv = intentVerdict.get(s.object_id);
  if (iv && v[0] === 'N') {
    return [s.object_id, s.storage_kind, s.canonical_identity_type, s.physical_relation,
      s.physical_pk_column,
      iv.ok ? 'ROUND_TRIPPED_AS_EXTERNAL_EFFECT_INTENT' : 'INTENT_ARM_FAILED',
      iv.ok ? 'true' : 'false', iv.ok ? 'true' : 'false', iv.ok ? 'true' : 'false'];
  }
  return [s.object_id, s.storage_kind, s.canonical_identity_type, s.physical_relation,
    s.physical_pk_column, decode(v), flag(v, 'O'), flag(v, 'I'), flag(v, 'V')];
});`);

rep(`const tripped = rows.filter((r) => r[5] === 'ROUND_TRIPPED').length;`,
`const tripped = rows.filter((r) => r[5] === 'ROUND_TRIPPED').length;
const trippedIntent = rows.filter((r) => r[5] === 'ROUND_TRIPPED_AS_EXTERNAL_EFFECT_INTENT').length;
const intentFailed = rows.filter((r) => r[5] === 'INTENT_ARM_FAILED');`);

rep('  numerator: tripped,', '  numerator: tripped + trippedIntent,');

rep(`  of: 'frozen business objects create/resolve round-tripped through the canonical reference',`,
'  of: `frozen business objects have a proved creation path: ${tripped} round-tripped through a '
+ 'canonical relation row and ${trippedIntent} through the declared external-effect intent that is '
+ 'the whole of Phase D’s creation contract for it`,');

rep('console.log(`  round-tripped            ${tripped}`);',
'console.log(`  round-tripped            ${tripped}`);\n'
+ 'console.log(`  round-tripped as intent  ${trippedIntent}   (an object whose Phase D creation IS an external-effect intent)`);');

rep('if (refused.length) fatal.push(`${refused.length} references could not be resolved at all`);',
'if (refused.length) fatal.push(`${refused.length} references could not be resolved at all`);\n'
+ 'if (intentFailed.length) fatal.push(`${intentFailed.length} object(s) whose only creation path is an external-effect intent did not produce or resolve one`);');

writeFileSync(p, s);
console.log('patched');
