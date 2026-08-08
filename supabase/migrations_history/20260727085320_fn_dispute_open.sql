-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727085320   name: fn_dispute_open
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_dispute_open(
  p_stripe_dispute_id text,
  p_stripe_charge_id text,
  p_payment_ref text,
  p_amount_aed numeric,
  p_reason text,
  p_evidence_due_by timestamptz
) returns bigint
language plpgsql security definer set search_path = public as $fn$
declare v_id bigint; v_txn bigint;
begin
  select id into v_txn from transactions where payment_ref = p_payment_ref limit 1;

  insert into payment_dispute (stripe_dispute_id, stripe_charge_id, payment_ref, transaction_id,
                               amount_aed, reason, evidence_due_by)
  values (p_stripe_dispute_id, p_stripe_charge_id, p_payment_ref, v_txn,
          p_amount_aed, p_reason, p_evidence_due_by)
  on conflict (stripe_dispute_id) do update set
    status = 'needs_response', evidence_due_by = excluded.evidence_due_by
  returning id into v_id;

  insert into founder_alerts (level, event, detail, channel)
  values ('crit','payment_dispute',
          format('Card dispute opened: AED %s, reason "%s", evidence due %s. Stripe dispute %s. An unanswered dispute is lost automatically and counts toward the account dispute rate.',
                 coalesce(p_amount_aed,0), coalesce(p_reason,'unknown'),
                 coalesce(p_evidence_due_by::text,'unknown'), p_stripe_dispute_id),
          'system');

  insert into company_event (event_type, entity_type, entity_id, actor, payload)
  values ('invoice.flagged','dispute', p_stripe_dispute_id, 'cfo',
          jsonb_build_object('amount_aed', p_amount_aed, 'reason', p_reason,
                             'evidence_due_by', p_evidence_due_by, 'transaction_id', v_txn));

  insert into institutional_memory (kind, subject_type, subject_id, headline, detail, outcome,
                                    money_aed, learned_by, confidence, evidence_ref)
  values ('pattern','dispute', p_stripe_dispute_id,
          'Card dispute opened on a reveal fee.',
          format('Reason "%s" on AED %s. Disputes on a facilitation fee usually mean the buyer did not understand what they paid for, or the supplier never responded after reveal.', coalesce(p_reason,'unknown'), coalesce(p_amount_aed,0)),
          'open', p_amount_aed, 'cfo', 1.0, 'payment_dispute id '||v_id);

  return v_id;
end; $fn$;
