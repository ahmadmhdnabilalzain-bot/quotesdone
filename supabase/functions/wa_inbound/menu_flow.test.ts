// The WhatsApp welcome and menu, driven through the real routing with fakes for the database and
// Twilio (founder_instruction 759, 22 Sep 2026). Prevents "said hi, got no response" from coming back
// for any reason inside the routing: a greeting, a first message, every option, each audience, and a
// conversation that continues past the first reply all get an answer.
//
//   deno test --no-lock --node-modules-dir=auto supabase/functions/wa_inbound/menu_flow.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { answerFromFaq, type Content, type MenuDeps, type MenuInput, menuTurn, reofferMenu, type Turn } from './menu_flow.ts';
import { type Audience, contentKey, isGreeting, type Lang, MENU_BUTTON, MENU_IDS, menuChoice, type MenuContext, menuItems } from './menu.ts';

const FROM = 'whatsapp:+971500000021'; // reserved ZZ DEMO fixture block

type Sent = { to: string; body: string; content?: Content };
function harness(o: { ctx?: Partial<MenuContext>; sids?: Record<string, string>; contentFails?: boolean; faq?: string | null;
                      enabled?: boolean; history?: Turn[] } = {}) {
  const sent: Sent[] = []; const rows: Array<Record<string, unknown>> = []; const cases: string[] = []; const notified: string[] = [];
  const history: Turn[] = [...(o.history || [])];
  const d: MenuDeps = {
    autoreplyEnabled: () => Promise.resolve(o.enabled ?? true),
    recentTurns: () => Promise.resolve([...history]),
    context: () => Promise.resolve({ audience: 'unknown', name: null, ...(o.ctx || {}) } as MenuContext),
    faq: () => Promise.resolve(o.faq ?? null),
    openCase: (_f, text) => { cases.push(text); return Promise.resolve('QD-S-ZZ' + cases.length); },
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
  return { d, sent, rows, cases, notified };
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
  assertMatch(h.sent[0].content!.variables['1'], /^Good day, and welcome to QuotesDone/);
  assert(!h.sent[0].content!.variables['1'].includes('\n'), 'a Content variable carries no line break');
  assertMatch(h.rows[0].reply as string, /QuotesDone team$/);
});

Deno.test('first "السلام عليكم": Arabic welcome that returns the salam, numbered when no Content SID exists', async () => {
  const h = harness();
  await menuTurn(h.d, msg('السلام عليكم'));
  assertEquals(h.sent.length, 1);
  assertEquals(h.sent[0].content, undefined);
  assertMatch(h.sent[0].body, /^وعليكم السلام ورحمة الله وبركاته/);
  assertMatch(h.sent[0].body, /1\. طلب عرض سعر جديد/);
  assertMatch(h.sent[0].body, /فريق QuotesDone/);
  assertEquals(h.rows[0].lang, 'ar');
});

Deno.test('a confirmed customer is greeted by name; a supplier sees "My supplier account"', async () => {
  const c = harness({ ctx: { audience: 'customer', name: 'ZZ DEMO Customer' }, sids: { menu_en_general: 'HX' + '1'.repeat(32) } });
  await menuTurn(c.d, msg('hello', 'customer'));
  assertEquals(c.sent[0].content?.variables['1'], 'Good day ZZ DEMO Customer, and welcome back to QuotesDone.');
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
    ['qd_new', /quotesdone\.com\/portal/, {}],
    ['qd_follow', /Request 1042: Quotes received/, { audience: 'customer', name: 'ZZ DEMO', requests: [{ rfq_no: 1042, status: 'quoted', created_at: '2026-09-20T10:00:00Z' }] }],
    ['qd_supplier', /register|Register/, {}],
    ['qd_general', /type your question/, {}],
    ['qd_problem', /describe the problem/, {}],
    ['qd_person', /member of our team/, {}],
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

Deno.test('follow-up: an unknown number is asked to sign in, never shown anyone\'s requests', async () => {
  const h = harness({ ctx: { audience: 'unknown', requests: [{ rfq_no: 9, status: 'quoted', created_at: '' }] } });
  await menuTurn(h.d, msg('Follow up my request'));
  assertMatch(h.sent[0].body, /confirmed on a QuotesDone account/);
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

Deno.test('first message with a real question: the FAQ answer, then the menu', async () => {
  const h = harness({ faq: 'Posting a job is free.' });
  await menuTurn(h.d, msg('Is posting a job free?'));
  assertEquals(h.sent.map((s) => s.body.slice(0, 22)), ['Posting a job is free.', h.sent[1].body.slice(0, 22)]);
  assertEquals(h.rows.map((r) => r.route), ['menu_first_answer', 'menu_welcome']);
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
