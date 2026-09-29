-- PROBE for customer_support_scores_its_own_plain_language_and_tone_every_month.sql (founder instruction 1013 item 7).
-- A pure probe: it always raises CHK<<...>>, so every row it writes rolls back. Seat: customer_support.
-- Three demo replies of last month (one plain, one rewritten, one sent canned because the rewrite was still
-- unreadable) must come out of the monthly self-review as 3 replies, 1 rewrite, 1 canned-because-unreadable,
-- a first-time pass share of 1/3 and a below-target flag - and the real month's row must not be touched.
do $probe$
declare
  v_last timestamptz := ((date_trunc('month', now() at time zone 'Asia/Dubai') - interval '1 month')::timestamp + interval '3 days') at time zone 'Asia/Dubai';
  v_real_before int; v_real_after int; r jsonb; v_bad text := '';
begin
  select count(*) into v_real_before from public.customer_support_monthly_review where not fixture;
  perform set_config('qd.duty_fixtures', 'on', true);
  perform public.fn_support_reply_readability_log('widget', 'en', 'reasoned', false, 100, 100, '{}', null, true);
  perform public.fn_support_reply_readability_log('whatsapp', 'ar', 'reasoned', true, 100, 90, '{}', null, true);
  perform public.fn_support_reply_readability_log('whatsapp', 'en', 'fallback', false, 70, 100, '{long_sentence:40}', 'readability: long_sentence:40', true);
  update public.support_reply_readability set created_at = v_last where demo and created_at > now() - interval '1 minute';
  r := public.fn_customer_support_monthly_self_review();
  select count(*) into v_real_after from public.customer_support_monthly_review where not fixture;
  if (r->>'replies')::int <> 3 then v_bad := v_bad || ' replies=' || (r->>'replies'); end if;
  if (r->>'rewritten')::int <> 1 then v_bad := v_bad || ' rewritten=' || (r->>'rewritten'); end if;
  if (r->>'canned_because_unreadable')::int <> 1 then v_bad := v_bad || ' canned=' || (r->>'canned_because_unreadable'); end if;
  if (r->>'first_time_pass_share')::numeric <> 0.333 then v_bad := v_bad || ' pass=' || (r->>'first_time_pass_share'); end if;
  if not (r->'below_target' ? 'first_time_pass<80%') then v_bad := v_bad || ' below_target=' || (r->>'below_target'); end if;
  if (r->'by_channel'->'whatsapp'->>'replies')::int <> 2 then v_bad := v_bad || ' by_channel'; end if;
  if v_real_after <> v_real_before then v_bad := v_bad || ' real_rows_touched'; end if;
  if v_bad = '' then raise exception 'CHK<<PROBE OK: %>>', r::text;
  else raise exception 'CHK<<PROBE FAILED:% | %>>', v_bad, r::text; end if;
end $probe$;
