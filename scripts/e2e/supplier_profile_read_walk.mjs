// scripts/e2e/supplier_profile_read_walk.mjs — THE COMPANY PROFILE A SUPPLIER UPLOADS, SUMMARISED AND CONFIRMED, IN A REAL BROWSER.
// Assigned: sales_engineer. 2 Nov 2026, founder ledger 1469: "the sales agent summarises an uploaded company profile, gives
// keywords of services, the supplier confirms". Until now the tests only checked that the section shows; this one checks that
// what it shows is TRUE of the file. Sibling of supplier_document_read_walk.mjs (the licence), same fixtures, same teardown.
//
// Per file (profile_read_corpus.mjs: text PDF, scanned PDF, image-heavy brochure, DOCX, Arabic-and-English, multi-trade,
// no services, blank, corrupt), on the live site, as a supplier:
//   1. an invited ZZ DEMO lead claims its listing (API, as the portal's claim does), a clean text licence is sent through
//      supplier_api process_docs, and the PROFILE is uploaded through the Documents tab's own card in Chromium;
//   2. the read must reach an end (a stuck "reading" is a hang), and a read that failed must say why;
//   3. terms + Save hold the registration at pending / services_unconfirmed (ledger 1469);
//   4. the Services tab is read OFF THE SCREEN: the summary lines and the keywords are judged against what the file prints
//      (profile_read_judge.mjs: nothing invented, exact trade or none, English only, honest when it could not read);
//   5. the supplier EDITS (unticks a service, adds its own words where there is no checklist) and presses Confirm in the
//      browser; what was saved must equal what was ticked, and the supplier becomes approved and verified.
// Not real: the licence upload, the claim, the mobile and terms + Save are the portal's API calls, not clicks (the licence form is
// walked by supplier_document_read_walk.mjs, terms by supplier_registration_walk.mjs); the SMS code cannot be read.
//
//   node scripts/e2e/supplier_profile_read_walk.mjs [--case a,b] [--concurrency 3] [--keep] [--json f] [--shots dir]
// Exit 1 when any case fails. Cost: model spend is read from ai_cost_log by the run tag and must stay under USD 2.
import { writeFileSync, readFileSync, mkdtempSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openRun, closeRun, read, write, call, BASE } from './fixtures.mjs';
import { keys, verifyEmailByOtp, mkAuthUser } from '../lib/demo_factory.mjs';
import { ACTIVITIES, AUTHORITIES, licenceTruth, licenceTextPdf } from './document_intake_corpus.mjs';
import { profileCorpus } from './profile_read_corpus.mjs';
import { judgeView, stateOfNotice, ARABIC } from './profile_read_judge.mjs';
import { launch, signedInPage, realErrors, SITE } from './browser.mjs';

const argv = process.argv.slice(2);
const val = (f, d) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : d; };
const ONLY = val('--case', '').split(',').filter(Boolean);
const CONC = Number(val('--concurrency', '3'));
const KEEP = argv.includes('--keep');
const JSON_OUT = val('--json', '');
const SHOTS = val('--shots', 'profile-walk-shots');
const CAP_USD = 2;
mkdirSync(SHOTS, { recursive: true });

const TMP = mkdtempSync(join(tmpdir(), 'qd-profwalk-'));
mkdirSync(join(TMP, 'prof'), { recursive: true });
const ALL = await profileCorpus(join(TMP, 'prof'));
// EACH SUPPLIER GETS ITS OWN CLEAN TEXT LICENCE in the name its profile prints (one licence number and one company name can belong to
// one account only: claim answers 409; and a profile about another company than the registered one is not what a supplier uploads).
// The licence is not the subject here: its activities are the plain "General Trading" ones, so it proposes no trade of its own.
const GENERAL = [ACTIVITIES[12], ACTIVITIES[13]];
const CASES = ALL.map((c, i) => {
  const t = licenceTruth('dubai_det', 40 + i, { legal: c.company, acts: GENERAL });
  const name = `licence_${c.id}.pdf`; writeFileSync(join(TMP, name), licenceTextPdf(AUTHORITIES.dubai_det, t));
  return { ...c, lic: { file: join(TMP, name), mime: 'application/pdf', name, registered: t.legal_name_en, trades: t.trades } };
}).filter((c) => !ONLY.length || ONLY.includes(c.id));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let BR = null;

const PROFILE_SQL = (id) => `select l.approval_status status, l.licence_gate_reason reason, l.verified, l.signed_terms_path is not null signed, l.trade_license_no licence_no,
    l.company_profile_doc_path prof_path, c.proposed_trades,
    (select coalesce(jsonb_agg(d), '[]'::jsonb) from jsonb_array_elements(coalesce(c.source_docs->'docs','[]'::jsonb)) d where d->>'kind'='profile') prof,
    (select coalesce(jsonb_agg(d), '[]'::jsonb) from jsonb_array_elements(coalesce(c.source_docs->'docs','[]'::jsonb)) d where d->>'kind'='licence') licrec,
    (select count(*)::int from public.supplier_capability_confirmation k where k.supplier_id = l.id) confirmations
  from public.leads l left join public.supplier_capabilities c on c.supplier_id = l.id where l.id=${id}`;

// ONE SERVICES-TAB SNAPSHOT, read off the screen the way the supplier sees it.
async function servicesView(page, M) {
  const box = M.getByTestId('profile-summary');
  await box.waitFor({ timeout: 60000 });
  const text = (await box.innerText()).replace(/[ \t]+/g, ' ');
  const keywords = (await box.locator('p', { hasText: /^Keywords of your services$/ }).locator('xpath=following-sibling::div[1]/*').allInnerTexts()).map((s) => s.trim()).filter(Boolean);
  const lines = (await box.locator('q').allInnerTexts()).map((s) => s.replace(/[“”"]/g, '').trim()).filter(Boolean);
  const outside = await M.evaluate((el) => { const c = el.cloneNode(true); c.querySelectorAll('q,textarea').forEach((e) => e.remove()); return c.textContent || ''; });
  const m = outside.match(/[^\s]*[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]+[^\s]*/);
  return { state: stateOfNotice(text), text, keywords, lines, arabicOutside: m ? m[0] : '', arabicQuotes: lines.filter((l) => ARABIC.test(l)) };
}

async function walk(run, c, n) {
  const out = { id: c.id, label: c.label, steps: [], ok: true };
  const step = (name, ok, detail = '') => { out.steps.push({ name, ok: !!ok, detail }); if (!ok) out.ok = false; console.log(`${ok ? 'PASS' : 'FAIL'} [${c.id}] ${name}${detail ? ' — ' + String(detail).slice(0, 1100) : ''}`); };
  const email = `qd-${run.tag}-prof${n}@example.invalid`, mobile = `+9715000000${String(30 + n).padStart(2, '0')}`;
  const company = c.lic.registered;
  const lead = (await write(`insert into public.leads (company_name, email, emirate, source, invite_status, invited_at, locale, tags)
     values ('${company.replace(/'/g, "''")}', '${email}', 'Dubai', 'directory', 'sent', now(), 'en', ARRAY['qd_demo','qd_run:${run.tag}']) returning id, claim_token::text t`, 'invited demo lead'))[0];
  run.ids.leads.add(String(lead.id));

  // 1. account, e-mail code, claim, fixture mobile (as supplier_document_read_walk.mjs)
  const u = await mkAuthUser(run, email);
  const v = await verifyEmailByOtp(email, 'supplier');
  const { ANON } = await keys();
  const s = await (await fetch(`${BASE}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: u.password }) })).json();
  step('account + e-mail code (login_otp)', v.json?.ok === true && !!s.access_token, `HTTP ${v.status}`);
  if (!s.access_token) return out;
  const jwt = s.access_token;
  const cl = await call('supplier_api', jwt, { action: 'claim', t: lead.t, first_touch: null });
  step('the invited listing is claimed', cl.status === 200, `HTTP ${cl.status}`);
  await call('kyc', jwt, { action: 'send_sms', phone: mobile });
  await write(`update public.leads set phone='${mobile}', owner_phone_verified=true where id=${lead.id}`, 'fixture mobile verified');
  await call('kyc', jwt, { action: 'whatsapp_choose', user_kind: 'supplier', email, opt: 'same' });

  // 2. the licence (not the subject here): a clean text licence, so the only variable is the profile
  const lb = readFileSync(c.lic.file).toString('base64');
  const lic = await call('supplier_api', jwt, { action: 'process_docs', license: { original_b64: lb, file_b64: lb, images: [], filename: c.lic.name, mime: c.lic.mime } }, 200000);
  step('the licence is taken (API)', lic.status === 200 && lic.json?.ok === true, `HTTP ${lic.status}`);

  // 3. THE PROFILE through the Documents tab's own card, in Chromium
  BR ||= await launch();
  const { ctx, page, consoleErrors } = await signedInPage(BR, { kind: 'supplier', email, newSession: async () => s }, { lang: 'en', viewport: 'desktop' });
  page.setDefaultTimeout(60000);
  const M = page.locator('main').first();
  const shot = (name) => page.screenshot({ path: join(SHOTS, `${c.id}_${name}.png`), fullPage: true }).catch(() => {});
  try {
    await page.goto(`${SITE}/portal`, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.getByRole('button', { name: /^Documents$/ }).first().click();
    await page.getByText('Documents & certificates').first().waitFor();
    const card = M.locator('.qd-panel').filter({ has: page.locator('b', { hasText: /^Company profile$/ }) }).last();
    await card.locator('input[type=file]').first().waitFor({ state: 'attached' });
    const isSave = (r) => /\/functions\/v1\/supplier_portal/.test(r.url()) && /save_documents/.test(r.request().postData() || '') && /"profile"/.test(r.request().postData() || '');
    const t0 = Date.now();
    const ans = page.waitForResponse(isSave, { timeout: 150000 }).then(async (r) => ({ status: r.status(), body: (await r.text().catch(() => '')).slice(0, 500), ms: Date.now() - t0 })).catch(() => ({ hung: true, ms: Date.now() - t0 }));
    await card.locator('input[type=file]').first().setInputFiles(c.file);
    await card.getByRole('button', { name: /^Upload$/ }).click({ timeout: 15000 });
    const a = await ans;
    out.upload = a;
    await page.waitForTimeout(1500);
    out.documents_alerts = await page.getByRole('alert').allInnerTexts().catch(() => []);
    out.documents_text = (await M.innerText().catch(() => '')).replace(/\s+/g, ' ').slice(0, 900);
    await shot('documents');
    step('the Documents tab answers the profile upload (no hang)', !a.hung, `${a.ms} ms ${a.status ? 'HTTP ' + a.status : ''} ${a.body || ''}`.trim());
    step('Documents tab is not left on "Uploading…"', !(await page.getByText(/^Uploading…/).first().isVisible().catch(() => false)));

    // 4. the read must END. 'reading' for ever is a hang; a failed read must carry its reason.
    const t1 = Date.now(); let row;
    for (;;) {
      row = (await read(PROFILE_SQL(lead.id)))[0];
      const rec = row.prof?.[0];
      if ((rec && rec.status !== 'reading') || (!row.prof_path && Date.now() - t1 > 40000) || Date.now() - t1 > 300000) break;
      await sleep(5000);
    }
    if (row.prof_path) run.ids.storage.push('supplier-docs/' + row.prof_path);
    const rec = row.prof?.[0] || null;
    out.profile_record = rec ? { status: rec.status, reason: rec.reason, source: rec.source, format: rec.format, trades: (rec.trades || []).map((t) => t.code), choice: rec.choice, vision_held: (rec.vision_held || []).map((t) => t.code),
      rejected: rec.rejected, held_readings: rec.held_readings, exact: rec.exact, meaning: rec.meaning } : null;
    step('the read of the profile ends (not stuck on "reading")', !rec ? !row.prof_path : rec.status !== 'reading', `${Date.now() - t1} ms; ${JSON.stringify(out.profile_record)}`);
    if (c.failedRead) {
      const shownWhy = (out.documents_alerts || []).join(' ').trim();
      step('a profile that cannot be read says why (a recorded reason, or the error shown to the supplier)', !!(rec?.reason) || shownWhy.length > 0, `reason=${rec?.reason || ''} alert=${shownWhy.slice(0, 200)}`);
    }
    const docTrades = (rec?.trades || []).map((t) => t.code);
    // EXACT TRADE OR NONE in the stored read as well as on screen: the codes proposed are the codes the file states.
    const stray = docTrades.filter((t) => !c.truth.stated.includes(t));
    step('the stored read of the profile names only trades the file states (no nearest mapping)', stray.length === 0, stray.length ? `not in the file: ${stray.join(', ')}` : `${docTrades.join(', ') || 'none'}`);
    const okTrades = [...c.truth.stated, ...c.lic.trades];   // the file's, and the licence's own activities
    const lrec = row.licrec?.[0] || null;
    const licTrades = (lrec?.trades || []).map((t) => t.code);
    out.licence_record = lrec ? { status: lrec.status, reason: lrec.reason, trades: (lrec.trades || []).map((t) => ({ code: t.code, via: t.via, snippet: t.snippet, phrases: t.phrases })), exact: lrec.exact, meaning: lrec.meaning } : null;
    // The licence prints "General Trading, Import and Export": no trade code is named by those words (exact trade or none).
    step('the licence read proposes no trade for "General Trading, Import and Export" (no nearest mapping)', licTrades.filter((t) => !c.lic.trades.includes(t)).length === 0, JSON.stringify(out.licence_record));
    const strayAll = (row.proposed_trades || []).filter((t) => !okTrades.includes(t));
    step('every trade proposed for the supplier comes from the profile or the licence', strayAll.length === 0, strayAll.length ? `from neither: ${strayAll.join(', ')}` : `${(row.proposed_trades || []).join(', ') || 'none'}`);

    // 5. terms + Save, as the Profile tab sends them; an otherwise complete registration is held for the services
    const sv = await call('supplier_api', jwt, { action: 'save_profile', service_emirates: ['Dubai'], accept_terms: true, marketing_consent: false, contact_name: 'ZZ DEMO Contact', signatory_name: 'ZZ DEMO Signatory' }, 60000);
    await call('kyc', jwt, { action: 'accept_terms' }, 60000).catch(() => null);
    step('save_profile answers', sv.status === 200 && sv.json?.ok === true, `HTTP ${sv.status} ${String(sv.text).slice(0, 120)}`);
    const t2 = Date.now();
    for (;;) { row = (await read(PROFILE_SQL(lead.id)))[0]; if ((row.signed && row.reason !== 'reg_terms' && row.reason !== 'documents_being_read') || Date.now() - t2 > 240000) break; await sleep(4000); }
    step('ledger 1469: before the supplier confirms its services it is held (pending / services_unconfirmed)', row.status === 'pending' && row.reason === 'services_unconfirmed', `got ${row.status} / ${row.reason}`);

    // 6. THE SERVICES TAB, read off the screen
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.getByRole('button', { name: /^Services$/ }).first().click({ timeout: 60000 });
    const view = await servicesView(page, M);
    await shot('services');
    out.view = { state: view.state, keywords: view.keywords, lines: view.lines, arabicOutside: view.arabicOutside, arabicQuotes: view.arabicQuotes };
    const st = (await call('supplier_api', jwt, { action: 'services_state' })).json || {};
    const label = new Map((st.vocabulary?.trades || []).map((t) => [t.code, t.label]));
    const labelOf = (code) => label.get(code) || code;
    out.truth = { read: c.truth.read, stated: c.truth.stated, stated_labels: c.truth.stated.map(labelOf) };
    for (const j of judgeView({ truth: c.truth, view, labelOf })) step(j.name, j.ok, j.detail);
    // THE KNOWN-BAD CONTROLS, ON THIS RUN'S OWN DATA: the judge must fail a screen with one more keyword, and a screen judged against another file.
    const bad = judgeView({ truth: c.truth, view: { ...view, keywords: [...view.keywords, 'Elevators & Escalators'] }, labelOf });
    step('control: the judge flags this screen when one invented keyword is added', bad.some((j) => !j.ok && /invented/.test(j.name)));
    if (c.truth.read === 'text') {
      const other = CASES.find((o) => o.id !== c.id && o.truth.read === 'text' && o.truth.stated.join() !== c.truth.stated.join());
      if (other) step(`control: the judge flags this screen when judged against ${other.id}'s file`, judgeView({ truth: other.truth, view, labelOf }).some((j) => !j.ok));
    }
    const checklist = (st.checklist || []).map((x) => ({ code: x.code, source: x.source }));
    out.checklist = checklist;
    const fromDocs = checklist.filter((x) => x.source === 'documents').map((x) => x.code).filter((x) => !okTrades.includes(x));
    step('the prepared checklist offers no trade from the documents that neither the profile nor the licence states', fromDocs.length === 0, fromDocs.join(', '));

    // 7. THE SUPPLIER EDITS AND CONFIRMS, in the browser
    const roleBoxes = M.locator('input[type=checkbox][id*="-role-"]');
    if ((await roleBoxes.count()) && !(await roleBoxes.evaluateAll((els) => els.some((e) => e.checked)))) await roleBoxes.first().check();
    const svc = M.locator('input[type=checkbox]:not([id*="-role-"])');
    const nSvc = await svc.count();
    let own = '';
    if (nSvc > 0) {
      const on = await svc.evaluateAll((els) => els.map((e) => e.checked));
      if (!on.some(Boolean)) await svc.first().check();                    // nothing was pre-ticked: the supplier ticks what it does
      else if (on.filter(Boolean).length >= 2) await svc.nth(on.indexOf(true)).uncheck();   // the supplier removes one: an edit
    }
    if (nSvc === 0 || c.id === 'text_pdf') {
      own = c.id === 'text_pdf' ? 'We also supply and install aluminium shopfronts.' : 'We install and maintain commercial kitchen exhaust systems.';
      await M.locator('textarea').first().fill(own);
      await M.getByRole('button', { name: /^Rewrite my services$/ }).click();
      await M.getByRole('button', { name: /Our sales engineer is reading it/ }).waitFor({ state: 'detached', timeout: 150000 }).catch(() => {});
      await page.waitForTimeout(800);
    }
    const ticked = await svc.evaluateAll((els) => els.filter((e) => e.checked).map((e) => (e.closest('label')?.innerText || '').trim()));
    out.edit = { services_on_screen: nSvc, ticked, own_words: own };
    const confirm = M.getByRole('button', { name: /^(Confirm my services|Update my services)$/ });
    step('Confirm is available once a role and a service are chosen', await confirm.isEnabled().catch(() => false), await M.locator('p.text-warn-fg').allInnerTexts().then((x) => x.join(' ')).catch(() => ''));
    const saveResp = page.waitForResponse((r) => /\/functions\/v1\/supplier_api/.test(r.url()) && /services_save_rewrite/.test(r.request().postData() || ''), { timeout: 150000 }).then(async (r) => `HTTP ${r.status()} ${(await r.text().catch(() => '')).slice(0, 200)}`).catch(() => 'no answer in 150 s');
    await confirm.click({ timeout: 15000 });
    const saved = await saveResp;
    const note = await M.getByText(/^Saved\./).first().waitFor({ timeout: 30000 }).then(() => true).catch(() => false);
    await shot('confirmed');
    step('the supplier confirms in the browser and is told it saved', note && /HTTP 200/.test(saved) && /"ok":true/.test(saved), saved);

    // 8. what was saved is what was ticked; then approved
    const after = (await call('supplier_api', jwt, { action: 'services_state' })).json || {};
    const labelOfKey = new Map(Object.values(after.services_by_trade || {}).flat().map((x) => [x.key, x.label_en]));
    const savedLabels = (after.selected_services || []).map((k) => labelOfKey.get(k) || k);
    const missing = ticked.filter((t) => !savedLabels.includes(t));
    const extra = savedLabels.filter((t) => !ticked.includes(t));
    out.saved = { selected: savedLabels, own_words: after.extra_services || [] };
    step('what was saved is what the supplier ticked', missing.length === 0 && (own ? true : extra.length === 0), `ticked ${JSON.stringify(ticked)} saved ${JSON.stringify(savedLabels)}`);
    if (own) step('the supplier\'s own words are kept and shown back', (after.extra_services || []).length + (after.selected_services || []).length > 0 && !!after.raw_text, `raw_text=${String(after.raw_text).slice(0, 80)} own=${JSON.stringify(after.extra_services)}`);
    const t3 = Date.now();
    for (;;) { row = (await read(PROFILE_SQL(lead.id)))[0]; if (row.status === 'approved' || Date.now() - t3 > 90000) break; await sleep(3000); }
    step('after the confirm the supplier is approved and verified with no hold', row.status === 'approved' && row.verified === true && !row.reason && row.confirmations > 0, `${row.status}/${row.reason} verified=${row.verified} confirmations=${row.confirmations}`);
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.getByRole('button', { name: /^Services$/ }).first().click({ timeout: 60000 });
    const again = await servicesView(page, M);
    step('the same profile summary is still shown after confirming and reloading', again.state === view.state && JSON.stringify(again.keywords) === JSON.stringify(view.keywords), `${again.state} ${again.keywords.join(', ')}`);
    step('the page raised no console error', realErrors(consoleErrors).length === 0, realErrors(consoleErrors).join(' | '));
  } catch (e) {
    step('the walk reached the end of this case', false, String(e?.message || e).slice(0, 300));
    await shot('error');
    out.page_text = (await page.locator('body').innerText().catch(() => '')).replace(/\s+/g, ' ').slice(0, 600);
  }
  await ctx.close().catch(() => {});
  return out;
}

const run = await openRun({ capUsd: CAP_USD, minutes: 75 });
const results = [];
try {
  const queue = CASES.map((c, i) => [c, run.seq++ + i]);
  await Promise.all(Array.from({ length: Math.max(1, CONC) }, async () => {
    for (let job = queue.shift(); job; job = queue.shift()) {
      try { results.push(await walk(run, job[0], job[1])); }
      catch (e) { console.error('LEG ERROR', job[0].id, String(e?.stack || e).slice(0, 400)); results.push({ id: job[0].id, ok: false, error: String(e?.message || e) }); }
    }
  }));
  const spend = (await read(`select coalesce(sum(cost_usd_reported),0)::numeric(10,4) usd, count(*)::int calls from public.ai_cost_log where e2e_run_tag = '${run.tag}'`).catch(() => [{ usd: null }]))[0];
  console.log('model spend', JSON.stringify(spend));
  const within = spend.usd === null || Number(spend.usd) <= CAP_USD;
  console.log(`${within ? 'PASS' : 'FAIL'} model spend ${spend.usd} USD is within the USD ${CAP_USD} budget`);
  if (!within) results.push({ id: 'budget', ok: false });
} finally {
  await BR?.close().catch(() => {});
  const c = await closeRun(run, { keep: KEEP });
  console.log('teardown:', JSON.stringify(c.leftovers || 'kept'));
}
if (JSON_OUT) writeFileSync(JSON_OUT, JSON.stringify(results, null, 1));
// THE TABLE: per file, what the file states against what the tab showed.
console.log('\nTRUE vs SHOWN');
for (const r of results) if (r.truth) console.log(`${r.ok ? 'PASS' : 'FAIL'} ${r.id.padEnd(12)} file states [${r.truth.stated_labels.join(', ')}] (${r.truth.read}) | tab shows ${r.view.state} [${r.view.keywords.join(', ')}] lines ${JSON.stringify(r.view.lines)} | read ${JSON.stringify(r.profile_record)}`);
const failed = results.filter((r) => !r.ok);
console.log(`${results.length - failed.length}/${results.length} cases passed`);
process.exit(failed.length ? 1 : 0);
