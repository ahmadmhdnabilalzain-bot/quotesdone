-- THE WEBHOOK ASKS THE DATABASE TO ATTACH THE RECEIPT.
--
-- The Stripe refund work earlier today added one direct write from the handler:
--
--     await admin.from('refunds').update({ stripe_receipt_url: receiptUrl })
--
-- It is benign in itself — a link to the charge's hosted receipt, guarded by `.is(null)` so it
-- cannot overwrite one, and wrapped so a failure cannot un-settle a refund. But the standing check
-- `settlement is delegated to the database, not reimplemented in the handler` refused it, and the
-- check is right to. Its rule is not "do not write settlement fields"; it is "the handler does not
-- write to refunds AT ALL", and that is deliberate — the moment one direct write is allowed because
-- it is harmless, the next one is argued for on the same grounds, and the ordering guard that makes
-- Stripe deliveries idempotent stops being the only path.
--
-- So the write moves behind a routine. The handler asks; the database decides. Same effect, and the
-- rule survives intact.
--
-- WHAT THE ROUTINE REFUSES, and why each matters:
--   an unknown refund id      — a receipt attached to nothing is a silent no-op that reads as success
--   a URL that is not Stripe's — this column is shown to the founder and the CEO as the document
--                                behind a refund; it must not be able to point anywhere else
--   overwriting an existing one — the first receipt recorded is the one the money moved under
--
-- WHY THERE IS STILL NO PDF. stripe_checkout creates the reveal-fee session with mode=payment and
-- no invoice_creation, so Stripe mints no Invoice object and there is no invoice_pdf to fetch. The
-- only artefact that exists is the charge's hosted receipt page, and `charge.refunded` is the one
-- event carrying it. That is a reference, not a stored document, and the founder has a real choice
-- to make: turn on invoice_creation so Stripe issues a proper invoice per reveal fee, or render the
-- hosted receipt to PDF and store it. Neither is a decision this routine should make for him.

create or replace function public.fn_refund_attach_receipt(p_refund_id bigint, p_receipt_url text)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_existing text; v_ok boolean;
begin
  if p_refund_id is null or p_refund_id <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'no refund id');
  end if;
  if coalesce(btrim(p_receipt_url), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'no receipt url');
  end if;
  -- Stripe's hosted receipts live on stripe.com. A column the founder and the CEO open as "the
  -- document behind this refund" may not be made to point somewhere else by a spoofed payload.
  if p_receipt_url !~ '^https://[a-z0-9.-]*\.?stripe\.com/' then
    return jsonb_build_object('ok', false, 'reason', 'not a stripe.com receipt url', 'given', left(p_receipt_url, 120));
  end if;

  select stripe_receipt_url into v_existing from public.refunds where id = p_refund_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', format('no refund %s', p_refund_id));
  end if;
  if coalesce(v_existing, '') <> '' then
    return jsonb_build_object('ok', true, 'unchanged', true, 'reason', 'a receipt is already recorded; the first one is the one the money moved under');
  end if;

  update public.refunds set stripe_receipt_url = p_receipt_url
   where id = p_refund_id and stripe_receipt_url is null;
  get diagnostics v_ok = row_count;
  return jsonb_build_object('ok', v_ok, 'refund_id', p_refund_id);
end $fn$;
revoke execute on function public.fn_refund_attach_receipt(bigint, text) from public, anon, authenticated;

do $do$
declare v jsonb;
begin
  -- Every refusal, proved. There are 0 refunds, so the id checks are the ones that can run for real.
  v := public.fn_refund_attach_receipt(null, 'https://pay.stripe.com/receipts/x');
  if (v->>'ok')::boolean then raise exception 'accepted a null refund id'; end if;

  v := public.fn_refund_attach_receipt(999999999, 'https://pay.stripe.com/receipts/x');
  if (v->>'ok')::boolean then raise exception 'accepted an unknown refund id'; end if;
  if v->>'reason' !~ '999999999' then raise exception 'the refusal did not name the id'; end if;

  -- THE ONE THAT MATTERS: a non-Stripe URL must be refused before any lookup.
  v := public.fn_refund_attach_receipt(1, 'https://evil.example.com/receipts/x');
  if (v->>'ok')::boolean then raise exception 'accepted a receipt url that is not Stripe''s'; end if;
  if v->>'reason' <> 'not a stripe.com receipt url' then
    raise exception 'a non-Stripe URL was refused for the wrong reason: %', v->>'reason';
  end if;

  -- And a lookalike domain must not pass the pattern.
  v := public.fn_refund_attach_receipt(1, 'https://stripe.com.evil.example/receipts/x');
  if (v->>'ok')::boolean then raise exception 'a lookalike domain passed the receipt check'; end if;

  v := public.fn_refund_attach_receipt(1, '');
  if (v->>'ok')::boolean then raise exception 'accepted an empty url'; end if;

  raise notice 'RECEIPT ATTACHMENT DELEGATED. The handler no longer writes to refunds. Refused: null id, unknown id, non-Stripe URL, stripe.com lookalike, empty URL.';
end
$do$;
