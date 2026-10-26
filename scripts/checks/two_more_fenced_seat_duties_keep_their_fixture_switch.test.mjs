// TWO MORE FENCED SEAT DUTIES KEEP THEIR FIXTURE SWITCH (18 Oct 2026; it_engineer).
//
// #1348 (founder ruling 1199) fenced fn_sales_engineer_comparison_kpi and fn_support_case_idle_close from demo rows
// with no fixture switch, so no ZZ DEMO probe could prove either one.
// two_more_fenced_seat_duties_keep_their_fixture_switch.sql gives them qd.duty_fixtures. WHAT FAILS IF THE CAUSE
// RETURNS -- production, ONE aborted transaction (the pending file replayed first; ZZ DEMO and @example.invalid only;
// every write rolls back), for each duty:
//   (a) a demo fixture the duty should act on is built inside the transaction;
//   (b) with qd.duty_fixtures 'on' the duty acts on it (the KPI counts it; the idle case is closed);
//   (c) with the switch off the duty ignores it;
//   (d) the fixture run touches no real row (real rows fingerprinted before and after).
//
//   node --test scripts/checks/two_more_fenced_seat_duties_keep_their_fixture_switch.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILES = ['scripts/sql/two_more_fenced_seat_duties_keep_their_fixture_switch.sql'];
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));

test('the file fences both duties with the switch and leaves no bare demo exclusion', () => {
  const s = read(FILES[0]).replace(/--[^\n]*/g, '');
  assert.match(s, /fn_inquiry_is_demo\(di\.id\)\)\s*= \(coalesce\(current_setting\('qd\.duty_fixtures', true\), ''\) = 'on'\)/);
  assert.match(s, /fn_party_is_demo\(party_kind, party_id\) = v_fx;/);
  assert.doesNotMatch(s, /\bnot (exists \(select 1 from public\.inquiries di|public\.fn_party_is_demo)/);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token';

async function probe(block) {
  try { await replaySql(FILES.filter(pending).map(read).join('\n') + '\n' + block, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    return JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.fail('the probe committed instead of rolling back');
}

// a fingerprint of every REAL row the duty could read or write
const KPI_REAL = `(select md5(coalesce(string_agg(c.inquiry_id || c.quotes_hash || c.lang || c.created_at::text, ',' order by c.inquiry_id, c.quotes_hash, c.lang), ''))
     from public.qd_compare_cache c
    where not exists (select 1 from public.inquiries di where di.id::text = c.inquiry_id and public.fn_inquiry_is_demo(di.id)))`;
const CASE_REAL = `(select md5(coalesce(string_agg(case_id || state || coalesce(closed_at::text, '') || coalesce(close_reason, ''), ',' order by case_id), ''))
     from public.support_case where not public.fn_party_is_demo(party_kind, party_id))`;

test('production, aborted: both duties act on demo rows only under the switch, and never touch a real row', { skip: SKIP }, async () => {
  const o = await probe(String.raw`
do $$ declare o jsonb := '{}'; inq uuid; cid bigint; tag text := 'zz-demo-fx2-' || substr(md5(random()::text), 1, 10);
  k_on0 int; k_on1 int; k_off0 int; k_off1 int; real0 text; real1 text; st_off text; st_on text;
begin
  -- ── fn_sales_engineer_comparison_kpi (read-only) ──
  perform set_config('qd.duty_fixtures', 'on', true);  k_on0 := (public.fn_sales_engineer_comparison_kpi(7)->>'reports')::int;
  perform set_config('qd.duty_fixtures', 'off', true); k_off0 := (public.fn_sales_engineer_comparison_kpi(7)->>'reports')::int;
  real0 := ${KPI_REAL};
  -- (a) a ZZ DEMO request with one comparison report made two hours after it
  insert into public.inquiries (category, summary, raw_input, brief_source, status, created_at)
  values ('ZZ DEMO', 'ZZ DEMO comparison KPI fixture ' || tag, 'ZZ DEMO', 'qd_demo_fixture', 'open', now() - interval '3 hours')
  returning id into inq;
  insert into public.qd_compare_cache (inquiry_id, quotes_hash, lang, analysis, created_at)
  values (inq::text, tag, 'en', '{"zz_demo": true}', now() - interval '1 hour');
  perform set_config('qd.duty_fixtures', 'on', true);  k_on1 := (public.fn_sales_engineer_comparison_kpi(7)->>'reports')::int;
  perform set_config('qd.duty_fixtures', 'off', true); k_off1 := (public.fn_sales_engineer_comparison_kpi(7)->>'reports')::int;
  real1 := ${KPI_REAL};
  o := o || jsonb_build_object('kpi_demo_is_demo', public.fn_inquiry_is_demo(inq), 'kpi_on_before', k_on0, 'kpi_on_after', k_on1,
    'kpi_off_before', k_off0, 'kpi_off_after', k_off1, 'kpi_real_unchanged', real0 = real1);

  -- ── fn_support_case_idle_close (writes) ──
  -- (a) a ZZ DEMO case waiting on the customer for 60 days, known only by a reserved address
  insert into public.support_case (case_ref, party_kind, party_id, subject, state, channel)
  values ('ZZ-DEMO-' || tag, 'unknown', tag || '@example.invalid', 'ZZ DEMO idle-close fixture', 'waiting_customer', 'internal')
  returning case_id into cid;
  update public.support_case set last_activity_at = now() - interval '60 days' where case_id = cid;
  -- (c) switch off: the real run ignores the demo case
  perform set_config('qd.duty_fixtures', 'off', true);
  o := o || jsonb_build_object('idle_off', public.fn_support_case_idle_close());
  st_off := (select state from public.support_case where case_id = cid);
  -- (d) real cases fingerprinted AFTER the real run, so only the fixture run can move them
  real0 := ${CASE_REAL};
  -- (b) switch on: the fixture run closes the demo case
  perform set_config('qd.duty_fixtures', 'on', true);
  o := o || jsonb_build_object('idle_on', public.fn_support_case_idle_close());
  st_on := (select state from public.support_case where case_id = cid);
  real1 := ${CASE_REAL};
  o := o || jsonb_build_object('idle_demo_is_demo', public.fn_party_is_demo('unknown', tag || '@example.invalid'),
    'idle_last_activity_days', extract(day from now() - (select last_activity_at from public.support_case where case_id = cid)),
    'idle_state_off', st_off, 'idle_state_on', st_on, 'idle_real_unchanged', real0 = real1,
    'idle_real_cases', (select count(*) from public.support_case where not public.fn_party_is_demo(party_kind, party_id)));
  raise exception 'CHK<<%>>', o::text;
end $$;`);
  console.log(JSON.stringify(o));
  // comparison KPI
  assert.equal(o.kpi_demo_is_demo, true, 'the fixture request is not demo by the shared predicate');
  assert.equal(o.kpi_on_after, o.kpi_on_before + 1, '(b) with the switch on the KPI did not count the ZZ DEMO comparison');
  assert.equal(o.kpi_off_after, o.kpi_off_before, '(c) with the switch off the KPI counted the ZZ DEMO comparison');
  assert.equal(o.kpi_real_unchanged, true, '(d) the fixture run changed a real comparison row');
  // idle close
  assert.equal(o.idle_demo_is_demo, true, 'the fixture case is not demo by the shared predicate');
  assert.equal(o.idle_state_off, 'waiting_customer', '(c) with the switch off the duty closed the ZZ DEMO case');
  assert.equal(o.idle_state_on, 'closed', '(b) with the switch on the duty did not close the ZZ DEMO case');
  assert.equal(o.idle_real_unchanged, true, '(d) the fixture run changed a real support case');
  assert.ok(o.idle_on.closed >= 1, '(b) the fixture run reports nothing closed');
});
