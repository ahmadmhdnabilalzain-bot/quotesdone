// RETIRED 22 Sep 2026 WITH ITS SUBJECT (it_engineer, founder instruction 642). It asserted an IT digest
// every tick, at most one an hour, of kind it_new_bug at level high (email + WhatsApp). The founder ruled
// that too often: the digest now leaves once a day at 19:00 Dubai, email only, kind it_daily_digest, and
// no routine may send it_new_bug to him. Guarded by the_founder_hears_from_it_once_a_day.test.mjs.
// Kept for its history; nothing runs it.
//
// THE FOUNDER GETS ONE IT DIGEST PER TICK, NOT ONE EMAIL PER FINDING.
//
// Measured 15 Sep 2026: one duty raised ~50 findings in one tick and the founder got 45 separate
// emails (55 requests in one minute; 111 more rows skipped by hand). scripts/sql/the_founder_gets_one_it_digest_per_tick.sql
// holds every founder it_new_bug request and sends them as one digest.
//
// Statically (runs in CI without a token), on the CANONICAL body of each routine (the last file in
// scripts/sql/MANIFEST.txt that defines it):
//   * support's handler holds an it_new_bug request before it can reach fn_notify_founder;
//   * the digest routine is the ONLY routine that passes kind it_new_bug to fn_notify_founder;
//   * the IT tick sends the digest.
// Against production (skipped without a token, or until the file is applied), ONE aborted transaction --
// a pure probe, no DDL, ZZ DEMO subjects, the founder stub on -- proves: five requests are held, one
// digest completes all five with one key, a family of four reads as one line with its count, a second
// run finds nothing, the 60-minute floor holds the next one, and 0 rows reached the founder.
//
//   node --test scripts/checks/the_founder_gets_one_it_digest_per_tick.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../../..', import.meta.url));
const manifest = readFileSync(join(REPO, 'scripts', 'sql', 'MANIFEST.txt'), 'utf8')
  .split(/\r?\n/).map((l) => l.trim()).filter((l) => l.endsWith('.sql') && !l.startsWith('#'));

// name -> { file, body } from the LAST defining file in apply order.
const canonical = new Map();
for (const f of manifest) {
  const p = join(REPO, f);
  if (!existsSync(p)) continue;
  const src = readFileSync(p, 'utf8');
  for (const m of src.matchAll(/create or replace function public\.(\w+)\s*\(/gi)) {
    const end = src.indexOf('$fn$;', m.index);
    canonical.set(m[1].toLowerCase(), { file: f, body: src.slice(m.index, end < 0 ? undefined : end) });
  }
}
const body = (n) => {
  const c = canonical.get(n);
  assert.ok(c, `${n} is defined by no file in MANIFEST.txt`);
  return c.body;
};

test('support holds a founder it_new_bug request before anything can notify him', () => {
  const b = body('fn_customer_support_acts_on_handoff');
  const hold = b.search(/d->>'kind'\s*=\s*'it_new_bug'/);
  const send = b.indexOf('fn_notify_founder(');
  assert.ok(hold > 0, 'the canonical handler has no it_new_bug hold');
  assert.ok(send > hold, 'the it_new_bug hold must come before the fn_notify_founder call');
  assert.match(b.slice(hold, send), /'waiting'/, "the hold must answer 'waiting' so the request stays pending");
});

test('only the digest passes kind it_new_bug to fn_notify_founder', () => {
  const callers = [...canonical.entries()]
    .filter(([n, c]) => n !== 'fn_notify_founder' && /fn_notify_founder\s*\(/.test(c.body)
      && /p_kind\s*=>\s*'it_new_bug'/.test(c.body))
    .map(([n]) => n);
  assert.deepEqual(callers, ['fn_customer_support_sends_the_it_digest']);
});

test('the IT tick sends the digest', () => {
  assert.match(body('fn_it_loop_tick'), /fn_customer_support_sends_the_it_digest\(\)/);
  assert.match(body('fn_it_loop_tick'), /'digest'\]/, "the tick must report its 'digest' stage");
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

const PROBE = `
do $p$
declare v jsonb; w jsonb; v_max bigint; k int; j int; i int;
begin
  perform set_config('app.qd_stub_founder_notify', 'on', true);
  select coalesce(max(id), 0) into v_max from public.notifications;
  for i in 1..5 loop
    perform public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'support_ceo_report', 'zz-demo-digest-probe-' || i,
      jsonb_build_object('recipient_role', 'founder', 'kind', 'it_new_bug', 'level', 'high',
        'event', 'New problem the IT engineer could not fix: ZZ DEMO ' || case when i < 5 then 'not backed up zz_demo.col' || i else 'detector' end,
        'detail', 'ZZ DEMO probe row',
        'dedupe_key', case when i < 5 then 'it_new_bug:duty:zz_demo_backup_gap:zz_demo.col' || i else 'it_new_bug:watch:zz_demo_detector' end));
  end loop;
  -- A problem he was already told about within 24 hours is folded, never told twice.
  insert into public.founder_alerts (level, event, detail, channel, dedupe_key, created_at)
  values ('high', 'ZZ DEMO already told', 'ZZ DEMO', 'digested', 'it_new_bug:zz_demo_told:x', now() - interval '1 hour');
  perform public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'support_ceo_report', 'zz-demo-digest-probe-d',
    jsonb_build_object('recipient_role', 'founder', 'kind', 'it_new_bug', 'level', 'high',
      'event', 'New problem the IT engineer could not fix: ZZ DEMO told', 'detail', 'ZZ DEMO', 'dedupe_key', 'it_new_bug:zz_demo_told:x'));
  select count(*) into k from public.agent_actions
   where kind = 'handoff' and target_id like 'delivery.request:zz-demo-digest-probe-%' and status = 'pending' and evidence->>'digest' = 'pending';
  if k <> 6 then raise exception 'ZZFAIL: % of 6 requests were held for the digest', k; end if;

  v := public.fn_customer_support_sends_the_it_digest(interval '0');
  if not exists (select 1 from public.agent_actions where target_id = 'delivery.request:zz-demo-digest-probe-d'
                  and status = 'done' and evidence->>'digest' = 'deduped')
     or (v->>'deduped')::int < 1 or v->>'detail' ~ 'zz_demo_told' then
    raise exception 'ZZFAIL: a problem told within 24 hours was not folded: %', v;
  end if;
  select count(*), count(distinct evidence->>'digest_key') into k, j from public.agent_actions
   where kind = 'handoff' and target_id like 'delivery.request:zz-demo-digest-probe-%' and status = 'done'
     and evidence->>'digest' = 'sent' and coalesce((evidence->>'stubbed')::boolean, false);
  if k <> 5 or j <> 1 then raise exception 'ZZFAIL: one digest did not complete all five (% done, % keys): %', k, j, v; end if;
  if v->>'event' !~ ' new problems the IT engineer could not fix$' then raise exception 'ZZFAIL: digest subject %', v->>'event'; end if;
  if (v->>'lines')::int <= 15 and (v->>'detail' !~ '4 problems of one kind, duty:zz_demo_backup_gap' or v->>'detail' !~ 'watch:zz_demo_detector') then
    raise exception 'ZZFAIL: the family is not one counted line: %', v->>'detail';
  end if;
  w := public.fn_customer_support_sends_the_it_digest(interval '0');
  if (w->>'held')::int <> 0 then raise exception 'ZZFAIL: a second run found held requests: %', w; end if;

  insert into public.founder_alerts (level, event, detail, channel, dedupe_key, created_at)
  values ('high', 'ZZ DEMO probe digest', 'ZZ DEMO', 'email', 'it_new_bug_digest:zz-demo', now() - interval '10 minutes');
  perform public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'support_ceo_report', 'zz-demo-digest-probe-6',
    jsonb_build_object('recipient_role', 'founder', 'kind', 'it_new_bug', 'level', 'high',
      'event', 'New problem the IT engineer could not fix: ZZ DEMO later', 'detail', 'ZZ DEMO', 'dedupe_key', 'it_new_bug:duty:zz_demo_other:x'));
  w := public.fn_customer_support_sends_the_it_digest();
  if coalesce((w->>'sent')::boolean, true) or (w->>'held')::int < 1 then raise exception 'ZZFAIL: the 60-minute floor did not hold: %', w; end if;

  select count(*) into k from public.notifications
   where id > v_max and (to_role in ('founder', 'admin', 'owner') or type = 'founder_alert');
  if k <> 0 then raise exception 'ZZFAIL: % row(s) were queued to the founder', k; end if;
  raise exception 'CHK<<%>>', jsonb_build_object('digest_event', v->>'event', 'lines', v->'lines', 'problems', v->'problems',
                                                 'floor', w, 'founder_rows', k)::text;
end $p$;`;

test('production: one digest for many held requests, and nothing reaches the founder', { skip: hasToken ? false : 'no Supabase management token' }, async (t) => {
  const { sql } = await import('../../lib/db.mjs');
  const live = await sql(`select to_regprocedure('public.fn_customer_support_sends_the_it_digest(interval)') is not null as live`);
  if (!live?.[0]?.live) { t.skip('the_founder_gets_one_it_digest_per_tick.sql is not applied yet'); return; }
  let message = '';
  try { await sql(PROBE); message = 'the probe returned without raising, so it did not roll back'; } catch (e) { message = String(e.message); }
  const chk = message.match(/CHK<<([\s\S]*?)>>/);
  assert.ok(chk, message.slice(0, 1500));
  const out = JSON.parse(chk[1].replace(/\\"/g, '"'));
  assert.equal(out.founder_rows, 0);
  assert.equal(out.problems, 5);
});
