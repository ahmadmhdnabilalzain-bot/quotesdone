-- FIGMA WAS CANCELLED, AND CHATGPT IS COMING.
--
-- The founder, 9 September 2026: "figma cancelled" and "chatgpt will be shared later".
--
-- These close the last two questions the vendor-side completeness check was asking, and they close
-- them DIFFERENTLY, which is the point of having more than one kind of answer.
--
-- FIGMA: one receipt (10 Jul 2026, USD 20.00), silent for 70 days, and now known to be cancelled.
-- No money is missing. It is recorded as `ended` and leaves the shortfall list for good.
--
-- CHATGPT: NOT closed, and deliberately left open. It stays `portal_only` -- still billing monthly,
-- never emails an invoice, so the August and September charges are real and unbooked. "Will be
-- shared later" is a promise about evidence arriving, not evidence that has arrived, and a report
-- that stopped saying so because somebody intends to fix it would be lying about the present to
-- flatter the future. It keeps appearing as a named shortfall with its remedy attached until the
-- invoices are actually booked, at which point it stops on its own.
--
-- That distinction is the whole design: `ended`, `annual` and `one_off` mean nothing is missing;
-- `portal_only` means something IS missing and we know where it is. A promise to send it later
-- belongs in neither category and changes nothing.
--
-- No figure moves. Figma was already booked; ChatGPT's missing months are still not invented.

insert into public.vendor_billing_ended (vendor, ended_after, kind, basis, note)
values ('Figma', date '2026-07-10', 'ended', 'founder',
        'Founder''s own words, 9 Sep 2026: "figma cancelled". One receipt was booked (10 Jul 2026, '
        || 'USD 20.00 = AED 73.45) and no charge is expected after it. Recorded so the cadence check '
        || 'asks once rather than on every report.')
on conflict (vendor) do update
  set kind = excluded.kind, ended_after = excluded.ended_after,
      basis = excluded.basis, note = excluded.note;

do $do$
declare v jsonb; r jsonb; v_figma int; v_openai int; v_entries int;
begin
  select count(*) into v_entries from public.expense_entries;
  if v_entries = 0 then
    raise exception 'POSITIVE CONTROL FAILED: expense_entries is empty, so nothing here is tested';
  end if;
  if (select count(*) from public.expense_entries where vendor = 'Figma') <> 1 then
    raise exception 'POSITIVE CONTROL FAILED: Figma does not have exactly one booked receipt, so the case being closed is not the case described';
  end if;

  v := public.fn_accountant_receipt_cadence_gaps();

  -- Figma must be gone from the shortfall lists...
  select count(*) into v_figma
    from jsonb_array_elements(v->'vendors_seen_once_unexplained') x
   where lower(x->>'vendor') = 'figma';
  if v_figma > 0 then
    raise exception 'Figma is still reported despite being recorded as cancelled';
  end if;

  -- ...and OpenAI must NOT be. A promise to send the invoices later is not the invoices.
  select count(*) into v_openai
    from jsonb_array_elements(v->'vendors_billing_outside_email') x
   where lower(x->>'vendor') = 'openai';
  if v_openai = 0 then
    raise exception 'OpenAI stopped being reported, but its August and September invoices are still unbooked';
  end if;

  -- And the report must still refuse to call itself complete while that stands.
  r := public.fn_accountant_spend_report();
  if (r->>'complete')::boolean then
    raise exception 'the report claims complete while OpenAI''s invoices are unbooked';
  end if;

  raise notice 'Figma closed as ended; OpenAI still named (% suspected); report complete = %',
    v->>'suspected_missing', r->>'complete';
end
$do$;
