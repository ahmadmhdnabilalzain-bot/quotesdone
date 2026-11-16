// THE PER-TURN FACTS RIDE AFTER THE CACHED CONVERSATION (turn_facts.ts). No network, no model: the prompt is built with the
// gateway's own block builders (ai_gateway/system_message.ts systemMessage + withHistoryBreakpoint, called exactly as
// handle.ts calls them) and billed by a model of the provider's prefix cache, at the rates ai_cost_log measured.
// Run: deno test --no-lock --node-modules-dir=none --allow-read supabase/functions/site_assistant/turn_facts.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { systemMessage, withHistoryBreakpoint } from '../ai_gateway/system_message.ts';
import { BRIEF_TEXT } from '../_shared/brief.generated.ts';
import { approxTokens } from '../_shared/company_brief.ts';
import { givenBlock, type GivenRow } from '../_shared/given_trade_knowledge.ts';
import { liveFacts, timelineFacts, turnContent, turnFacts } from './turn_facts.ts';

// claude-sonnet-5.5 through OpenRouter, USD per token: each matched ai_cost_log.cost_usd_reported to the 7th decimal on a
// 600-row sample (20 days to 10 Nov 2026), e.g. 5,457 in + 14 out = 0.0110540; 98 in + 3,007 written (5 m) + 747 out = 0.0151835.
const RATE = { input: 2.0e-6, read: 0.10e-6, write1h: 4.0e-6, write5m: 2.5e-6 };

type Block = { key: string; tokens: number; bp: '1h' | '5m' | null };
// deno-lint-ignore no-explicit-any
function blocksOf(messages: any[]): Block[] {
  const out: Block[] = [];
  for (const m of messages) {
    const parts = typeof m.content === 'string' ? [{ type: 'text', text: m.content }] : m.content;
    // deno-lint-ignore no-explicit-any
    for (const p of parts as any[]) out.push({ key: m.role + '\u0000' + p.text, tokens: approxTokens(p.text), bp: p.cache_control ? (p.cache_control.ttl === '1h' ? '1h' : '5m') : null });
  }
  return out;
}
/** The provider's prefix cache: a prefix is stored at each breakpoint; a call reads the longest stored prefix that ends on
 *  a block boundary up to 20 blocks before one of its breakpoints, writes from there to its last breakpoint (at the rate
 *  of the breakpoint that closes each block), and pays the input rate for everything after the last breakpoint. */
function cacheBill() {
  const stored = new Set<string>();
  return (messages: unknown[]) => {
    const b = blocksOf(messages as never[]);
    const ids: string[] = []; let id = '';
    for (const x of b) { id = String(approxTokens(id)) + ':' + fnv(id + '\u0001' + x.key); ids.push(id); }
    const bps = b.map((x, i) => (x.bp ? i : -1)).filter((i) => i >= 0);
    const last = bps.length ? bps[bps.length - 1] : -1;
    let hit = -1;
    for (const p of bps) for (let j = p; j >= Math.max(0, p - 20); j--) if (stored.has(ids[j]) && j > hit) hit = j;
    let read = 0, write = 0, input = 0, usd = 0;
    b.forEach((x, i) => {
      if (i <= hit) { read += x.tokens; usd += x.tokens * RATE.read; }
      else if (i <= last) { const closes = b[bps.find((p) => p >= i)!].bp; write += x.tokens; usd += x.tokens * (closes === '1h' ? RATE.write1h : RATE.write5m); }
      else { input += x.tokens; usd += x.tokens * RATE.input; }
    });
    for (const p of bps) stored.add(ids[p]);
    return { read, write, input, usd };
  };
}
function fnv(s: string): string { let h = 0x811c9dc5; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; } return h.toString(16) + ':' + s.length; }

// THE SHAPE OF A WIDGET CONVERSATION, measured on production assistant_logs (20 days to 10 Nov 2026, path '/'): 12 turns
// (median and mode), messages of 87 characters and replies of 461 on average.
const TURNS = 12;
const say = (i: number) => ('Turn ' + i + ': what do I need for a 3 m kitchen in Dubai Marina, and how long does it take? ').slice(0, 87);
const reply = (i: number) => ('Reply ' + i + ': a 3 m kitchen needs the carcass material, the worktop, the appliances and the site measurements. ').repeat(5).slice(0, 461);
// sys as index.ts writes it: the template literal's own text (its interpolations are a few words each)
const SRC = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
const TEMPLATE = SRC.slice(SRC.indexOf('const sys = `'), SRC.indexOf('`;', SRC.indexOf('const sys = `')));
const SYS = '\n\n' + TEMPLATE.replace(/\$\{[^}]*\}/g, '');
const STABLE = 'PACK, COMPANY BLOCK, PRICE GUIDE, FAQ AND THE PUBLISHED FACTS. '.repeat(1200).slice(0, 48_000);   // ~19k tokens, as companyBrief builds it under BRIEF_TOKEN_CAP
// the trade knowledge retrieved for each message: 3 rows of ~1,100 characters (given_trade_knowledge.ts cuts at 1,100)
const given = (i: number): GivenRow[] => [1, 2, 3].map((k) => ({ source: 'sales_knowledge', id: 'kitchens:' + i + '.' + k, title: 'Kitchen entry ' + i + '.' + k, excerpt: ('Fact ' + i + '.' + k + ' about carcass boards, hinges and worktops in UAE kitchens. ').repeat(20).slice(0, 1100), similarity: 0.85 }));
// a signed-in customer: their live account (fn_wa_context) and a timeline that gains an event every turn (30 newest)
const LIVE = { known: true, requests: [{ ref: 'QD-1042', status: 'quoting', quotes: 3, price_band: 'AED 18,000-24,000' }], name: 'ZZ DEMO' };
const events = (i: number) => Array.from({ length: 30 }, (_, k) => ({ at: '2026-11-10T09:' + String(59 - k).padStart(2, '0') + ':00Z', channel: 'widget', seat: 'customer_support', kind: 'reply', summary: 'turn ' + (i - k) + ' answered about the kitchen request' }));

/** One conversation, billed turn by turn. `layout` 'before': this turn's facts inside sys (main up to 10 Nov 2026);
 *  'after': sys alone, the facts with the message after the conversation (turn_facts.ts). */
function conversation(layout: 'before' | 'after', who: 'visitor' | 'signed-in') {
  const bill = cacheBill();
  // the brief is shared by every conversation on this route: another visitor's call has it in the cache already
  bill([systemMessage({ shared: BRIEF_TEXT, stable: STABLE, sys: SYS, useCache: true, ttl: '1h' })!, { role: 'user', content: 'another visitor' }]);
  const totals = { read: 0, write: 0, input: 0, usd: 0 }; const systems: string[] = [];
  const past: { role: 'user' | 'assistant'; content: string }[] = [];
  for (let i = 1; i <= TURNS; i++) {
    const facts = turnFacts({ live: who === 'signed-in' ? LIVE : null, uiLang: 'en', timeline: who === 'signed-in' ? events(i) : null, given: given(i) });
    const sys = layout === 'before' ? SYS.replace('\nRULES:', '\n\n' + facts + '\nRULES:') : SYS;
    const sysMsg = systemMessage({ shared: BRIEF_TEXT, stable: STABLE, sys, useCache: true, ttl: '1h' })!;
    const last = { role: 'user', content: layout === 'before' ? say(i) : turnContent(facts, say(i)) };
    const convo = [...past, last];
    const msgs = [sysMsg, ...(past.length ? withHistoryBreakpoint(convo, null) : convo)];   // handle.ts: cache_history when input has history
    const r = bill(msgs);
    for (const k of ['read', 'write', 'input', 'usd'] as const) totals[k] += r[k];
    systems.push(JSON.stringify(sysMsg));
    past.push({ role: 'user', content: say(i) }, { role: 'assistant', content: reply(i) });
  }
  return { ...totals, systems };
}

Deno.test('sys carries none of this turn\'s facts; the message carries them, after the conversation', () => {
  assert(TEMPLATE.length > 2000, 'the sys template was not found in index.ts');
  for (const v of ['liveBlock', 'timelineBlock', 'givenBlock', 'JSON.stringify(live)', 'JSON.stringify(ev)', 'given)']) assert(!TEMPLATE.includes(v), 'sys interpolates ' + v + ' again');
  assert(/const facts = turnFacts\(\{ live, uiLang, timeline, given \}\);\s*const turnText = turnContent\(facts, message\);/.test(SRC), 'the turn text is not built from turnFacts');
  // since 11 Nov 2026 the history is the case's (_shared/case_context.ts: the last turns when the case has a summary)
  assert(SRC.includes("input: [...kase.past, { role: 'user', content: turnText }]"), 'the turn text is not the newest user turn');
  // the reply check still reads every figure and contact the facts carry (their price band, the timeline)
  assert(SRC.includes("check: siteReplyCheck(brief, sys + '\\n\\n' + facts, replyLang),"), 'the reply check no longer sees this turn\'s facts');
});

Deno.test('the words are the ones sys carried; no facts leaves the message byte for byte', () => {
  assertEquals(turnContent('', 'hello'), 'hello');
  assertEquals(turnFacts({ live: null, uiLang: 'en', timeline: null, given: [] }), '');
  const f = turnFacts({ live: LIVE, uiLang: 'ar', timeline: events(1), given: given(1) });
  assert(f.startsWith('THIS PERSON IS SIGNED IN.') && f.includes('"طلب جديد"') && f.includes('price_band'));
  assert(f.includes(timelineFacts(events(1))) && f.includes(givenBlock(given(1)).trim()));
  assert(f.indexOf('THIS PERSON') < f.indexOf('THEIR CASE TIMELINE') && f.indexOf('THEIR CASE TIMELINE') < f.indexOf('TRADE KNOWLEDGE'), 'the order sys used');
  assertEquals(liveFacts(null, 'en'), ''); assertEquals(timelineFacts([]), '');
  assertEquals(turnContent(f, 'hi'), f + '\n\nMESSAGE:\nhi');
});

Deno.test('a 12-turn conversation: the system prompt is byte-identical every turn and the cache writes fall', () => {
  const out: Record<string, unknown> = {};
  for (const who of ['visitor', 'signed-in'] as const) {
    const before = conversation('before', who), after = conversation('after', who);
    assertEquals(new Set(after.systems).size, 1, who + ': the system message changed between turns');
    assert(new Set(before.systems).size === TURNS, 'the fixture does not reproduce the old per-turn change');
    out[who] = { before: { read: before.read, write: before.write, input: before.input, usd: +before.usd.toFixed(4) },
      after: { read: after.read, write: after.write, input: after.input, usd: +after.usd.toFixed(4) } };
    // CEILINGS (estimated tokens, approxTokens): the old layout wrote sys and the whole conversation again on every turn;
    // now a turn writes only its newest exchange (~215 tokens) and the facts are plain input once.
    const ceiling = approxTokens(SYS) + TURNS * (approxTokens(say(1)) + approxTokens(reply(1)) + 10);   // sys once, then one exchange a turn
    assert(after.write <= ceiling, `${who}: ${after.write} tokens written over ${TURNS} turns (ceiling ${ceiling})`);
    assert(after.write < before.write / 2, `${who}: writes ${before.write} -> ${after.write}`);
    assert(after.usd < before.usd * 0.8, `${who}: USD ${before.usd.toFixed(4)} -> ${after.usd.toFixed(4)} per conversation`);
  }
  console.log('per 12-turn conversation (estimated tokens; USD input side, claude-sonnet-5.5):', JSON.stringify(out));
});

// THE SIGNED-IN SUPPLIER IS KNOWN (customer_support, 16 Nov 2026; ledgers 1711-1713, who-knows-what audit item 5): his trades,
// emirates, jobs and why not more ride with the turn in the words every supplier door uses (_shared/supplier_known.ts).
Deno.test('a signed-in supplier\'s why-no-jobs reaches the widget turn; a customer\'s turn gets none of it', () => {
  const live = { scope: 'supplier', known: true, company: 'ZZ DEMO Polar Duct Works', profile: { approval_status: 'approved', verified: true },
    services: { confirmed: true, trades: [{ code: 'hvac', label: 'HVAC', open_to_customers: false }], emirates_covered: [] },
    matching: { receives_requests_now: true, jobs_sent_30d: 0, requests_in_his_trades_30d: 0,
      why_no_jobs: [{ code: 'trades_not_open_to_customers', says: 'None of his trades is open to customers yet.' }] } };
  const t = turnFacts({ live, uiLang: 'en', timeline: [], given: [] });
  for (const s of ['HVAC (not open to customers yet)', 'all of the UAE', 'None of his trades is open to customers yet', 'Receives requests now: yes']) assert(t.includes(s), `missing "${s}"`);
  assert(!turnFacts({ live: { scope: 'customer', known: true, inquiries: [] }, uiLang: 'en', timeline: [], given: [] }).includes('Why not more'));
});
