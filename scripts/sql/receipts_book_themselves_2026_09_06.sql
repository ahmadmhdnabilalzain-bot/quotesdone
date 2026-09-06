-- ---------------------------------------------------------------------------------------------
-- RECEIPTS BOOK THEMSELVES; A RECEIPT NOBODY COULD PARSE GOES TO THE BOOKKEEPER, NOT THE FOUNDER.
--
-- Measured 6 Sep 2026: the founder opened the OS and saw "Inbox — awaiting your reply" and
-- "Reviews pending" filled with HIS OWN forwarded SaaS receipts (Resend, Supabase, Vercel, Apify —
-- inbound_messages 67/73/74/75, doc_reviews 8-12). resend_inbound booked a receipt only after an
-- ai_gateway extraction call; under the paid hold (15 Aug) that call returns nothing, so every
-- receipt fell through to the supplier-document path: PDF stored, doc_reviews 'pending',
-- inbound_messages needs_review=true — and both surfaces read straight from those flags.
-- expense_entries since 15 Aug: 0.
--
-- Three things here, all data-shaped and small:
--   1. owner_role on inbound_messages and doc_reviews. A held row that a department owns is that
--      department's work, and the founder's surfaces (fn_inbox_list, fn_ws_documents) show only
--      rows nobody owns — today that set is empty for him. Nothing routes to him except a refund.
--   2. fn_receipt_hand_to_bookkeeper(inbound_id, review_ids, reason): opens ONE org_task in the
--      finance lane for `bookkeeper` (the same lane fn_agent_action_hand_to_owner uses) and stamps
--      owner_role on the rows it carries. Idempotent on the [inbound_message:<id>] marker.
--   3. fn_inbox_list / fn_ws_documents exclude owned rows; the Documents "Reviews pending" list
--      now lists PENDING rows (it listed the last 20 of any status under Approve/Reject buttons).
-- The deterministic parser itself lives in supabase/functions/_shared/receipt_parse.ts; the
-- backfill of the four receipts is scripts/backfill_unbooked_receipts.ts (same parser).
-- ---------------------------------------------------------------------------------------------

alter table public.inbound_messages add column if not exists owner_role text;
alter table public.doc_reviews      add column if not exists owner_role text;
comment on column public.inbound_messages.owner_role is 'org_agents.agent_key that owns this held row (6 Sep 2026). A row with an owner is that department''s work and never the founder''s inbox.';
comment on column public.doc_reviews.owner_role      is 'org_agents.agent_key that owns this review (6 Sep 2026). Owned rows are not "Reviews pending" for the founder.';

create or replace function public.fn_receipt_hand_to_bookkeeper(p_inbound_id bigint, p_review_ids bigint[], p_reason text)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare m record; v_owner text := 'bookkeeper'; v_task bigint;
begin
  select * into m from public.inbound_messages where id = p_inbound_id;
  if not found then return null; end if;

  -- one task per inbound email, however many times the email is redelivered
  select t.id into v_task from public.org_tasks t
   where t.detail like '[inbound_message:' || p_inbound_id || ']%'
     and t.status not in ('done', 'cancelled')
   order by t.id limit 1;

  if v_task is null then
    if not exists (select 1 from public.org_agents o where o.agent_key = v_owner and o.active and coalesce(o.available, true)) then
      v_owner := null;   -- a05_org_task_fill_ownership picks the least-loaded finance colleague
    end if;
    insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, decided_by,
                                  action_class, assigned_agent, priority, result)
    values ('finance',
            left('Book a forwarded receipt the parser could not read: ' || coalesce(m.subject, '(no subject)'), 200),
            '[inbound_message:' || p_inbound_id || '] ' || coalesce(p_reason, 'no amount could be read from the text')
              || E'\n\nFrom ' || coalesce(m.from_email, '?') || ' to ' || coalesce(m.to_email, '?') || ' at ' || m.created_at
              || '. Stored documents: doc_reviews ' || coalesce(array_to_string(p_review_ids, ', '), '(none)')
              || '. Read the document, book the expense in expense_entries (source ''receipt''), close the doc_reviews rows '
              || 'as auto_applied and the inbound row as replied. Only a Stripe refund reaches the founder.',
            'assigned', 'advisory', false, 'fn_receipt_hand_to_bookkeeper',
            'analysis', v_owner, 1,
            jsonb_build_object('source', jsonb_build_object('inbound_message_id', p_inbound_id,
                               'doc_review_ids', to_jsonb(coalesce(p_review_ids, '{}'::bigint[])),
                               'reason', p_reason, 'handed_at', now())))
    returning id into v_task;
  end if;

  update public.inbound_messages set owner_role = 'bookkeeper' where id = p_inbound_id and owner_role is null;
  update public.doc_reviews set owner_role = 'bookkeeper'
   where id = any(coalesce(p_review_ids, '{}'::bigint[])) and owner_role is null;
  return v_task;
end
$function$;

revoke all on function public.fn_receipt_hand_to_bookkeeper(bigint, bigint[], text) from public, anon, authenticated;
grant execute on function public.fn_receipt_hand_to_bookkeeper(bigint, bigint[], text) to service_role;

CREATE OR REPLACE FUNCTION public.fn_inbox_list()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  -- owner_role is null: a row a department owns is that department's work, never the founder's inbox (6 Sep 2026)
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'needs_review', (select count(*) from public.inbound_messages where needs_review=true and replied_at is null and owner_role is null
                        and created_at >= public.fn_os_fresh_start_at()),
      'untriaged', (select count(*) from public.inbound_messages where needs_review=true and triaged_at is null and replied_at is null and owner_role is null
                     and created_at >= public.fn_os_fresh_start_at()),
      'replied_7d', (select count(*) from public.inbound_messages where replied_at > now()-interval '7 days')),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'id',id,'from_email',from_email,'subject',subject,'body',left(coalesce(body,''),1200),
        'category',ai_category,'summary',ai_summary,'draft',ai_draft_reply,
        'triaged_at',triaged_at,'created_at',created_at) order by created_at desc)
      from (select * from public.inbound_messages
             where needs_review=true and replied_at is null and owner_role is null
               and created_at >= public.fn_os_fresh_start_at()
             order by created_at desc limit 50) m),'[]'::jsonb)
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_ws_documents()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'documents',(select count(*) from documents),
      'inventory_total',(select count(*) from document_inventory),
      'dropbox_files',(select count(*) from dropbox_files where not is_folder),
      'indexed',(select count(*) from documents where indexed is true),
      -- a review a department owns is not pending for the founder (6 Sep 2026)
      'reviews_pending',(select count(*) from doc_reviews where coalesce(status,'')='pending' and owner_role is null),
      'versions',(select count(*) from doc_versions)
    ),
    'controller', jsonb_build_object(
      'health', (select (kpis->>'doc_health')::numeric from document_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from document_kpis k),
      'by_bucket', coalesce((select jsonb_agg(jsonb_build_object('bucket',bucket,'docs',c,'bytes',b,'past_retention',pr,'class',cls) order by c desc)
          from (select bucket, count(*) c, sum(bytes) b, count(*) filter (where past_retention) pr, max(retention_class) cls from document_inventory group by bucket) t),'[]'::jsonb),
      'dropbox', jsonb_build_object(
        'connected', (select (max(synced_at) is not null) from dropbox_files),
        'files', (select count(*) from dropbox_files where not is_folder),
        'folders', (select count(*) from dropbox_files where is_folder),
        'bytes', (select coalesce(sum(size),0) from dropbox_files),
        'last_sync', (select max(synced_at) from dropbox_files),
        'top_folders', coalesce((select jsonb_agg(jsonb_build_object('path',path,'items',n) order by n desc)
            from (select split_part(path,'/',2) path, count(*) n from dropbox_files where path like '/%/%' group by 1 order by 2 desc limit 8) t),'[]'::jsonb)
      ),
      'retention', coalesce((select jsonb_agg(jsonb_build_object('bucket',bucket,'class',class,'retention_days',retention_days) order by bucket) from retention_policy),'[]'::jsonb),
      'tasks', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation)) from agent_actions where agent='document_controller' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    'documents', coalesce((select jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'kind',kind,'ref_table',ref_table,'ref_id',ref_id,'status',status,'indexed',indexed,'created_at',created_at)) from (select * from documents order by created_at desc limit 40) d),'[]'::jsonb),
    -- the section is titled "Reviews pending" and carries Approve/Reject: it lists pending, unowned rows only
    'reviews', coalesce((select jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'ai_category',ai_category,'ai_summary',ai_summary,'ai_confidence',ai_confidence,'status',status,'created_at',created_at)) from (select * from doc_reviews where coalesce(status,'')='pending' and owner_role is null order by created_at desc limit 20) r),'[]'::jsonb),
    'kinds', coalesce((select jsonb_agg(jsonb_build_object('key',k,'count',c) order by c desc) from (select coalesce(nullif(kind,''),'other') k, count(*) c from documents group by 1) kk),'[]'::jsonb)
  );
$function$;
