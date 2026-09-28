// A PROVIDER KEY THE ESTATE CAN ROTATE BY API IS ROTATED, AND EVERY ROTATION IS RECORDED.
//
// scripts/sql/a_provider_key_the_estate_can_rotate_by_api_is_rotated_and_recorded.sql, applied and driven through a whole
// rotation inside ONE transaction that ends in raise exception 'CHK<<...>>', so no key, row or claim is kept. The
// fake secret below is never a real one and never appears in the CHK payload. Fails when:
//   1. a provider never rotated is not due (28 Sep 2026: it_credential_rotation had 0 rows, ever);
//   2. the record does not put the new pair in app_secrets and a row in it_credential_rotation together;
//   3. a second claim inside the overlap is due (two rotations would stack);
//   4. the old key is offered for deletion before its overlap ends, or not after;
//   5. fn_it_credential_reverify touches a provider row.
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

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('claim -> record -> overlap -> retire, recorded, secret stored and never echoed', { skip: hasToken ? false : 'no management token' }, async () => {
  const body = `do $p$ declare o jsonb; v_id bigint; begin
      delete from public.it_credential_rotation where provider = 'twilio';
      delete from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'provider_rotation_claim';
      o := jsonb_build_object('first_claim', public.fn_it_provider_rotation_claim('twilio')->'due');
      v_id := public.fn_it_provider_rotation_record('twilio', 'SKchkold', 'SKchknew', 'chk-fake-secret');
      o := o || jsonb_build_object(
        'stored_sid', (select value = 'SKchknew' from public.app_secrets where key = 'twilio_api_key_sid'),
        'stored_secret', (select value = 'chk-fake-secret' from public.app_secrets where key = 'twilio_api_key_secret'),
        'row_status', (select status from public.it_credential_rotation where id = v_id),
        'second_claim', public.fn_it_provider_rotation_claim('twilio')->'due',
        'retire_early', (select count(*) from public.fn_it_provider_rotation_retire_due('twilio')));
      perform public.fn_it_credential_reverify();
      o := o || jsonb_build_object('after_reverify', (select status from public.it_credential_rotation where id = v_id));
      update public.it_credential_rotation set overlap_until = now() - interval '1 minute' where id = v_id;
      o := o || jsonb_build_object('retire_due', (select old_ref from public.fn_it_provider_rotation_retire_due('twilio') limit 1));
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
  assert.equal(r.first_claim, true, 'a provider never rotated is due');
  assert.equal(r.stored_sid, true); assert.equal(r.stored_secret, true);
  assert.equal(r.row_status, 'overlap');
  assert.equal(r.second_claim, false, 'no second rotation inside the overlap');
  assert.equal(r.retire_early, 0, 'the old key is not deleted before the overlap ends');
  assert.equal(r.after_reverify, 'overlap', 'reverify must leave a provider row alone');
  assert.equal(r.retire_due, 'SKchkold');
  assert.equal(r.closed, 'retired');
});
