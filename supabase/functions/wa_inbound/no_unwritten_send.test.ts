// RULINGS 1195/1196/1197 (12 Oct 2026): in wa_inbound every CONVERSATION reply is written by a model in that turn.
// index.ts cannot be driven end to end offline, so this reads it: every text that reaches sendWa(From, …) is assigned
// only from the model (say / sayFor / sayC, model_says.ts), from a guard over such text, from the HELD NOTICE (the
// fixed receipt when no model answered — a notification, review of #1335), or '' — and the one named notification
// (the accepted-offer confirmation). It fails the moment a literal sentence, a routine's own message, an FAQ row or a
// deterministic answer is assigned to a reply variable again. The menu's sends are proved by menu_flow.test.ts
// (1195-1197 test); the writer and the held notice by model_says.test.ts.
import { assert, assertEquals } from 'jsr:@std/assert@1';

const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
const code = src.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');

Deno.test('1195-1197: every WhatsApp reply variable is assigned only model-written text, the held notice, or nothing', () => {
  const sends = [...code.matchAll(/sendWa\(From, (\w+)\)/g)].map((m) => m[1]);
  // 't' is holdUnwritten's send, which only ever sends HELD_NOTICE (model_says.test.ts)
  assertEquals(new Set(sends), new Set(['replyS', 'reply', 'replyD', 't']), 'a new direct send appeared: prove its text is model-written here');
  const sources = new Set([...sends.filter((v) => v !== 't'), 'text', 'out']);
  const bad: string[] = [];
  for (const v of sources) {
    for (const m of code.matchAll(new RegExp(`(?:^|[^\\w.])(?:let |const )?${v}\\s*=\\s*([^;\\n]+(?:\\n\\s+[?:+][^;\\n]+)*)`, 'g'))) {
      const rhs = m[1].trim();
      const ok = /^''$/.test(rhs) || /^String\(out\.reply/.test(rhs)
        || /^(?:\(?await (?:say|sayFor|sayC)\b)/.test(rhs)
        || /^(?:text|out|reply|replyS|replyD) \? (?:toContact|bidiSafe)\((?:text|out|reply)\.slice\(0, 1200\)\) : ''$/.test(rhs)
        || /^reply\.trim\(\) \? bidiSafe\(reply\.slice\(0, 1200\)\) : ''$/.test(rhs)
        || /^\(await say\(situation\)\)\.slice\(0, 1200\)$/.test(rhs)
        || rhs === 'toContact(reply)'                   // the outgoing guard over the model's own text
        || rhs === 'h.notice'                           // the HELD NOTICE: a notification when no model answered
        || (v === 'text' && rhs === 'msg.body');        // the accepted-offer confirmation: a NOTIFICATION
      if (!ok) bad.push(v + ' = ' + rhs.slice(0, 120));
    }
  }
  assertEquals(bad, [], 'reply text assigned from something other than the model:\n' + bad.join('\n'));
});

Deno.test('1195-1197: the only notification sent as-is is the accepted-offer confirmation, and it is marked', () => {
  assert(/so\.state === 'accepted'\) \{ text = msg\.body; notice = true; \}/.test(code));
});

Deno.test('1195-1197: no stored-sentence road remains, and no path leaves the person silent', () => {
  for (const gone of ["route: 'deterministic'", 'welcomeFirstContact(', 'supportReply(', 'publicSys', 'FACTS_SHARED', "p_answered_by: 'deterministic'"]) {
    assert(!code.includes(gone), gone + ' is back in wa_inbound');
  }
  // spec offer, founder setting, document, supplier price, main reply: each sends the held notice when no model answered
  assertEquals((code.match(/const h = await heldTurn\(/g) || []).length, 5, 'every direct no-model path sends the held notice');
  assert(/held: \(r\) => heldTurn\(/.test(code), 'the menu sends the held notice too');
});

Deno.test('review of #1335: the per-number rate key is carried, and the model\'s own escalate flag is OR-ed with the router', () => {
  assert(code.includes("rateKey: 'wa:' + From"), 'the per-number ceiling (wa:<From>) reaches the gateway');
  assert(code.includes('const escalate = route?.needs_a_person === true || modelEscalate;'), 'a complaint the router misses still reaches a person');
});
