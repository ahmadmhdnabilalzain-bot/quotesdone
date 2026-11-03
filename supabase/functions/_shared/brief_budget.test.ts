// NO REPLY PATH SENDS MORE THAN BRIEF_TOKEN_CAP OF BRIEF (it_engineer, 3 Nov 2026). Before: 140-150k Sonnet prompt tokens a
// reply (ai_cost_log 30 Oct-3 Nov). Every chat path builds its brief with companyBrief (aiReply for wa_inbound,
// inquiry_intake, supplier_api, reasoned_delivery, email_triage, support_reply and marketing; the portal's sales_engineer;
// site_assistant; customerReplyGate), so this proves the cap for every trade, no trade, both readers, with live inputs at
// today's measured sizes plus 10%: the company block (5,673 characters), the price guide (17,615), site_assistant's
// facts (4,617), and every published FAQ row (150 EN, 152 AR at today's average length).
// No network. Run: deno test --no-lock supabase/functions/_shared/brief_budget.test.ts
import { assert, assertEquals } from 'jsr:@std/assert';
import { BRIEF_APPROX_TOKENS, BRIEF_PACKS, BRIEF_SUPPLIER, BRIEF_TEXT } from './brief.generated.ts';
import { approxTokens, BRIEF_TOKEN_CAP, companyBrief, figureSource, packOf, pricesFor, splitBrief } from './company_brief.ts';

const TRADES = BRIEF_PACKS.map(([code]) => code);
// fn_company_context(public): 5,673 characters on 3 Nov 2026 (its own cap is 8,000); the fixture is today's plus 10%
const COMPANY = 'REVEAL FEE: the CUSTOMER pays 3.00% of the selected quotation value. '.repeat(200).slice(0, Math.ceil(5_673 * 1.1));
const GUIDE = '## PUBLISHED PRICE GUIDE (UAE ranges QuotesDone publishes; quote them as a range)\n'
  + TRADES.flatMap((c) => [1, 2, 3, 4, 5].map((n) => `- ${c}: Item ${n}, std: AED ${n}00 to ${n}900 per sqm (as of 2026-06-28)`)).join('\n')
  // the live guide's 26 `general` (materials) rows, which every pack keeps
  + '\n' + Array.from({ length: 26 }, (_, n) => `- general: Material ${n} (18mm sheet): AED ${n + 1}0 to ${n + 1}90 per sheet (as of 2026-06-28)`).join('\n')
  + '\nNo published range (say so, never estimate): combined-mep, elevators';
const FAQS = [...Array.from({ length: 150 }, (_, i) => ({ id: i, language: 'en', question: 'How does step ' + i + ' work for me?', answer: 'It works like this. '.repeat(17) })),
  ...Array.from({ length: 152 }, (_, i) => ({ id: 1000 + i, language: 'ar', question: 'كيف تعمل الخطوة ' + i + '؟', answer: 'تعمل الخطوة بهذه الطريقة تماما. '.repeat(10) }))];
// site_assistant's FACTS_SHARED + FACTS_CUSTOMER + FACTS_SUPPLIER measured 4,617 characters on 3 Nov 2026
const SITE_FACTS = 'SHARED FACTS (safe for anyone): the published facts of the website chat. '.repeat(90).slice(0, 5000);
const rpc = (fn: string) => Promise.resolve({ data: fn === 'fn_price_brief' ? GUIDE : { block: COMPANY }, error: null });
let clock = 1_000_000;
const build = (faqs: typeof FAQS, facts: string, trade: string | null, supplier: boolean) =>
  companyBrief(rpc, faqs, facts, 'en', [], (clock += 10_000_000), { trade, supplier });

Deno.test('the estimate agrees with the compiler, the core is ~20k and every pack ~10k', () => {
  // ponytail: the cap is proven for today's live sizes plus ~10% (fn_price_brief: 17,615 characters on 3 Nov 2026). If the
  // live guide grows past the fixture, a supplier on the website loses its FAQ first; grow the fixture and re-measure.
  assert(GUIDE.length >= 17_615 * 1.1, `the price guide fixture (${GUIDE.length}) is not 10% above today's`);
  assertEquals(approxTokens(BRIEF_TEXT), BRIEF_APPROX_TOKENS, 'company_brief.ts and compile_brief.mjs estimate differently');
  assert(BRIEF_APPROX_TOKENS <= 22_000, `the core is ~${BRIEF_APPROX_TOKENS} tokens`);
  assert(approxTokens(BRIEF_SUPPLIER) <= 6_000);
  for (const t of TRADES) assert(approxTokens(packOf(t)) <= 10_000, `${t}: ~${approxTokens(packOf(t))} tokens`);
});

Deno.test('every reply path, every trade, both readers: the brief stays under the cap', async () => {
  const worst: Record<string, number> = {};
  for (const trade of [null, ...TRADES]) for (const supplier of [false, true]) {
    // aiReply and the portal: no FAQ, no facts in the brief (the per-turn facts ride with the message)
    const chat = await build([], '', trade, supplier);
    const n = approxTokens(chat);
    assert(n <= BRIEF_TOKEN_CAP, `chat ${trade} ${supplier ? 'supplier' : 'customer'}: ~${n}`);
    if (trade) assert(chat.includes(packOf(trade)), `chat ${trade}: the pack was left out, but a chat reply always has room for it`);
    assert(chat.includes(BRIEF_SUPPLIER) === supplier, 'the supplier how-to rides for a supplier reader only');
    // site_assistant: its three FACTS blocks and every published FAQ row
    const site = await build(FAQS, SITE_FACTS, trade, supplier);
    const m = approxTokens(site);
    assert(m <= BRIEF_TOKEN_CAP, `site ${trade} ${supplier ? 'supplier' : 'customer'}: ~${m}`);
    for (const [k, v] of [['chat', n], ['site', m]] as const) worst[k] = Math.max(worst[k] ?? 0, v);
    assert(splitBrief(site).shared === BRIEF_TEXT, 'the core is first and the shared cached block');
  }
  console.log('worst estimated brief tokens:', JSON.stringify(worst), 'cap', BRIEF_TOKEN_CAP);
});

Deno.test('a customer on the website still gets FAQ answers in both languages beside a pack', async () => {
  const site = await build(FAQS, SITE_FACTS, 'kitchens', false);
  assert(site.includes('Q: How does step 0 work for me?') && site.includes('Q: كيف تعمل الخطوة 0؟'), 'both FAQ languages');
  assert(site.includes(packOf('kitchens')));
});

// THE EXAM STILL REACHES ITS FACTS (scripts/kb/brief_quality_questions.json, the 30 questions the brief was scored on,
// ruling 1198). A company, fee, refund, liability or privacy question is answered from the core every reply carries; every
// technical, code and comparison question names a trade, and its pack carries that trade's regulation digest.
Deno.test('every exam question reaches its facts: the company ones in the core, the trade ones in their pack', async () => {
  const { conversationTrade } = await import('./company_brief.ts');
  const qs = JSON.parse(await Deno.readTextFile(new URL('../../../scripts/kb/brief_quality_questions.json', import.meta.url))) as { id: string; kind: string; q: string }[];
  assertEquals(qs.length, 30);
  for (const k of ['## 4. Fees', '## 5. Refunds', '## 6. Liability', '## 9. Privacy', '## 7. Verification', '## 12. Contact']) assert(BRIEF_TEXT.includes(k), 'the core lost ' + k);
  for (const x of qs.filter((q) => ['technical', 'uae_code', 'compare'].includes(q.kind))) {
    const t = conversationTrade(x.q);
    assert(t, `${x.id} names no trade with a pack: ${x.q.slice(0, 80)}`);
    assert(packOf(t).includes('<<<FILE knowledge/brief/uae_regulations/'), `${x.id} (${t}): its pack has no regulation digest`);
  }
  // a fee question that only looks like a trade (بقيمة "worth", أنشر "I post") carries no pack (conversation_trade.ts)
  for (const id of ['ar02', 'ar06']) assertEquals(conversationTrade(qs.find((q) => q.id === id)!.q), null, id);
});

// prevented by: these tests (independent review of this change, 3 Nov 2026). Each is a scenario the review produced.
Deno.test('the trade is the one the conversation is about, and passing words are not trades', async () => {
  const { conversationTrade } = await import('./company_brief.ts');
  for (const q of ['How do I sign up?', 'ok where do I sign in?', 'where do I sign?', 'I am ready to sign today', 'How big is your supplier network?',
    'Do you have a network of suppliers in Abu Dhabi?', 'QuotesDone network is big', 'Can you build a quote for me?', 'خلاص فنش',
    'كم سأدفع إذا اخترت عرض سعر بقيمة 20,000 درهم؟'])
    assertEquals(conversationTrade(q), null, q);
  const kitchen = ['I want new kitchen cabinets.', 'The kitchen is L-shaped, 4 m by 3 m.', 'High-gloss for the kitchen doors please.'];
  assertEquals(conversationTrade('the cabinets should match the floor tiles', kitchen), 'kitchens', 'a passing word does not swap the job');
  assertEquals(conversationTrade('Now I need a quote for AC servicing', ['I want new kitchen cabinets.', 'Thanks, all done.']), 'hvac', 'a new job takes over at once when the old one went quiet');
  assertEquals(conversationTrade('Now I need a quote for AC servicing', kitchen), 'kitchens', 'mid-job, a new trade needs a second message');
  assertEquals(conversationTrade('It is a 2 ton split unit.', [...kitchen, 'Now I need a quote for AC servicing']), 'hvac', '... and then it has it');
  assertEquals(conversationTrade('عندي البق في الشقة'), 'pest', 'the article form still matches');
  assertEquals(conversationTrade('الشتر خربان'), 'garage-doors');
  assertEquals(conversationTrade('عندنا مشكلة النش في السقف'), 'waterproofing');
  assertEquals(conversationTrade('Do I need a Dubai Municipality permit to renovate my villa?'), 'fitout', 'a renovation carries the fit-out digest');
  assertEquals(conversationTrade('We need a new sign board for the shop'), 'signage');
});

Deno.test('the figure check accepts what it accepted before: other families\' prices and the FAQ rows the budget cut', async () => {
  const chat = await build([], '', 'signage', false);   // a kitchen job whose customer said "sign board"
  assert(!chat.includes('- kitchens: Item 1') && figureSource(chat).includes('- kitchens: Item 1'), 'another family\'s range is out of the prompt and still accepted');
  const b = await build(FAQS, SITE_FACTS, 'signage', true);   // a supplier on the website: the smallest FAQ share
  assert(!b.includes('Q: How does step 149 work for me?') && figureSource(b).includes('Q: How does step 40 work for me?'), 'a cut FAQ row is still a published source');
  const rows = (t: string) => (t.match(/^Q: /gm) ?? []).length;
  // the rows the prompt keeps, per reader (FAQ_CAP alone kept ~84 of these fixture rows): a floor, so a change that
  // starves the FAQ further fails here
  assert(rows(await build(FAQS, SITE_FACTS, null, false)) >= 30, 'website customer, no trade');
  assert(rows(await build(FAQS, SITE_FACTS, 'kitchens', false)) >= 20, 'website customer with a pack');
});

Deno.test('with a pack the price guide keeps only that trade family, its heading and its notes; the figures follow', async () => {
  const p = pricesFor(GUIDE, 'tiling');
  assert(p.includes('- tiling: Item 1') && p.includes('- marble-granite: Item 1') && p.includes('- flooring: Item 1'), 'the flooring_and_stone family');
  assert(!p.includes('- hvac:') && p.includes('## PUBLISHED PRICE GUIDE') && p.includes('No published range'));
  assert(p.includes('- general: Material 0'), 'the materials rows (no trade) are kept for every job');
  assertEquals(pricesFor(GUIDE, null), GUIDE);
  assertEquals(pricesFor(GUIDE, 'not-a-trade'), GUIDE);
  // the knowledge never licenses a figure: what the check accepts is the live text only
  const b = await build([], '', 'tiling', true);
  const fs = figureSource(b);
  assert(!fs.includes('<<<FILE') && fs.includes('- tiling: Item 1') && fs.includes('REVEAL FEE'));
});
