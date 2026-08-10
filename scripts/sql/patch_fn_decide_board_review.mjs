// Insert the board-review call into fn_decide on both projects without pulling 19k chars of body
// through anyone's context. Fetch the definition, splice one guarded block before the final return,
// apply, then verify the check's own BOARD_INVOKED predicate.
import { readFileSync } from 'node:fs';
const token = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
const q = async (ref, sql) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }), signal: AbortSignal.timeout(120000) });
  const b = await r.text();
  if (!r.ok) throw new Error(ref + ' ' + r.status + ': ' + b.slice(0, 400));
  return JSON.parse(b);
};

const BLOCK = `
  -- BOARD BEFORE A MAJOR DECISION (spec #3 s24). Every active advisor gives an independent opinion
  -- on the problem this decision answers, keyed to the decision_record by id -- so the link is a
  -- foreign key and not the text match the scorer had to fall back on when subject_ref was null on
  -- all 28 rows. fn_challenge underneath is pure SQL, so this costs no model call.
  -- Guarded twice: only when a record was actually written, and an advisor that throws must not
  -- lose the decision it was advising on. The failure is raised as a warning rather than swallowed.
  if v_dr_id is not null then
    begin
      perform public.fn_board_review(
        coalesce((select d.problem from public.decision_record d where d.id = v_dr_id), p_kind),
        v_dr_id::text);
    exception when others then
      raise warning 'fn_board_review failed for decision_record % : %', v_dr_id, sqlerrm;
    end;
  end if;

`;

const MARK = "  return jsonb_build_object('kind',p_kind,'decision',decision,'confidence',conf,'reasons',reasons,";

for (const ref of ['htdblwldjkcgjvmqkbeh', 'pglpqrhvozwepymcuunn']) {
  const def = (await q(ref, `select pg_get_functiondef(p.oid) def from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_decide'`))[0]?.def;
  if (!def) { console.log(ref, 'fn_decide ABSENT'); continue; }
  if (/fn_board_review\s*\(/.test(def)) { console.log(ref, 'already calls fn_board_review'); continue; }
  const i = def.lastIndexOf(MARK);
  if (i < 0) { console.log(ref, 'MARKER NOT FOUND — not patched'); continue; }
  const patched = def.slice(0, i) + BLOCK + def.slice(i);
  await q(ref, patched);
  const chk = await q(ref, `select exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.prokind in ('f','p')
        and p.proname in ('fn_decide','fn_decision_gate','fn_task_approve','fn_check_spend','fn_exec_meeting')
        and pg_get_functiondef(p.oid) ~* '\\yfn_board_review\\s*\\(') as board_invoked`);
  console.log(ref, 'patched; BOARD_INVOKED =', chk[0].board_invoked);
}
