-- THE REMINDER STOPS WHICHEVER DOOR THE LICENCE CAME THROUGH
--
-- Build spec §6 and §15: the three intake paths must behave the same, and §15 names "cancellation of
-- obsolete reminders after approval" among the scenarios that must pass.
--
-- THE GAP THIS CLOSES IS ONE I OPENED THIS SESSION. fn_licence_ask_close_on_intake reads
-- wa_document_intake, and nothing else. When email and portal intake was built, a supplier who
-- replied to the renewal email with their new licence attached had it filed correctly -- and then
-- kept being chased for it, because the ask was only ever answered by a WhatsApp row.
--
-- That is the worst shape of chase: the company has the document, the file is complete, and the
-- reminder keeps going out. The supplier concludes nobody read their email, which is exactly what
-- they concluded before -- 81 invited, 0 registered.
--
-- ONE CLOSER, TAKING THE FACT RATHER THAN THE TABLE. The existing WhatsApp function keeps its
-- signature because five callers use it; it now delegates, so there is one implementation of
-- "a licence arrived for this lead, stop asking" rather than two that must be kept in step.

create or replace function public.fn_licence_ask_close_for_lead(
  p_lead_id bigint,
  p_source  text,
  p_source_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_closed int;
begin
  if p_lead_id is null then
    return jsonb_build_object('ok', true, 'closed', 0,
      'reason', 'no lead, so no ask is answered. A document held for an unmatched sender has not arrived for anybody yet.');
  end if;

  -- ANSWERED, not sent. The distinction the original function was built around and which this
  -- preserves: an ask closes when a document ARRIVES, never when a message goes out.
  update public.licence_renewal_ask
     set answered_at = now(),
         answered_by_intake = case when p_source = 'whatsapp' then p_source_id else answered_by_intake end
   where lead_id = p_lead_id and answered_at is null;
  get diagnostics v_closed = row_count;

  return jsonb_build_object('ok', true, 'closed', v_closed, 'lead_id', p_lead_id, 'source', p_source,
    'note', 'Every open renewal ask for this supplier is answered by the document that arrived, whichever door it came through.');
end $function$;

comment on function public.fn_licence_ask_close_for_lead is
  'The one place a renewal ask is answered. answered_by_intake still points at wa_document_intake because that is what the column references; the email and portal paths record their source in the return rather than writing a foreign key into a table the row does not belong to.';

-- The WhatsApp entry point keeps its signature -- five callers use it -- and delegates, so there is
-- one implementation rather than two that have to be kept in step.
create or replace function public.fn_licence_ask_close_on_intake(p_intake_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare v_i record;
begin
  select * into v_i from public.wa_document_intake where id = p_intake_id;
  if not found or v_i.lead_id is null or v_i.classified_as <> 'licence' or not v_i.attached then
    return jsonb_build_object('ok', true, 'closed', 0,
      'reason', 'Not an attached licence for a known lead, so no renewal ask is answered by it.');
  end if;
  return public.fn_licence_ask_close_for_lead(v_i.lead_id, 'whatsapp', p_intake_id);
end;
$fn$;

revoke execute on function public.fn_licence_ask_close_for_lead(bigint,text,bigint) from public;
revoke execute on function public.fn_licence_ask_close_for_lead(bigint,text,bigint) from anon;
revoke execute on function public.fn_licence_ask_close_for_lead(bigint,text,bigint) from authenticated;
