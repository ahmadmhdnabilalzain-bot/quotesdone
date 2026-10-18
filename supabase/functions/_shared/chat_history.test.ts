// The chat never forgets (founder, 14 Oct 2026 wardrobe chat; ruling 18 Oct 2026: no turn limit, every turn stored).
// No network, no paid call: a stubbed model and an in-memory assistant_logs that answers the same supabase-js chain
// loadTranscript uses. The model stub can only quote the wardrobe size if the size reached it in the turns it was given.
import { assert, assertEquals } from 'jsr:@std/assert';
import { accountKey, fitHistory, loadTranscript, openConversation, transcriptFromRows, type ChatMsg } from './chat_history.ts';
import { aiReply } from './ai_reply.ts';
import type { LlmReply, ThinkDeps } from './think.ts';

type Row = { id: number; conv_id: string | null; message: string | null; reply: string | null };
function fakeAdmin(rows: Row[]) {
  return {
    from: (_t: string) => ({
      insert: (r: Omit<Row, 'id'>) => { rows.push({ id: rows.length + 1, ...r }); return Promise.resolve({ error: null }); },
      update: (patch: Partial<Row>) => ({ eq: (_k: string, v: string) => ({ select: () => {
        const hit = rows.filter((r) => r.conv_id === v); hit.forEach((r) => Object.assign(r, patch));
        return Promise.resolve({ data: hit.map((r) => ({ id: r.id })), error: null }); } }) }),
      select: (_c: string) => {
        let conv = ''; const q = {
          eq: (_k: string, v: string) => { conv = v; return q; },
          order: () => q,
          range: (a: number, b: number) => Promise.resolve({ data: rows.filter((r) => r.conv_id === conv).sort((x, y) => x.id - y.id).slice(a, b + 1), error: null }),
        }; return q;
      },
    }),
  };
}

const FIRST = 'I want a custom wardrobe, 2 m high and 1.2 m wide, cheapest possible way, for a flat in Al Barsha.';
const SIZE = /2 m high and 1\.2 m wide/;

Deno.test('turn 220 of a wardrobe chat still uses turn 1, and the store holds every turn', async () => {
  const rows: Row[] = [];
  const admin = fakeAdmin(rows);
  const conv = 'p-cust-0001-tab';
  const seen: { history: ChatMsg[] }[] = [];
  const deps = {
    gate: () => Promise.resolve(null),
    llm: (_p: string, _s: string, input: string, o: { history?: ChatMsg[] }) => {
      seen.push({ history: o.history ?? [] });
      const remembered = (o.history ?? []).find((h) => h.role === 'user' && SIZE.test(h.content));
      const answer = remembered ? 'For your 2 m by 1.2 m wardrobe in Al Barsha: ' + input.slice(-40) : 'How can I help you?';
      return Promise.resolve({ content: JSON.stringify({ answer }), model: 'stub' } as LlmReply);
    },
    embed: () => Promise.resolve(null),
    rpc: () => Promise.resolve({ data: null, error: null }),
  } as unknown as ThinkDeps;

  let last = '';
  for (let turn = 1; turn <= 220; turn++) {
    const message = turn === 1 ? FIRST : turn === 220 ? 'so what size was the wardrobe again, and where?' : `detail ${turn}: hinge option ${turn % 4}, finish idea ${turn}`;
    const transcript = await loadTranscript(admin, conv);   // the database, not the browser, is the record
    assert(transcript, 'the transcript is readable');
    const r = await aiReply(deps, { seat: 'sales_engineer', channel: 'portal', audience: 'customer', lang: 'en', message,
      conversation: transcript.map((t) => ({ role: t.role === 'assistant' ? 'seat' as const : 'customer' as const, text: t.content })) });
    await admin.from('assistant_logs').insert({ conv_id: conv, message, reply: r.reply });
    last = r.reply;
  }
  // the store holds every turn, in order
  assertEquals(rows.filter((r) => r.conv_id === conv).length, 220);
  const whole = await loadTranscript(admin, conv);
  assertEquals(whole?.length, 440);
  assertEquals(whole?.[0].content, FIRST);
  // turn 220 was given all 219 earlier exchanges, turn 1 first and verbatim, and its reply used the turn-1 facts
  const at220 = seen[seen.length - 1].history;
  assertEquals(at220.length, 438);
  assertEquals(at220[0], { role: 'user', content: FIRST });
  assert(/2 m by 1\.2 m wardrobe in Al Barsha/.test(last), 'the last reply still uses the size and area from turn 1: ' + last);
  assert(!seen.some((s, i) => i > 0 && !s.history.some((h) => SIZE.test(h.content))), 'no turn after the first ever lost turn 1');
});

Deno.test('the store is read whole past one page of rows', async () => {
  const rows: Row[] = Array.from({ length: 2500 }, (_, i) => ({ id: i + 1, conv_id: 'w-x', message: 'm' + i, reply: 'r' + i }));
  const t = await loadTranscript(fakeAdmin(rows), 'w-x');
  assertEquals(t?.length, 5000);
  assertEquals(t?.[4999].content, 'r2499');
});

Deno.test('within the window nothing is left out; past it every customer turn stays and the matching old reply is retrieved', () => {
  const turns = transcriptFromRows(Array.from({ length: 500 }, (_, i) => ({ message: i === 0 ? FIRST : 'q' + i, reply: i === 3 ? 'Laminate on MDF is the cheapest carcass for your wardrobe.' : 'a' + i })));
  assertEquals(fitHistory(turns, 'next').length, 1000);   // 500 messages, all of them
  const tight = fitHistory(turns, 'which carcass was cheapest for the wardrobe?', 3500);
  assert(tight.some((t) => t.content === FIRST), 'turn 1 kept');
  assertEquals(tight.filter((t) => t.role === 'user').length, 500);   // every customer turn, verbatim
  assert(tight.some((t) => /Laminate on MDF/.test(t.content)), 'the old reply the question is about was retrieved');
  const order = tight.map((t) => turns.findIndex((x) => x.role === t.role && x.content === t.content));
  assertEquals(order, [...order].sort((a, b) => a - b));
});

// ── ruling 1255 (19 Oct 2026): the agent can't lose the chat, whatever happens to the browser or the account ──
const replyDeps = (seen: ChatMsg[][]) => ({
  gate: () => Promise.resolve(null),
  llm: (_p: string, _s: string, _i: string, o: { history?: ChatMsg[] }) => {
    seen.push(o.history ?? []);
    const r = (o.history ?? []).some((h) => SIZE.test(h.content)) ? 'For your 2 m by 1.2 m wardrobe in Al Barsha: noted.' : 'How can I help you?';
    return Promise.resolve({ content: JSON.stringify({ answer: r }), model: 'stub' } as LlmReply);
  },
  embed: () => Promise.resolve(null), rpc: () => Promise.resolve({ data: null, error: null }),
}) as unknown as ThinkDeps;
// one turn exactly as site_assistant / sales_engineer take it: resolve the conversation, answer from it, store the turn
async function turn(admin: ReturnType<typeof fakeAdmin>, deps: ThinkDeps, who: { account?: string; visitorConv?: string }, message: string) {
  const c = await openConversation(admin, who);
  assert(c.turns, 'readable');
  const r = await aiReply(deps, { seat: 'customer_support', channel: 'website', audience: 'customer', lang: 'en', message,
    conversation: c.turns.map((t) => ({ role: t.role === 'assistant' ? 'seat' as const : 'customer' as const, text: t.content })) });
  await admin.from('assistant_logs').insert({ conv_id: c.key, message, reply: r.reply });
  return { ...c, reply: r.reply };
}

Deno.test('a reload, a closed browser, a return days later: the conversation comes back from the database whole', async () => {
  const rows: Row[] = []; const seen: ChatMsg[][] = [];
  const visitor = '7c1d2f40-aaaa-4bbb-8ccc-000000000001';   // the id ChatWidget keeps in localStorage
  // day 1, first tab: 10 turns
  for (let i = 1; i <= 10; i++) await turn(fakeAdmin(rows), replyDeps(seen), { visitorConv: visitor }, i === 1 ? FIRST : 'detail ' + i);
  // days later, a NEW process and a NEW browser session: nothing in memory, no history from the client, the same id
  const back = await openConversation(fakeAdmin(rows), { visitorConv: visitor });
  assertEquals(back.turns?.length, 20);                      // what the widget redraws (action 'history')
  assertEquals(back.turns?.[0].content, FIRST);
  const next = await turn(fakeAdmin(rows), replyDeps(seen), { visitorConv: visitor }, 'what size did I say?');
  assert(/2 m by 1.2 m/.test(next.reply), 'the agent still has turn 1: ' + next.reply);
  // the provider cache plays no part: the model was handed every stored turn, read fresh from the store
  assertEquals(seen[seen.length - 1].length, 20);
  // a short or missing id never reads anybody's conversation
  assertEquals((await openConversation(fakeAdmin(rows), { visitorConv: 'a' })).turns, []);
});

Deno.test('signing up mid-conversation carries the whole widget chat into the portal, and nothing is deleted', async () => {
  const rows: Row[] = []; const seen: ChatMsg[][] = [];
  const visitor = '7c1d2f40-aaaa-4bbb-8ccc-000000000002';
  for (let i = 1; i <= 12; i++) await turn(fakeAdmin(rows), replyDeps(seen), { visitorConv: visitor }, i === 1 ? FIRST : 'widget detail ' + i);
  const account = accountKey('customer', 'cust-uuid-1');
  // first portal call after sign-up (assist_history or assist), presenting the widget id from localStorage
  const portal = await openConversation(fakeAdmin(rows), { account, visitorConv: visitor });
  assertEquals(portal.adopted, 12);
  assertEquals(portal.turns?.length, 24);
  assertEquals(portal.turns?.[0].content, FIRST);
  // the sales engineer answers from it, through 8 more portal turns
  let last = '';
  for (let i = 1; i <= 8; i++) last = (await turn(fakeAdmin(rows), replyDeps(seen), { account, visitorConv: visitor }, 'portal question ' + i)).reply;
  assert(/2 m by 1.2 m wardrobe in Al Barsha/.test(last), 'the portal still uses what was said before sign-up: ' + last);
  assertEquals(rows.length, 20);                             // every row still there: adoption re-keys, never deletes
  assertEquals((await loadTranscript(fakeAdmin(rows), account))?.length, 40);
  // the visitor id now reads nothing for anyone else, and another account presenting it adopts nothing
  assertEquals((await openConversation(fakeAdmin(rows), { visitorConv: visitor })).turns, []);
  const other = await openConversation(fakeAdmin(rows), { account: accountKey('customer', 'cust-uuid-2'), visitorConv: visitor });
  assertEquals([other.adopted, other.turns?.length], [0, 0]);
});
