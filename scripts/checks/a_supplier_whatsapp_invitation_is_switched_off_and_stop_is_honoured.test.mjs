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

// 27 Oct 2026: the switch, window, cap and STOP cases moved to
// the_supplier_whatsapp_invitation_waits_for_opt_in_and_both_switches.test.mjs. They replayed this file's two-argument
// fn_wa_supplier_invite_queue, which the 27 Oct file drops; replayed after that apply, the old body would sit beside the
// three-argument one and every call would be ambiguous. The new cases run on ZZ DEMO leads only (p_demo_only).

