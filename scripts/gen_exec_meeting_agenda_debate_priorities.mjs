// ROW #3, LAYER 5 — the weekly executive meeting runs, and produces almost none of what a meeting is.
//
// ── MEASURED ON PRODUCTION, 9 AUG 2026, BEFORE A LINE OF THIS WAS WRITTEN ───────────────────────
//   exec-meeting-weekly-autostart    MET      exec_meeting_weekly (0 5 * * 1), last ok 2026-08-03
//   exec-meeting-ten-participants    MET      10 of 10 operating systems contributed
//   exec-meeting-agenda-six          MISSING  0 of 6 sections on all 12 contributions
//   exec-meeting-debate              MISSING  fn_exec_meeting invokes fn_challenge: false; 0 recorded
//   exec-meeting-priorities-agreed   MISSING  0 of 4 meetings end with a ranked/owned list
//   exec-meeting-replayable          MISSING  0 reachable routines emit the findings body
//
// The contributions carry item/owner/health/finding/drivers and nothing else, the recommendations
// are an array of two prose STRINGS, and no challenge is recorded anywhere near the meeting.
//
// ── WHAT THIS CHANGES, AND WHERE EVERY VALUE COMES FROM ─────────────────────────────────────────
// Six sections on every contribution, each one a count over live rows plus the top three by name.
// Nothing here is invented and nothing is a placeholder: a section with no rows says so, with the
// count, because "0 open risks on the register" is a finding a meeting is entitled to hear.
//
//   wins           org_tasks closed in the last 7 days for the owner's department
//   problems       the os_review findings for that OS this period
//   kpis           the live per-OS figures already gathered for `drivers`
//   risks          risk_register rows for the department that are not closed
//   opportunities  opportunity rows detected by someone in that department, + the company total
//   requests       org_tasks needing a founder decision in that department
//
// The three company-level items (Revenue, Supplier coverage, Platform availability) get the same
// six scoped to the company, merged in afterwards rather than typed into each of the three — so
// any item added later inherits them instead of silently arriving with four sections.
//
// ── ALL TEN PARTICIPATE, NOT ONLY THE ONES IN TROUBLE ───────────────────────────────────────────
// The loop was `where r2.health <> 'green'`. ten-participants passes today only because all ten
// happen to be amber this week — the first OS to go green would have dropped out of its own
// meeting and taken a passing check with it. A green OS reporting green IS participation, so the
// filter moves off the agenda and onto the two things that genuinely only concern trouble: the
// org_tasks that get raised, and the priority list.
//
// ── THE DEBATE IS THE PRIORITY ORDER, PUT TO ANOTHER OFFICER ────────────────────────────────────
// fn_challenge is the company's existing adversary: it matches the proposal against
// challenge_heuristic, reads institutional_memory for a prior outcome, and returns support /
// concern / recommend_against with its reasoning. The top three priorities are put to the first
// officer in the list who is not the one proposing — that is the "each other" the spec asks for,
// and three per week is a debate rather than thirteen rows of boilerplate.
//
// It is wrapped in its own exception block. A challenge that throws must not fail the meeting: the
// meeting's own cron success is what exec-meeting-weekly-autostart measures, and this change must
// not be able to take a passing check down with it. The count of challenges that actually landed
// goes into the agent_runs note, so a swallowed failure is visible instead of silent.
//
// ── PRIORITIES BECOME OBJECTS, RANKED AND OWNED ─────────────────────────────────────────────────
// `recs` was ['<sentence>', '<sentence>']. It becomes one object per non-green contribution with
// rank, owner, priority and title, ordered red before amber and then by OS number. `title` is
// deliberate: fn_report_recommendation_approve already reads `v_rec ->> 'title'` and falls back to
// the raw text, so the founder's approve button gets a real title instead of 160 characters of JSON.
//
// THIS DOES NOT MAKE priorities-agreed FLIP TODAY. That check is a universal over every ceo
// exec_report in 60 days, and three of the four in the window were written on 28 Jul and 3 Aug with
// string recommendations. Rewriting those rows would be editing the record to turn a gate green,
// so they are left alone; the check flips when they age out of the window.
//
// ── HOW IT IS APPLIED ───────────────────────────────────────────────────────────────────────────
// fn_exec_meeting is 6,523 characters. It is read from the live database and patched at anchors
// that are each asserted to appear EXACTLY ONCE, so every line this change does not touch stays
// byte-identical to what is running. Same discipline as gen_os_health_reaches_the_exec_meeting.mjs.
import { readFileSync, writeFileSync } from 'node:fs';
import { mgmtRead } from './lib/qd_guard.mjs';
import { REF as STAGE } from './lib/demo_factory.mjs';

const OUT = 'scripts/sql/exec_meeting_agenda_debate_priorities.sql';
const one = async (sql) => { const r = await mgmtRead(STAGE, sql); return r[0] ? Object.values(r[0])[0] : null; };

const fnDef = await one(`select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.proname='fn_exec_meeting' limit 1`);
if (!fnDef) { console.error('fn_exec_meeting not found'); process.exit(1); }
if (/fn_challenge/.test(fnDef)) { console.error('REFUSING: fn_exec_meeting already invokes fn_challenge.'); process.exit(1); }

let out = fnDef;
// Every patch asserts its anchor appears exactly once. A body that has drifted fails here rather
// than producing a half-applied function.
const patch = (label, anchor, replacement) => {
  const hits = out.split(anchor).length - 1;
  if (hits !== 1) {
    console.error(`REFUSING: anchor "${label}" matched ${hits} time(s), expected exactly 1.`);
    console.error('fn_exec_meeting has changed shape since this generator was written. Re-read it first.');
    process.exit(1);
  }
  out = out.replace(anchor, replacement);
};

// ── A. the declarations ─────────────────────────────────────────────────────────────────────────
patch('declare',
  `declare m jsonb; findings jsonb := '[]'::jsonb; actions int := 0; recs jsonb;`,
  `declare m jsonb; findings jsonb := '[]'::jsonb; actions int := 0; recs jsonb;
  -- the six agenda sections, rebuilt per contribution, plus their company-scoped counterparts
  v_wins text; v_probs text; v_risks text; v_opps text; v_reqs text; v_kpis jsonb;
  v_dept text; v_opp_all int; v_co jsonb; p record; v_challenger text; v_ch int := 0;`);

// ── B. all ten participate ──────────────────────────────────────────────────────────────────────
patch('agenda filter',
  `    where r2.period = v_period and r2.health <> 'green' order by
      case r2.health when 'red' then 1 else 2 end, o.num`,
  `    where r2.period = v_period order by
      case r2.health when 'red' then 1 when 'amber' then 2 else 3 end, o.num`);

// ── C. the six sections on every per-OS contribution ────────────────────────────────────────────
patch('per-OS contribution',
  `    findings := findings || jsonb_build_array(jsonb_build_object(
      'item', r.num||'. '||r.name, 'owner', coalesce(r.owner_agent,'unassigned'),
      'health', r.health, 'finding', r.findings::text, 'drivers', v_drivers));`,
  `    -- THE SIX AGENDA SECTIONS. Each is a count over live rows and the top three by name; a
    -- section with nothing in it states the zero rather than being omitted, because a meeting is
    -- entitled to hear "no open risks" and a missing section is not the same claim.
    v_dept := (select department from org_agents where agent_key = r.owner_agent);

    v_wins := (select count(*) from org_tasks
                where status='done' and updated_at > now()-interval '7 days' and dept_key = v_dept)
      ||' task(s) closed in the last 7 days'
      || coalesce(': '||(select string_agg(w.title, '; ') from (
             select title from org_tasks where status='done'
              and updated_at > now()-interval '7 days' and dept_key = v_dept
              order by updated_at desc limit 3) w), '')||'.';

    v_probs := case when jsonb_typeof(r.findings)='array' and jsonb_array_length(r.findings) > 0
      then (select string_agg(coalesce(e->>'issue', e::text)||coalesce(' — '||(e->>'detail'), ''), '; ')
              from jsonb_array_elements(r.findings) e)
      else 'No unresolved finding recorded for this operating system in '||v_period||'.' end;

    v_kpis := jsonb_build_object('health', r.health,
      'open_risks', r.open_risks, 'kpi_gaps', r.kpi_gaps, 'capacity_pct', r.capacity_pct,
      'backlog_per_head', r.backlog_per_head, 'stale_tasks', r.stale_tasks,
      'review_pass_pct', r.review_pass_pct, 'budget_pct', r.budget_pct,
      'needs_founder_pct', r.needs_founder_pct);

    v_risks := (select count(*) from risk_register
                 where coalesce(status,'open') <> 'closed' and dept_key = v_dept)
      ||' open risk(s) on the register'
      || coalesce(': '||(select string_agg(k.risk, '; ') from (
             select risk from risk_register where coalesce(status,'open') <> 'closed'
              and dept_key = v_dept order by updated_at desc nulls last limit 3) k), '')||'.';

    v_opps := (select count(*) from opportunity op join org_agents oa on oa.agent_key = op.detected_by
                where coalesce(op.status,'open')='open' and oa.department = v_dept)
      ||' open opportunit(ies) attributed to this operating system'
      || coalesce(': '||(select string_agg(x.title, '; ') from (
             select op.title from opportunity op join org_agents oa on oa.agent_key = op.detected_by
              where coalesce(op.status,'open')='open' and oa.department = v_dept
              order by op.value_score desc nulls last limit 3) x), '')
      ||'; '||v_opp_all||' open company-wide.';

    v_reqs := (select count(*) from org_tasks
                where needs_founder and status <> 'done' and dept_key = v_dept)
      ||' item(s) awaiting a founder decision'
      || coalesce(': '||(select string_agg(q.title, '; ') from (
             select title from org_tasks where needs_founder and status <> 'done'
              and dept_key = v_dept order by created_at desc limit 3) q), '')||'.';

    findings := findings || jsonb_build_array(jsonb_build_object(
      'item', r.num||'. '||r.name, 'owner', coalesce(r.owner_agent,'unassigned'),
      'health', r.health, 'finding', r.findings::text, 'drivers', v_drivers,
      'wins', v_wins, 'problems', v_probs, 'kpis', v_kpis,
      'risks', v_risks, 'opportunities', v_opps, 'requests', v_reqs));`);

// ── C2. the company total the per-OS opportunities line quotes, gathered once ───────────────────
patch('company opportunity total',
  `  m := jsonb_build_object('week',v_period,`,
  `  select count(*) into v_opp_all from opportunity where coalesce(status,'open')='open';

  m := jsonb_build_object('week',v_period,`);

// ── D. the company-level items get the same six, company-scoped ────────────────────────────────
patch('company sections merge',
  `  insert into org_tasks (dept_key,title,detail,status,tier,needs_founder,action_class)`,
  `  -- The company-level items above are contributions too, so they carry the same six sections,
  -- scoped to the company rather than to one department. Merged rather than typed into each of
  -- the three: an item added later inherits the sections instead of arriving with four.
  v_co := jsonb_build_object(
    'wins', (select count(*) from org_tasks where status='done' and updated_at > now()-interval '7 days')
            ||' task(s) closed company-wide in the last 7 days.',
    'problems', v_red||' operating system(s) red and '||v_amber||' amber in '||v_period||'.',
    'kpis', m,
    'risks', (select count(*) from risk_register where coalesce(status,'open') <> 'closed')
             ||' open risk(s) on the company register.',
    'opportunities', v_opp_all||' open opportunit(ies) company-wide.',
    'requests', (select count(*) from org_tasks where needs_founder and status <> 'done')
                ||' item(s) awaiting a founder decision company-wide.');
  select coalesce(jsonb_agg(case when f ? 'wins' then f else f || v_co end order by ord), '[]'::jsonb)
    into findings from jsonb_array_elements(findings) with ordinality as t(f, ord);

  insert into org_tasks (dept_key,title,detail,status,tier,needs_founder,action_class)`);

// ── E. a green operating system does not raise an action ───────────────────────────────────────
patch('task filter',
  `  where not exists (select 1 from org_tasks t where t.title='Exec meeting '`,
  `  where coalesce(f->>'health','') <> 'green'
    and not exists (select 1 from org_tasks t where t.title='Exec meeting '`);

// ── F. the priorities become ranked, owned objects ─────────────────────────────────────────────
patch('recommendations',
  `  recs := case when jsonb_array_length(findings)=0
    then jsonb_build_array('All ten operating systems green and company metrics within tolerance. Hold current priorities.')
    else jsonb_build_array(
      v_red||' operating system(s) red, '||v_amber||' amber. Each has a named owner and a tracked action.',
      'Priority order follows the constitution: compliance, then customer trust, then quality, then revenue.') end;`,
  `  -- AGREED PRIORITIES, RANKED AND OWNED. One object per contribution that is not green, red
  -- before amber and then in operating-system order, which is the order the constitution gives:
  -- compliance and trust sit in the red band before anything amber is opened. \`title\` is the key
  -- fn_report_recommendation_approve already reads, so the founder's approve control gets a name
  -- rather than 160 characters of JSON.
  select coalesce(jsonb_agg(jsonb_build_object(
           'rank', x.rn, 'owner', x.owner, 'priority', x.health,
           'title', x.item, 'why', x.finding) order by x.rn), '[]'::jsonb)
    into recs from (
      select row_number() over (order by case f->>'health' when 'red' then 1 else 2 end, ord) rn,
             f->>'item' item, f->>'owner' owner, f->>'health' health,
             -- an operating system's readable problem statement lives in \`problems\`; \`finding\` is
             -- the raw os_review JSON. The three company items are the other way round.
             case when f ? 'drivers' then f->>'problems' else f->>'finding' end finding
        from jsonb_array_elements(findings) with ordinality as t(f, ord)
       where coalesce(f->>'health','') <> 'green') x;
  if jsonb_array_length(recs) = 0 then
    recs := jsonb_build_array(jsonb_build_object('rank', 1, 'owner', 'ceo', 'priority', 'hold',
      'title', 'Hold current priorities',
      'why', 'All ten operating systems green and company metrics within tolerance.'));
  end if;`);

// ── G. the debate ──────────────────────────────────────────────────────────────────────────────
patch('debate',
  `  insert into agent_runs (agent,started_at,finished_at,status,counts,note)`,
  `  -- THE DEBATE. The CEO's proposed priority order is put to another officer, who evaluates it
  -- through fn_challenge against challenge_heuristic and any prior outcome in institutional_memory
  -- and answers support / concern / recommend_against with its reasoning. The challenger is the
  -- first officer in the list who is not the one proposing, so this is officers challenging each
  -- other rather than the CEO agreeing with itself. Top three only: a debate, not thirteen rows of
  -- boilerplate a week.
  --
  -- In its own block because a challenge that throws must not fail the meeting — the cron's own
  -- success is what exec-meeting-weekly-autostart measures. The number that actually landed goes
  -- into the run note below, so a swallowed failure is visible rather than silent.
  begin
    for p in select (e->>'rank')::int prank, e->>'title' ptitle, e->>'owner' powner
               from jsonb_array_elements(recs) e
              where (e->>'rank')::int <= 3 order by (e->>'rank')::int
    loop
      v_challenger := coalesce((select e2->>'owner' from jsonb_array_elements(recs) e2
                                 where coalesce(e2->>'owner','') <> coalesce(p.powner,'')
                                 order by (e2->>'rank')::int limit 1), 'ceo');
      perform fn_challenge('Exec meeting '||v_period||' priority '||p.prank||': '||p.ptitle,
                           coalesce(p.powner,'ceo'), v_challenger);
      v_ch := v_ch + 1;
    end loop;
  exception when others then
    v_ch := -1;
  end;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)`);

// ── H. the run record says what was actually produced ──────────────────────────────────────────
patch('run counts',
  `    jsonb_build_object('os_green',v_green,'os_amber',v_amber,'os_red',v_red,'findings',jsonb_array_length(findings),'actions',actions),`,
  `    jsonb_build_object('os_green',v_green,'os_amber',v_amber,'os_red',v_red,'findings',jsonb_array_length(findings),'actions',actions,
      'priorities',jsonb_array_length(recs),'challenges',v_ch),`);

patch('run note',
  ` across ten operating systems, '||actions||' actions assigned.');`,
  ` across ten operating systems, '||actions||' actions assigned, '
    ||jsonb_array_length(recs)||' ranked priorities, '
    ||case when v_ch < 0 then 'the challenge round failed' else v_ch||' challenge(s) put to a second officer' end||'.');`);

patch('return value',
  `  return jsonb_build_object('week',v_period,'green',v_green,'amber',v_amber,'red',v_red,
                            'findings',jsonb_array_length(findings),'actions',actions,'metrics',m);`,
  `  return jsonb_build_object('week',v_period,'green',v_green,'amber',v_amber,'red',v_red,
                            'findings',jsonb_array_length(findings),'actions',actions,
                            'priorities',jsonb_array_length(recs),'challenges',v_ch,'metrics',m);`);

patch('summary wording', `' agenda finding(s), '`, `' agenda contribution(s), '`);

// ── THE TRANSCRIPT REACHES THE BROWSER ─────────────────────────────────────────────────────────
// exec_reports.findings holds the whole ordered transcript and no routine the browser can run has
// ever named it: `reachable routine(s) emitting the findings body: 0`. fn_ws_reports is dispatched
// by os_api as ws.reports, so the meeting goes there — the transcript, the ranked priorities, and
// the challenges recorded in its window, which is the debate the founder would otherwise have to
// take on trust.
const wsDef = await one(`select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.proname='fn_ws_reports' limit 1`);
if (!wsDef) { console.error('fn_ws_reports not found'); process.exit(1); }
if (/exec_reports/.test(wsDef)) { console.error('REFUSING: fn_ws_reports already reads exec_reports.'); process.exit(1); }

const WS_ANCHOR = `  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.report_kpis k),`;
if (wsDef.split(WS_ANCHOR).length - 1 !== 1) {
  console.error('REFUSING: the fn_ws_reports anchor did not match exactly once.'); process.exit(1);
}
const wsOut = wsDef.replace(WS_ANCHOR, `  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.report_kpis k),
    -- THE LATEST EXECUTIVE MEETING, IN SEQUENCE. exec_reports.findings is the ordered transcript of
    -- what each of the ten officers said; report_registry projects only title/period/id, so until
    -- now the body reached nothing the browser could run. \`contributions\` keeps the array order
    -- the meeting wrote it in — that order IS the replay.
    'meeting', (select jsonb_build_object(
        'id', r.id, 'period', r.period, 'officer', r.officer, 'summary', r.summary,
        'at', to_char(r.created_at,'YYYY-MM-DD HH24:MI'),
        'contributions', coalesce(r.findings, '[]'::jsonb),
        'priorities', coalesce(r.recommendations, '[]'::jsonb),
        'challenges', (select coalesce(jsonb_agg(jsonb_build_object(
              'proposal', c.proposal, 'by', c.challenged_by, 'of', c.proposed_by,
              'stance', c.stance, 'confidence', c.confidence, 'reasoning', c.reasoning,
              'alternatives', c.alternatives) order by c.id), '[]'::jsonb)
            from public.challenge_record c
           where c.created_at between r.created_at - interval '30 minutes'
                                  and r.created_at + interval '6 hours'))
      from public.exec_reports r where r.officer='ceo' order by r.created_at desc limit 1),`);

const selfLines = readFileSync(new URL(import.meta.url).pathname.replace(/^\//, ''), 'utf8').split('\n');
const end = selfLines.findIndex((l) => !l.startsWith('//'));
const HEADER = selfLines.slice(0, end < 0 ? selfLines.length : end)
  .map((l) => l.replace(/^\/\/ ?/, '-- ').replace(/^\/\//, '--')).join('\n');

writeFileSync(OUT, `${HEADER}\n\n${out};\n\n${wsOut};\n`);
console.log(`wrote ${OUT}`);
console.log(`  fn_exec_meeting  ${fnDef.length} -> ${out.length} chars`);
console.log(`  fn_ws_reports    ${wsDef.length} -> ${wsOut.length} chars`);
