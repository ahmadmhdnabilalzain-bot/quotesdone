// THE INBOX TRIAGE CLASSIFIES EACH MAIL ON ITS OWN, NEVER FROM THE CACHE (28 Oct 2026, it_engineer; supplier-journey
// audit, founder ledger 1401). Owner of the surface: customer_support (email_triage).
//
// email_triage's classification (category, summary, draft) ran through a binding whose task class caches for a day,
// and ai_gateway's semantic cache embeds only the first 400 characters of the system prompt and the first 800 of the
// conversation: for a reply to the invitation that is the fixed instructions, the From line, the subject and the quoted
// invitation, so every reply embeds alike. Measured 28 Oct: all 9 classifications in 14 days were semantic hits that ran
// no model, and "Yes", "How much does it cost?" and "Is this a scam?" were stored with ONE summary from an earlier mail.
// The category decides whether a mail is answered at all (spam is skipped), so this fails if the classification binding
// stops opting out of the cache. It reads the CODE of the makeLlm call (comments stripped), so a comment cannot pass it.
//   node --test scripts/checks/the_inbox_triage_classifies_each_mail_on_its_own.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const SRC = 'supabase/functions/email_triage/index.ts';

/** The source without // and /* *\/ comments (string contents kept). */
export function code(src) {
  let out = '', i = 0, q = null;
  while (i < src.length) {
    const c = src[i], n = src[i + 1];
    if (q) { out += c; if (c === '\\') { out += n ?? ''; i += 2; continue; } if (c === q) q = null; i++; continue; }
    if (c === '"' || c === "'" || c === '`') { q = c; out += c; i++; continue; }
    if (c === '/' && n === '/') { while (i < src.length && src[i] !== '\n') i++; continue; }
    if (c === '/' && n === '*') { i = src.indexOf('*/', i + 2); i = i < 0 ? src.length : i + 2; continue; }
    out += c; i++;
  }
  return out;
}

/** The problems with the classification binding, [] when it opts out of the cache. */
export function problems(src) {
  const c = code(src);
  const calls = [...c.matchAll(/\bconst\s+(\w+)\s*=\s*makeLlm\(\s*[^,)]*,\s*\{([^}]*)\}\s*\)/g)];
  if (!calls.length) return ['no makeLlm binding with an options object in email_triage'];
  // the binding the classification calls: llm(SYS, ...)
  const used = calls.filter(([, name]) => new RegExp(`\\b${name}\\(\\s*SYS\\b`).test(c));
  if (!used.length) return ['the classification (…(SYS, …)) does not call a makeLlm binding this check can read'];
  return used.filter(([, , opts]) => !/\bcacheTtlMin\s*:\s*0\b/.test(opts))
    .map(([, name]) => `${name} = makeLlm(…) classifies mail without cacheTtlMin: 0: a semantic cache hit replays another mail's category`);
}

test('the classification binding in email_triage opts out of the cache', () => {
  const p = problems(readFileSync(SRC, 'utf8'));
  assert.deepEqual(p, [], p.join('; '));
});

test('known-bad control: the binding before this fix is caught, and a comment cannot pass', () => {
  const before = "const llm = makeLlm(SONNET_FIRST, { max: 700 }); // cacheTtlMin: 0\nconst out = await llm(SYS, 'x', 800);";
  assert.equal(problems(before).length, 1);
  const fixed = "const llm = makeLlm(SONNET_FIRST, { max: 700, cacheTtlMin: 0 });\nconst out = await llm(SYS, 'x', 800);";
  assert.deepEqual(problems(fixed), []);
});
