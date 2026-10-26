-- AUDIT 3.6 — Control Mode can be entered with no MFA at all.
--
-- public.control_mode_session carried exactly one constraint: its primary key. mfa_ref was
-- nullable, unreferenced and unchecked, and service_role held INSERT/UPDATE/DELETE on the table.
-- Every one of the 190 edge functions runs as service_role. So the whole challenge -> WhatsApp ->
-- verify path could be skipped by inserting a row:
--
--   insert into control_mode_session (actor_email, reason, expires_at, mfa_method)
--   values ('...', 'x', now() + interval '1 hour', 'anything');
--
-- and fn_control_mode_require() would then find an open session and allow the change. The MFA was
-- decoration: it was implemented correctly in fn_control_mode_open() and simply not required.
--
-- Locking the door needs three separate things, because any one of them alone is bypassable:
--   1. GRANTS  - only SECURITY DEFINER functions (owned by postgres) may write these tables. A
--                constraint cannot help if the caller is free to satisfy it by writing the rows
--                it references. Revoking on control_mode_session alone would leave the forgery
--                path "insert my own challenge, then open against it", so control_mode_challenge
--                and control_mode_identity are revoked too - registering an identity is itself a
--                way in, which fn_control_mode_challenge_start already says in its own error text.
--   2. SHAPE   - mfa_ref NOT NULL, referencing a real challenge, with a known mfa_method.
--   3. MEANING - a FK only proves the challenge EXISTS. The trigger below proves it was the
--                actor's own challenge and that it was actually consumed by an open, which is the
--                part that says a human read a code off a phone.
--
-- No rows exist yet (control_mode_session is empty), so nothing is backfilled or grandfathered.

alter table public.control_mode_session
  alter column mfa_ref set not null;

alter table public.control_mode_session
  add constraint control_mode_session_mfa_ref_fk
  foreign key (mfa_ref) references public.control_mode_challenge(id) on delete restrict;

-- One permitted method today. Adding a second (a passkey, say) must be a deliberate edit here,
-- not a string a caller picks.
alter table public.control_mode_session
  add constraint control_mode_session_mfa_method_ck
  check (mfa_method = 'control_mode_challenge');

create or replace function public.fn_control_mode_session_mfa_is_real()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare v public.control_mode_challenge%rowtype;
begin
  select * into v from public.control_mode_challenge where id = new.mfa_ref;
  if not found then
    raise exception 'control mode: mfa_ref % is not a challenge', new.mfa_ref using errcode = '23514';
  end if;
  if lower(btrim(v.admin_email)) <> lower(btrim(new.actor_email)) then
    raise exception 'control mode: challenge belongs to %, not %', v.admin_email, new.actor_email using errcode = '23514';
  end if;
  if v.purpose <> 'control_mode' then
    raise exception 'control mode: challenge % was issued for %, not control_mode', v.id, v.purpose using errcode = '23514';
  end if;
  -- fn_control_mode_open() stamps consumed_why='opened' immediately before inserting the session.
  -- Any other caller reaches this trigger with a challenge that is unconsumed, expired,
  -- superseded or attempts_exhausted - none of which prove a code was ever read off a phone.
  if v.consumed_at is null or coalesce(v.consumed_why,'') <> 'opened' then
    raise exception 'control mode: challenge % was not consumed by an open (consumed_why=%)',
      v.id, coalesce(v.consumed_why,'<null>') using errcode = '23514';
  end if;
  return new;
end $function$;

revoke all on function public.fn_control_mode_session_mfa_is_real() from public, anon, authenticated, service_role;

drop trigger if exists trg_control_mode_session_mfa_is_real on public.control_mode_session;
create trigger trg_control_mode_session_mfa_is_real
  before insert on public.control_mode_session
  for each row execute function public.fn_control_mode_session_mfa_is_real();

-- Writes go through the SECURITY DEFINER functions only. Every legitimate caller already does:
-- os_api, os_ops and refunds_api all reach Control Mode through fn_control_mode_* RPCs and never
-- touch these tables directly (verified across supabase/functions).
revoke insert, update, delete, truncate on public.control_mode_session   from service_role;
revoke insert, update, delete, truncate on public.control_mode_challenge from service_role;
revoke insert, update, delete, truncate on public.control_mode_identity  from service_role;
-- The audit trail stays appendable (the functions write it) but stops being rewritable.
revoke update, delete, truncate on public.control_mode_audit from service_role;

do $mig$
declare v_ok boolean; v_msg text;
begin
  -- Assert the hole is shut by trying to walk through it as the role that could.
  begin
    set local role service_role;
    insert into public.control_mode_session (actor_email, reason, expires_at, mfa_method)
    values ('forgery-probe@example.invalid', 'audit 3.6 probe', now() + interval '1 hour', 'control_mode_challenge');
    reset role;
    raise exception '3.6: service_role STILL inserted a Control Mode session - the hole is open';
  exception
    when insufficient_privilege then
      reset role; v_ok := true; v_msg := 'insufficient_privilege';
    when not_null_violation then
      reset role; v_ok := true; v_msg := 'not_null_violation on mfa_ref';
    when others then
      reset role;
      if sqlstate = 'P0001' and sqlerrm like '3.6:%' then raise; end if;
      v_ok := true; v_msg := sqlstate;
  end;
  if not v_ok then raise exception '3.6: probe did not fail'; end if;
  raise notice '3.6: forged Control Mode session rejected (%)', v_msg;

  -- And assert the legitimate shape is still expressible: constraints present, trigger armed.
  if not exists (select 1 from pg_constraint
                  where conrelid='public.control_mode_session'::regclass
                    and conname='control_mode_session_mfa_ref_fk')
    then raise exception '3.6: FK missing'; end if;
  if not exists (select 1 from pg_trigger
                  where tgrelid='public.control_mode_session'::regclass
                    and tgname='trg_control_mode_session_mfa_is_real')
    then raise exception '3.6: trigger missing'; end if;
  if exists (select 1 from information_schema.role_table_grants
              where table_schema='public' and table_name in
                    ('control_mode_session','control_mode_challenge','control_mode_identity')
                and grantee='service_role' and privilege_type in ('INSERT','UPDATE','DELETE'))
    then raise exception '3.6: service_role still holds a write grant'; end if;

  raise notice '3.6: mfa_ref is NOT NULL, references a consumed challenge owned by the same actor, and service_role cannot write the table';
end $mig$;
