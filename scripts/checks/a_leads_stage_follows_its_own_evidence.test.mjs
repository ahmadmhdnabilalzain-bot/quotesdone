// A lead's stage follows its own evidence (sales_engineer, 18 Nov 2026). Measured: Shine Carpets (leads 2936) invited, replied,
// registered and approved on 17 Nov still read lifecycle_stage 'not_contacted' and contacted false; 123 sent invitations read
// 'not_contacted'. The routine is read from its pending file and its rules are replayed on the measured rows.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const SQL = readFileSync(new URL('../sql/a_leads_stage_follows_its_own_evidence.sql', import.meta.url), 'utf8');
const BACKFILL = readFileSync(new URL('../sql/a_leads_stage_follows_its_own_evidence_backfill.sql', import.meta.url), 'utf8');
const fn = SQL.slice(SQL.indexOf('create or replace function public.fn_leads_stage_follows_its_evidence'), SQL.indexOf('end $fn$;'));

test('registration evidence is null-safe: an unset approval_status never makes the whole test null', () => {
  // measured while writing the backfill: claimed OR ... OR approval_status = 'approved' read NULL for 320 rows
  assert.match(fn, /coalesce\(new\.claimed, false\)/);
  assert.match(fn, /coalesce\(new\.approval_status, ''\) = 'approved'/);
  assert.doesNotMatch(fn, /or new\.approval_status = 'approved'/);
});

test('review of #2051: registered means the terms were taken; a page only claimed is claimed; the DDL carries a lock timeout', () => {
  assert.match(fn, /declare v_reg boolean := new\.accepted_terms_at is not null or new\.signed_terms_at is not null/);
  assert.doesNotMatch(fn.slice(fn.indexOf('declare v_reg'), fn.indexOf('v_stage text')), /claimed/);
  assert.equal(stage({ claimed: true, invite_status: 'sent', lifecycle_stage: 'not_contacted' }).lifecycle_stage, 'claimed');
  assert.match(SQL, /^set local lock_timeout = '1500ms';/m);
  assert.match(BACKFILL, /^set local lock_timeout = '1500ms';/m);
  // a reply counts only from the lead's own address (inbound_messages.lead_id may be a domain match)
  assert.match(BACKFILL, /lower\(btrim\(l\.email\)\)/);
});

test('the trigger fires on the fields its rules read, before the gates, and is revoked', () => {
  assert.match(SQL, /create trigger a20_leads_stage_follows_its_evidence\s+before insert or update of claimed, accepted_terms_at, signed_terms_at, registration_submitted_at, approval_status, invite_status, lifecycle_stage/);
  assert.match(SQL, /revoke execute on function public\.fn_leads_stage_follows_its_evidence\(\) from public, anon, authenticated/);
  assert.match(fn, /set search_path to 'public', 'pg_temp'/);
});

// the rules, as the function states them, replayed
function stage(r) {
  const reg = !!r.accepted_terms_at || !!r.signed_terms_at || !!r.registration_submitted_at || r.approval_status === 'approved';
  const s = r.lifecycle_stage || 'not_contacted', inv = r.invite_status || '';
  const sentish = ['sent', 'bounced', 'complained'].includes(inv);
  if (reg) return { lifecycle_stage: 'registered', contacted: sentish ? true : !!r.contacted };
  if (r.claimed) return { lifecycle_stage: 'claimed', contacted: sentish ? true : !!r.contacted };
  if (s === 'replied') return { lifecycle_stage: s, contacted: true };
  let n = s;
  if (['bounced', 'complained'].includes(inv) && ['not_contacted', 'contacted'].includes(s)) n = 'undeliverable';
  else if (inv === 'sent' && s === 'not_contacted') n = 'contacted';
  return { lifecycle_stage: n, contacted: sentish ? true : !!r.contacted };
}
test('replay: Shine Carpets as measured reads registered and contacted', () => {
  const shine = { invite_status: 'sent', lifecycle_stage: 'not_contacted', contacted: false, claimed: true, approval_status: 'approved',
    accepted_terms_at: '2026-11-17T08:38:12Z', signed_terms_at: '2026-11-17T08:38:14Z', registration_submitted_at: '2026-11-17T08:38:55Z' };
  assert.deepEqual(stage(shine), { lifecycle_stage: 'registered', contacted: true });
});
test('replay: sent -> contacted, bounced -> undeliverable, replied and no_response are kept, never back to not_contacted', () => {
  assert.equal(stage({ invite_status: 'sent', lifecycle_stage: 'not_contacted' }).lifecycle_stage, 'contacted');
  assert.equal(stage({ invite_status: 'bounced', lifecycle_stage: 'not_contacted' }).lifecycle_stage, 'undeliverable');
  assert.equal(stage({ invite_status: 'sent', lifecycle_stage: 'replied' }).lifecycle_stage, 'replied');
  assert.equal(stage({ invite_status: 'sent', lifecycle_stage: 'no_response' }).lifecycle_stage, 'no_response');
  assert.equal(stage({ invite_status: 'queued', lifecycle_stage: 'not_contacted' }).lifecycle_stage, 'not_contacted');
  assert.equal(stage({ invite_status: null, lifecycle_stage: null }).lifecycle_stage, 'not_contacted');
  for (const [k, v] of [['not_contacted', "v_stage = 'not_contacted'"], ['undeliverable', "new.lifecycle_stage := 'undeliverable'"], ['contacted', "new.lifecycle_stage := 'contacted'"]]) assert.ok(fn.includes(v), k);
});
test('the backfill is real rows only, proves Shine in the same transaction, and states its dry-run counts', () => {
  assert.match(BACKFILL, /not coalesce\(l\.is_demo, false\) and not public\.fn_is_demo_email\(l\.email\)/);
  assert.match(BACKFILL, /if \(select lifecycle_stage from public\.leads where id = 2936\) is distinct from 'registered'/);
  assert.match(BACKFILL, /DRY RUN \(18 Nov 2026, production, read-only, re-measured after review of #2051\): registered 3/);
  assert.doesNotMatch(BACKFILL, /^(begin|commit);/m);   // the applier's one transaction, so the proof rolls it all back
});
