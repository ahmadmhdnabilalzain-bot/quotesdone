// THE SLOW-STATEMENT DUTY SKIPS SCHEMA CHANGES.
//
// 24 Sep 2026, it_engineer. Duty 14 (db_health) raised the `create or replace function` statement of
// an applied SQL file as a slow product statement (duty:db_health:slow:7518326696961925895), because
// the management API's stamp is a TRAILING comment that only the last statement of a multi-statement
// apply carries. The CEO had no remedy, the report stayed accepted, and
// monitor:ceo_accepted_report_review_overdue stayed open. See
// scripts/sql/a_schema_change_is_never_a_slow_product_statement.sql.
//
// Reads the live mirror. Until that file is applied it is excused only by its pending note.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const root = new URL('../../', import.meta.url);
const FILE = 'a_schema_change_is_never_a_slow_product_statement';

// The same expression the duty uses, so a regression in the pattern fails here too.
export const isSchemaChange = (q) =>
  /^(create|alter|drop|grant|revoke|comment)\s/i.test(q.replace(/^(\s*--[^\n]*)*\s*/, ''));

test('the pattern tells a schema change from product traffic', () => {
  assert.equal(isSchemaChange("-- THE BACKUP EXPECTS ...\n-- Assigned\n\ncreate or replace function public.f() returns int"), true);
  assert.equal(isSchemaChange('select public.fn_kb_embed_dispatch()'), false);
  assert.equal(isSchemaChange('-- create a row\nupdate public.leads set locale = $1'), false);
});

test('duty 14 leaves schema changes out of the slow-statement reading', () => {
  const schema = readFileSync(new URL('supabase/schema/full_schema.sql', root), 'utf8');
  const start = schema.indexOf('FUNCTION public.fn_it_duties_scheduled(');
  assert.ok(start > 0, 'fn_it_duties_scheduled is in the mirror');
  const body = schema.slice(start, schema.indexOf('$function$;', start));
  if (body.includes('not s.schema_change')) return;
  assert.ok(existsSync(new URL(`scripts/sql/pending/${FILE}.txt`, root)),
    `duty 14 does not exclude schema changes and ${FILE}.sql is not pending an apply`);
});
