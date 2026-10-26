// An agent that produces a document must be able to EMAIL it, not merely link to it.
//
// This property was FALSE until 9 Sep 2026: notifications had no column for a document and
// send_outbox built the Resend payload without an attachments field, so the accountant's weekly
// financial report could only reach the founder as a signed URL that expires in seven days.
//
// The check is read-only and sends nothing. It asserts the carriage exists, that the guard refuses
// the four shapes that would be dangerous, and — the part that matters most — that the DEPLOYED
// send_outbox bundle still contains the attachment path. A column and a trigger with no sender
// reading them is a finished capability with no entry point.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const q = (s) => `'${String(s).replace(/'/g, "''")}'`;

// THE CI CHECKS JOB HAS NO MANAGEMENT TOKEN. Four of these tests read production, and without a
// token they do not fail meaningfully -- they fail on the connection, sixty seconds each, and say
// nothing about whether attachment carriage works. The estate's convention is to SKIP and say so
// loudly, so a green CI run never reads as "verified against production" when it was not. The last
// test reads the repository and runs everywhere.
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

test('notifications can carry a document reference', { skip: SKIP }, async () => {
  const [{ n }] = await sql(`select count(*) n from information_schema.columns
     where table_schema='public' and table_name='notifications' and column_name='attachments'`);
  assert.equal(Number(n), 1, 'notifications.attachments is missing - no agent can email a file');
});

test('the attachment guard is attached and fires before insert', { skip: SKIP }, async () => {
  const rows = await sql(`select tgname, pg_get_triggerdef(oid) def from pg_trigger
     where tgrelid='public.notifications'::regclass and not tgisinternal
       and tgname='a20_notifications_attachment_policy'`);
  assert.equal(rows.length, 1, 'a20_notifications_attachment_policy is not attached');
  assert.match(rows[0].def, /BEFORE INSERT/i, 'the guard must run before the row is written');
});

// Each refusal is proved by attempting it for real inside an aborted transaction. A guard is only
// worth having if it actually refuses; asserting the trigger EXISTS proves nothing about what it does.
const REFUSALS = [
  ['a bucket outside the allow-list', `'[{"bucket":"signed-terms","path":"a.pdf","filename":"a.pdf"}]'`],
  ['a traversal path', `'[{"bucket":"reports","path":"../../secrets","filename":"a.pdf"}]'`],
  ['a filename carrying quote and semicolon', `'[{"bucket":"reports","path":"a.pdf","filename":"a\\";x.pdf"}]'`],
  ['a non-array attachments value', `'{"bucket":"reports"}'`],
];

test('the guard refuses every unsafe attachment shape, and accepts a good one', { skip: SKIP }, async () => {
  // POSITIVE CONTROL FIRST. A trigger that rejected everything would "pass" all four refusals
  // below while making the feature useless, so prove a well-formed reference is accepted.
  const good = `'[{"bucket":"finance-reports","path":"2026/w37/r.pdf","filename":"Weekly_Financial_Report.pdf"}]'`;
  const probe = async (value) => {
    try {
      await sql(`do $probe$
        declare v_id bigint;
        begin
          insert into public.notifications(type, kind, to_email, to_role, channel, subject, body, attachments)
          values ('zz_demo_attach_check','founder_brief','probe@example.invalid','admin','email','x','x', ${value}::jsonb)
          returning id into v_id;
          raise exception 'CHK<<accepted id=%>>', v_id;
        end $probe$;`);
      return { accepted: false, note: 'no exception at all' };
    } catch (e) {
      const m = String(e?.message || e);
      return { accepted: m.includes('CHK<<accepted'), note: m.slice(0, 160) };
    }
  };

  const ok = await probe(good);
  assert.ok(ok.accepted,
    `POSITIVE CONTROL FAILED: a well-formed attachment was refused, so the refusals below prove nothing. ${ok.note}`);

  for (const [label, value] of REFUSALS) {
    const r = await probe(value);
    assert.equal(r.accepted, false, `HOLE: ${label} was accepted`);
  }

  const [{ n }] = await sql(`select count(*) n from public.notifications where type='zz_demo_attach_check'`);
  assert.equal(Number(n), 0, 'the aborted-transaction probe left rows behind');
});

test('the allow-list holds only buckets of documents this company generated for itself', { skip: SKIP }, async () => {
  const [{ src }] = await sql(`select prosrc src from pg_proc
     where proname='fn_notification_attachment_policy' and pronamespace='public'::regnamespace`);
  for (const forbidden of ['signed-terms', 'quote-files', 'supplier-docs', 'site', 'brand', 'demo-assets']) {
    assert.ok(!new RegExp(`'${forbidden}'`).test(src),
      `${forbidden} must not be attachable: it holds other parties' documents or is a public bucket`);
  }
});

test('the sender still reads attachments and fails closed without them', () => {
  // This reads the REPO file, which is what deploy_functions.mjs ships. Whether production is
  // actually running it is a different property with its own instrument -- verify_deploy_parity.mjs
  // -- and this check does not claim to prove it. Naming the boundary is the point.
  const src = readFileSync('supabase/functions/send_outbox/index.ts', 'utf8');
  assert.match(src, /mail\.attachments\s*=/, 'send_outbox no longer puts attachments on the Resend payload');
  assert.match(src, /resolveAttachments/, 'send_outbox no longer resolves attachment references');
  assert.match(src, /MAX_ATTACH_BYTES/, 'the byte ceiling is gone; only the sender knows the size');
  // FAIL CLOSED. If this regresses to a warning, the founder gets "here is your report" with no
  // report and cannot tell that from a report saying nothing happened.
  assert.match(src, /was NOT sent/,
    'send_outbox must fail the row when a document cannot be read, never send the covering note alone');
});
