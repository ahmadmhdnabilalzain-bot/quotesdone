-- Close the two money-safety holes the proof-based money audit found. The founder's #1 hard rule:
-- EVERY refund reaches him; agents never move money autonomously. The DB gate on public.refunds was
-- proven airtight, but the REAL Stripe actuator (edge function refunds_api) writes public.transactions
-- and calls Stripe directly, never touching public.refunds — so the gate protected a path the actuator
-- bypasses (MNY-02), and an autonomous outbound credential is scoped to call that actuator (MNY-01).
--
--   node scripts/apply_sql.mjs scripts/sql/money_reaches_only_the_founder_at_the_real_path.sql --apply --ddl

begin;

-- MNY-01. Remove refunds_api from the autonomous caller credential (id 53, fn.cos_execute) scope, so no
-- autonomous executor can invoke the Stripe-refund actuator. (No code invokes it today; this closes the
-- capability, not just the current callers.)
update public.internal_credential
   set scope = array_remove(scope, 'refunds_api')
 where id = 53 and 'refunds_api' = any(scope);

-- MNY-02. Defense in depth where the money actually moves: a refund_status transition into a
-- money-moved value on public.transactions must correspond to a row in the founder-gated public.refunds
-- table (which enforces the founder decision via fn_phase_c_refund_execution_requires_decision). An
-- actuator that writes transactions WITHOUT a refunds record is refused — it cannot bypass the gate.
create or replace function public.fn_transactions_refund_needs_the_founder_gate()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
begin
  -- only the transition INTO a money-moved refund_status is gated
  if tg_op = 'UPDATE' and NEW.refund_status is not distinct from OLD.refund_status then return NEW; end if;
  if lower(coalesce(NEW.refund_status,'')) not in ('refunded','processing','succeeded','approved') then
    return NEW;
  end if;
  -- there must be a refunds row for this transaction; that table is founder-gated (z00/z05), so a
  -- refund recorded there has either a founder decision or a recorded external-Stripe origin.
  -- refunds.transaction_id is uuid and matches transactions.id; original_txn_id is a bigint legacy
  -- key that cannot reference a uuid transaction, so it is deliberately not compared here.
  if not exists (
    select 1 from public.refunds r where r.transaction_id = NEW.id
  ) then
    raise exception 'transactions.refund_status -> % for transaction % has no row in public.refunds; a refund must go through the founder-gated refunds path (every refund reaches the founder)',
      NEW.refund_status, NEW.id
      using errcode = 'insufficient_privilege';
  end if;
  return NEW;
end
$function$;
revoke execute on function public.fn_transactions_refund_needs_the_founder_gate() from public;

drop trigger if exists z00_transactions_refund_needs_founder on public.transactions;
create trigger z00_transactions_refund_needs_founder
  before update on public.transactions
  for each row execute function public.fn_transactions_refund_needs_the_founder_gate();

commit;
