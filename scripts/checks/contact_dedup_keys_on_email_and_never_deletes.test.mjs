// CONTACT DEDUP KEYS ON EMAIL, NEVER DELETES, AND MERGES REAL ROWS ONLY ON REVIEW (it_engineer, 5 Oct 2026, backlog T4).
//
// WHAT FAILS IF THE CAUSE RETURNS:
//   * a group is formed from a phone (a phone may confirm, never select);
//   * the merge deletes a row instead of marking it merged_into;
//   * the FKs to re-point are a hand-written list instead of read from pg_constraint;
//   * a merge runs without a live reviewer seat and a reason, or the detector approves a real group;
//   * a customer and a supplier can be merged into each other;
//   * the audit loses before/after/repointed or becomes editable;
//   * production, in ONE aborted transaction: the _probe.sql answers PROBE OK (see the pending note).
//
//   node --test scripts/checks/contact_dedup_keys_on_email_and_never_deletes.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const src = readFileSync(join(REPO, 'scripts/sql/the_it_engineer_finds_duplicate_contacts_by_email_and_merges_only_reviewed_or_demo_ones.sql'), 'utf8');
const body = (name) => src.slice(src.indexOf(`function public.${name}(`), src.indexOf('$fn$;', src.indexOf(`function public.${name}(`)));
const members = body('fn_contact_identity_members');
const merge = body('fn_contact_merge');
const duty = body('fn_it_engineer_contact_dedup');

test('identity is lower(btrim(email)); phone only confirms', () => {
  assert.match(members, /lower\(btrim\(v\.addr\)\) = p_key/);
  assert.match(members, /lower\(btrim\(c\.email\)\) = p_key/);
  assert.doesNotMatch(members, /phone_key\s*=\s*p_key|phone[^\n]*= p_key/);
  assert.match(duty, /keys as \(select k from ids group by k having count\(\*\) > 1\)/);
  assert.doesNotMatch(duty.slice(duty.indexOf('with ids'), duty.indexOf('), keys')), /phone/);
});

test('nothing is deleted; the loser is marked merged_into', () => {
  assert.doesNotMatch(src, /\bdelete\s+from\b/i);
  assert.match(merge, /set merged_into = v_winner::bigint, merged_at = now\(\), matching_blocked = true/);
  assert.match(merge, /set merged_into = v_winner::uuid, merged_at = now\(\)/);
});

test('every FK is enumerated from the catalogue at merge time', () => {
  assert.match(merge, /from pg_constraint c/);
  assert.match(merge, /c\.contype = 'f' and c\.confrelid = v_tbl/);
});

test('a merge needs a live seat and a reason; the detector never approves a real group; kinds never cross', () => {
  assert.match(merge, /length\(btrim\(coalesce\(p_reason, ''\)\)\) < 10/);
  assert.match(merge, /from public\.org_role where role_id = p_reviewed_by_seat and status = 'active'/);
  assert.match(merge, /not g\.all_demo and p_reviewed_by_seat = 'it_engineer'/);
  assert.match(merge, /cardinality\(g\.kinds\) <> 1/);
});

test('the duty merges demo only and hands real groups to sales_engineer', () => {
  assert.match(duty, /if g\.all_demo and cardinality\(g\.kinds\) = 1 then/);
  assert.match(duty, /'owner_seat', 'sales_engineer'/);
  assert.match(duty, /fn_it_duty_settle\('contact_dedup', v_items\)/);
  assert.doesNotMatch(duty, /fn_reason_hold|think\(/);
  assert.match(src, /'it_engineer\.contact_dedup', 'it_engineer', '1 day', 'fn_it_engineer_contact_dedup'/);
});

test('the audit is append-only with before, after and every re-pointed FK; everything is service-role only', () => {
  assert.match(src, /before_row\s+jsonb not null/);
  assert.match(src, /after_row\s+jsonb not null/);
  assert.match(src, /repointed\s+jsonb not null/);
  assert.match(src, /before update or delete on public\.contact_merge_audit/);
  for (const sig of ['fn_contact_merge(uuid, text, text)', 'fn_it_engineer_contact_dedup()', 'fn_contact_identity_members(text)']) {
    assert.ok(src.includes(`revoke execute on function public.${sig} from public, anon, authenticated;`), sig);
  }
  for (const t of ['contact_duplicate_group', 'contact_merge_audit']) {
    assert.ok(src.includes(`revoke all on public.${t} from anon, authenticated;`), t);
    assert.ok(src.includes(`alter table public.${t} enable row level security;`), t);
  }
});
