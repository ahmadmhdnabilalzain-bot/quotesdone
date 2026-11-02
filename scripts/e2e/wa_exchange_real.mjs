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
    supplier: phone, stranger: STRANGER, parityOld: '+971500000094', parityNew: '+971500000095',
    pngB64: demoOfficePlanPng().toString('base64'),
    pdfB64: demoTradeLicence({ company: sup.companyName, licenceNo: 'ZZ-DEMO-000123' }).toString('base64') }));
  const r = spawnSync('deno', ['run', '--no-lock', '--node-modules-dir=auto', '--allow-net', '--allow-env', '--allow-read', 'scripts/e2e/wa_exchange_real_driver.ts', cfg],
    { encoding: 'utf8', maxBuffer: 64 << 20, timeout: 20 * 60 * 1000 });
  console.log((r.stderr || '').split('\n').filter((l) => /error|Error/.test(l)).slice(0, 8).join('\n'));
  const line = (r.stdout || '').split('\n').find((l) => l.startsWith('RESULT='));
  if (!line) throw new Error('driver produced no RESULT; stdout tail: ' + (r.stdout || '').slice(-600) + ' stderr tail: ' + (r.stderr || '').slice(-1200));
  result = JSON.parse(line.slice(7));
  const brief = (x) => ({ status: x?.status, ms: x?.ms, reply: x?.reply, results: x?.rows?.[0]?.meta?.results, err: x?.rows?.[0]?.meta?.send_error, nrows: x?.rows?.length, t: x?.rows?.[0]?.meta?.timings });
  for (const k of ['parity', 'parity_control_detects_a_difference', 'forged', 'question', 'hi', 'arabic', 'stranger_hi', 'fee', 'top3', 'identity', 'reveal', 'image', 'document']) console.log('## ' + k + ' ' + JSON.stringify(['forged', 'parity', 'parity_control_detects_a_difference'].includes(k) ? result[k] : brief(result[k])));
  console.log('## ten ' + JSON.stringify(result.ten));
  {
    const turns = [...['question', 'hi', 'arabic', 'stranger_hi', 'fee', 'top3', 'identity', 'reveal'].map((k) => result[k]), ...result.ten.filter((t) => typeof t.ms === 'number')].filter((t) => t && typeof t.ms === 'number');
    const ms = turns.map((t) => t.ms).sort((a, b) => a - b); const pct = (p) => ms[Math.min(ms.length - 1, Math.floor(p * ms.length))];
    console.log('LATENCY turns=' + ms.length + ' p50_ms=' + pct(0.5) + ' p95_ms=' + pct(0.95) + ' max_ms=' + ms[ms.length - 1] + ' unanswered=' + turns.filter((t) => !t.reply).length);
  }
  // The held queue, by design: a turn that got no reply is filed (fn_reason_hold) and the re-ask cron answers it or lets it expire.
  // Polled up to 5 minutes. A fixture reply is captured, never delivered, so 'failed' with reask_delivery.detail 'captured' means
  // the model's answer WAS written and handed to the sender, which is the most a fixture can show.
  try {
    const phones = [phone, STRANGER, '+971500000094', '+971500000095'].map((p) => `'${p}'`).join(',');
    for (let i = 0; i < 10; i++) {
      const held = await mgmtRead(REF, `select id, status, attempts, left(coalesce(result::text,''),260) res from public.reasoning_held_question where surface='wa_inbound.unwritten_reply' and created_at >= ${q(started)} and subject->>'phone' in (${phones.replaceAll("'+", "'whatsapp:+").replace(/'/g, "'")}) order by id`).catch(() => []);
      if (held.length === 0 || held.every((h) => h.status !== 'pending' && h.status !== 'held')) { console.log('HELD_QUEUE ' + JSON.stringify(held)); break; }
      if (i === 9) console.log('HELD_QUEUE (still open after 5 min) ' + JSON.stringify(held));
      await new Promise((r) => setTimeout(r, 30000));
    }
  } catch (e) { console.log('held queue read failed: ' + String(e).slice(0, 200)); }
  try {
    const cost = (await mgmtRead(REF, `select coalesce(sum(cost_aed),0)::float aed from public.ai_cost_log where occurred_at >= ${q(started)}`))[0];
    console.log('COST_AED_SINCE_START(all callers)=' + cost.aed + ' (USD ' + (cost.aed / 3.6725).toFixed(2) + ')');
  } catch (e) { console.log('cost read failed: ' + String(e).slice(0, 200)); }
} finally {
  for (const p of [sup && (await mgmtRead(REF, `select phone from public.leads where id=${sup.leadId}`).then((x) => x[0]?.phone).catch(() => null)), STRANGER, '+971500000094', '+971500000095'].filter(Boolean)) {
    const d = p.replace(/\D/g, '');
    await mgmtFixture(REF, `delete from public.wa_turn where conversation_id in (select id from public.wa_conversation where phone_e164=${q(d)});
      delete from public.wa_conversation where phone_e164=${q(d)}; delete from public.wa_messages where wa_from=${q('whatsapp:' + p)};
      delete from public.wa_inbound_seen where wa_from=${q('whatsapp:' + p)}`, 'fixture wa rows').catch((e) => console.log('cleanup:', String(e).slice(0, 200)));
  }
  await mgmtFixture(REF, `update public.rehearsal_window set ended_at=now() where run_tag='qd_run:${tag}' and ended_at is null`, 'close window').catch(() => {});
  await teardown(run).catch((e) => console.log('teardown:', String(e).slice(0, 300)));
}
