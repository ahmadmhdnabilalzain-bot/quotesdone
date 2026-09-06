// THE DESIGNER WAS THE DEFAULT REVIEWER OF ITS OWN ARTIFACT.
//
// 15 Aug 2026. The Visual Design Director's role_id is `visual_design`; its runtime agent_key is
// `marketing_design`. artifact_review defaulted reviewer_agent to 'marketing_design', and both
// guards on that path compared the two names RAW:
//
//   supabase/functions/artifact_review/index.ts   authorAgent === reviewerAgent
//   fn_artifact_review_valid()                    new.reviewer_agent = new.author_agent
//
// Measured on production before the fix, at zero model cost:
//
//   ('visual_design' = 'marketing_design')                                     -> false
//   fn_org_agent_resolve('visual_design') = fn_org_agent_resolve('marketing_design') -> true
//
// One employee, two names, and the guard built to stop a designer approving its own work could not
// see the one case it exists for. review_chain got this fix on 14 Aug
// (trg_review_chain_no_self_review resolves both sides); the artifact path did not.
//
// artifact_review holds 0 rows on both projects. A zero cannot tell a working guard from a dead
// one, so every test here FORCES the guard to fire — inside an aborted transaction, so nothing is
// left behind.
//
//   node --test scripts/checks/artifact_review_alias_cannot_self_approve.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

// staging (pglpqrhvozwepymcuunn) was a second target until its Supabase project was deleted on
// 15 Aug 2026; the same assertions now run against production alone.
const PROJECTS = { production: 'htdblwldjkcgjvmqkbeh' };

async function post(project, query) {
  for (let attempt = 0; ; attempt++) {
    const r = await fetch(`https://api.supabase.com/v1/projects/${project}/database/query`, {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + mgmtToken, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query }),
    });
    const text = await r.text();
    // A mass of failures with the other project passing is throttling, not a finding.
    if ((r.status === 429 || r.status >= 500) && attempt < 8) {
      await new Promise((s) => setTimeout(s, Math.min(1500 * 2 ** attempt, 20000))); continue;
    }
    return { ok: r.ok, status: r.status, text };
  }
}
const q = async (project, query) => {
  const r = await post(project, query);
  assert.ok(r.ok, `query failed on ${project}: ${r.status} ${r.text}`);
  return JSON.parse(r.text);
};
const one = async (project, query) => (await q(project, query))[0];

// A write we expect to be REFUSED. Returns the refusal text. Wrapped in a DO block so the failed
// statement aborts its own transaction and leaves no row behind either way.
async function refuses(project, sql) {
  const r = await post(project, `do $$
begin
  ${sql}
  raise exception 'GUARD DID NOT FIRE';
end $$;`);
  assert.ok(!r.ok || /GUARD DID NOT FIRE|error/i.test(r.text),
    `expected a refusal on ${project} but the statement succeeded: ${r.text}`);
  assert.doesNotMatch(r.text, /GUARD DID NOT FIRE/,
    `the guard did not fire on ${project} — the self-review was accepted`);
  return r.text;
}

const INS = (author, reviewer, verdict = 'pass') => `
  insert into artifact_review
    (subject_type, subject_id, artifact_url, artifact_sha256, revision, bytes, mime, verdict,
     author_agent, reviewer_agent, deterministic, vision, failures)
  values ('probe', 'alias-self-review-probe', 'https://example.invalid/a.png',
          repeat('0', 64), 1, 1, 'image/png', '${verdict}',
          ${author === null ? 'null' : `'${author}'`},
          ${reviewer === null ? 'null' : `'${reviewer}'`},
          '{}'::jsonb, '{}'::jsonb, '{}'::text[]);`;

for (const [name, ref] of Object.entries(PROJECTS)) {
  if (!mgmtToken) break;

  test(`${name}: the two names really are one employee (the premise of this file)`, async () => {
    const r = await one(ref, `select
      ('visual_design' = 'marketing_design') as raw_guard_fires,
      (fn_org_agent_resolve('visual_design') = fn_org_agent_resolve('marketing_design')) as same_employee,
      fn_org_agent_resolve('Visual Design Specialist') as title_resolves`);
    assert.equal(r.raw_guard_fires, false,
      'the premise no longer holds: the two identifiers are now equal as strings');
    assert.equal(r.same_employee, true,
      'visual_design and marketing_design no longer resolve to the same employee — this file is '
      + 'testing a case that has stopped existing, so re-derive it before deleting the guard');
  });

  test(`${name}: a self-review under an alias is REFUSED, not recorded`, async () => {
    // The exact shape that used to pass: author named by role_id, reviewer by agent_key.
    const err = await refuses(ref, INS('visual_design', 'marketing_design'));
    assert.match(err, /same employee|self-review/i,
      `the refusal did not name the reason: ${err}`);
  });

  test(`${name}: a self-review under the job TITLE is refused too`, async () => {
    // Rule 5 of the founder's standing instructions is to address employees by title. A guard that
    // only understands keys would be defeated by the very convention the company is asked to use.
    await refuses(ref, INS('Visual Design Director', 'marketing_design'));
  });

  test(`${name}: the identical raw name is still refused (the old guard's only case)`, async () => {
    await refuses(ref, INS('marketing_design', 'marketing_design'));
  });

  test(`${name}: a PASS with no reviewer at all is refused`, async () => {
    // The old guard permitted this: null is never equal to the author, so it read as "not a
    // self-review" and the artifact was recorded as passed with nobody having looked at it.
    await refuses(ref, INS('marketing_design', null));
  });

  test(`${name}: a genuinely independent review is ACCEPTED and stored canonically`, async () => {
    // A guard that refuses everything is not a guard. This proves the legitimate path still works,
    // and that what lands in the table is the canonical employee rather than what was typed.
    const r = await post(ref, `do $$
declare v_a text; v_r text;
begin
  ${INS('visual_design', 'ai_quality_reviewer')}
  select author_agent, reviewer_agent into v_a, v_r
    from artifact_review where subject_id = 'alias-self-review-probe';
  raise exception 'PROBE author=% reviewer=%', v_a, v_r;
end $$;`);
    // \S+ would swallow the "\nCONTEXT:" the management API appends to the error text.
    const m = /PROBE author=([a-z0-9_]+) reviewer=([a-z0-9_]+)/.exec(r.text);
    assert.ok(m, `the independent review was refused or produced no row on ${name}: ${r.text}`);
    assert.equal(m[1], 'marketing_design',
      'the author was stored as typed rather than canonically');
    // 6 SEP 2026: since PACR-004 (3 Sep 2026) ai_qa_specialist is a PARKED persona whose alias resolves
    // to qa_manager, the canonical QA employee; the reviewer typed under the old name is stored as
    // that. The property is unchanged — stored canonically, never as typed — the canonical name moved.
    assert.equal(m[2], 'qa_manager',
      'the reviewer was stored as typed rather than canonically');
  });

  test(`${name}: artifact_review's default reviewer is not the agent that draws the artifact`, () => {
    const src = readFileSync('supabase/functions/artifact_review/index.ts', 'utf8');
    const m = /body\.reviewer_agent \|\| '([^']+)'/.exec(src);
    assert.ok(m, 'the reviewer default in artifact_review has moved — re-derive this check');
    assert.notEqual(m[1], 'marketing_design',
      'the default reviewer is the Visual Design Director\'s own runtime key again: every artifact '
      + 'sent without an explicit reviewer would be reviewed by the agent that produced it');
  });

  test(`${name}: artifact_review resolves both identities before comparing them`, () => {
    const src = readFileSync('supabase/functions/artifact_review/index.ts', 'utf8');
    assert.match(src, /fn_org_agent_resolve/,
      'artifact_review compares author to reviewer without resolving either — an alias walks past it');
    assert.doesNotMatch(src, /authorAgent\s*===\s*reviewerAgent/,
      'the raw comparison is back; it answers "independent" for the one case the guard exists for');
  });
}
