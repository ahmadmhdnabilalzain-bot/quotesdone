// deno test supabase/functions/supplier_api/an_arabic_only_licence_goes_to_a_person.test.ts
// REVIEW OF #1987, S7 (12 Nov 2026): a licence that prints its company name in Arabic only left the company unnamed and was held
// "licence_unreadable", and he was asked for "a clearer copy", which cannot help. It goes to a person; he is told so and not stopped.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import { functionSource } from '../../../scripts/lib/function_sources.mjs';
import { ARABIC_ONLY_NOTE, ARABIC_ONLY_ROW, arabicOnlyName, holdArabicOnlyNameForPerson } from '../_shared/licence_name_for_person.ts';

const AR = 'شركة زد ديمو للتجارة';   // a made-up Arabic company name

Deno.test('an Arabic-only name is taken as the legal name the model read; an English name stays the reading', () => {
  assertEquals(arabicOnlyName({ legal_name_en: null }, { legal_name_ar: AR }), AR);
  assertEquals(arabicOnlyName({ legal_name_en: 'ZZ DEMO Trading LLC' }, { legal_name_ar: AR }), null);
  assertEquals(arabicOnlyName({ legal_name_en: null }, { legal_name_ar: '' }), null);
  assertEquals(arabicOnlyName({ legal_name_en: null }, { legal_name_ar: 'ZZ' }), null, 'no Arabic letters, no Arabic name');
});

Deno.test('the sentence is truthful, asks nothing and never says "clearer copy"; the row is held as ours and never re-read', () => {
  assertMatch(ARABIC_ONLY_NOTE, /A person at QuotesDone will confirm your company name/);
  assertMatch(ARABIC_ONLY_NOTE, /you can submit/);
  assert(!/clearer|upload|copy/i.test(ARABIC_ONLY_NOTE));
  assertEquals(ARABIC_ONLY_ROW, { licence_read_state: 'ours_failed', licence_read_tries: 8 });
});

Deno.test('a person is asked once per file: the review row, the ceo task and the once-mark', async () => {
  const rows: Record<string, unknown>[] = []; const rpcs: string[] = [];
  const admin = {
    from: (_t: string) => ({
      select: () => ({ eq: () => ({ eq: () => ({ eq: () => ({ limit: () => Promise.resolve({ data: rows.filter((r) => r.kind === 'licence_name_for_person'), error: null }) }) }) }) }),
      insert: (r: Record<string, unknown>) => { rows.push(r); return Promise.resolve({ error: null }); },
    }),
    rpc: (n: string) => { rpcs.push(n); return Promise.resolve({ data: null, error: null }); },
  };
  await holdArabicOnlyNameForPerson(admin, 990017, 'test', 'licenses/990017/a.pdf', AR, { licence_no: 'ZZ-1' });
  await holdArabicOnlyNameForPerson(admin, 990017, 'test', 'licenses/990017/a.pdf', AR, { licence_no: 'ZZ-1' });
  assertEquals(rows.map((r) => r.kind), ['licence_name_for_person', 'held_registration_for_ceo']);
  assertEquals(rows[0].status, 'needs_review');
  assertEquals(rpcs, ['fn_ceo_task_open']);
});

Deno.test('process_docs routes it, shows the Arabic name back, and never for an approved supplier keeping his reading', () => {
  const src = functionSource('supplier_api');
  assertMatch(src, /arabicName = keepAccepted \? null : arabicOnlyName\(r\.merged, jd\.doc\);/);
  assertMatch(src, /if \(arabicName\) \{ \(mOut\.license as Record<string, unknown>\)\.legal_name = arabicName; mOut\.licence_name_note = ARABIC_ONLY_NOTE; \}/);
  assertMatch(src, /Object\.assign\(mUpd, ARABIC_ONLY_ROW\);/);
  assertMatch(src, /'licence_wrong_document', 'licence_name_note'\]\) if \(v\[k\] !== undefined\) out\[k\] = v\[k\];/);
});
