-- TODAY'S NEW TABLES AND ROUTINES GET THE LOCKS THE ESTATE EXPECTS.
--
-- CI refused the branch, and it was right to. Supabase's own security advisor reported 14 findings
-- that did not exist this morning, and every one of them is from work applied today:
--
--   7 tables with RLS ENABLED and NO POLICY
--     ceo_weekly_report · founder_instruction · it_refusal_policy · kb_embed_inflight
--     kb_embed_priority · price_benchmark · supplier_response_watch
--
--   7 routines with a MUTABLE search_path
--     fn_ar_norm · fn_ceo_binding_constraint · fn_founder_instruction_needs_evidence
--     fn_it_refusal_is_policy · fn_refund_document · fn_refund_document_coverage
--     fn_refund_execution_requires_ceo_approval
--
-- WHY EACH ONE MATTERS, because "the advisor said so" is not a reason to change production.
--
-- RLS ENABLED WITH NO POLICY denies everyone by default, so this is not an open door — and that is
-- exactly why it is worth fixing rather than waving through. A table in that state is
-- indistinguishable from one where somebody meant to write a policy and forgot, and the next
-- person to find it cannot tell "deliberately service_role only" from "unfinished". These seven
-- ARE deliberately service_role only: they are the seats' own working records, and no browser
-- should ever read them. An explicit policy says so in the schema instead of in someone's memory.
--
-- A MUTABLE search_path IS THE REAL ONE. A SECURITY DEFINER routine without a fixed search_path
-- resolves unqualified names against whatever the CALLER's search_path says. Anyone able to create
-- a schema earlier in that path can shadow a table or an operator and have the routine execute
-- their object with the definer's privileges. fn_refund_execution_requires_ceo_approval is the
-- trigger that decides whether money may move; it is the last routine in this estate that should
-- resolve a name it did not pin.
--
-- fn_ar_norm and fn_ceo_binding_constraint are not SECURITY DEFINER, so the hijack does not apply
-- to them — but a pinned search_path is free and makes their behaviour independent of the caller,
-- which for an IMMUTABLE function it is also correctness rather than only hygiene.
--
-- NOTHING'S BEHAVIOUR CHANGES. Every routine is re-declared with its body byte-identical to what is
-- live; only the SET clause is added. Every policy grants exactly what the table already had:
-- nothing, to anon and authenticated.

-- ── 1. SAY OUT LOUD THAT THESE ARE THE SEATS' OWN RECORDS ───────────────────────────────────────
do $do$
declare t text; n int := 0;
begin
  foreach t in array array[
    'ceo_weekly_report','founder_instruction','it_refusal_policy',
    'kb_embed_inflight','kb_embed_priority','price_benchmark','supplier_response_watch']
  loop
    if to_regclass('public.' || t) is null then
      raise exception 'POSITIVE CONTROL FAILED: public.% does not exist, so this file is describing a table that is not there', t;
    end if;
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_service_role_only', t);
    -- `to public using (false)` is the policy that MEANS "nobody but a role that bypasses RLS".
    -- service_role bypasses RLS, so the seats keep full access; anon and authenticated get nothing,
    -- which is what they already had — the difference is that it is now written down.
    execute format(
      'create policy %I on public.%I as permissive for all to public using (false) with check (false)',
      t || '_service_role_only', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    n := n + 1;
  end loop;
  raise notice '% tables now carry an explicit service-role-only policy', n;
end
$do$;

-- ── 2. PIN THE SEARCH PATH ──────────────────────────────────────────────────────────────────────
-- ALTER FUNCTION ... SET adds the clause without touching the body, so there is no chance of a
-- transcription error in a routine that decides whether money moves.
alter function public.fn_ar_norm(text)                                    set search_path to 'public', 'pg_temp';
alter function public.fn_ceo_binding_constraint(jsonb)                    set search_path to 'public', 'pg_temp';
alter function public.fn_founder_instruction_needs_evidence()             set search_path to 'public', 'pg_temp';
alter function public.fn_it_refusal_is_policy(text, jsonb)                set search_path to 'public', 'pg_temp';
alter function public.fn_refund_execution_requires_ceo_approval()         set search_path to 'public', 'pg_temp';

do $do$
declare r record; v_missing text[] := '{}'; v_fixed int := 0; v_pol int;
begin
  -- fn_refund_document and fn_refund_document_coverage take arguments this file should not guess
  -- at, so they are found rather than named.
  for r in select p.oid::regprocedure::text sig from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and p.proname in ('fn_refund_document','fn_refund_document_coverage')
  loop
    execute format('alter function %s set search_path to %L, %L', r.sig, 'public', 'pg_temp');
  end loop;

  -- ASSERT IT TOOK, for every one of the seven.
  for r in select p.proname, p.proconfig from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and p.proname in ('fn_ar_norm','fn_ceo_binding_constraint','fn_founder_instruction_needs_evidence',
                               'fn_it_refusal_is_policy','fn_refund_document','fn_refund_document_coverage',
                               'fn_refund_execution_requires_ceo_approval')
  loop
    if r.proconfig is null or not exists (select 1 from unnest(r.proconfig) c where c like 'search_path=%') then
      v_missing := v_missing || r.proname::text;
    else
      v_fixed := v_fixed + 1;
    end if;
  end loop;
  if array_length(v_missing,1) is not null then
    raise exception 'these still have a mutable search_path: %', array_to_string(v_missing, ', ');
  end if;

  select count(*) into v_pol from pg_policies
   where schemaname = 'public'
     and tablename in ('ceo_weekly_report','founder_instruction','it_refusal_policy',
                       'kb_embed_inflight','kb_embed_priority','price_benchmark','supplier_response_watch');
  if v_pol < 7 then raise exception 'only % of 7 tables carry a policy', v_pol; end if;

  -- POSITIVE CONTROL: the seats must still be able to do their work. A lock that locks out the
  -- company is not a fix.
  if (select count(*) from public.founder_instruction) = 0 then
    raise exception 'the instruction ledger reads empty to service_role — the policy locked out the estate';
  end if;
  if (select public.fn_ar_norm('الشركة')) is null then
    raise exception 'fn_ar_norm stopped answering after its search_path was pinned';
  end if;

  raise notice 'LOCKED. % routines have a pinned search_path, % tables carry an explicit service-role-only policy, and the seats still read their own records.',
    v_fixed, v_pol;
end
$do$;
