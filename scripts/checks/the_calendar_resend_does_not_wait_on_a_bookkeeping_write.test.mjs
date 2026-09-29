// THE CALENDAR RE-SEND DOES NOT WAIT ON A BOOKKEEPING WRITE.
//
// 28 Sep 2026: fn_marketing_calendar_due waited 30 minutes after marketing_post.updated_at, and every dry run
// of a held post writes updated_at, so while a post was held the calendar email that would release it never
// went out by itself (the 14:02 UTC beat sent nothing and logged nothing). The quiet period now reads
// marketing_post.content_edited_at, which only the trigger moves, and only for a column the calendar hash reads.
//
// Reads supabase/schema/full_schema/ (the live mirror). Fails if the decision reads the post's generic
// write clock again, if the trigger is gone, or if the decision stops logging.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const SCHEMA = readSchemaMirror();

function body(name) {
  const re = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\([^)]*\\)[\\s\\S]*?\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`, 'i');
  const m = SCHEMA.match(re);
  assert.ok(m, `${name} is not in the schema mirror`);
  return m[2].replace(/--[^\n]*/g, '');
}

test('the re-send decision waits on content edits, not on marketing_post.updated_at', () => {
  const b = body('fn_marketing_calendar_resend_decide');
  assert.match(b, /max\(p\.content_edited_at\)/);
  assert.doesNotMatch(b, /max\(p\.updated_at\)/, 'a dry run writes marketing_post.updated_at; the wait must not read it');
  assert.match(b, /insert into public\.marketing_calendar_resend_decision/i, 'each decision change is logged');
});

test('the due list goes through the logged decision', () => {
  assert.match(body('fn_marketing_calendar_due'), /fn_marketing_calendar_resend_decide\(/);
});

test('only the trigger moves content_edited_at, and dry_run is not one of its columns', () => {
  const b = body('fn_marketing_post_content_edited_at');
  assert.doesNotMatch(b, /dry_run|updated_at|attempts|postiz_result/);
  assert.match(SCHEMA, /CREATE TRIGGER z95_marketing_post_content_edited_at BEFORE INSERT OR UPDATE ON public\.marketing_post/i);
});
