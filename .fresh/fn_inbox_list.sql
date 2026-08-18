CREATE OR REPLACE FUNCTION public.fn_inbox_list()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
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
$function$
