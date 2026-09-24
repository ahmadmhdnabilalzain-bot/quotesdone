// A HANDOFF WAITING MORE THAN A DAY IS A FINDING, EVEN WHEN ITS PROBLEM IS STILL OPEN.
//
// scripts/sql/a_handoff_waiting_more_than_a_day_is_a_finding.sql. Runs the file inside ONE transaction that ends
// in raise exception 'CHK<<...>>', with an invented open finding and a replied it.finding handoff to the ceo
// handed over 25 hours ago, so nothing is kept. This fails when fn_it_handoff_sla_items does not raise
// 'open_over_24h' for it (the 23 Sep 2026 case: 22 answered handoffs at the CEO matched no state at all),
// or raises it for the same handoff at 23 hours.
//
//   node --test scripts/checks/a_handoff_waiting_more_than_a_day_is_a_finding.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/a_handoff_waiting_more_than_a_day_is_a_finding.sql';
const ddl = readFileSync(join(REPO, FILE), 'utf8').split('\n-- PROBE')[0];

// A production probe: CI's checks job has no management token, so it skips there (the credential job runs it).
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('a replied it.finding handoff whose finding is still open is a finding after 24 hours, not before', { skip: hasToken ? false : 'no management token' }, async () => {
  const body = `do $p$ declare hid bigint; k text := 'zz:test:handoff_sla_24h'; o jsonb := '{}'; begin
      insert into public.it_engineer_finding (issue_key, title, where_it_is, blast, affected, evidence, raised_by, started_at, last_seen_at)
      values (k, 'test finding', 'test', 'monitor', 1, '{}'::jsonb, 'it_engineer', now() - interval '26 hours', now());
      insert into public.agent_actions (agent, kind, status, title, detail, created_at)
      values ('ceo', 'handoff', 'pending', 'it.finding test handoff',
              jsonb_build_object('type', 'it.finding', 'from', 'it_engineer', 'to', 'ceo', 'issue_key', k,
                                 'replied_at', now() - interval '24 hours', 'occurrence_started_at', now() - interval '26 hours'),
              now() - interval '25 hours') returning id into hid;
      o := o || jsonb_build_object('at25h', (select count(*) from jsonb_array_elements(public.fn_it_handoff_sla_items()) e
                                              where e->>'item' = 'it.finding:ceo:open_over_24h' and e->'evidence'->'handoff_ids' @> to_jsonb(hid)));
      update public.agent_actions set created_at = now() - interval '23 hours' where id = hid;
      o := o || jsonb_build_object('at23h', (select count(*) from jsonb_array_elements(public.fn_it_handoff_sla_items()) e
                                              where e->'evidence'->'handoff_ids' @> to_jsonb(hid)));
      raise exception 'CHK<<%>>', o;
    end $p$;`;
  let r;
  try { await sql('begin;\n' + ddl + '\n' + body); } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw e;
    r = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(r, 'the probe must end in CHK');
  assert.equal(Number(r.at25h), 1, 'a day-old answered handoff on an open finding is reported');
  assert.equal(Number(r.at23h), 0, 'not before the day is up');
});
