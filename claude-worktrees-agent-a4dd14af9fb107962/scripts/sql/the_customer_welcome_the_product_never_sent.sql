-- THE CUSTOMER WELCOME THE PRODUCT NEVER SENT (6 Sep 2026).
--
-- A real person registered on the live site at 07:38 UTC today (public.customers
-- e0dee407-456c-4d8d-be52-2512bd4b1074, email verified). The company opened W04 (customer
-- registration and onboarding), routed customer.registered to cs_onboarding, and the org_task lane
-- "determined" the task with executor NONE -- so NOTHING reached the customer. QuotesDone has never
-- sent a customer a welcome. That is the acting half of the founder's rule (2 Sep 2026): an
-- onboarding specialist who only *knows* a customer registered, and does nothing, is not doing the
-- job. A real onboarding specialist sends the first-request guidance the moment someone registers.
--
-- THE OWNER is cs_onboarding (org_role customer_onboarding, "Customer Onboarding Specialist";
-- event_subscription customer.registered -> cs_onboarding; docs/knowledge_audit/customer_experience.md
-- §4 "first-inquiry guidance"). This is that employee's deterministic act -- no model, no founder.
--
-- WHAT IT DOES. On every customer registration (AFTER INSERT on public.customers, which is where
-- customer.registered is emitted), fn_customer_welcome renders a branded welcome from LIVE facts --
-- the reveal rate from pricing_config, the refund rule linked to the published policy -- and queues
-- ONE notification. The shared renderer (send_outbox, email_customer template) applies the brand and
-- signature; this function supplies only the body, so a brand change made elsewhere flows through.
-- It routes to the CUSTOMER (to_role 'customer'), never the founder, and send_outbox refuses the
-- reserved @example.invalid demo domain before any provider call, so a rehearsal never emails anyone.
--
-- IDEMPOTENT: one welcome per address. FAIL-SAFE: the trigger can never abort a registration -- a
-- welcome that errors is swallowed, because a customer who could not be greeted must still be
-- created. The founder_mail_policy row registers the kind defensively so it can never be routed to
-- him even if a future path addressed one to an admin address.
--
--   node scripts/apply_sql.mjs scripts/sql/the_customer_welcome_the_product_never_sent.sql --apply --ddl

begin;

-- The kind is registered where notification kinds are enumerated. allowed_to_email=false means: if a
-- customer_welcome were ever addressed to the founder, it is NOT emailed to him -- it routes to an
-- owned task. A customer-facing welcome never reaches that path (it is to_role 'customer'), so this
-- is a belt-and-braces guarantee that this kind can never land in his inbox.
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role)
values ('customer_welcome', false,
        'Customer-facing onboarding welcome; owned by customer onboarding, never routed to the founder.',
        'customer_onboarding')
on conflict (kind) do update set
  allowed_to_email = excluded.allowed_to_email, reason = excluded.reason, owner_role = excluded.owner_role;

-- ROUTINE REMOVED 7 September 2026. public.fn_customer_welcome was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke all on function public.fn_customer_welcome(uuid, boolean) from public, anon, authenticated;
grant execute on function public.fn_customer_welcome(uuid, boolean) to service_role;

-- The deterministic act: greet every new registration. AFTER INSERT so the customer row is committed
-- to the row before the welcome is queued; a welcome that fails is swallowed so it can never abort a
-- registration (a customer who cannot be greeted must still be created).
create or replace function public.fn_customer_welcome_trg()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  if coalesce(btrim(new.email),'') <> '' then
    begin
      perform public.fn_customer_welcome(new.id, true);
    exception when others then
      -- Never let onboarding courtesy break account creation.
      null;
    end;
  end if;
  return new;
end $function$;

revoke all on function public.fn_customer_welcome_trg() from public, anon, authenticated;

-- z55: after the kernel emit (z50) so the run exists first; the welcome is a courtesy, not a gate.
drop trigger if exists z55_customer_welcome on public.customers;
create trigger z55_customer_welcome
  after insert on public.customers
  for each row execute function public.fn_customer_welcome_trg();

-- Ownership ledger follows the manifest (conventions step 4).
insert into public.kernel_routine_ownership
  (schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file, justification)
values
  ('public','fn_customer_welcome','p_customer_id uuid, p_send boolean','QUOTESDONE_APPLICATION','R4_MANIFEST_DEFINES_IT',
   'canonical file scripts/sql/the_customer_welcome_the_product_never_sent.sql','MANIFEST',
   'scripts/sql/the_customer_welcome_the_product_never_sent.sql', null),
  ('public','fn_customer_welcome_trg','','QUOTESDONE_APPLICATION','R4_MANIFEST_DEFINES_IT',
   'canonical file scripts/sql/the_customer_welcome_the_product_never_sent.sql','MANIFEST',
   'scripts/sql/the_customer_welcome_the_product_never_sent.sql', null)
on conflict (schema_name, routine_name, identity_args) do update set
  ownership_class = excluded.ownership_class, classified_by_rule = excluded.classified_by_rule,
  evidence = excluded.evidence, source_kind = excluded.source_kind, source_file = excluded.source_file,
  justification = excluded.justification;

do $proof$
declare v_sub text; v_body text; v jsonb;
begin
  -- Render (do not send) proves the body carries the four required elements.
  v := public.fn_customer_welcome('e0dee407-456c-4d8d-be52-2512bd4b1074', false);
  if coalesce((v->>'ok')::boolean,false) is not true then
    raise exception 'welcome render failed: %', v::text;
  end if;
  v_body := v->>'body';
  if position('quotesdone.com/me' in v_body) = 0 then raise exception 'welcome omits the new-request link'; end if;
  if position('% of that quote' in v_body) = 0 and position('٪' in v_body) = 0 then raise exception 'welcome omits the reveal fee'; end if;
  if position('refund-policy' in v_body) = 0 then raise exception 'welcome omits the refund policy link'; end if;
  if position('top three' in v_body) = 0 and position('ثلاثة' in v_body) = 0 then raise exception 'welcome omits the top-3 rule'; end if;
  raise notice 'proof: welcome renders with new-request link, reveal fee, top-3 and refund link';
end $proof$;

commit;
