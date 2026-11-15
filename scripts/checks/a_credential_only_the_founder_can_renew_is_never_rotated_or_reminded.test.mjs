// A CREDENTIAL ONLY THE FOUNDER CAN RENEW IS NEVER ROTATED OR REMINDED (founder ruling, ledger 1090, 30 Sep 2026).
//
// scripts/sql/a_credential_only_the_founder_can_renew_is_never_rotated_or_reminded.sql, applied inside ONE transaction
// that ends in raise exception 'CHK<<...>>', so nothing is kept. Founder mail is stubbed (app.qd_stub_founder_notify)
// and every fixture is ZZ DEMO: a founder-required credential and a company_api one, neither a real secret.
// Fails when:
//   1. the renewal watch hands, escalates or reminds anyone about a founder-required credential near expiry;
//   2. the integration settle would mail the founder (integration_reauth_needed) about a refused founder credential;
//   3. the 19:00 IT digest would carry a line about one;
//   4. anything claims a rotation of a founder-required credential;
//   5. a real outage (HTTP 503) on the same integration is silenced - it must still take the founder path;
//   6. the company-rotated Twilio key stops being due on its 90-day schedule;
//   7. any live routine that sends kind integration_reauth_needed, or the digest, or the renewal watch, stops
//      asking fn_it_credential_founder_required first (the notice coming back by a rewrite).
//
//   node --test scripts/checks/a_credential_only_the_founder_can_renew_is_never_rotated_or_reminded.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';
import { replaySql } from '../lib/safe_replay.mjs';   // a rolled-back probe goes through the replay guard (13 Nov 2026)

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/a_credential_only_the_founder_can_renew_is_never_rotated_or_reminded.sql';
const ddl = readFileSync(join(REPO, FILE), 'utf8').split('\n-- ── VERDICT')[0];
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('the file routes every founder-facing credential path through the classifier', () => {
  for (const fn of ['fn_it_integration_settle', 'fn_customer_support_sends_the_it_digest', 'fn_it_renewal_watch']) {
    const body = ddl.split(`function public.${fn}(`)[1]?.split('end $fn$;')[0] || '';
    assert.ok(body, `${FILE} must define ${fn}`);
    assert.match(body, /fn_it_credential_founder_required\(/, `${fn} must ask fn_it_credential_founder_required first`);
  }
});

test('no live routine pages the founder about a founder-required credential', { skip: hasToken ? false : 'no management token' }, async () => {
  const rows = await sql(`select p.proname,
      pg_get_functiondef(p.oid) like '%fn_it_credential_founder_required(%' asks
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f'
     and (pg_get_functiondef(p.oid) like '%''integration_reauth_needed''%'
          or p.proname in ('fn_customer_support_sends_the_it_digest', 'fn_it_renewal_watch'))
     and p.proname <> 'fn_it_credential_founder_required'`);
  const names = rows.map((r) => r.proname);
  assert.ok(names.includes('fn_it_renewal_watch') && names.includes('fn_customer_support_sends_the_it_digest'));
  const silent = rows.filter((r) => !r.asks).map((r) => r.proname);
  // Until the file is applied at merge the live bodies are the old ones; the probe below proves the new ones.
  const applied = (await sql(`select to_regclass('public.it_credential_class') is not null ok`))[0].ok;
  if (applied) assert.deepEqual(silent, [], `these routines can page the founder without asking the classifier: ${silent}`);
});

test('ZZ DEMO: founder-required near expiry -> 0 notices, 0 rotations; outage still paged; Twilio still rotates', { skip: hasToken ? false : 'no management token' }, async () => {
  const body = `do $p$ declare o jsonb := '{}'; r jsonb; v_fa bigint; v_n bigint; v_h bigint; v_now timestamptz; v_base bigint;
    begin
      perform set_config('app.qd_stub_founder_notify', 'on', true);
      select count(*) into v_fa from public.founder_alerts;
      select count(*) into v_n from public.notifications;
      insert into public.it_credential_class (credential, rotation, integrations, expiry_item, why) values
        ('zz_demo_founder_key', 'founder_required', '{zz_demo_founder}', 'key:zz_demo_founder_key', 'ZZ DEMO: console-only'),
        ('zz_demo_api_key', 'company_api', '{zz_demo_api}', null, 'ZZ DEMO: provider API');
      insert into public.it_expiry (item, kind, owner_seat, route, expires_on, warn_days, source, never_expires)
      values ('key:zz_demo_founder_key', 'token', 'accountant', 'ZZ DEMO', current_date + 5, '{60,30}', 'ZZ DEMO', false);

      -- 1. the renewal watch, twice (a second tick must not escalate either)
      perform public.fn_it_renewal_watch(); perform public.fn_it_renewal_watch();
      select count(*) into v_h from public.agent_actions where kind = 'handoff' and detail->>'item' = 'key:zz_demo_founder_key';
      o := o || jsonb_build_object('renewal_handoffs', v_h,
        'ceo_reports', (select count(*) from public.support_ceo_report where idempotency_key like 'renewal:key:zz_demo_founder_key@%'),
        'renewal_finding_silent', (select (evidence->>'founder_required_credential')::boolean from public.it_engineer_finding
                                    where issue_key = 'duty:renewal:key:zz_demo_founder_key' and closed_at is null));

      -- 2. the integration settle, two beats: a refused key and, on the same integration, a real outage
      r := '[{"item":"zz_demo_founder","title":"zz_demo_founder (ZZ DEMO): answered HTTP 401: invalid api key. Tried: nothing","owner_seat":"it_engineer","blast":"agent_facing","affected":1,"evidence":{"integration":"zz_demo_founder","what_broke":"answered HTTP 401: invalid api key"}},
           {"item":"zz_demo_founder:outage","title":"zz_demo_founder (ZZ DEMO): answered HTTP 503. Tried: retried","owner_seat":"it_engineer","blast":"agent_facing","affected":1,"evidence":{"integration":"zz_demo_founder","what_broke":"answered HTTP 503"}}]';
      perform public.fn_it_integration_settle('integration', r);
      r := public.fn_it_integration_settle('integration', r);
      o := o || jsonb_build_object(
        'mailed_refusal', (select count(*) from jsonb_array_elements(r->'mailed') m where m->>'key' = 'duty:integration:zz_demo_founder'),
        'mailed_outage', (select count(*) from jsonb_array_elements(r->'mailed') m where m->>'key' = 'duty:integration:zz_demo_founder:outage'),
        'refusal_recorded', (select (evidence->>'founder_required_credential')::boolean from public.it_engineer_finding
                              where issue_key = 'duty:integration:zz_demo_founder' and closed_at is null));

      -- 3. the digest, at 20:00 Dubai two days on, with the refusal waiting for it
      update public.it_engineer_finding set started_at = now() - interval '3 days' where issue_key = 'duty:integration:zz_demo_founder';
      insert into public.agent_actions (agent, kind, status, detail, evidence)
      values ('customer_support', 'handoff', 'pending',
              jsonb_build_object('type', 'delivery.request', 'recipient_role', 'founder', 'kind', 'it_new_bug', 'from', 'ceo', 'to', 'customer_support',
                                 'dedupe_key', 'it_new_bug:duty:integration:zz_demo_founder',
                                 'subject_table', 'it_engineer_finding', 'subject_id', 'duty:integration:zz_demo_founder'),
              jsonb_build_object('digest', 'pending'));
      v_now := ((current_date + 2)::timestamp + time '20:00') at time zone 'Asia/Dubai';
      r := public.fn_customer_support_sends_the_it_digest(v_now);
      o := o || jsonb_build_object('digest_mentions', coalesce(r->>'detail', '') like '%zz_demo_founder%',
        'digest_verdict', (select evidence->>'digest' from public.agent_actions
                            where kind = 'handoff' and detail->>'dedupe_key' = 'it_new_bug:duty:integration:zz_demo_founder'));

      -- 4. no rotation attempt of the founder-required credential; 6. Twilio still due on schedule
      o := o || jsonb_build_object('founder_claim', public.fn_it_provider_rotation_claim('zz_demo_founder')->'due',
        'founder_claims_logged', (select count(*) from public.agent_runs where counts->>'job' = 'provider_rotation_claim' and counts->>'provider' = 'zz_demo_founder'));
      delete from public.it_credential_rotation where provider = 'twilio';
      delete from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'provider_rotation_claim' and counts->>'provider' = 'twilio';
      v_base := public.fn_it_provider_rotation_baseline('twilio', 'SKzzdemo', now() - interval '91 days');
      o := o || jsonb_build_object('twilio_due', public.fn_it_provider_rotation_claim('twilio')->'due');

      o := o || jsonb_build_object('founder_alerts_added', (select count(*) from public.founder_alerts) - v_fa,
                                   'notifications_added', (select count(*) from public.notifications) - v_n);
      raise exception 'CHK<<%>>', o;
    end $p$;`;
  let r;
  try { await replaySql('begin;\n' + ddl + '\n' + body, { label: 'the credential-class probe' }); } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw e;
    r = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(r, 'the probe must end in CHK');
  assert.equal(Number(r.renewal_handoffs), 0, 'no renewal handoff for a founder-required credential');
  assert.equal(Number(r.ceo_reports), 0, 'no CEO escalation for a founder-required credential');
  assert.equal(r.renewal_finding_silent, true, 'the state stays visible as a silent IT engineer finding');
  assert.equal(Number(r.mailed_refusal), 0, 'no integration_reauth_needed mail for a refused founder credential');
  assert.equal(r.refusal_recorded, true, 'the refusal is still recorded');
  assert.equal(Number(r.mailed_outage), 1, 'a real outage on the same integration still takes the founder path');
  assert.equal(r.digest_mentions, false, 'the IT digest carries no line about it');
  assert.equal(r.digest_verdict, 'internal', 'its digest handoff is closed internal');
  assert.equal(r.founder_claim, false, 'a founder-required credential is never claimed for rotation');
  assert.equal(Number(r.founder_claims_logged), 0, 'no rotation attempt is logged');
  assert.equal(r.twilio_due, true, 'the company-rotated Twilio key is still due at 91 days');
  assert.equal(Number(r.founder_alerts_added), 0, 'no founder alert row');
  assert.equal(Number(r.notifications_added), 0, 'no notification row');
});
