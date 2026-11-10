// THE CEO'S TARGET PATH, EXPERIMENTS, COMPETITOR WATCH AND COMPANY STAGES ACT (23 Sep 2026; "ambition and drive").
//
// WHAT FAILS IF THE CAUSE RETURNS. Production, in ONE aborted transaction: the pending files are replayed first, the
// founder path is stubbed, and every fixture is ZZ DEMO / example.invalid.
//   * experiments: a proposal is not filed as a high-stakes CEO decision; a choice outside the options is applied;
//     an approval is not challenged by the accountant; a weekly verdict is not reasoned or never reaches
//     seat_case_memory;
//   * competitors: an identical page is reasoned, a changed page is not, or a material change opens no CEO task;
//   * target: the AED 1M contract is still in force; a miss beyond tolerance on the base-case path opens no CEO task,
//     sends the owning seat no root-cause question, or opens a second task on the same day; the answer never
//     reaches the task;
//   * stages: a met milestone does not move the stage; a stage held by the founder's gate still pins the plan when
//     a seat-movable stage is behind; demand binds during supply_seeding.
//
//   node --test scripts/checks/the_ceo_target_experiments_and_competitors_act.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const MINE = 'scripts/sql/the_ceo_sets_the_target_runs_experiments_and_watches_competitors.sql';
const FILES = ['scripts/sql/every_seat_duty_has_an_owner_a_clock_and_a_check.sql',
  'scripts/sql/the_ceo_reviews_the_week_watches_pricing_and_forecasts_the_target.sql', MINE,
  // the founder's year-one targets (24 Sep 2026) replace this file's base-case contract; replayed after it when pending
  'scripts/sql/the_ceo_runs_the_company_on_the_founders_year_one_targets.sql'];
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));
const code = (p) => read(p).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

test('static: every routine pinned and revoked, every table RLS + policy, duties owned, pending XOR MANIFEST', () => {
  const src = code(MINE);
  const made = [...new Set([...src.matchAll(/create or replace function public\.(\w+)\(/g)].map((m) => m[1]))];
  assert.ok(made.length >= 25, `expected the routines of this file, found ${made.length}`);
  const pure = new Set(['fn_ceo_plan_decide']);   // immutable, reads only its arguments (as in the file it replaces)
  for (const name of made) {
    const head = src.slice(src.indexOf(`function public.${name}(`)).split('$fn$')[0];
    assert.match(head, /set search_path to 'public', 'pg_temp'/, `${name} has no pinned search_path`);
    if (!pure.has(name)) assert.match(head, /security definer/, `${name} is not security definer`);
    assert.match(src, new RegExp(`revoke execute on function public\\.${name}\\([^)]*\\) from public, anon, authenticated;`), `${name} is not revoked`);
  }
  for (const t of [...src.matchAll(/create table if not exists public\.(\w+)/g)].map((m) => m[1])) {
    assert.match(src, new RegExp(`alter table public\\.${t} enable row level security`), `${t} has no RLS`);
    assert.match(src, new RegExp(`create policy ${t}_service_role_only on public\\.${t}[^;]*using \\(false\\) with check \\(false\\)`), `${t} has no policy`);
    assert.match(src, new RegExp(`revoke all on public\\.${t} from anon, authenticated`), `${t} is not revoked`);
  }
  for (const [, prefix, owner] of src.matchAll(/\('(\w+)\.\w+', '(\w+)', interval/g)) assert.equal(prefix, owner, `duty ${prefix} registered to ${owner}`);
  assert.ok(!/update public\.pricing_config/.test(src), 'the watch writes a price; pricing is the founder\'s');
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  assert.ok(pending(MINE) !== manifest.includes(MINE), 'exactly one of a pending note and a MANIFEST line');
});

test('static: the probe touches the hold\'s target_keys only, never its flag', () => {
  const src = read('scripts/checks/the_ceo_target_experiments_and_competitors_act.test.mjs');
  const writes = [...src.matchAll(/update public\.founder_hold set (\w+) =/g)].map((m) => m[1]);
  assert.ok(writes.length === 2 && writes.every((c) => c === 'target_keys'), `the probe writes the hold beyond its target_keys: ${writes}`);
  assert.ok([...src.matchAll(/update public\.founder_hold [^;]*;/g)].every((m) => /where hold_key = 'supplier_campaign'/.test(m[0])), 'a hold write is not scoped to supplier_campaign');
  assert.ok(!/(update|insert into|delete from) public\.app_secrets/i.test(src), 'the probe writes app_secrets: the hold\'s flag is the founder\'s');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token';

// The hold pauses, it does not hide: with the founder's hold on, every held target reads 'paused' and every other
// target reads exactly what it reads without the hold. While the hold is on, at least one held target must be one
// that would otherwise have missed, or the held pass proves nothing about the hold.
function assertHoldPauses(held, free) {
  assert.ok(held && held.day && free, 'the probe did not read the day with and without the hold');
  for (const [m, s] of Object.entries(free)) {
    const want = held.keys.includes(m) ? 'paused' : s;
    assert.equal(held.day[m], want, `with the founder's hold on, ${m} read ${held.day[m]}, expected ${want}`);
  }
  assert.deepEqual(Object.keys(held.day).sort(), Object.keys(free).sort(), 'the hold dropped a target from the day');
  if (held.keys.length) assert.ok(held.keys.some((k) => free[k] === 'miss'), `the hold is on (${held.keys}) but no held target would have missed: the held pass is vacuous`);
}

async function liveHold() {
  const { sql } = await import('../lib/db.mjs');
  return (await sql(`select h.target_keys, (select value from public.app_secrets where key = h.flag_key) is not distinct from h.flag_released_value released
                       from public.founder_hold h where hold_key = 'supplier_campaign'`, { readOnly: true }))[0];
}

async function probe(block) {
  const { sql } = await import('../lib/db.mjs');
  try { await replaySql(FILES.filter(pending).map(read).join('\n') + '\n' + block, { retry: false }); }
  catch (e) {
    // e.message is capped at 2,000 characters by db.mjs; the full answer is on e.body
    const m = String(e.body ?? e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 1500));
    return JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.fail('the probe committed instead of rolling back');
}

test('production, aborted: target, experiments, competitor watch and stages act', { skip: SKIP }, async () => {
  const hold = await liveHold();
  const o = await probe(String.raw`
do $$ declare o jsonb := '{}'; v jsonb; h bigint; e bigint; c bigint; s bigint; t bigint; hid bigint; n bigint; tgt jsonb; f jsonb; hk text[]; yc bigint; begin
  perform set_config('app.qd_stub_founder_notify', 'on', true);
  -- author models are proven on internal_judgement, think()'s decision class (founder_instruction 1056, 29 Sep)
  insert into public.ai_cost_log (fn, agent_key, seat, task_class, model_used, ok) values
    ('probe', 'ceo', 'ceo', 'internal_judgement', 'anthropic/claude-opus-5.5', true),
    ('probe', 'marketing', 'marketing', 'internal_judgement', 'google/gemini-3.8-flash', true);

  -- the seeded unknowns
  o := o || jsonb_build_object('seeded', (select jsonb_agg(jsonb_build_object('key', x.key, 'seat', q.seat, 'stakes', q.request->>'stakes') order by x.key)
            from public.ceo_experiment x join public.reasoning_held_question q on q.id = x.approval_held_id
           where x.key in ('reveal_conversion', 'b2b_accounts_consented', 'category_mix_top4')));

  -- a ZZ DEMO experiment through approval, the weekly verdict and the case memory
  e := public.fn_ceo_experiment_propose('marketing', 'zz_demo_probe', 'ZZ DEMO hypothesis', 'inquiries_posted', 'ZZ DEMO', 0, 'ZZ DEMO', 5, 'min', 'ZZ DEMO', current_date - 1, 14);
  select approval_held_id into h from public.ceo_experiment where id = e;
  begin
    perform public.fn_reason_held_resolve(h, '{"status":"answered","answer":"x","decision":{"choice":"yolo"}}');
    o := o || jsonb_build_object('bad_choice', 'applied');
  exception when others then o := o || jsonb_build_object('bad_choice', left(sqlerrm, 20)); end;
  perform public.fn_reason_held_resolve(h, '{"status":"answered","answer":"ZZ DEMO: sound, the metric is measured by code and fourteen days is enough","model":"anthropic/claude-opus-5.5","decision":{"choice":"approve","fields":{"owner_seat":{"value":"marketing"},"days":{"value":"14"}}}}');
  o := o || jsonb_build_object('approved', (select jsonb_build_object('status', status, 'owner', owner_seat, 'days', ends_on - starts_on,
            'reviewer', (select reviewer_seat from public.seat_deliberation where id = (approval->'review'->>'deliberation_id')::bigint))
            from public.ceo_experiment where id = e));
  v := public.fn_ceo_experiment_review();
  select held_id into h from public.ceo_experiment_verdict where experiment_id = e;
  perform public.fn_reason_held_resolve(h, '{"status":"answered","answer":"ZZ DEMO: refuted, the metric did not move in fourteen days","model":"anthropic/claude-opus-5.5","decision":{"choice":"killed","fields":{"lesson":{"value":"ZZ DEMO lesson"}}}}');
  o := o || jsonb_build_object('killed', (select status from public.ceo_experiment where id = e),
    'case', (select jsonb_build_object('seat', seat, 'final', finalised, 'lessons', lessons) from public.seat_case_memory
              where source_table = 'ceo_experiment_verdict' and source_id like e || ':%'));

  -- the competitor watch
  -- Every live competitor was fetched on 24 Sep, so for 30 days the real scan has nothing due and starts 0 fetches
  -- (29 Sep 2026). A watched ZZ DEMO competitor, due now, is the one the scan must start; its request is queued
  -- inside this transaction and rolled back with it.
  insert into public.competitor (name, url, kind, threat_level, watched, what_they_do) values ('ZZ DEMO watched competitor', 'https://zz-watched.example.invalid', 'marketplace', 'low', true, 'ZZ DEMO');
  v := public.fn_marketing_competitor_scan();
  o := o || jsonb_build_object('fetches_started', v->'requested');
  insert into public.competitor (name, url, kind, threat_level, watched, what_they_do, business_model, overlap, strength, weakness) values ('ZZ DEMO competitor', 'https://zz.example.invalid', 'marketplace', 'low', false, 'ZZ DEMO', 'ZZ DEMO', 'ZZ DEMO', 'ZZ DEMO', 'ZZ DEMO') returning id into c;
  -- 10 Nov 2026 (it_engineer): since the_competitor_watch_reads_real_pages_and_never_briefs_on_nothing.sql (19 Oct, marketing,
  -- ledger 1003 stage 2) a page with under 200 characters of readable text is 'failed' as an empty shell and holds no
  -- question, so the fixture pages below carry 200+ characters (the same padding on the 'same' page, so it still hashes equal).
  insert into public.competitor_scan (competitor_id, page_kind, url) values (c, 'pricing', 'https://zz.example.invalid') returning id into s;
  v := public.fn_competitor_scan_ingest(s, 200, '<html><script>var t=1</script><p>ZZ DEMO: AED 100 a lead' || repeat(' ZZ DEMO marketplace page text for the competitor watch probe.', 5) || '</p></html>');
  o := o || jsonb_build_object('first', v->>'status', 'first_options', (select jsonb_agg(x->>'id') from public.competitor_scan z join public.reasoning_held_question q on q.id = z.held_id,
            jsonb_array_elements(q.request->'decision'->'options') x where z.id = s));
  perform public.fn_reason_held_resolve((select held_id from public.competitor_scan where id = s),
    '{"status":"answered","answer":"ZZ DEMO","model":"google/gemini-3.8-flash","decision":{"choice":"profiled","fields":{"pricing":{"value":"AED 100 a lead"}}}}');
  insert into public.competitor_scan (competitor_id, page_kind, url) values (c, 'pricing', 'https://zz.example.invalid') returning id into s;
  o := o || jsonb_build_object('same', public.fn_competitor_scan_ingest(s, 200, '<html><script>var t=2</script><p>ZZ DEMO: AED 100 a lead' || repeat(' ZZ DEMO marketplace page text for the competitor watch probe.', 5) || '</p></html>')->>'status');
  insert into public.competitor_scan (competitor_id, page_kind, url) values (c, 'pricing', 'https://zz.example.invalid') returning id into s;
  o := o || jsonb_build_object('diff', public.fn_competitor_scan_ingest(s, 200, '<p>ZZ DEMO: free for suppliers now' || repeat(' ZZ DEMO marketplace page text for the competitor watch probe.', 5) || '</p>')->>'status');
  perform public.fn_reason_held_resolve((select held_id from public.competitor_scan where id = s),
    '{"status":"answered","answer":"ZZ DEMO","model":"google/gemini-3.8-flash","decision":{"choice":"changed","fields":{"what_changed":{"value":"ZZ DEMO dropped the lead fee"}}}}');
  o := o || jsonb_build_object('change_task', (select t.title from public.competitor_scan z join public.ceo_task t on t.task_id = z.task_id where z.id = s));

  -- the target contract in force, and a day on the path in November with nothing measured
  o := o || jsonb_build_object('contracts', (select jsonb_object_agg(contract_key, status) from public.target_contract
            where contract_key in ('REVENUE_AED_1M_BY_2027_10_01', 'REVEAL_FEES_BASE_PATH_BY_2027_08_31')),
    'paths', (select count(*) from public.target_path), 'path_seats', (select count(distinct owner_seat) from public.target_path),
    'nov_month_plan', (select inquiries from public.ceo_plan_month where month = date '2026-11-01'));
  -- The founder's supplier_campaign hold (ledger 1312) pauses the supplier targets. First the day as production would
  -- read it, in a sub-block that rolls itself back: every held target must read 'paused' (never dropped). Then the
  -- hold's target_keys are emptied INSIDE THIS ABORTED TRANSACTION ONLY (the flag, invite_enabled, is never touched),
  -- so the misses, tasks and root-cause questions below are the path's own; they are restored before 'today'.
  select id into yc from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30';
  hk := array(select target_key from public.fn_held_targets() where hold_key = 'supplier_campaign');
  begin
    tgt := public.fn_ceo_target_daily_verdict(timestamptz '2026-11-20 10:00+04');
    o := o || jsonb_build_object('held', jsonb_build_object('keys', to_jsonb(hk), 'misses', tgt->'misses',
      'day', (select jsonb_object_agg(metric_key, status) from public.target_daily_verdict where contract_id = yc and day = date '2026-11-20')));
    raise exception 'ZZ_HELD_PASS_ROLLED_BACK';
  exception when raise_exception then if sqlerrm <> 'ZZ_HELD_PASS_ROLLED_BACK' then raise; end if;
  end;
  -- ISOLATION (10 Nov 2026, it_engineer). This probe reads a November day; it was written before production had one.
  -- Since 8 Nov the year-one contract holds REAL open November miss tasks (5 on 10 Nov: invitations_delivered,
  -- registrations_submitted, registrations_verified_cumulative, verified_suppliers_milestone, it_findings_open), and the
  -- verdict rightly opens one task per metric per month, so the probe saw 7 misses and only 2 new tasks. The real
  -- links are set aside for the 20 Nov runs only and restored before 'today' is read; the closing raise rolls back both.
  create temp table _zz_nov_links on commit drop as
    select day, contract_id, metric_key, task_id from public.target_daily_verdict where contract_id = yc and day between date '2026-11-01' and date '2026-11-30' and task_id is not null;
  update public.target_daily_verdict d set task_id = null from _zz_nov_links l
   where (d.day, d.contract_id, d.metric_key) = (l.day, l.contract_id, l.metric_key);
  update public.founder_hold set target_keys = '{}' where hold_key = 'supplier_campaign';
  select coalesce(max(id), 0) into n from public.agent_actions;
  tgt := public.fn_ceo_target_daily_verdict(timestamptz '2026-11-20 10:00+04');
  o := o || jsonb_build_object('nov', jsonb_build_object('misses', tgt->'misses', 'opened', tgt->'tasks_opened'),
    'nov_day', (select jsonb_object_agg(metric_key, status) from public.target_daily_verdict where contract_id = yc and day = date '2026-11-20'),
    'nov_again', public.fn_ceo_target_daily_verdict(timestamptz '2026-11-20 11:00+04')->'tasks_opened',
    'root_cause_to', (select jsonb_agg(distinct agent order by agent) from public.agent_actions where id > n and kind = 'handoff' and detail->>'type' = 'ceo.root_cause' and status = 'pending'));
  select id, (detail->>'task_id')::bigint into hid, t from public.agent_actions where id > n and kind = 'handoff' and detail->>'type' = 'ceo.root_cause' and agent = 'marketing';
  select id into h from public.reasoning_held_question where dedupe_key = 'root_cause:marketing:' || t;
  perform public.fn_reason_held_resolve(h, '{"status":"answered","answer":"ZZ DEMO","model":"google/gemini-3.8-flash","decision":{"choice":"demand_short","fields":{"root_cause":{"value":"ZZ DEMO no buyers yet"},"corrective_action":{"value":"ZZ DEMO SEO"}}}}');
  o := o || jsonb_build_object('answered', (select jsonb_build_object('task', state, 'has_cause', evidence like '%ZZ DEMO no buyers yet%') from public.ceo_task where task_id = t),
    'handoff_after', (select status from public.agent_actions where id = hid),
    'miss_case', (select seat from public.seat_case_memory where source_table = 'ceo_task' and source_id = t::text));
  -- today is read with the founder's hold back as production has it (restored from what this transaction emptied)
  update public.founder_hold set target_keys = (select array_agg(distinct k) from unnest(hk) k) where hold_key = 'supplier_campaign' and cardinality(hk) > 0;
  update public.target_daily_verdict d set task_id = l.task_id from _zz_nov_links l   -- the real November links, back
   where (d.day, d.contract_id, d.metric_key) = (l.day, l.contract_id, l.metric_key);
  o := o || jsonb_build_object('today', public.fn_ceo_target_daily_verdict()->'tasks_opened');

  -- the company stage and the plan that is not pinned to a held stage
  o := o || jsonb_build_object('stage_now', public.fn_ceo_company_stage_advance()->>'stage',
    'next1', public.fn_ceo_company_stage_next('supply_seeding', '{"registrations_verified_cumulative":80,"reveals_paid_cumulative":0}'),
    'next3', public.fn_ceo_company_stage_next('supply_seeding', '{"registrations_verified_cumulative":90,"reveals_paid_cumulative":3,"reveals_paid_30d":9,"fee_aed_30d":100}'),
    'funnel_stage', public.fn_ceo_plan_funnel(now())->'company_stage'->>'stage');
  f := '{"local_date":"2026-11-20","day_of_month":20,"days_in_month":30,"state":{"bounce_pct_7d":0,"stranded_submissions":0},
         "gates":{"invite_enabled":false,"supplier_outreach_golive":false,"invite_daily_cap":50},
         "month_to_date":{"invitations_delivered":0,"registrations_submitted":0,"registrations_verified":0,"inquiries_posted":0,"reveals_paid":0},
         "last_7_days":{}}'::jsonb;
  v := public.fn_ceo_plan_decide(f || '{"company_stage":{"stage":"first_revenue","scope":["deliverability","invitations","registrations","verification","demand","quotes","reveals"]}}',
         '{"invites":2200,"registered":90,"verified":0,"inquiries":138,"reveals":9}', null);
  o := o || jsonb_build_object('open_scope', jsonb_build_object('stage', v->>'stage', 'lever', v->>'lever', 'owner', v->>'owner_seat', 'held', v->'held_upstream'));
  v := public.fn_ceo_plan_decide(f || '{"company_stage":{"stage":"supply_seeding","scope":["deliverability","invitations","registrations","verification"]}}',
         '{"invites":2200,"registered":90,"verified":0,"inquiries":138,"reveals":9}', null);
  o := o || jsonb_build_object('seeding', jsonb_build_object('stage', v->>'stage', 'lever', v->>'lever'));
  o := o || jsonb_build_object('forecast_has_path', public.fn_ceo_target_forecast()->'verdicts' @> '[{"contract":"FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30"}]');
  raise exception 'CHK<<%>>', o::text;
end $$;`);
  assert.deepEqual(await liveHold(), hold, 'the founder\'s hold changed in production: the probe must touch it only inside its aborted transaction');

  assert.deepEqual(o.seeded, [
    { key: 'b2b_accounts_consented', seat: 'ceo', stakes: 'high' },
    { key: 'category_mix_top4', seat: 'ceo', stakes: 'high' },
    { key: 'reveal_conversion', seat: 'ceo', stakes: 'high' }], 'the three unknowns are not awaiting the CEO\'s reasoned approval');
  assert.equal(o.bad_choice, 'CHOICE_NOT_AN_OPTION', 'a choice outside the options was applied');
  assert.deepEqual(o.approved, { status: 'running', owner: 'marketing', days: 14, reviewer: 'accountant' }, 'the approval did not run the experiment or was not challenged');
  assert.equal(o.killed, 'killed');
  assert.deepEqual(o.case, { seat: 'marketing', final: true, lessons: ['ZZ DEMO lesson'] }, 'the verdict never reached seat_case_memory');

  assert.ok(o.fetches_started > 0 && o.fetches_started <= 10, `the monthly scan started ${o.fetches_started} fetches`);
  assert.equal(o.first, 'fetched');
  assert.deepEqual(o.first_options, ['profiled', 'unreadable']);
  assert.equal(o.same, 'unchanged', 'a page whose text did not change was reasoned');
  assert.equal(o.diff, 'fetched', 'a changed page was not reasoned');
  assert.match(o.change_task ?? '', /^Competitor change: ZZ DEMO competitor/, 'a material change opened no CEO task');

  assert.deepEqual(o.contracts, { REVENUE_AED_1M_BY_2027_10_01: 'superseded', REVEAL_FEES_BASE_PATH_BY_2027_08_31: 'superseded' }, 'the year-one targets did not replace the base case');
  assert.equal(o.paths, 262); assert.equal(o.path_seats, 6);   // 70 of the base case (superseded) + 192 of the year-one path
  assert.equal(o.nov_month_plan, 0, 'the CEO month plan does not follow the year-one path');
  assert.ok(o.nov.misses >= 3 && o.nov.opened === o.nov.misses, `a November day with nothing measured: ${JSON.stringify(o.nov)}`);
  assertHoldPauses(o.held, o.nov_day);
  assert.equal(o.nov_again, 0, 'a second verdict the same day opened a second task');
  for (const s of ['customer_support', 'marketing', 'sales_engineer']) assert.ok(o.root_cause_to.includes(s), 'the owning seats were not asked for the root cause: ' + o.root_cause_to);
  assert.deepEqual(o.answered, { task: 'working', has_cause: true }, 'the root cause never reached the CEO task');
  assert.equal(o.handoff_after, 'done', 'the CEO did not close the root-cause handoff');
  assert.equal(o.miss_case, 'marketing');
  assert.equal(o.today, 0, 'a September day (no path) opened a task');

  assert.equal(o.stage_now, 'supply_seeding'); assert.equal(o.funnel_stage, 'supply_seeding');
  assert.equal(o.next1, 'demand_opening'); assert.equal(o.next3, 'repeatable');
  assert.deepEqual(o.open_scope, { stage: 'demand', lever: 'seat', owner: 'marketing', held: ['invitations', 'registrations'] },
    'a stage held by the founder\'s gate still pins the plan');
  assert.deepEqual(o.seeding, { stage: 'invitations', lever: 'founder_reserved' }, 'demand bound during supply_seeding');
  assert.equal(o.forecast_has_path, true, 'the weekly forecast does not read the target in force');
});
