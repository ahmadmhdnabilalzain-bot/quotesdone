-- THE EMBED DISPATCHER NEVER QUEUES MORE THAN IT CAN HAVE IN FLIGHT (22 Sep 2026, it_engineer, CONN-08).
--
-- WHAT WAS THERE. fn_kb_embed_dispatch claims up to p_limit (default 200, ceiling 1000) unembedded
-- chunks and places ONE net.http_post per chunk at ai_gateway, all inside one statement. Nothing looked
-- at how many requests were already in flight. pg_net's background worker drains its own queue at its
-- own pace, and ai_gateway is an edge function with a CPU budget per invocation — the estate has
-- already been bitten by that: an edge function's CPU cap is not bounded by its deadline, and #686's
-- escaping hit 546 CPU-exceeded kills, which skip every finding path and leave the job hung silently.
--
-- WHAT THIS ADDS. One count before the claim: requests already queued in the last three minutes (the
-- same three minutes as the claim lease, so the two windows agree). The dispatch takes only the
-- difference, and when the cap is already met it queues nothing and says so instead of piling on.
--
-- WHY 150. The existing comment in this routine records the other, independent bound: the caller runs
-- under statement_timeout = 8 s and can place about 23 rows inside it, so 150 is not a throttle on the
-- normal path at all — it is the ceiling that stops a caller WITHOUT that timeout (a manual run, a
-- future scheduler) from queueing a thousand posts at a gateway that answers them one at a time.
-- Everything else in the routine is unchanged.

create or replace function public.fn_kb_embed_dispatch(p_limit integer default 200, p_max_tier integer default 4)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_lim     int := greatest(1, least(coalesce(p_limit, 200), 1000));
  v_url     text;
  v_secret  text;
  v_queued  int := 0;
  v_cap     constant int := 150;   -- see the header: the in-flight ceiling, not the normal bound
  v_inflight int;
begin
  select 'https://' || value || '.supabase.co/functions/v1/ai_gateway' into v_url
    from public.app_secrets where key = 'project_ref';
  select value into v_secret from public.app_secrets where key = 'cred_fn_ai';
  if v_url is null or coalesce(v_secret, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_project_ref_or_cred_fn_ai');
  end if;

  -- CONCURRENCY CAP. Three minutes, matching the claim lease below, so "in flight" means the same
  -- thing in both places.
  select count(*) into v_inflight from public.kb_embed_inflight i
   where i.queued_at > now() - interval '3 minutes';
  v_lim := least(v_lim, greatest(0, v_cap - v_inflight));
  if v_lim = 0 then
    return jsonb_build_object('ok', true, 'queued', 0, 'inflight', v_inflight, 'cap', v_cap,
      'held', 'the gateway already has the in-flight ceiling of embed requests; nothing was claimed', 'at', now());
  end if;

  -- The claim. Same lease discipline as fn_kb_embed_claim -- FOR UPDATE SKIP LOCKED, a three-minute
  -- expiry stamped into embed_claimed_at -- so concurrent dispatches take disjoint slices and a
  -- dispatch that dies costs three minutes rather than its rows.
  with pick as (
    select k.id, k.title, k.content
      from public.kb_chunks k
      left join public.kb_embed_priority p on p.category = k.category
     where k.embedding_gte is null
       and (k.embed_claimed_at is null or k.embed_claimed_at < now() - interval '3 minutes')
       and coalesce(p.tier, 3) <= greatest(1, least(coalesce(p_max_tier, 4), 4))
     order by coalesce(p.tier, 3) asc, k.created_at asc
     limit v_lim
     for update of k skip locked
  ), claimed as (
    update public.kb_chunks k set embed_claimed_at = now()
      from pick where k.id = pick.id
    returning k.id, pick.title, pick.content
  ), sent as (
    select c.id,
           net.http_post(
             url := v_url,
             headers := '{"Content-Type":"application/json"}'::jsonb,
             body := jsonb_build_object(
                       '__secret', v_secret,
                       'fn', 'kb_embed_dispatch',
                       'action', 'embed',
                       -- 1,200 characters is the window kb_embed used and the window every existing
                       -- kb_chunks vector was built from. Changing it would make new rows
                       -- incomparable with the 166,093 already embedded.
                       'text', left(coalesce(c.title, '') || E'\n' || coalesce(c.content, ''), 1200)),
             timeout_milliseconds := 25000) as request_id
      from claimed c
  )
  insert into public.kb_embed_inflight (request_id, chunk_id)
  select s.request_id, s.id from sent s
  on conflict (request_id) do nothing;

  get diagnostics v_queued = row_count;
  return jsonb_build_object('ok', true, 'queued', v_queued, 'inflight_before', v_inflight, 'cap', v_cap,
                            'max_tier', p_max_tier, 'at', now());
end
$function$;

revoke execute on function public.fn_kb_embed_dispatch(integer, integer) from public, anon, authenticated;
