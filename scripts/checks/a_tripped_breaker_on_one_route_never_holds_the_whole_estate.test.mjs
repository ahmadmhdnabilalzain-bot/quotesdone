// A TRIPPED BREAKER ON ONE ROUTE NEVER HOLDS THE WHOLE ESTATE. Founder, 7 Oct 2026 (ledger 1175): "from now on
// keep open router always on" -- and failure circuit breakers must still work normally, per route.
// Seat: it_engineer. Subject: scripts/sql/a_tripped_breaker_on_one_route_never_holds_the_whole_estate.sql.
//
// Measured 7 Oct 2026 after the lift: rule 3 of fn_kernel_paid_provider_gate counted any open_until > now() as the
// founder's hold, so one model's 5-15 minute failure breaker denied every paid call on every route. This check
// fails if rule 3 goes back to reading a cooldown as a hold, or if a breaker stops refusing its own route.
//
//   node --test scripts/checks/a_tripped_breaker_on_one_route_never_holds_the_whole_estate.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const ROOT = new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const sqlText = readFileSync(join(ROOT, 'scripts/sql/a_tripped_breaker_on_one_route_never_holds_the_whole_estate.sql'), 'utf8');
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('rule 3 counts only routes held more than a year out; rule 5 still refuses an open breaker on its own route', () => {
  assert.match(sqlText, /into v_held from public\.llm_route_health where open_until is not null and open_until > now\(\) \+ interval '1 year';/);
  assert.match(sqlText, /'rule', 'route_open'/);
});

test('no SQL file writes a far-future open_until into llm_route_health any more', () => {
  for (const f of ['hold_01_stop_all_openrouter_calls.sql', 'gpt_sol_takes_every_qwen_class_and_one_gemini_takes_every_gemini_class.sql',
    'the_catalogue_names_every_model_the_seats_run_and_the_hold_covers_all_of_them.sql',
    'every_seat_runs_the_founders_model_matrix_and_every_review_stays_cross_family.sql']) {
    const s = readFileSync(join(ROOT, 'scripts/sql', f), 'utf8').replace(/--[^\n]*/g, '');
    assert.doesNotMatch(s, /open_until\s*=\s*now\(\)\s*\+\s*interval '100 years'/i, f);
    assert.doesNotMatch(s, /\(select max\(h\.open_until\) from public\.llm_route_health h\)/i, `${f}: a new route copies the fleet's open_until`);
  }
});

const PROBE = `
do $p$
declare o jsonb := '{}'; a text; b text;
begin
  select model_id into a from public.llm_route_health h
   where exists (select 1 from public.model_registry r where r.model_id = h.model_id and r.active) order by model_id limit 1;
  select model_id into b from public.llm_route_health h
   where exists (select 1 from public.model_registry r where r.model_id = h.model_id and r.active) and model_id <> a order by model_id limit 1;
  o := o || jsonb_build_object('held_routes', (select count(*) from public.llm_route_health where open_until > now() + interval '1 year'));
  -- a real breaker: one route, cooldown in minutes (rolled back by the raise below)
  perform set_config('app.change_reason', 'probe:a_tripped_breaker_on_one_route_never_holds_the_whole_estate', true);
  update public.llm_route_health set open_until = now() + interval '15 minutes' where model_id = a;
  o := o || jsonb_build_object('tripped', public.fn_kernel_paid_provider_gate(a)->>'rule',
                               'other', public.fn_kernel_paid_provider_gate(b)->>'rule');
  raise exception 'CHK<<%>>', o::text;
end $p$;`;

test('production, one aborted transaction: a breaker on one route refuses that route and no other', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { replaySql } = await import('../lib/safe_replay.mjs');
  let out;
  try { await replaySql(sqlText + '\n' + PROBE, { retry: false }); } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw e;
    out = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  console.log(JSON.stringify(out));
  assert.equal(out.held_routes, 0, 'ruling 1175: no route is held by the founder');
  assert.equal(out.tripped, 'route_open', 'the tripped route is refused by its own breaker');
  assert.equal(out.other, 'registered_breaker_closed', 'every other route stays open');
});

// The held-question replay (resilience_ping -> _shared/think.ts replayHeld) and the accountant call ai_gateway with
// their own cred_fn_<name>. Measured 7 Oct 03:45: both got HTTP 403 because their scope did not name ai_gateway, so the
// queue burnt its tries and drained nothing. Fails if either credential loses the door again.
test('production, aborted: every gateway caller that replays held questions can present itself', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { replaySql } = await import('../lib/safe_replay.mjs');
  const fix = readFileSync(join(ROOT, 'scripts/sql/the_held_question_replay_may_present_itself_to_the_gateway.sql'), 'utf8');
  let out;
  try {
    await replaySql(fix + `\ndo $p$ begin raise exception 'CHK<<%>>', (select jsonb_object_agg(context, 'ai_gateway' = any(scope))
      from public.internal_credential where active and context in ('fn.resilience_ping', 'fn.accountant'))::text; end $p$;`, { retry: false });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw e;
    out = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.deepEqual(out, { 'fn.accountant': true, 'fn.resilience_ping': true });
});
