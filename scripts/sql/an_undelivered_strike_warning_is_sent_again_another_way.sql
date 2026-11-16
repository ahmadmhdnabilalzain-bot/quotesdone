-- AN UNDELIVERED STRIKE WARNING IS SENT AGAIN ANOTHER WAY.
--
-- Assigned: sales_engineer. Agent: W3_PEOPLE, 16 Nov 2026. Founder ledgers 1711-1713; wave-3 brief item 6; REVIEW_NOTFORME
-- ("Optional: let the stop happen only when the strike-2 warning itself was delivered").
--
-- MEASURED BEFORE WRITING (16 Nov 2026, light SELECTs on production):
--   * The stop already waits for a warning that reached him: fn_sales_engineer_counts_unanswered_request (md5
--     0e46c6d9f00dada5c97f39e22f35d5c8) counts the strike that would pause a supplier only when a supplier_strike_warning row since
--     his last clear was delivered or read, or accepted 3+ days ago with no failure. Nothing to change there.
--   * But a warning that did NOT reach him is never sent again: fn_supplier_strike_notice (md5 read 16 Nov) writes ONE e-mail to
--     claimed_by (else leads.email) through fn_sales_engineer_writes, and nothing reads a bounce. Its WhatsApp twin (fn_wa_fanout,
--     to a confirmed number) has no template (send_whatsapp/templates.ts tmplKey maps no supplier_strike_* type), so outside the
--     24-hour window it is never sent either. The supplier then sits one short of the stop for ever, untold, his requests not
--     counted, while the matcher keeps sending him work: a loop that never closes.
--
-- THE CHANGE (the stop rule is untouched):
--   fn_supplier_strike_warning_redeliver, hourly: for each supplier one short of the stop whose warning since his last clear reached
--   no one (every e-mail copy undelivered or failed, or still queued after a day) and was not delivered on WhatsApp, ONE next step
--   per run, in this order, each recorded in supplier_strike_warning_retry:
--     1. a WhatsApp copy to his confirmed number (fn_whatsapp_destination), when none is on its way (at most two);
--     2. the same warning to another address the company has: its listed e-mail, then each active member's (#2017), one at a time,
--        each tried once, the next only after the last one failed;
--     3. nothing left: ONE pending task for the sales engineer to reach him another way (never silent).
--   send_whatsapp maps supplier_strike_warning and supplier_strike_stopped to the approved supplier_account_notice template.
--
-- prevented by: an_undelivered_strike_warning_is_sent_again_another_way_probe.sql (LOCAL Postgres 16) and
-- send_whatsapp/strike_notice_template.test.ts.

set local lock_timeout = '3s';

create table if not exists public.supplier_strike_warning_retry (
  id         bigint generated always as identity primary key,
  lead_id    bigint not null references public.leads(id),
  step       text not null check (step in ('whatsapp', 'other_address', 'task')),
  address    text,
  created_at timestamptz not null default now()
);
create index if not exists supplier_strike_warning_retry_lead_idx on public.supplier_strike_warning_retry (lead_id, created_at desc);
alter table public.supplier_strike_warning_retry enable row level security;
drop policy if exists supplier_strike_warning_retry_service_role_only on public.supplier_strike_warning_retry;
create policy supplier_strike_warning_retry_service_role_only on public.supplier_strike_warning_retry as permissive for all to public using (false) with check (false);
revoke all on public.supplier_strike_warning_retry from anon, authenticated;

create or replace function public.fn_supplier_strike_warning_redeliver()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_limit int := public.fn_matching_strike_limit(); r record; w record; v_since timestamptz; v_dest text; v_addr text;
  v_wa int := 0; v_mail int := 0; v_task int := 0; v_body text;
begin
  for r in select l.id, l.claimed_by, l.email, l.company_name, coalesce(l.is_demo, false) as is_demo
             from public.leads l
            where coalesce(l.chat_strikes, 0) = v_limit - 1 and coalesce(l.claimed_by, '') <> ''
              and exists (select 1 from public.notifications n where n.type = 'supplier_strike_warning' and n.lead_id = l.id)
            order by l.id limit 200 loop
    v_since := coalesce((select max(x.created_at) from public.supplier_strike_event x where x.lead_id = r.id and x.kind = 'cleared'), '-infinity'::timestamptz);
    -- REACHED (the production stop rule's own test, on every channel): nothing to do
    continue when exists (select 1 from public.notifications n
                           where n.type = 'supplier_strike_warning' and n.lead_id = r.id and n.created_at > v_since
                             and (n.provider_status in ('delivered', 'read')
                                  or (n.status = 'sent' and coalesce(n.sent_at, n.created_at) <= now() - interval '3 days'
                                      and coalesce(n.provider_status, '') not in ('undelivered', 'failed'))));
    -- the latest e-mail warning since the clear; none at all: nothing to copy (the strike routine never wrote one)
    select n.subject, n.body into w from public.notifications n
     where n.type = 'supplier_strike_warning' and n.lead_id = r.id and n.channel = 'email' and n.created_at > v_since
     order by n.id limit 1;
    continue when not found;
    -- STILL ON ITS WAY: an e-mail copy not failed and less than a day old, or a WhatsApp copy queued or sent and not failed
    continue when exists (select 1 from public.notifications n
                           where n.type = 'supplier_strike_warning' and n.lead_id = r.id and n.channel = 'email' and n.created_at > v_since
                             and coalesce(n.provider_status, '') not in ('undelivered', 'failed')
                             and coalesce(n.status, '') not in ('failed', 'bounced', 'skipped')
                             and (n.status = 'sent' or n.created_at > now() - interval '1 day'));
    continue when exists (select 1 from public.notifications n
                           where n.type = 'supplier_strike_warning' and n.lead_id = r.id and n.channel = 'whatsapp' and n.created_at > v_since
                             and coalesce(n.provider_status, '') not in ('undelivered', 'failed')
                             and coalesce(n.status, '') not in ('failed', 'skipped', 'bounced')
                             and (n.status = 'sent' or n.created_at > now() - interval '1 day'));
    v_body := regexp_replace(coalesce(w.body, ''), E'\\n\\nQuotesDone sales engineer\\s*$', '');

    -- 1. ANOTHER CHANNEL: his confirmed WhatsApp number, when no copy is on its way (at most two copies)
    v_dest := public.fn_whatsapp_destination('supplier', null, r.id, r.claimed_by);
    if v_dest is not null and (select count(*) from public.notifications n where n.type = 'supplier_strike_warning' and n.lead_id = r.id
                                  and n.channel = 'whatsapp' and n.created_at > v_since) < 2 then
      insert into public.notifications (type, to_email, to_role, to_phone, lead_id, subject, body, channel, status)
      values ('supplier_strike_warning', r.claimed_by, 'supplier', v_dest, r.id, w.subject, v_body, 'whatsapp', 'queued');
      insert into public.supplier_strike_warning_retry (lead_id, step, address) values (r.id, 'whatsapp', right(v_dest, 4));
      v_wa := v_wa + 1;
      continue;
    end if;

    -- 2. ANOTHER ADDRESS the company has, each tried once: its listed e-mail, then each active member's
    select a.addr into v_addr
      from (select lower(btrim(r.email)) as addr, 0 as ord
            union all
            select lower(m.email), 1 from public.supplier_member m
             where m.lead_id = r.id and m.status in ('active', 'screening') and public.fn_supplier_member_counts(m.id)) a
     where coalesce(a.addr, '') like '%@%'
       and not exists (select 1 from public.notifications n where n.type = 'supplier_strike_warning' and n.lead_id = r.id
                         and n.created_at > v_since and lower(n.to_email) = a.addr)
     order by a.ord, a.addr limit 1;
    if v_addr is not null then
      perform public.fn_sales_engineer_writes('supplier_strike_warning', 'supplier', v_addr, r.id, null, null, null,
        coalesce(w.subject, 'Please answer your QuotesDone job requests'), v_body, null, null, '{}'::text[],
        'supplier_strike_warning_retry:' || r.id || ':' || v_addr);
      insert into public.supplier_strike_warning_retry (lead_id, step, address) values (r.id, 'other_address', v_addr);
      v_mail := v_mail + 1;
      continue;
    end if;

    -- 3. NOTHING LEFT TO TRY: one task for the sales engineer, never silent
    if not exists (select 1 from public.agent_actions a where a.kind = 'supplier_strike_warning_undelivered'
                    and a.target_id = 'supplier_strike_warning_undelivered:' || r.id and a.status = 'pending') then
      insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
      values ('sales_engineer', 'supplier_strike_warning_undelivered', 'pending', 'low',
              left('The unanswered-requests warning never reached ' || coalesce(r.company_name, 'supplier #' || r.id), 200),
              'He is one unanswered request short of the stop and the warning reached no address or number we hold. The stop waits until a '
              || 'warning reaches him. Reach him another way (his phone), and correct his e-mail or WhatsApp number.',
              jsonb_build_object('supplier_id', r.id, 'tried', (select jsonb_agg(jsonb_build_object('to', n.to_email, 'channel', n.channel,
                                   'status', n.status, 'provider_status', n.provider_status) order by n.id)
                                   from public.notifications n where n.type = 'supplier_strike_warning' and n.lead_id = r.id and n.created_at > v_since),
                                 'demo', r.is_demo),
              'leads', 'supplier_strike_warning_undelivered:' || r.id);
      insert into public.supplier_strike_warning_retry (lead_id, step) values (r.id, 'task');
      v_task := v_task + 1;
    end if;
  end loop;
  return jsonb_build_object('whatsapp', v_wa, 'other_address', v_mail, 'tasks', v_task);
end $fn$;
revoke execute on function public.fn_supplier_strike_warning_redeliver() from public, anon, authenticated;
grant execute on function public.fn_supplier_strike_warning_redeliver() to service_role;

select cron.schedule('supplier_strike_warning_redeliver_hourly', '23 * * * *',
  $CRON$set statement_timeout = '30s'; select public.fn_supplier_strike_warning_redeliver();$CRON$);

insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('supplier_strike_warning_redeliver_hourly', 'Unanswered-requests warning sent again', 'Suppliers',
   'fn_supplier_strike_warning_redeliver() every hour at :23: a supplier one short of the stop whose warning reached nobody gets it '
   || 'on WhatsApp, then at another company address, else the sales engineer gets one task to reach him. W3_PEOPLE, 16 Nov 2026.')
on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'supplier_strike_warning_redeliver_hourly', 'sales_engineer',
   'fn_supplier_strike_warning_redeliver() hourly at :23: an undelivered unanswered-requests warning is sent again another way.',
   'scripts/sql/an_undelivered_strike_warning_is_sent_again_another_way.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;
