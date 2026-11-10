// THE PORTAL PUTS OPTIONS TO A CUSTOMER WHO IS DECIDING (10 Nov 2026, sales_engineer; founder ledger 1572, 1586). No network.
// The portal's rules now carry the ADVISE step and allow one short line per option, and the sentence filter that drops
// "lines nobody asked for" (portal_conversation.replyFilter) keeps a reply that advises: three option lines with their
// trade-offs and the one question that prices it. Known-bad control: the same reply with a fee line still loses that line.
// Run: deno test --no-lock --node-modules-dir=none supabase/functions/sales_engineer/the_portal_advises_options.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { heldState, PORTAL_INTAKE, REPLY_SHAPE, stripReply } from './portal_conversation.ts';
import { portalRules } from './portal_turn.ts';

Deno.test('the rules carry the ADVISE step and room for the options', () => {
  assert(/\(1b\) When they describe a problem or ask what to do and have not chosen a solution, advise first/.test(PORTAL_INTAKE));
  assert(/Once they choose, never offer options again/.test(PORTAL_INTAKE));
  assert(/up to three more short lines, one per option/.test(REPLY_SHAPE));
  assert(portalRules().includes('(1b)'));
});

Deno.test('an advising reply survives the filter whole; a fee line in it is still dropped (known-bad control)', () => {
  const past = [{ role: 'user' as const, content: 'I have a small MDF partition and want to cover it, PVC panels or a wrap sticker?' }];
  const msg = 'It is in a kids room, what do you recommend?';
  const h = heldState(past, msg);
  const reply = 'For a small MDF partition in a kids room there are three good routes. '
    + 'PVC or WPC wall panels are moisture-proof and quick to fix, though the joints show. '
    + 'A vinyl film wrap keeps the shape and edges and is low-odour, but the board must be smooth and sealed first. '
    + 'Paint is the simplest refresh, and a laminate facing is the toughest, with more joinery work. '
    + 'What size is the partition, and is it one face or both?';
  const s = stripReply(reply, h);
  assertEquals(s.dropped, [], JSON.stringify(s.dropped));
  assertEquals(s.text, reply);
  const withFee = reply.replace('Paint is the simplest', 'Posting your request is free of charge. Paint is the simplest');
  assert(stripReply(withFee, h).dropped.some((d) => /fee/.test(d.why)), 'the unasked fee line was kept');
});
