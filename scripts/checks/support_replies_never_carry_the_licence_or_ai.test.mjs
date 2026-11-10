// customer_support: every outgoing support reply passes supabase/functions/_shared/support_reply_guard.ts.
//
// Measured 28 Sep 2026: 4 production widget replies carried the trade licence number (latest 22 Sep, to
// "What does QuotesDone do?"), and an Arabic corpus answer went out with an English contact line on the
// end. This fails if the guard stops catching either, if a support channel stops calling it, or if the
// number comes back into a support prompt.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { guardSupportReply, replyViolations } from '../../supabase/functions/_shared/support_reply_guard.ts';

const src = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
import { functionSource } from '../lib/function_sources.mjs';
// Built from parts so this file never holds the number it forbids.
const LIC = ['163', '3275'].join('');

test('the production leak is caught and only its sentence is removed', () => {
  const leaked = `QuotesDone is the UAE's anonymous quotation marketplace. It is operated by QuotesDone Technologies, a Dubai DET-licensed business (E-Trader Licence No. ${LIC}).\n\nIf that does not cover it, call us.`;
  const g = guardSupportReply(leaked, 'en');
  assert.deepEqual(g.violations, ['licence']);
  assert.ok(!g.text.includes(LIC));
  assert.match(g.text, /anonymous quotation marketplace/);
  assert.match(g.text, /\n\nIf that does not cover it/);
});

test('the Arabic form of the licence is caught', () => {
  const g = guardSupportReply(`نحن سوق عروض أسعار. رخصة تاجر إلكتروني رقم ${LIC}.`, 'ar');
  assert.ok(g.violations.includes('licence'));
  assert.ok(!g.text.includes(LIC));
});

test('"AI" becomes "smart" in both scripts; Dubai and "said" are untouched', () => {
  const g = guardSupportReply('Our AI-powered engine said Dubai jobs are matched by AI.', 'en');
  assert.deepEqual(g.violations, ['ai_word']);
  assert.equal(g.text, 'Our smart engine said Dubai jobs are matched by smart.');
  assert.ok(guardSupportReply('نستخدم الذكاء الاصطناعي', 'ar').text.includes('التقنية الذكية'));
  assert.deepEqual(replyViolations('We serve Dubai and Abu Dhabi.'), []);
});

// 12 Oct 2026 (rulings 1195/1196, review of #1330): no canned replacement. A refused reply sends nothing from here;
// callers check replyViolations() first and the model rewrites (_shared/ai_reply.ts).
test('an internal error or prompt wording refuses the whole reply: nothing is sent, no canned line replaces it', () => {
  for (const bad of ['Sorry, ai_gateway returned circuit_open', 'TypeError: x is undefined at run (index.ts:4:2)',
                     'fn_support_corpus_search failed', 'Per the AUDIENCE RULES I cannot say']) {
    const g = guardSupportReply(bad, 'en');
    assert.equal(g.text, '', bad);
    assert.ok(g.violations.length, bad);
  }
  assert.equal(guardSupportReply('supabase error', 'ar').text, '');
});

test('a clean reply passes unchanged', () => {
  const ok = 'Comparing quotes is free. The 3% reveal fee applies only when you reveal a supplier.';
  assert.deepEqual(guardSupportReply(ok, 'en'), { text: ok, violations: [] });
});


test('both support channels call the guard, and neither prompt carries the number', () => {
  // site_assistant's guard runs inside siteReplyCheck since 3 Nov 2026 (it_engineer, #1836: the same check now also runs
  // replyProblems), so the widget is asserted through that module: it calls the guard, and the widget hands it to answerFromBrief.
  const guarded = { 'supabase/functions/wa_inbound/replies.ts': '../_shared/support_reply_guard.ts', 'supabase/functions/site_assistant/reply_check.ts': '../_shared/support_reply_guard.ts' };
  for (const [f, from] of Object.entries(guarded)) {
    const s = src(f);
    assert.match(s, new RegExp(`import \\{[^}]*guardSupportReply[^}]*\\} from '${from.replace(/[.]/g, '\\.')}'`), f);
    assert.match(s, /guardSupportReply\(/, f);
  }
  const site = src('supabase/functions/site_assistant/index.ts');
  assert.match(site, /import \{ siteReplyCheck(, siteReplyLanguage)? \} from '\.\/reply_check\.ts'/);
  assert.match(site, /check: siteReplyCheck\(brief, sys, replyLang\),/);
  for (const f of ['supabase/functions/site_assistant/index.ts', 'supabase/functions/wa_inbound/index.ts']) assert.ok(!(f.endsWith('wa_inbound/index.ts') ? functionSource('wa_inbound') : src(f)).includes(LIC), f + ' still carries the licence number');
});

test('every WhatsApp send to a customer or supplier is guarded; only the founder reply is bidiSafe alone', () => {
  const s = functionSource('wa_inbound');
  assert.match(s, /function toContact\(s: string\): string \{\s*return bidiSafe\(guardSupportReply\(/);
  // bidiSafe( call sites outside its own definition and toContact: exactly the founder directive reply
  // and the founder branch of the menu send.
  const bare = s.split('\n').filter((l) => /bidiSafe\(/.test(l) && !/function bidiSafe|return bidiSafe\(guardSupportReply/.test(l));
  assert.equal(bare.length, 2, 'unguarded bidiSafe sites:\n' + bare.join('\n'));
  assert.ok(bare.every((l) => /founder|\? bidiSafe\(reply\.slice\(0, 1200\)\)/.test(l)), bare.join('\n'));
  assert.ok((s.match(/toContact\(/g) || []).length >= 6); // 6 since 12 Oct 2026 (rulings 1195-1197): the hold-only stored-sentence road is gone
});

test('a supplier\'s own licence number in an upload confirmation survives', () => {
  const t = 'Got it — your trade licence is on file (updated: licence no 705522).';
  assert.equal(guardSupportReply(t, 'en').text, t);
});

// RETIRED 12 Oct 2026 (rulings 1195/1196): 'an Arabic corpus answer is not closed with an English line'. Its subject,
// the widget's quoted-passage answer with a code-written closing line, was removed; the model writes every reply.
