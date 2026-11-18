// A request sent while its drawing's sheets are still being checked says the pages follow, and gets them, with every
// supplier already sent it and the customer told (17 Nov 2026 evening, sales_engineer; ./drawing_pages_follow.ts).
// Offline, no model, no network. The statement the worker runs was also executed on a local Postgres 16 (hand-back).
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/_shared/drawing_pages_follow.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { CONCLUDED, FINISHED_PAGES_JOBS_SQL, PAGES_FOLLOW_LINE, STILL_FOLLOWING_SQL, followUpFinishedPages, PAGES_FOLLOW_MESSAGE, pagesArrivedMail, pagesAttachedForCustomer, pagesFollowFor, pagesReachTheirRequestsSql } from './drawing_pages_follow.ts';
import { attachedLine, newInquiryBody } from '../supplier_api/what_a_supplier_receives.ts';
import { hasArabic, toSuppliers } from './supplier_english.ts';

const JOB = { id: '11111111-1111-4111-8111-111111111111', customer_id: 'c0000000-0000-4000-8000-000000000001', source_path: "drawings/c1/1_ZZ DEMO set's.pdf" };

Deno.test('the request a supplier reads says the redacted drawing pages follow, only while no page is attached', () => {
  assertEquals(attachedLine('drawing', true, false, true), ' A draft bill of quantities from the customer’s drawing is attached.' + PAGES_FOLLOW_LINE);
  assertEquals(attachedLine('drawing', false, false, true), PAGES_FOLLOW_LINE);
  assertEquals(attachedLine('drawing', true, true, true), ' A redacted drawing with a draft bill of quantities is attached.', 'pages attached: nothing follows');
  assertEquals(attachedLine('drawing', false, false), '', 'no pages and none queued: nothing is promised');
  assertMatch(attachedLine('boq', true, false, true), /bill of quantities is attached[\s\S]*pages follow/);
  // The new-inquiry e-mail carries it, in English, with nothing of the customer in it.
  const mail = newInquiryBody({ resolved: true, buyer: { name: 'ZZ DEMO Buyer' }, spec: null, summary: 'HVAC works', budget: null, extra: attachedLine('drawing', true, false, true), category: 'hvac', emirate: 'Dubai', briefSource: 'drawing' });
  assertMatch(mail, /Redacted drawing pages follow: they are being checked and will be added to this request\./);
  assert(!/ZZ DEMO/.test(mail));
});

Deno.test('the e-mails when the pages arrive: the supplier\'s says the trade, the emirate and the page count, in English, and nobody\'s name; the customer\'s is in his language', () => {
  const m = pagesArrivedMail({ category: 'plumbing_sanitary', emirate: 'Dubai' }, 7);
  assertEquals(m.type, 'rfq_addendum');
  assertEquals(m.body, 'The redacted drawing for the plumbing sanitary job in Dubai you were invited to quote is now attached: 7 pages, with the customer\'s details removed. Log in to your QuotesDone supplier portal to see the drawing and quote.');
  assertEquals(toSuppliers([m]).length, 1, 'suppliers read English only: the row survives the Arabic filter');
  assertEquals(pagesArrivedMail({}, 1).body.includes('request job you were invited to quote is now attached: 1 page,'), true);
  const ar = pagesAttachedForCustomer('ar', 7), en = pagesAttachedForCustomer('en', 7);
  assert(hasArabic(ar.subject) && hasArabic(ar.body) && ar.lang === 'ar');
  assert(!hasArabic(en.body) && en.lang === 'en' && /7 pages/.test(en.body));
  assert(hasArabic(PAGES_FOLLOW_MESSAGE.ar) && !hasArabic(PAGES_FOLLOW_MESSAGE.en));
});

Deno.test('pagesReachTheirRequestsSql: only this customer\'s open requests with this drawing and no pages; matched, not declined, not banned suppliers; one delivery door; a dedupe key per request and recipient', () => {
  const sql = pagesReachTheirRequestsSql(JOB, ['redacted/a/page_p0.jpg', 'redacted/b/page_p0.jpg'])!;
  assert(sql);
  assertMatch(sql, /update public\.inquiries i set drawing_redacted_paths = array\[\$qd\$redacted\/a\/page_p0\.jpg\$qd\$, \$qd\$redacted\/b\/page_p0\.jpg\$qd\$\]::text\[\]/);
  assertMatch(sql, /where i\.customer_id = \$qd\$c0000000-0000-4000-8000-000000000001\$qd\$::uuid and i\.drawing_file_path = \$qd\$drawings\/c1\/1_ZZ DEMO set's\.pdf\$qd\$/);
  assertMatch(sql, /and coalesce\(cardinality\(i\.drawing_redacted_paths\), 0\) = 0/, 'a request that already has pages is never touched (a re-run attaches nothing)');
  for (const c of CONCLUDED) assert(sql.includes(`$qd$${c}$qd$`), `a ${c} request is not touched`);
  assertMatch(sql, /join public\.inquiry_matches m on m\.inquiry_id = a\.id and m\.declined_at is null/);
  assertMatch(sql, /join public\.leads l on l\.id = m\.supplier_id and coalesce\(l\.banned, false\) = false/);
  assertMatch(sql, /public\.fn_customer_support_takes_delivery\(\(select jsonb_agg\(r\) from rows\)\)/, 'the one delivery door: suppression, consent and sanctions apply');
  assert(!/insert into public\.notifications/i.test(sql), 'never the outbox table directly');
  assertMatch(sql, /'dedupe_key', \$qd\$drawing_pages_follow:11111111-1111-4111-8111-111111111111\$qd\$ \|\| ':' \|\| s\.inquiry_id \|\| ':' \|\| s\.lead_id/);
  assertMatch(sql, /'dedupe_key', \$qd\$drawing_pages_follow:11111111-1111-4111-8111-111111111111\$qd\$ \|\| ':customer'/);
  assertMatch(sql, /'to_role', 'supplier'[\s\S]*'lang', 'en'/);
  assertEquals(pagesReachTheirRequestsSql({ ...JOB, customer_id: null }, ['x']), null, 'no customer: nothing is attached');
  assertEquals(pagesReachTheirRequestsSql({ ...JOB, customer_id: "x' or 1=1" }, ['x']), null);
  assertEquals(pagesReachTheirRequestsSql(JOB, []), null);
  // A path with the quoting tag inside it cannot close the literal.
  const odd = pagesReachTheirRequestsSql({ ...JOB, source_path: 'drawings/c1/$qd$; drop table x; --.pdf' }, ['p'])!;
  assertMatch(odd, /\$qdx\$drawings\/c1\/\$qd\$; drop table x; --\.pdf\$qdx\$/);
});

Deno.test('pagesFollowFor: an open pages job of the request\'s own customer for the request\'s own drawing; nothing else, and nothing on a failed read', async () => {
  const rows = [
    { id: 'i1', customer_id: 'c1', drawing_file_path: 'drawings/c1/a.pdf' },
    { id: 'i2', customer_id: 'c2', drawing_file_path: 'drawings/c1/a.pdf' },   // another customer's request, same path string
    { id: 'i3', customer_id: 'c1', drawing_file_path: 'drawings/c1/b.pdf' },
    { id: 'i4', customer_id: 'c1', drawing_file_path: null },
  ];
  const asked: unknown[] = [];
  const db = (data: unknown, error: unknown = null) => ({ from: (t: string) => { asked.push(t); const q: any = { select: () => q, eq: (k: string, v: unknown) => { asked.push([k, v]); return q; }, in: (k: string, v: unknown) => { asked.push([k, v]); return q; }, then: (ok: (x: unknown) => unknown) => Promise.resolve({ data, error }).then(ok) }; return q; } });
  const got = await pagesFollowFor(db([{ customer_id: 'c1', source_path: 'drawings/c1/a.pdf' }]), rows);
  assertEquals([...got], ['i1']);
  assert(asked.some((a) => Array.isArray(a) && a[0] === 'why' && a[1] === 'pages_need_time'));
  assert(asked.some((a) => Array.isArray(a) && a[0] === 'status' && JSON.stringify(a[1]) === '["queued","running"]'));
  assertEquals([...await pagesFollowFor(db(null, { message: 'down' }), rows)], []);
  assertEquals([...await pagesFollowFor(db([]), [{ id: 'i4', customer_id: 'c1', drawing_file_path: null }])], []);
});

Deno.test('wired: create_inquiry, the supplier inbox and the portal say the pages follow; the worker attaches and tells', () => {
  const src = (p: string) => Deno.readTextFileSync(new URL(p, import.meta.url));
  const create = src('../customer_api/actions/inquiry_create.ts');
  assertMatch(create, /const follow = drawingPath && !rr\.paths\.length && briefSource === 'drawing' \? await pagesStillBeingChecked\(String\(cust\.id\), String\(user\.id \|\| ''\), drawingPath\)/);
  assertMatch(create, /const pagesFollow = !pagesRefused && !drawingRedacted && follow\.follows;/, 'pages refused for a priced source never "follow" either');
  assertEquals((create.match(/attachedLine\(briefSource, !!boqObj, !!drawingRedacted, pagesFollow\)/g) ?? []).length, 3, 'single, turnkey and every split part');
  assertMatch(create, /if \(drawingPath && !drawingRedacted && !pagesFollow && \(briefSource === 'drawing'/);
  assertEquals((create.match(/return J\(\{ \.\.\.followSaid, \.\.\.posted/g) ?? []).length, 3);
  const lib = src('../customer_api/lib/drawings.ts');
  assertMatch(lib, /export async function pagesStillBeingChecked[\s\S]{0,1400}resolveRedactedPaths\(custId, authUserId, \{ redaction_job_ids:/, 'a finished job\'s pages are resolved by ownership and completeness');
  const inbox = src('../supplier_api/actions/inbox.ts');
  assertMatch(inbox, /pagesFollow = await pagesFollowFor\(admin, owners \|\| \[\]\)/);
  assertMatch(inbox, /drawing_withheld: drawingWithheld\(hasOriginal\.has\(String\(i\.id\)\), dp\.expected\) && !\(pagesFollow\.has\(String\(i\.id\)\) && dp\.expected === 0\), drawing_pages_follow: pagesFollow\.has\(String\(i\.id\)\) && dp\.expected === 0,/);
  assertMatch(src('../supplier_api/quote_review_actions.ts'), /drawing_pages_follow: !!i\.drawing_pages_follow/);
  const copy = src('../../../src/components/portal/supplier/workspaceCopy.ts');
  assertEquals((copy.match(/rfq_pages_follow: '/g) ?? []).length, 2, 'English and Arabic');
  assertMatch(src('../../../src/components/portal/supplier/InquiriesTab.tsx'), /\{d\.drawing_pages_follow \? <p role="status"[^\n]*ws\(lang, 'rfq_pages_follow'\)/);
  const worker = src('../../../scripts/cad_read_worker.ts');
  assertMatch(worker, /if \(drawing\.redaction_complete === true\) \{\s*const stmt = pagesReachTheirRequestsSql\(job, /);
  assertMatch(worker, /catch \(e\) \{ throw new Error\('the verified pages could not be attached to the requests: '/, 'an attach that fails sends the job back to the queue, never lost');
});

Deno.test('every worker run: pages jobs finished in the last day are attached again (a request saved after its job finished gets them), and a request still without its pages 2 h on is raised', async () => {
  const ran: string[] = []; const raised: { key: string; evidence: Record<string, unknown> }[] = [];
  const J2 = { ...JOB, id: '22222222-2222-4222-8222-222222222222' };
  const sql = async (q: string) => {
    ran.push(q);
    if (q === FINISHED_PAGES_JOBS_SQL) return [{ id: JOB.id, customer_id: JOB.customer_id, source_path: JOB.source_path, paths: ['redacted/a/page_p0.jpg'] }, { id: J2.id, customer_id: J2.customer_id, source_path: 'drawings/c1/2.pdf', paths: ['redacted/b/page_p0.jpg'] }, { id: 'x', customer_id: null, source_path: 'p', paths: [] }];
    if (q === STILL_FOLLOWING_SQL) return [{ job_id: J2.id, status: 'done', why: '', inquiries: ['a0000000-0000-4000-8000-000000000009'] }];
    if (q.includes('drawings/c1/2.pdf')) throw new Error('statement timeout');
    return [{ attached: ['a0000000-0000-4000-8000-000000000007'], delivered: [{}, {}] }];
  };
  const out = await followUpFinishedPages({ sql, raise: async (key, _t, evidence) => { raised.push({ key, evidence }); } });
  assertEquals(out, { jobs: 2, attached: 1, failed: 1, still: 1 }, 'a job with no customer is skipped; one failed attach does not stop the rest');
  assertEquals(ran.filter((q) => q.startsWith('with att as')).length, 2, 'the same idempotent attach-and-tell statement, once per finished job');
  assertEquals(raised.map((r) => r.key), ['cad_read_worker:pages_never_followed:' + J2.id]);
  assertEquals(raised[0].evidence.inquiries, ['a0000000-0000-4000-8000-000000000009']);
  // the finding's read: only requests saved while the job was open or just after it finished, still without pages, still open
  assertMatch(FINISHED_PAGES_JOBS_SQL, /why = 'pages_need_time' and status = 'done' and result->>'redaction_complete' = 'true'\s+and finished_at > now\(\) - interval '24 hours'/);
  assertMatch(STILL_FOLLOWING_SQL, /j\.finished_at between now\(\) - interval '24 hours' and now\(\) - interval '2 hours'/);
  assertMatch(STILL_FOLLOWING_SQL, /i\.created_at >= j\.created_at and i\.created_at < j\.finished_at \+ interval '10 minutes'/);
  assertMatch(STILL_FOLLOWING_SQL, /coalesce\(cardinality\(i\.drawing_redacted_paths\), 0\) = 0/);
  assert(!/\b(update|insert|delete)\b/i.test(STILL_FOLLOWING_SQL), 'the finding read writes nothing');
  const worker = Deno.readTextFileSync(new URL('../../../scripts/cad_read_worker.ts', import.meta.url));
  const main = worker.slice(worker.indexOf('if (import.meta.main)'));
  assertMatch(main, /\n  \}\n  \/\/ EVERY RUN, claimed jobs or none[\s\S]*const f = await followUpFinishedPages\(\{/, 'outside the claimed-jobs branch: every run');
  assertMatch(worker, /redactQueuedPages\(q, \{ originalB64: b64u\(bytes\), raster, redact, progress, signal: stop\.signal \}\)/, 'the budget stops the asking');
  assertMatch(worker, /const budgetTimer = setTimeout\(\(\) => stop\.abort\(\), PAGES_JOB_MS\);/);
});
