-- A PAID REVEAL OPENS THE SUPPLIER RESPONSE WATCH (19 Oct 2026, agent: sales_engineer).
--
-- public.supplier_response_watch is the evidence every non-response refund rests on (one row per
-- transaction; first_response_at NULL is the silence). Measured 19 Oct 2026: 0 rows, ever. The only
-- routines that insert into it are fn_support_record_supplier_contact (called by nothing) and
-- fn_sales_engineer_attaches_delivery_result (only on a proof of response). So a reveal never opened
-- a watch, the silence of a supplier who never answered was recorded nowhere, and sandbox run 5
-- (tag 321d13ae) S12 found no watch on the revealed supplier.
--
-- The watch now opens on the sale itself, in the same transaction that records it: whichever path
-- writes the paid transaction (element_pay, element_settle, stripe_webhook invoice.paid, a manual
-- reveal), the watch exists. Idempotent on the unique transaction_id. Attempts and replies are
-- appended later by the chase ladder exactly as before.
--
-- Prevented by: scripts/checks/a_paid_reveal_opens_the_supplier_response_watch.test.mjs

create or replace function public.trg_reveal_opens_response_watch()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if NEW.fee_status = 'paid' and NEW.revealed_at is not null and NEW.supplier_id is not null
     and (TG_OP = 'INSERT' or OLD.revealed_at is null or OLD.fee_status is distinct from 'paid') then
    insert into public.supplier_response_watch (transaction_id, lead_id)
    values (NEW.id, NEW.supplier_id)
    on conflict (transaction_id) do nothing;
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_reveal_opens_response_watch() from public, anon, authenticated;

drop trigger if exists z25_reveal_opens_response_watch on public.transactions;
create trigger z25_reveal_opens_response_watch
  after insert or update of revealed_at, fee_status on public.transactions
  for each row execute function public.trg_reveal_opens_response_watch();

-- Verdict: the trigger is attached and enabled. Behaviour is proved end to end by the sandbox
-- harness S12 (scripts/e2e/stage2.mjs), which reveals with a Stripe TEST card and reads the watch.
select case when exists (select 1 from pg_trigger
                          where tgrelid = 'public.transactions'::regclass
                            and tgname = 'z25_reveal_opens_response_watch' and tgenabled <> 'D')
            then 'PROBE OK' else 'PROBE FAILED: z25_reveal_opens_response_watch is not attached' end as verdict;
