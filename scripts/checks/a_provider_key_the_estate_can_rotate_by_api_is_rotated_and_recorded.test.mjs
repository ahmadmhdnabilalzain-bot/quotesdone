// A PROVIDER KEY THE ESTATE CAN ROTATE BY API IS ROTATED, AND EVERY ROTATION IS RECORDED.
//
// scripts/sql/a_provider_key_the_estate_can_rotate_by_api_is_rotated_and_recorded.sql, applied and driven through a whole
// rotation inside ONE transaction that ends in raise exception 'CHK<<...>>', so no key, row or claim is kept. The
// fake secret below is never a real one and never appears in the CHK payload. Fails when:
//   1. a provider with no row is due (review of #1038: the live Twilio key would have rotated on the first tick
//      after apply, whatever its age) - it must answer baseline_needed instead;
//   2. the schedule does not count from the baseline (the current key's creation date at the provider): created
//      10 days ago is not due, created 91 days ago is;
//   3. the record does not put the new pair in app_secrets and a row in it_credential_rotation together;
//   4. the overlap is under 24 hours, even with credential_overlap_hours set to 1;
//   5. a second claim inside the overlap is due (two rotations would stack);
//   6. the old key is offered for deletion before its overlap ends, or not after;
//   7. fn_it_credential_reverify touches a provider row.
// Plus, from source: kyc, which caches the Twilio pair for a minute, re-reads it on a Twilio 401.
//
//   node --test scripts/checks/a_provider_key_the_estate_can_rotate_by_api_is_rotated_and_recorded.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const ddl = readFileSync(join(REPO, 'scripts/sql/a_provider_key_the_estate_can_rotate_by_api_is_rotated_and_recorded.sql'), 'utf8')
  .split('\n-- ── VERDICT')[0];

test('kyc drops its cached Twilio pair and retries once on a 401', () => {
  const kyc = readFileSync(join(REPO, 'supabase/functions/kyc/index.ts'), 'utf8');
  assert.match(kyc, /if \(r\.status === 401\) \{\s*for \(const k of TW_KEYS\) _sec\.delete\(k\);/);
  assert.match(kyc, /verifySend[\s\S]*?twilioVerifyPost\(tw, 'Verifications'/);
  assert.match(kyc, /verifyCheck[\s\S]*?twilioVerifyPost\(tw, 'VerificationCheck'/);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('baseline -> on schedule -> record -> 24 h overlap -> retire, recorded, secret stored and never echoed', { skip: hasToken ? false : 'no management token' }, async () => {
  const body = `do $p$ declare o jsonb; v_id bigint; v_base bigint; begin
      delete from public.it_credential_rotation where provider = 'twilio';
      delete from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'provider_rotation_claim';
      o := jsonb_build_object('no_row_claim', public.fn_it_provider_rotation_claim('twilio'));
      v_base := public.fn_it_provider_rotation_baseline('twilio', 'SKchkold', now() - interval '10 days');
      o := o || jsonb_build_object(
        'baseline_status', (select status from public.it_credential_rotation where id = v_base),
        'second_baseline', public.fn_it_provider_rotation_baseline('twilio', 'SKother', now() - interval '400 days'),
        'young_key_claim', public.fn_it_provider_rotation_claim('twilio')->'due');
      update public.it_credential_rotation set rotated_at = now() - interval '91 days' where id = v_base;
      o := o || jsonb_build_object('old_key_claim', public.fn_it_provider_rotation_claim('twilio')->'due');
      update public.it_threshold set value = 1 where key = 'credential_overlap_hours';
      v_id := public.fn_it_provider_rotation_record('twilio', 'SKchkold', 'SKchknew', 'chk-fake-secret');
      o := o || jsonb_build_object(
        'stored_sid', (select value = 'SKchknew' from public.app_secrets where key = 'twilio_api_key_sid'),
        'stored_secret', (select value = 'chk-fake-secret' from public.app_secrets where key = 'twilio_api_key_secret'),
        'row_status', (select status from public.it_credential_rotation where id = v_id),
        'overlap_hours', (select round(extract(epoch from overlap_until - rotated_at) / 3600) from public.it_credential_rotation where id = v_id),
        'second_claim', public.fn_it_provider_rotation_claim('twilio')->'due',
        'retire_early', (select count(*) from public.fn_it_provider_rotation_retire_due('twilio')));
      perform public.fn_it_credential_reverify();
      o := o || jsonb_build_object('after_reverify', (select status from public.it_credential_rotation where id = v_id));
      update public.it_credential_rotation set overlap_until = now() - interval '1 minute' where id = v_id;
      o := o || jsonb_build_object('retire_due', (select jsonb_agg(old_ref) from public.fn_it_provider_rotation_retire_due('twilio')));
      perform public.fn_it_provider_rotation_retired(v_id, 'chk');
      o := o || jsonb_build_object('closed', (select status from public.it_credential_rotation where id = v_id));
      raise exception 'CHK<<%>>', o;
    end $p$;`;
  let r;
  try { await sql('begin;\n' + ddl + '\n' + body); } catch (e) {
    const msg = String(e.message);
    const m = msg.match(/CHK<<(.*?)>>/s);
    if (!m) throw e;
    assert.ok(!msg.includes('chk-fake-secret'), 'the secret must never come back out');
    r = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(r, 'the probe must end in CHK');
  assert.equal(r.no_row_claim.due, false, 'a provider with no row is not due');
  assert.equal(r.no_row_claim.baseline_needed, true, 'a provider with no row asks for its baseline');
  assert.equal(r.baseline_status, 'baseline');
  assert.equal(r.second_baseline, null, 'a baseline is written once');
  assert.equal(r.young_key_claim, false, 'a key created 10 days ago is not due');
  assert.equal(r.old_key_claim, true, 'a key created 91 days ago is due');
  assert.equal(r.stored_sid, true); assert.equal(r.stored_secret, true);
  assert.equal(r.row_status, 'overlap');
  assert.ok(Number(r.overlap_hours) >= 24, `the old key is kept at least 24 h (got ${r.overlap_hours} h with the threshold at 1 h)`);
  assert.equal(r.second_claim, false, 'no second rotation inside the overlap');
  assert.equal(r.retire_early, 0, 'the old key is not deleted before the overlap ends');
  assert.equal(r.after_reverify, 'overlap', 'reverify must leave a provider row alone');
  assert.deepEqual(r.retire_due, ['SKchkold'], 'only the rotated-away key is offered for deletion, never the baseline');
  assert.equal(r.closed, 'retired');
});
