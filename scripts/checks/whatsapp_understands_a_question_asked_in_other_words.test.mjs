// WHATSAPP UNDERSTANDS A QUESTION ASKED IN OTHER WORDS — and says nothing rather than guess.
//
// customer_support, 22 Sep 2026, founder instruction 763. wa_inbound called fn_faq_answer with no
// embedding, so a question was answered only when its stemmed words matched a record; the semantic
// branch it could have used accepted the nearest neighbour on cosine alone. Both are fixed
// (supabase/functions/wa_inbound/index.ts embeds with the in-region gte-small; fn_faq_answer needs the
// asker's own words to corroborate the neighbour — the_whatsapp_menu_answers_like_a_senior_member_of_staff.sql).
//
// This replays what WhatsApp does: the question is embedded by the SAME model (ai_gateway action
// 'embed', Supabase.ai gte-small, free, never OpenRouter) and fn_faq_answer is called with the vector
// and wa_inbound's floor (0.84). It fails if a paraphrase stops reaching its answer, or if a question
// the FAQ does not cover gets an answer anyway.
//
//   node --test scripts/checks/whatsapp_understands_a_question_asked_in_other_words.test.mjs
//   SIMULATE=1 node --test ...   # (automatic while the SQL file has a pending note) applies the
//                                # pending SQL file and embeds the missing FAQ rows inside ONE
//                                # transaction that is never committed, then asks the same questions
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { sql, PROJECT_REF } from '../lib/db.mjs';

const ROOT = fileURLToPath(new URL('../..', import.meta.url));
const FILE = 'scripts/sql/the_whatsapp_menu_answers_like_a_senior_member_of_staff.sql';
const FLOOR = 0.84;   // wa_inbound's FAQ_MIN_SIMILARITY
// While the SQL file is still pending (scripts/sql/pending/<name>.txt), production has the old routine,
// so the check simulates instead of failing on what has not shipped. Once applied it asks production,
// and fails until the FAQ backfill has run too -- which is the point.
const SIMULATE = !!process.env.SIMULATE || existsSync(join(ROOT, FILE.replace('scripts/sql/', 'scripts/sql/pending/').replace(/\.sql$/, '.txt')));

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

// [question, the FAQ questions that are a right answer, or null = must NOT answer by meaning]
export const CASES = [
  ['how much do you charge', ['What are the platform fees?', 'What is the 3% fee?', 'When is it charged?']],
  ['is it free for suppliers', ['Is there a subscription fee for suppliers?']],
  ['كم رسومكم', ['ما هي رسوم المنصة؟', 'ما هي رسوم الـ 3٪؟', 'متى يتم تحصيل الرسوم؟']],
  // The Arabic corpus has no supplier-fee record (23 rows, measured): the registration answer is right,
  // silence (the menu again) is acceptable, a customer-fee answer is not.
  ['هل التسجيل مجاني للموردين', ['كيف أسجل كمورد؟'], 'or_none'],
  ['what is the weather in paris', null],
  ['ما هو سعر الذهب اليوم', null],
  ['can i trust the suppliers on your site', null],
];

const lit = (s) => `'${String(s).replace(/'/g, "''")}'`;
let secret = null;
async function embed(text) {
  if (!secret) secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
  for (let i = 0; i < 3; i++) {
    const r = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/ai_gateway`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: secret, fn: 'check_wa_paraphrase', action: 'embed', text }) });
    const j = await r.json().catch(() => ({}));
    if (j.embedding) return typeof j.embedding === 'string' ? j.embedding : '[' + j.embedding.join(',') + ']';
  }
  throw new Error('gte-small returned no vector for: ' + text);
}

async function answers() {
  const calls = [];
  for (const [q] of CASES) calls.push(`public.fn_faq_answer(${lit(q)}, 0.15, ${lit(await embed(q))}::vector, ${FLOOR})`);
  const select = `select jsonb_agg(a order by n) r from (values ${calls.map((c, i) => `(${i}, ${c})`).join(',')}) v(n, a)`;
  if (!SIMULATE) return (await sql(select))[0].r;
  // Simulation: the pending routine and the missing vectors, in a transaction nobody commits.
  const missing = await sql(`select id, question, answer from public.company_faq
                              where public and status = 'approved' and embedding_gte is null`);
  const vals = [];
  for (const m of missing) vals.push(`(${m.id}, ${lit(await embed(m.question + '\n' + m.answer))}::vector)`);
  const fill = vals.length ? `update public.company_faq f set embedding_gte = v.e from (values ${vals.join(',')}) v(id, e) where f.id = v.id;` : '';
  return (await sql(`begin;\n${readFileSync(join(ROOT, FILE), 'utf8')}\n;\n${fill}\n${select}`, { retry: false }))[0].r;
}

test('a question asked in other words reaches its answer, and an uncovered one gets none', { skip: SKIP, timeout: 300000 }, async () => {
  const got = await answers();
  if (process.env.SHOW) CASES.forEach(([q], i) => console.log(q, '->', JSON.stringify({ ...got[i], answer: undefined })));
  CASES.forEach(([q, ok, orNone], i) => {
    const a = got[i];
    if (ok && orNone && !a.answered) return;
    if (ok) {
      assert.equal(a.answered, true, `"${q}" was not answered: ${JSON.stringify(a)}`);
      assert.ok(ok.includes(a.question), `"${q}" was answered with "${a.question}" (${a.source} ${a.confidence})`);
    } else {
      // No answer at all: wa_inbound then offers the menu again (reofferMenu) instead of guessing.
      assert.equal(a.answered, false, `"${q}" was answered with "${a.question}" (${a.source} ${a.confidence}); it must get the menu instead`);
    }
  });
});
