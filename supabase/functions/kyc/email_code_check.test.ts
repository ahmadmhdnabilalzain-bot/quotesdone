// Run: deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/kyc/email_code_check.test.ts
// Parallel wrong guesses at a kyc e-mail code cannot get past the 5-try cap (security audit 17 Nov 2026, finding 5).
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { checkEmailCode, type EmailCodeDb, type EmailCodeRow } from './email_code_check.ts';

const MAX = 5;
const RIGHT = 'h(123456)';
const hash = (c: string) => Promise.resolve(`h(${c})`);
const tick = () => new Promise((ok) => setTimeout(ok, 0));

// One row in memory. newest() reads, then yields (the network), so requests started together all read the same count,
// which is the timing the old read-then-write lost to. claim() is the conditional UPDATE: atomic, as one row update is.
function memoryDb() {
  const row: EmailCodeRow & { used_at: string | null; verified_at: string | null } = {
    id: 'zz-demo-row', expires_at: new Date(Date.now() + 600e3).toISOString(), attempts: 0, token_hash: RIGHT,
    used_at: null, verified_at: null };
  const db: EmailCodeDb = {
    newest: async () => { const read = row.used_at ? null : { ...row }; await tick(); return read; },
    claim: async (id, from) => {
      if (id !== row.id || row.used_at || row.attempts !== from) return false;
      row.attempts = from + 1; return true;
    },
    burn: async () => { row.used_at = row.used_at ?? 'burned'; },
    verified: async () => { row.used_at = 'now'; row.verified_at = 'now'; },
  };
  return { row, db };
}

Deno.test('fifty wrong guesses sent together are compared at most five times', async () => {
  const { row, db } = memoryDb();
  let compares = 0;
  const counted = (c: string) => { compares++; return hash(c); };
  for (let round = 0; round < 10; round++) {
    await Promise.all(Array.from({ length: 5 }, (_, i) => checkEmailCode(db, String(100000 + round * 5 + i), counted, MAX)));
  }
  assert(compares <= MAX, `${compares} codes were compared against one row; the cap is ${MAX}`);
  assert((row.attempts ?? 0) <= MAX, `attempts reached ${row.attempts}`);
  assertEquals(row.verified_at, null);
  assertEquals(row.used_at, 'burned', 'the code is spent once the cap is reached');
  assertEquals(await checkEmailCode(db, '123456', hash, MAX), 'no_code', 'a spent code verifies nothing, the right one included');
});

Deno.test('one guess at a time: five wrong answers, then the code is burned, even for the right code', async () => {
  const { db } = memoryDb();
  for (let i = 0; i < MAX; i++) assertEquals(await checkEmailCode(db, '000000', hash, MAX), 'wrong');
  assertEquals(await checkEmailCode(db, '123456', hash, MAX), 'burned');
});

Deno.test('the right code after two wrong ones verifies, and an expired or missing code says so', async () => {
  const { row, db } = memoryDb();
  assertEquals(await checkEmailCode(db, '000000', hash, MAX), 'wrong');
  assertEquals(await checkEmailCode(db, '000001', hash, MAX), 'wrong');
  assertEquals(await checkEmailCode(db, '123456', hash, MAX), 'ok');
  assertEquals([row.attempts, row.verified_at], [3, 'now']);
  assertEquals(await checkEmailCode(db, '123456', hash, MAX), 'no_code');
  const late = memoryDb(); late.row.expires_at = new Date(Date.now() - 1000).toISOString();
  assertEquals(await checkEmailCode(late.db, '123456', hash, MAX), 'expired');
});

Deno.test('kyc verify_email goes through checkEmailCode and writes no count it read earlier', async () => {
  const src = await Deno.readTextFile('supabase/functions/kyc/index.ts');
  assertMatch(src, /await checkEmailCode\(/);
  assertMatch(src, /\.update\(\{ attempts: from \+ 1 \}\)\.eq\('id', id\)\.eq\('attempts', from\)\.is\('used_at', null\)/,
    'the claim must be one conditional update on the count it read');
  assertEquals(/attempts: \(row\.attempts \|\| 0\) \+ 1/.test(src), false, 'the read-then-write counter is back');
});
