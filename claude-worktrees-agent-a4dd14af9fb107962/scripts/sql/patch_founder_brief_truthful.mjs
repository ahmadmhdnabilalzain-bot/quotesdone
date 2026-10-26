// THREE THINGS THE OVERNIGHT BRIEF TOLD THE FOUNDER THAT WERE NOT TRUE.
//
// Patched by splice rather than retyped: fn_founder_brief is ~400 lines and pulling it through a
// context window to change three fragments is how a fourth defect gets introduced. Same method as
// patch_fn_decide_board_review.mjs.
//
//   node scripts/sql/patch_founder_brief_truthful.mjs
//
// 1. "Monthly goal attainment: 97.7% against target"  — on a morning with AED 0 revenue against an
//    AED 83,333 monthly target. Three compounding causes, all measured 11 Aug 2026:
//      * least(100.0, NULL) returns 100.0 in PostgreSQL — least() ignores nulls — so all 56 goals
//        with no measured actual scored a PERFECT 100 and were averaged in.
//      * no period filter, so it averaged the 2026-07 rows on 11 August.
//      * direction ignored, so 19 'at_most' goals were scored as though bigger were better.
//    Replaced by fn_goal_attainment('monthly'), which returns the percentage AND the denominator,
//    so the brief can no longer quote a percentage without saying what it is a percentage of. The
//    same figure now reads 50.0% across 2 of 61 goals.
//
// 2. "Approvals waiting: 40 (incl. 6 supplier KYC)" — the 40 is agent_actions and the 6 is leads.
//    They are disjoint sets. The real number waiting on the founder was 46, and "incl." told him it
//    was 40.
//
// 3. THE DIGEST SWALLOWED WHAT IT DID NOT REPORT. The brief lists digested alerts as bare counts by
//    TYPE for the last 24 hours — "ops_alert: 1" and nothing about what the alert said — and then
//    marks EVERY row with status='digest' as 'digested' regardless of age. Anything older than 24
//    hours was therefore closed without ever having appeared in a brief. 34 rows sit 'digested'
//    today and the founder never saw one subject line. Now: the subjects are printed, and only the
//    rows actually reported are closed.
import { readFileSync } from 'node:fs';
const token = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
const q = async (ref, sql) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }), signal: AbortSignal.timeout(180000) });
  const b = await r.text();
  if (!r.ok) throw new Error(ref + ' ' + r.status + ': ' + b.slice(0, 400));
  return JSON.parse(b);
};

// Each edit is [find, replace]. `find` must appear exactly once; a miss is reported, never guessed.
const EDITS = [
  // 1 — attainment: read the shared function, and carry the denominator.
  [`  begin select round(avg(least(100.0, 100.0 * g.actual_value / nullif(g.target_value,0))),1) into v_goal
     from public.goal_period g where g.horizon = 'monthly' and g.target_value is not null;
  exception when others then v_goal := null; end;`,
   `  -- least(100.0, NULL) is 100.0 in PostgreSQL, so the previous inline version scored every
  -- UNMEASURED goal as a perfect 100 and averaged them with the two that were real. It also read
  -- last month's rows and ignored direction. fn_goal_attainment does all three correctly and
  -- returns the denominator, which is what stops a percentage being quoted without its base.
  begin
    v_goal_j := public.fn_goal_attainment('monthly');
    v_goal := (v_goal_j->>'pct')::numeric;
  exception when others then v_goal := null; v_goal_j := null; end;`],

  // declaration for the new variable
  [`  v_opp text; v_goal numeric;`,
   `  v_opp text; v_goal numeric; v_goal_j jsonb;`],

  // 2 — approvals: the two queues are disjoint.
  [`    '- Approvals waiting: '||v_pend||' (incl. '||v_kyc||' supplier KYC)'||E'\\n'||`,
   `    '- Approvals waiting: '||(v_pend + v_kyc)||' — '||v_pend||' agent action(s) plus '||v_kyc||' supplier KYC (separate queues)'||E'\\n'||`],

  // 1b — the printed line states its base.
  [`    '- Monthly goal attainment: '||coalesce(v_goal::text,'0')||'% against target'||E'\\n'||`,
   `    '- Monthly goal attainment: '||coalesce(v_goal::text,'not measurable')||
      case when v_goal is not null then '% across '||coalesce(v_goal_j->>'goals_measured','?')||' of '||
             coalesce(v_goal_j->>'goals_total','?')||' goals that carry a measured actual for '||
             coalesce(v_goal_j->>'period','this period')||
             ' (the rest have no measure and are NOT counted as met)'
           else ' — no goal has a measured actual for this period' end||E'\\n'||`],

  // 3 — the digest reports what it closes.
  [`    select string_agg('- '||type||': '||n, E'\\n' order by n desc)
      into v_handled
    from (select type, count(*) n from notifications
          where status='digest' and created_at >= now()-interval '24 hours'
          group by type) z;`,
   `    -- SUBJECTS, NOT A TALLY. "ops_alert: 3" tells the founder nothing about what was raised for
    -- him, and these rows are then CLOSED. The window also moves from 24 hours to 7 days so that a
    -- row created outside the last day is reported before it is marked digested rather than after.
    select string_agg('- ['||to_char(created_at,'DD Mon HH24:MI')||'] '||type||': '||
                      coalesce(nullif(subject,''),'(no subject)'), E'\\n' order by created_at desc)
      into v_handled
    from (select type, subject, created_at from notifications
          where status='digest' and created_at >= now()-interval '7 days'
          order by created_at desc limit 25) z;`],

  [`  update notifications set status='digested' where status='digest' and created_at <= now();`,
   `  -- ONLY WHAT WAS ACTUALLY REPORTED. This closed EVERY digest row regardless of age, so anything
  -- older than the brief's own reporting window was marked handled without the founder ever seeing
  -- it. The window here and the window above are the same window on purpose.
  update notifications set status='digested'
   where status='digest' and created_at >= now()-interval '7 days' and created_at <= now();`],
];

let bad = 0;
// 15 Aug 2026: one project. pglpqrhvozwepymcuunn was deleted, and a loop that still named it ran
// every statement twice — once for real, once into a management API 400 this script prints and
// moves past, which reads in the log exactly like a partial success.
for (const ref of ['htdblwldjkcgjvmqkbeh']) {
  let def = (await q(ref, `select pg_get_functiondef(p.oid) def from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_founder_brief'`))[0]?.def;
  if (!def) { console.log(ref, 'fn_founder_brief ABSENT'); bad++; continue; }
  if (def.includes('fn_goal_attainment')) { console.log(ref, 'already patched'); continue; }
  let applied = 0;
  for (const [find, repl] of EDITS) {
    const hits = def.split(find).length - 1;
    if (hits !== 1) { console.log(`${ref}  MARKER x${hits}: ${find.slice(0, 60).replace(/\n/g, ' ')}…`); bad++; continue; }
    def = def.replace(find, repl); applied++;
  }
  if (applied !== EDITS.length) { console.log(`${ref}  ${applied}/${EDITS.length} edits matched — NOT applied`); bad++; continue; }
  await q(ref, def);
  console.log(`${ref}  patched, ${applied} edit(s)`);
}
if (bad) { console.error(`${bad} project(s)/marker(s) failed`); process.exit(1); }

// PROVE IT. Run the brief in a transaction that rolls itself back, and read the three lines.
// 15 Aug 2026: one project. pglpqrhvozwepymcuunn was deleted, and a loop that still named it ran
// every statement twice — once for real, once into a management API 400 this script prints and
// moves past, which reads in the log exactly like a partial success.
for (const ref of ['htdblwldjkcgjvmqkbeh']) {
  try {
    await q(ref, `do $$ declare b text; begin
      perform public.fn_founder_brief();
      select body into b from notifications where type='founder_brief' order by id desc limit 1;
      raise exception 'PROBE %', (select string_agg(l, ' || ') from unnest(string_to_array(b, chr(10))) l
        where l like '%Approvals waiting%' or l like '%goal attainment%' or l like '%HANDLED FOR YOU%' or l like '- [%');
    end $$;`);
  } catch (e) { console.log(`\n${ref}\n  ` + String(e.message).replace(/^.*PROBE /s, '').slice(0, 900)); }
}
