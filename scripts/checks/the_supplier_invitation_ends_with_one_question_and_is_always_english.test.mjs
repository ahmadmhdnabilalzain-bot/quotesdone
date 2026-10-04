// THE SUPPLIER INVITATION ENDS WITH ONE QUESTION A SUPPLIER CAN ANSWER BY REPLYING, AND IS ALWAYS ENGLISH
// (24 Sep 2026, marketing, ledger 993).
//
// Measured on production that day: app_secrets.invite_body ended "We look forward to welcoming you." with
// nothing to answer, and fn_supplier_invite_candidates gave 116 of 6,863 eligible leads the Arabic invitation
// although ledger 993 says "invitations always in English". This check renders the invitation with
// send_outbox's own modules (render.ts, supplier_mail.ts, invitation_copy.ts) and reads the owning SQL file, and
// fails if:
//   - the rendered body (html and text) does not end with ONE question sentence, after the portal link and
//     before the signature, the footer and the unsubscribe line (which stays last);
//   - the word AI (whole word, any case) appears in the subject, body or preheader;
//   - the invitation can be anything but English: the selection returns a language other than 'en', or reads
//     the Arabic subject/body;
//   - send_outbox stops passing the invitation body through withReplyQuestion for both the html and the text part;
//   - the question in the SQL file and the one in code drift apart.
//   node --test scripts/checks/the_supplier_invitation_ends_with_one_question_and_is_always_english.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const ROOT = new URL('../../', import.meta.url);
const read = (p) => readFileSync(new URL(p, ROOT), 'utf8');
globalThis.Deno ??= { env: { get: () => '' } };
const OUTBOX = new URL('supabase/functions/send_outbox/', ROOT);
const { tmpl } = await import(new URL('render.ts', OUTBOX).href);
const { plainTextPart } = await import(new URL('supplier_mail.ts', OUTBOX).href);
const { INVITE_REPLY_QUESTION, withReplyQuestion, invitationCopyLint, endsWithOneQuestion } = await import(new URL('invitation_copy.ts', OUTBOX).href);

const SQL_FILE = 'scripts/sql/the_supplier_invitation_ends_with_one_question_and_is_always_english.sql';
const sql = read(SQL_FILE);
const outbox = read('supabase/functions/send_outbox/index.ts');
// Only code, not the header that explains what used to happen.
const sqlCode = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');

const LINK = 'https://quotesdone.com/en/portal?t=00000000-0000-0000-0000-000000000000';
const UNSUB = 'https://x.supabase.co/functions/v1/unsubscribe?e=a%40b.ae&t=abc';
const SUBJECT = 'Invitation: become a founding supplier on QuotesDone (free, no commission)';
const PRE = 'Free for the first 1,000 suppliers, permanently. No commission, ever. Register in minutes.';
// The closing of the live invite_body as read on 24 Sep 2026, the copy this change replaces.
const OLD = 'Dear ZZ DEMO Supplier,\n\nTo join, open your supplier portal here:\n\n' + LINK + '\n\nand complete a short company profile.\n\n'
  + 'We will never ask for payment or passwords by email. If you would prefer not to receive these invitations, use the unsubscribe link '
  + 'at the foot of this email and we will not write again.\n\nWe look forward to welcoming you.';
const WRAPPER = '<!doctype html><html><head></head><body>{{LOGO}}<div dir="auto">{{BODY}}</div><div>{{NAME}}</div>'
  + '<div>{{TITLE}}, QuotesDone</div><div>{{REPLY}}</div><div>QuotesDone Technologies &middot; Al Furjan, Dubai, UAE &middot; TDRA NOL-26-100000665{{UNSUB}}</div></body></html>';

// The stored body after the SQL applies: the old closing, a blank line, then the question the file appends.
const sqlQuestion = (sqlCode.match(/v_q constant text :=\s*'([^']+)'/) || [])[1];
const APPLIED = OLD + '\n\n' + sqlQuestion;

test('the SQL file and the code ask the same single question', () => {
  assert.ok(sqlQuestion, `${SQL_FILE} no longer declares the question (v_q)`);
  assert.equal(sqlQuestion, INVITE_REPLY_QUESTION, 'the stored question and the send-time fallback say different things');
  assert.ok(endsWithOneQuestion(APPLIED), `the stored body after ${SQL_FILE} does not end with one question`);
});

test('the old closing fails the rule: the check can tell', () => {
  assert.equal(endsWithOneQuestion(OLD), false);
});

for (const [name, stored] of [['the stored copy after the SQL applies', APPLIED], ['the old stored copy with the send-time fallback', OLD]]) {
  test(`${name}: renders ending with the question, after the link, before the footer and unsubscribe`, () => {
    const body = withReplyQuestion(stored);
    for (const r of invitationCopyLint({ lang: 'en', subject: SUBJECT, body, preheader: PRE, link: LINK })) assert.ok(r.ok, `${r.rule} -- ${r.detail}`);
    const html = tmpl({ body, logo: '', name: 'Ahmad Alzain', title: 'Founder', channelEmail: 'suppliers@mail.quotesdone.com', unsub: UNSUB,
      wrapper: WRAPPER, internal: false, preheader: PRE });
    const q = html.indexOf(INVITE_REPLY_QUESTION);
    assert.ok(q > 0, 'the question is not in the rendered html');
    assert.equal(html.indexOf(INVITE_REPLY_QUESTION), html.lastIndexOf(INVITE_REPLY_QUESTION), 'the question is rendered twice');
    assert.ok(html.indexOf(`<a href="${LINK}"`) < q, 'the question sits above the portal link');
    assert.ok(q < html.indexOf('<div>Ahmad Alzain</div>'), 'the question is below the signature');
    assert.ok(q < html.indexOf('Al Furjan, Dubai, UAE') && html.indexOf('Al Furjan, Dubai, UAE') < html.indexOf(`<a href="${UNSUB}"`),
      'the footer and then the unsubscribe line must follow the question, the unsubscribe last');
    // #953: Outlook drops pre-wrap, so the break before the question must be explicit.
    assert.ok(html.includes('<br><br>' + INVITE_REPLY_QUESTION + '</div>'), 'the question is not its own paragraph in Outlook');
    const text = plainTextPart({ body, unsub: UNSUB, ar: false, internal: false });
    assert.ok(text.includes(INVITE_REPLY_QUESTION + '\n\n--\n\n'), 'text part: the question is not the last line of the body');
    assert.match(text.trimEnd(), /to be removed\.$/, 'text part: the unsubscribe line is no longer last');
  });
}

test('never the word AI in the invitation copy (the founder: say "smart")', () => {
  assert.doesNotMatch(INVITE_REPLY_QUESTION, /\bai\b/i);
  const body = withReplyQuestion(OLD);
  assert.equal(invitationCopyLint({ lang: 'en', subject: 'Our AI matches you', body, preheader: PRE, link: LINK })[1].ok, false);
  assert.equal(invitationCopyLint({ lang: 'en', subject: SUBJECT, body: body + ' ai', preheader: PRE, link: LINK })[1].ok, false);
  assert.equal(invitationCopyLint({ lang: 'en', subject: SUBJECT, body, preheader: 'Smart matching. Ai.', link: LINK })[1].ok, false);
  assert.equal(invitationCopyLint({ lang: 'en', subject: 'Maintain, repair, retain', body, preheader: PRE, link: LINK })[1].ok, true);
  // The SQL's verdict row checks the stored subject, body and preheader the same way.
  assert.match(sqlCode, /~\* '\\mAI\\M'/, 'the verdict row stopped checking the stored copy for the word');
});

test('the invitation is English only: the selection never chooses or reads the Arabic copy', () => {
  const fn = sqlCode.slice(sqlCode.indexOf('create or replace function public.fn_supplier_invite_candidates'));
  assert.ok(fn.length > 100, 'fn_supplier_invite_candidates is no longer defined in the owning file');
  assert.match(fn, /'en'::text as lang/, 'the selection no longer fixes the language to English');
  assert.doesNotMatch(fn, /invite_body_ar|invite_subject_ar|then 'ar'/, 'the selection reads or chooses the Arabic invitation again');
  assert.match(fn, /'\/en\/portal\?t='/, 'the portal link is not the English one');
  assert.match(sqlCode, /not_en > 0 then 'PROBE FAILED/, 'the verdict row stopped checking that every candidate is English');
  assert.equal(invitationCopyLint({ lang: 'ar', subject: SUBJECT, body: withReplyQuestion(OLD), preheader: PRE, link: LINK })[0].ok, false);
});

test('the SQL verdict cannot pass on a missing field and applies the one-sentence rule (review of #964)', () => {
  const verdict = sqlCode.slice(sqlCode.indexOf('with s as ('));
  assert.match(verdict, /coalesce\(s\.subj, ''\)/, 'a NULL subject would make the AI/Arabic test NULL and the verdict PROBE OK');
  assert.match(verdict, /invite_subject is missing/);
  assert.match(verdict, /invite_body is missing/);
  assert.match(verdict, /'\[\.!\]\\s\+\\S'/, 'the verdict only counts question marks, not sentences');
  assert.match(verdict, /e\\\.g\|i\\\.e\|etc\|co\|l\\\.l\\\.c/, 'the verdict treats an abbreviation as a sentence break');
  assert.doesNotMatch(verdict, /when \(last\.subj \|\|/, 'the uncoalesced concatenation is back');
});

test('a closing question with an abbreviation is one sentence, and is not given a second question', () => {
  const q = 'Which trades do you cover, e.g. MEP, joinery or L.L.C. fit-out works?';
  assert.ok(endsWithOneQuestion('x\n\n' + q));
  assert.equal(withReplyQuestion('x\n\n' + q), 'x\n\n' + q);
  assert.equal(endsWithOneQuestion('x\n\nThanks. Which trades do you cover?'), false);
});

test('an invitation queued in Arabic is held before it is rendered, never sent', () => {
  const hold = outbox.indexOf('if (holdArabicInvitation(n.type, n.lang, supplierSide))');
  assert.ok(hold > 0, 'send_outbox no longer holds a supplier invitation queued in Arabic');
  assert.ok(hold < outbox.indexOf('const htmlBody0 = tmpl('), 'the Arabic hold must run before the mail is rendered');
  assert.match(outbox.slice(hold, hold + 400), /status: 'held'/);
});

test('the inbox check refuses Arabic candidate copy and renders no Arabic variant', () => {
  const chk = read('scripts/invitation_inbox_check.mjs');
  assert.match(chk, /ARABIC_SCRIPT\.test\(readOpt\(k\) \?\? ''\)/, '--subject-file/--body-file accept Arabic script again');
  assert.doesNotMatch(chk, /arabicFrame|invite_body_ar|invite_subject_ar/, 'the inbox check renders an Arabic invitation again');
});

test('send_outbox renders both parts of an English invitation through withReplyQuestion', () => {
  assert.match(outbox, /import \{[^}]*\bwithReplyQuestion\b[^}]*\} from '\.\/invitation_copy\.ts'/);
  assert.match(outbox, /const inviteEn = String\(n\.type \|\| ''\)\.startsWith\('supplier_invite'\) && !arMail;/);
  assert.match(outbox, /const mailBody = inviteEn \? withReplyQuestion\(n\.body \|\| ''\) : \(n\.body \|\| ''\);/);
  assert.match(outbox, /tmpl\(\{ body: mailBody,/, 'the html part no longer renders the body with the question');
  assert.match(outbox, /plainTextPart\(\{ body: mailBody,/, 'the text part no longer carries the question');
});
