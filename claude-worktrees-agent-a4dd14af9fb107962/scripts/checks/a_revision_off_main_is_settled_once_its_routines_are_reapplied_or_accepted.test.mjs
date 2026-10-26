// A revision applied from off main stops being raised once every change it made is settled (22 Sep 2026, it_engineer).
//
// WHY THIS EXISTS. duty:unsigned_revision:rev:14ad86a named four routines whose live bodies equal main's
// canonical files (canonical_routine_manifest, 0 drift, sha256 per routine), yet fn_it_change_watch
// raised it on every tick with no way to settle it: closing it by hand lasted until fn_it_duty_settle
// upserted it open 15 minutes later. The settled rule lives in
// scripts/sql/a_revision_off_main_is_settled_once_its_routines_are_reapplied_or_accepted.sql and was
// proved on production in a rolled-back transaction both ways (accepted: the finding closed; not
// accepted: it stayed open with two of four routines re-applied). This fails if the rule is dropped
// from the canonical body, or if it would settle a revision on the strength of only SOME routines.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const SQL = readFileSync(join(ROOT, 'scripts/sql/a_revision_off_main_is_settled_once_its_routines_are_reapplied_or_accepted.sql'), 'utf8');
const body = SQL.slice(SQL.indexOf('create or replace function public.fn_it_change_watch()'), SQL.indexOf('revoke execute on function public.fn_it_change_watch()'));

test('the revision loop skips a revision only when NO change of it is unsettled', () => {
  const rule = body.slice(body.indexOf('-- SETTLED:'), body.indexOf('v_items := v_items'));
  assert.ok(rule.length > 0, 'the settled rule is gone from fn_it_change_watch');
  assert.match(rule, /continue when exists[\s\S]*and not exists \(/, 'must require the revision to have changes AND none unsettled');
  assert.match(rule, /it_change_acceptance a where a\.txid = c\.txid/, 'an accepted transaction settles its changes');
  assert.match(rule, /s\.object_identity = c\.object_identity and s\.at > c\.at[\s\S]*'on_main', 'merged_pr'/, 'a later re-apply from a reviewed revision settles a change');
});

test('the routine keeps its pinned search_path and its revoke', () => {
  assert.match(body, /security definer set search_path to 'public', 'pg_temp'/);
  assert.match(SQL, /revoke execute on function public\.fn_it_change_watch\(\) from public, anon, authenticated;/);
});
