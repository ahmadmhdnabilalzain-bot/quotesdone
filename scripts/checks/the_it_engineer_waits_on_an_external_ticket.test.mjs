// THE IT ENGINEER WAITS ON A PROVIDER'S TICKET INSTEAD OF ASKING THE FOUNDER, AND ITS MAIL IS ITS OWN.
//
// it_engineer, 24 Sep 2026, founder instruction 979. The integration watch's first live mail (notification
// 64992) told the founder to bring the WhatsApp sender back ONLINE in the Twilio console. He cannot: Twilio
// lost the sender's WABA link on its side and holds ticket 29665983. Two defects, one test each:
//   1. A KNOWN EXTERNAL CAUSE (public.it_integration_external_cause) keeps the finding open and OFF his mail and
//      his digest; he is mailed once, only when the provider replied AND the reply asks something of him; the
//      cause closes itself when the integration answers again. Proved in ONE transaction that always rolls
//      back (ZZ PROBE subjects, the founder stub on, 0 notification rows).
//   2. THE MAIL IS THE IT ENGINEER'S: customer_support is the only sender by the founder's 14 Sep ruling
//      (CHECK notifications_sender_is_customer_support), so the seat of record is requested_by, which must
//      resolve to it_engineer for the kind, and the subject must say the IT engineer is asking.
//
//   node --test scripts/checks/the_it_engineer_waits_on_an_external_ticket.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FILE = 'scripts/sql/the_it_engineer_watches_every_integration_and_fixes_what_it_can.sql';
const SRC = readFileSync(join(REPO, FILE), 'utf8');
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token';

test('every founder mail the integration watch sends says the IT engineer is asking', () => {
  const events = [...SRC.matchAll(/p_event\s*=>\s*'([^']*)'/g)].map((m) => m[1]);
  assert.ok(events.length >= 2, 'the settle routine no longer calls fn_notify_founder');
  for (const e of events) assert.match(e, /^IT engineer: /);
});

test('production: the kind resolves to it_engineer as the seat of record', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const [r] = await sql(`select public.fn_channel_requester('founder_alert', 'integration_reauth_needed') as who,
    (select owner_role from public.founder_mail_policy where kind = 'integration_reauth_needed') as owner`);
  assert.equal(r.who, 'it_engineer');
  assert.equal(r.owner, 'it_engineer');
});

const PROBE = `
do $p$
declare b1 jsonb; b2 jsonb; b3 jsonb; b4 jsonb; b5 jsonb; v_max bigint; v_cls_open boolean; v_cls_after boolean; v_closed timestamptz;
  it jsonb := jsonb_build_array(jsonb_build_object('item','zz_probe_ext','owner_seat','it_engineer','subject','zz_probe_ext','blast','internal',
    'affected',1,'title','ZZ PROBE provider-side outage','evidence',jsonb_build_object('integration','zz_probe_ext','notify',true)));
begin
  perform set_config('app.qd_stub_founder_notify', 'on', true);
  select coalesce(max(id), 0) into v_max from public.notifications;
  perform public.fn_it_external_cause_open('zz_probe_ext', 'ZZ Provider', 'ZZ-1', current_date, 'ZZ thread', 'ZZ PROBE');
  select exists (select 1 from public.it_founder_decision_class where issue_key_like = 'duty:integration%:zz_probe_ext' and not to_founder) into v_cls_open;
  b1 := public.fn_it_integration_settle('integration', it, '[]');
  b2 := public.fn_it_integration_settle('integration', it, '[]');               -- seen twice: would mail without the cause
  perform public.fn_it_external_cause_reply('zz_probe_ext', now() - interval '2 minutes', 'Ticket on hold, engineering investigating, we will update you.');
  b3 := public.fn_it_integration_settle('integration', it, '[]');
  perform public.fn_it_external_cause_reply('zz_probe_ext', now() - interval '1 minute', 'Please confirm the account owner by replying to this email.');
  b4 := public.fn_it_integration_settle('integration', it, '[]');
  b5 := public.fn_it_integration_settle('integration', it, '[]');               -- told once, not again
  perform public.fn_it_integration_settle('integration',                        -- a passing re-probe: finding and cause close
    jsonb_build_array(jsonb_build_object('item','zz_probe_ext','title','answers again','recovered',true)), '[]');
  select closed_at into v_closed from public.it_integration_external_cause where integration = 'zz_probe_ext';
  select exists (select 1 from public.it_founder_decision_class where issue_key_like = 'duty:integration%:zz_probe_ext') into v_cls_after;
  raise exception 'CHK<<%>>', jsonb_build_object('digest_off_him', v_cls_open, 'mailed', jsonb_build_array(b1->'founder_mailed', b2->'founder_mailed',
    b3->'founder_mailed', b4->'founder_mailed', b5->'founder_mailed'), 'told', b4->'mailed'->0->>'detail',
    'cause_closed', v_closed is not null, 'digest_row_removed', not v_cls_after,
    'founder_rows', (select count(*) from public.notifications where id > v_max))::text;
end $p$;`;

test('production: an open external cause keeps him out of it until the provider asks something of him', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  let message = '';
  try { await replaySql(PROBE, { retry: false }); message = 'the probe returned without raising, so it did not roll back'; } catch (e) { message = String(e.message); }
  const chk = message.match(/CHK<<([\s\S]*?)>>/);
  assert.ok(chk, message.slice(0, 1500));
  const o = JSON.parse(chk[1].replace(/\\"/g, '"'));
  assert.equal(o.digest_off_him, true, 'the open cause did not keep the digest off him');
  assert.deepEqual(o.mailed, [0, 0, 0, 1, 0], 'mailed before the provider asked, or more than once');
  assert.match(o.told, /ZZ Provider replied on ticket ZZ-1/);
  assert.match(o.told, /Please confirm the account owner/);
  assert.equal(o.cause_closed, true, 'the cause did not close when the integration recovered');
  assert.equal(o.digest_row_removed, true);
  assert.equal(o.founder_rows, 0, 'a test reached the founder');
});
