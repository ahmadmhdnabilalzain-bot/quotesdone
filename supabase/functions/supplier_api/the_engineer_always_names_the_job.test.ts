// THE ENGINEER ALWAYS NAMES THE JOB (11 Nov 2026, sales_engineer).
// MEASURED, nightly run 077cbbfc (10 Nov 2026): the quotation chat's opening message named no job number on en-desktop
// (job 164941) and en-mobile (job 164942). The greeting FACTS carry it ("... the QuotesDone sales engineer for Job N ...",
// said.ts greeting); the model rewrites them (rulings 1195-1197) and was only asked, in its rules, to keep job numbers.
// aiReply has a check for exactly this (`must`: a draft that leaves it out is rewritten with the omission named), and the
// chat's voice never passed it. It now passes the job of every code-decided message.
// Run: deno test --no-check --allow-read supabase/functions/supplier_api/the_engineer_always_names_the_job.test.ts
import { assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { awaitingUploadSaid, choiceSaid, greeting, jobsIn, readyToSubmitSaid, reviewSaid } from './quote_review.ts';

Deno.test('the job number is read from every fact code writes about a job, and nothing else', () => {
  assertEquals(jobsIn(greeting('164941').en), ['164941']);
  assertEquals(jobsIn(readyToSubmitSaid('D958E1EA').en), ['D958E1EA']);
  assertEquals(jobsIn(reviewSaid('164942', { approved: false, issues: [{ code: 'validity', kind: 'missing', line_no: null, boq_line: null, attr: null, en: 'Validity', ar: 'الصلاحية' }], price_ex_vat: null, boq_lines: 0, matched: 0 } as never).en), ['164942']);
  assertEquals(jobsIn(choiceSaid().en), []);
  assertEquals(jobsIn(awaitingUploadSaid().en), []);
  assertEquals(jobsIn('Job 12'), []);   // not a job number: too short to be one
});

Deno.test('the quotation chat requires it of the model in every code-decided message', async () => {
  const src = await Deno.readTextFile(new URL('./actions/quote_review_chat.ts', import.meta.url));
  assertMatch(src, /must: v\.kind === 'text' \? \[\] : jobsIn\(v\.situation\)/);
  // and aiReply refuses a draft that leaves a `must` text out (its own test: _shared/ai_reply.test.ts '1339: must-carry text')
  const ai = await Deno.readTextFile(new URL('../_shared/ai_reply.ts', import.meta.url));
  assertMatch(ai, /must\.filter\(\(m\) => !t\.includes\(m\)\)/);
});
