// AN EDITED FAQ ANSWER IS RE-EMBEDDED, AND A QUOTE IS NOT A FEE — customer_support, 23 Sep 2026.
// Pairs with scripts/sql/an_edited_faq_answer_is_re_embedded_and_a_quote_is_not_a_fee.sql.
//
// 1. Editing company_faq.question/answer clears embedding_gte (so embed_sales_knowledge.mjs rebuilds it),
//    and a write that sets a new vector with the text keeps it. Proved in a transaction never committed.
// 2. The rows #872 rewrote carry the vector of their CURRENT text: gte-small(question + "\n" + answer),
//    the recipe the stored vectors are built from, reproduces the stored one (cosine >= 0.999).
// 3. WhatsApp's retrieval (fn_faq_answer with the asker's vector and wa_inbound's 0.84 floor) answers a
//    drawing question in English and in Arabic with the corrected text, and "ما هي رسومكم" is never
//    answered with a quotation FAQ.
// Free in-region gte-small through ai_gateway action 'embed' — never OpenRouter.
//
//   node --test scripts/checks/an_edited_faq_answer_is_re_embedded.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql, PROJECT_REF } from '../lib/db.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

const lit = (s) => `'${String(s).replace(/'/g, "''")}'`;
let secret = null;
async function embed(text) {
  if (!secret) secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
  for (let i = 0; i < 3; i++) {
    const r = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/ai_gateway`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: secret, fn: 'check_faq_reembed', action: 'embed', text }) });
    const j = await r.json().catch(() => ({}));
    if (j.embedding) return typeof j.embedding === 'string' ? j.embedding : '[' + j.embedding.join(',') + ']';
  }
  throw new Error('gte-small returned no vector for: ' + text);
}
const ask = async (q) => (await sql(`select public.fn_faq_answer(${lit(q)}, 0.15, ${lit(await embed(q))}::vector, 0.84) a`))[0].a;

test('a text edit clears the vector; a vector written with the text is kept', { skip: SKIP }, async () => {
  const [r] = await sql(`begin;
    update public.company_faq set answer = answer || ' ' where id = 1;
    select (select embedding_gte is null from public.company_faq where id = 1) cleared;`, { retry: false });
  assert.equal(r.cleared, true, 'editing the answer left the old vector in place');
  const [k] = await sql(`begin;
    update public.company_faq set answer = answer || ' ', embedding_gte = (select embedding_gte from public.company_faq where id = 2) where id = 1;
    select embedding_gte is not null kept from public.company_faq where id = 1;`, { retry: false });
  assert.equal(k.kept, true, 'the embedder\'s own write was cleared');
});

test('the rewritten rows carry the vector of their current text', { skip: SKIP, timeout: 120000 }, async () => {
  const rows = await sql(`select id, question, answer from public.company_faq where id in (16, 20, 116, 126, 289, 605, 663, 718, 741) order by id`);
  for (const r of rows) {
    const [c] = await sql(`select embedding_gte is not null has, round((1 - (embedding_gte <=> ${lit(await embed(r.question + '\n' + r.answer))}::vector))::numeric, 4) cos
                             from public.company_faq where id = ${r.id}`);
    assert.equal(c.has, true, `FAQ ${r.id} has no vector`);
    assert.ok(Number(c.cos) >= 0.999, `FAQ ${r.id}: stored vector is of other text (cosine ${c.cos})`);
  }
});

test('WhatsApp answers a drawing question with the corrected text, and a fee question never with a quote', { skip: SKIP, timeout: 120000 }, async () => {
  const en = await ask('will suppliers see my drawing?');
  assert.equal(en.answered, true, JSON.stringify(en));
  assert.match(en.answer, /covered/, `English drawing answer is not the corrected text: ${en.question}`);
  const ar = await ask('هل يمكنني رفع المخططات؟');
  assert.equal(ar.answered, true, JSON.stringify(ar));
  assert.match(ar.answer, /تغطية/, `Arabic drawing answer is not the corrected text: ${ar.question}`);
  assert.doesNotMatch(ar.answer, /تلقائي/, 'Arabic drawing answer still promises automatic redaction');
  for (const q of ['ما هي رسومكم', 'كم رسومكم']) {
    const a = await ask(q);
    if (!a.answered) continue;               // the menu again is acceptable; a wrong answer is not
    assert.doesNotMatch(a.question, /عرو?ض\s+(ال)?(سعر|أسعار|الأسعار)/, `"${q}" was answered with a quotation FAQ: ${a.question} (${a.confidence})`);
    assert.match(a.question + a.answer, /رسوم|٪/, `"${q}" was answered with "${a.question}"`);
  }
});
