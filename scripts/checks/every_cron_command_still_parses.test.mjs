// EVERY SCHEDULED COMMAND IS STILL VALID SQL, AND STILL POINTS WHERE IT DID.
//
// 16 Aug 2026. A migration rewrote 46 cron job URLs to read the project ref from app_secrets instead
// of naming it, so that a schema export would be identical from either source. The substitution was
// built with SQL quote escaping and came out one level too deep:
//
//     ... where key = ''project_ref''        instead of        ... where key = 'project_ref'
//
// which is a syntax error. Every one of those 46 jobs would have failed on its next firing,
// including backup_daily and the uptime and health probes — the eight the stand-down deliberately
// kept running.
//
// The migration verified itself and passed. It asserted the rewritten commands matched
// `key = ''project_ref''` — written with the same doubled escaping as the defect. The assertion and
// the bug came from one mistaken belief about quoting, so they agreed, and the agreement was read as
// proof. A string comparison between two things the same author wrote in the same breath verifies
// nothing.
//
// Nothing in this repository would have caught it. sql_files_match_live checks routine bodies,
// verify_deploy_parity checks edge functions; neither reads cron.job.command, and a broken schedule
// is invisible until the schedule fires — up to a week later for a weekly job, and only as an absent
// result rather than an alarm.
//
// So this asks the database, not a pattern:
//
//   1. every parameterised URL expression is EXECUTED on its own and must resolve to
//      https://<project_ref>.supabase.co/... — proving it is valid SQL and still points at the same
//      host. That is the property the rewrite was supposed to preserve.
//   2. every command that is a single plannable statement is EXPLAINed — planned, not run, so no
//      HTTP call is made and no row is written.
//   3. no command names a project ref literally, which is the portability property itself.
//
// Commands that are DO blocks or CALLs cannot be planned without executing them; they are covered by
// (1) and (3) and are COUNTED AND NAMED in the output rather than quietly reported as checked.
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { readFileSync, existsSync } from 'node:fs';

const REF_TOKEN = /\b[a-z]{20}\b/;
const LOCAL = SUPABASE_TOKEN_FILE;
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL) ? readFileSync(LOCAL, 'utf8') : '')).trim();
if (!token) {
  console.log('SKIPPED: no SUPABASE_ACCESS_TOKEN and no local access token. This check reads the '
    + 'live scheduler; it has nothing to assert without it.');
  process.exit(0);
}
const PROJECT = 'htdblwldjkcgjvmqkbeh';

async function q(sql, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROJECT}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  if ((r.status === 429 || r.status >= 500) && attempt < 8) {
    await new Promise((s) => setTimeout(s, 2000 * (attempt + 1)));
    return q(sql, attempt + 1);
  }
  const body = await r.text();
  if (!r.ok) return { error: body };
  return JSON.parse(body);
}

// One round trip. The whole verification runs inside an aborted transaction so that EXPLAIN cannot
// leave anything behind even if a command has a side effect the planner evaluates.
const sql = `
do $check$
declare r record; got text; resolved text; e text;
        bad text := ''; unplannable text := ''; n_url int := 0; n_plan int := 0; v_ref text;
        body text;
begin
  select value into v_ref from public.app_secrets where key = 'project_ref';
  if coalesce(v_ref,'') = '' then
    raise exception 'app_secrets.project_ref is missing: every parameterised cron URL resolves to https://.supabase.co/';
  end if;

  for r in select jobid, jobname, command from cron.job order by jobname loop
    for got in
      select (regexp_matches(r.command,
        $q$('https://' \\|\\| \\(\\s*select value from (?:public\\.)?app_secrets where key = 'project_ref'\\s*\\) \\|\\| '[^']*')$q$,
        'g'))[1]
    loop
      begin
        execute 'select ' || got into resolved;
        if resolved !~ ('^https://' || v_ref || '\\.supabase\\.co/') then
          bad := bad || r.jobname || ' resolves to ' || coalesce(resolved,'NULL') || '; ';
        else n_url := n_url + 1; end if;
      exception when others then
        get stacked diagnostics e = message_text;
        bad := bad || r.jobname || ' URL will not evaluate (' || left(e,80) || '); ';
      end;
    end loop;

    body := btrim(btrim(regexp_replace(r.command, '^(\\s*--[^\\n]*\\n)+', '', 'g')), ';');
    begin
      if body ~* '^(select|insert|update|delete|with)\\y' then
        execute 'explain (costs off) ' || body;
        n_plan := n_plan + 1;
      else
        unplannable := unplannable || r.jobname || ' ';
      end if;
    exception when others then
      get stacked diagnostics e = message_text;
      if sqlstate like '42%' then bad := bad || r.jobname || ' does not parse (' || left(e,80) || '); '; end if;
    end;

    if r.command like '%' || v_ref || '%' then
      bad := bad || r.jobname || ' names the project ref literally; ';
    end if;
  end loop;

  raise exception 'RESULT|%|%|%|%', n_url, n_plan, coalesce(nullif(unplannable,''),'(none)'), coalesce(nullif(bad,''),'OK');
end $check$;`;

const res = await q(sql);
const msg = (res.error || '').match(/RESULT\|([^|]*)\|([^|]*)\|([^|]*)\|([\s\S]*?)(?:\\n|"|$)/);
if (!msg) {
  console.error('could not read production, or the probe itself failed:',
    (res.error || JSON.stringify(res)).slice(0, 500));
  process.exit(1);
}
const [, nUrl, nPlan, unplannable, bad] = msg;
console.log(`CRON COMMANDS — ${nUrl} parameterised URL(s) resolve to https://${PROJECT}.supabase.co/…`);
console.log(`               ${nPlan} whole command(s) plan`);
console.log(`               not statically plannable (DO/CALL, covered by URL + ref checks): ${unplannable}`);

if (bad.trim() !== 'OK') {
  console.error(`\nFAIL: ${bad}`);
  process.exit(1);
}
console.log('\nOK: every scheduled command parses, every URL points at this project, and no command '
  + 'names the project ref literally.');
