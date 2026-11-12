// scripts/e2e/services_screens_walk.mjs — THE SERVICES TAB AS A SUPPLIER USES IT, for the registration certification.
// Assigned: it_engineer (12 Nov 2026), on the coordinator's brief after slice 4 (#1967) went live: the certification still walked the
// old tab ("Tick all proposed services", "Saved. Your services are confirmed"), which the three screens replaced.
//
// The three screens (src/components/portal/supplier/ServicesTab.tsx, ServiceQuestions.tsx):
//   Screen 1 "Here is what we understood your company does" (data-testid proposed-services): the rows read off his documents, under
//     his own sentence, each unticked; "Yes, we do all of these" ticks his certain rows and moves on; Next moves on.
//   The cards "A few quick questions" (question-cards, data-kind): one at a time, chips, "None of these", per-row Own team / Partner /
//     Not offered on a partner card, a textarea on the 'nothing' card; Back and Next in cards-bar.
//   The check screen (check-lists, confirm-bar): his lists (own team, through a partner, in his own words), his role, Confirm.
//
// EVERY TAP IS DECIDED BY THE FIXTURE, NEVER GUESSED (`intendedFor`): a key is his when its trade is one of the fixture's expected
// trades (registration_fixtures.mjs PROFILES[].expect); it is partner work only when its trade is in `partner_trades` (no fixture
// has one today); words (a chip with no key, a row in his own words) are his only when the fixture carries that phrase; free text is
// typed only from the fixture's `describe`. Which chip is which key is read from services_state's questions (the same rows the page
// draws), matched to the card on screen by its kind and question, never from the chip's label alone.
//
// TIMING HONESTY: every read the walk makes for its own record (counts, inner texts, services_state) and every pause it makes for the
// cards' double-tap guard (serviceQuestions.tapAllowed, 350 ms) is added to `harness.ms`, never to the supplier's time. Reads never wait:
// `count()` first, then a short `innerText`.
import { judgeCards, judgeStoredAnswers, judgeNothingUntapped } from './registration_certification_judge.mjs';

const tradeOf = (k) => String(k || '').split('.')[0];
const KEY_AT_END = /([a-z0-9_]+\.[a-z0-9_]+)$/;
export const BADGE = { partner: 'Through a partner', projects: 'From your projects', brands: 'From your brand list', check: 'Please check', words: 'Your words', licence: 'Not on your trade licence' };
const UNSURE = [BADGE.partner, BADGE.projects, BADGE.brands, BADGE.check];
const TAP_GUARD_MS = 450;   // > serviceQuestions.tapAllowed's 350 ms after a card changes

/** The fixture's rule. expect: { trades, partner_trades?, phrases?, describe?, licence_answer? } */
export function intendedFor(expect) {
  const trades = new Set(expect.trades || []), partner = new Set(expect.partner_trades || []);
  const phrases = (expect.phrases || []).map((s) => String(s).toLowerCase().trim());
  return {
    keyIsHis: (k) => !!k && (trades.has(tradeOf(k)) || partner.has(tradeOf(k))),
    keyThroughPartner: (k) => !!k && partner.has(tradeOf(k)),
    wordsAreHis: (w) => !!w && phrases.includes(String(w).toLowerCase().trim()),
    describe: expect.describe || null,
    licenceAnswer: expect.licence_answer || 'Both',
  };
}

/**
 * Screen 1. rows: [{ id, key, words, badges: [text], checked }]. "Yes, we do all of these" is pressed only when every certain row (a
 * key with no partner / projects / brand / please-check badge, and every row in his own words) is his; the uncertain rows he does are
 * ticked one by one first. Otherwise each of his rows is ticked one by one and Next is pressed.
 */
export function screen1Plan(rows, rule, { allButton = true } = {}) {
  // a row marked "Through a partner" is his only when the fixture says that trade is partner work; any other row when its trade is his
  const his = (r) => (r.key ? (r.badges.includes(BADGE.partner) ? rule.keyThroughPartner(r.key) : rule.keyIsHis(r.key)) : rule.wordsAreHis(r.words));
  const certain = rows.filter((r) => !r.key || !r.badges.some((b) => UNSURE.includes(b)));
  const useAll = allButton && certain.length > 0 && certain.every(his);
  const tick = rows.filter((r) => his(r) && !r.checked && !(useAll && certain.includes(r))).map((r) => r.id);
  const mine = rows.filter(his);
  return { useAll, tick, tapped_keys: mine.filter((r) => r.key).map((r) => r.key), tapped_words: mine.filter((r) => !r.key).map((r) => r.words),
    partner_keys: mine.filter((r) => r.key && r.badges.includes(BADGE.partner)).map((r) => r.key) };
}

/** One card. q: the stored question (kind, prompt_en, options [{ key, label_en }], multi). */
export function cardPlan(q, rule) {
  const opts = q.options || [];
  if (q.kind === 'partner') return { per: opts.map((o) => (rule.keyIsHis(o.key) ? (rule.keyThroughPartner(o.key) ? 'partner' : 'own') : 'no')) };
  if (q.kind === 'nothing') return rule.describe ? { text: rule.describe } : { trade_list: true };
  const his = opts.map((o, i) => ({ o, i })).filter(({ o }) => (o.key ? rule.keyIsHis(o.key) : rule.wordsAreHis(o.label_en))).map(({ i }) => i);
  if (!q.multi) {
    if (q.kind === 'licence') { const i = opts.findIndex((o) => o.label_en === rule.licenceAnswer); return i >= 0 ? { single: i } : { stop: 'the licence card has no "' + rule.licenceAnswer + '"' }; }
    return his.length ? { single: his[0] } : { stop: 'a single-choice card with none of his options' };
  }
  if (his.length) return { picked: his };
  const brand = q.kind === 'shown' && String(q.prompt_en || '').startsWith('Your brand list');
  return q.kind === 'shown' && !brand ? { only_inside: true } : { none: true };
}

/** What a card's plan means for what must be stored: own / partner keys, phrases, and the keys he said he does not do. */
export function cardTaps(q, plan) {
  const opts = q.options || [], t = { own: [], partner: [], words: [], declined: [] };
  if (plan.per) plan.per.forEach((v, i) => { const k = opts[i]?.key; if (!k) { if (v !== 'no') t.words.push(opts[i]?.label_en); return; } (v === 'own' ? t.own : v === 'partner' ? t.partner : t.declined).push(k); });
  const pick = plan.picked || (plan.single != null ? [plan.single] : []);
  if (q.kind !== 'licence') for (const i of pick) { const o = opts[i]; if (o?.key) t.own.push(o.key); else if (o) t.words.push(o.label_en); }
  if (plan.none || plan.only_inside) for (const o of opts) if (o.key) t.declined.push(o.key);
  // typed on the 'nothing' card: read by the sales engineer, not stored as given; counted as his (typed) for "nothing he did not tap"
  if (plan.text) t.typed = [plan.text];
  return t;
}

/**
 * Walks screen 1, the cards and the check screen, confirms, reads back what was stored and judges it.
 * page, M (the page's main), expect (intendedFor's input + role), readState() -> services_state json, timed(action, done, ack) and
 * step(name, ok, opts) as the certification has them, look(where) and shot(name) (may be no-ops), harness { ms }.
 * st: the services_state the tab is showing (the certification has just read it). Returns the record the journey keeps.
 */
export async function walkServices({ page: p, M, expect, st, readState, timed, step, look = async () => {}, shot = async () => {}, harness, sleep = (ms) => new Promise((r) => setTimeout(r, ms)) }) {
  const rule = intendedFor(expect);
  const own = harness || { ms: 0 };
  const rec = async (fn) => { const t = Date.now(); try { return await fn(); } finally { own.ms += Date.now() - t; } };
  const pause = async (ms) => { own.ms += ms; await sleep(ms); };
  const vocab = new Map(((st?.vocabulary?.trades) || []).map((t) => [t.code, t.label]));
  const W = { screen1: null, cards: [], check: null, tapped: { own: [], partner: [], words: [], declined: [], typed: [] }, checklist: [], stored: null, path: null };
  const reading = !!st?.reading;

  // ── SCREEN 1 ─────────────────────────────────────────────────────────────────────────────────────────────────────────
  const s1 = M.getByTestId('proposed-services');
  if (await s1.count()) {
    const seen = await rec(() => s1.evaluate((el) => ({
      summary: el.querySelector('[data-testid=reading-summary]')?.innerText?.trim() || null,
      rows: [...el.querySelectorAll('input[type=checkbox]')].map((i) => {
        const lab = el.querySelector(`label[for="${CSS.escape(i.id)}"]`); const id = i.id; const tail = id.split('-p-').slice(1).join('-p-');
        const badges = lab ? [...lab.querySelectorAll('span span, span > div, [class*="badge"]')].map((b) => b.innerText.trim()).filter(Boolean) : [];
        const text = lab ? lab.innerText.trim() : '';
        const quote = i.closest('li')?.querySelector('q')?.innerText?.trim() || null;
        return { id, tail, checked: i.checked, text, badges, quote };
      }),
      all: [...el.querySelectorAll('button')].some((b) => b.innerText.trim() === 'Yes, we do all of these'),
    }), null, { timeout: 2000 }).catch(() => ({ summary: null, rows: [], all: false })));
    const rows = seen.rows.map((r) => {
      const words = r.tail.startsWith('w:') ? r.tail.slice(2) : null;
      const key = words ? null : (r.tail.match(KEY_AT_END)?.[1] || null);
      // a badge is a known label at the end of the row's text, when the component's inner markup changes the text still says it
      const badges = [...new Set([...r.badges, ...Object.values(BADGE).filter((b) => r.text.endsWith(b) || r.text.includes(b))])];
      return { id: r.id, key, words, badges, checked: r.checked, label: r.text, quote: r.quote };
    });
    const plan = screen1Plan(rows, rule, { allButton: seen.all });
    W.screen1 = { summary: seen.summary, rows: rows.map((r) => ({ key: r.key, words: r.words, label: r.label, badges: r.badges, quote: r.quote, ticked_before: r.checked })),
      pressed_all: plan.useAll, ticked_one_by_one: plan.tick.length, tapped_keys: plan.tapped_keys, tapped_words: plan.tapped_words };
    step('proposed services start unticked', rows.length > 0 && rows.every((r) => !r.checked), { detail: `${rows.filter((r) => r.checked).length} of ${rows.length} ticked before the supplier acts` });
    for (const id of plan.tick) { await p.locator(`[id="${id}"]`).check().catch(() => {}); }
    const nowOn = await rec(() => s1.evaluate((el, ids) => ids.filter((id) => document.getElementById(id)?.checked).length, plan.tick, { timeout: 2000 }).catch(() => -1));
    step('screen 1: his rows ticked one by one as the fixture says', nowOn === plan.tick.length, { detail: `${nowOn} of ${plan.tick.length} took; "Yes, we do all of these" ${plan.useAll ? 'pressed' : 'not pressed'} | his keys ${plan.tapped_keys.join(', ') || 'none'}${plan.tapped_words.length ? ' | his words ' + plan.tapped_words.join('; ') : ''}` });
    W.tapped.own.push(...plan.tapped_keys.filter((k) => !plan.partner_keys.includes(k)));
    W.tapped.partner.push(...plan.partner_keys);
    W.tapped.words.push(...plan.tapped_words);
    await shot('services_screen1_ticked');
    const btn = M.getByTestId('understood-bar').getByRole('button', { name: plan.useAll ? /^Yes, we do all of these$/ : /^Next$/ });
    await btn.click();
    await M.getByTestId('question-cards').or(M.getByTestId('check-lists')).first().waitFor({ timeout: 15000 }).catch(() => {});
  }

  // ── THE CARDS ────────────────────────────────────────────────────────────────────────────────────────────────────────
  const cardsEl = M.getByTestId('question-cards');
  let questions = st?.questions || [];
  const used = new Set();
  for (let guard = 0; guard < 12 && await cardsEl.count(); guard++) {
    const seen = await rec(() => cardsEl.evaluate((el) => ({
      kind: el.dataset.kind, progress: el.querySelector('[data-testid=progress]')?.innerText?.trim() || '',
      quote: el.querySelector('p q')?.innerText?.trim() || null, ask: el.querySelector('h3')?.innerText?.trim() || '',
      chips: [...el.querySelectorAll('[role=checkbox], [role=radio]')].map((b) => b.innerText.trim()),
      rows: [...el.querySelectorAll('fieldset legend')].map((l) => l.innerText.trim()),
    }), null, { timeout: 2000 }).catch(() => null));
    if (!seen) break;
    // the stored question this card draws: same kind, its question ends with what is on screen, not answered already on this walk
    let q = questions.find((x) => !used.has(x.id) && x.kind === seen.kind && String(x.prompt_en || '').endsWith(seen.ask));
    if (!q) { questions = (await rec(() => readState().catch(() => null)))?.questions || questions; q = questions.find((x) => !used.has(x.id) && x.kind === seen.kind && String(x.prompt_en || '').endsWith(seen.ask)); }
    const labelsMatch = q && (seen.kind === 'partner' ? seen.rows : seen.chips).join('|') === (q.options || []).map((o) => o.label_en).join('|');
    const card = { kind: seen.kind, progress: seen.progress, prompt: q?.prompt_en || seen.ask, quote: seen.quote, chips: seen.kind === 'partner' ? seen.rows : seen.chips,
      keys: (q?.options || []).map((o) => o.key), trade: q?.about?.trade || null, trade_label: vocab.get(q?.about?.trade) || null,
      answer: null };
    W.cards.push(card);
    if (!q || !labelsMatch) { card.answer = { stop: q ? 'the chips on screen are not the stored question\'s options' : 'no stored question draws this card' }; break; }
    used.add(q.id);
    const plan = cardPlan(q, rule);
    card.answer = plan;
    if (plan.stop) break;
    const t = cardTaps(q, plan);
    for (const k of Object.keys(t)) W.tapped[k].push(...t[k]);
    card.picked = (plan.picked || (plan.single != null ? [plan.single] : [])).map((i) => q.options[i]?.label_en);
    await pause(TAP_GUARD_MS);
    const bar = M.getByTestId('cards-bar');
    const next = () => bar.getByRole('button', { name: /^Next$/ }).click();
    if (plan.per) {
      const fs = cardsEl.locator('fieldset');
      for (let i = 0; i < plan.per.length; i++) await fs.nth(i).getByRole('button', { name: plan.per[i] === 'own' ? /^Own team$/ : plan.per[i] === 'partner' ? /^Partner$/ : /^Not offered$/ }).click();
      await next();
    } else if (plan.picked) {
      for (const i of plan.picked) await cardsEl.getByRole('checkbox').nth(i).click();
      await next();
    } else if (plan.single != null) await cardsEl.getByRole('radio').nth(plan.single).click();
    else if (plan.none) await cardsEl.getByRole('button', { name: /^None of these$/ }).click();
    else if (plan.only_inside) await cardsEl.getByRole('button', { name: /^Only inside our own projects$/ }).click();
    else if (plan.text) { await cardsEl.locator('textarea').fill(plan.text); await next(); }
    else if (plan.trade_list) { await cardsEl.getByRole('button', { name: /^Choose my trade instead$/ }).click(); }
    // the next card, or the check screen: the answer the supplier waits for
    await page_changed(p, cardsEl, seen.progress);
  }
  async function page_changed(page, el, before) {
    for (let i = 0; i < 50; i++) {
      if (!(await el.count())) return;
      const now = await el.locator('[data-testid=progress]').innerText({ timeout: 500 }).catch(() => '');
      if (now && now !== before) return;
      await sleep(200);
    }
  }
  if (W.cards.length) {
    const j = judgeCards(W.cards);
    W.cards_verdict = j;
    step('the questions are specific and few', j.ok, { detail: `${j.count} card(s), cap ${j.cap} | ` + W.cards.map((c, i) => `${i + 1}. ${c.kind}: "${String(c.prompt).slice(-80)}" ${c.chips.length} chips${c.answer?.stop ? ' STOPPED: ' + c.answer.stop : ''}`).join(' | ') });
  } else step('the questions are specific and few', true, { deferred: !reading, detail: reading ? 'his documents left no question: no card' : 'no reading (models off): no card' });

  // ── THE CHECK SCREEN ─────────────────────────────────────────────────────────────────────────────────────────────────
  const lists = M.getByTestId('check-lists');
  await lists.first().waitFor({ timeout: 15000 }).catch(() => {});
  // TODAY'S PATH (no reading: models off, or nothing of his on the screens): his trade's services ticked from the checklist, box by box
  if (!W.tapped.own.length && !W.tapped.partner.length && !W.tapped.words.length) {
    W.path = 'checklist';
    const browse = M.getByTestId('browse-trades');
    if (await browse.count() && !(await browse.evaluate((el) => el.open, null, { timeout: 1000 }).catch(() => true))) await browse.locator('summary').click().catch(() => {});
    const ticked0 = [], missed0 = [], tick0 = Date.now();
    for (const c of (st?.checklist || []).filter((x) => (expect.trades || []).includes(x.code))) {
      // the trade's fieldset is the one holding its first service's box (each box's id ends with its key): a legend's label can differ
      const k0 = (c.services || [])[0]?.key;
      const fs = (k0 ? M.locator('fieldset').filter({ has: p.locator(`input[id$="${k0}"]`) }) : M.locator('fieldset').filter({ has: p.locator('legend', { hasText: c.label_en || c.code }) })).first();
      const boxes = await fs.locator('input[type=checkbox]').all().catch(() => []);
      for (const b of boxes) await b.check().catch(() => {});
      const on = await rec(() => fs.locator('input[type=checkbox]:checked').count().catch(() => 0));
      if (boxes.length && on === boxes.length) ticked0.push(`${c.code} ${on}/${boxes.length}`); else if (boxes.length) missed0.push(`${c.code} ${on}/${boxes.length}`);
      W.checklist.push(...(c.services || []).map((s) => s.key));
    }
    if (ticked0.length || missed0.length)
      step('his own trade\'s services ticked from the checklist', missed0.length === 0, { detail: `ticked ${ticked0.join(', ') || 'none'}${missed0.length ? ' | did not take: ' + missed0.join(', ') : ''}; ${Date.now() - tick0} ms for all the taps` });
  } else W.path = 'screens';
  W.check = await rec(() => lists.evaluate((el) => [...el.children].map((sec) => ({ title: sec.querySelector('h3')?.innerText?.trim() || '', items: [...sec.querySelectorAll('li span[dir=auto]')].map((s) => s.innerText.trim()) })).filter((s) => s.title), null, { timeout: 2000 }).catch(() => null));
  // his role: one chip, the fixture's, when none is chosen yet
  const roleGroup = M.getByRole('group', { name: /^Your role$/ });
  if (await roleGroup.count()) {
    const chips = roleGroup.getByRole('checkbox');
    const n = await chips.count(), on = await roleGroup.locator('[aria-checked=true]').count();
    if (n && !on) {
      const names = await rec(() => chips.allInnerTexts().catch(() => []));
      const i = names.findIndex((t) => expect.role && expect.role.test(t.trim()));
      await chips.nth(i >= 0 ? i : 0).click();
    }
  }
  await look('services check screen'); await shot('services_check');
  const confirm = M.getByTestId('confirm');
  const canConfirm = await confirm.isEnabled().catch(() => false);
  let saved = false, r10 = null;
  if (canConfirm) {
    // acknowledged when the button reads "Confirming…"; done when "Done." is said in the confirm bar (or an alert)
    r10 = await timed(() => confirm.click(), M.getByTestId('confirm-done').or(M.locator('[role=alert]')), M.getByRole('button', { name: /^Confirming…$/ }));
    await look('services confirmed'); await shot('services_confirmed');
    saved = /^Done\./.test(await rec(() => M.getByTestId('confirm-done').innerText({ timeout: 1000 }).catch(() => '')));
    step('"Confirm my services" confirms them', saved, { kind: 'submit', ms: r10.ms, ackMs: r10.ackMs });
  }
  W.saved = saved; W.can_confirm = canConfirm;
  // ── WHAT WAS STORED, read through services_state (the read the certification uses for the row) ─────────────────────────
  if (saved) {
    const after = await rec(() => readState().catch(() => null));
    const cap = after?.capability || {};
    W.stored = { services: cap.services || [], services_partner: cap.services_partner || after?.services_partner || [], services_implied: cap.services_implied || after?.implied_services || [] };
    // his ANSWERS are screen 1's ticks and the cards' answers (W.tapped); the checklist's boxes are today's path, judged below only
    const answered = ['own', 'partner', 'words', 'declined'].some((k) => W.tapped[k].length > 0);
    const sa = judgeStoredAnswers(W.tapped, W.stored);
    W.stored_answers = sa;
    step('every answer became a key or his words', sa.ok, { deferred: !answered, detail: answered ? `${sa.answers} answers | ${sa.missing.join('; ') || 'all stored'} | stored ${W.stored.services.length}, partner ${W.stored.services_partner.length}` : 'no screen-1 tick and no card answer of his (no reading, or nothing of his trades on them): his services came from the checklist' });
    const tappedAll = [...W.tapped.own, ...W.tapped.partner, ...W.tapped.words, ...W.tapped.typed, ...W.checklist];
    const nu = judgeNothingUntapped(tappedAll, W.stored);
    W.untapped = nu;
    step('nothing was saved that he did not tap', nu.ok, { detail: `stored ${W.stored.services.length} (${W.path}) | not tapped: ${nu.extra.join(', ') || 'none'}${nu.extra_partner.length ? ' | partner not tapped: ' + nu.extra_partner.join(', ') : ''} | curated implications the server added (services_implied, not his): ${nu.implied.join(', ') || 'none'}` });
  }
  return W;
}
