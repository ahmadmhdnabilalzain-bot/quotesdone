-- F01 - a test context an untrusted caller cannot manufacture
--
-- THE FOUNDER'S RULING, 21 Aug 2026, section A: the zero-persistence scenario factory
-- "must be callable only by a trusted audited Phase D test operation... not callable by
--  public, anon, ordinary authenticated users, frontend code, or arbitrary service-role callers
--  without the approved audit context. Use a transaction-local protected test context that an
--  untrusted caller cannot manufacture."
--
-- WHAT WAS THERE BEFORE, AND WHY IT IS NOT A CONTEXT.
--
--     if coalesce(current_setting('app.phase_d_test_context', true),'') <> 'on' then raise ...
--
-- `app.phase_d_test_context` is a plain GUC. ANY caller can set it:
--
--     set local app.phase_d_test_context = 'on';           -- service_role: ACCEPTED
--     select public.fn_phase_d_fixture_scenario('{"label":"x","execution_context":"test"}');
--
-- So the "protected context" was a string the caller supplied about itself. That is the same shape
-- as E39 -- fn_phase_c_require_founder resolving a caller-supplied email -- and the same shape as
-- E38 -- a register the guard trusted, writable by the caller it was guarding against. The estate
-- has now met this defect three times, and this is the fourth surface.
--
-- WHAT REPLACES IT.
--
-- The GUC still carries the context, because a transaction-local GUC is the only place a Postgres
-- session can put a per-transaction fact. What changes is that its VALUE is now unforgeable:
--
--   token = hmac( txid_current() || ':' || operation_key || ':' || fixture_run_id, secret, sha256 )
--
-- The secret lives in public.phase_d_fixture_secret, which grants SELECT to nobody -- not PUBLIC,
-- not anon, not authenticated, not service_role. Only a SECURITY DEFINER routine owned by the
-- database owner can read it. A caller who sets the GUC by hand sets it to a value that does not
-- verify, and every consumer calls fn_phase_d_fixture_context(), which recomputes and compares.
--
-- Binding the token to txid_current() is what makes it transaction-local in fact and not just by
-- convention: a token minted in one transaction does not verify in the next, so it cannot be
-- copied out of a log and replayed.
--
-- WHO MAY MINT ONE. fn_phase_d_test_context_open refuses unless:
--   * the caller is not anon / authenticated;
--   * the named operation_key is a row in public.phase_d_test_operation with enabled = true;
--   * that register is NOT writable by anon, authenticated or service_role -- E38's lesson applied
--     before the fact rather than after an auditor demonstrates it.
--
-- Every mint writes an audit row. The audit table is guarded by fn_kernel_write_guard through
-- public.kernel_write_authority, so the only routine that can write it is the minting routine
-- itself, and it carries the truncate guard every enforcing table in this estate carries (E37).
--
-- ZERO COST. Nothing here calls a provider. hmac() is pgcrypto, which Supabase installs into the
-- "extensions" schema; it is schema-qualified at every call site rather than reached through
-- search_path, because a routine that finds its crypto by search_path is one shadowed schema away
-- from signing with something else.

-- ---- the secret nobody can read ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.phase_d_fixture_secret (
  singleton  boolean     PRIMARY KEY DEFAULT true CHECK (singleton),
  secret     bytea       NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- REVOKE FROM PUBLIC FIRST. A grant held through PUBLIC makes a revoke from a named role a silent
-- no-op, and this estate has been caught by exactly that.
REVOKE ALL ON public.phase_d_fixture_secret FROM PUBLIC;
REVOKE ALL ON public.phase_d_fixture_secret FROM anon, authenticated, service_role;

INSERT INTO public.phase_d_fixture_secret (singleton, secret)
VALUES (true, extensions.gen_random_bytes(32))
ON CONFLICT (singleton) DO NOTHING;

COMMENT ON TABLE public.phase_d_fixture_secret IS
  'THE KEY THE PHASE D FIXTURE CONTEXT IS SIGNED WITH. One row, 32 random bytes, readable by no '
  'role at all: SELECT is revoked from PUBLIC, anon, authenticated and service_role, so only a '
  'SECURITY DEFINER routine owned by the database owner can reach it. This is what makes '
  'app.phase_d_fixture_context a context a caller cannot manufacture rather than a string a caller '
  'sets about itself (F01).';

-- ---- the register of approved Phase D test operations -----------------------------------------
CREATE TABLE IF NOT EXISTS public.phase_d_test_operation (
  operation_key text        PRIMARY KEY,
  purpose       text        NOT NULL CHECK (length(btrim(purpose)) >= 40),
  enabled       boolean     NOT NULL DEFAULT true,
  added_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT phase_d_test_operation_key_shape
    CHECK (operation_key ~ '^pdop_[a-z0-9_]{3,60}$')
);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_d_test_operation FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_d_test_operation FROM anon, authenticated, service_role;

COMMENT ON TABLE public.phase_d_test_operation IS
  'THE APPROVED PHASE D TEST OPERATIONS. fn_phase_d_test_context_open refuses any operation_key '
  'that is not an enabled row here. Written only by a migration applied as the owner -- E38 found '
  'that a register writable by the caller it guards is not a register, and that finding is applied '
  'here before an auditor has to demonstrate it (F01).';

INSERT INTO public.phase_d_test_operation (operation_key, purpose) VALUES
  ('pdop_scenario_factory',
   'Build a zero-persistence Phase D scenario through the canonical object services inside a transaction that is aborted.'),
  ('pdop_workflow_drive',
   'Drive one or more frozen Phase B workflows through the kernel doors inside a transaction that is aborted.'),
  ('pdop_capability_fixture',
   'Submit a pre-authored capability result through the canonical capability-result acceptance service with provider_mode fixture.'),
  ('pdop_deliverable_build',
   'Regenerate a committed Phase D deliverable from production inside a transaction that is aborted.'),
  ('pdop_acceptance_probe',
   'An independent acceptance auditor probing a Phase D control inside a transaction that is aborted.')
ON CONFLICT (operation_key) DO NOTHING;

-- ---- the audit of every context that was ever opened ------------------------------------------
CREATE TABLE IF NOT EXISTS public.phase_d_test_context_grant (
  fixture_run_id    bigserial   PRIMARY KEY,
  operation_key     text        NOT NULL REFERENCES public.phase_d_test_operation(operation_key),
  label             text        NOT NULL CHECK (length(btrim(label)) >= 3),
  txid              bigint      NOT NULL,
  backend_pid       int         NOT NULL,
  granted_to        text        NOT NULL,
  session_user_name text        NOT NULL,
  opened_at         timestamptz NOT NULL DEFAULT now()
);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_d_test_context_grant FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_d_test_context_grant FROM anon, authenticated, service_role;

COMMENT ON TABLE public.phase_d_test_context_grant IS
  'EVERY PHASE D FIXTURE CONTEXT EVER MINTED. One row per fn_phase_d_test_context_open call, '
  'naming the approved operation, the label, the transaction id it is bound to and the role that '
  'asked. The fixture_run_id every fixture record carries is this row''s id, so a residue row can '
  'always be traced back to the operation that authorised the run that made it (F01).';

-- ---- the mint --------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_d_test_context_open(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_op    text := nullif(btrim(coalesce(p_input->>'operation_key','')),'');
  v_label text := nullif(btrim(coalesce(p_input->>'label','')),'');
  v_id    bigint;
  v_tok   text;
begin
  if v_op is null or v_label is null then
    raise exception 'fn_phase_d_test_context_open: operation_key and label are both required (pd_test_context_input_invalid)'
      using errcode = '22023';
  end if;

  -- The frontend and an ordinary signed-in user are refused before anything else is read. This is
  -- the same refusal fn_phase_d_fixture_scenario already made; it is repeated here because this
  -- routine is now the only door and a door must carry its own lock.
  if current_user in ('anon','authenticated') then
    raise exception 'fn_phase_d_test_context_open: % may not open a Phase D test context (pd_test_context_untrusted_caller)',
      current_user using errcode = '42501';
  end if;

  if not exists (select 1 from public.phase_d_test_operation o
                  where o.operation_key = v_op and o.enabled) then
    raise exception 'fn_phase_d_test_context_open: % is not an enabled approved Phase D test operation. A service-role caller with no approved audit context may not build fixtures. (pd_test_context_operation_unapproved)',
      v_op using errcode = '42501';
  end if;

  insert into public.phase_d_test_context_grant
    (operation_key, label, txid, backend_pid, granted_to, session_user_name)
  values (v_op, v_label, txid_current(), pg_backend_pid(), current_user, session_user)
  returning fixture_run_id into v_id;

  -- BOUND TO THE TRANSACTION. A token minted here does not verify in any other transaction, so it
  -- cannot be lifted out of a log, a query plan or an error message and replayed.
  select encode(extensions.hmac(convert_to(format('%s:%s:%s', txid_current(), v_op, v_id),'UTF8'), s.secret, 'sha256'), 'hex')
    into v_tok from public.phase_d_fixture_secret s where s.singleton;

  perform set_config('app.phase_d_fixture_context', format('%s.%s', v_id, v_tok), true);

  return jsonb_build_object(
    'ok', true, 'fixture_run_id', v_id, 'operation_key', v_op, 'label', v_label,
    'txid', txid_current(),
    'note', 'transaction-local; abort this transaction when finished. The token is bound to this '
         || 'txid and to nothing else.');
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_test_context_open(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_d_test_context_open(jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_test_context_open(jsonb) TO service_role;

COMMENT ON FUNCTION public.fn_phase_d_test_context_open(jsonb) IS
  'MINT A PROTECTED PHASE D FIXTURE CONTEXT. Refuses anon and authenticated outright, refuses any '
  'operation_key that is not an enabled row in public.phase_d_test_operation, writes an audit row, '
  'and sets app.phase_d_fixture_context to <fixture_run_id>.<hmac>. The hmac is over the current '
  'txid and is keyed by a secret no role can SELECT, so a caller who sets the GUC by hand sets a '
  'value fn_phase_d_fixture_context() does not accept (F01).';

-- ---- the verifier every consumer calls --------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_context()
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_raw text := nullif(btrim(current_setting('app.phase_d_fixture_context', true)),'');
  v_id  bigint;
  v_tok text;
  v_exp text;
  g     public.phase_d_test_context_grant%rowtype;
begin
  if v_raw is null then return null; end if;
  begin
    v_id := nullif(split_part(v_raw, '.', 1),'')::bigint;
  exception when others then
    return null;
  end;
  v_tok := nullif(split_part(v_raw, '.', 2),'');
  if v_id is null or v_tok is null then return null; end if;

  select * into g from public.phase_d_test_context_grant where fixture_run_id = v_id;
  if not found then return null; end if;
  -- A grant is only a context inside the transaction it was minted in.
  if g.txid <> txid_current() then return null; end if;

  select encode(extensions.hmac(convert_to(format('%s:%s:%s', g.txid, g.operation_key, g.fixture_run_id),'UTF8'), s.secret, 'sha256'), 'hex')
    into v_exp from public.phase_d_fixture_secret s where s.singleton;

  if v_exp is null or v_exp <> v_tok then return null; end if;
  return v_id;
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_fixture_context() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_d_fixture_context() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_fixture_context() TO service_role;

COMMENT ON FUNCTION public.fn_phase_d_fixture_context() IS
  'THE ACTIVE PHASE D FIXTURE RUN, OR NULL. Recomputes the hmac over the current txid and the '
  'audited grant row and compares it with app.phase_d_fixture_context. Returns null for an absent '
  'context, a hand-set GUC, a token from another transaction and a grant that does not exist. '
  'Every Phase D fixture path calls this instead of reading a GUC (F01).';

-- ---- the operation this context was opened for, for a routine that must check it ---------------
CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_operation()
 RETURNS text
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select g.operation_key from public.phase_d_test_context_grant g
   where g.fixture_run_id = public.fn_phase_d_fixture_context();
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_fixture_operation() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_d_fixture_operation() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_fixture_operation() TO service_role;

-- ---- the new audit table is enforcing, so it carries the guards enforcing tables carry ----------
-- E37: adding a trigger to a table moves it into the population fn_kernel_truncate_protection_state
-- watches, and it must arrive with a truncate guard and no TRUNCATE grant, or the board goes red on
-- a hole this file opened.
INSERT INTO public.kernel_write_authority (table_name, routine_name, why) VALUES
  ('phase_d_test_context_grant', 'fn_phase_d_test_context_open',
   'The only routine that mints a Phase D fixture context. The audit row and the token are written in the same statement, so a grant row cannot exist without the context that was handed out for it.')
ON CONFLICT DO NOTHING;

DROP TRIGGER IF EXISTS z10_kernel_write_guard ON public.phase_d_test_context_grant;
CREATE TRIGGER z10_kernel_write_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.phase_d_test_context_grant
  FOR EACH ROW EXECUTE FUNCTION public.fn_kernel_write_guard();

REVOKE TRUNCATE ON public.phase_d_test_context_grant FROM PUBLIC;
REVOKE TRUNCATE ON public.phase_d_test_context_grant FROM anon, authenticated, service_role;
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_d_test_context_grant;
CREATE TRIGGER z00_kernel_truncate_guard
  BEFORE TRUNCATE ON public.phase_d_test_context_grant
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();

REVOKE TRUNCATE ON public.phase_d_test_operation FROM PUBLIC;
REVOKE TRUNCATE ON public.phase_d_test_operation FROM anon, authenticated, service_role;
REVOKE TRUNCATE ON public.phase_d_fixture_secret FROM PUBLIC;
REVOKE TRUNCATE ON public.phase_d_fixture_secret FROM anon, authenticated, service_role;
