-- F20 - the founder is a verified auth subject, not a typed string
--
-- PCCR-003. THE ONE PHASE C AMENDMENT THE FOUNDER HAS APPROVED, IN HIS OWN WORDS, 21 Aug 2026:
--
--     "Do not request a new founder secret. Do not use the founder's email address as
--      authentication proof. The approved design is Supabase Auth JWT identity. Use:
--      verified JWT -> verified auth subject (sub) -> server-side lookup against the enabled
--      founder identity -> founder action."
--
-- E39 recorded the finding and refused to paper over it:
--
--     set local role service_role;
--     select public.fn_phase_c_require_founder('management@quotesdone.com');   -- PASSED_AS
--
-- That routine gates fn_kernel_cancel, fn_founder_command_clarify, fn_founder_command_control and
-- fn_phase_c_refund_decision_guard. The founder's standing rule is that every refund needs him, at
-- any amount. So the estate's model of "the founder approved this" was "somebody typed his email",
-- and his email is a plaintext literal in this repository's own committed history.
--
-- WHAT REPLACES IT. p_actor stops being the source of the identity and becomes an ASSERTION that
-- must match one. The identity is resolved from a verified auth subject, by one of two routes, and
-- from nothing else:
--
--   ROUTE A -- auth.uid(). A request that arrived at PostgREST with the founder's own bearer token
--   carries a subject PostgREST has already verified against the project's JWT secret. Nothing in
--   this database can manufacture it and no caller can set it.
--
--   ROUTE B -- the server path. os_api verifies the JWT itself (supabase.auth.getUser(token), a
--   200 from the auth server), then calls fn_phase_c_founder_subject_bind with ONLY the verified
--   subject. The bind resolves it against phase_c_founder_identity.auth_user_id where active, writes
--   an audit row carrying the current txid, and puts that row's id in a transaction-local GUC.
--
-- WHY NO SECRET AND NO HMAC HERE. The GUC carries an audit-row id and nothing else, and the
-- verifier requires that row to name txid_current(). A caller who sets the GUC by hand must point
-- it at an event row created in THIS transaction, and the only routine that creates one is the bind
-- -- which refuses any subject that is not an enabled founder. So there is nothing to forge and,
-- per the founder's instruction, no new secret is requested, placed in source, in database prose,
-- in a prompt or in a test file.
--
-- WHAT DOES NOT CHANGE. The founder register is still not writable by service_role (E38). The
-- freeze amendment approver still has to resolve to an active founder identity (E36) and is still
-- re-resolved on every read (E38). fn_refund_decide still needs the founder. What changes is that
-- knowing his email is no longer sufficient to be him.
--
-- THE RESIDUAL, STATED RATHER THAN HIDDEN. Route B trusts os_api, which holds service_role. Anyone
-- else holding service_role could call the bind with the founder's auth subject if they knew it.
-- That is the boundary the founder's own approved design draws, and it is a strictly smaller
-- surface than the one it replaces: a uuid that appears in no committed file, versus an email
-- address that appears in several. Route A has no such residual and is preferred wherever a real
-- bearer token can reach the database.

-- ================================================================================================
-- 1. THE REGISTER LEARNS THE AUTH SUBJECT
-- ================================================================================================
ALTER TABLE public.phase_c_founder_identity
  ADD COLUMN IF NOT EXISTS auth_user_id uuid;

COMMENT ON COLUMN public.phase_c_founder_identity.auth_user_id IS
  'THE SUPABASE AUTH SUBJECT THIS FOUNDER IDENTITY IS. Populated from auth.users by email. '
  'fn_phase_c_require_founder resolves the founder from a VERIFIED subject -- auth.uid(), or one '
  'os_api verified and bound -- and matches it here. The email column is no longer authentication '
  'proof (PCCR-003, founder-approved 21 Aug 2026).';

UPDATE public.phase_c_founder_identity f
   SET auth_user_id = u.id
  FROM auth.users u
 WHERE lower(u.email) = lower(f.identity)
   AND f.kind = 'email'
   AND f.auth_user_id IS DISTINCT FROM u.id;

-- ================================================================================================
-- 2. THE AUDIT OF EVERY BOUND SUBJECT
-- ================================================================================================
CREATE TABLE IF NOT EXISTS public.phase_c_founder_auth_event (
  event_id     bigserial   PRIMARY KEY,
  auth_subject uuid        NOT NULL,
  identity     text        NOT NULL REFERENCES public.phase_c_founder_identity(identity),
  route        text        NOT NULL CHECK (route in ('server_verified_subject')),
  txid         bigint      NOT NULL,
  bound_by     text        NOT NULL,
  bound_at     timestamptz NOT NULL DEFAULT now()
);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_c_founder_auth_event FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_c_founder_auth_event FROM anon, authenticated, service_role;

COMMENT ON TABLE public.phase_c_founder_auth_event IS
  'EVERY FOUNDER SUBJECT EVER BOUND BY THE SERVER PATH. One row per '
  'fn_phase_c_founder_subject_bind call, naming the verified auth subject, the founder identity it '
  'resolved to, the transaction it is bound to and the role that bound it. The transaction-local '
  'GUC carries this row''s id, and the verifier requires the row to name txid_current() -- so a '
  'caller who sets the GUC by hand must point it at a row only the bind could have written (F20).';

INSERT INTO public.kernel_write_authority (table_name, routine_name, why) VALUES
  ('phase_c_founder_auth_event', 'fn_phase_c_founder_subject_bind',
   'The only routine that binds a verified founder auth subject to a transaction. The audit row and the context are written in the same statement, so a bound context cannot exist without the audit of who bound it.')
ON CONFLICT DO NOTHING;

DROP TRIGGER IF EXISTS z10_kernel_write_guard ON public.phase_c_founder_auth_event;
CREATE TRIGGER z10_kernel_write_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.phase_c_founder_auth_event
  FOR EACH ROW EXECUTE FUNCTION public.fn_kernel_write_guard();

REVOKE TRUNCATE ON public.phase_c_founder_auth_event FROM PUBLIC, anon, authenticated, service_role;
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_c_founder_auth_event;
CREATE TRIGGER z00_kernel_truncate_guard
  BEFORE TRUNCATE ON public.phase_c_founder_auth_event
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();

-- ================================================================================================
-- 3. THE SERVER PATH: os_api verified the JWT, and passes ONLY the subject
-- ================================================================================================
CREATE OR REPLACE FUNCTION public.fn_phase_c_founder_subject_bind(p_subject uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id text; v_ev bigint;
begin
  if current_user in ('anon','authenticated') then
    raise exception 'fn_phase_c_founder_subject_bind: % may not bind a founder subject; this is the server path (pd_founder_bind_untrusted_caller)',
      current_user using errcode = '42501';
  end if;
  if p_subject is null then
    raise exception 'fn_phase_c_founder_subject_bind: a verified auth subject is required, and null is not one'
      using errcode = '28000';
  end if;

  select f.identity into v_id
    from public.phase_c_founder_identity f
   where f.auth_user_id = p_subject and f.active and f.kind = 'email';
  if v_id is null then
    raise exception 'not the founder: auth subject % does not resolve to an enabled founder identity', p_subject
      using errcode = '28000';
  end if;

  insert into public.phase_c_founder_auth_event
    (auth_subject, identity, route, txid, bound_by)
  values (p_subject, v_id, 'server_verified_subject', txid_current(), current_user)
  returning event_id into v_ev;

  perform set_config('app.phase_c_founder_auth_event', v_ev::text, true);
  return jsonb_build_object('ok', true, 'identity', v_id, 'event_id', v_ev,
    'note','transaction-local; the verifier requires this event to name the current txid');
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_c_founder_subject_bind(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_c_founder_subject_bind(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_phase_c_founder_subject_bind(uuid) TO service_role;

-- ================================================================================================
-- 4. THE GUARD ITSELF
-- ================================================================================================
CREATE OR REPLACE FUNCTION public.fn_phase_c_require_founder(p_actor text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_sub    uuid;
  v_id     text;
  v_ev     bigint;
  v_route  text;
begin
  -- ---- ROUTE A: a bearer token PostgREST already verified -------------------------------------
  -- auth.uid() is null for a service_role connection and for anything that did not arrive with a
  -- user JWT. It cannot be set by a caller.
  begin
    v_sub := auth.uid();
  exception when others then
    v_sub := null;
  end;
  if v_sub is not null then
    select f.identity into v_id
      from public.phase_c_founder_identity f
     where f.auth_user_id = v_sub and f.active and f.kind = 'email';
    v_route := 'auth.uid()';
  end if;

  -- ---- ROUTE B: the server path bound a subject it verified ------------------------------------
  if v_id is null then
    v_ev := nullif(btrim(current_setting('app.phase_c_founder_auth_event', true)),'')::bigint;
    if v_ev is not null then
      select e.identity, e.auth_subject into v_id, v_sub
        from public.phase_c_founder_auth_event e
        join public.phase_c_founder_identity f on f.identity = e.identity
       where e.event_id = v_ev
         -- BOUND TO THIS TRANSACTION. A GUC pointing at an event from another transaction is not a
         -- session: it is a value a caller typed.
         and e.txid = txid_current()
         and f.active and f.kind = 'email';
      v_route := 'fn_phase_c_founder_subject_bind';
    end if;
  end if;

  if v_id is null then
    -- E39's vector, refused: knowing the email is no longer being the founder.
    raise exception 'not the founder: no verified auth subject on this call. The founder is resolved from auth.uid() or from a subject os_api verified and bound with fn_phase_c_founder_subject_bind; a caller-supplied identity is not authentication. (PCCR-003)'
      using errcode = '28000',
            hint = 'Call with the founder''s bearer token so auth.uid() resolves, or verify the JWT in os_api and bind the verified subject first.';
  end if;

  -- p_actor is now an ASSERTION, not a source. Supplying one that disagrees with the verified
  -- identity is a caller claiming to be someone else and is refused; supplying none is fine.
  if coalesce(btrim(p_actor),'') <> '' and lower(btrim(p_actor)) <> lower(v_id) then
    raise exception 'not the founder: the call asserts identity % and the verified auth subject resolves to %',
      lower(btrim(p_actor)), v_id using errcode = '28000';
  end if;

  return v_id;
end $function$;

COMMENT ON FUNCTION public.fn_phase_c_require_founder(text) IS
  'THE FOUNDER, RESOLVED FROM A VERIFIED AUTH SUBJECT. Route A is auth.uid(); route B is a subject '
  'os_api verified against Supabase Auth and bound with fn_phase_c_founder_subject_bind. p_actor is '
  'an assertion that must MATCH the verified identity and is never the source of it -- E39 measured '
  'that typing the founder''s email returned PASSED_AS from service_role, and that this routine '
  'gates fn_kernel_cancel and the refund decision guard. PCCR-003, founder-approved 21 Aug 2026.';

-- ================================================================================================
-- 5. THE BOARD
-- ================================================================================================
-- ROUTINE REMOVED 7 September 2026. public.fn_phase_c_founder_auth_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


COMMENT ON FUNCTION public.fn_phase_c_founder_auth_state() IS
  'THE FOUNDER AUTHENTICATION BOARD. Every enabled founder identity carries an auth subject; '
  'fn_phase_c_require_founder no longer contains the string-resolution E39 demonstrated; the bind '
  'is not executable by anon or authenticated; and no bind audit row is committed on production '
  '(every probe of this path runs inside a transaction that is aborted) (F20).';
