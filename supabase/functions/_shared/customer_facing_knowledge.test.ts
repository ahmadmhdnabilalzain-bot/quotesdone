// Founder ruling 1338 (27 Oct 2026): "Withhold from customers." Model-written kb_chunks rows (source_kind 'generated')
// and agent notes ('memory') are never told to a customer or a supplier; every read source still is.
import { assert, assertEquals } from 'jsr:@std/assert';
import { KB_CHUNKS_NOT_CUSTOMER_FACING, kbChunkIsCustomerFacing } from './customer_facing_knowledge.ts';

Deno.test('generated and memory kb_chunks rows are withheld; the read source kinds pass', () => {
  assertEquals([...KB_CHUNKS_NOT_CUSTOMER_FACING].sort(), ['generated', 'memory']);
  for (const k of ['generated', 'memory', ' generated ']) assert(!kbChunkIsCustomerFacing(k), k);
  // every other source kind measured on production 27 Oct 2026
  for (const k of ['standard', 'cert', 'code', 'guide', 'document', 'trade', 'regulation', 'company_faq', 'library', 'paper', 'reference', 'material']) {
    assert(kbChunkIsCustomerFacing(k), k);
  }
});

Deno.test('fails closed: a missing, empty or non-text source_kind is not trusted', () => {
  for (const k of [null, undefined, '', '   ', 7, {}, ['standard']]) assert(!kbChunkIsCustomerFacing(k), JSON.stringify(k));
});

Deno.test('every edge reader that hands kb_chunks text to a customer goes through the one rule, not a copy', async () => {
  const read = (p: string) => Deno.readTextFile(new URL(p, import.meta.url));
  const intake = await read('../inquiry_intake/index.ts');
  const at = intake.indexOf("admin.rpc('kb_query'");
  assert(at > 0, 'inquiry_intake no longer calls kb_query: re-check where its passages come from');
  assert(intake.slice(at, at + 2500).includes('.filter((c: any) => kbChunkIsCustomerFacing(c?.source_kind))'), 'inquiry_intake gives kb_query passages to the customer unfiltered');
  const portal = await read('../sales_engineer/portal_turn.ts');
  assert(/kb_chunks: \{ table: 'kb_chunks', key: 'id', select: 'id, source_kind',\s+safe: \(f\) => kbChunkIsCustomerFacing\(f\.source_kind\) \}/.test(portal), 'portal_turn kb_chunks rule is not the shared one');
  // no second copy of the list anywhere in the edge code
  for (const p of ['../sales_engineer/portal_turn.ts', '../inquiry_intake/index.ts']) {
    assert(!/source_kind\s*!==?\s*'(generated|memory)'/.test(await read(p)), p + ' carries its own copy of the rule');
  }
});
