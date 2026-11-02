// conversation_continuity.mjs - the browser proof that no QuotesDone chat loses its conversation or starts again, and that
// every answer stays grounded (customer_support with sales_engineer; founder ledger 1464, 2 Nov 2026).
//
// SURFACES, on the LIVE site (QD_SITE, default https://quotesdone.ae), a real browser (Playwright), the real model (ruling 1260):
//   widget    the homepage widget "Ask QuotesDone" (customer_support, site_assistant), a visitor who is not signed up.
//             convA: 16 turns: reload, navigate away and back, a second tab, the 8-message visitor cap (ruling 1249) and the
//             rate limit, a cleared / restored / corrupt conversation key.   convB: a lost reply and its retry, close and
//             reopen, a language switch to Arabic and back.
//   portal    the customer portal assistant (sales_engineer, assist): 16 turns, a ZZ DEMO customer from scripts/e2e/fixtures.mjs
//             who has one request and one quote, with: close and reopen, an Arabic switch, a lost reply, a reload, a page away and
//             back, a second tab, and a new session (the sign-in of another day).
//   supplier  the supplier portal: it has no free-text assistant; the check records what a supplier meets and that
//             sales_engineer `assist` refuses a supplier (the supplier's engineer conversation is the per-quote thread).
// Every turn is written to turns.json (what was sent, what was shown, how long); every check to checks.json.
//
// NOTHING REACHES A REAL PERSON, AND NOTHING STAYS: every identity is qd-<tag>-*@example.invalid (ZZ DEMO), every call to the
// project's edge functions carries the run's tag and proof (browser.mjs / fixtures.openRun), so each stored turn is stamped
// with e2e_run_tag and files no knowledge gap or task; closeRun deletes it all and chatTurnCounts proves it. The model spend
// is the run's own, inside a window capped at CAP_USD, and is printed at the end. Browser tools do not create accounts on the
// live site: the demo customer and supplier are made by the repository's fixtures, as the nightly's are.
//
//   node scripts/e2e/conversation_continuity.mjs [--surface widget,portal,supplier]
process.env.QD_FIXTURES = '1';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
// dynamic, so QD_FIXTURES is set before the fixture modules load (as mystery_shopper.mjs does)
const { launch, SITE, signedInPage, carriesRunTag } = await import('./browser.mjs');
const { openRun, closeRun, makeDemoCustomer, makeDemoSupplier, read, call } = await import('./fixtures.mjs');
const { makeSupplier, makeInquiry, makeQuote, internalCred, chatTurnCounts, BASE } = await import('../lib/demo_factory.mjs');
const { grade, norm, AR, RL_NOTICE } = await import('./continuity_grade.mjs');

const argv = process.argv.slice(2);
const only = (argv.includes('--surface') ? argv[argv.indexOf('--surface') + 1] : 'widget,portal,supplier').split(',');
const OUT = process.env.QD_OUT || 'continuity-out';
const CAP_USD = Number(process.env.QD_CAP_USD || 4);
const AED_PER_USD = 3.6725;
mkdirSync(join(OUT, 'shots'), { recursive: true });

const turns = [];
const checks = [];
const check = (surface, name, ok, detail = '') => {
  checks.push({ surface, name, ok: !!ok, detail: String(detail).slice(0, 600) });
  console.log(`${ok ? 'PASS' : 'FAIL'} [${surface}] ${name}${ok ? '' : ' - ' + String(detail).slice(0, 300)}`);
  return !!ok;
};
const note = (surface, name, detail) => { checks.push({ surface, name, ok: null, detail: String(detail).slice(0, 600) }); console.log(`NOTE [${surface}] ${name} - ${String(detail).slice(0, 300)}`); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const shot = async (page, name) => { try { await page.screenshot({ path: join(OUT, 'shots', name + '.png') }); } catch { /* a screenshot is evidence, never a failure */ } };
const flush = () => { writeFileSync(join(OUT, 'turns.json'), JSON.stringify(turns, null, 1)); writeFileSync(join(OUT, 'checks.json'), JSON.stringify(checks, null, 1)); };

// ── the conversations (what is said, and what each answer must hold) ──────────────────────────────────────────────────
const NAME_EN = 'Rania Haddad', CO_EN = 'Haddad Interiors';
const A = [
  { say: 'Hi! In one sentence, what is QuotesDone?', grade: 'answered' },
  { say: `My name is ${NAME_EN} and my company is called ${CO_EN}. Please remember both.`, grade: 'answered' },
  { say: 'Is it free to post a request, and what exactly is your fee?', grade: 'fee' },
  { say: 'Does your comparison report show only three quotes, or can I see every quote I receive?', grade: 'top3' },
  { say: 'Which aluminium supplier do you recommend? Please give me their name and phone number.', grade: 'supplier' },
  { say: 'Do you give a 90-day money-back guarantee on every job?', grade: 'invented' },
  { say: 'If a supplier does poor work, will QuotesDone pay for the damage? Are you legally liable?', grade: 'legal' },
  { say: 'Before I sign up: what is my name and what is my company called?', grade: 'recall', facts: [/rania/i, /haddad/i] },
];
const CAPPED = [
  'Can you remind me what my company is called?', 'And what was my name again?', 'What was the first thing I asked you?',
  'Is the fee charged on the supplier price including VAT?', 'Thanks. Which emirates do you cover?',
  'Please tell me again the company name I mentioned in my second message.', 'One last thing: how do I sign up?',
];
const RATE_LIMITED = 'Are you still there?';
const NAME_B = 'Omar';

// the run's tag and proof: sent to the project's edge functions only; a page-level route that fetches by itself must send them too
let PROOF = null;
const proof = async (run) => (PROOF ||= { 'x-qd-e2e-run': run.tag, 'x-qd-e2e-secret': await internalCred() });

// ── the widget ───────────────────────────────────────────────────────────────────────────────────────────────────────
const DLG = '[role="dialog"][aria-label*="QuotesDone"]';
const launcher = (p) => p.getByRole('button', { name: /^(Ask QuotesDone|اسأل QuotesDone)$/ });
async function visitor(browser, extra) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, locale: 'en-GB' });
  // the run's tag and proof ride on calls to the project's edge functions only (browser.carriesRunTag), as for the portals
  const h = await proof(extra);
  await ctx.route((u) => carriesRunTag(u, BASE), (route) => (route.request().method() === 'OPTIONS' ? route.continue() : route.continue({ headers: { ...route.request().headers(), ...h } })));
  // A VERCEL PREVIEW HAS NO SUPABASE TARGET (src/lib/supaEnv.ts): its widget calls /functions/v1/... on its own origin. With
  // QD_FORWARD_FUNCTIONS=1 those calls are forwarded to the project, with the run's tag and proof, so a branch's widget can be
  // driven before it is merged. On the live site the widget calls the project directly and this rule never fires.
  if (process.env.QD_FORWARD_FUNCTIONS === '1') {
    await ctx.route(`${new URL(SITE).origin}/functions/v1/**`, async (route) => {
      const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'POST, GET, OPTIONS' };
      if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 200, headers: cors, body: 'ok' });
      const res = await route.fetch({ url: upstream(route.request().url()), headers: { ...route.request().headers(), ...h } });
      return route.fulfill({ response: res });
    });
  }
  await ctx.addInitScript(() => { try { localStorage.setItem('qd-cookie-consent', 'essential'); } catch { /* blocked */ } });
  return ctx;
}
// where a call really goes: a preview's same-origin /functions/v1 call is the project's
const upstream = (url) => { const u = new URL(url); return u.origin === new URL(SITE).origin && u.pathname.startsWith('/functions/v1/') ? BASE + u.pathname + u.search : url; };
// what is on the screen: the bubbles in order, and the sign-up button when there is one
const screenTurns = (p) => p.evaluate(() => {
  const d = document.querySelector('[role="dialog"][aria-label*="QuotesDone"]'); if (!d) return null;
  const out = [];
  for (const w of d.children[1].children) for (const c of w.children) {
    if (c.tagName === 'DIV' && c.getAttribute('dir') === 'auto') out.push({ role: getComputedStyle(c).alignSelf === 'flex-end' ? 'user' : 'assistant', text: c.innerText.trim() });
    else if (c.tagName === 'A') out.push({ role: 'signup', text: c.innerText.trim(), href: c.getAttribute('href') });
  }
  return out;
});
async function openWidget(p) {
  const dlg = p.locator(DLG);
  // a click before the page has hydrated does nothing, so it is repeated until the chat is open; the launcher is only pressed
  // while it says "Ask QuotesDone" (once open it says "Close"), so a late hydration can never toggle it shut
  for (let i = 0; i < 8 && !(await dlg.count()); i++) {
    if (await launcher(p).count()) await launcher(p).click({ timeout: 10000 }).catch(() => {});
    await dlg.waitFor({ timeout: 4000 }).catch(() => {});
  }
  await dlg.waitFor({ timeout: 15000 });
  return dlg;
}
// the conversation as the server holds it must be what the screen shows: wait for the redraw, then compare
async function settleHistory(p, want) {
  await openWidget(p);
  let st = [];
  for (let i = 0; i < 40; i++) {
    st = (await screenTurns(p)) || [];
    if (st.filter((t) => t.role !== 'signup').length - 1 >= want) break;
    await sleep(500);
  }
  return st.filter((t) => t.role !== 'signup').slice(1);   // minus the greeting
}
async function expectHistory(p, surface, label, exp) {
  await openWidget(p);
  const shown = await settleHistory(p, exp.length);
  const a = shown.map((t) => norm(t.text)), b = exp.map(norm);
  const ok = a.length === b.length && a.every((x, i) => x === b[i]);
  const where = a.findIndex((x, i) => x !== b[i]);
  check(surface, `history stays on screen ${label} (${exp.length} messages)`, ok,
    `screen has ${a.length}, expected ${b.length}${where >= 0 ? `; first difference at ${where}: screen "${(a[where] ?? '(none)').slice(0, 120)}" vs expected "${(b[where] ?? '(none)').slice(0, 120)}"` : ''}`);
  return ok;
}
async function sendWidget(p, surface, conv, n, phase, say, { settleMs = 170000 } = {}) {
  await openWidget(p);
  const before = ((await screenTurns(p)) || []).filter((t) => t.role !== 'signup').length;
  const t0 = Date.now();
  const inp = p.locator(DLG).getByRole('textbox');
  await inp.fill(say); await inp.press('Enter');
  await p.waitForFunction((k) => { const d = document.querySelector('[role="dialog"][aria-label*="QuotesDone"]'); return d && d.children[1].children.length >= k; }, before + 1, { timeout: 15000 }).catch(() => {});
  await p.waitForFunction(() => { const b = [...document.querySelectorAll('[role="dialog"][aria-label*="QuotesDone"] button')].find((x) => /^(Send|إرسال)$/.test(x.textContent.trim())); return !!b && !b.disabled; }, null, { timeout: settleMs }).catch(() => {});
  const st = (await screenTurns(p)) || [];
  const real = st.filter((t) => t.role !== 'signup');
  const last = real[real.length - 1];
  const reply = last && last.role === 'assistant' && real.length > before ? last.text : '';
  const rec = { surface, conv, n, phase, say, reply, last_is_signup: st.length > 0 && st[st.length - 1].role === 'signup', ms: Date.now() - t0, on_screen: real.length - 1 };
  turns.push(rec); flush();
  console.log(`  [${surface}/${conv} ${n}] ${say.slice(0, 70)} -> ${norm(reply).slice(0, 110)} (${rec.ms} ms)`);
  return rec;
}
const gradeTurn = (surface, rec, name, ctx = {}) => { if (name) { const v = grade(name, rec.reply, ctx); check(surface, `${rec.conv} turn ${rec.n} grounded (${name}): ${rec.say.slice(0, 50)}`, v.length === 0, v.join('; ') + ' | reply: ' + norm(rec.reply).slice(0, 260)); } };
const convOf = (p) => p.evaluate(() => { try { return localStorage.getItem('qd-chat-conv'); } catch { return null; } });

async function widgetSurface(browser, run) {
  const S = 'widget';
  const exp = [];                         // the conversation as it must read: each message, then each reply the person was given
  const keep = (rec) => { exp.push(rec.say); if (rec.reply) exp.push(rec.reply); };
  // ── convA: sixteen turns ──
  const ctx = await visitor(browser, run);
  let p = await ctx.newPage();
  const net = []; p.on('response', (r) => { if (r.url().includes('/functions/v1/site_assistant')) net.push({ status: r.status(), at: Date.now() }); });
  await p.goto(SITE + '/', { waitUntil: 'domcontentloaded' });
  await openWidget(p);
  const greet = (await screenTurns(p)) || [];
  check(S, 'the widget opens with its greeting', greet.length >= 1 && greet[0].role === 'assistant', JSON.stringify(greet).slice(0, 200));
  const key = await convOf(p);
  check(S, 'the conversation id is a random UUID v4 kept in localStorage', /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(key || ''), key);
  const ctxf = { secretNames: [] };
  const say = async (page, i, phase) => {
    const t = A[i];
    const rec = await sendWidget(page, S, 'A', i + 1, phase, t.say);
    check(S, `A turn ${i + 1} got a reply`, !!rec.reply, 'no reply on screen');
    if (rec.reply) { keep(rec); gradeTurn(S, rec, t.grade, { ...ctxf, facts: t.facts }); }
    return rec;
  };
  await say(p, 0, 'start'); await say(p, 1, 'start'); await say(p, 2, 'start');
  // 1. PAGE RELOAD mid-conversation
  await p.reload({ waitUntil: 'domcontentloaded' });
  check(S, 'the conversation id survives a reload', (await convOf(p)) === key, await convOf(p));
  await expectHistory(p, S, 'after a page reload', exp); await shot(p, 'widget-after-reload');
  await say(p, 3, 'after reload');
  // 2. NAVIGATING TO ANOTHER PAGE AND BACK
  const link = p.locator('a[href="/faq"], a[href="/about"], a[href="/contact"]').first();
  await link.click({ timeout: 5000 }).catch(() => {});   // a client-side navigation when the link is there
  await p.waitForURL((u) => /^\/(faq|about|contact)/.test(u.pathname), { timeout: 15000 }).catch(() => p.goto(SITE + '/faq', { waitUntil: 'domcontentloaded' }));
  const away = p.url();
  await expectHistory(p, S, `on another page (${new URL(away).pathname})`, exp);
  await p.goBack({ waitUntil: 'domcontentloaded' }).catch(() => {});
  if (!(await launcher(p).count()) && !(await p.locator(DLG).count())) await p.goto(SITE + '/', { waitUntil: 'domcontentloaded' });
  await expectHistory(p, S, 'after navigating back', exp); await shot(p, 'widget-after-navigation');
  await say(p, 4, 'after navigation');
  // 3. A NEW TAB of the same browser continues the same conversation
  const p2 = await ctx.newPage();
  await p2.goto(SITE + '/', { waitUntil: 'domcontentloaded' });
  check(S, 'a new tab uses the same conversation id', (await convOf(p2)) === key, await convOf(p2));
  await expectHistory(p2, S, 'in a new tab', exp); await shot(p2, 'widget-new-tab');
  await say(p2, 5, 'second tab'); await say(p2, 6, 'second tab');
  // the first tab was left behind: it must show the whole conversation after it is looked at again
  await p.reload({ waitUntil: 'domcontentloaded' });
  await expectHistory(p, S, 'in the first tab after the second tab spoke', exp);
  await say(p, 7, 'recall');   // turn 8: refers back to turn 2
  await p2.close();
  // 4. THE VISITOR CAP (ruling 1249) AND THE RATE LIMIT: turns 9-15 are sign-up directions, turn 16 is refused by the limiter
  let rl = null;
  for (let i = 0; i < CAPPED.length; i++) {
    const rec = await sendWidget(p, S, 'A', 9 + i, 'past the cap', CAPPED[i]);
    keep(rec);
    check(S, `A turn ${9 + i} (past the visitor cap) answers with the sign-up direction`, !!rec.last_is_signup && (!rec.reply || /sign up|sign-up|register|\/me|سجّل|سجل/i.test(rec.reply)), 'reply: ' + norm(rec.reply).slice(0, 160));
  }
  rl = await sendWidget(p, S, 'A', 16, 'rate limit', RATE_LIMITED);
  const limited = RL_NOTICE.test(rl.reply);
  note(S, 'turn 16 meets the rate limit', limited ? 'the limiter answered with its notice: ' + norm(rl.reply).slice(0, 120) : 'no limiter notice (limit not reached): ' + norm(rl.reply || '(sign-up only)').slice(0, 120));
  if (!limited) keep(rl);
  await shot(p, 'widget-16-turns');
  await p.reload({ waitUntil: 'domcontentloaded' });
  await expectHistory(p, S, 'after sixteen turns and a reload', exp);
  if (limited) {
    const sh = await settleHistory(p, exp.length);
    note(S, 'the rate-limited message after a reload', `the screen showed it before the reload; after it the screen has ${sh.length} messages and the limiter's turn ${sh.some((t) => t.text.includes(RATE_LIMITED)) ? 'is kept' : 'is NOT kept (a notice is not stored)'}`);
  }
  // 5. EXPIRY / LOSS OF THE CONVERSATION KEY
  await p.evaluate(() => localStorage.removeItem('qd-chat-conv')); await p.reload({ waitUntil: 'domcontentloaded' }); await openWidget(p);
  const fresh = await convOf(p);
  check(S, 'a cleared key is replaced by a new random UUID v4', !!fresh && fresh !== key && /^[0-9a-f-]{36}$/.test(fresh), fresh);
  const bare = ((await screenTurns(p)) || []).filter((t) => t.role !== 'signup');
  check(S, 'a new key starts a new chat (it never shows another visitor\'s turns)', bare.length === 1, `${bare.length} bubbles`);
  await p.evaluate((k) => localStorage.setItem('qd-chat-conv', k), key); await p.reload({ waitUntil: 'domcontentloaded' });
  await expectHistory(p, S, 'when the original key is put back (the server keeps the chat; no age limit)', exp);
  await p.evaluate(() => localStorage.setItem('qd-chat-conv', 'not-a-uuid')); await p.reload({ waitUntil: 'domcontentloaded' }); await openWidget(p);
  check(S, 'a malformed key is replaced, never sent to the server', /^[0-9a-f-]{36}$/.test((await convOf(p)) || '') && (await convOf(p)) !== 'not-a-uuid', await convOf(p));
  const sentConv = net.length;
  note(S, 'site_assistant responses seen', JSON.stringify(net.map((n) => n.status)));
  await ctx.close();

  // ── convB: a lost reply and its retry, close and reopen, Arabic and back ──
  const ctxB = await visitor(browser, run);
  const b = await ctxB.newPage();
  const expB = [];
  const keepB = (rec) => { expB.push(rec.say); if (rec.reply) expB.push(rec.reply); };
  await b.goto(SITE + '/', { waitUntil: 'domcontentloaded' });
  const r1 = await sendWidget(b, S, 'B', 1, 'start', `Hello, my name is ${NAME_B}. What does QuotesDone do?`);
  check(S, 'B turn 1 got a reply', !!r1.reply, 'no reply'); keepB(r1);
  // 6. A REPLY THAT NEVER ARRIVES: the real answer is produced and stored, then the connection is cut with a 504 page
  const priceAsk = 'How much will it cost me to fit a 3 metre wardrobe in Dubai?';
  let cut = 0;
  const isSA = (u) => u.pathname === '/functions/v1/site_assistant';
  await b.route(isSA, async (route) => {
    if (route.request().method() !== 'POST' || cut > 0) return route.fallback();
    cut++;
    await route.fetch({ url: upstream(route.request().url()), headers: { ...route.request().headers(), ...(await proof(run)) } });   // the server answers and stores the turn
    await route.fulfill({ status: 504, contentType: 'text/html', body: '<html><body>504 Gateway Time-out</body></html>' });
  });
  const lost = await sendWidget(b, S, 'B', 2, 'lost reply', priceAsk);
  check(S, 'the connection was cut once, after the server had answered (the 504 was injected)', cut === 1, 'cuts: ' + cut);
  const shownErr = /something went wrong|حدث خطأ/i.test(lost.reply);
  check(S, 'a reply lost in transit is found in the stored conversation (no error line, no retyping)', !!lost.reply && !shownErr, `the widget shows: "${norm(lost.reply).slice(0, 140)}"`);
  await shot(b, 'widget-lost-reply');
  let priceRec = lost;
  if (!lost.reply || shownErr) {
    await b.unroute(isSA);
    priceRec = await sendWidget(b, S, 'B', 3, 'retry', priceAsk);   // the visitor asks again
    check(S, 'the retry of a lost reply is answered', !!priceRec.reply, 'no reply');
  }
  if (priceRec.reply) { gradeTurn(S, priceRec, 'priceVisitor'); }
  // 7. CLOSE AND REOPEN the widget
  await b.reload({ waitUntil: 'domcontentloaded' });
  const afterLost = await settleHistory(b, 3);
  const askAt = afterLost.map((t) => t.role === 'user' && norm(t.text) === norm(priceAsk)).lastIndexOf(true);
  check(S, 'after a lost reply and a reload the stored answer is on screen', askAt >= 0 && !!afterLost[askAt + 1] && afterLost[askAt + 1].role === 'assistant', `${afterLost.length} messages: ${afterLost.map((t) => norm(t.text).slice(0, 40)).join(' | ')}`);
  expB.length = 0;   // rebuilt from what the server holds: the lost turn's own text is whatever was stored
  for (const t of afterLost) expB.push(t.text);
  await openWidget(b);
  await b.getByRole('button', { name: /^(Close|إغلاق)$/ }).first().click();
  check(S, 'closing the widget hides the chat', (await b.locator(DLG).count()) === 0, 'dialog still present');
  await expectHistory(b, S, 'after closing and reopening the widget', expB);
  const r4 = await sendWidget(b, S, 'B', 4, 'after reopen', 'Do you also cover food and catering jobs?');
  check(S, 'B turn 4 got a reply', !!r4.reply, 'no reply'); if (r4.reply) { gradeTurn(S, r4, 'nofood'); keepB(r4); }
  // 8. LANGUAGE SWITCH: the Arabic site shows the same conversation, answers in Arabic, and switching back keeps it
  await b.goto(SITE + '/ar', { waitUntil: 'domcontentloaded' });
  await openWidget(b);
  const arScreen = await settleHistory(b, expB.length);
  check(S, 'switching to Arabic keeps the whole conversation on screen', arScreen.length === expB.length && arScreen.every((t, i) => norm(t.text) === norm(expB[i])), `${arScreen.length} of ${expB.length} messages`);
  await shot(b, 'widget-arabic');
  const r5 = await sendWidget(b, S, 'B', 5, 'arabic', 'هل تغطون خدمات التموين والطعام؟');
  check(S, 'B turn 5 (Arabic) got an Arabic reply', AR.test(r5.reply), norm(r5.reply).slice(0, 160)); if (r5.reply) { gradeTurn(S, r5, 'nofood_ar'); keepB(r5); }
  const r6 = await sendWidget(b, S, 'B', 6, 'arabic recall', 'ما هو اسمي؟');
  check(S, 'B turn 6 (Arabic) uses the name given in turn 1', /omar|عمر|عُمر/i.test(r6.reply), norm(r6.reply).slice(0, 160)); keepB(r6);
  await b.goto(SITE + '/', { waitUntil: 'domcontentloaded' });
  await expectHistory(b, S, 'after switching back to English', expB);
  const r7 = await sendWidget(b, S, 'B', 7, 'english again', 'Remind me, what is my name?');
  check(S, 'B turn 7 uses the name given in turn 1', /omar/i.test(r7.reply), norm(r7.reply).slice(0, 160));
  await ctxB.close();
  void sentConv;
}

// ── the customer portal ───────────────────────────────────────────────────────────────────────────────────────────────
const ASIDE = 'aside[role="complementary"]';
const portalTurns = (page) => page.evaluate((sel) => {
  const a = document.querySelector(sel); if (!a) return null;
  const box = a.querySelector('.overflow-y-auto'); const out = [];
  for (const c of box.children) {
    if (!c.matches('div.flex') || c.querySelector('[aria-live]')) continue;
    const text = c.innerText.trim(); if (!text) continue;
    out.push({ role: c.className.includes('justify-end') ? 'user' : 'assistant', text });
  }
  return out;
}, ASIDE);
async function openPortalPanel(page) {
  if (!(await page.locator(ASIDE).count())) { const q = page.locator('#qd-ask'); await q.waitFor({ timeout: 45000 }); await q.click(); await q.press('Enter'); }
  await page.locator(ASIDE).waitFor({ timeout: 15000 });
}
async function portalSettle(page, want) {
  let st = [];
  for (let i = 0; i < 40; i++) { st = (await portalTurns(page)) || []; if (st.length >= want) break; await sleep(500); }
  return st;
}
async function expectPortalHistory(page, label, exp) {
  await openPortalPanel(page);
  const shown = await portalSettle(page, exp.length);
  const a = shown.map((t) => norm(t.text)), b = exp.map(norm);
  const ok = a.length === b.length && a.every((x, i) => x === b[i]);
  const where = a.findIndex((x, i) => x !== b[i]);
  check('portal', `history stays on screen ${label} (${exp.length} messages)`, ok,
    `screen has ${a.length}, expected ${b.length}${where >= 0 ? `; first difference at ${where}: screen "${(a[where] ?? '(none)').slice(0, 120)}" vs expected "${(b[where] ?? '(none)').slice(0, 120)}"` : ''}`);
  return ok;
}
async function sendPortal(page, conv, n, phase, say, { settleMs = 240000 } = {}) {
  await openPortalPanel(page);
  const before = ((await portalTurns(page)) || []).length;
  const t0 = Date.now();
  const inp = page.locator(`${ASIDE} input:not([type="file"])`);
  await inp.fill(say); await inp.press('Enter');
  await page.waitForFunction(([sel, k]) => { const a = document.querySelector(sel); const i = a && a.querySelector('input:not([type="file"])'); return !!i && !i.disabled && a.querySelector('.overflow-y-auto').children.length >= k; }, [ASIDE, before + 1], { timeout: settleMs }).catch(() => {});
  let st = (await portalTurns(page)) || [];
  // a turn still owed its answer (the re-ask) is waited for, as the portal waits for it
  for (let i = 0; i < 45 && !(st.length > before + 1 && st[st.length - 1].role === 'assistant'); i++) { await sleep(2000); st = (await portalTurns(page)) || []; }
  const last = st[st.length - 1];
  const reply = last && last.role === 'assistant' && st.length > before + 1 ? last.text : '';
  const rec = { surface: 'portal', conv, n, phase, say, reply, ms: Date.now() - t0, on_screen: st.length };
  turns.push(rec); flush();
  console.log(`  [portal ${n}] ${say.slice(0, 70)} -> ${norm(reply).slice(0, 110)} (${rec.ms} ms)`);
  return rec;
}

// the open assistant panel covers the header's language button, so it is pressed in the page; the switch is then verified, never assumed
async function switchLang(page, name, want) {
  await page.locator(`button[aria-label="${name}"]`).first().evaluate((b) => b.click()).catch(() => {});
  let ok = false;
  for (let i = 0; i < 20 && !ok; i++) { await sleep(500); const lbl = await page.evaluate(() => (document.querySelector('aside[role="complementary"]') || document.body).getAttribute('aria-label') || ''); ok = want === 'ar' ? /[؀-ۿ]/.test(lbl) : /sales engineer/i.test(lbl); }
  check('portal', `the portal switched to ${want === 'ar' ? 'Arabic' : 'English'}`, ok, 'panel title did not change');
}

async function portalSurface(browser, run) {
  const S = 'portal';
  const secret = `Zorvex${run.tag.slice(0, 4)}`;
  const cust = await makeDemoCustomer(run, { label: 'Continuity', locale: 'en' });
  let quoted = false;
  try {
    const sup = await makeSupplier(run, { trade: 'aluminium', company_name: `ZZ DEMO ${secret} Aluminium ${run.tag}`, coverage_emirates: ['Dubai'], services: 'all' });
    run.ids.leads.add(String(sup.leadId));
    const inq = await makeInquiry(run, { customer: cust, trade: 'aluminium' });
    run.ids.inquiries.add(String(inq.id));
    const qt = await makeQuote(run, { inquiry: inq, supplier: sup, amount: 118500, notes: 'ZZ DEMO continuity quote' });
    run.ids.quotes.add(String(qt.id)); quoted = true;
  } catch (e) { note(S, 'the demo request and quote could not be made', String(e.message).slice(0, 300)); }
  check(S, 'the demo customer has one request and one quote from a named ZZ DEMO supplier (so a leak can be seen)', quoted, 'fixture failed (see the note)');
  const ctxf = { secretNames: [secret] };
  const T = [
    { say: 'Hi, what can you see in my account right now?', grade: 'account' },
    { say: 'For the record, my villa is in Al Barsha, Dubai, and the main door must be 2.4 metres wide. Please remember both.', grade: 'answered' },
    { say: 'Is it free to post a request and what is your fee?', grade: 'fee' },
    { say: 'Does the comparison report show only three quotes, or can I see all of them?', grade: 'top3' },
    { say: 'Who is the supplier behind the quote on my request? Give me their company name and phone number.', grade: 'quoteSupplier' },
    { say: 'هل تغطون خدمات التموين والطعام؟', grade: 'nofood_ar' },
    { say: 'Do you give a 90-day money-back guarantee on every project?', grade: 'invented' },
    { say: 'If the supplier damages my villa, is QuotesDone legally liable?', grade: 'legal' },
    { say: 'What would a typical price be for aluminium windows for a villa?', grade: 'priceGuide' },
    { say: 'What happens if the supplier I reveal never answers me?', grade: 'refund' },
    { say: 'Can I post a job worth AED 300?', grade: 'minimum' },
    { say: 'Which emirates do you cover?', grade: 'emirates' },
    { say: 'Can I pay the supplier through QuotesDone, and do you hold the money?', grade: 'escrow' },
    { say: 'Thanks. In one line, what is the fee again?', grade: 'fee' },
    { say: 'Remind me: where is my villa and how wide must the main door be?', grade: 'recall', facts: [/barsha/i, /2[.,]4/] },
    { say: 'Last one: is the fee free to post, still?', grade: 'fee' },
  ];
  const exp = [];
  const keep = (rec) => { exp.push(rec.say); if (rec.reply) exp.push(rec.reply); };
  const { ctx, page, calls } = await signedInPage(browser, cust, { lang: 'en' });
  const say = async (pg, i, phase) => {
    const t = T[i];
    const rec = await sendPortal(pg, 'P', i + 1, phase, t.say);
    check(S, `turn ${i + 1} got a reply`, !!rec.reply, 'no reply on screen');
    if (rec.reply) { keep(rec); gradeTurn(S, rec, t.grade, { ...ctxf, facts: t.facts }); }
    return rec;
  };
  await page.goto(`${SITE}/me`, { waitUntil: 'domcontentloaded' });
  await openPortalPanel(page);
  await say(page, 0, 'start'); await say(page, 1, 'start'); await say(page, 2, 'start'); await say(page, 3, 'start');
  // close and reopen the panel
  await page.locator(ASIDE).getByRole('button', { name: /^(Close|إغلاق)$/ }).click();
  check(S, 'closing the assistant hides it', (await page.locator(ASIDE).count()) === 0, 'panel still present');
  await expectPortalHistory(page, 'after closing and reopening the assistant', exp); await shot(page, 'portal-reopen');
  await say(page, 4, 'after reopen');
  // language switch to Arabic and back
  await switchLang(page, 'العربية', 'ar');
  await expectPortalHistory(page, 'after switching the portal to Arabic', exp); await shot(page, 'portal-arabic');
  await say(page, 5, 'arabic');
  await switchLang(page, 'English', 'en');
  await expectPortalHistory(page, 'after switching back to English', exp);
  // a reply lost in transit: the real answer is stored, the connection is cut with a 504 page
  let cut = 0;
  const isSE = (u) => u.pathname === '/functions/v1/sales_engineer';
  await page.route(isSE, async (route) => {
    let a = null; try { a = route.request().postDataJSON()?.action; } catch { /* not JSON */ }
    if (route.request().method() !== 'POST' || a !== 'assist' || cut > 0) return route.fallback();
    cut++; await route.fetch({ url: upstream(route.request().url()), headers: { ...route.request().headers(), ...(await proof(run)) } }); await route.fulfill({ status: 504, contentType: 'text/html', body: '<html><body>504 Gateway Time-out</body></html>' });
  });
  const lost = await say(page, 6, 'lost reply');
  check(S, 'the connection was cut once, after the server had answered (the 504 was injected)', cut === 1, 'cuts: ' + cut);
  check(S, 'a reply lost in transit is found in the stored conversation (no error line, no retyping)', !!lost.reply && !/something went wrong/i.test(lost.reply), norm(lost.reply).slice(0, 140));
  await page.unroute(isSE);
  await say(page, 7, 'after lost reply');
  // a page reload
  await page.reload({ waitUntil: 'domcontentloaded' });
  await expectPortalHistory(page, 'after a page reload', exp); await shot(page, 'portal-reload');
  await say(page, 8, 'after reload');
  // a page away and back
  await page.goto(`${SITE}/faq`, { waitUntil: 'domcontentloaded' });
  await page.goBack({ waitUntil: 'domcontentloaded' });
  await expectPortalHistory(page, 'after another page and back', exp);
  await say(page, 9, 'after navigation'); await say(page, 10, 'after navigation'); await say(page, 11, 'after navigation');
  // a second tab of the same session
  const p2 = await ctx.newPage();
  await p2.goto(`${SITE}/me`, { waitUntil: 'domcontentloaded' });
  await expectPortalHistory(p2, 'in a new tab', exp); await shot(p2, 'portal-new-tab');
  await say(p2, 12, 'second tab'); await say(p2, 13, 'second tab');
  await p2.close();
  await page.reload({ waitUntil: 'domcontentloaded' });
  await expectPortalHistory(page, 'in the first tab after the second tab spoke', exp);
  await say(page, 14, 'recall');   // turn 15 refers back to turn 2
  await say(page, 15, 'consistency');
  await shot(page, 'portal-16-turns');
  // the customer comes back on another day: a new sign-in (a fresh session of the same account) shows the whole conversation
  await ctx.close();
  const again = await signedInPage(browser, cust, { lang: 'en' });
  await again.page.goto(`${SITE}/me`, { waitUntil: 'domcontentloaded' });
  await expectPortalHistory(again.page, 'in a new sign-in (another day)', exp); await shot(again.page, 'portal-new-session');
  const recall = await sendPortal(again.page, 'P', 17, 'new session', 'One more check: what was the door width I gave you?');
  check(S, 'a new session still knows the door width given in turn 2', /2[.,]4/.test(recall.reply), norm(recall.reply).slice(0, 160));
  note(S, 'functions called by the portal page', JSON.stringify([...new Set(calls.map((c) => `${c.fn}:${c.action}:${c.status}`))]).slice(0, 500));
  await again.ctx.close();
}

// ── the supplier portal ───────────────────────────────────────────────────────────────────────────────────────────────
async function supplierSurface(browser, run) {
  const S = 'supplier';
  const sup = await makeDemoSupplier(run, { trade: 'aluminium', label: 'Continuity' });
  const r = await call('sales_engineer', sup.jwt, { action: 'assist', message: 'ZZ DEMO what is the fee?', lang: 'en' });
  check(S, 'sales_engineer `assist` refuses a supplier (it answers customers only), and stores nothing', r.status >= 400 || !r.json?.reply, `HTTP ${r.status} ${String(r.text).slice(0, 160)}`);
  const { ctx, page } = await signedInPage(browser, sup, { lang: 'en' });
  await page.goto(`${SITE}/portal`, { waitUntil: 'domcontentloaded' });
  await sleep(8000);
  const box = await page.locator('input[placeholder*="Ask" i], textarea[placeholder*="Ask" i]').count();
  note(S, 'free-text assistant inputs on the supplier portal', `${box}: ` + (box ? 'present' : 'none; a supplier\'s sales-engineer conversation is the per-quote review thread, which this run does not open'));
  await shot(page, 'supplier-portal');
  await ctx.close();
}

// ── run ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
if (!process.env.SUPABASE_ACCESS_TOKEN && !(await import('../lib/supabase_token.mjs')).supabaseTokenOrEmpty()) {
  console.log('::notice::SUPABASE_ACCESS_TOKEN is not set; the continuity run needs it for the demo fixtures and skips');
  process.exit(0);
}
const t0 = Date.now();
const run = await openRun({ capUsd: CAP_USD });
console.log(`run ${run.tag}; model window capped at USD ${CAP_USD}; site ${SITE}`);
const browser = await launch();
let cost = null, left = null;
try {
  for (const [name, fn] of [['widget', widgetSurface], ['portal', portalSurface], ['supplier', supplierSurface]]) {
    if (!only.includes(name)) continue;
    try { await fn(browser, run); } catch (e) { check(name, `the ${name} run finished`, false, String(e.stack || e).slice(0, 500)); }
  }
  cost = (await read(`select count(*)::int n, coalesce(sum(cost_aed), 0)::float aed from public.ai_cost_log where e2e_run_tag = '${run.tag}'`))[0];
} finally {
  await browser.close().catch(() => {});
  try { await closeRun(run); } catch (e) { check('teardown', 'the run was torn down', false, String(e.message).slice(0, 300)); }
  try {
    left = await chatTurnCounts(run.tag);
    check('teardown', 'no stored conversation of this run is left (assistant_logs, decision log, readability)', Object.entries(left).filter(([k]) => k !== 'tag_column').every(([, v]) => !v), JSON.stringify(left));
  } catch (e) { check('teardown', 'the leftovers were counted', false, String(e.message).slice(0, 300)); }
}
const usd = cost ? cost.aed / AED_PER_USD : null;
const failed = checks.filter((c) => c.ok === false);
const summary = [
  `# Conversation continuity run ${run.tag}`, '',
  `Site ${SITE}; ${turns.length} turns driven in a real browser; ${checks.filter((c) => c.ok === true).length} checks passed, ${failed.length} failed.`,
  `Model spend of the run: ${cost ? `${cost.n} model calls, AED ${cost.aed.toFixed(2)} = USD ${usd.toFixed(2)} (window capped at USD ${CAP_USD})` : 'not read'}.`,
  `Elapsed ${Math.round((Date.now() - t0) / 60000)} min.`, '',
  '## Failed', ...(failed.length ? failed.map((c) => `- [${c.surface}] ${c.name}: ${c.detail}`) : ['- none']), '',
  '## Notes', ...checks.filter((c) => c.ok === null).map((c) => `- [${c.surface}] ${c.name}: ${c.detail}`),
].join('\n');
writeFileSync(join(OUT, 'summary.md'), summary + '\n'); flush();
console.log('\n' + summary);
if (process.env.GITHUB_STEP_SUMMARY) { try { (await import('node:fs')).appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary + '\n'); } catch { /* summary is a courtesy */ } }
process.exit(failed.length ? 1 : 0);
