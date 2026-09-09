-- A REFUND NAMES THE ONE APPROVAL AND THE ONE STRIPE PAYMENT IT REVERSES.
--
-- THE FOUNDER, 9 SEPTEMBER 2026, IN HIS WORDS:
--
--   "Every refund is connected to a Stripe invoice, and that's how it should be registered in the
--    data. So when a refund is issued, it's issued against that exact invoice reference. which also
--    should be available in... with the accountant and the CEO as a PDF as it is from Stripe. So
--    it's literally a refund would be issued for that exact reference. It has an ID."
--
-- ── THE DEFECT THIS CLOSES, AND WHY IT COST NOTHING YET ────────────────────────────────────────
--
-- public.fn_refund_execution_requires_ceo_approval is the trigger that stops money leaving without
-- the CEO. It checked four things about the cited public.ceo_approval row -- that it exists, that
-- its subject_kind is 'refund', that its decision is 'approved', and that nothing superseded it --
-- and it never once checked that the approval was about THIS refund. `d.subject_id` was read into
-- the rowtype and then never compared to anything.
--
-- So ONE approved decision could be cited by an UNLIMITED number of unrelated refund rows. The CEO
-- approves AED 300 back to one customer; every other pending refund in the table sets
-- refund_decision_id to that same decision_id and walks straight through the guard to 'succeeded'.
-- The guard was not weak, it was answering a different question: "is there an approved refund
-- decision somewhere in the estate", not "was THIS refund approved". An instrument measuring the
-- wrong subject reads green forever.
--
-- public.refunds is 0 rows today, so this has cost nothing. It is unbounded the day money moves,
-- which is why it is fixed before there is a first refund rather than after.
--
-- ── THE SECOND HALF: A REFUND THAT NAMES NO PAYMENT ────────────────────────────────────────────
--
-- fn_refund_amount_is_the_fee_paid already refused a refund that named no TRANSACTION, and already
-- refused an amount that was not exactly the reveal fee that transaction recorded. What it never
-- asked was the founder's actual question: which Stripe object is this reversing. refunds carried
-- stripe_payment_intent as a nullable text column that nothing ever checked, so a refund could name
-- transaction A and cite the payment intent of transaction B, or cite none at all, and the ledger
-- would accept both. `transactions.payment_ref` is the reference Stripe gave us when the customer
-- paid -- written by stripe_webhook as `payment_intent || session.id` -- and it is now the only
-- reference a platform refund may carry.
--
-- Both guards live in the two routines EVERY non-external refund already passes through, rather
-- than in the callers. fn_refund_request is not the only door -- fn_refund_settle writes rows too,
-- and so would any future path -- and a guard added per-caller is a guard the next caller misses.
--
-- ── WHAT IS DELIBERATELY NOT GUARDED: REFUNDS STRIPE ALREADY ISSUED ────────────────────────────
--
-- requested_by in ('stripe_webhook','stripe_dashboard','stripe') stays exempt from all of it. A
-- refund issued from the Stripe dashboard is a FACT to be recorded, not a request to be approved;
-- refusing that row would delete our only record of real money leaving, which is strictly worse
-- than admitting it happened. That exemption already existed in both routines and is unchanged.
--
-- ── WHICH REFUND TABLE IS AUTHORITATIVE ────────────────────────────────────────────────────────
--
-- public.refunds. It is the only one of the two that touches Stripe (stripe_refund_id UNIQUE,
-- stripe_payment_intent, stripe_charge_id), the only one the webhook settles into, the only one
-- foreign-keyed to public.ceo_approval, and the only one carrying gl_entry_id and reconciliation.
-- public.refund_case is a CASE FILE -- the support/CEO workflow states -- and its "execution"
-- (fn_refund_execute_authorized) never contacts a payment provider at all; it records a
-- provider_ref its caller hands it. So the Stripe binding belongs here, on refunds, and the
-- silence-evidence chain applied earlier today correctly belongs on refund_case. The two are not
-- joined by anything, which is itself a defect and is reported rather than silently bridged here:
-- bridging them is a data-model decision, not a guard.
--
-- ── THE DOCUMENT ───────────────────────────────────────────────────────────────────────────────
--
-- The estate already has this shape working for expenses: doc_path/doc_name/doc_content_type/
-- doc_kind/doc_note on the record itself, a private bucket, one view that reports the state of the
-- evidence, one lookup that turns a row id into something openable, and one coverage function so
-- "how many records cannot be opened" is a number rather than a blank cell somebody notices months
-- later. Refunds get the same shape, in the finance-docs bucket.
--
-- WHAT STRIPE ACTUALLY OFFERS, MEASURED RATHER THAN ASSUMED. supabase/functions/stripe_checkout
-- creates the reveal-fee session with mode=payment and NO invoice_creation, so Stripe produces no
-- Invoice object for a reveal fee and there is therefore no invoice_pdf to fetch. The Stripe-hosted
-- artefact that DOES exist for these payments is the charge's receipt_url. That reference is stored
-- here in stripe_receipt_url, and a refund holding only that reads as 'reference_only' -- an
-- honest state, distinct from both 'missing' and from a stored file. No PDF-download endpoint is
-- invented: fetching and storing the object is an edge-function job and is reported for deployment.

-- ── 1. THE APPROVAL MUST NAME THIS REFUND ──────────────────────────────────────────────────────
create or replace function public.fn_refund_execution_requires_ceo_approval()
returns trigger language plpgsql as $fn$
declare
  v_money_moved constant text[] := array['approved','processing','succeeded'];
  -- A refund Stripe already issued is a FACT to be recorded, not a request to be approved. Refusing
  -- the row would delete our only record of real money leaving, which is worse than admitting it.
  v_external    constant text[] := array['stripe_webhook','stripe_dashboard','stripe'];
  d public.ceo_approval%rowtype;
begin
  if not (new.status = any(v_money_moved)) then return new; end if;
  if tg_op = 'UPDATE' and old.status = any(v_money_moved)
     and new.refund_decision_id is not distinct from old.refund_decision_id then
    return new;   -- already past this boundary and not changing which decision it cites
  end if;
  if lower(coalesce(new.requested_by, '')) = any(v_external) then
    return new;
  end if;

  if new.refund_decision_id is null then
    raise exception 'refunds %: a platform-originated refund may not reach status % without naming the CEO decision that authorised it.',
      coalesce(new.id::text, '(new)'), new.status
      using errcode = '23514',
            hint = 'Record one in public.ceo_approval (subject_kind = ''refund'', subject_id = this '
                || 'refund''s id) and cite its decision_id. Founder ruling, 8 Sep 2026: all '
                || 'approvals are the CEO''s.';
  end if;

  select * into d from public.ceo_approval where decision_id = new.refund_decision_id;
  if not found then
    raise exception 'refunds %: refund_decision_id % names no CEO decision',
      coalesce(new.id::text, '(new)'), new.refund_decision_id using errcode = '23503';
  end if;
  if d.subject_kind <> 'refund' then
    raise exception 'refunds %: decision % is a % decision, not a refund decision',
      coalesce(new.id::text, '(new)'), d.decision_id, d.subject_kind using errcode = '23514';
  end if;

  -- THE BINDING THIS ROUTINE WAS MISSING UNTIL 9 SEP 2026. Everything above this line was already
  -- checked; subject_id was read and never compared, so one approved decision could authorise every
  -- refund in the table. ONE APPROVAL, ONE REFUND, ALWAYS.
  if d.subject_id is distinct from new.id::text then
    raise exception 'refunds %: decision % approved refund %, not this one. One approval authorises one refund.',
      coalesce(new.id::text, '(new)'), d.decision_id, coalesce(d.subject_id, '(nothing)')
      using errcode = '23514',
            hint = 'The CEO decides each refund on its own facts. Reusing another refund''s approval '
                || 'would move money nobody approved. Record a ceo_approval row whose subject_id is '
                || 'this refund''s id, and cite that.';
  end if;

  if d.decision <> 'approved' then
    raise exception 'refunds %: decision % refused this refund; it may not reach %',
      coalesce(new.id::text, '(new)'), d.decision_id, new.status using errcode = '23514';
  end if;
  if d.superseded_by is not null then
    raise exception 'refunds %: decision % was superseded by %; cite the decision that stands',
      coalesce(new.id::text, '(new)'), d.decision_id, d.superseded_by using errcode = '23514';
  end if;
  return new;
end
$fn$;

comment on function public.fn_refund_execution_requires_ceo_approval() is
  'Money leaves public.refunds only on a CEO decision that names THIS refund: ceo_approval.subject_kind '
  '= ''refund'', subject_id = the refund''s id, decision = ''approved'', not superseded. The subject_id '
  'comparison was added 9 Sep 2026 -- without it one approval authorised an unlimited number of '
  'unrelated refunds. Refunds Stripe issued itself (requested_by stripe_webhook/stripe_dashboard/stripe) '
  'are recorded facts and stay exempt.';

-- ── 2. THE REFUND MUST NAME THE EXACT STRIPE PAYMENT IT REVERSES ────────────────────────────────
create or replace function public.fn_refund_amount_is_the_fee_paid()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $fn$
declare
  t public.transactions%rowtype;
  v_expected bigint;
  -- A refund Stripe already issued is a fact to be recorded, not a request to be approved.
  v_external constant text[] := array['stripe_webhook','stripe_dashboard','stripe'];
begin
  if lower(coalesce(NEW.requested_by,'')) = any(v_external) then
    return NEW;
  end if;

  if NEW.transaction_id is null then
    raise exception 'refunds: a refund must name the transaction it reverses. transaction_id is null, so this row asserts money is owed without saying which payment it came from. (refund_names_no_payment)'
      using errcode = '23514',
            hint = 'Set transaction_id to the public.transactions row whose reveal_fee is being returned. A refund this platform did not issue is recorded through fn_refund_settle with requested_by stripe_webhook, and that path is exempt.';
  end if;

  select * into t from public.transactions where id = NEW.transaction_id;
  if not found then
    raise exception 'refunds: transaction % does not exist. (refund_transaction_absent)',
      NEW.transaction_id using errcode = '23503';
  end if;

  if t.reveal_fee is null or t.reveal_fee <= 0 then
    raise exception 'refunds: transaction % records no reveal fee (reveal_fee %), so there is nothing to give back. A refund of an unpaid reveal is a payment, not a refund. (refund_no_fee_was_paid)',
      NEW.transaction_id, coalesce(t.reveal_fee::text,'null') using errcode = '23514';
  end if;

  if t.refund_deadline is null then
    raise exception 'refunds: transaction % has no refund window. trg_reveal_window opens one at reveal, so a transaction without it was never revealed and no refund can be due yet. (refund_window_not_open)',
      NEW.transaction_id using errcode = '23514';
  end if;
  if now() < t.refund_deadline then
    raise exception 'refunds: the refund window on transaction % opens at % and it is now %. The customer waits the founder-set period of working days after the reveal before a refund can be claimed. (refund_window_not_yet_open)',
      NEW.transaction_id, t.refund_deadline, now() using errcode = '23514';
  end if;

  -- ── THE STRIPE REFERENCE, ADDED 9 SEP 2026 ───────────────────────────────────────────────────
  -- The founder: "it's issued against that exact invoice reference... It has an ID." The reference
  -- Stripe gave us when the customer paid is transactions.payment_ref (stripe_webhook writes the
  -- payment_intent, falling back to the checkout session id). Until now stripe_payment_intent on a
  -- refund was a nullable text column nothing checked, so a refund could name transaction A and
  -- cite the payment of transaction B -- or name no payment at all -- and still move money.
  if coalesce(btrim(t.payment_ref), '') = '' then
    raise exception 'refunds: transaction % carries no Stripe payment reference, so there is no payment of record to reverse. (refund_payment_has_no_reference)',
      NEW.transaction_id using errcode = '23514',
            hint = 'transactions.payment_ref is written by stripe_webhook when the reveal fee settles. A transaction without one was never paid through Stripe, and money must not be returned against a payment nobody can point at.';
  end if;
  if coalesce(btrim(NEW.stripe_payment_intent), '') = '' then
    raise exception 'refunds: this refund names no Stripe payment. Transaction % was paid under reference %, and a refund is issued against that exact reference. (refund_names_no_stripe_reference)',
      NEW.transaction_id, t.payment_ref using errcode = '23514',
            hint = 'Set stripe_payment_intent to the payment_ref of the transaction being reversed. Founder ruling, 9 Sep 2026.';
  end if;
  if btrim(NEW.stripe_payment_intent) <> btrim(t.payment_ref) then
    raise exception 'refunds: this refund cites Stripe payment %, but transaction % was paid under %. A refund is issued against the exact reference of the payment it reverses, never another one. (refund_cites_the_wrong_stripe_payment)',
      NEW.stripe_payment_intent, NEW.transaction_id, t.payment_ref using errcode = '23514';
  end if;

  -- AND THE AMOUNT IS READ OFF THAT PAYMENT. Equality, not a ceiling: the reveal fee is refunded
  -- whole or not at all, so "cannot exceed what the payment took" is enforced by the stricter rule
  -- that it must EQUAL it. A platform refund with no amount is refused outright -- an unstated
  -- figure is not a smaller figure, it is an unbounded one.
  v_expected := round(t.reveal_fee * 100)::bigint;
  if NEW.amount_fils is null then
    raise exception 'refunds: a platform refund must state its amount. Transaction % took % fils (AED %), and that is the only figure this refund may carry. (refund_states_no_amount)',
      NEW.transaction_id, v_expected, round(t.reveal_fee,2) using errcode = '23514';
  end if;
  if NEW.amount_fils <> v_expected then
    raise exception 'refunds: the amount must equal the reveal fee the customer actually paid on transaction % — expected % fils (AED %), got % fils (AED %). A refund figure is read off the payment, never typed. (refund_amount_is_not_the_fee_paid)',
      NEW.transaction_id, v_expected, round(t.reveal_fee,2), NEW.amount_fils, round(NEW.amount_fils/100.0,2)
      using errcode = '23514';
  end if;

  return NEW;
end
$fn$;

comment on function public.fn_refund_amount_is_the_fee_paid() is
  'A platform refund must name the transaction it reverses, cite that transaction''s exact Stripe '
  'payment reference (transactions.payment_ref), and carry an amount equal to the reveal fee that '
  'payment took. The Stripe-reference and mandatory-amount clauses were added 9 Sep 2026 on the '
  'founder''s ruling that a refund is issued against the exact reference of the payment it reverses. '
  'Refunds Stripe issued itself are recorded facts and stay exempt.';

-- ── 3. THE DOCUMENT LIVES WITH THE RECORD ──────────────────────────────────────────────────────
-- The same five columns expense_entries carries, so one shape means one habit across finance, plus
-- the Stripe-hosted receipt reference, which is the only document Stripe produces for a
-- mode=payment Checkout (there is no Invoice object, so there is no invoice_pdf).
alter table public.refunds
  add column if not exists stripe_receipt_url text,
  add column if not exists doc_path           text,
  add column if not exists doc_name           text,
  add column if not exists doc_content_type   text,
  add column if not exists doc_kind           text,
  add column if not exists doc_note           text;

comment on column public.refunds.stripe_receipt_url is
  'The Stripe-hosted receipt for the charge this refund reverses (charge.receipt_url). This is the '
  'only document Stripe produces for a reveal fee: stripe_checkout uses mode=payment with no '
  'invoice_creation, so no Invoice object and therefore no invoice_pdf exists. A reference, not a '
  'stored file — a refund holding only this reads as ''reference_only''.';
comment on column public.refunds.doc_path is
  'Object path in the private finance-docs bucket for the stored document of this refund. NULL means '
  'no file is held; it is never a silently blank cell — v_refund_documents reports it as missing.';
comment on column public.refunds.doc_kind is
  'What the stored document IS: stripe_receipt, stripe_refund_receipt, bank_advice. NULL alongside a '
  'doc_path is ''unclassified'' — a file whose writer did not say what it was.';

-- ── 4. THE STATE OF THE EVIDENCE, PER REFUND ───────────────────────────────────────────────────
create or replace view public.v_refund_documents as
select
  r.id,
  r.transaction_id,
  r.status,
  r.reason_code,
  r.amount_fils,
  r.currency,
  r.requested_by,
  r.stripe_payment_intent,
  r.stripe_charge_id,
  r.stripe_refund_id,
  r.refund_decision_id,
  r.stripe_receipt_url,
  'finance-docs'::text as doc_bucket,
  r.doc_path,
  r.doc_name,
  r.doc_content_type,
  r.doc_kind,
  r.doc_note,
  case
    when r.doc_path is not null and r.doc_kind is null then 'unclassified'
    when r.doc_path is not null                        then r.doc_kind
    when r.stripe_receipt_url is not null              then 'reference_only'
    else 'missing'
  end as document_state,
  r.doc_path is not null as is_openable,
  -- The founder's binding, reported as a fact rather than assumed: does this refund name the exact
  -- Stripe payment of the transaction it reverses. Externally-issued refunds have no transaction to
  -- compare against and are reported as such, not as a failure.
  case
    when lower(coalesce(r.requested_by,'')) in ('stripe_webhook','stripe_dashboard','stripe')
      then 'external'
    when r.transaction_id is null then 'no_transaction'
    when coalesce(btrim(r.stripe_payment_intent),'') = '' then 'no_reference'
    when btrim(r.stripe_payment_intent) = btrim(coalesce(t.payment_ref,'')) then 'bound'
    else 'mismatched'
  end as stripe_binding
from public.refunds r
left join public.transactions t on t.id = r.transaction_id;

comment on view public.v_refund_documents is
  'One row per refund with the state of its evidence and of its Stripe binding. document_state is '
  'the doc_kind, ''unclassified'', ''reference_only'' (Stripe''s hosted receipt is known but no file '
  'is stored) or ''missing''. stripe_binding says whether the refund names the exact payment '
  'reference of the transaction it reverses. The founder''s rule of 9 Sep 2026 made countable.';

revoke all on public.v_refund_documents from anon, authenticated;

-- ── 5. THE ROW -> DOCUMENT LOOKUP ──────────────────────────────────────────────────────────────
-- SECURITY INVOKER on purpose, exactly as fn_expense_document is: the caller's own rights decide,
-- so this cannot become a way to read finance paths from a seat that may not read finance. The
-- caller names a REFUND, never a path — a caller who could name its own path could read any object
-- in finance-docs.
create or replace function public.fn_refund_document(p_refund_id bigint)
returns jsonb language sql stable as $fn$
  select coalesce(
    (select jsonb_build_object(
       'ok',              v.doc_path is not null,
       'refund_id',       v.id,
       'transaction_id',  v.transaction_id,
       'status',          v.status,
       'amount_fils',     v.amount_fils,
       'currency',        v.currency,
       'stripe_payment_intent', v.stripe_payment_intent,
       'stripe_charge_id',      v.stripe_charge_id,
       'stripe_refund_id',      v.stripe_refund_id,
       'stripe_receipt_url',    v.stripe_receipt_url,
       'stripe_binding',  v.stripe_binding,
       'bucket',          v.doc_bucket,
       'path',            v.doc_path,
       'name',            v.doc_name,
       'content_type',    v.doc_content_type,
       'kind',            v.doc_kind,
       'note',            v.doc_note,
       'state',           v.document_state,
       'reason',          case
                            when v.doc_path is not null then null
                            when v.stripe_receipt_url is not null
                              then 'No file is stored for this refund yet. Stripe''s own hosted '
                                || 'receipt for the payment is known and is returned as '
                                || 'stripe_receipt_url; it has not been fetched into finance-docs.'
                            else 'This refund has no stored document and no Stripe receipt reference. '
                              || 'The reveal fee was taken through a mode=payment Checkout, which '
                              || 'produces no Stripe invoice, so the receipt reference has to be read '
                              || 'off the charge before anything can be stored.'
                          end)
     from public.v_refund_documents v where v.id = p_refund_id),
    jsonb_build_object('ok', false, 'refund_id', p_refund_id, 'state', 'no_such_refund',
                       'reason', 'There is no public.refunds row with that id.'));
$fn$;

comment on function public.fn_refund_document(bigint) is
  'The way from a refund row to its document: bucket + path + kind + name, or ok:false with the '
  'reason in words. finance-docs is private, so the signed URL is minted by an edge function that '
  'calls this to find out what to sign — the caller never names a path.';

-- ── 6. THE STANDING COUNT ──────────────────────────────────────────────────────────────────────
create or replace function public.fn_refund_document_coverage()
returns jsonb language sql stable as $fn$
  select jsonb_build_object(
    'refunds',          count(*),
    'openable',         count(*) filter (where is_openable),
    'reference_only',   count(*) filter (where document_state = 'reference_only'),
    'unclassified',     count(*) filter (where document_state = 'unclassified'),
    'missing',          count(*) filter (where document_state = 'missing'),
    'missing_ids',      coalesce(jsonb_agg(id order by id) filter (where document_state = 'missing'), '[]'::jsonb),
    'stripe_bound',     count(*) filter (where stripe_binding = 'bound'),
    'stripe_unbound_ids', coalesce(jsonb_agg(id order by id)
                            filter (where stripe_binding in ('no_reference','mismatched','no_transaction')), '[]'::jsonb),
    'by_kind',          (select coalesce(jsonb_object_agg(document_state, n), '{}'::jsonb)
                         from (select document_state, count(*) n
                               from public.v_refund_documents group by 1) s))
  from public.v_refund_documents;
$fn$;

comment on function public.fn_refund_document_coverage() is
  'How many refunds carry a document that can actually be opened, how many carry only Stripe''s '
  'hosted receipt reference, and which ids carry nothing — plus how many name the exact Stripe '
  'payment they reverse. The founder''s condition of 9 Sep 2026 made measurable, so a regression '
  'shows up as a number rather than as a blank cell.';
