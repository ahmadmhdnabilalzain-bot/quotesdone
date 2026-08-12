-- THE SUPPLIER COULD ASK BUT COULD NOT CHANGE
--
-- fn_wa_context already lets a supplier ask the command channel anything about their own record —
-- is my profile approved, how many inquiries have I missed, what was my last quotation — and the
-- scoping is done in SQL off their phone number so a prompt can never reach another person's rows.
-- What they cannot do is the one thing on the founder's list that is a verb: "adjust my quotation
-- price".
--
-- The founder got that capability on 13 Aug as fn_founder_settings() + fn_founder_apply_setting():
-- a registry the model maps a sentence onto, type and bounds checked in SQL, an audit row whether
-- it applied or refused, and a refusal that teaches instead of stonewalling. This is that same
-- shape for a supplier, with the scoping moved from "trust the caller" to "derive it from the
-- phone", because a supplier is not the founder and the blast radius of a mistake is someone
-- else's money.
--
-- ONE TABLE FOR BOTH NON-FOUNDER AUDIENCES. founder_directive already exists with exactly the
-- right columns, and writing a supplier's price change into a table called founder_directive would
-- be the defect this session has found four times: a record whose name says something other than
-- what it holds.
create table if not exists public.channel_directive (
  id           bigserial primary key,
  actor_type   text not null check (actor_type in ('supplier','customer')),
  actor_id     bigint,
  actor_phone  text,
  channel      text not null default 'whatsapp',
  inbound      text,
  field        text,
  target_id    text,
  old_value    text,
  new_value    text,
  applied      boolean not null default false,
  refusal      text,
  created_at   timestamptz not null default now()
);

comment on table public.channel_directive is
  'Every write a supplier or customer asked for over a messaging channel, applied or refused, with the sentence that asked for it. The refusals matter as much as the applications: a refused price change is the record that the guard fired.';

-- Production adds RLS to a new table by event trigger and staging does not, so the same DDL
-- otherwise produces two different tables and project_parity fails. Declared here for both.
alter table public.channel_directive enable row level security;
revoke all on public.channel_directive from anon, authenticated;

create index if not exists channel_directive_actor_idx on public.channel_directive(actor_type, actor_id, created_at desc);

-- ---------------------------------------------------------------------------------------------
-- WHAT A SUPPLIER MAY CHANGE BY MESSAGE, AND WHAT STOPS THEM.
--
-- Exactly one field today, because exactly one was asked for. The registry exists so the second
-- one is a row rather than a rewrite, and so a refusal can list what IS possible.
create or replace function public.fn_supplier_changeable()
 returns table (field text, kind text, description text)
 language sql
 stable
as $function$
  select 'quote_price', 'number',
         'The amount on your open quotation. It can be changed while the customer has not paid to reveal you, the quotation is not committed, and the request is still open.';
$function$;

-- The write. Everything that decides is in here, in SQL, off the phone number — the model's only
-- job upstream is to turn a sentence into (field, value), and if it gets that wrong the checks
-- below are what stops it becoming someone else's problem.
create or replace function public.fn_supplier_apply_change(
    p_phone text, p_field text, p_value text, p_inbound text,
    p_quote_id uuid default null, p_channel text default 'whatsapp')
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_lead bigint; v_num numeric; v_q record; v_n int; v_refusal text; v_old numeric; v_list text;
        v_company text;
begin
  -- SCOPE FIRST, AND FROM THE PHONE. Nothing downstream takes a supplier id from the caller.
  v_lead := public.fn_wa_lead_id(p_phone);
  if v_lead is null then
    insert into public.channel_directive(actor_type, actor_phone, channel, inbound, field, applied, refusal)
    values ('supplier', p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, false, 'no supplier account matches this number');
    return jsonb_build_object('ok', false, 'refusal',
      'This number is not linked to a supplier account, so there is nothing of yours I can change. Sign in at https://quotesdone.com/suppliers.');
  end if;
  select company_name into v_company from public.leads where id = v_lead;

  if not exists (select 1 from public.fn_supplier_changeable() c where c.field = p_field) then
    v_refusal := 'I cannot change "' || coalesce(p_field,'(nothing)') || '" from a message. What I can change this way: '
              || (select string_agg(c.field, ', ' order by c.field) from public.fn_supplier_changeable() c)
              || '. Everything else — your licence, your company details, and generating a new quotation — is in the portal.';
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal);
  end if;

  begin v_num := p_value::numeric; exception when others then v_num := null; end;
  if v_num is null or v_num <= 0 then
    v_refusal := '"' || coalesce(p_value,'') || '" is not an amount I can put on a quotation.';
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal);
  end if;

  -- WHICH QUOTATION. Editable means: theirs, still open, nobody has paid to reveal them, not
  -- committed, not already accepted. Each of those is a different reason and each gets said.
  select count(*) into v_n
    from public.quotes q
    join public.inquiries i on i.id = q.inquiry_id
   where q.supplier_id = v_lead
     and (p_quote_id is null or q.id = p_quote_id)
     and q.committed_at is null
     and coalesce(q.status,'') not in ('accepted','withdrawn','expired')
     and coalesce(i.status,'') not in ('concluded','closed','cancelled','awarded')
     and not exists (select 1 from public.transactions t
                      where t.inquiry_id = q.inquiry_id and t.supplier_id = q.supplier_id
                        and t.revealed_at is not null);

  if v_n = 0 then
    -- Say WHY there is nothing to change rather than "no quotation found", which is true of a
    -- supplier who has never quoted and of one whose customer paid an hour ago.
    select string_agg(distinct r, '; ') into v_refusal from (
      select case
               when q.committed_at is not null then 'one is committed and cannot be re-priced'
               when coalesce(q.status,'') = 'accepted' then 'one has already been accepted'
               when exists (select 1 from public.transactions t where t.inquiry_id = q.inquiry_id
                             and t.supplier_id = q.supplier_id and t.revealed_at is not null)
                 then 'the customer has already paid to reveal you on one, so the price they paid to see stands'
               else 'the request is closed on one' end as r
        from public.quotes q where q.supplier_id = v_lead
         and (p_quote_id is null or q.id = p_quote_id)) z;
    v_refusal := coalesce('I cannot change a price right now: ' || v_refusal || '.',
                          'You have no open quotation for me to re-price. You can send a new one from the portal.');
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal);
  end if;

  if v_n > 1 then
    select string_agg(i.category || ' in ' || coalesce(i.emirate,'the UAE') || ' (currently AED ' || q.quote_amount || ')', '; ' order by q.created_at desc)
      into v_list
      from public.quotes q join public.inquiries i on i.id = q.inquiry_id
     where q.supplier_id = v_lead and q.committed_at is null
       and coalesce(q.status,'') not in ('accepted','withdrawn','expired');
    v_refusal := 'You have ' || v_n || ' open quotations, so I will not guess which one you mean: ' || v_list
              || '. Tell me which, or change it in the portal.';
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal, 'open_quotes', v_n);
  end if;

  select q.* into v_q
    from public.quotes q join public.inquiries i on i.id = q.inquiry_id
   where q.supplier_id = v_lead
     and (p_quote_id is null or q.id = p_quote_id)
     and q.committed_at is null
     and coalesce(q.status,'') not in ('accepted','withdrawn','expired')
     and coalesce(i.status,'') not in ('concluded','closed','cancelled','awarded')
     and not exists (select 1 from public.transactions t
                      where t.inquiry_id = q.inquiry_id and t.supplier_id = q.supplier_id
                        and t.revealed_at is not null);
  v_old := v_q.quote_amount;

  -- THE FAT-FINGER BOUND. A supplier may price their own work at whatever they like — that is
  -- their commercial decision and not ours. But this arrives as a sentence typed on a phone, where
  -- a missing or extra zero is one keystroke, and a quotation is a number a customer will compare
  -- against others and pay to unlock. Beyond half up or half down, the portal asks for it twice.
  if v_old is not null and v_old > 0 and (v_num > v_old * 1.5 or v_num < v_old * 0.5) then
    v_refusal := 'That would move the price from AED ' || v_old || ' to AED ' || v_num
              || ', which is more than half up or down. I have not changed it — if you do mean that, please set it in the portal so you can see the whole quotation while you do.';
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, target_id, old_value, new_value, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, v_q.id::text, v_old::text, v_num::text, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal, 'old', v_old, 'asked', v_num);
  end if;

  if v_old is not distinct from v_num then
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, target_id, old_value, new_value, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, v_q.id::text, v_old::text, v_num::text, false, 'already at that value');
    return jsonb_build_object('ok', true, 'unchanged', true, 'old', v_old, 'new', v_num,
      'message', 'Your quotation is already AED ' || v_num || '. Nothing to change.');
  end if;

  update public.quotes set quote_amount = v_num where id = v_q.id;

  insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, target_id, old_value, new_value, applied)
  values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, v_q.id::text, v_old::text, v_num::text, true);

  insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('supplier_directive', 'ok',
          jsonb_build_object('lead_id', v_lead, 'quote_id', v_q.id, 'old', v_old, 'new', v_num, 'channel', p_channel),
          coalesce(v_company,'lead ' || v_lead) || ' changed a quotation from AED ' || coalesce(v_old::text,'(unset)')
          || ' to AED ' || v_num || ' by ' || p_channel || '. Instruction: ' || left(coalesce(p_inbound,''),200),
          now(), now());

  return jsonb_build_object('ok', true, 'quote_id', v_q.id, 'old', v_old, 'new', v_num,
    'message', 'Done — your quotation is now AED ' || v_num || ' (it was AED ' || coalesce(v_old::text,'unset') || '). The customer sees the new price from now on.');
end $function$;

-- Both are NEW SECURITY DEFINER functions, so EXECUTE was granted to PUBLIC on creation. Revoked
-- here, and this file goes out with --promote --ddl so the REVOKE reaches production too.
revoke all on function public.fn_supplier_changeable() from public, anon, authenticated;
revoke all on function public.fn_supplier_apply_change(text, text, text, text, uuid, text) from public, anon, authenticated;
grant execute on function public.fn_supplier_changeable() to service_role;
grant execute on function public.fn_supplier_apply_change(text, text, text, text, uuid, text) to service_role;
