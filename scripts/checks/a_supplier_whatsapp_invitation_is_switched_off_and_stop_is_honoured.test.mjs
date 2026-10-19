// A SUPPLIER WHATSAPP INVITATION IS SWITCHED OFF, STOP IS HONOURED, AND LEAD INGEST NEVER SENDS (marketing, 19 Oct 2026).
// Rulings 1184/1185/1205. Every production case runs as a rolled-back replay (scripts/lib/safe_replay.mjs).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { replaySql } from '../lib/safe_replay.mjs';

// The production cases need a management token; the checks job has none (the credential job runs them).
const SKIP = (process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'))) ? false : 'no Supabase management token in this environment';
const FILE = 'scripts/sql/a_supplier_whatsapp_invitation_is_built_switched_off_and_stop_is_honoured.sql';
const sqlText = readFileSync(FILE, 'utf8');
const gate = readFileSync('supabase/functions/_shared/marketing_send_gate.ts', 'utf8');

test('the SQL opt-out cancels exactly the marketing types send_whatsapp gates', () => {
  const ts = JSON.parse(gate.match(/MARKETING_TYPES: readonly string\[\] = (\[[^\]]*\])/)[1].replace(/'/g, '"'));
  const sq = JSON.parse('[' + sqlText.match(/type = any \(array\[([^\]]*)\]\)/)[1].replace(/'/g, '"') + ']');
  assert.deepEqual(sq, ts);
});

test('fn_lead_sourcing_record never queues a send on any channel', { skip: SKIP }, async () => {
  const [r] = await replaySql(`
    create temp table _b as select count(*) n from public.notifications;
    select public.fn_lead_sourcing_record('{"kind":"probe","emirate":"UAE","trades":["pest_control"]}'::jsonb,
      '[{"company_name":"ZZ DEMO wa probe","website":"https://zz-demo.example.invalid","domain":"zz-demo.example.invalid",
         "email":"owner@zz-demo.example.invalid","email_status":"mx_ok","phone_e164":"+971500000001","contact_name":"ZZ DEMO",
         "contact_title":"Owner","emirate":"Dubai","trade_code":"pest_control"}]'::jsonb) r;
    select (select count(*) from public.notifications) - (select n from _b) as queued,
           (select count(*) from public.leads where company_name = 'ZZ DEMO wa probe') as promoted;`, { label: 'lead ingest never sends', rows: true });
  assert.equal(Number(r.promoted), 1, 'the probe lead must be promoted, or the test measures nothing');
  assert.equal(Number(r.queued), 0);
});

test('switched off queues nothing; on queues within the cap and window; STOP cancels', { skip: SKIP }, async () => {
  const [r] = await replaySql(sqlText + `
    update public.app_secrets set value = 'true' where key = 'wa_supplier_invite_golive';
    create temp table _q as select public.fn_wa_supplier_invite_queue(50, '2026-10-20 08:00+00') a,
                                   public.fn_wa_supplier_invite_queue(50, '2026-10-24 08:00+00') sat;
    create temp table _p as select to_phone from public.notifications where type = 'supplier_invite_wa' and status = 'queued' limit 1;
    create temp table _s as select public.fn_wa_supplier_invite_opt_out('whatsapp:' || (select to_phone from _p)) s;
    select (select (a->>'queued')::int from _q) as on_queued, (select (sat->>'queued')::int from _q) as sat_queued,
           (select (s->>'invitations_cancelled')::int from _s) as cancelled,
           (select count(*) from public.leads l where l.phone_e164 = (select to_phone from _p) and l.whatsapp_opt is distinct from 'none') as still_opted_in,
           (select count(*) from public.notifications where type = 'supplier_invite_wa' and status = 'queued' and to_phone = (select to_phone from _p)) as still_queued;`,
    { label: 'whatsapp invitation switch and STOP', rows: true });
  assert.equal(r.on_queued > 0 && r.on_queued <= 20, true, 'on: 1..20 queued, got ' + r.on_queued);
  assert.equal(r.sat_queued, 0, 'never on a Saturday');
  assert.equal(r.cancelled, 1);
  assert.equal(Number(r.still_opted_in), 0);
  assert.equal(Number(r.still_queued), 0);
});

test('switched off: the first call writes nothing', { skip: SKIP }, async () => {
  const [r] = await replaySql(sqlText + `
    create temp table _b as select count(*) n from public.notifications where type = 'supplier_invite_wa';
    create temp table _o as select public.fn_wa_supplier_invite_queue(50, '2026-10-20 08:00+00') o;
    select (select (o->>'queued')::int from _o) as queued, (select (o->>'live')::boolean from _o) as live,
           (select count(*) from public.notifications where type = 'supplier_invite_wa') - (select n from _b) as rows;`,
    { label: 'whatsapp invitation off', rows: true });
  assert.equal(r.live, false); assert.equal(r.queued, 0); assert.equal(Number(r.rows), 0);
});
