// THE SCHEMA EXPORT SORTS ON A UNIQUE KEY (27 Oct 2026; seat: it_engineer).
//
// On 27 Oct, from about 10:55Z, export_from_either_source_is_identical failed on every branch with 16 differing
// lines. Every one was in the ORDER of triggers that share a table, and no trigger had changed.
// fn_schema_export sorted the TRIGGERS section on the table name alone. A catalog rewrite (#1630's revoke)
// therefore reshuffled triggers within a table, and the gate reported drift that did not exist.
// FUNCTIONS had the same latent tie between overloads. The fix is
// scripts/sql/the_schema_export_sorts_triggers_and_overloads_on_a_unique_key.sql.
//
// This reads the committed mirror (kept equal to production by the export check), so it runs offline:
//   1. the live export's own body breaks both ties with a unique key;
//   2. the TRIGGERS section the mirror holds is actually in (table, trigger name) order.
// With the old body or a heap-ordered mirror, both tests fail.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const SCHEMA = readSchemaMirror();

function exportBody() {
  const start = SCHEMA.indexOf('CREATE OR REPLACE FUNCTION public.fn_schema_export()');
  assert.ok(start >= 0, 'fn_schema_export is not in the schema mirror');
  const open = SCHEMA.indexOf('$function$', start);
  const close = SCHEMA.indexOf('$function$', open + 1);
  return SCHEMA.slice(open, close);
}

test('fn_schema_export breaks the trigger and overload ties with a unique key', () => {
  const body = exportBody();
  assert.match(body, /order by c\.relname, tg\.tgname\) from pg_trigger/,
    'TRIGGERS must sort by (table, trigger name); the table name alone is not unique per trigger');
  assert.match(body, /order by p\.proname, pg_get_function_identity_arguments\(p\.oid\)\) from pg_proc/,
    'FUNCTIONS must sort by (name, identity arguments); the name alone does not separate overloads');
});

test('the mirrored TRIGGERS section is in (table, trigger name) order', () => {
  // Anchored on whole lines: the export's own body (in FUNCTIONS) quotes these headers as string literals.
  const from = SCHEMA.indexOf('\n-- ===== TRIGGERS =====\n');
  const to = SCHEMA.indexOf('\n-- ===== ROW LEVEL SECURITY', from);
  assert.ok(from >= 0 && to > from, 'TRIGGERS section not found in the mirror');
  const keys = SCHEMA.slice(from, to).split('\n')
    .map((l) => l.match(/^CREATE (?:CONSTRAINT )?TRIGGER (\S+) .*? ON public\.(\S+) /))
    .filter(Boolean)
    .map((m) => [m[2].replace(/"/g, ''), m[1].replace(/"/g, '')]);
  assert.ok(keys.length > 100, `only ${keys.length} triggers parsed; the pattern no longer matches the export`);
  // Postgres sorts the `name` type bytewise (C collation); JS compares UTF-16 code units, which agrees for ASCII.
  const cmp = (a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : 0);
  const out = [];
  for (let i = 1; i < keys.length; i++) if (cmp(keys[i - 1], keys[i]) > 0) out.push(`${keys[i - 1].join('.')} before ${keys[i].join('.')}`);
  assert.deepEqual(out.slice(0, 10), [], `${out.length} trigger(s) out of (table, name) order`);
});
