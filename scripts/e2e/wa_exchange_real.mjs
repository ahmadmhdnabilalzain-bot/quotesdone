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
const { newRun, makeSupplier, teardown, REF, BASE, keys, internalCred } = await import('../lib/demo_factory.mjs');
const { mgmtRead, mgmtFixture } = await import('../lib/qd_guard.mjs');
const { demoTradeLicence, demoOfficePlanPng } = await import('../lib/demo_pdf.mjs');
const MEDIA_ONLY = process.env.QD_MEDIA_ONLY === '1';   // six file turns, USD 1 cap
// QD_CONV_SCRIPT=<file.json> {supplier?: [text...], customer?: [text...]}: scripted conversations only (the supplier's number and
// the no-account number); the transcripts are written to QD_CONV_OUT. Used by scripts/eval/conversation_quality.mjs.
const SCRIPT = process.env.QD_CONV_SCRIPT ? JSON.parse((await import('node:fs')).readFileSync(process.env.QD_CONV_SCRIPT, 'utf8')) : null;
const CAP_USD = Number(process.env.QD_CAP_USD) || (MEDIA_ONLY ? 1 : 2.5);   // QD_CAP_USD: conversation_quality's per-conversation cap
const run = newRun({ quiet: true }); const tag = run.tag;
// the workflow's always() step closes this window by its tag even if the process is killed (close_job_windows.mjs)
if (process.env.QD_E2E_RUN_TAGS) (await import('node:fs')).appendFileSync(process.env.QD_E2E_RUN_TAGS, tag + '\n');
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
// ONCE PER CHANGE, NEVER ON A LOOP (it_engineer, 3 Nov 2026). Measured: 48 runs of this exchange on 2-3 Nov, most of
// them the same code exercised again. The code it exercises is fingerprinted (wa_inbound, _shared, this script and its
// driver) and written on the run's rehearsal window; a run of a fingerprint that already completed is refused before
// anything is created or spent. QD_EXCHANGE_AGAIN=1 runs it anyway (a deliberate re-run, by hand). A scripted run
// (QD_CONV_SCRIPT) is one conversation of conversation_quality.mjs's sample and is not fingerprinted here.
const CODE = await (async () => {
  const { createHash } = await import('node:crypto');
  const { readdirSync, readFileSync, statSync } = await import('node:fs');
  const h = createHash('sha256');
  const walk = (p) => statSync(p).isDirectory() ? readdirSync(p).sort().forEach((f) => walk(join(p, f))) : h.update(p.replace(/\\/g, '/') + '\0').update(readFileSync(p));
  for (const p of ['supabase/functions/wa_inbound', 'supabase/functions/_shared', 'scripts/e2e/wa_exchange_real.mjs', 'scripts/e2e/wa_exchange_real_driver.ts']) walk(p);
  return h.digest('hex').slice(0, 16) + (MEDIA_ONLY ? ':media' : ':full');
})();
if (!SCRIPT && process.env.QD_EXCHANGE_AGAIN !== '1') {
  const done = await mgmtRead(REF, `select run_tag, ended_at from public.rehearsal_window where opened_by = 'wa_exchange_real' and note = ${q('code=' + CODE)} and ended_at is not null order by ended_at desc limit 1`);
  if (done.length) { console.log(`REFUSED: this code (${CODE}) was already exchanged by ${done[0].run_tag}, ended ${done[0].ended_at}; QD_EXCHANGE_AGAIN=1 runs it again`); process.exit(0); }
}
// A scripted run (QD_CONV_SCRIPT) may run beside another (the before and after jobs of conversation-quality.yml), so its
// no-account number is a run-allocated fixture number with no conversation on it, never the shared +971500000097.
const freeFixtureNumber = async (not = '') => {
  const { demoMobile } = await import('../lib/demo_factory.mjs');
  for (let i = 0; i < 40; i++) {
    const p = demoMobile(); if (p === not) continue;
    const t = q(p.replace(/\D/g, '').slice(-9));
    const used = await mgmtRead(REF, `select (exists (select 1 from public.wa_conversation where right(phone_e164, 9) = ${t})
      or exists (select 1 from public.leads where right(regexp_replace(coalesce(phone,''),'[^0-9]','','g'),9) = ${t} or right(regexp_replace(coalesce(whatsapp_phone,''),'[^0-9]','','g'),9) = ${t})
      or exists (select 1 from public.customers where right(regexp_replace(coalesce(phone,''),'[^0-9]','','g'),9) = ${t} or right(regexp_replace(coalesce(whatsapp_phone,''),'[^0-9]','','g'),9) = ${t})) used`);
    if (used[0]?.used === false) return p;
  }
  throw new Error('no free fixture number for the scripted run');
};
const STRANGER = SCRIPT ? await freeFixtureNumber() : '+971500000097';
let sup, started = new Date().toISOString(), result = null;
try {
  sup = await makeSupplier(run, {});
  // a scripted run's supplier gets a number nobody else holds (see freeFixtureNumber): one party, or wa_inbound names nobody
  if (SCRIPT) await mgmtFixture(REF, `update public.leads set phone = ${q(await freeFixtureNumber(STRANGER))} where id = ${sup.leadId}`, 'fixture supplier number of its own');
  const phone = (await mgmtRead(REF, `select phone from public.leads where id=${sup.leadId}`))[0].phone;
  if (!/^\+9715000000\d\d$/.test(phone)) throw new Error('REFUSED: supplier phone ' + phone + ' is not in the fixture block');
  // the supplier chose "same number for WhatsApp" (what the new kyc rule writes after a WhatsApp-delivered code)
  await mgmtFixture(REF, `update public.leads set whatsapp_opt='other', whatsapp_phone=${q(phone)}, whatsapp_verified_at=now(), whatsapp_asked_at=now() where id=${sup.leadId}`, 'fixture WhatsApp confirmed');
  await mgmtFixture(REF, `insert into public.rehearsal_window (run_tag, opened_by, note) values ('qd_run:${tag}', 'wa_exchange_real', ${q(SCRIPT ? 'scripted conversation' : 'code=' + CODE)})`, 'rehearsal window');
  await mgmtFixture(REF, `update public.rehearsal_window set models_allowed = true, cap_usd = ${CAP_USD}, expires_at = now() + interval '1 hour' where run_tag = 'qd_run:${tag}' and ended_at is null`, 'rehearsal window models');
  const sec = Object.fromEntries((await mgmtRead(REF, `select key, value from public.app_secrets where key in ('twilio_auth_token','cred_fn_wa_inbound','cred_ops_wa_replay')`)).map((r) => [r.key, r.value]));
  const { SERVICE } = await keys();
  const dir = mkdtempSync(join(tmpdir(), 'waexch-'));
  const cfg = join(dir, 'cfg.json');
  writeFileSync(cfg, JSON.stringify({ url: `https://${REF}.supabase.co`, service: SERVICE, authToken: sec.twilio_auth_token, mediaOnly: MEDIA_ONLY, internals: [sec.cred_fn_wa_inbound, sec.cred_ops_wa_replay].filter(Boolean),
    // EVERY run names its run and proves it (it_engineer, 3 Nov 2026), not only the scripted one: measured 48 exchange runs
    // on 2-3 Nov whose Twilio-signed turns carried no tag, so ai_gateway saw a stranger's WhatsApp and the window's cap
    // never applied. The driver puts the tag and the secret on every request it makes (wa_exchange_real_driver.ts).
    supplier: phone, stranger: STRANGER, e2e: { tag, secret: await internalCred() }, ...(SCRIPT ? { script: SCRIPT } : {}), parityOld: '+971500000094', parityNew: '+971500000095',
    pngB64: demoOfficePlanPng().toString('base64'),
    pdfB64: demoTradeLicence({ company: sup.companyName, licenceNo: 'ZZ-DEMO-000123' }).toString('base64') }));
  const r = spawnSync('deno', ['run', '--no-lock', '--node-modules-dir=auto', '--allow-net', '--allow-env', '--allow-read', 'scripts/e2e/wa_exchange_real_driver.ts', cfg],
    { encoding: 'utf8', maxBuffer: 64 << 20, timeout: (MEDIA_ONLY ? 8 : SCRIPT ? 60 : 20) * 60 * 1000 });
  console.log((r.stderr || '').split('\n').filter((l) => /error|Error/.test(l)).slice(0, 8).join('\n'));
  const line = (r.stdout || '').split('\n').find((l) => l.startsWith('RESULT='));
  if (!line) throw new Error('driver produced no RESULT; stdout tail: ' + (r.stdout || '').slice(-600) + ' stderr tail: ' + (r.stderr || '').slice(-1200));
  result = JSON.parse(line.slice(7));
  if (SCRIPT) writeFileSync(process.env.QD_CONV_OUT, JSON.stringify(result.script));
  if (!SCRIPT) {
  const brief =(x) => ({ status: x?.status, ms: x?.ms, reply: x?.reply, results: x?.rows?.[0]?.meta?.results, err: x?.rows?.[0]?.meta?.send_error, nrows: x?.rows?.length, t: x?.rows?.[0]?.meta?.timings, att: x?.rows?.[0]?.meta?.reply_attempts });
  for (const k of ['parity', 'parity_control_detects_a_difference', 'forged', 'question', 'hi', 'arabic', 'stranger_hi', 'fee', 'top3', 'identity', 'reveal', 'image', 'document', 'bad_image_control', 'bad_pdf_control', 'voice', 'stranger_image']) console.log('## ' + k + ' ' + JSON.stringify(['forged', 'parity', 'parity_control_detects_a_difference'].includes(k) ? result[k] : brief(result[k])));
  {
    // Media verdicts. Each file turn must leave a row and a reply; the bad-file controls must NOT read as accepted;
    // a voice note must say it was not heard (and never ask for a licence).
    const rep = (k) => String(result[k]?.reply || '').toLowerCase();
    const checks = {
      image_answered: !!rep('image'), document_answered: !!rep('document'), stranger_image_answered: !!rep('stranger_image'),
      document_not_refused: !!rep('document') && !/couldn.t be accepted|not accepted|refused/.test(rep('document')),
      bad_image_not_accepted: !!rep('bad_image_control') && !/on file|record was updated/.test(rep('bad_image_control')),
      bad_pdf_not_accepted: !!rep('bad_pdf_control') && !/on file|record was updated/.test(rep('bad_pdf_control')),
      voice_says_not_heard: /type|typed|write|text/.test(rep('voice')) && !/trade licen|pdf|photo of/.test(rep('voice')),
      english_only: ['image', 'document', 'voice'].every((k) => !/[\u0600-\u06FF]/.test(rep(k))),
    };
    console.log('MEDIA_CHECKS ' + JSON.stringify(checks));
    if (Object.values(checks).some((v) => !v)) process.exitCode = 1;
  }
  if (!MEDIA_ONLY) console.log('## ten ' + JSON.stringify(result.ten));
  if (!MEDIA_ONLY) {
    const turns = [...['question', 'hi', 'arabic', 'stranger_hi', 'fee', 'top3', 'identity', 'reveal'].map((k) => result[k]), ...result.ten.filter((t) => typeof t.ms === 'number')].filter((t) => t && typeof t.ms === 'number');
    const ms = turns.map((t) => t.ms).sort((a, b) => a - b); const pct = (p) => ms[Math.min(ms.length - 1, Math.floor(p * ms.length))];
    console.log('LATENCY turns=' + ms.length + ' p50_ms=' + pct(0.5) + ' p95_ms=' + pct(0.95) + ' max_ms=' + ms[ms.length - 1] + ' unanswered=' + turns.filter((t) => !t.reply).length);
    // EVERY TURN IS ANSWERED, THE PARITY TURNS TOO (customer_support, 3 Nov 2026). Run 41530397323 printed unanswered=0 while the
    // lean "scam" parity turn had no reply at 93 s: the count above leaves the ten parity turns out. These verdicts fail the run.
    const par = result.parity || [];
    const parUnanswered = par.flatMap((p) => [p.old, p.lean]).filter((x) => !x?.answered).length;
    const mismatches = par.filter((p) => !p.same).length;
    console.log('VERDICT unanswered_including_parity=' + (turns.filter((t) => !t.reply).length + parUnanswered) + ' parity_mismatches=' + mismatches);
    if (turns.some((t) => !t.reply) || parUnanswered || mismatches) process.exitCode = 1;
  }
  // The held queue, by design: a turn that got no reply is filed (fn_reason_hold) and the re-ask cron answers it or lets it expire.
  // Polled up to 5 minutes. A fixture reply is captured, never delivered, so 'failed' with reask_delivery.detail 'captured' means
  // the model's answer WAS written and handed to the sender, which is the most a fixture can show.
  if (!MEDIA_ONLY) try {
    const phones = [phone, STRANGER, '+971500000094', '+971500000095'].map((p) => `'${p}'`).join(',');
    for (let i = 0; i < 10; i++) {
      const held = await mgmtRead(REF, `select id, status, attempts, left(coalesce(result::text,''),260) res from public.reasoning_held_question where surface='wa_inbound.unwritten_reply' and created_at >= ${q(started)} and subject->>'phone' in (${phones.replaceAll("'+", "'whatsapp:+").replace(/'/g, "'")}) order by id`).catch(() => []);
      if (held.length === 0 || held.every((h) => h.status !== 'pending' && h.status !== 'held')) { console.log('HELD_QUEUE ' + JSON.stringify(held)); break; }
      if (i === 9) console.log('HELD_QUEUE (still open after 5 min) ' + JSON.stringify(held));
      await new Promise((r) => setTimeout(r, 30000));
    }
  } catch (e) { console.log('held queue read failed: ' + String(e).slice(0, 200)); }
  }   // !SCRIPT
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
