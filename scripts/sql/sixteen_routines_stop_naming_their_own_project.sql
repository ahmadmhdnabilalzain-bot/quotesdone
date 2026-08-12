-- Sixteen routines stop naming their own project — 12 Aug 2026
--
-- apply_sql now refuses to promote any routine carrying a literal https://<ref>.supabase.co URL,
-- because promoting one repoints the production copy at staging and nothing fails visibly. Three of
-- the nineteen were converted by hand (fn_ai_trainer, and the two triggers on the demand and supply
-- critical path). These are the remaining sixteen.
--
-- CORRECTION, made before this shipped: I first wrote here that none of the sixteen was a trigger.
-- Two are — qd_sign_customer and qd_sign_supplier, both live and attached, both on the
-- Terms-acceptance path — and qd_project_ref() RAISES when it cannot resolve. Raising there would
-- have made accepting the Terms fail. They are given the non-raising treatment in
-- the_two_signing_triggers_must_never_refuse_a_signature.sql; the reasoning is in that file. The
-- other fourteen are scheduled or internally-called routines, where failing loudly is correct.
--
-- WHY A HELPER RATHER THAN SIXTEEN HAND EDITS. Every one of the sixteen has exactly ONE URL,
-- measured. Introducing a local variable would mean rewriting sixteen declare blocks and sixteen
-- bodies by hand — 26,000 characters retyped, where a single transcription slip inside a
-- SECURITY DEFINER routine is a silent defect. qd_project_ref() turns the change into a substitution
-- inside one existing string expression:
--
--   (REF below stands for the twenty-letter project ref — it is not spelled out, because qd_guard
--    rightly refuses to apply any SQL file that names production, and it caught this comment.)
--   url := 'https://REF.supabase.co/functions/v1/x'
--   url := 'https://'||qd_project_ref()||'.supabase.co/functions/v1/x'
--
-- so the rewrite touches one substring per routine and leaves every other byte identical. The DO
-- block below performs exactly that substitution against pg_get_functiondef and re-executes the
-- result, which is why it is safer than retyping: it CANNOT alter anything but the URL.
--
-- The block runs independently on each project, so each rewrites its own definitions — and because
-- the result contains no ref at all, both projects converge on identical text and become promotable.
--
-- qd_project_ref() RAISES rather than returning null. These sixteen are all background routines
-- where failing loudly is right; the two triggers were deliberately given the opposite treatment,
-- skipping the call rather than refusing a customer's RFQ or a supplier's approval, because a retry
-- sweep stands behind each of them. Both projects were checked to hold app_secrets.project_ref with
-- the correct value before this ran.

create or replace function public.qd_project_ref()
returns text
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_ref text;
begin
  select value into v_ref from app_secrets where key = 'project_ref';
  if v_ref is null then
    select substring(command from 'https://([a-z]+)[.]supabase[.]co') into v_ref
      from cron.job where command like '%supabase.co/functions/v1/%' limit 1;
  end if;
  if v_ref is null then
    raise exception 'qd_project_ref: cannot determine the Supabase project ref. Set app_secrets.project_ref.';
  end if;
  return v_ref;
end $function$;

revoke all on function public.qd_project_ref() from public, anon, authenticated;

do $rewrite$
declare
  r record;
  v_def text;
  v_new text;
  v_done int := 0;
begin
  for r in
    select p.oid, p.proname, pg_get_functiondef(p.oid) as def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind = 'f'
       and p.proname <> 'qd_project_ref'
       and pg_get_functiondef(p.oid) ~ 'https://[a-z]{20}[.]supabase[.]co'
     order by p.proname
  loop
    v_def := r.def;
    -- One substitution, and only inside the URL literal. Nothing else in the body is touched.
    -- 'https://xxx.supabase.co/functions/v1/y'
    --   becomes
    -- 'https://' || public.qd_project_ref() || '.supabase.co/functions/v1/y'
    -- The replacement closes the original literal after the scheme, concatenates the derived ref,
    -- and reopens it before the rest of the path, so the surrounding quotes stay exactly where the
    -- routine already had them.
    v_new := regexp_replace(v_def,
                            'https://[a-z]{20}\.supabase\.co',
                            'https://'' || public.qd_project_ref() || ''.supabase.co',
                            'g');
    if v_new = v_def then
      raise exception 'rewrite produced no change for %', r.proname;
    end if;
    if v_new ~ 'https://[a-z]{20}\.supabase\.co' then
      raise exception 'rewrite left a literal ref behind in %', r.proname;
    end if;
    execute v_new;
    v_done := v_done + 1;
  end loop;

  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.prokind = 'f'
                and pg_get_functiondef(p.oid) ~ 'https://[a-z]{20}[.]supabase[.]co') then
    raise exception 'a literal project ref survived the rewrite';
  end if;

  raise notice 'qd_project_ref: rewrote % routine(s); 0 literal refs remain', v_done;
end
$rewrite$;
