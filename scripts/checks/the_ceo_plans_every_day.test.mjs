// THE CEO PLANS EVERY DAY, DIRECTS THE SEATS, AND FOLLOWS UP.       seat: ceo · 22 Sep 2026 · instruction 638
//
// Measured 22 Sep 2026: nothing computed the funnel against a plan, the CEO gave no seat an order, and its
// decision log held two rows. This check fails if the same causes come back:
//   A. the plan leaves the heartbeat (no ceoPlan runner, or no resilience_step row for it);
//   B. the plan starts writing to the founder (notifications, founder_alerts, fn_notify_founder, ...);
//   C. the plan starts writing a supplier, customer, payment or founder-switch row;
//   D. the directive stops travelling the existing handoff machinery, or the CEO stops being its closer;
//   E. the model slot loses its contract limits or its validation, or plan C stops acting first;
//   F. the founder brief stops carrying the plan in item 7;
//   G. (live, when a management token is present) the pure decision function, replayed in pg_temp,
//      stops naming the right lever: switches off -> founder, no directive; switches on -> a directive to
//      sales_engineer; 8 days stalled -> level 2; 15 days -> level 3 with a line for the founder.
//      The 22 Sep defect this also replays: a JSON null directive read as present by the act.
//
//   node --test scripts/checks/the_ceo_plans_every_day.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pendingNotes } from '../lib/pending_sql.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const SQL_FILE = 'scripts/sql/the_ceo_plans_every_day_and_directs_the_seats.sql';
const sql = readFileSync(path.join(REPO, SQL_FILE), 'utf8');
const code = sql.replace(/--[^\n]*/g, '');
const fnBody = (name) => {
  // ends at the first `$fn$;` -- a body closes with "end $fn$;" or "\n$fn$;", and the opening "as $fn$" has no ";"
  const m = sql.match(new RegExp('create or replace function public\\.' + name + '\\([\\s\\S]*?\\$fn\\$;'));
  assert.ok(m, `${name} is not defined in ${SQL_FILE}`);
  return m[0];
};

test('A. the plan runs on the heartbeat', () => {
  const rp = readFileSync(path.join(REPO, 'supabase/functions/resilience_ping/index.ts'), 'utf8');
  assert.match(rp, /ceoPlan: \{ run: ceoPlanTick \}/, 'resilience_ping has no ceoPlan runner');
  assert.match(rp, /admin\.rpc\('fn_ceo_plan_tick'\)/);
  assert.match(code, /insert into public\.resilience_step[\s\S]*'ceoPlan'/, 'no resilience_step row schedules ceoPlan');
  const listed = readFileSync(path.join(REPO, 'scripts/sql/MANIFEST.txt'), 'utf8').split(/\r?\n/).includes(SQL_FILE)
    || pendingNotes().has(SQL_FILE);
  assert.ok(listed, 'the file is neither in MANIFEST.txt nor pending');
});

test('B. nothing in the plan writes to the founder', () => {
  for (const re of [/insert\s+into\s+public\.notifications/i, /insert\s+into\s+public\.founder_alerts/i,
                    /fn_notify_founder/i, /fn_founder_mail_route/i, /alert_founder/i, /fn_support_report_to_ceo/i])
    assert.doesNotMatch(code, re, `the plan reaches the founder: ${re}`);
});

test('C. nothing in the plan writes a supplier, customer, payment or switch row', () => {
  for (const t of ['leads', 'customers', 'transactions', 'inquiries', 'quotes', 'refunds', 'app_secrets'])
    assert.doesNotMatch(code, new RegExp(`(insert\\s+into|update|delete\\s+from)\\s+public\\.${t}\\b`, 'i'), `the plan writes public.${t}`);
});

test('D. directives travel the handoff machinery and only the CEO closes them', () => {
  const act = fnBody('fn_ceo_plan_act');
  assert.match(act, /public\.fn_seat_handoff\('ceo', dr->>'seat', 'ceo\.directive'/);
  assert.match(act, /nullif\(d->'directive', 'null'::jsonb\)/, 'a JSON null directive would be read as present again');
  assert.match(code, /'ceo\.directive', 'ceo', s[\s\S]*'fn_seat_takes_ceo_directive', interval '1 hour', true/,
    'ceo.directive is not registered with the read-only handler and originator_closes');
  const fu = fnBody('fn_ceo_plan_followup');
  assert.match(fu, /set_config\('qd\.handoff_closer', 'ceo', true\)/);
  assert.match(fu, /p_now > \(a\.detail->>'due_at'\)::timestamptz/, 'an overdue directive is no longer closed as missed');
  const handler = fnBody('fn_seat_takes_ceo_directive').replace(/--[^\n]*/g, '');
  assert.doesNotMatch(handler, /\b(insert|update|delete)\b/i, 'the directive handler writes: it must only read and reply');
  // 22 Sep 2026 (instruction 721): marketing is directed like every other seat, owns the demand stage, and the plan
  // reads its daily report. Each fails if the marketing seat is dropped from the plan again.
  assert.match(code, /from unnest\(array\[[^\]]*'marketing'\]\) s/, 'ceo.directive does not reach the marketing seat');
  assert.match(fnBody('fn_ceo_plan_decide'), /when 'demand' then 'marketing'/, 'the demand stage is not owned by marketing');
  assert.doesNotMatch(fnBody('fn_ceo_plan_decide'), /v_lever := 'unowned'/, 'the demand stage is unowned again');
  assert.match(handler, /when 'demand' then/, 'the directive handler names no duty for the demand stage');
  assert.match(fnBody('fn_ceo_plan_tick'), /'marketing_report',[\s\S]*from public\.marketing_report/, 'the plan no longer reads the marketing report');
  assert.match(fnBody('fn_ceo_judgement_request'), /'marketing', p\.funnel->'marketing_report'/, 'the model no longer sees the marketing report');
});

test('E. the model slot is bounded, validated, and second to plan C', () => {
  const c = fnBody('fn_ceo_judgement_contract');
  for (const w of ['may not move money', 'change a supplier or customer record', 'message a customer, a supplier or the founder',
                   'are not yours to propose or mention', 'Choose exactly one option id'])
    assert.ok(c.includes(w), `the contract lost: ${w}`);
  assert.doesNotMatch(c, /propose such a change in founder_decision/, 'the contract invites the model to propose a campaign or cap change');
  const acc = fnBody('fn_ceo_judgement_accept');
  assert.match(acc, /option_id is not one of the options/);
  assert.match(acc, /~\* public\.fn_ceo_founder_text_forbidden\(\)/, 'a founder_decision about the campaign would be accepted');
  assert.match(acc, /a directive is outside the contract/);
  assert.match(acc, /plan_c_stands/);
  const tick = fnBody('fn_ceo_plan_tick');
  assert.ok(tick.indexOf('fn_ceo_plan_act') < tick.indexOf('fn_ceo_judgement_request'), 'plan C must act before the model is asked');
  assert.match(tick, /'call_model', v_funnel->'gates'->>'ceo_model_slot' = 'on'/, 'the model is called without the founder\'s slot');
});

test('F. the founder brief carries the plan in item 7', () => {
  const brief = readFileSync(path.join(REPO, 'scripts/sql/the_founder_brief_says_seven_things_in_plain_words.sql'), 'utf8');
  assert.match(brief, /v_plan := public\.fn_ceo_plan_brief_lines\(\) \|\| v_plan;/);
});

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

test('G. the decision names the right lever and escalates a stall (pure, replayed in pg_temp)', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const fn = fnBody('fn_ceo_plan_decide').replace('public.fn_ceo_plan_decide', 'pg_temp.fn_ceo_plan_decide');
  const zero = `jsonb_build_object('invitations_delivered',0,'registrations_submitted',0,'registrations_verified',0,'inquiries_posted',0,'quote_coverage_pct',null,'reveals_paid',0,'fee_aed',0)`;
  const f = (on, date) => `jsonb_build_object('local_date','${date}','day_of_month',15,'days_in_month',31,
      'gates', jsonb_build_object('invite_enabled',${on},'supplier_outreach_golive',${on},'invite_daily_cap',50),
      'month_to_date', ${zero}, 'last_7_days', ${zero},
      'state', jsonb_build_object('bounce_pct_7d',1,'stranded_submissions',0))`;
  const target = `jsonb_build_object('invites',1100,'registered',45,'verified',30,'inquiries',10,'reveals',1,'fee_aed',1500)`;
  const prev = `jsonb_build_object('stage','invitations','constraint_since','2000-01-10')`;
  const query = fn + `\nselect pg_temp.fn_ceo_plan_decide(${f(false, '2000-01-10')}, ${target}, null) as off,
    pg_temp.fn_ceo_plan_decide(${f(true, '2000-01-10')}, ${target}, null) as seat,
    pg_temp.fn_ceo_plan_decide(${f(true, '2000-01-18')}, ${target}, ${prev}) as l2,
    pg_temp.fn_ceo_plan_decide(${f(true, '2000-01-25')}, ${target}, ${prev}) as l3;`;
  const r = await fetch('https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/database/query', {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }, body: JSON.stringify({ query }),
  });
  const rows = await r.json();
  assert.ok(r.ok, `query failed: ${r.status} ${JSON.stringify(rows)}`);
  const [{ off, seat, l2, l3 }] = rows;
  assert.equal(off.stage, 'invitations'); assert.equal(off.lever, 'founder_reserved'); assert.equal(off.directive, null);
  assert.equal(off.founder_line, null, 'a closed campaign gate must be held silently (instruction 636)');
  assert.equal(seat.lever, 'seat'); assert.equal(seat.directive.seat, 'sales_engineer'); assert.equal(seat.directive.due_days, 7);
  assert.equal(l2.stalled, true); assert.equal(l2.level, 2); assert.equal(l2.directive.due_days, 3); assert.equal(l2.plan_c_choice, 'escalate');
  assert.equal(l3.level, 3); assert.equal(l3.founder_line, null, 'the invitation stage never reaches the founder, even at level 3');
});

// H. FOUNDER-FACING TEXT (instructions 636, 639, 22 Sep 2026). The founder is never asked or reminded about
//    the campaign go, the invitation switches, caps or warm-up, subscriptions, and is never told about a
//    seat that does not exist. Replayed live over every lever the decision can take, then every source of
//    founder-facing text in the repository is scanned for the reserved subjects.
const SEATS = ['ceo', 'customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing'];
const FORBIDDEN = /(switched off|switch them|campaign|\bgate\b|go[- ]?live|invite_enabled|\bcaps?\b|ceiling|warm[- ]?up|subscription)/i;

test('H. no founder-facing text raises the campaign, caps, subscriptions or a seat that does not exist', async (t) => {
  // the pattern the database enforces is the pattern this test enforces
  const fbd = fnBody('fn_ceo_founder_text_forbidden');
  for (const w of ['switched off', 'campaign', 'go[- ]?live', 'caps?', 'warm[- ]?up', 'subscription'])
    assert.ok(fbd.includes(w), `fn_ceo_founder_text_forbidden lost ${w}`);
  // 22 Sep 2026 (instruction 721): the marketing seat exists, so its name is no longer a reserved word. The rule that
  // replaced it is seat-aware: only an ACTIVE seat can be directed or named in a brief line.
  assert.doesNotMatch(fbd, /marketing/, 'the founder-text filter still drops every line that says marketing (rule 641 is superseded by 721)');
  assert.match(fnBody('fn_ceo_plan_brief_lines'), /r.role_id = a.agent and r.status = 'active'/, 'brief lines may name a seat that is not active');
  assert.match(fnBody('fn_ceo_judgement_accept'), /r.role_id = dd->>'seat' and r.status = 'active'/, 'the model may direct a seat that is not active');
  assert.match(fnBody('fn_ceo_plan_brief_lines'), /x !~\* public\.fn_ceo_founder_text_forbidden\(\)/, 'brief lines are not filtered');

  // static: the founder-facing literals in the brief and in the plan's decision
  const brief = readFileSync(path.join(REPO, 'scripts/sql/the_founder_brief_says_seven_things_in_plain_words.sql'), 'utf8');
  // the text the founder reads: item 7's lines and the words of the brief (not delivery error strings)
  const item7 = brief.slice(brief.indexOf('-- 7. THE PLAN FOR TOMORROW'), brief.indexOf("'window_from', p_from"));
  const words = (brief.match(/create or replace function public\.fn_founder_brief_text\([\s\S]*?\$fn\$;/) || [''])[0];
  assert.ok(item7.length > 100 && words.length > 100, 'the brief text or its item 7 could not be located');
  const briefLits = ((item7 + words).replace(/--[^\n]*/g, '').match(/'(?:[^']|'')*'/g) || []).filter((s) => / /.test(s));
  const bad = briefLits.filter((s) => FORBIDDEN.test(s));
  assert.deepEqual(bad, [], 'the founder brief carries a reserved subject: ' + bad.join(' | '));
  const decide = fnBody('fn_ceo_plan_decide').replace(/--[^\n]*/g, '');
  const founderAssigns = decide.match(/v_founder := [\s\S]*?;/g) || [];
  for (const a of founderAssigns) assert.doesNotMatch(a, FORBIDDEN, 'a founder line raises a reserved subject: ' + a);

  if (!token) { t.skip('no management token for the live replay'); return; }
  const fn = [fnBody('fn_ceo_plan_decide').replace('public.fn_ceo_plan_decide', 'pg_temp.fn_ceo_plan_decide')].join('\n');
  const z = (o = {}) => `jsonb_build_object('invitations_delivered',${o.i ?? 0},'registrations_submitted',${o.r ?? 0},'registrations_verified',${o.v ?? 0},'inquiries_posted',${o.q ?? 0},'quote_coverage_pct',null,'reveals_paid',0,'fee_aed',0)`;
  const f = (on, date, cap, mtd) => `jsonb_build_object('local_date','${date}','day_of_month',15,'days_in_month',31,
      'gates', jsonb_build_object('invite_enabled',${on},'supplier_outreach_golive',${on},'invite_daily_cap',${cap}),
      'month_to_date', ${mtd}, 'last_7_days', ${z()}, 'state', jsonb_build_object('bounce_pct_7d',1,'stranded_submissions',0))`;
  const tg = `jsonb_build_object('invites',2200,'registered',90,'verified',65,'inquiries',70,'reveals',30,'fee_aed',45000)`;
  const prev = (s) => `jsonb_build_object('stage','${s}','constraint_since','2000-01-10')`;
  const cases = {
    gate_closed: `${f(false, '2000-01-25', 50, z())}, ${tg}, ${prev('invitations')}`,
    cap_short: `${f(true, '2000-01-25', 50, z())}, ${tg}, ${prev('invitations')}`,
    demand_marketing: `${f(true, '2000-01-25', 100, z({ i: 5000, r: 500, v: 500 }))}, ${tg}, ${prev('demand')}`,
    reveals_l3: `${f(true, '2000-01-25', 100, z({ i: 5000, r: 500, v: 500, q: 500 }))}, ${tg}, ${prev('reveals')}`,
  };
  const query = fn + '\nselect ' + Object.entries(cases).map(([k, a]) => `pg_temp.fn_ceo_plan_decide(${a}) as ${k}`).join(', ') + ';';
  const r = await fetch('https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/database/query', {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }, body: JSON.stringify({ query }),
  });
  const rows = await r.json();
  assert.ok(r.ok, `query failed: ${r.status} ${JSON.stringify(rows)}`);
  const [d] = rows;
  assert.equal(d.gate_closed.founder_line, null, 'a closed campaign gate reached the founder');
  assert.equal(d.cap_short.founder_line, null, 'the invitation cap reached the founder');
  // the demand stage is the marketing seat's (instruction 721): a directive to marketing, and a 15-day stall reaches the brief naming it
  assert.equal(d.demand_marketing.lever, 'seat', 'the demand stage has no owner again');
  assert.equal(d.demand_marketing.directive.seat, 'marketing', 'the demand stage is not directed to marketing');
  assert.match(d.demand_marketing.founder_line || '', /marketing was directed/, 'a stalled demand stage does not name its seat to the founder');
  assert.ok(d.reveals_l3.founder_line, 'a seat-movable 15-day stall must still reach the brief');
  for (const [k, v] of Object.entries(d)) {
    const line = v.founder_line || '';
    assert.doesNotMatch(line, FORBIDDEN, `${k}: the founder line raises a reserved subject: ${line}`);
    for (const m of line.matchAll(/\b([a-z]+_[a-z_]+)\b/g)) assert.ok(SEATS.includes(m[1]), `${k}: the founder line names ${m[1]}, not a seat in org_agents`);
  }
});
