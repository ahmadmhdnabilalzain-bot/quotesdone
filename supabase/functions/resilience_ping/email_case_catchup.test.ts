// The e-mail case summary a reply owes is caught up by the beat (ticks/email_case_catchup.ts). Stubbed database and writer.
import { assertEquals } from 'jsr:@std/assert@1';
import { emailCaseCatchup } from './ticks/email_case_catchup.ts';
import type { ThinkDeps } from '../_shared/think.ts';

const owedRow = (ref: string, their: string, ours: string) => ({ case_ref: ref, summary_text: '', summary_version: 0, profile: 7, their_message: their, our_reply: ours });
function deps(rows: unknown[] | null, error: string | null = null): ThinkDeps {
  return { gate: () => Promise.resolve({ allowed: true } as never), llm: () => Promise.reject(new Error('no model in this test')), embed: () => Promise.resolve([]),
    rpc: (fn) => Promise.resolve(fn === 'fn_support_case_email_summaries_owed' ? { data: rows, error: error ? { message: error } : null } : { data: null, error: null }) } as ThinkDeps;
}

Deno.test('each owed e-mail exchange is summarised once; an empty side is skipped; a failure is counted, never thrown', async () => {
  const seen: string[] = [];
  const write = (_d: ThinkDeps, o: { memory: { ref: string }; theirMessage: string; ourReply: string }) => {
    seen.push(o.memory.ref + '|' + o.theirMessage + '|' + o.ourReply);
    return Promise.resolve(o.memory.ref === 'QD-S-BAD' ? { ok: false, reason: 'not json' } : { ok: true });
  };
  const r = await emailCaseCatchup(deps([owedRow('QD-S-AAA', 'Where is my quote?', 'It arrives tomorrow.'), owedRow('QD-S-EMPTY', 'Hello', ''),
    owedRow('QD-S-BAD', 'Still nothing', 'We are checking.')]), 3, write);
  assertEquals(r, { ok: false, owed: 3, written: 1, failed: 1 });
  assertEquals(seen, ['QD-S-AAA|Where is my quote?|It arrives tomorrow.', 'QD-S-BAD|Still nothing|We are checking.']);
  const e = await emailCaseCatchup(deps(null, 'function does not exist'), 3, write);
  assertEquals(e.ok, false);
  assertEquals(e.owed, 0);
});
