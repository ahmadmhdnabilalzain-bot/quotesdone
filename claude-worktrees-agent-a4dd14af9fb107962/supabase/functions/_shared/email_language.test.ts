// email_language.test.ts — the code emails and the Arabic outbox frame speak one language each.
// deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/email_language.test.ts
// Founder, 14 Sep 2026 (founder_instruction #193): the registered language follows every message.
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { codeEmail } from './code_email.ts';
import { arabicFrame } from '../send_outbox/arabic_frame.ts';

// Visible text only; the brand name, URLs and the code itself are not prose.
const prose = (html: string) => html.replace(/<[^>]+>/g, ' ').replace(/QuotesDone/g, ' ').replace(/[\w.+-]+@[\w.-]+/g, ' ').replace(/[\w.+-]+@[\w.-]+/g, ' ').replace(/https?:\/\/\S+/g, ' ').replace(/\d+/g, ' ');
const hasArabic = (s: string) => /[؀-ۿ]/.test(s);
const englishWords = (s: string) => s.match(/[A-Za-z]{2,}/g) || [];

for (const purpose of ['signin', 'confirm'] as const) {
  Deno.test(`${purpose} code email in Arabic carries no English`, () => {
    const e = codeEmail(purpose, '482913', true);
    assertStringIncludes(e.html, '482913');
    assertStringIncludes(e.html, 'dir="rtl"');
    assert(hasArabic(e.subject) && hasArabic(prose(e.html)));
    assertEquals(englishWords(prose(e.subject + ' ' + e.html)), []);
  });
  Deno.test(`${purpose} code email in English carries no Arabic`, () => {
    const e = codeEmail(purpose, '482913', false);
    assertStringIncludes(e.html, '482913');
    assert(!hasArabic(e.subject + e.html));
  });
}

Deno.test('the outbox frame of an Arabic email is Arabic and right-to-left', () => {
  const unsub = 'https://example.invalid/unsubscribe?e=x';
  const english = `<!doctype html><html><head></head><body><div>مرحبًا</div>`
    + `<div>QuotesDone &middot; Dubai, UAE &middot; Dubai DET E-Trader Licence 1633275<br><a href="${unsub}" style="color:#9ca3af">Unsubscribe</a> &middot; or email unsubscribe@mail.quotesdone.com to be removed.</div>`
    + `<div>You're receiving this because your business is publicly listed and may match clients sourcing on QuotesDone.</div></body></html>`;
  const out = arabicFrame(english);
  assertStringIncludes(out, '<html dir="rtl" lang="ar">');
  assertStringIncludes(out, unsub);
  assertEquals(englishWords(prose(out.replace(/&middot;/g, ' ').replace(/<!doctype html>/i, ''))), []);
});
