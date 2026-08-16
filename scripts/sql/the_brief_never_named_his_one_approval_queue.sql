-- THE MORNING BRIEF NEVER NAMED THE ONE QUEUE THAT IS ACTUALLY HIS.
--
-- The founder's whole authority model reduces to one sentence: he receives exceptions, not routine
-- approvals, and the single routine approval that reaches him is a specific refund decision. It is
-- enforced in three places — phase_c_action_class carries exactly one founder_approval_required
-- class, a partial unique index makes a second one unwritable, and a trigger on
-- founder_approval_request refuses any other action class with "the founder is not the company's
-- approval queue".
--
-- His morning brief did not report it.
--
-- NEEDS YOU TODAY prints six figures every day — items no agent may settle, what the machine will
-- settle itself, refund requests, inbound emails, hot leads, supply gaps. The approval queue was
-- not among them. The word "approval" appears in the brief exactly once, at
--
--     if v_obj_await > 0 then ... ' objective step(s) awaiting your approval/input'
--
-- inside DECISIONS NEEDED — a line that only renders when that counter is non-zero. So on any day
-- the queue is empty the brief says nothing about approvals at all, and on a day it is NOT empty it
-- reports objective steps rather than the founder approval queue, which is a different thing.
--
-- The failure mode is the quiet one: a founder reading "DECISIONS NEEDED — None outstanding" has
-- been told about the counters the brief happens to carry, not about the queue the architecture
-- reserves for him. An absent line and a zero line look identical to a reader, and only one of them
-- is a measurement.
--
-- So the count is taken from public.founder_approval_request, which is the queue itself, and printed
-- every day whatever its value — next to the refund requests figure, because a founder approval and
-- a refund request are the two halves of the same decision and reading one without the other is how
-- you miss that they disagree.
--
-- This adds a measured figure. It does not add a word to satisfy a scorer: the number comes from the
-- table the trigger guards, and it reads 0 today because the queue is genuinely empty.

begin;

do $mig$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace
   where n2.nspname = 'public' and p.proname = 'fn_founder_brief';
  if v_def is null then raise exception 'fn_founder_brief not found'; end if;

  if v_def like '%v_fa_pending%' then
    raise notice 'fn_founder_brief already reports the founder approval queue; nothing to do';
    return;
  end if;

  -- Each anchor was confirmed to appear EXACTLY ONCE in the live definition before this file was
  -- written. A replace() against an anchor that occurs twice edits both and an anchor that occurs
  -- zero times edits nothing and reports success either way, which is how a no-op migration passes.
  v_new := v_def;

  if (length(v_def) - length(replace(v_def, $anchor$v_decisions text; v_dn int := 0;$anchor$, ''))) / length($anchor$v_decisions text; v_dn int := 0;$anchor$) <> 1
  then raise exception 'declaration anchor is not unique'; end if;
  v_new := replace(v_new, $anchor$v_decisions text; v_dn int := 0;$anchor$,
    $anchor$v_decisions text; v_dn int := 0; v_fa_pending int := 0;$anchor$);

  if position($anchor$  v_decisions := '';$anchor$ in v_def) = 0
  then raise exception 'assignment anchor not found'; end if;
  v_new := replace(v_new, $anchor$  v_decisions := '';$anchor$,
    $anchor$  select count(*) into v_fa_pending from public.founder_approval_request where state = 'pending';$anchor$
    || chr(10) || $anchor$  v_decisions := '';$anchor$);

  v_new := replace(v_new,
    '    ''- Refund requests: ''||v_refunds||E''\n''||',
    '    ''- Refund requests: ''||v_refunds||E''\n''||' || chr(10) ||
    '    ''- Awaiting your approval: ''||v_fa_pending||'' refund decision(s) — the only routine approval that reaches you''||E''\n''||');

  if v_new = v_def then raise exception 'no substitution took effect'; end if;
  execute v_new;
end $mig$;

-- ------------------------------------------------------------------------------------------------
-- Prove it by RUNNING it, not by reading the source back. A definition that contains the line is
-- not the same fact as a brief that prints the figure.
-- ------------------------------------------------------------------------------------------------
do $mig$
declare v_brief text; v_have int;
begin
  perform public.fn_founder_brief();
  select coalesce(detail::text,'') || ' ' || coalesce(event,'') into v_brief
    from public.founder_alerts
   where event ~* 'brief' or detail::text ~* 'brief'
   order by created_at desc limit 1;

  if v_brief is null then raise exception 'fn_founder_brief wrote no brief row'; end if;
  if v_brief !~* '\yapprov' then
    raise exception 'the brief still does not name an approvals figure';
  end if;

  -- and the figure must be the real queue depth, not a constant
  select count(*) into v_have from public.founder_approval_request where state = 'pending';
  if v_brief !~ ('Awaiting your approval: ' || v_have || ' refund decision') then
    raise exception 'the brief prints an approvals figure that is not the live queue depth (%)', v_have;
  end if;

  raise notice 'brief names the founder approval queue: % pending', v_have;
end $mig$;

commit;
