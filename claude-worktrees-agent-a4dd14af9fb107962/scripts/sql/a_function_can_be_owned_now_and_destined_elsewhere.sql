-- A FUNCTION CAN BE OWNED NOW AND DESTINED ELSEWHERE
--
-- The founder, 8 September 2026: "email cron will be added to the IT agent so its ok."
--
-- That is a third state the registry could not express. email_cron is genuinely the customer
-- support agent's today -- it is how his mail leaves the building, and if it stopped, his email
-- would stop -- but it is not really his job. Scheduling and delivery infrastructure belongs to an
-- IT seat that does not exist yet.
--
-- Recording it as customer_support and saying nothing would lose the founder's decision the moment
-- this conversation ends. Recording it as 'it' would be worse: an owner column pointing at a seat
-- with no rows in org_role is a reference to nobody, and the whole registry exists to stop exactly
-- that. Both are the same mistake in opposite directions -- pretending the present is the plan, or
-- pretending the plan is the present.
--
-- So ownership stays honest about today and carries the plan beside it. When the IT agent is built,
-- `select * from public.function_owner where moves_to is not null` is the list of what to hand over,
-- and nobody has to remember a sentence from a chat window.
--
-- moves_to is deliberately NOT constrained to existing roles. It names seats that do not exist yet;
-- constraining it to org_role would make it impossible to write down a plan before building the
-- thing the plan is about.

alter table public.function_owner
  add column if not exists moves_to      text,
  add column if not exists moves_to_note text;

do $$ begin
  -- A destination without a reason is a rumour. If a function is marked as moving, the row has to
  -- say why, because the person reading it in three months will not have been in this conversation.
  if not exists (select 1 from pg_constraint where conname = 'function_owner_moves_to_ck') then
    alter table public.function_owner add constraint function_owner_moves_to_ck
      check ((moves_to is null) = (moves_to_note is null));
  end if;
  -- Moving somewhere it already is would be a no-op recorded as a plan.
  if not exists (select 1 from pg_constraint where conname = 'function_owner_moves_elsewhere_ck') then
    alter table public.function_owner add constraint function_owner_moves_elsewhere_ck
      check (moves_to is null or moves_to <> owner);
  end if;
end $$;

comment on column public.function_owner.moves_to is
  'The seat this is destined for once that seat exists. Not constrained to org_role on purpose: it names agents not yet built, and a plan you cannot write down until the thing exists is not a plan. The owner column always states who is accountable TODAY.';

update public.function_owner
   set moves_to = 'it',
       moves_to_note = 'Founder, 8 Sep 2026: "email cron will be added to the IT agent so its ok." It is the customer-support agent''s today because his email does not leave without it, but scheduling and delivery are infrastructure, not his job.'
 where function_slug = 'email_cron';
