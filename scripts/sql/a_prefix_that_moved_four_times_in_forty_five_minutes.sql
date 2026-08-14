-- A "BYTE-STABLE" PREFIX THAT MOVED FOUR TIMES IN FORTY-FIVE MINUTES.
--
-- WHAT WAS ALREADY TRUE. agent_brain splits its system prompt into a stable half and a volatile
-- half, passes the stable half as sys_stable, and ai_gateway stamps cache_control on exactly that
-- block. All of that plumbing works. decision_policy.prompt_cache_enabled is FALSE, and the note
-- in ai_gateway says to re-measure with the split working and then move the switch.
--
-- WHY THE SWITCH MUST NOT SIMPLY BE MOVED. Measured on production 14 Aug 2026, hashing the first
-- 19,500 characters that fn_agent_context_capped returns for `procurement`:
--
--     03:10  a7f351e2402d7924c753b8311f19f338
--     03:18  03d70254f5c241f86a4def35cb4a8d39
--     03:30  d2eaa6c942ba0f34fce9e2fb937faa54
--     03:55  b26a841a215976cb3035b08f7aac6188
--
-- Four distinct prefixes in forty-five minutes for the same employee. At 03:55 the same hash came
-- back for three different questions, so it is NOT the question — the block genuinely is
-- query-independent, exactly as fn_agent_context_capped intends. It is TIME. The head contains
-- '# YOUR CURRENT WORKLOAD (live)', '# WHAT THE COMPANY IS WORRIED ABOUT - its own live risk
-- register' and '## Pricing & fees (LIVE — auto-synced)' — three sections whose own headings say
-- live — and org_tasks moved from 999 to 1,014 rows during that same window.
--
-- A provider prompt cache pays only on a BYTE-IDENTICAL prefix. A block that changes every few
-- minutes is the worst possible input to one: every call buys a cache WRITE at 1.25x the input
-- rate and reads none of it back. Turning prompt_cache_enabled on against this block would have
-- RAISED the bill, which is the opposite of what the switch is for, and the 0.1% hit rate already
-- in ai_cost_log is that fact showing up in the ledger.
--
-- The comment in fn_agent_context_capped says "head is left() to a CONSTANT length, so for a given
-- agent and budget these bytes are identical on every call". Constant LENGTH is not constant
-- BYTES. That is the whole defect, and it is invisible to any check that looks at one call.
--
-- THE FIX: STOP ASSEMBLING THE PREFIX AND START REMEMBERING IT.
-- fn_agent_context is 400 lines with roughly a dozen `order by <non-unique key> limit N` reads and
-- three sections that are live by design. Making that deterministic is neither possible nor
-- desirable — the employee SHOULD see a live risk register. What is wrong is asking a live
-- generator for a cacheable constant. So the head is computed on a schedule, stored, and served
-- byte-identical until the next refresh. Between refreshes it cannot drift, because nothing
-- recomputes it.
--
-- NOTHING BECOMES STALE THAT MATTERS. agent_brain already appends, in the VOLATILE half of the
-- same prompt and on every single turn: the LIVE DATA SNAPSHOT ("captured just now" — suppliers,
-- customers, inquiries, quotes, approvals, KYC, refunds, security events), the handoff inbox,
-- LAYER 2b/2c retrieved for this question, and the kb_search pass. The live operational figures
-- the employee is told to quote from are in that half and are unaffected by this change.
--
-- IT ALSO TAKES THE ASSEMBLY OFF THE HOT PATH. fn_agent_context('procurement') is the routine that
-- once blew an 8-second statement_timeout and needed two new indexes to reach 765 ms. Every
-- agent_brain turn pays that. Now one hourly job pays it once per employee.
--
-- FAIL-OPEN, ALWAYS. No stored row, or a stored row older than the staleness bound, means the
-- previous behaviour exactly: assemble live and serve it. A cache miss here must never be an
-- employee without its context — that failure has already happened once on this path and cost
-- three weeks of employees answering as nobody in particular.

create table if not exists agent_context_head (
  agent_key   text primary key,
  head        text        not null,
  head_md5    text        not null,
  head_chars  integer     not null,
  built_at    timestamptz not null default now(),
  changed_at  timestamptz not null default now()
);
comment on table agent_context_head is
  'The byte-stable prefix of each employee''s standing context, so a provider prompt cache can '
  'actually hit it. Refreshed on a schedule by fn_agent_context_head_refresh(); read by '
  'fn_agent_context_capped(). changed_at moves only when the bytes actually change, so it is the '
  'honest answer to "how often does this prefix really move".';

alter table agent_context_head enable row level security;

-- The budget is a constant in two places or it is not a stable prefix. 19500 = 24000 - 4500, the
-- same v_want - v_reserve fn_agent_context_capped computes; agent_brain is the only caller and it
-- asks for 24000. Any other budget falls through to live assembly rather than serving a prefix
-- built for a different size.
create or replace function public.fn_agent_context_head_refresh()
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  r record; v_head text; v_md5 text; v_prev text;
  n_seen int := 0; n_changed int := 0; n_failed int := 0;
begin
  -- Only employees that have actually reasoned recently. Refreshing all 93 would spend a minute of
  -- CPU an hour building prefixes nothing reads; an employee that starts working is picked up on
  -- the next tick and serves live context until then, which is what it gets today anyway.
  for r in
    select distinct c.agent_key
      from ai_cost_log c
     where c.fn = 'agent_brain' and c.agent_key is not null
       and c.occurred_at > now() - interval '14 days'
  loop
    begin
      v_head := left(public.fn_agent_context(r.agent_key, 24000), 19500);
      if v_head is null or length(v_head) < 500 then n_failed := n_failed + 1; continue; end if;
      n_seen := n_seen + 1;
      v_md5  := md5(v_head);
      -- Read the prior hash BEFORE the upsert: asking afterwards always says "unchanged", because
      -- the upsert has already written the value being compared against.
      select h.head_md5 into v_prev from agent_context_head h where h.agent_key = r.agent_key;
      if v_prev is distinct from v_md5 then n_changed := n_changed + 1; end if;
      insert into agent_context_head (agent_key, head, head_md5, head_chars)
      values (r.agent_key, v_head, v_md5, length(v_head))
      on conflict (agent_key) do update
        set head       = excluded.head,
            head_md5   = excluded.head_md5,
            head_chars = excluded.head_chars,
            built_at   = now(),
            changed_at = case when agent_context_head.head_md5 = excluded.head_md5
                              then agent_context_head.changed_at else now() end;
    exception when others then
      -- One employee whose context cannot be built must not stop the other thirteen.
      n_failed := n_failed + 1;
    end;
  end loop;
  return jsonb_build_object('refreshed', n_seen, 'changed', n_changed, 'failed', n_failed);
end $$;

revoke execute on function public.fn_agent_context_head_refresh() from public, anon, authenticated;

-- Serve the stored prefix. Patched, not retyped: fn_agent_context_capped is short but its exact
-- text is the contract agent_brain splits on, so only the two lines that fetch the head change.
do $mig$
declare
  src text; before text;
  a_call constant text := '    v_raw := public.fn_agent_context(p_agent_key, v_want, p_query);';
begin
  src := pg_get_functiondef('public.fn_agent_context_capped(text,integer,text)'::regprocedure);

  -- Declare the two locals alongside the existing ones.
  before := src;
  src := replace(src, '  v_note   text;',
       '  v_note   text;' || E'\n'
    || '  -- THE STORED PREFIX. See scripts/sql/a_prefix_that_moved_four_times_in_forty_five_minutes.sql:' || E'\n'
    || '  -- the head used to be reassembled per call and drifted four times in forty-five minutes, so' || E'\n'
    || '  -- the provider cache wrote on every call and read on none.' || E'\n'
    || '  v_stored text;' || E'\n'
    || '  -- Older than this and we assemble live rather than serve a prefix nobody refreshed. The' || E'\n'
    || '  -- refresh runs hourly; three hours means the job has been broken for three ticks.' || E'\n'
    || '  c_head_max_age constant interval := interval ''3 hours'';');
  if src = before then raise exception 'anchor (v_note declaration) not found in fn_agent_context_capped'; end if;

  -- Take the stored head when one is fresh and the budget matches the one it was built for.
  before := src;
  src := replace(src, a_call, a_call || E'\n'
    || E'\n'
    || '    -- Fail-open: no row, a stale row, or a different budget all fall through to the live head' || E'\n'
    || '    -- computed below, which is exactly the pre-14-Aug behaviour.' || E'\n'
    || '    if v_want = 24000 then' || E'\n'
    || '      select h.head into v_stored from agent_context_head h' || E'\n'
    || '       where h.agent_key = p_agent_key and h.built_at > now() - c_head_max_age' || E'\n'
    || '         and h.head_chars = 19500;' || E'\n'
    || '    end if;');
  if src = before then raise exception 'anchor (3-arg fn_agent_context call) not found in fn_agent_context_capped'; end if;

  -- The one place the head is cut. Serve the stored bytes when we have them.
  before := src;
  src := replace(src,
    '  return left(v_head, v_room) || v_mark || v_note ||',
    '  return coalesce(v_stored, left(v_head, v_room)) || v_mark || v_note ||');
  if src = before then raise exception 'anchor (head truncation in the return) not found in fn_agent_context_capped'; end if;

  execute src;
end $mig$;
