// A LICENCE IS ASKED FOR AT 30 AND 7 DAYS AND PAUSED ON ITS EXPIRY DAY (founder ruling 1209). Assigned: sales_engineer.
// Offline: reads the SQL file the release operator applies at merge. Fails when:
//   1. the sweep asks at any threshold other than 30 and 7 days, or asks on/after the expiry day (the pause notice is
//      that day's one message);
//   2. the pause comes later than the expiry day, reads the UTC day instead of Dubai's, or lifts before a date AFTER today;
//   3. it_engineer's invariant reads a different day from the pause;
//   4. the ask stops being one English template row per lead, expiry, band and channel (the WhatsApp twin rides on it);
//   5. the aborted-transaction probe stops asserting the thresholds, the re-run and the pause.
//   node --test scripts/checks/a_licence_is_asked_for_at_30_and_7_days_and_paused_on_its_expiry_day.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const NAME = 'a_licence_is_asked_for_at_30_and_7_days_and_paused_on_its_expiry_day';
const SRC = readFileSync(join(REPO, `scripts/sql/${NAME}.sql`), 'utf8');
const PROBE = readFileSync(join(REPO, `scripts/sql/${NAME}_probe.sql`), 'utf8');
const code = (s) => s.split(/\r?\n/).map((l) => l.replace(/--.*$/, '')).join('\n');
const body = (name) => {
  const m = code(SRC).match(new RegExp(`function public\\.${name}\\([\\s\\S]*?\\$function\\$([\\s\\S]*?)\\$function\\$`, 'i'));
  assert.ok(m, `public.${name} is not defined in ${NAME}.sql`);
  return m[1];
};

test('the sweep asks at 30 and 7 days only, and never on or after the expiry day', () => {
  const b = body('fn_licence_expiry_sweep');
  assert.match(b, /v_band := case when v_days <= 7 then 't_minus_7' else 't_minus_30' end;/, 'the bands are not exactly 30 and 7');
  assert.doesNotMatch(b, /t_minus_14|'expired'/, 'a 14-day or expired ask came back');
  assert.match(b, /license_expiry >\s+\(now\(\) at time zone 'Asia\/Dubai'\)::date\s/, 'the sweep reaches the expiry day or past it');
  assert.match(b, /license_expiry <= \(now\(\) at time zone 'Asia\/Dubai'\)::date \+ 30/, 'the 30-day window moved');
  assert.match(b, /on conflict \(lead_id, expiry_date, band, channel\) do nothing/, 'an ask is no longer once per threshold');
  assert.match(b, /insert into public\.notifications \(type, kind, to_email, to_role[\s\S]*'licence_renewal', 'licence_expiry', r\.email, 'supplier'/,
    'the ask is no longer the supplier licence_renewal row trg_wa_fanout twins to the confirmed WhatsApp number');
  assert.doesNotMatch(b, /[؀-ۿ]/, 'suppliers are written in English');
});

test('the pause is the Dubai expiry day and lifts only on a later date', () => {
  const b = body('fn_reconcile_doc_blocks');
  assert.match(b, /v_cut date := \(now\(\) at time zone 'Asia\/Dubai'\)::date - p_grace_days;/, 'the pause reads the UTC day');
  assert.match(b, /license_expiry is not null and license_expiry <= v_cut/, 'the licence pause comes after the expiry day');
  assert.match(b, /\(license_expiry is null or license_expiry > v_cut\)/, 'the licence block lifts on the expiry day itself');
  assert.doesNotMatch(b, /license_expiry < v_cut|license_expiry >= v_cut/, 'an off-by-one day came back');
  const w = body('fn_it_engineer_licence_expiry_watch');
  assert.match(w, /l\.license_expiry <= v_today/, "it_engineer's invariant reads a different day from the pause");
  assert.doesNotMatch(w, /license_expiry < v_today/);
});

test('the duty stays the sales engineer\'s, and the probe aborts its transaction', () => {
  assert.match(SRC, /where duty = 'sales_engineer\.licence_expiry_watch';/);
  assert.match(PROBE, /raise exception 'CHK<<%>>'/);
  for (const s of ["band in ('t_minus_14', 'expired')", 'n1 <> 3 or n2 <> 3', "matching_block_reason = 'licence_expired'", 'v_today + 365']) {
    assert.ok(PROBE.includes(s), `the probe no longer asserts ${s}`);
  }
  assert.doesNotMatch(code(PROBE), /insert into public\.leads[^;]*@(?!example\.invalid)[a-z]/i, 'the probe writes a supplier on a real address');
});
