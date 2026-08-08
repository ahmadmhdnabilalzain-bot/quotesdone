-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708125005   name: inbound_email_triage
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.inbound_messages
  add column if not exists ai_category text,
  add column if not exists ai_draft_reply text,
  add column if not exists ai_summary text,
  add column if not exists triaged_at timestamptz,
  add column if not exists replied_at timestamptz,
  add column if not exists replied_by text;

-- Inbox for the founder: triaged inbound emails awaiting a reply.
create or replace function public.fn_inbox_list()
returns jsonb language sql security definer set search_path=public,pg_catalog as $$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'needs_review', (select count(*) from public.inbound_messages where needs_review=true and replied_at is null),
      'untriaged', (select count(*) from public.inbound_messages where needs_review=true and triaged_at is null and replied_at is null),
      'replied_7d', (select count(*) from public.inbound_messages where replied_at > now()-interval '7 days')),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'id',id,'from_email',from_email,'subject',subject,'body',left(coalesce(body,''),1200),
        'category',ai_category,'summary',ai_summary,'draft',ai_draft_reply,
        'triaged_at',triaged_at,'created_at',created_at) order by created_at desc)
      from (select * from public.inbound_messages
             where needs_review=true and replied_at is null order by created_at desc limit 50) m),'[]'::jsonb)
  );
$$;
revoke execute on function public.fn_inbox_list() from anon, authenticated, public;

-- Send a reply to an inbound email (founder-approved action). Uses the notifications pipeline (email_cron sends it).
create or replace function public.fn_inbox_send(p_id bigint, p_body text, p_by text default null)
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare m public.inbound_messages%rowtype;
begin
  select * into m from public.inbound_messages where id=p_id;
  if m.id is null then return jsonb_build_object('error','message not found'); end if;
  if m.from_email is null then return jsonb_build_object('error','no sender address'); end if;
  if coalesce(trim(p_body),'')='' then return jsonb_build_object('error','empty reply'); end if;

  insert into public.notifications(type,to_email,to_role,channel,subject,body)
    values('inbound_reply', m.from_email, null, 'email',
           case when coalesce(m.subject,'') ilike 're:%' then m.subject else 'Re: '||coalesce(m.subject,'your message') end,
           p_body);

  update public.inbound_messages set replied_at=now(), replied_by=coalesce(p_by,'founder'), needs_review=false where id=p_id;
  update public.agent_actions set status='approved', decided_by=coalesce(p_by,'founder'), decided_at=now()
   where target_table='inbound_messages' and target_id=p_id::text
     and status in ('pending','held_for_review','proposed','open');
  return jsonb_build_object('ok',true, 'to', m.from_email);
end $$;
revoke execute on function public.fn_inbox_send(bigint,text,text) from anon, authenticated, public;
