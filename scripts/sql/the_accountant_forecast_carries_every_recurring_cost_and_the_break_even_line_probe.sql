-- PROBE for the_accountant_forecast_carries_every_recurring_cost_and_the_break_even_line.sql. Seat: accountant. Never
-- applied: it always raises CHK<<...>> and rolls back. A read of the forecast, asserted on the books it reads.
do $probe$
declare f jsonb; v_bad text := ''; v_items text[]; v text;
begin
  perform public.fn_break_even_ledger(now());
  f := public.fn_accountant_cash_forecast(date '2026-11-10', 'mashreq');
  select array_agg(distinct e->>'item') into v_items from jsonb_array_elements(f->'flows') e where e->>'source' = 'books_recurring';
  foreach v in array array['supabase', 'vercel', 'godaddy', 'resend', 'glockapps', 'google', 'openrouter'] loop
    if not (v = any(coalesce(v_items, '{}'))) then v_bad := v_bad || ' missing:' || v; end if;
  end loop;
  foreach v in array array['github', 'ubicloud', 'namespace', 'apify', 'anthropic', 'openai'] loop
    if v = any(coalesce(v_items, '{}')) then v_bad := v_bad || ' counted:' || v; end if;
  end loop;
  if f->'break_even' is null or f->'break_even' = 'null'::jsonb then v_bad := v_bad || ' no-break-even-line'; end if;
  if jsonb_array_length(f->'weeks') <> 13 then v_bad := v_bad || ' weeks=' || jsonb_array_length(f->'weeks'); end if;
  if v_bad <> '' then raise exception 'CHK<<PROBE FAILED:%>>', v_bad; end if;
  raise exception 'CHK<<PROBE OK books_recurring %; break-even %>>', v_items, f->'break_even';
end $probe$;
