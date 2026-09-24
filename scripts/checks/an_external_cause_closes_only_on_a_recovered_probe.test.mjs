// AN EXTERNAL CAUSE CLOSES ONLY ON A RECOVERED PROBE, AND A TICKET REFERENCE IS MATCHED LITERALLY.
//
// it_engineer, 24 Sep 2026, review of #935. One test per finding, each against the NEW body of
// fn_it_integration_settle, run inside ONE transaction that always rolls back (the file itself is executed first
// in that transaction, so the probe runs the routine as written here, applied or not):
//   1. a provider reference containing % and _ matches only mail that names it literally (was an ILIKE pattern);
//   2. a finding closed WITHOUT a successful re-probe leaves the cause open; a recovered item closes it.
// Offline, the same two shapes are asserted on the source so the check still bites without a token.
//
//   node --test scripts/checks/an_external_cause_closes_only_on_a_recovered_probe.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const SRC = readFileSync(join(REPO, 'scripts/sql/an_external_cause_closes_only_on_a_recovered_probe.sql'), 'utf8');
const BODY = SRC.slice(SRC.indexOf('create or replace function'));
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token';

test('offline: the ticket reference is never concatenated into a LIKE/ILIKE pattern', () => {
  assert.doesNotMatch(BODY, /like\s+'%'\s*\|\|\s*c\.ticket_ref/i);
  assert.match(BODY, /strpos\(lower\(coalesce\(i\.subject, ''\)\), lower\(c\.ticket_ref\)\) > 0/);
});

test('offline: the cause closes only on a closed finding stamped recovered', () => {
  const at = BODY.indexOf('perform public.fn_it_external_cause_close(');
  const guard = BODY.slice(BODY.lastIndexOf('if exists', at), at);
  assert.match(guard, /closed_at is not null/);
  assert.match(guard, /\(evidence->>'recovered'\)::boolean/);
});

const PROBE = `
do $p$
declare v_open_after_sweep boolean; v_closed_after_probe boolean; v_excerpt text;
  it jsonb := jsonb_build_array(jsonb_build_object('item','zz_probe_rec','owner_seat','it_engineer','subject','zz_probe_rec','blast','internal',
    'affected',1,'title','ZZ PROBE provider-side outage','evidence',jsonb_build_object('integration','zz_probe_rec','notify',true)));
begin
  perform set_config('app.qd_stub_founder_notify', 'on', true);
  perform public.fn_it_external_cause_open('zz_probe_rec', 'ZZ Provider', 'zz_9%', current_date - 1, 'ZZ thread', 'ZZ PROBE');
  -- 1. A wildcard-shaped reference: the first mail names ZZX9Y (a pattern would match it), the second names it literally.
  insert into public.inbound_messages (subject, body, created_at) values
    ('ZZ PROBE about ZZX9Y', 'not our ticket', now() - interval '3 minutes'),
    ('ZZ PROBE re ZZ_9% update', 'the literal ticket', now() - interval '4 minutes');
  perform public.fn_it_integration_settle('integration', it, '[]');
  select last_reply_excerpt into v_excerpt from public.it_integration_external_cause where integration = 'zz_probe_rec' and closed_at is null;
  -- 2. The finding closes by a sweep with no probe having passed: the cause must stay open.
  perform public.fn_it_integration_settle('integration', '[]', '[]');
  select closed_at is null into v_open_after_sweep from public.it_integration_external_cause where integration = 'zz_probe_rec';
  -- A successful re-probe: the recovered item closes it.
  perform public.fn_it_integration_settle('integration',
    jsonb_build_array(jsonb_build_object('item','zz_probe_rec','title','answers again','recovered',true,'evidence',jsonb_build_object('recovered',true))), '[]');
  select closed_at is not null into v_closed_after_probe from public.it_integration_external_cause where integration = 'zz_probe_rec';
  raise exception 'CHK<<%>>', jsonb_build_object('excerpt', v_excerpt, 'open_after_sweep', v_open_after_sweep,
    'closed_after_probe', v_closed_after_probe,
    'finding_open', exists (select 1 from public.it_engineer_finding where issue_key = 'duty:integration:zz_probe_rec' and closed_at is null))::text;
end $p$;`;

test('production: a % and _ reference matches literally; only a recovered probe closes the cause', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  let message = '';
  try { await sql(SRC + '\n' + PROBE, { retry: false }); message = 'the probe returned without raising, so it did not roll back'; }
  catch (e) { message = String(e.message); }
  const chk = message.match(/CHK<<([\s\S]*?)>>/);
  assert.ok(chk, message.slice(0, 1500));
  const o = JSON.parse(chk[1].replace(/\\"/g, '"'));
  assert.match(o.excerpt ?? '', /the literal ticket/, 'the reply picked was not the one naming the ticket literally');
  assert.equal(o.open_after_sweep, true, 'a closure without a successful re-probe closed the external cause');
  assert.equal(o.closed_after_probe, true, 'a recovered probe did not close the external cause');
  assert.equal(o.finding_open, false, 'a recovered item was settled as a failure');
});
