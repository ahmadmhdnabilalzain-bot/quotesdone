-- THE COMPANY GETS AN ACCOUNTANT, AND THE MONEY FINALLY HAS AN OWNER.
--
-- The founder, 9 Sep 2026: "now what we need to build is the accountant agent. tasks: any financial
-- thing on the platform including refunds. reports to CEO. collects expenses from the email
-- expenses@mail.quotesdone.com. create weekly report as pdf and share it with me and the CEO. takes
-- approval from CEO on refunds and Meta ads expenses."
--
-- This is the FOURTH seat, and it is the one every earlier ruling was holding surfaces for. On
-- 9 Sep he said "fine leave payments stuff so we link them later to the new accountant" -- ten
-- payment functions have been owned by 'website' since, waiting for exactly this row to exist.
--
-- WHAT THE SEAT MUST DO BEFORE IT CAN EXIST, learned building sales_engineer and applied here in
-- the order the constraints demand:
--   1  org_agents FIRST -- org_role.runtime_agent_key is an FK to it, so the role cannot come first
--   2  org_role       -- ceo_standing_grant.grantee_role_id is an FK to THIS, so no grant without it
--   3  org_reporting_edge -- fn_support_report_to_ceo resolves its recipient here and REFUSES rather
--                            than inventing one, so a seat with no edge cannot report at all
--   4  function_owner_owner_ck must admit the new owner before it owns anything
--
-- THE GRANTS ARE NARROWER THAN THE OTHER SEATS', deliberately. The founder named two things this
-- agent may NOT decide alone: "takes approval from CEO on refunds and Meta ads expenses". So those
-- two are issued as grants that ROUTE to the CEO rather than permit -- max_amount_aed = 0 means every
-- amount exceeds the ceiling, so fn_agent_may_act returns may_act:false with route ceo_case_decision
-- on every single call. That is not a placeholder: it is the founder's rule expressed in the same
-- mechanism that already governs support, so it cannot be forgotten by a caller that neglects to ask.
--
-- Bookkeeping, expense capture and reporting ARE its own, because he said "any financial thing on
-- the platform" and did not reserve those.
--
-- WHY NOT SIMPLY OMIT THE TWO GRANTS. An absent grant already routes to the CEO -- fn_agent_may_act
-- returns may_act:false when it finds nothing. But an absent grant is indistinguishable from an
-- oversight, and the next person to read the table cannot tell "the founder ruled this needs the
-- CEO" from "nobody got round to it". A zero-ceiling grant carries the ruling in its own scope_note.
--
--   node scripts/apply_sql.mjs scripts/sql/the_company_gets_an_accountant_and_the_money_finally_has_an_owner.sql --apply --ddl

begin;

-- 1. THE OWNER CHECK ADMITS THE FOURTH SEAT. Widened, never dropped.
alter table public.function_owner drop constraint if exists function_owner_owner_ck;
alter table public.function_owner add constraint function_owner_owner_ck
  check (owner = any (array['ceo','customer_support','sales_engineer','accountant','website']));

-- 2. THE AGENT. department stays NULL; there are none and there will be none.
insert into public.org_agents (agent_key, role, kind, active, title, seniority, routing_tier,
                               max_open_tasks, available)
values (
  'accountant',
  'Accountant AI -- every financial matter on the platform: bookkeeping, expenses, refunds, reporting',
  'brain',
  true,
  'Accountant',
  'specialist',
  'analyst_controller',
  20,
  true
)
on conflict (agent_key) do update
  set role = excluded.role, active = excluded.active, title = excluded.title,
      seniority = excluded.seniority, routing_tier = excluded.routing_tier,
      max_open_tasks = excluded.max_open_tasks, available = excluded.available;

-- 3. THE ROLE. responsibilities and activation_conditions are NOT NULL with no default.
insert into public.org_role (
  role_id, display_name, runtime_mode, runtime_agent_key, authority_level,
  responsibilities, activation_conditions, owned_decisions, forbidden_decisions,
  handoff_targets, escalation_targets
)
values (
  'accountant',
  'Accountant',
  'event_driven_operator',
  'accountant',
  'execute_low',
  'Own every financial matter on the platform: the ledger, expense capture from the expenses inbox, reconciliation of the two cashflow sources (Stripe in, the expenses mailbox out), refunds, and the weekly report. Money is measured, never estimated -- a figure this seat publishes is one it can point at a source row for.',
  'A receipt arrives in the expenses mailbox; a Stripe event settles; a refund is requested; the weekly reporting window closes; a spend needs classifying.',
  array[
    'how a receipt is classified against the chart of accounts',
    'what the ledger says the company spent and earned',
    'whether a figure is measurable or must be reported as unknown',
    'when a refund is due under the published policy'
  ],
  array[
    'APPROVING A REFUND -- the founder ruled this goes to the CEO',
    'APPROVING META ADS EXPENSES -- the founder ruled this goes to the CEO',
    'emailing the founder directly outside the weekly report he asked for',
    'publishing a financial figure it cannot bind to a source row',
    'inventing an expense or a revenue number to close a gap'
  ],
  array['ceo'],
  array['ceo']
)
on conflict (role_id) do update
  set display_name = excluded.display_name, runtime_mode = excluded.runtime_mode,
      runtime_agent_key = excluded.runtime_agent_key, authority_level = excluded.authority_level,
      responsibilities = excluded.responsibilities,
      activation_conditions = excluded.activation_conditions,
      owned_decisions = excluded.owned_decisions,
      forbidden_decisions = excluded.forbidden_decisions,
      handoff_targets = excluded.handoff_targets,
      escalation_targets = excluded.escalation_targets;

-- 4. THE REPORTING EDGE. "reports to CEO", in his words.
insert into public.org_reporting_edge (child_role_id, parent_role_id, established_by, reason)
values (
  'accountant',
  'ceo',
  'founder',
  'Founder ruling 9 Sep 2026: the accountant agent "reports to CEO". Fourth seat, after ceo, customer_support and sales_engineer. No finance director, no CFO, no department.'
)
on conflict (child_role_id) do update
  set parent_role_id = excluded.parent_role_id, reason = excluded.reason;

-- 5. THE STANDING GRANTS.
insert into public.ceo_standing_grant
  (grant_key, grantee_role_id, action_class, scope_note, limit_note, max_amount_aed, issued_by, active)
values
  ('accountant.bookkeeping', 'accountant', 'bookkeeping',
   'Record, classify and reconcile financial events against the chart of accounts: journal entries, expense entries, bills, and the reconciliation of Stripe inflows against expenses-inbox outflows.',
   'Every figure must bind to a source row. An unmeasurable figure is reported as unknown, never estimated and never defaulted to zero.',
   null, 'ceo', true),

  ('accountant.expense_capture', 'accountant', 'expense_capture',
   'Read receipts forwarded to expenses@mail.quotesdone.com, extract vendor, date, amount, currency and tax, and file them against the chart of accounts.',
   'Only from senders on app_secrets.expense_forwarders. A receipt that cannot be read is held for review, never guessed at.',
   null, 'ceo', true),

  ('accountant.reporting', 'accountant', 'financial_reporting',
   'Produce the weekly financial report as a PDF and deliver it to the founder and the CEO -- the one founder-facing subscription this seat has, and it exists because he asked for it by name.',
   'Informational only. It carries no approval request and opens no queue the founder must action.',
   null, 'ceo', true),

  -- THE TWO THE FOUNDER RESERVED. A zero ceiling means every amount exceeds it, so
  -- fn_agent_may_act refuses on every call and names the CEO route. The rule is in the data.
  ('accountant.refund_decision', 'accountant', 'refund',
   'Investigate and prepare a refund: gather the evidence, apply the published policy, and put a recommendation to the CEO. RESERVED BY THE FOUNDER 9 Sep 2026 -- "takes approval from CEO on refunds". This seat prepares; the CEO decides.',
   'max_amount_aed 0 means EVERY refund exceeds this seat''s ceiling and routes to a CEO decision. That is the ruling, not a limit awaiting a number.',
   0, 'ceo', true),

  ('accountant.meta_ads_spend', 'accountant', 'meta_ads_spend',
   'Prepare and account for Meta advertising spend. RESERVED BY THE FOUNDER 9 Sep 2026 -- "takes approval from CEO on ... Meta ads expenses". This seat prepares and reconciles; the CEO approves the spend.',
   'max_amount_aed 0 means EVERY amount routes to a CEO decision.',
   0, 'ceo', true)
on conflict (grant_key) do update
  set scope_note = excluded.scope_note, limit_note = excluded.limit_note,
      max_amount_aed = excluded.max_amount_aed, active = excluded.active;

-- 6. THE SCOPED CREDENTIAL. The value is generated here and never leaves the database.
do $mint$
declare v_secret text;
begin
  if exists (select 1 from public.internal_credential where context = 'fn.accountant') then
    raise notice 'fn.accountant already exists -- left untouched';
    return;
  end if;
  v_secret := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active)
  values ('fn.accountant',
          'The Accountant seat -- bookkeeping, expense capture, refunds and financial reporting',
          public.fn_internal_credential_hash(v_secret),
          array['accountant'], false, true);
  insert into public.app_secrets (key, value)
  values ('cred_fn_accountant', v_secret)
  on conflict (key) do update set value = excluded.value;
end
$mint$;

-- 7. THE MONEY CHANGES HANDS. Ten payment functions have been owned by 'website' since 9 Sep,
-- held for precisely this seat. function_owner is the registry a sweep reads before deleting --
-- 137 functions were deleted on 8 Sep because it was incomplete -- so an owner that says 'website'
-- for the refund executor is not a cosmetic mislabel.
update public.function_owner
   set owner = 'accountant',
       note  = case function_slug
         when 'stripe_checkout'   then 'Customer pays the reveal fee. Money in.'
         when 'stripe_confirm'    then 'The payment settles and the reveal is recorded. Money in.'
         when 'stripe_webhook'    then 'Stripe''s own event feed -- one of the company''s two cashflow sources.'
         when 'stripe_setup'      then 'Stripe configuration.'
         when 'stripe_setup_page' then 'Stripe configuration page.'
         when 'supplier_pay'      then 'Supplier-side payment: refund clawback and the annual subscription.'
         when 'refunds_api'       then 'Refund execution, including the Stripe refund call itself.'
         when 'refund_flow'       then 'The refund ladder.'
         when 'reveal_invoice'    then 'The invoice for a reveal.'
         when 'quote_pdf'         then 'The quotation document that carries the money figures.'
         else note end
 where function_slug in ('stripe_checkout','stripe_confirm','stripe_webhook','stripe_setup',
                         'stripe_setup_page','supplier_pay','refunds_api','refund_flow',
                         'reveal_invoice','quote_pdf');

-- 8. THE CLOSING ASSERTION.
do $check$
declare
  v_agent int; v_role int; v_edge int; v_grants int; v_cred int; v_money int;
  v_refund jsonb; v_meta jsonb; v_book jsonb; v_support jsonb;
begin
  select count(*) into v_agent  from public.org_agents where agent_key = 'accountant' and active;
  select count(*) into v_role   from public.org_role   where role_id   = 'accountant';
  select count(*) into v_edge   from public.org_reporting_edge
    where child_role_id = 'accountant' and parent_role_id = 'ceo';
  select count(*) into v_grants from public.ceo_standing_grant where grantee_role_id = 'accountant';
  select count(*) into v_cred   from public.internal_credential
    where context = 'fn.accountant' and active and 'accountant' = any(scope);
  select count(*) into v_money  from public.function_owner where owner = 'accountant';

  if v_agent <> 1 or v_role <> 1 or v_edge <> 1 or v_grants <> 5 or v_cred <> 1 then
    raise exception 'SEAT NOT ESTABLISHED: agent=% role=% edge=% grants=% cred=%',
      v_agent, v_role, v_edge, v_grants, v_cred;
  end if;
  if v_money <> 10 then
    raise exception 'THE MONEY DID NOT MOVE: accountant owns % payment function(s), expected 10', v_money;
  end if;

  -- The founder's two reservations must REFUSE, at any amount, including none at all.
  v_refund := public.fn_agent_may_act('accountant', 'refund', 1);
  v_meta   := public.fn_agent_may_act('accountant', 'meta_ads_spend', 1);
  if (v_refund ->> 'may_act')::boolean is distinct from false
     or (v_refund ->> 'route') is distinct from 'ceo_case_decision' then
    raise exception 'A REFUND DID NOT ROUTE TO THE CEO: %', v_refund;
  end if;
  if (v_meta ->> 'may_act')::boolean is distinct from false then
    raise exception 'META ADS SPEND DID NOT ROUTE TO THE CEO: %', v_meta;
  end if;

  -- And what it MAY do must still work, or the seat is seated and mute.
  v_book := public.fn_agent_may_act('accountant', 'bookkeeping');
  if (v_book ->> 'may_act')::boolean is distinct from true then
    raise exception 'THE ACCOUNTANT CANNOT KEEP BOOKS: %', v_book;
  end if;

  -- The other seats are untouched.
  v_support := public.fn_support_may_act('conversation');
  if (v_support ->> 'may_act')::boolean is distinct from true then
    raise exception 'SUPPORT REGRESSED: %', v_support;
  end if;

  raise notice 'accountant seated: 1 agent, 1 role, 1 edge, 5 grants (3 active + refund/meta routed to CEO), 1 credential, % payment functions moved; support unaffected', v_money;
end
$check$;

commit;
