-- A LEAD'S STAGE FOLLOWS ITS OWN EVIDENCE: INVITED, REPLIED, REGISTERED, UNDELIVERABLE.
-- Seat: sales_engineer. 18 Nov 2026.
--
-- WHAT WAS MEASURED (production, read-only, 18 Nov 2026):
--   * Shine Carpets Washing L.L.C. (leads 2936): invited 17 Nov 05:00 UTC (invite_status 'sent'), replied 08:30 (inbound_messages
--     2214), registered 08:38 (accepted_terms_at, signed_terms_at, registration_submitted_at), approved 08:40. The row still read
--     lifecycle_stage 'not_contacted' and contacted false the next day.
--   * Nothing live writes either column on an invite, a reply, a registration or an approval: the only routines that read or write
--     lifecycle_stage are sanction screens and reports (read 'registered') and fn_sales_engineer_final_touch_parked_suppliers (reads
--     'no_response'); contacted is set only by inbound_email for a lead it creates. Of 316 invited real leads, 123 sent invitations
--     read 'not_contacted', 16 bounced read 'not_contacted', 4 that replied read 'not_contacted' (2 of them registered), and 314 have
--     contacted false.
--   * invite_followups was 0 because no follow-up WAS sent to Shine (he registered three hours after the invitation); it is counted
--     by the chase in an_interested_prospect_is_chased_three_times_until_he_registers_or_declines.sql, which sends follow-ups.
--
-- WHAT THIS ADDS
--   fn_leads_stage_follows_its_evidence, a BEFORE INSERT OR UPDATE trigger on leads (a20_, before the mandatory-six gate e0 and the
--   z-triggers; it reads only the row, so a bulk update of 20k rows stays cheap). The stage only moves forward, from the row's own
--   fields, never from a guess:
--     registered     terms accepted or signed, registration submitted, or approved. The readers (sanction screens:
--                    lifecycle_stage = 'registered' OR approval_status approved; the bd_manager KPI: 'registered' AND a dated
--                    registration_submitted_at / accepted_terms_at; fn_ws_*) mean a company that took the terms, so a page
--                    that is only claimed is NOT 'registered' (review of #2051);
--     claimed        the portal page is claimed but the terms are not taken yet;
--     replied        set by the reply path (trg_invite_reply_reaches_sales_engineer, the chase booking in the file above), kept here
--                    until he registers;
--     undeliverable  the invitation bounced and nothing better is known;
--     contacted      the invitation was sent (a new value: 'not_contacted' now means what it says; nothing selects on 'contacted');
--     no_response    kept as fn_sales_engineer_final_touch_parked_suppliers reads it, until he replies or registers.
--   contacted (boolean) becomes true when an invitation was sent or bounced, he replied, or he registered after one; it is never
--   set back to false.
-- Backfill of the existing rows: a_leads_stage_follows_its_own_evidence_backfill.sql (one-off, its own pending note, dry-run counts).
--
-- Pending: scripts/sql/pending/a_leads_stage_follows_its_own_evidence.txt
-- Prevented by: scripts/checks/a_leads_stage_follows_its_own_evidence.test.mjs

set local lock_timeout = '1500ms';   -- apply discipline: the trigger DDL on leads gives up rather than queue behind live traffic

create or replace function public.fn_leads_stage_follows_its_evidence()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $fn$
-- 'registered' means he accepted or signed the terms, submitted, or was approved (review of #2051): a page merely claimed is 'claimed'
declare v_reg boolean := new.accepted_terms_at is not null or new.signed_terms_at is not null
                         or new.registration_submitted_at is not null or coalesce(new.approval_status, '') = 'approved';
        v_stage text := coalesce(nullif(btrim(new.lifecycle_stage), ''), 'not_contacted');
begin
  if v_reg then
    new.lifecycle_stage := 'registered';
    if coalesce(new.invite_status, '') in ('sent', 'bounced', 'complained') then new.contacted := true; end if;
    return new;
  end if;
  if coalesce(new.claimed, false) then
    new.lifecycle_stage := 'claimed';
    if coalesce(new.invite_status, '') in ('sent', 'bounced', 'complained') then new.contacted := true; end if;
    return new;
  end if;
  if v_stage = 'replied' then new.contacted := true; return new; end if;
  if coalesce(new.invite_status, '') in ('bounced', 'complained') and v_stage in ('not_contacted', 'contacted') then
    new.lifecycle_stage := 'undeliverable';
  elsif coalesce(new.invite_status, '') = 'sent' and v_stage = 'not_contacted' then
    new.lifecycle_stage := 'contacted';
  end if;
  if coalesce(new.invite_status, '') in ('sent', 'bounced', 'complained') then new.contacted := true; end if;
  return new;
end $fn$;
revoke execute on function public.fn_leads_stage_follows_its_evidence() from public, anon, authenticated;

drop trigger if exists a20_leads_stage_follows_its_evidence on public.leads;
create trigger a20_leads_stage_follows_its_evidence
  before insert or update of claimed, accepted_terms_at, signed_terms_at, registration_submitted_at, approval_status, invite_status, lifecycle_stage
  on public.leads for each row execute function public.fn_leads_stage_follows_its_evidence();
