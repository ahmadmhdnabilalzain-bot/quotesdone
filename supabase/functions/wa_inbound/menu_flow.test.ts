// The WhatsApp welcome and menu, driven through the real routing with fakes for the database and
// Twilio (founder_instruction 759, 22 Sep 2026). Prevents "said hi, got no response" from coming back
// for any reason inside the routing: a greeting, a first message, every option, each audience, and a
// conversation that continues past the first reply all get an answer.
//
//   deno test --no-lock --node-modules-dir=auto supabase/functions/wa_inbound/menu_flow.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { answerFromFaq, type Content, type MenuDeps, type MenuInput, menuTurn, reofferMenu, type Turn, welcomeFirstContact } from './menu_flow.ts';
import {
  type Audience, caseConfirm, cleanName, contentKey, founderCommand, greetLine, HOURS, humanAlert, isGreeting, type Lang, MENU_BUTTON,
  MENU_IDS, menuChoice, type MenuContext, menuItems, optionReply, WELCOME_TAIL, welcomeText, withinHours,
} from './menu.ts';

const FROM = 'whatsapp:+971500000021'; // reserved ZZ DEMO fixture block

type Sent = { to: string; body: string; content?: Content };
function harness(o: { ctx?: Partial<MenuContext>; sids?: Record<string, string>; contentFails?: boolean; faq?: string | null;
                      enabled?: boolean; history?: Turn[]; weWrote?: boolean; held?: boolean; appended?: boolean } = {}) {
  const sent: Sent[] = []; const rows: Array<Record<string, unknown>> = []; const cases: string[] = []; const notified: string[] = []; const closed: string[] = [];
  const history: Turn[] = [...(o.history || [])];
  const d: MenuDeps = {
    autoreplyEnabled: () => Promise.resolve(o.enabled ?? true),
    recentTurns: () => Promise.resolve([...history]),
    weWroteRecently: () => Promise.resolve(o.weWrote ?? false),
    context: () => Promise.resolve({ audience: 'unknown', name: null, ...(o.ctx || {}) } as MenuContext),
    faq: () => Promise.resolve(o.faq ?? null),
    openCase: (_f, text) => { cases.push(text); return Promise.resolve({ ref: 'QD-S-ZZ' + cases.length, appended: o.appended ?? false, slaHours: 24 }); },
    humanHold: () => Promise.resolve(o.held ?? false),
    closeCase: (ref, reason) => { closed.push(ref + ':' + reason); return Promise.resolve({ ok: true, phone: '971500000041', lang: 'ar' as Lang, reason }); },
    closeHuman: (phone) => { closed.push('human:' + phone); return Promise.resolve(1); },
    notifyHuman: (from) => { notified.push(from); return Promise.resolve(true); },
    contentSid: (key) => Promise.resolve(o.sids?.[key] ?? null),
    send: (to, body, content) => {
      sent.push({ to, body, content });
      return Promise.resolve(content && o.contentFails ? { ok: false, err: '63xxx list not allowed' } : { ok: true });
    },
    record: (row) => {
      rows.push(row as unknown as Record<string, unknown>);
      history.unshift({ route: row.route, await: row.await, lang: row.lang });
      return Promise.resolve();
    },
  };
  return { d, sent, rows, cases, notified, closed };
}
const msg = (body: string, audience: Audience = 'unknown', extra: Partial<MenuInput> = {}): MenuInput => ({ from: FROM, body, audience, ...extra });

Deno.test('the list fits WhatsApp: 6 items, titles <= 24, descriptions <= 72, button <= 20, both languages', () => {
  for (const lang of ['en', 'ar'] as Lang[]) {
    assert(MENU_BUTTON[lang].length <= 20);
    for (const aud of ['unknown', 'customer', 'supplier'] as Audience[]) {
      const items = menuItems(lang, aud);
      assertEquals(items.map((i) => i.id), [...MENU_IDS]);
      for (const i of items) {
        assert(i.item.length <= 24, lang + ' title too long: ' + i.item);
        assert(i.description.length <= 72, lang + ' description too long: ' + i.description);
      }
    }
  }
});

Deno.test('greetings are recognised in English and Arabic, and a question is not a greeting', () => {
  for (const g of ['Hi', 'hi!', 'Hello there', 'السلام عليكم', 'السلام عليكم ورحمة الله وبركاته', 'مرحبا', 'مرحبًا', 'Good morning']) assert(isGreeting(g), g);
  for (const q of ['hi, what are your fees?', 'how do I register', 'أريد عرض سعر']) assert(!isGreeting(q), q);
});

Deno.test('first "Hi" from an unknown number: English welcome signed QuotesDone, sent as the interactive list', async () => {
  const h = harness({ sids: { menu_en_general: 'HX' + '0'.repeat(32) } });
  const r = await menuTurn(h.d, msg('Hi'));
  assertEquals(r.route, 'menu_welcome');
  assertEquals(h.sent.length, 1);
  assertEquals(h.sent[0].content?.sid, 'HX' + '0'.repeat(32));
  assertEquals(h.sent[0].content!.variables['1'], 'Good day, and thank you for contacting QuotesDone.');
  assert(!h.sent[0].content!.variables['1'].includes('\n'), 'a Content variable carries no line break');
  assertMatch(h.rows[0].reply as string, /Kind regards,\nQuotesDone Customer Support$/);
});

Deno.test('first "السلام عليكم": Arabic welcome that returns the salam, numbered when no Content SID exists', async () => {
  const h = harness();
  await menuTurn(h.d, msg('السلام عليكم'));
  assertEquals(h.sent.length, 1);
  assertEquals(h.sent[0].content, undefined);
  assertMatch(h.sent[0].body, /^وعليكم السلام ورحمة الله وبركاته/);
  assertMatch(h.sent[0].body, /1\. طلب عرض سعر جديد/);
  assertMatch(h.sent[0].body, /فريق خدمة العملاء في QuotesDone/);
  assertEquals(h.rows[0].lang, 'ar');
});

Deno.test('a confirmed customer is greeted by name; a supplier sees "My supplier account"', async () => {
  const c = harness({ ctx: { audience: 'customer', name: 'ZZ DEMO Customer' }, sids: { menu_en_general: 'HX' + '1'.repeat(32) } });
  await menuTurn(c.d, msg('hello', 'customer'));
  assertEquals(c.sent[0].content?.variables['1'], 'Good day ZZ DEMO Customer, and thank you for contacting QuotesDone.');
  assertEquals(contentKey('en', 'customer'), 'menu_en_general');

  const s = harness({ ctx: { audience: 'supplier', name: 'ZZ DEMO Trading LLC', approved: false } });
  await menuTurn(s.d, msg('menu', 'supplier'));
  assertMatch(s.sent[0].body, /3\. My supplier account/);
  assertEquals(contentKey('en', 'supplier'), 'menu_en_supplier');
});

Deno.test('the interactive list is refused: the numbered menu goes instead, nobody is left unanswered', async () => {
  const h = harness({ sids: { menu_en_general: 'HX' + '2'.repeat(32) }, contentFails: true });
  await menuTurn(h.d, msg('Hi'));
  assertEquals(h.sent.length, 2);
  assertMatch(h.sent[1].body, /1\. Request a quotation[\s\S]*6\. Talk to a person/);
  assertEquals(h.rows[0].sent, true);
  assertEquals((h.rows[0].extra as Record<string, unknown>).via, 'text_fallback');
});

Deno.test('a list reply (ListId), a typed title and a bare number after the menu each select the option', () => {
  assertEquals(menuChoice({ listId: 'qd_follow' }), 'qd_follow');
  assertEquals(menuChoice({ buttonPayload: 'qd_person' }), 'qd_person');
  assertEquals(menuChoice({ body: 'Report a problem' }), 'qd_problem');
  assertEquals(menuChoice({ body: 'الإبلاغ عن مشكلة' }), 'qd_problem');
  assertEquals(menuChoice({ body: '2', numbers: true }), 'qd_follow');
  assertEquals(menuChoice({ body: '٥', numbers: true }), 'qd_problem');
  assertEquals(menuChoice({ body: '2' }), null, 'a bare number means nothing unless we just offered the menu');
  assertEquals(menuChoice({ listId: 'qd_drop_tables' }), null);
});

Deno.test('every option routes to its own flow', async () => {
  const cases: Array<[string, RegExp, Partial<MenuContext>]> = [
    ['qd_new', /quotesdone\.com\/me\?new=1/, {}],
    ['qd_follow', /Request 1042: Quotes received/, { audience: 'customer', name: 'ZZ DEMO', requests: [{ rfq_no: 1042, status: 'quoted', created_at: '2026-09-20T10:00:00Z' }] }],
    ['qd_supplier', /register|Register/, {}],
    ['qd_general', /type your question/, {}],
    ['qd_problem', /describe the problem/, {}],
    ['qd_person', /a member of the team will reply to you on this number/, {}],
  ];
  for (const [id, expect, ctx] of cases) {
    const h = harness({ ctx, history: [{ route: 'menu_welcome', await: null, lang: 'en' }] });
    const r = await menuTurn(h.d, msg('x', (ctx.audience as Audience) || 'unknown', { listId: id }));
    assertEquals(r.route, 'menu_' + id);
    assertMatch(h.sent[0].body, expect, id);
    if (id === 'qd_person') assertEquals(h.notified, [FROM]);
    else assertEquals(h.notified, []);
  }
});

Deno.test('follow-up: an unknown number is told plainly nothing is registered on it, never shown anyone\'s requests', async () => {
  // fn_wa_menu_context lists requests only for a CONFIRMED customer number; the reply trusts that.
  const h = harness({ ctx: { audience: 'unknown', requests: [] } });
  await menuTurn(h.d, msg('Follow up my request'));
  assertMatch(h.sent[0].body, /^There is no request registered under this mobile number \(or its email\)/);
  assertMatch(h.sent[0].body, /https:\/\/quotesdone\.com\/me\?new=1/);
  assert(!h.sent[0].body.includes('9'));
});

Deno.test('supplier option: a verified supplier gets the portal, an unverified one the remaining steps', async () => {
  const ok = harness({ ctx: { audience: 'supplier', name: 'ZZ DEMO Co', approved: true } });
  await menuTurn(ok.d, msg('x', 'supplier', { listId: 'qd_supplier' }));
  assertMatch(ok.sent[0].body, /is verified/);
  const no = harness({ ctx: { audience: 'supplier', name: 'ZZ DEMO Co', approved: false } });
  await menuTurn(no.d, msg('x', 'supplier', { listId: 'qd_supplier' }));
  assertMatch(no.sent[0].body, /not verified yet/);
});

Deno.test('report a problem: the next message becomes a case and the reference is confirmed', async () => {
  const h = harness({ history: [{ route: 'menu_welcome', await: null, lang: 'en' }] });
  await menuTurn(h.d, msg('5'));
  assertEquals(h.rows[0].await, 'problem');
  const r = await menuTurn(h.d, msg('My quote for request 1042 disappeared'));
  assertEquals(r.route, 'menu_case');
  assertEquals(h.cases, ['My quote for request 1042 disappeared']);
  assertMatch(h.sent[1].body, /Your case reference is QD-S-ZZ1/);
});

Deno.test('the caps do not stop a conversation: every turn of a five-message session is answered', async () => {
  // wa_per_recipient_24h = 1 governs the outbox's business-initiated notices, not replies in a session.
  const h = harness();
  for (const b of ['Hi', '4', 'what are your fees', 'menu', '6']) await menuTurn(h.d, msg(b));
  // 'what are your fees' has no FAQ answer in this fake, so it is left to the normal route (not sent here).
  assertEquals(h.sent.length, 4);
  assert(h.rows.every((r) => r.sent === true));
});

Deno.test('the caps really are absent from wa_inbound: it never reads them and never queues a reply in the outbox', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(!src.includes("'wa_per_recipient_24h'") && !src.includes("'wa_daily_cap'"));
  assert(!/from\('notifications'\)\s*\.insert/.test(src));
});

Deno.test('wa_autoreply_enabled off: nothing is sent, the turn is still recorded', async () => {
  const h = harness({ enabled: false });
  await menuTurn(h.d, msg('Hi'));
  assertEquals(h.sent.length, 0);
  assertEquals(h.rows[0].sent, false);
});

Deno.test('the founder: "Hi" opens the menu, but a command is left to his command channel', async () => {
  const h = harness({ ctx: { audience: 'founder', name: 'ZZ DEMO Founder' } });
  assertEquals((await menuTurn(h.d, msg('Hi', 'founder'))).handled, true);
  const g = harness({ ctx: { audience: 'founder' } });
  assertEquals((await menuTurn(g.d, msg('send me the weekly report', 'founder'))).handled, false);
});

Deno.test('first contact with a real question: left to the handlers first, then the FAQ answer and the menu', async () => {
  const h = harness({ faq: 'Posting a job is free.' });
  assertEquals((await menuTurn(h.d, msg('Is posting a job free?'))).handled, false);
  assertEquals(h.sent.length, 0);
  assertEquals(await welcomeFirstContact(h.d, msg('Is posting a job free?')), true);
  assertEquals(h.sent.map((s) => s.body.slice(0, 22)), ['Posting a job is free.', h.sent[1].body.slice(0, 22)]);
  assertEquals(h.rows.map((r) => r.route), ['menu_first_answer', 'menu_welcome']);
});

// Review of #841 (HIGH): a supplier replying to a price request we sent through the outbox was welcomed
// with the menu instead of reaching fn_supplier_apply_change.
Deno.test('a supplier replying "12500" to our price request is in-flow: no menu, the price-change handler gets it', async () => {
  const h = harness({ ctx: { audience: 'supplier' }, weWrote: true });
  for (const b of ['12500', 'yes, reduce to 9000']) {
    assertEquals((await menuTurn(h.d, msg(b, 'supplier'))).handled, false, b);
    assertEquals(await welcomeFirstContact(h.d, msg(b, 'supplier')), false, b);
  }
  assertEquals(h.sent.length, 0);
});

Deno.test('a first message with a document goes to document intake, never the menu', async () => {
  const h = harness();
  assertEquals((await menuTurn(h.d, msg('my trade licence', 'unknown', { hasMedia: true }))).handled, false);
  assertEquals((await menuTurn(h.d, msg('Hi', 'unknown', { hasMedia: true }))).handled, false);
  assertEquals(await welcomeFirstContact(h.d, msg('', 'unknown', { hasMedia: true })), false);
  assertEquals(h.sent.length, 0);
});

Deno.test('an explicit hello after one of our notices still gets the welcome', async () => {
  const h = harness({ weWrote: true, history: [{ route: 'deterministic', await: null, lang: 'en' }] });
  assertEquals((await menuTurn(h.d, msg('Hello'))).route, 'menu_welcome');
  assertEquals(h.sent.length, 1);
});

Deno.test('in wa_inbound the first-contact welcome runs only after every handler that could claim the message', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  const at = src.indexOf('await welcomeFirstContact(');
  assert(at > 0);
  for (const handler of ["admin.rpc('fn_supplier_apply_change'", "admin.rpc('fn_wa_route'", 'if (media.length) {', "if (audience === 'founder') {"]) {
    const h = src.indexOf(handler);
    assert(h > 0 && h < at, handler + ' must come before the first-contact welcome');
  }
});

Deno.test('later free text: a confident FAQ answer is sent; with none, the menu is offered again', async () => {
  const yes = harness({ faq: 'Suppliers pay no commission.', history: [{ route: 'menu_qd_general', await: 'question', lang: 'en' }] });
  assertEquals(await answerFromFaq(yes.d, msg('do suppliers pay commission')), true);
  assertMatch(yes.sent[0].body, /Suppliers pay no commission\.\n\nReply MENU/);
  const no = harness({ history: [{ route: 'faq_answer', await: null, lang: 'en' }] });
  assertEquals((await menuTurn(no.d, msg('blah blah'))).handled, false);
  assertEquals(await answerFromFaq(no.d, msg('blah blah')), false);
  await reofferMenu(no.d, msg('blah blah'), 'Sorry, I could not match that to an answer.');
  assertMatch(no.sent[0].body, /Sorry, I could not match[\s\S]*1\. Request a quotation/);
  assertEquals(no.rows[0].route, 'menu_reoffer');
});

// ---- Founder instruction 763 (22 Sep 2026): the five defects he found testing the live menu ----------

Deno.test('763/1 the welcome never greets with an address, and sounds like a senior support lead', () => {
  // wa_messages 252: "Good day management@quotesdone.com" -- fn_identify_contact returns the admin email.
  assertEquals(cleanName('management@quotesdone.com'), null);
  assertEquals(cleanName('+971 50 000 0021'), null);
  assertEquals(cleanName('  ZZ DEMO  Person '), 'ZZ DEMO Person');
  assertEquals(greetLine('en', 'founder', 'management@quotesdone.com'), 'Good day, and thank you for contacting QuotesDone.');
  assert(!greetLine('ar', 'founder', 'management@quotesdone.com').includes('@'));
  for (const lang of ['en', 'ar'] as Lang[]) {
    const w = welcomeText(lang, 'unknown', null);
    assert(w.length <= 1024, lang + ' welcome exceeds the list-picker body limit: ' + w.length);
    assert(w.includes(HOURS[lang]), lang + ' welcome states the working hours');
    assert(w.includes('QuotesDone'));
  }
  assertMatch(WELCOME_TAIL.en, /construction procurement platform: request quotations and compare verified suppliers/);
  assertMatch(WELCOME_TAIL.ar, /فريق خدمة العملاء في QuotesDone$/);
});

Deno.test('763/1 the working hours are the company\'s published hours (src/content/company.json), not copy', async () => {
  const company = JSON.parse(await Deno.readTextFile(new URL('../../../src/content/company.json', import.meta.url)));
  assertEquals(HOURS.en, company.hours.en);
  assertEquals(HOURS.ar, company.hours.ar);
  assertEquals(withinHours(new Date('2026-09-22T06:00:00Z')), true);   // Tuesday 10:00 Dubai
  assertEquals(withinHours(new Date('2026-09-22T15:00:00Z')), false);  // Tuesday 19:00 Dubai
  assertEquals(withinHours(new Date('2026-09-25T06:00:00Z')), false);  // Friday
});

Deno.test('763/2 links go to the right portal: customers and strangers to /me, only suppliers to /portal', () => {
  const none: MenuContext = { audience: 'founder', name: 'ZZ DEMO', requests: [] };
  const cases: Array<[typeof MENU_IDS[number], MenuContext]> = [
    ['qd_new', { audience: 'unknown', name: null }], ['qd_follow', none], ['qd_follow', { audience: 'customer', name: null, requests: [] }]];
  for (const [id, ctx] of cases) {
    for (const lang of ['en', 'ar'] as Lang[]) {
      const t = optionReply(id, lang, ctx);
      assert(!t.includes('/portal'), id + ' ' + lang + ' must not send a customer to the supplier portal: ' + t);
      assert(t.includes(lang === 'ar' ? 'https://quotesdone.com/ar/me?new=1' : 'https://quotesdone.com/me?new=1'), id + ' ' + lang);
    }
  }
  const listed = optionReply('qd_follow', 'en', { audience: 'customer', name: 'ZZ DEMO', requests: [
    { id: '00000000-0000-4000-8000-000000000001', rfq_no: 1042, status: 'quoted', created_at: '2026-09-20T10:00:00Z' }] });
  assertMatch(listed, /Request 1042: Quotes received \(opened 2026-09-20\)\nhttps:\/\/quotesdone\.com\/me\?request=00000000-0000-4000-8000-000000000001/);
  assertMatch(optionReply('qd_supplier', 'en', { audience: 'supplier', name: 'ZZ DEMO Co', approved: true }), /https:\/\/quotesdone\.com\/portal$/);
  assertMatch(optionReply('qd_follow', 'en', { audience: 'supplier', name: 'ZZ DEMO Co', approved: true }), /\/portal$/);
});

Deno.test('763/3 a second report while a case is open is added to it; the reporter is told the reference and the clock', async () => {
  assertMatch(caseConfirm('en', { ref: 'QD-S-ZZ1', appended: true, slaHours: 24 }), /already have an open case, QD-S-ZZ1.*within 24 hours/);
  assertMatch(caseConfirm('ar', { ref: 'QD-S-ZZ1', appended: false, slaHours: 24 }), /QD-S-ZZ1.*خلال 24 ساعة/);
  const h = harness({ appended: true, history: [{ route: 'menu_qd_problem', await: 'problem', lang: 'en' }] });
  await menuTurn(h.d, msg('still broken'));
  assertEquals((h.rows[0].extra as Record<string, unknown>).case_appended, true);
});

Deno.test('763/3 the founder closes a case by WhatsApp and the reporter is told, in their language', async () => {
  assertEquals(founderCommand('close QD-S-ABC234 fixed the upload'), { kind: 'close_case', ref: 'QD-S-ABC234', reason: 'fixed the upload' });
  assertEquals(founderCommand('DONE +971 50 000 0041'), { kind: 'close_human', phone: '971500000041' });
  assertEquals(founderCommand('close the door'), null);
  const h = harness({ ctx: { audience: 'founder' } });
  const r = await menuTurn(h.d, msg('close QD-S-ABC234 fixed the upload', 'founder'));
  assertEquals(r.route, 'founder_close_case');
  assertEquals(h.closed, ['QD-S-ABC234:fixed the upload']);
  assertEquals(h.sent[0].to, 'whatsapp:+971500000041');
  assertMatch(h.sent[0].body, /^نفيدكم بإغلاق البلاغ رقم QD-S-ABC234/);
  assertMatch(h.sent[1].body, /Case QD-S-ABC234 is closed\. The reporter was told on WhatsApp\./);
  // Nobody but the founder can close anything.
  const s = harness();
  assertEquals((await menuTurn(s.d, msg('close QD-S-ABC234 x'))).handled, false);
  assertEquals(s.closed, []);
});

Deno.test('763/4 after "Talk to a person" the seat stays quiet until it is closed; the founder is never held', async () => {
  const h = harness({ held: true });
  for (const b of ['hello?', 'menu', 'is anyone there']) assertEquals((await menuTurn(h.d, msg(b))).route, 'held_for_human');
  assertEquals(h.sent.length, 0);
  assertEquals(h.rows.map((r) => r.route), ['held_for_human', 'held_for_human', 'held_for_human']);
  const f = harness({ held: true, ctx: { audience: 'founder' } });
  assertEquals((await menuTurn(f.d, msg('Hi', 'founder'))).route, 'menu_welcome');
  const d = harness({ ctx: { audience: 'founder' } });
  assertEquals((await menuTurn(d.d, msg('DONE +971500000041', 'founder'))).route, 'founder_close_human');
  assertEquals(d.closed, ['human:971500000041']);
});

Deno.test('763/4 the reply is honest about timing, and the alert is actionable', () => {
  assertMatch(optionReply('qd_person', 'en', { audience: 'unknown', name: null }, new Date('2026-09-22T06:00:00Z')),
    /working hours are Sunday to Thursday, 9am to 6pm \(GST\), excluding UAE public holidays\.\nAutomatic replies/);
  assertMatch(optionReply('qd_person', 'en', { audience: 'unknown', name: null }, new Date('2026-09-22T16:00:00Z')), /outside those hours now/);
  const a = humanAlert({ phone: 'whatsapp:+971500000041', name: 'management@quotesdone.com', profile: 'ZZ DEMO Ahmad',
                         audience: 'customer', lastMessages: ['my quote is missing', 'hello?'] });
  assertEquals(a.event, 'WhatsApp: ZZ DEMO Ahmad asks to talk to a person');
  assert(!a.event.includes('@') && !a.detail.includes('management@'));
  assertMatch(a.detail, /Reply now: https:\/\/wa\.me\/971500000041/);
  assertMatch(a.detail, /Last messages:\n- "my quote is missing"\n- "hello\?"/);
  assertMatch(a.detail, /send DONE \+971500000041/);
});

Deno.test('763/5 wa_inbound asks the FAQ with the gte-small embedding, never text alone', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(src.includes("new (globalThis as any).Supabase.ai.Session('gte-small')"));
  assertMatch(src, /rpc\('fn_faq_answer', \{\s*p_text: q, p_min_rank: 0\.15, p_embedding: await embedQuestion\(q\), p_min_similarity: FAQ_MIN_SIMILARITY/);
  assert(!/rpc\('fn_faq_answer', \{ p_text: [^}]*\}\)/.test(src), 'a text-only FAQ call is back');
});

// ---- Founder instruction 763 (22 Sep 2026): the five defects he found testing the live menu ----------

Deno.test('763/1 the welcome never greets with an address, and sounds like a senior support lead', () => {
  // wa_messages 252: "Good day management@quotesdone.com" -- fn_identify_contact returns the admin email.
  assertEquals(cleanName('management@quotesdone.com'), null);
  assertEquals(cleanName('+971 50 000 0021'), null);
  assertEquals(cleanName('  ZZ DEMO  Person '), 'ZZ DEMO Person');
  assertEquals(greetLine('en', 'founder', 'management@quotesdone.com'), 'Good day, and thank you for contacting QuotesDone.');
  assert(!greetLine('ar', 'founder', 'management@quotesdone.com').includes('@'));
  for (const lang of ['en', 'ar'] as Lang[]) {
    const w = welcomeText(lang, 'unknown', null);
    assert(w.length <= 1024, lang + ' welcome exceeds the list-picker body limit: ' + w.length);
    assert(w.includes(HOURS[lang]), lang + ' welcome states the working hours');
    assert(w.includes('QuotesDone'));
  }
  assertMatch(WELCOME_TAIL.en, /construction procurement platform: request quotations and compare verified suppliers/);
  assertMatch(WELCOME_TAIL.ar, /فريق خدمة العملاء في QuotesDone$/);
});

Deno.test('763/1 the working hours are the company\'s published hours (src/content/company.json), not copy', async () => {
  const company = JSON.parse(await Deno.readTextFile(new URL('../../../src/content/company.json', import.meta.url)));
  assertEquals(HOURS.en, company.hours.en);
  assertEquals(HOURS.ar, company.hours.ar);
  assertEquals(withinHours(new Date('2026-09-22T06:00:00Z')), true);   // Tuesday 10:00 Dubai
  assertEquals(withinHours(new Date('2026-09-22T15:00:00Z')), false);  // Tuesday 19:00 Dubai
  assertEquals(withinHours(new Date('2026-09-25T06:00:00Z')), false);  // Friday
});

Deno.test('763/2 links go to the right portal: customers and strangers to /me, only suppliers to /portal', () => {
  const none: MenuContext = { audience: 'founder', name: 'ZZ DEMO', requests: [] };
  const cases: Array<[typeof MENU_IDS[number], MenuContext]> = [
    ['qd_new', { audience: 'unknown', name: null }], ['qd_follow', none], ['qd_follow', { audience: 'customer', name: null, requests: [] }]];
  for (const [id, ctx] of cases) {
    for (const lang of ['en', 'ar'] as Lang[]) {
      const t = optionReply(id, lang, ctx);
      assert(!t.includes('/portal'), id + ' ' + lang + ' must not send a customer to the supplier portal: ' + t);
      assert(t.includes(lang === 'ar' ? 'https://quotesdone.com/ar/me?new=1' : 'https://quotesdone.com/me?new=1'), id + ' ' + lang);
    }
  }
  const listed = optionReply('qd_follow', 'en', { audience: 'customer', name: 'ZZ DEMO', requests: [
    { id: '00000000-0000-4000-8000-000000000001', rfq_no: 1042, status: 'quoted', created_at: '2026-09-20T10:00:00Z' }] });
  assertMatch(listed, /Request 1042: Quotes received \(opened 2026-09-20\)\nhttps:\/\/quotesdone\.com\/me\?request=00000000-0000-4000-8000-000000000001/);
  assertMatch(optionReply('qd_supplier', 'en', { audience: 'supplier', name: 'ZZ DEMO Co', approved: true }), /https:\/\/quotesdone\.com\/portal$/);
  assertMatch(optionReply('qd_follow', 'en', { audience: 'supplier', name: 'ZZ DEMO Co', approved: true }), /\/portal$/);
});

Deno.test('763/3 a second report while a case is open is added to it; the reporter is told the reference and the clock', async () => {
  assertMatch(caseConfirm('en', { ref: 'QD-S-ZZ1', appended: true, slaHours: 24 }), /already have an open case, QD-S-ZZ1.*within 24 hours/);
  assertMatch(caseConfirm('ar', { ref: 'QD-S-ZZ1', appended: false, slaHours: 24 }), /QD-S-ZZ1.*خلال 24 ساعة/);
  const h = harness({ appended: true, history: [{ route: 'menu_qd_problem', await: 'problem', lang: 'en' }] });
  await menuTurn(h.d, msg('still broken'));
  assertEquals((h.rows[0].extra as Record<string, unknown>).case_appended, true);
});

Deno.test('763/3 the founder closes a case by WhatsApp and the reporter is told, in their language', async () => {
  assertEquals(founderCommand('close QD-S-ABC234 fixed the upload'), { kind: 'close_case', ref: 'QD-S-ABC234', reason: 'fixed the upload' });
  assertEquals(founderCommand('DONE +971 50 000 0041'), { kind: 'close_human', phone: '971500000041' });
  assertEquals(founderCommand('close the door'), null);
  const h = harness({ ctx: { audience: 'founder' } });
  const r = await menuTurn(h.d, msg('close QD-S-ABC234 fixed the upload', 'founder'));
  assertEquals(r.route, 'founder_close_case');
  assertEquals(h.closed, ['QD-S-ABC234:fixed the upload']);
  assertEquals(h.sent[0].to, 'whatsapp:+971500000041');
  assertMatch(h.sent[0].body, /^نفيدكم بإغلاق البلاغ رقم QD-S-ABC234/);
  assertMatch(h.sent[1].body, /Case QD-S-ABC234 is closed\. The reporter was told on WhatsApp\./);
  // Nobody but the founder can close anything.
  const s = harness();
  assertEquals((await menuTurn(s.d, msg('close QD-S-ABC234 x'))).handled, false);
  assertEquals(s.closed, []);
});

Deno.test('763/4 after "Talk to a person" the seat stays quiet until it is closed; the founder is never held', async () => {
  const h = harness({ held: true });
  for (const b of ['hello?', 'menu', 'is anyone there']) assertEquals((await menuTurn(h.d, msg(b))).route, 'held_for_human');
  assertEquals(h.sent.length, 0);
  assertEquals(h.rows.map((r) => r.route), ['held_for_human', 'held_for_human', 'held_for_human']);
  const f = harness({ held: true, ctx: { audience: 'founder' } });
  assertEquals((await menuTurn(f.d, msg('Hi', 'founder'))).route, 'menu_welcome');
  const d = harness({ ctx: { audience: 'founder' } });
  assertEquals((await menuTurn(d.d, msg('DONE +971500000041', 'founder'))).route, 'founder_close_human');
  assertEquals(d.closed, ['human:971500000041']);
});

Deno.test('763/4 the reply is honest about timing, and the alert is actionable', () => {
  assertMatch(optionReply('qd_person', 'en', { audience: 'unknown', name: null }, new Date('2026-09-22T06:00:00Z')),
    /working hours are Sunday to Thursday, 9am to 6pm \(GST\), excluding UAE public holidays\.\nAutomatic replies/);
  assertMatch(optionReply('qd_person', 'en', { audience: 'unknown', name: null }, new Date('2026-09-22T16:00:00Z')), /outside those hours now/);
  const a = humanAlert({ phone: 'whatsapp:+971500000041', name: 'management@quotesdone.com', profile: 'ZZ DEMO Ahmad',
                         audience: 'customer', lastMessages: ['my quote is missing', 'hello?'] });
  assertEquals(a.event, 'WhatsApp: ZZ DEMO Ahmad asks to talk to a person');
  assert(!a.event.includes('@') && !a.detail.includes('management@'));
  assertMatch(a.detail, /Reply now: https:\/\/wa\.me\/971500000041/);
  assertMatch(a.detail, /Last messages:\n- "my quote is missing"\n- "hello\?"/);
  assertMatch(a.detail, /send DONE \+971500000041/);
});

Deno.test('763/5 wa_inbound asks the FAQ with the gte-small embedding, never text alone', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(src.includes("new (globalThis as any).Supabase.ai.Session('gte-small')"));
  assertMatch(src, /rpc\('fn_faq_answer', \{\s*p_text: q, p_min_rank: 0\.15, p_embedding: await embedQuestion\(q\), p_min_similarity: FAQ_MIN_SIMILARITY/);
  assert(!/rpc\('fn_faq_answer', \{ p_text: [^}]*\}\)/.test(src), 'a text-only FAQ call is back');
});
