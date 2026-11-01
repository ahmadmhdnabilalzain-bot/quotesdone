// scripts/e2e/wa_exchange_real.mjs - a supplier who just got a WhatsApp code texts us; the REAL handler, REAL model, REAL database.
// Seat: customer_support (2 Nov 2026; coordinator's check; ledger 1260: all tests with AI).
//   node scripts/e2e/wa_exchange_real.mjs        (needs SUPABASE_ACCESS_TOKEN and deno)
// WHO IT CAN REACH. Two reserved fixture numbers (+971 50 000 00xx, demo_identity.ts): wa_inbound never hands a fixture
// reply to Twilio, it is captured on wa_messages. The supplier is a ZZ DEMO lead made by demo_factory, torn down after.
// COST. A rehearsal window with models_allowed and cap_usd 2.5 bounds model spend; the spend is read back and printed.
// The handler is this checkout's wa_inbound/index.ts run under Deno, so an UNDEPLOYED fix is exercised.
import { spawnSync } from 'node:child_process';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
process.env.QD_FIXTURES = '1';
const { newRun, makeSupplier, teardown, REF, BASE, keys } = await import('../lib/demo_factory.mjs');
const { mgmtRead, mgmtFixture } = await import('../lib/qd_guard.mjs');
const { demoTradeLicence, demoOfficePlanPng } = await import('../lib/demo_pdf.mjs');
const CAP_USD = 2.5;
const run = newRun({ quiet: true }); const tag = run.tag;
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
const STRANGER = '+971500000097';
let sup, started = new Date().toISOString(), result = null;
try {
  sup = await makeSupplier(run, {});
  const phone = (await mgmtRead(REF, `select phone from public.leads where id=${sup.leadId}`))[0].phone;
  if (!/^\+9715000000\d\d$/.test(phone)) throw new Error('REFUSED: supplier phone ' + phone + ' is not in the fixture block');
  // the supplier chose "same number for WhatsApp" (what the new kyc rule writes after a WhatsApp-delivered code)
  await mgmtFixture(REF, `update public.leads set whatsapp_opt='other', whatsapp_phone=${q(phone)}, whatsapp_verified_at=now(), whatsapp_asked_at=now() where id=${sup.leadId}`, 'fixture WhatsApp confirmed');
  await mgmtFixture(REF, `insert into public.rehearsal_window (run_tag, opened_by) values ('qd_run:${tag}', 'wa_exchange_real')`, 'rehearsal window');
  await mgmtFixture(REF, `update public.rehearsal_window set models_allowed = true, cap_usd = ${CAP_USD}, expires_at = now() + interval '1 hour' where run_tag = 'qd_run:${tag}' and ended_at is null`, 'rehearsal window models');
  const sec = Object.fromEntries((await mgmtRead(REF, `select key, value from public.app_secrets where key in ('twilio_auth_token','cred_fn_wa_inbound')`)).map((r) => [r.key, r.value]));
  const { SERVICE } = await keys();
  const dir = mkdtempSync(join(tmpdir(), 'waexch-'));
  const cfg = join(dir, 'cfg.json');
  writeFileSync(cfg, JSON.stringify({ url: `https://${REF}.supabase.co`, service: SERVICE, authToken: sec.twilio_auth_token, internal: sec.cred_fn_wa_inbound,
    supplier: phone, stranger: STRANGER,
    pngB64: demoOfficePlanPng().toString('base64'),
    pdfB64: demoTradeLicence({ company: sup.companyName, licenceNo: 'ZZ-DEMO-000123' }).toString('base64') }));
  const r = spawnSync('deno', ['run', '--no-lock', '--node-modules-dir=auto', '--allow-net', '--allow-env', '--allow-read', 'scripts/e2e/wa_exchange_real_driver.ts', cfg],
    { encoding: 'utf8', maxBuffer: 64 << 20, timeout: 20 * 60 * 1000 });
  console.log((r.stderr || '').split('\n').filter((l) => /error|Error/.test(l)).slice(0, 8).join('\n'));
  const line = (r.stdout || '').split('\n').find((l) => l.startsWith('RESULT='));
  if (!line) throw new Error('driver produced no RESULT; stdout tail: ' + (r.stdout || '').slice(-600) + ' stderr tail: ' + (r.stderr || '').slice(-1200));
  result = JSON.parse(line.slice(7));
  const cost = (await mgmtRead(REF, `select coalesce(sum(cost_aed),0)::float aed from public.ai_cost_log where created_at >= ${q(started)}`))[0];
  console.log('COST_AED_SINCE_START(all callers)=' + cost.aed + ' (USD ' + (cost.aed / 3.6725).toFixed(2) + ')');
  const brief = (x) => ({ status: x?.status, ms: x?.ms, reply: x?.reply });
  for (const k of ['forged', 'question', 'hi', 'arabic', 'stranger_hi', 'fee', 'top3', 'identity', 'reveal', 'image', 'document']) console.log('## ' + k + ' ' + JSON.stringify(k === 'forged' ? result[k] : brief(result[k])));
  console.log('## ten ' + JSON.stringify(result.ten));
} finally {
  for (const p of [sup && (await mgmtRead(REF, `select phone from public.leads where id=${sup.leadId}`).then((x) => x[0]?.phone).catch(() => null)), STRANGER].filter(Boolean)) {
    const d = p.replace(/\D/g, '');
    await mgmtFixture(REF, `delete from public.wa_turn where conversation_id in (select id from public.wa_conversation where phone_e164=${q(d)});
      delete from public.wa_conversation where phone_e164=${q(d)}; delete from public.wa_messages where wa_from=${q('whatsapp:' + p)};
      delete from public.wa_inbound_seen where wa_from=${q('whatsapp:' + p)}`, 'fixture wa rows').catch((e) => console.log('cleanup:', String(e).slice(0, 200)));
  }
  await mgmtFixture(REF, `update public.rehearsal_window set ended_at=now() where run_tag='qd_run:${tag}' and ended_at is null`, 'close window').catch(() => {});
  await teardown(run).catch((e) => console.log('teardown:', String(e).slice(0, 300)));
}
