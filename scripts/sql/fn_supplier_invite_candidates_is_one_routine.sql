-- FN_SUPPLIER_INVITE_CANDIDATES IS ONE ROUTINE (2 Nov 2026, sales_engineer, ledger 1449).
-- MEASURED on production after #1744: two overloads. (integer, text[]) is the canonical body; (integer) was a one-line wrapper that
-- called it with null::text[], so it could not bypass the verified-mailbox gate, but no canonical file defines it, and that turned
-- "repo and database agree" red. Its one routine caller was fn_supplier_campaign_next_list, moved here to the two-argument call.
-- fn_customer_support_campaign_list_tick only names it in a sentence. enqueue_supplier_invites and the restart already pass two.
--
-- The auto-named check lead_email_check_check becomes a named constraint, because the drift check reads names from the repository.

CREATE OR REPLACE FUNCTION public.fn_supplier_campaign_next_list(p_after date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_after date := coalesce(p_after, (now() at time zone 'Asia/Dubai')::date);
  v_day date := v_after + 1; v_skipped jsonb := '[]'::jsonb; v_why text; i int := 0;
  v_cap int; v_pool int; v_n int; v_switch boolean; v_held text; v_rows jsonb;
begin
  loop
    v_why := public.fn_supplier_invites_hold_reason(v_day);
    exit when v_why is null;
    v_skipped := v_skipped || jsonb_build_object('day', v_day, 'why', v_why);
    v_day := v_day + 1; i := i + 1;
    if i > 20 then raise exception 'no supplier sending day within 20 days of %', v_after; end if;
  end loop;
  v_switch := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
              and public.fn_supplier_outreach_golive();
  v_held := case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
                 when not v_switch then 'invite_enabled is false' end;
  -- the sender's own numbers (enqueue_supplier_invites): cap, eligible pool, planned = least of the two
  v_cap := coalesce((select nullif(value, '')::int from public.app_secrets where key = 'invite_daily_cap'), 10);
  -- fn_invite_ramp runs before the batch on the sending day; with nothing sent in the 3 days before it, it resets
  -- the cap to invite_warmup.base_cap (a cold domain restarts). Show that number, not the stale stored cap.
  -- Scoped to the invitation lane exactly as the ramp is (fn_invite_lane_since; '-infinity' while it is off).
  if coalesce((select max(l.invited_at) from public.leads l where l.invited_at >= public.fn_invite_lane_since() and (public.fn_invite_lane_since() = '-infinity'::timestamptz or public.fn_invite_lane_sent(l.id)) and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(l.email)), '-infinity'::timestamptz) < (v_day::timestamp at time zone 'Asia/Dubai') - interval '3 days' then
    v_cap := coalesce((select (nullif(value, '')::jsonb->>'base_cap')::int from public.app_secrets where key = 'invite_warmup'), 30);
  end if;
  select count(*) into v_pool from public.fn_supplier_invite_eligible_ids();   -- the set, read once (see header)
  v_n := greatest(least(v_cap, v_pool), 0);
  select coalesce(jsonb_agg(jsonb_build_object('n', c.rn, 'lead_id', c.lead_id,
            'company', coalesce(nullif(btrim(c.company_name), ''), '(no company name)'),
            'emirate', coalesce(nullif(btrim(l.emirate), ''), '-'), 'language', c.lang,
            'email', public.fn_mask_email(c.to_email)) order by c.rn), '[]'::jsonb)
    into v_rows
    from (select x.*, row_number() over () rn from public.fn_supplier_invite_candidates(v_n, null::text[]) x) c
    join public.leads l on l.id = c.lead_id;
  return jsonb_build_object('send_day', v_day, 'skipped', v_skipped, 'switch_on', v_switch, 'held_because', v_held,
                            'cap', v_cap, 'pool', v_pool, 'planned', v_n, 'rows', v_rows);
end $function$;

drop function if exists public.fn_supplier_invite_candidates(integer);

alter table public.lead_email_check drop constraint if exists lead_email_check_check;
alter table public.lead_email_check drop constraint if exists lead_email_check_verified_needs_mx;
alter table public.lead_email_check add constraint lead_email_check_verified_needs_mx check (verdict <> 'verified' or mx_kind = 'mx');
