// A REVISION THE MODEL COULD NOT WRITE IS ASKED AGAIN, AND A MONTH PLAN'S REVISION CHANGES THE PLAN (ceo, 27 Oct 2026).
//
// Measured 27 Oct 2026: every pending ceo.revise handoff (4 of 4) sat on a held question that failed on 13-17 Oct, and
// nothing asked again, so the CEO's decision cycle (founder ruling 1059) stopped; marketing.month_plan failed daily
// on "marketing owes the CEO a revision". And on the month-plan path a revision could only append a note: the CEO's
// round-2 rejection says the 12 ideas were word for word round 1.
// Fix: scripts/sql/a_revision_the_model_could_not_write_is_asked_again.sql
//
//   node --test scripts/checks/a_revision_the_model_could_not_write_is_asked_again.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { manifestWithPending, pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const FILE = 'scripts/sql/a_revision_the_model_could_not_write_is_asked_again.sql';

function canonicalBody(fn) {
  const re = new RegExp(`create or replace function public\\.${fn}\\(`, 'i');
  const owner = [...manifestWithPending()].reverse().find((f) => existsSync(join(ROOT, f)) && re.test(R(f)));
  assert.ok(owner, `no applied or pending file defines ${fn}`);
  return R(owner).slice(R(owner).search(re)).split('$fn$')[1] || '';
}

test('a failed revision question is asked again under a new key, and the CEO is owed the choice after three', () => {
  const refile = canonicalBody('fn_ceo_revision_refile');
  assert.match(refile, /h\.status not in \('failed', 'expired'\)/, 'the refile does not look for a failed or expired question');
  assert.match(refile, /interval '7 days'/, 'the refile does not wait out fn_reason_hold\'s 7-day window');
  assert.match(refile, /fn_ceo_decision_owe\(/, 'after the re-filings the CEO is not owed the choice');
  assert.doesNotMatch(refile, /fn_notify_founder|'founder'/, 'the refile addresses the founder');
  assert.match(canonicalBody('fn_seat_revises_for_the_ceo'), /':t' \|\| \(a\.evidence->>'refiles'\)/,
    'the revision question\'s dedupe key does not change on a re-filing, so fn_reason_hold returns the closed row');
});

test('a month-plan revision can replace the idea list the CEO reviews', () => {
  assert.match(canonicalBody('fn_seat_revises_for_the_ceo'), /'key', 'ideas'/, 'marketing is never asked for the revised list');
  const app = canonicalBody('fn_ceo_revision_applies');
  assert.match(app, /jsonb_set\(plan, '\{ideas\}', v_ideas\)/, 'a revision never reaches plan.ideas');
  assert.match(app, /UNREADABLE_IDEAS/, 'an unreadable list is not refused');
});

test('the refile runs on the CEO\'s clock', () => {
  assert.match(R(FILE), /\('ceo\.revision_refile', 'ceo', interval '1 day', 'fn_ceo_revision_refile'/);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

// Rolled back. Takes a pending marketing_month_plan ceo.revise handoff (production had 163352 on 27 Oct 2026), makes its
// question a failed one last tried 8 days ago, re-files, answers the re-filed question with a revised list, and reads
// the plan; then a list with a date outside the month must be refused. Nothing is sent: a held question is only a row.
const PROBE = `
do $p$
declare a public.agent_actions; v jsonb; q bigint; m date; ideas jsonb; ok_bad boolean := false; h text;
begin
  select * into a from public.agent_actions
   where kind = 'handoff' and status = 'pending' and detail->>'type' = 'ceo.revise' and detail->>'path' = 'marketing_month_plan'
     and not coalesce(evidence, '{}'::jsonb) ? 'resubmitted_at'
     and exists (select 1 from public.marketing_month_plan p where p.month = (detail->'version'->>'month')::date and p.status = 'ceo_reviewing')
   order by id desc limit 1;
  if a.id is null then raise exception 'CHK<<PROBE SKIP: no pending month-plan revision to rehearse on>>'; end if;
  m := (a.detail->'version'->>'month')::date;
  update public.reasoning_held_question set status = 'failed', last_attempt_at = now() - interval '8 days'
   where id = (a.evidence->>'held_id')::bigint;
  v := public.fn_ceo_revision_refile();
  select (evidence->>'held_id')::bigint into q from public.agent_actions where id = a.id;
  select status || '/' || surface || '/' || (request->'decision'->'fields' @> '[{"key":"ideas"}]')::text into h
    from public.reasoning_held_question where id = q;
  if q is null or q = (a.evidence->>'held_id')::bigint or h is distinct from 'held/marketing.ceo_revision/true' then
    raise exception 'CHK<<PROBE FAILED: not re-filed (refile=% new=% %)>>', v, q, h;
  end if;
  -- a list with a date outside the month is refused
  begin
    perform public.fn_ceo_revision_applies(q, jsonb_build_object('model', 'zz-probe', 'answer', 'Each of the CEO reasons is answered with the revised list below.',
      'decision', jsonb_build_object('choice', 'revised', 'fields', jsonb_build_object(
        'answers', jsonb_build_object('value', 'Every idea now targets suppliers and carries the corrected wording the CEO asked for.'),
        'ideas', jsonb_build_object('value', '[{"n":1,"date":"2099-01-05","title":"ZZ PROBE wrong month"}]')))));
  exception when check_violation then ok_bad := sqlerrm like 'UNREADABLE_IDEAS%';
  end;
  ideas := jsonb_build_array(jsonb_build_object('n', 1, 'date', to_char(m + 1, 'YYYY-MM-DD'), 'idea_key', 'zz-probe', 'title', 'ZZ PROBE revised idea',
                                                'hook', 'h', 'film_plan', 'f', 'cta', 'c', 'audience', 'supplier', 'why', 'rotation'));
  v := public.fn_ceo_revision_applies(q, jsonb_build_object('model', 'zz-probe', 'answer', 'Each of the CEO reasons is answered with the revised list below.',
    'decision', jsonb_build_object('choice', 'revised', 'fields', jsonb_build_object(
      'answers', jsonb_build_object('value', 'Every idea now targets suppliers and carries the corrected wording the CEO asked for.'),
      'ideas', jsonb_build_object('value', ideas::text)))));
  select plan->'ideas'->0->>'title' || '|' || jsonb_array_length(plan->'ideas') || '|' || (plan->'revisions'->-1->>'ideas_revised')
    into h from public.marketing_month_plan where month = m;
  raise exception 'CHK<<%>>', case when ok_bad and h = 'ZZ PROBE revised idea|1|true' and (v->>'applied')::boolean
    then 'PROBE OK refiled ' || a.id || ' as ' || q || '; revised list reached the plan; a wrong-month list was refused'
    else 'PROBE FAILED: bad_refused=' || ok_bad || ' plan=' || coalesce(h, 'null') || ' apply=' || coalesce(v::text, 'null') end;
end $p$;`;

test('production, rolled back: a failed revision is re-filed and its revised list reaches the plan', { skip: SKIP }, async (t) => {
  const pre = pendingNotes().has(FILE) ? R(FILE) + '\n' : '';
  let out = null;
  try { await replaySql(pre + PROBE, { retry: false }); } catch (e) {
    out = String(e.message || e).match(/CHK<<([\s\S]*)>>/)?.[1];
    assert.ok(out, 'the probe failed before it could report: ' + String(e.message || e).slice(0, 800));
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  if (out.startsWith('PROBE SKIP')) { t.skip(out); return; }
  assert.match(out, /^PROBE OK/, out);
});
