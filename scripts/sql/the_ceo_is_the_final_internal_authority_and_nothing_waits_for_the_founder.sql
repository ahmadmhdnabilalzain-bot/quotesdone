-- THE CEO IS THE FINAL INTERNAL AUTHORITY, AND NOTHING WAITS FOR THE FOUNDER
--
-- Operating constitution revision 1.2, identical in both packs and verified so:
--
--   "The existing new CEO is the final INTERNAL decision and approval authority... There is no
--    internal founder approval queue, including for refunds. There is no serious-incident exception
--    that asks Ahmad to decide, approve, investigate or supply a workaround."
--
-- THIS UNDOES SOMETHING I BUILT THIS MORNING, and it should be undone. The CEO decision register I
-- wrote a few hours ago marked refunds, paid inference and organisation structure as
-- founder_reserved, and the company charter named "Stripe refunds -- every refund needs the founder"
-- as the single reserved matter. That was the founder's rule then. It is not his rule now, and a
-- prompt sentence saying "the CEO decides refunds" while the DATABASE still says founder_reserved
-- is exactly the failure the master update warns about: "Do not merely append a new sentence to a
-- prompt while old code waits for a founder."
--
-- WHAT DOES NOT CHANGE, because the constitution is equally clear: "No founder approvals does not
-- mean unlimited money, unrestricted data disclosure, illegal conduct, deceptive statements,
-- unlicensed capability or permission to disable audit/security." Those are facts and controls, not
-- hidden human approvers, and none of them is touched here.

-- ---------------------------------------------------------------------------------------------
-- 1. THE AUTHORITY MODEL ITSELF
-- ---------------------------------------------------------------------------------------------
create table if not exists public.autonomy_policy (
  id                  int primary key default 1,
  revision            text not null,
  final_internal_authority text not null,
  founder_approval_required boolean not null,
  founder_escalation_allowed boolean not null,
  constitution_note   text not null,
  effective_from      timestamptz not null default now(),
  constraint autonomy_policy_single check (id = 1),
  -- The two properties the constitution turns on, made unfalsifiable. A future edit that reintroduces
  -- a founder approval queue has to change a CHECK, not a sentence, and will be seen.
  constraint autonomy_policy_no_founder_approval check (founder_approval_required = false),
  constraint autonomy_policy_no_founder_escalation check (founder_escalation_allowed = false)
);

insert into public.autonomy_policy (id, revision, final_internal_authority, founder_approval_required,
                                    founder_escalation_allowed, constitution_note)
values (1, '1.2', 'ceo', false, false,
  'Operating constitution 1.2: the CEO is the final internal decision and approval authority. No internal founder approval queue, including for refunds. No serious-incident exception that asks the founder to decide. Visibility in the OS is not a disguised approval request and never suspends work.')
on conflict (id) do update
  set revision = excluded.revision,
      final_internal_authority = excluded.final_internal_authority,
      founder_approval_required = false,
      founder_escalation_allowed = false,
      constitution_note = excluded.constitution_note,
      effective_from = now();

-- ---------------------------------------------------------------------------------------------
-- 2. STANDING GRANTS: HOW ROUTINE WORK IS AUTHORISED WITHOUT ASKING
-- ---------------------------------------------------------------------------------------------
-- "Approval comes from either a current CEO-issued standing delegation or a scoped CEO case
-- decision. Do not ask the CEO to approve every ordinary message; do not let a subordinate invent
-- its own approval."
create table if not exists public.ceo_standing_grant (
  grant_key        text primary key,
  grantee_role_id  text not null references public.org_role(role_id) on delete cascade,
  action_class     text not null,
  scope_note       text not null,
  limit_note       text,
  max_amount_aed   numeric,
  issued_by        text not null default 'ceo',
  issued_at        timestamptz not null default now(),
  expires_at       timestamptz,
  active           boolean not null default true,
  -- A GRANT IS ISSUED BY THE CEO OR IT IS NOT A GRANT. A subordinate inventing its own approval is
  -- the failure the constitution names, and this makes it a constraint rather than a hope.
  constraint ceo_standing_grant_issuer check (issued_by = 'ceo')
);

comment on table public.ceo_standing_grant is
  'Standing delegations the CEO has issued. Routine work is authorised by one of these, so the CEO is not asked to approve every ordinary message. A grant may only be issued by the CEO, and an expired grant authorises nothing -- fn_support_may_act checks the expiry rather than the row''s existence.';

insert into public.ceo_standing_grant (grant_key, grantee_role_id, action_class, scope_note, limit_note, max_amount_aed) values
 ('support.reply',            'customer_support', 'conversation',
  'Answer any customer or supplier message from live account facts and approved company knowledge.',
  'No authority to change a price, an entitlement or a permission by conversation.', null),
 ('support.notify',           'customer_support', 'notification',
  'Send the deterministic quotation, report, invoice and licence notifications on either channel.',
  'Anonymity scan must pass; the outbox CHECK enforces it.', null),
 ('support.document_intake',  'customer_support', 'document',
  'Accept, quarantine, scan and file a supplier document arriving on any of the three intake paths.',
  'Canonical verification decides validity; support records receipt, never approval.', null),
 ('support.refund_investigate','customer_support', 'refund',
  'Investigate a refund request end to end: gather evidence, check settlement, entitlement and duplicates, and put a decision to the CEO service.',
  'Investigation only. Execution requires a CEO refund decision; support never authorises its own.', null)
on conflict (grant_key) do update
  set scope_note = excluded.scope_note, limit_note = excluded.limit_note, active = true;

-- Is an action authorised right now? Read, never assumed.
create or replace function public.fn_support_may_act(p_action_class text, p_amount_aed numeric default null)
returns jsonb
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
declare g record;
begin
  select * into g from public.ceo_standing_grant
   where grantee_role_id = 'customer_support' and action_class = p_action_class and active
     and (expires_at is null or expires_at > now())
   order by issued_at desc limit 1;

  if not found then
    -- NOT a founder question. The constitution is explicit that an uncovered action goes to the CEO.
    return jsonb_build_object('may_act', false, 'route', 'ceo_case_decision',
      'reason', format('No current standing grant covers %L. This needs a scoped CEO decision -- not a founder approval, which does not exist.', p_action_class));
  end if;

  if g.max_amount_aed is not null and p_amount_aed is not null and p_amount_aed > g.max_amount_aed then
    return jsonb_build_object('may_act', false, 'route', 'ceo_case_decision',
      'reason', format('AED %s exceeds the standing limit of AED %s on %L.', p_amount_aed, g.max_amount_aed, g.grant_key));
  end if;

  return jsonb_build_object('may_act', true, 'grant', g.grant_key, 'scope', g.scope_note,
    'limit', g.limit_note);
end $function$;

-- ---------------------------------------------------------------------------------------------
-- 3. THE DECISION REGISTER MOVES TO THE CEO
-- ---------------------------------------------------------------------------------------------
-- The register still records that these are exceptional. What changes is WHO decides: the CEO,
-- with no upward route. The old rows said founder_reserved; every one of them is rewritten and the
-- previous wording is kept in the decision text so the change is legible rather than silent.
alter table public.ceo_decision drop constraint if exists ceo_decision_authority_ck;
-- The constraint is re-added AFTER the rows below are migrated. Adding it first fails on the
-- existing founder_reserved values, which is the constraint working correctly at the wrong moment.

update public.ceo_decision
   set authority = 'ceo_alone',
       decision = 'Whether to refund, on the evidence. The CEO owns refund decisions outright: support investigates and assembles evidence, the CEO decides, and the canonical payment service executes. Superseded 7 Sep 2026 -- this previously read "Nothing. Every refund is the founder''s decision alone."',
       evidence_required = 'The transaction, the settlement state, the entitlement state, any duplicate or prior remedy, the buyer''s stated reason, and the decision with its rationale. A denied refund still needs an evidence-based explanation and an appropriate alternative remedy.'
 where decision_key = 'refund';

update public.ceo_decision
   set authority = 'ceo_alone',
       decision = 'Whether paid inference may run, and within what budget. The hold is a founder CONSTRAINT on spend, not an approval queue: the CEO operates inside it and lifts or requests nothing from the founder. Superseded 7 Sep 2026 -- this previously read "Nothing while the hold stands."'
 where decision_key = 'paid_inference';

update public.ceo_decision
   set authority = 'founder_specified',
       decision = 'Nothing is decided here. The founder SPECIFIES which agents exist and adds them one at a time; that is not an approval the company waits on, and no work blocks pending it. The CEO allocates to the roster that exists.'
 where decision_key = 'structure';

-- ---------------------------------------------------------------------------------------------
-- Now that every row says ceo_alone or founder_specified, the constraint goes back on and makes
-- founder_reserved unwritable.
alter table public.ceo_decision add constraint ceo_decision_authority_ck
  check (authority in ('ceo_alone','ceo_case_decision','founder_specified'));

-- 4. THE CHARTER'S RESERVED MATTER IS RETIRED
-- ---------------------------------------------------------------------------------------------
-- reserved_matters held exactly one entry: Stripe refunds. Under revision 1.2 there are none, and an
-- empty array is the honest representation -- not a rewritten sentence that still implies a queue.
update public.company_charter
   set reserved_matters = array[]::text[]
 where active and reserved_matters <> array[]::text[];

-- ---------------------------------------------------------------------------------------------
-- 5. THE OLD RESERVED-DECISION REGISTER, PRESERVED AND DEACTIVATED
-- ---------------------------------------------------------------------------------------------
-- "Audit and migrate existing awaiting-founder/human approval cases: preserve history... Do not
-- auto-approve the backlog." The rows are kept as history and marked superseded; nothing waits on
-- them, and nothing is retroactively approved.
do $$
begin
  if to_regclass('public.founder_reserved_decision') is not null then
    if not exists (select 1 from information_schema.columns
                    where table_schema='public' and table_name='founder_reserved_decision'
                      and column_name='superseded_at') then
      alter table public.founder_reserved_decision add column superseded_at timestamptz;
      alter table public.founder_reserved_decision add column superseded_reason text;
    end if;
    update public.founder_reserved_decision
       set superseded_at = now(),
           superseded_reason = 'Operating constitution 1.2, 7 Sep 2026: the CEO is the final internal authority and there is no founder approval queue. This row is retained as history. It is NOT approved and NOT re-routed retroactively; it simply no longer gates anything.'
     where superseded_at is null;
  end if;
end $$;
