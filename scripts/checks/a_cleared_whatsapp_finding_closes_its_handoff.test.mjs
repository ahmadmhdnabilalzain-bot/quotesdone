// A CLEARED WHATSAPP FINDING CLOSES ITS HANDOFF (24 Sep 2026, it_engineer for customer_support; instruction 207).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: the whatsapp_delivery playbook class loses its prefix, its cause or its regression check; the
//     whatsapp_template class is given no cause; the file carries both (or neither of) a pending note and a MANIFEST line;
//   * production, in ONE aborted transaction (file replayed while pending; nothing commits): the playbook covers both
//     WhatsApp issue keys, and for every it.finding handoff on duty:whatsapp_delivery: parked at awaiting_learning
//     whose finding has cleared, fn_it_learning_from_playbook completes its incident, so fn_it_loop_reverify's close
//     branch takes it instead of parking it again. When no such handoff exists the second half reports 0 and passes:
//     it proves the class, not a particular row.
//
//   node --test scripts/checks/a_cleared_whatsapp_finding_closes_its_handoff.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/a_cleared_whatsapp_delivery_finding_closes_its_handoff_from_the_playbook.sql';
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));

test('static: both WhatsApp classes carry a cause and a regression check', () => {
  const src = read(FILE);
  assert.match(src, /\('whatsapp_delivery', 'duty:whatsapp_delivery:no_final_status:',[\s\S]{0,900}'scripts\/checks\/every_twilio_send_reports_its_status\.test\.mjs[\s\S]{0,200}'A WhatsApp or SMS that Twilio accepted/);
  assert.match(src, /update public\.it_playbook\s+set typical_cause = 'A WhatsApp template[\s\S]{0,400}where failure_class = 'whatsapp_template'/);
  assert.ok(existsSync(join(REPO, 'scripts/checks/every_twilio_send_reports_its_status.test.mjs')), 'the named regression check does not exist');
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  assert.ok(pending(FILE) !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: the playbook completes a parked, cleared WhatsApp handoff', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const replay = pending(FILE) ? read(FILE) : '';
  let o;
  try { await replaySql(replay + '\n' + PROBE, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.deepEqual([o.delivery_class, o.template_class], ['whatsapp_delivery', 'whatsapp_template']);
  assert.equal(o.rate_class ?? null, null, 'the no-final-report cause would be written onto a failure-rate incident');
  assert.equal(o.learned, o.parked, `${o.parked} parked WhatsApp handoff(s), ${o.learned} completed from the playbook`);
});

const PROBE = String.raw`
do $$ declare o jsonb := '{}'; h record; v_parked int := 0; v_learned int := 0;
begin
  o := o || jsonb_build_object('rate_class', (fn_it_playbook_for('duty:whatsapp_delivery:failure_rate:whatsapp')).failure_class);
  o := o || jsonb_build_object('delivery_class', (fn_it_playbook_for('duty:whatsapp_delivery:no_final_status:whatsapp')).failure_class,
                               'template_class', (fn_it_playbook_for('duty:sender:template:login_code_ar')).failure_class);
  for h in select a.id from agent_actions a
            join it_engineer_finding f on f.issue_key = a.detail->>'issue_key'
           where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status in ('pending', 'failed')
             and a.detail->>'issue_key' like 'duty:whatsapp\_delivery:no\_final\_status:%' and a.detail ? 'awaiting_learning'
             and f.closed_at is not null loop
    v_parked := v_parked + 1;
    if fn_it_learning_from_playbook(h.id) = 'whatsapp_delivery' then v_learned := v_learned + 1; end if;
  end loop;
  o := o || jsonb_build_object('parked', v_parked, 'learned', v_learned);
  raise exception 'CHK<<%>>', o::text;
end $$;
`;
