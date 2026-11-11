// The promise ledger's due times are read by code from our own words, in Dubai time (UTC+4; week Monday to Friday).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { carryWording, dueFrom, recordedPromises, stampPromises } from './case_promises.ts';
import { checkSummary, renderSummary, summariseExchange } from './support_case_memory.ts';
import type { LlmReply, ThinkDeps } from './think.ts';

// Wednesday 11 Nov 2026, 14:00 in Dubai
const WED = new Date('2026-11-11T10:00:00Z');
const iso = (d: Date | null) => d?.toISOString() ?? null;

Deno.test('a day with no time is due at the close of business (18:00 Dubai); a named time is kept', () => {
  assertEquals(iso(dueFrom('tomorrow', WED)), '2026-11-12T14:00:00.000Z');
  assertEquals(iso(dueFrom('tomorrow at 10am', WED)), '2026-11-12T06:00:00.000Z');
  assertEquals(iso(dueFrom('Thursday', WED)), '2026-11-12T14:00:00.000Z');
  assertEquals(iso(dueFrom('by Wednesday', WED)), '2026-11-11T14:00:00.000Z', 'the same weekday, before the close: today');
  assertEquals(iso(dueFrom('by Wednesday', new Date('2026-11-11T15:00:00Z'))), '2026-11-18T14:00:00.000Z', 'after the close: next week');
  assertEquals(iso(dueFrom('today', WED)), '2026-11-11T14:00:00.000Z');
  assertEquals(iso(dueFrom('2026-11-20', WED)), '2026-11-20T14:00:00.000Z');
  assertEquals(iso(dueFrom('14 Nov', WED)), '2026-11-14T14:00:00.000Z');
  assertEquals(iso(dueFrom('Jan 3', WED)), '2027-01-03T14:00:00.000Z', 'a month already past is next year');
  assertEquals(iso(dueFrom('غداً', WED)), '2026-11-12T14:00:00.000Z');
});

Deno.test('spans: hours from the moment it was said; working days skip Saturday and Sunday; a range reads its upper bound', () => {
  assertEquals(iso(dueFrom('within 24 hours', WED)), '2026-11-12T10:00:00.000Z');
  assertEquals(iso(dueFrom('in 2 hours', WED)), '2026-11-11T12:00:00.000Z');
  assertEquals(iso(dueFrom('3 working days', WED)), '2026-11-16T14:00:00.000Z', 'Thu, Fri, Mon');
  assertEquals(iso(dueFrom('usually within 3-5 working days', WED)), '2026-11-18T14:00:00.000Z');
  assertEquals(iso(dueFrom('end of the week', WED)), '2026-11-13T14:00:00.000Z', 'Friday');
});

Deno.test('words that name no time give null (the ledger assumes a due date and says so)', () => {
  for (const s of [null, '', 'as they arrive', 'soon', 'shortly']) assertEquals(dueFrom(s, WED), null, String(s));
});

Deno.test('a reworded promise the case already holds keeps its recorded wording and date: one promise, one ledger row', () => {
  const before = renderSummary({ asked: 'a quote', said_or_did: 'asked sizes', open: [],
    promised: [{ what: 'send the quotes as they arrive', by: 'Thursday' }, { what: 'call them back', by: null }] });
  assertEquals(recordedPromises(before), [{ what: 'send the quotes as they arrive', by: 'Thursday' }, { what: 'call them back', by: null }]);
  const carried = carryWording([{ what: 'send them the quotes as they arrive', by: null }, { what: 'confirm the site visit', by: 'Friday' }], before);
  assertEquals(carried, [{ what: 'send the quotes as they arrive', by: 'Thursday' }, { what: 'confirm the site visit', by: 'Friday' }]);
});

Deno.test('the summary step stamps every stated promise with its kind and due time before the write', async () => {
  let wrote: Record<string, unknown> | null = null;
  const d = {
    rpc: (fn: string, a: Record<string, unknown>) => { if (fn === 'fn_support_case_summary_write') wrote = a; return Promise.resolve({ data: { ok: true }, error: null }); },
    llm: () => Promise.resolve({ model: 'm', content: JSON.stringify({ title: 'Windows', asked: 'a quote for windows', said_or_did: 'took the sizes',
      promised: [{ what: 'send the quotes', by: 'tomorrow', kind: 'quotes' }, { what: 'call them back', by: null, kind: 'invent-a-kind' }, { what: 'give a discount', by: null }],
      open: [] }) } as LlmReply),
    embed: () => Promise.resolve(null),
  } as unknown as ThinkDeps;
  const r = await summariseExchange(d, { memory: { ref: 'QD-C1', summaryText: '', version: 0, profile: 1 }, theirMessage: 'sizes are 1x2',
    ourReply: 'Thank you. We will send the quotes tomorrow, and we will call them back if anything is missing.', seat: 'sales_engineer' });
  assertEquals(r.ok, true);
  // deno-lint-ignore no-explicit-any
  const p = (wrote as any).p_summary.promised as { what: string; kind: string; due_at: string | null }[];
  assertEquals(p.map((x) => [x.what, x.kind, !!x.due_at]), [['send the quotes', 'quotes', true], ['call them back', 'other', false]], 'the unstated discount is dropped; an unknown kind is other');
  assert(Date.parse(p[0].due_at!) > Date.now(), 'tomorrow is in the future');
  assertEquals(wrote!.p_written_by, 'sales_engineer', 'the seat that answered owns the promises');
});

Deno.test('checkSummary keeps the kind only as one of two words', () => {
  const s = checkSummary({ asked: 'a', said_or_did: 'b', open: [], promised: [{ what: 'send the quotes', by: null, kind: 'quotes' }, { what: 'send the quotes now', by: null, kind: 'DROP TABLE' }] },
    { ourReply: 'we will send the quotes now' })!;
  assertEquals(s.promised.map((x) => x.kind), ['quotes', 'other']);
  assertEquals(stampPromises(s, { madeAt: WED }).promised.map((x) => x.due_at), [null, null]);
});
