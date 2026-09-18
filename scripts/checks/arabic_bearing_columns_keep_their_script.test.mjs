// AN ARABIC QUESTION THAT ARRIVES AS QUESTION MARKS IS A CUSTOMER WE CANNOT SERVE.
//
// On 9 Sep 2026 at 20:42 UTC a question reached org_tasks 578945 and sales_knowledge_gap 14 as
// '?? ????? ????? ?????? ???????? ????? ?????? ?? ???' — every Arabic letter replaced by 0x3F. It
// sat in the work queue for nine days, asked four times, unreadable and therefore unanswerable.
//
// WHERE IT WAS LOST, traced rather than guessed. assistant_logs records the message as it arrived
// together with the user agent, and the split is exact:
//
//   ids 141-144, user_agent 'curl/8.21.0'  -> the destroyed string
//   ids 145-149, user_agent 'node'         -> intact Arabic, same endpoint, 13 minutes later
//
// Same widget, same edge function, same RPC, same table. The loss was a client-side encode: a
// curl.exe invocation from a Windows shell whose JSON body went out in the console/ANSI codepage
// instead of UTF-8, so the codepoints were already 0x3F before the request left the machine.
// Nothing in the estate can un-corrupt that, so fn_text_lost_its_script names the fingerprint and
// fn_support_knowledge_gap and fn_sales_assist refuse to file a question that carries it.
//
// THIS CHECK IS THE BACKSTOP FOR THE WRITER NOBODY HAS WRITTEN YET. Those two refusals cover the
// two paths that exist today. A third path added later, wired straight to a table, would reopen
// the defect silently. This fails instead.
//
// WHAT IT COVERS, exactly, so a green run is not read as a claim about the whole database. The
// columns below are the ANSWER-BEARING ones: text a person wrote or a person will read, where
// stripped script means the company cannot serve someone.
//
// WHAT IT DELIBERATELY DOES NOT COVER, said out loud rather than quietly omitted:
//
//   * assistant_logs. That is the ARRIVAL record. A corrupted arrival is a true record of a
//     corrupted arrival, and it is the only evidence naming the failing client — rewriting it to
//     make this check green would delete the trace of the defect. Its four historical rows are
//     left exactly as they are.
//   * kb_chunks (2.6m rows) and the other bulk corpora, which are imported reference material
//     rather than text anyone typed at us, and cannot be scanned inside the statement timeout.
//
// The list is asserted non-empty and every column in it is asserted to exist, so a rename that
// quietly empties this check fails it rather than passing over nothing.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

// table, id column, and the columns that carry text a person wrote or will read.
const COVERED = [
  ['sales_knowledge_gap', 'id', ['question']],
  ['org_tasks', 'id', ['title', 'detail']],
  ['company_faq', 'id', ['question', 'answer']],
  ['support_knowledge', 'record_id', ['title', 'body']],
  ['sales_knowledge', 'record_id', ['title', 'content']],
];

// The fingerprint, spelled in SQL exactly as fn_text_lost_its_script spells it. It is written out
// here rather than calling the function on purpose: if someone loosens the function until it stops
// detecting anything, this check still bites and the two disagree loudly.
//
// Described rather than quoted where the comment would otherwise match itself: no surviving
// character above the ASCII range, and either the whole field made of question-mark runs (two or
// more runs, at 30% or more of the non-whitespace characters) or a destroyed sentence embedded in
// a readable one (three or more runs of four or more). The second arm exists because this check
// found what the first arm missed: org_tasks 578945's title tripped it and its detail, which
// carries the same destroyed sentence inside two paragraphs of English, did not.
const fingerprint = (col) => `(
     ${col} !~ '[^\\x00-\\x7F]'
 and (
       (    (select count(*) from regexp_matches(${col}, '[?][?]+', 'g')) >= 2
        and length(regexp_replace(${col}, '[^?]', '', 'g'))::numeric
              >= 0.30 * greatest(length(regexp_replace(${col}, '\\s', '', 'g')), 1))
    or (select count(*) from regexp_matches(${col}, '[?]{4,}', 'g')) >= 3
     ))`;

test('the covered list names real columns and is not empty', { skip: SKIP }, async () => {
  assert.ok(COVERED.length > 0, 'nothing is covered — this check would pass over an empty set');
  const wanted = COVERED.flatMap(([t, id, cols]) => [...cols, id].map((c) => `('${t}','${c}')`)).join(',');
  const rows = await sql(`
    with wanted(t, c) as (values ${wanted})
    select w.t, w.c from wanted w
     where not exists (select 1 from information_schema.columns ic
                        where ic.table_schema = 'public' and ic.table_name = w.t and ic.column_name = w.c)`);
  assert.equal(rows.length, 0,
    'a covered column does not exist, so this check is scanning less than it claims: '
    + rows.map((r) => `${r.t}.${r.c}`).join(', '));
});

test('no answer-bearing column holds text with its script stripped', { skip: SKIP }, async () => {
  const parts = COVERED.flatMap(([t, id, cols]) => cols.map((c) => `
    select '${t}.${c}'::text as where_, ${id}::text as row_id, left(${c}, 120) as sample
      from public.${t} where ${c} is not null and ${fingerprint(c)}`));
  const rows = await sql(parts.join('\n union all ') + '\n order by 1, 2');
  assert.equal(rows.length, 0,
    'text reached a column with its non-ASCII stripped — a question nobody can read and nobody can '
    + 'answer. Find the client that sent it; the estate stores what it is handed. Rows: '
    + rows.map((r) => `${r.where_} #${r.row_id} = ${JSON.stringify(r.sample)}`).join(' | '));
});

test('the guard that refuses such text is deployed and closed to anon', { skip: SKIP }, async () => {
  const rows = await sql(`
    select p.oid::regprocedure::text as sig,
           has_function_privilege('anon', p.oid, 'execute') as anon_can,
           public.fn_text_lost_its_script('?? ????? ????? ?????? ???????? ????? ?????? ?? ???') as detects,
           public.fn_text_lost_its_script(
             'Someone who was NOT signed in asked this on the website_widget and Customer Support '
             || 'could not source an answer from company knowledge. QUESTION: '
             || '?? ????? ????? ?????? ???????? ????? ?????? ?? ??? REFUSAL: circuit_open') as detects_embedded,
           public.fn_text_lost_its_script('كم تكلفة السقف الجبسي المستعار للمتر المربع في دبي') as false_positive,
           public.fn_text_lost_its_script('what documents does a supplier need for verification?') as false_positive_en
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'fn_text_lost_its_script'`);
  assert.equal(rows.length, 1, 'fn_text_lost_its_script is not deployed, so nothing refuses a stripped question');
  assert.equal(rows[0].detects, true, 'the guard no longer detects the string it was written for');
  assert.equal(rows[0].detects_embedded, true,
    'the guard no longer detects a destroyed sentence embedded in an otherwise readable field');
  assert.equal(rows[0].false_positive, false, 'the guard now flags intact Arabic, which would refuse real customers');
  assert.equal(rows[0].false_positive_en, false, 'the guard now flags an ordinary English question');
  assert.equal(rows[0].anon_can, false, 'anon can execute fn_text_lost_its_script');
});

// A definition with its line comments removed. pg_get_functiondef returns the body verbatim,
// comments and all, so matching a name against the raw definition is the house trap — a check that
// greps for a string will match the comment that EXPLAINS the string, and both routines below
// carry prose naming the guard right next to the call. Strip the comments first and the match is
// against code. (Line comments only: neither routine uses block comments, and a naive block-comment
// strip would eat the dollar-quoted body.)
const codeOf = (proname) =>
  `regexp_replace(pg_get_functiondef(p.oid), '--[^\\n]*', '', 'g')`;

test('both routines that keep a visitor question consult the guard', { skip: SKIP }, async () => {
  // A guard nothing calls is not a guard. Read it out of the deployed bodies, not out of the repo.
  const rows = await sql(`
    select p.proname,
           ${codeOf()} like '%fn_text_lost_its_script(%' as consults
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('fn_sales_assist', 'fn_support_knowledge_gap')
     order by 1`);
  assert.equal(rows.length, 2, 'one of the two question-keeping routines is missing from the database');
  for (const r of rows) {
    assert.equal(r.consults, true, `${r.proname} does not consult fn_text_lost_its_script`);
  }
});

test('the Sales Engineer can see the FAQ the company publishes', { skip: SKIP }, async () => {
  // The other half of the same change, and the reason it is asserted here: the estate wrote the
  // answers to two recorded knowledge gaps into company_faq and fn_sales_assist did not read that
  // table, so a gap closed for the support seat stayed open for the sales seat.
  const rows = await sql(`
    select ${codeOf()} like '%from company_faq f%' as reads_faq,
           ${codeOf()} like '%company_faq%' as mentions_faq
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'fn_sales_assist'`);
  assert.equal(rows.length, 1, 'fn_sales_assist is not deployed');
  assert.equal(rows[0].reads_faq, true,
    'fn_sales_assist does not read company_faq — the corpus the company writes its answers into');
  assert.equal(rows[0].mentions_faq, true,
    'fn_sales_assist no longer names company_faq in the corpus list it reports to its caller');
});

// THE CEILING OF ALL OF THIS, stated so a green run is not read as more than it is. The fingerprint
// requires that NOTHING non-ASCII survived. A message that lost its Arabic but kept one non-ASCII
// character — a curly quote, an emoji, a degree sign, a pasted em dash — escapes both the guard at
// the trust boundary and this backstop. Nothing observed produces that shape: the codepage
// conversion takes every non-ASCII character or none. If one ever is observed, the fingerprint is
// what changes, and this comment is the record of why it was drawn where it was.
