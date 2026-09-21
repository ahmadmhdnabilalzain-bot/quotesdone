// NO ROUTINE NAMES A TABLE ALIAS AFTER ITS OWN RECORD VARIABLE.
//
// 21 Sep 2026, found by it_failures_of_18_to_21_september_do_not_recur.test.mjs against production:
// fn_it_backup_recheck declares `d public.doc_backups` and then runs `update public.doc_backups d ...
// where d.entity = 'transaction'`. PL/pgSQL cannot tell the record field from the column
// (42702 "column reference d.entity is ambiguous"), so the routine fails on EVERY call — and with it
// the CEO's backup-coverage decider that calls it. The same shape stopped nine scheduled IT duties on
// 15-18 Sep. It compiles, it applies, and it dies only when it runs, so only a reading of the body
// catches it before a caller does.
//
// Reads supabase/schema/full_schema.sql (the live mirror, kept equal to production on every PR).
// A record-typed variable is `record`, `%rowtype` or a `schema.table` row type; an alias is the word
// after a table in FROM / JOIN / UPDATE / INTO / DELETE FROM. A match is a routine that WILL raise
// 42702 the moment that statement touches `alias.column`.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const SCHEMA = readFileSync(new URL('../../supabase/schema/full_schema.sql', import.meta.url), 'utf8');
const SQL_WORDS = new Set(['where', 'set', 'on', 'join', 'left', 'right', 'inner', 'cross', 'using', 'order', 'group',
  'limit', 'returning', 'values', 'select', 'for', 'and', 'or', 'as', 'with', 'union', 'having', 'lateral', 'natural',
  'full', 'outer', 'into', 'then', 'loop', 'end', 'offset', 'window', 'except', 'intersect', 'default', 'from', 'do']);

export function shadowedAliases(fnBody) {
  const code = fnBody.replace(/--[^\n]*/g, '');
  const decl = (code.match(/\bdeclare\b([\s\S]*?)\bbegin\b/i) || [])[1] || '';
  const records = new Set();
  for (const [, name, type] of decl.matchAll(/(?:^|[;\s])([a-z_]\w*)\s+([a-z_][\w.]*(?:%rowtype)?)\s*(?::=[^;]*)?;/gi)) {
    if (/^record$|%rowtype$|^public\.\w+$/i.test(type)) records.add(name.toLowerCase());
  }
  const out = new Set();
  const body = code.slice(code.search(/\bbegin\b/i));
  for (const [, alias] of body.matchAll(/\b(?:from|join|update|into|delete\s+from)\s+(?:only\s+)?(?:public\.)?[a-z_]\w*\s+(?:as\s+)?([a-z_]\w*)\b/gi)) {
    const a = alias.toLowerCase();
    if (!SQL_WORDS.has(a) && records.has(a) && new RegExp(`\\b${a}\\.[a-z_]`, 'i').test(body)) out.add(a);
  }
  return [...out];
}

test('the shape is recognised: a record d and `update public.doc_backups d ... d.entity`', () => {
  const bad = `declare h public.agent_actions; d public.doc_backups; begin
    update public.doc_backups d set status = 'x' where d.entity = 'transaction'; end`;
  assert.deepEqual(shadowedAliases(bad), ['d']);
  assert.deepEqual(shadowedAliases(bad.replace('doc_backups d set', 'doc_backups b set').replace('d.entity', 'b.entity')), []);
});

test('no plpgsql routine in the live schema aliases a table with the name of its own record variable', () => {
  const found = [];
  const chunks = SCHEMA.split('CREATE OR REPLACE FUNCTION public.').slice(1);
  assert.ok(chunks.length > 500, `read only ${chunks.length} routines — the split is wrong, not the schema`);
  for (const c of chunks) {
    const head = c.slice(0, c.indexOf('$function$'));
    if (!/LANGUAGE plpgsql/.test(head)) continue;
    const s = shadowedAliases(c.slice(head.length, c.indexOf('$function$', head.length + 10)));
    if (s.length) found.push(`${c.slice(0, c.indexOf('('))}: ${s.join(', ')}`);
  }
  assert.deepEqual(found, [], 'each of these raises 42702 "column reference is ambiguous" when the statement runs; rename the alias');
});
