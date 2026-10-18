// logWithAttempts (reply_attempts.ts). No network.
import { assertEquals } from 'jsr:@std/assert';
import { logWithAttempts } from './reply_attempts.ts';

function db(columnLive: boolean) {
  const rows: Record<string, unknown>[] = [];
  return { rows, from: (_t: string) => ({ insert: (r: Record<string, unknown>) => {
    if (!columnLive && 'reply_attempts' in r) return Promise.resolve({ data: null, error: { message: 'column "reply_attempts" of relation "assistant_logs" does not exist' } });
    rows.push(r); return Promise.resolve({ data: null, error: null });
  } }) };
}

// prevented by: this test. The attempts are kept once the column exists; before it does, the log row is never lost.
Deno.test('attempts ride on the log row; without the column the row is still written', async () => {
  const live = db(true);
  await logWithAttempts(live, 'assistant_logs', { message: 'q' }, { attempts: ['stream:ok'] });
  assertEquals(live.rows, [{ message: 'q', reply_attempts: { attempts: ['stream:ok'] } }]);
  const before = db(false);
  const r = await logWithAttempts(before, 'assistant_logs', { message: 'q' }, { attempts: ['rewrite:ok [x]'] });
  assertEquals(before.rows, [{ message: 'q' }]);
  assertEquals(r.error, null);
});
