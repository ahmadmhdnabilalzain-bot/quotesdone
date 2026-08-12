-- THE DAILY BRIEF ADDED HIS QUEUE TO THE MACHINE'S AND SENT HIM THE TOTAL
--
-- fn_wa_context had this defect and so does the brief he actually reads every morning. Its
-- "NEEDS YOU TODAY" section says:
--
--     - Approvals waiting: N — <v_pend> agent action(s) plus <v_kyc> supplier KYC
--
-- and v_pend counts every agent_actions row in pending / held_for_review / proposed / open /
-- needs_review. On production this morning that is 38. Of those 38, TWELVE are the machine's own
-- work in flight — handoffs and knowledge tasks that action_worker will settle within the hour and
-- that he must not touch — and TWENTY-SEVEN are items no agent is permitted to settle. The oldest
-- of those is a legal_flag raised on 9 JULY. Thirty-five days.
--
-- A number that mixes the two is worse than no number, because the correct response to "38 agent
-- actions" is to ignore it, and he has been ignoring it correctly for five weeks while four legal
-- flags and a prompt approval sat inside it.
--
-- Worse: "DECISIONS NEEDED" enumerates KYC, refunds, objective steps, expired licences and severe
-- alerts, and does NOT mention agent_actions addressed to him at all. So the one section of the
-- brief whose entire job is to list what he must decide has never listed the queue built for
-- exactly that.
--
-- fn_founder_queue() already separates the populations and ages every item. This teaches the brief
-- to read it.
--
-- WHY THIS IS A PATCH AND NOT A REWRITE. fn_founder_brief is ~200 lines of plpgsql that composes
-- the email he gets every morning. Retyping it to change four lines is how a transcription error
-- reaches his inbox. So the definition is read back from the catalogue and edited by exact string
-- replacement, with EVERY anchor asserted to appear EXACTLY ONCE before anything is changed and the
-- result asserted to differ. If the function drifts, this raises instead of silently doing nothing
-- or doing something else — the failure mode a blind replace() has.
do $$
declare
  v_def text; v_new text; v_oid oid;
  a1 text; b1 text; a2 text; b2 text; a3 text; b3 text; a4 text; b4 text;
begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_founder_brief' and p.pronargs = 0;
  if v_oid is null then raise exception 'fn_founder_brief() not found'; end if;
  v_def := pg_get_functiondef(v_oid);

  -- 1. three more locals
  a1 := $q$  v_owner text; v_run bigint;$q$;
  b1 := $q$  v_owner text; v_run bigint; v_fq jsonb; v_fq_n int := 0; v_fq_age int; v_fq_list text;$q$;

  -- 2. read the queue just before the decisions list is built
  a2 := $q$  v_decisions := '';$q$;
  b2 := $q$  -- HIS QUEUE, SEPARATE FROM THE MACHINE'S. fn_founder_queue counts only kinds
  -- agent_action_kind_policy marks 'founder' — the ones no agent may settle — and ages them.
  begin
    v_fq := public.fn_founder_queue(5);
    v_fq_n := coalesce((v_fq->>'waiting_on_you_total')::int, 0);
    v_fq_age := (v_fq->>'oldest_days')::int;
    select string_agg('     · '||(x->>'kind')||' from '||(x->>'from')||' — '||(x->>'title')||
                      ' ('||(x->>'age_days')||'d)', E'\n')
      into v_fq_list from jsonb_array_elements(v_fq->'waiting_on_you') x;
  exception when others then v_fq_n := 0; v_fq_age := null; v_fq_list := null; end;

  v_decisions := '';$q$;

  -- 3. name it in DECISIONS NEEDED, with its age and its oldest items
  a3 := $q$  if v_expired > 0 then v_dn:=v_dn+1;$q$;
  b3 := $q$  if v_fq_n > 0 then v_dn:=v_dn+1; v_decisions := v_decisions||v_dn||'. Settle '||v_fq_n||
    ' item(s) no agent is allowed to decide'||
    case when v_fq_age is not null then ' — the oldest has been waiting '||v_fq_age||' day(s)' else '' end||
    E'\n'||coalesce(v_fq_list||E'\n','');
  end if;
  if v_expired > 0 then v_dn:=v_dn+1;$q$;

  -- 4. stop adding the two queues together in NEEDS YOU TODAY
  a4 := $q$    '- Approvals waiting: '||(v_pend + v_kyc)||' — '||v_pend||' agent action(s) plus '||v_kyc||' supplier KYC (separate queues)'||E'\n'||$q$;
  b4 := $q$    '- Waiting on YOU: '||v_fq_n||' item(s) no agent may settle'||
      case when v_fq_age is not null then ' (oldest '||v_fq_age||'d)' else '' end||
      ' plus '||v_kyc||' supplier KYC — these are yours'||E'\n'||
    '- The machine is working on: '||greatest(v_pend - v_fq_n, 0)||' item(s) it settles itself; no action needed'||E'\n'||$q$;

  if (length(v_def) - length(replace(v_def, a1, ''))) / nullif(length(a1),0) <> 1 then
    raise exception 'anchor 1 (locals) appears % time(s), expected exactly 1',
      (length(v_def) - length(replace(v_def, a1, ''))) / nullif(length(a1),0); end if;
  if (length(v_def) - length(replace(v_def, a2, ''))) / nullif(length(a2),0) <> 1 then
    raise exception 'anchor 2 (v_decisions init) appears % time(s), expected exactly 1',
      (length(v_def) - length(replace(v_def, a2, ''))) / nullif(length(a2),0); end if;
  if (length(v_def) - length(replace(v_def, a3, ''))) / nullif(length(a3),0) <> 1 then
    raise exception 'anchor 3 (expired-licence decision) appears % time(s), expected exactly 1',
      (length(v_def) - length(replace(v_def, a3, ''))) / nullif(length(a3),0); end if;
  if (length(v_def) - length(replace(v_def, a4, ''))) / nullif(length(a4),0) <> 1 then
    raise exception 'anchor 4 (approvals-waiting line) appears % time(s), expected exactly 1',
      (length(v_def) - length(replace(v_def, a4, ''))) / nullif(length(a4),0); end if;

  v_new := replace(replace(replace(replace(v_def, a1, b1), a2, b2), a3, b3), a4, b4);
  if v_new = v_def then raise exception 'the four replacements changed nothing'; end if;
  execute v_new;
end $$;
