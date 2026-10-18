-- PROBE: THE CEO'S MANAGEMENT REVIEW REQUEST FITS THE REASONING LIMIT.
--
-- Seat: ceo. 5 Oct 2026. Pure probe: no DDL, nothing survives it. Run AFTER
-- the_ceo_management_review_request_fits_the_reasoning_limit.sql (or appended to it in the same query, so the
-- CREATE OR REPLACE rolls back with it), as ONE query through the Management API; never applied.
-- WHAT IT RUNS, inside a sub-block that always raises: any review already filed for this week is cleared, then
-- fn_ceo_management_review() runs for real on today's production facts (the week holding 1 Oct 2026, the September
-- review that failed).
-- VERDICT: PROBE OK only if a reasoning_held_question was filed, its request is a JSON object of <= 60,000
-- characters, and the duties still carry each seat_duty (duty, failures) for the reviewer.
do $probe$
declare r jsonb; v_len int; v_type text; v_duties int; v_all int; v_err text;
begin
  begin
    update public.ceo_review set held_id = null where kind = 'management_review' and period = public.fn_ceo_review_week();
    r := public.fn_ceo_management_review();
    select length(h.request::text), jsonb_typeof(h.request),
           (select count(*) from public.ceo_review c, jsonb_each(c.facts->'seats') s, jsonb_array_elements(s.value->'duties') d
             where c.kind = 'management_review' and c.period = public.fn_ceo_review_week())
      into v_len, v_type, v_duties
      from public.reasoning_held_question h where h.id = (r->>'filed')::bigint;
    select count(*) into v_all from public.seat_duty d join public.org_role o on o.role_id = d.owner_seat and o.status = 'active';
    raise exception 'ZZPROBE rollback';
  exception when others then
    v_err := sqlerrm;
  end;
  if v_err <> 'ZZPROBE rollback' then
    raise exception 'CHK<<PROBE FAIL the routine raised: %>>', v_err;
  elsif v_len is null then
    raise exception 'CHK<<PROBE FAIL no reasoning question was filed: %>>', r;
  elsif v_type <> 'object' or v_len > 60000 then
    raise exception 'CHK<<PROBE FAIL request is % of % characters>>', v_type, v_len;
  elsif v_duties <> v_all then
    raise exception 'CHK<<PROBE FAIL the review carries % of % duties>>', v_duties, v_all;
  end if;
  raise exception 'CHK<<PROBE OK request=% chars, duties=%>>', v_len, v_duties;
end $probe$;
