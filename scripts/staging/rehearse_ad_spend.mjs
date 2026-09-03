// AD SPEND AUTOPILOT — the sandbox rehearsal (3 Sep 2026).
//
// Proves, on the production database and with the Meta token ABSENT, that the paid-media manager
// does what the founder's model needs: judges campaigns by cost per lead, kills losers, scales
// winners, holds learners, switches on what fits, paces down when the month runs short, and cannot
// be made to exceed the ceiling by any path — then executes its decisions in sandbox mode and leaves
// nothing behind. Everything it seeds is is_demo=true and tagged; fn_ads_manage(true) never sees a
// real campaign and the daily tick (fn_ads_manage(false)) never sees these.
//
//   QD_FIXTURES=1 node scripts/staging/rehearse_ad_spend.mjs
import { REF, q, num } from './demo_factory.mjs';
import { mgmtRead, mgmtFixture } from './qd_guard.mjs';

if (process.env.QD_FIXTURES !== '1') { console.error('refusing: this script writes fixtures; set QD_FIXTURES=1'); process.exit(2); }

const BASE = `https://${REF}.supabase.co/functions/v1`;
const checks = [];
const ok = (name, pass, detail) => { checks.push(pass); console.log(`${pass ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(56)} ${detail}`); };
const read = (sql) => mgmtRead(REF, sql);
const write = (sql) => mgmtFixture(REF, sql, 'ad spend rehearsal');
// An aborted-transaction probe: run the body, raise with a message, read the message back.
const probe = async (body) => {
  try { await write(`do $p$ begin ${body} end $p$;`); return 'NO_EXCEPTION'; }
  catch (e) { const m = String(e.message || e); const i = m.indexOf('PROBE|'); return i >= 0 ? m.slice(i).split('\n')[0] : m.slice(0, 300); }
};

const tag = 'zzdemo-ads-' + Math.random().toString(36).slice(2, 8);
const C = { W: `${tag}-winner`, L: `${tag}-loser`, N: `${tag}-learner`, P: `${tag}-paused` };
const cred = (await read("select value from public.app_secrets where key='cred_fn_agent_act'"))[0]?.value;
const execute = async () => {
  const r = await fetch(`${BASE}/meta_ads`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: cred, action: 'execute_decisions', limit: 50 }) });
  return { status: r.status, json: await r.json().catch(() => null) };
};

try {
  // The policy the rehearsal runs under is the live default row; read it rather than assume it.
  const pol = (await read('select * from public.ad_spend_policy where policy_key=\'default\''))[0];
  const ceiling = Number((await read('select public.fn_ad_spend_daily_ceiling() c'))[0].c);
  ok('policy row present, ceiling computed', !!pol && ceiling > 0, `daily_cap=${pol.daily_cap_aed} target_cpl=${pol.target_cpl_aed} kill=${pol.kill_multiplier}x ceiling=${ceiling}`);
  const target = Number(pol.target_cpl_aed), kill = Number(pol.kill_multiplier), maxPer = Number(pol.max_daily_per_campaign_aed), step = Number(pol.scale_step_pct);

  // 1. SEED four demo campaigns and the insights the manager will judge them on.
  await write(`
    insert into public.ad_campaign_state (campaign_id, campaign_name, adset_id, status, daily_budget_aed, started_at, is_demo) values
      (${q(C.W)}, 'ZZ DEMO winner',  ${q(C.W + '-adset')}, 'ACTIVE', 50, now() - interval '10 days', true),
      (${q(C.L)}, 'ZZ DEMO loser',   ${q(C.L + '-adset')}, 'ACTIVE', 50, now() - interval '10 days', true),
      (${q(C.N)}, 'ZZ DEMO learner', ${q(C.N + '-adset')}, 'ACTIVE', 40, now() - interval '1 day',   true),
      (${q(C.P)}, 'ZZ DEMO paused',  ${q(C.P + '-adset')}, 'PAUSED', 30, null,                       true);
    insert into public.meta_insights (campaign_id, campaign_name, effective_status, objective, time_window, spend, impressions, clicks, reach, ctr, cpc, results, currency, synced_at, synced_via) values
      (${q(C.W)}, 'ZZ DEMO winner',  'ACTIVE', 'OUTCOME_LEADS', 'last_7d', 500, 50000, 900, 30000, 1.8, 0.55, 10, 'AED', now(), 'rehearsal'),
      (${q(C.L)}, 'ZZ DEMO loser',   'ACTIVE', 'OUTCOME_LEADS', 'last_7d', 600, 60000, 700, 35000, 1.1, 0.85, 1,  'AED', now(), 'rehearsal'),
      (${q(C.N)}, 'ZZ DEMO learner', 'ACTIVE', 'OUTCOME_LEADS', 'last_7d', 30,  3000,  40,  2500,  1.3, 0.75, 0,  'AED', now(), 'rehearsal');`);
  const seeded = (await read(`select count(*)::int c from public.ad_campaign_state where is_demo and campaign_id like ${q(tag + '%')}`))[0].c;
  ok('4 demo campaigns seeded (winner cpl 50, loser cpl 600, learner day 1, paused never-run)', seeded === 4, `rows=${seeded}`);

  // 2. JUDGE. Expect exactly: loser paused (kill), winner scaled by step (capped), paused activated.
  const dec = await read(`select campaign_id, action, amount_aed, rule_key from public.fn_ads_manage(true, ${q(tag)}) order by campaign_id`);
  const by = Object.fromEntries(dec.map((d) => [d.campaign_id, d]));
  const expW = Math.min(maxPer, Math.floor(50 * (1 + step / 100)));
  ok('loser is paused by kill rule', by[C.L]?.action === 'pause' && by[C.L]?.rule_key === 'kill_3x', `${by[C.L]?.rule_key}: cpl 600 > ${kill}x${target}`);
  ok('winner is scaled up by the step', by[C.W]?.action === 'set_daily_budget' && Number(by[C.W]?.amount_aed) === expW && by[C.W]?.rule_key === 'scale_winner', `50 -> ${by[C.W]?.amount_aed} (expected ${expW})`);
  ok('learner gets no decision on day 1', !by[C.N], by[C.N] ? JSON.stringify(by[C.N]) : 'held');
  ok('never-run paused campaign is activated (fits under ceiling)', by[C.P]?.action === 'activate', `${by[C.P]?.rule_key || 'no decision'}`);
  ok('no other decisions were written', dec.length === 3, `decisions=${dec.length}`);

  // 3. THE GUARD, under aborted transactions: per-campaign maximum, then the ceiling itself.
  const g1 = await probe(`
    begin
      insert into public.ad_decision (campaign_id, action, amount_aed, rule_key, reason, run_tag) values (${q(C.N)}, 'set_daily_budget', ${num(maxPer + 1)}, 'probe', 'probe', ${q(tag)});
      raise exception 'PROBE|GUARD_DID_NOT_FIRE';
    exception when others then
      if sqlerrm like 'AD_SPEND_GUARD:%' then raise exception 'PROBE|per_campaign_max_refused|%', sqlerrm; else raise; end if;
    end;`);
  ok('guard refuses a budget above the per-campaign maximum', g1.startsWith('PROBE|per_campaign_max_refused'), g1.slice(0, 110));
  const g2 = await probe(`
    begin
      update public.ad_spend_policy set daily_cap_aed = 10 where policy_key = 'default';
      insert into public.ad_decision (campaign_id, action, rule_key, reason, run_tag) values (${q(C.P)}, 'activate', 'probe', 'probe', ${q(tag)});
      raise exception 'PROBE|GUARD_DID_NOT_FIRE';
    exception when others then
      if sqlerrm like 'AD_SPEND_CEILING:%' then raise exception 'PROBE|ceiling_refused|%', sqlerrm; else raise; end if;
    end;`);
  ok('guard refuses an activation that would exceed the ceiling', g2.startsWith('PROBE|ceiling_refused'), g2.slice(0, 120));
  const capBack = Number((await read('select daily_cap_aed from public.ad_spend_policy where policy_key=\'default\''))[0].daily_cap_aed);
  ok('the probe rolled the policy back', capBack === Number(pol.daily_cap_aed), `daily_cap=${capBack}`);

  // 4. EXECUTE in sandbox mode (no token) and check the manager's picture of Meta moved.
  const ex = await execute();
  ok('execute_decisions ran in sandbox mode, all executed', ex.status === 200 && ex.json?.mode === 'sandbox' && ex.json?.executed === 3 && ex.json?.failed === 0, JSON.stringify(ex.json));
  const st = Object.fromEntries((await read(`select campaign_id, status, daily_budget_aed, started_at from public.ad_campaign_state where campaign_id like ${q(tag + '%')}`)).map((r) => [r.campaign_id, r]));
  ok('state: loser PAUSED, winner budget raised, paused now ACTIVE with started_at', st[C.L]?.status === 'PAUSED' && Number(st[C.W]?.daily_budget_aed) === expW && st[C.P]?.status === 'ACTIVE' && !!st[C.P]?.started_at, `L=${st[C.L]?.status} W=${st[C.W]?.daily_budget_aed} P=${st[C.P]?.status}`);
  const led = (await read(`select count(*)::int n, count(executed_at)::int done, count(*) filter (where execution_mode='sandbox')::int sb from public.ad_decision where run_tag=${q(tag)}`))[0];
  ok('ledger: every decision executed, stamped sandbox', led.n === 3 && led.done === 3 && led.sb === 3, JSON.stringify(led));

  // 5. SECOND TICK: only the winner moves again (next step), nothing is re-decided.
  const dec2 = await read(`select campaign_id, action, amount_aed, rule_key from public.fn_ads_manage(true, ${q(tag)})`);
  const expW2 = Math.min(maxPer, Math.floor(expW * (1 + step / 100)));
  ok('second tick: winner steps up again, nothing else re-decided', dec2.length === 1 && dec2[0].campaign_id === C.W && Number(dec2[0].amount_aed) === expW2, JSON.stringify(dec2));
  const ex2 = await execute();
  ok('second execution in sandbox', ex2.json?.executed === 1 && ex2.json?.failed === 0, JSON.stringify(ex2.json));

  // 6. PACING under an aborted transaction: the month is nearly spent, the ceiling collapses.
  const g3 = await probe(`
    declare v_down int; v_pause int; v_ceiling numeric; v_total numeric;
    begin
      update public.ad_spend_policy set monthly_cap_aed = 100, month_spent_aed = 99, month_label = to_char(now(), 'YYYY-MM') where policy_key = 'default';
      v_ceiling := public.fn_ad_spend_daily_ceiling();
      select count(*) filter (where rule_key='pace_down'), count(*) filter (where rule_key='pace_pause') into v_down, v_pause from public.fn_ads_manage(true, ${q(tag)});
      raise exception 'PROBE|pace|ceiling=%|down=%|pause=%', round(v_ceiling, 3), v_down, v_pause;
    end;`);
  const pm = /PROBE\|pace\|ceiling=([0-9.]+)\|down=(\d+)\|pause=(\d+)/.exec(g3) || [];
  ok('pacing: ceiling collapses and the active set is shrunk then paused to fit', pm.length === 4 && Number(pm[1]) < 1 && Number(pm[2]) >= 1 && Number(pm[3]) >= 1, g3.slice(0, 90));
  const polBack = (await read('select monthly_cap_aed, month_spent_aed from public.ad_spend_policy where policy_key=\'default\''))[0];
  ok('pacing probe rolled back (policy untouched)', String(polBack.monthly_cap_aed ?? '') === String(pol.monthly_cap_aed ?? '') && Number(polBack.month_spent_aed) === Number(pol.month_spent_aed), JSON.stringify(polBack));

  // 7. The real manager never sees the fixtures.
  const realSees = (await read(`select count(*)::int c from public.fn_ads_manage(false, ${q(tag)}) where campaign_id like ${q(tag + '%')}`))[0].c;
  ok('fn_ads_manage(false) writes nothing about demo campaigns', realSees === 0, `demo decisions from the real tick=${realSees}`);
} finally {
  // TEARDOWN — by tag, then prove it.
  await write(`
    delete from public.ad_decision where run_tag = ${q(tag)} or campaign_id like ${q(tag + '%')};
    delete from public.ad_campaign_state where is_demo and campaign_id like ${q(tag + '%')};
    delete from public.meta_insights where campaign_id like ${q(tag + '%')};`);
  const left = (await read(`select (select count(*) from public.ad_decision where campaign_id like ${q(tag + '%')}) + (select count(*) from public.ad_campaign_state where campaign_id like ${q(tag + '%')}) + (select count(*) from public.meta_insights where campaign_id like ${q(tag + '%')}) as n`))[0].n;
  ok('teardown left nothing behind', Number(left) === 0, `rows left=${left}`);
}
const passed = checks.filter(Boolean).length;
console.log(`\n${passed}/${checks.length} checks passed`);
process.exit(passed === checks.length ? 0 : 1);
