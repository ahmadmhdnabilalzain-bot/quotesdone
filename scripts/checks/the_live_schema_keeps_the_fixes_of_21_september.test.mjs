// THE LIVE SCHEMA KEEPS THE DATABASE FIXES OF 21 SEPTEMBER 2026.
//
// Founder, 21 Sep 2026 (instruction 573): "i dont want things to pop up again for the same reasons".
// Each fix below was proved once, by a probe, at apply time. A probe runs once; this runs on every
// `node scripts/checks/run.mjs`. It reads supabase/schema/full_schema/ — the mirror of production
// that export_from_either_source_is_identical.mjs keeps equal to the live database on every pull
// request — so re-applying an old body cannot pass CI without this test seeing it.
// Index: docs/it/RECURRENCE_GUARDS_21_SEP_2026.md.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const SCHEMA = readSchemaMirror();
const noComments = (s) => s.replace(/--[^\n]*/g, '');
const body = (name) => {
  const at = SCHEMA.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert.ok(at >= 0, `public.${name} is not in the schema mirror — this check has lost its subject`);
  const end = SCHEMA.indexOf('\nCREATE ', at + 10);
  return noComments(SCHEMA.slice(at, end < 0 ? undefined : end));
};

test('#761 a stars-only rating is accepted: no CHECK on public.reviews demands a comment', () => {
  // 17 Sep: every star press was HTTP 500 (23514 reviews_reason_required); reviews held 0 rows ever.
  const checks = [...SCHEMA.matchAll(/^ALTER TABLE public\.reviews ADD CONSTRAINT (\S+) CHECK (.*)$/gm)];
  assert.ok(checks.length > 0, 'no CHECK on public.reviews in the mirror — this check has lost its subject');
  for (const [, name, expr] of checks.filter(([, , e]) => /\bcomment\b/.test(e))) {
    assert.match(expr, /\(comment IS NULL\) OR/, `${name} refuses a rating with no comment: ${expr}`);
    assert.doesNotMatch(expr, /NOT VALID/, `${name} is NOT VALID — an unvalidated constraint is one nobody proved`);
  }
});

test('#776 an org_task back-off earned under an older consumer version does not bind the current one', () => {
  // 21 Sep: the first v2 tick scanned 0 of 8 assigned rows — all inside a 4h/16h window earned from a
  // v1 "not_yet". The picker must name the SAME version the consumer writes into result.consumer.
  const b = body('fn_org_task_consume_tick');
  const picker = b.match(/->'consumer'->>'version', ''\) <> '(v\d+)'/);
  assert.ok(picker, 'the batch picker no longer exempts rows whose back-off came from an older consumer version');
  const written = [...new Set([...b.matchAll(/'version', '(v\d+)'/g)].map((m) => m[1]))];
  assert.deepEqual(written, [picker[1]], `the consumer writes version ${written.join(',')} but the picker exempts rows not on ${picker[1]}`);
});

test('#776 every org_task class that was re-asked for ever has a deterministic end', () => {
  // 11 assigned rows sat for ever: knowledge_gap closed only when knowledge already existed, and
  // routine_operational_decision had no handler for supplier_registered or sales_rating.
  const b = body('fn_org_task_consume_tick');
  assert.match(b, /'outcome', 'tracked_gap'/, 'a real knowledge gap no longer closes as a tracked gap');
  assert.match(b, /'supplier_registered' then/, 'the supplier_registered decider is gone');
  assert.match(b, /r\.result \? 'sales_rating' then/, 'the sales_rating decider is gone');
});

test('#776 PITR-off is held once as the founder\'s decision, not re-filed as a defect every run', () => {
  const b = body('fn_it_platform_ingest');
  assert.match(b, /'supabase_pitr_addon:declined', 'supabase_pitr_addon:approved'/, 'the PITR finding no longer reads the founder\'s decision');
});

test('#760 every change-tracked table also records a TRUNCATE', () => {
  // A TRUNCATE fires no row trigger; without the statement trigger an incremental day restores
  // every truncated row.
  const tracked = new Map();
  for (const [, events, table] of SCHEMA.matchAll(/^CREATE TRIGGER \S+ AFTER ([A-Z ]+?) ON public\.(\w+) .*trg_table_export_change\(/gm)) {
    tracked.set(table, (tracked.get(table) || '') + ' ' + events);
  }
  assert.ok(tracked.size > 0, 'no change-tracking triggers in the mirror — this check has lost its subject');
  for (const [t, ev] of tracked) {
    for (const e of ['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) assert.match(ev, new RegExp(`\\b${e}\\b`), `${t} is change-tracked without ${e}`);
  }
});

test('#760 the incremental export never casts the table key (524 on kb_chunks)', () => {
  // 18 Sep: `t.id::text in (select row_key ...)` made the primary-key index unusable and outlived the
  // management API gateway. The cast belongs on row_key.
  const b = body('fn_table_export_page');
  assert.match(b, /t\.%I in \(select cl\.row_key::%s from public\.table_export_change/, 'the key-typed row_key predicate is gone');
  assert.doesNotMatch(b, /t\.%I::text in \(/, 'the table key is cast to text again — a sequential scan of kb_chunks every page');
});
