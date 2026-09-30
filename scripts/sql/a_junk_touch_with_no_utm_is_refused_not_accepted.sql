-- A JUNK TOUCH WITH NO UTM IS REFUSED, NOT ACCEPTED (30 Sep 2026; seat: marketing).
--
-- Outcome audit 30 Sep 2026: #875's probe read "junk touch accepted" - a touch with no valid utm_source and no
-- opened invitation came back ok:true, recorded:false. Nothing was recorded, which is right, but ok:true told the
-- caller the touch was fine. It is now an explicit refusal, ok:false with reason 'no_utm', and it still records
-- nothing. The only caller (supplier_api recordFirstTouch) logs an rpc error only, so an ok:false answer never
-- blocks a registration. Every other branch is unchanged (body copied from
-- the_recruitment_funnel_counts_what_was_sent_and_names_the_stage_that_lost_them.sql). CREATE OR REPLACE keeps
-- the routine's ACL.
--
-- Prevented by: scripts/sql/each_post_is_measured_and_names_the_suppliers_it_brought_probe.sql (expects
-- ok:false, reason no_utm, and no row).
create or replace function public.fn_marketing_first_touch_record(p_lead_id bigint, p_touch jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_ok constant text := '^[A-Za-z0-9._-]{1,100}$';
  v_src text; v_med text; v_cmp text; v_cnt text; v_path text; v_at timestamptz; v_post bigint; v_id bigint;
begin
  if p_lead_id is null then
    return jsonb_build_object('ok', true, 'recorded', false, 'reason', 'no lead');
  end if;
  if p_touch is null or jsonb_typeof(p_touch) <> 'object' then p_touch := '{}'::jsonb; end if;
  v_src := nullif(btrim(p_touch->>'utm_source'), '');     if v_src !~ v_ok then v_src := null; end if;
  v_med := nullif(btrim(p_touch->>'utm_medium'), '');     if v_med !~ v_ok then v_med := null; end if;
  v_cmp := nullif(btrim(p_touch->>'utm_campaign'), '');   if v_cmp !~ v_ok then v_cmp := null; end if;
  v_cnt := nullif(btrim(p_touch->>'utm_content'), '');    if v_cnt !~ v_ok then v_cnt := null; end if;
  v_path := nullif(btrim(p_touch->>'landing_path'), '');  if v_path !~ '^/\S{0,200}$' then v_path := null; end if;
  -- THE INVITATION IS A TOUCH EVEN WHEN THE BROWSER KEPT NONE (28 Sep 2026): private mode or a link
  -- opened before the ref existed leaves no tagged visit, but claim_lookup stamps invite_clicked_at when the
  -- lead's own claim link is opened. That is evidence of the invitation, not a status column.
  if v_src is null then
    select 'invite', 'email', 'supplier_invite', 'lead-' || l.id, '/portal', l.invite_clicked_at
      into v_src, v_med, v_cmp, v_cnt, v_path, v_at
      from public.leads l where l.id = p_lead_id and l.invite_clicked_at is not null;
    if v_src is null then
      -- refused, not accepted: nothing is recorded, and the caller can tell (outcome audit 30 Sep 2026)
      return jsonb_build_object('ok', false, 'recorded', false, 'reason', 'no_utm',
        'detail', 'no valid utm_source and no opened invitation');
    end if;
    p_touch := jsonb_build_object('first_seen_at', v_at);
  end if;
  begin
    v_at := (p_touch->>'first_seen_at')::timestamptz;
    if v_at < now() - interval '400 days' or v_at > now() + interval '1 hour' then v_at := null; end if;
  exception when others then v_at := null;
  end;
  if v_med = 'social' and v_cnt is not null then
    select id into v_post from public.marketing_post where ingest_key = lower(v_cnt);
  end if;
  insert into public.marketing_first_touch (lead_id, utm_source, utm_medium, utm_campaign, utm_content, landing_path, first_seen_at, post_id)
  values (p_lead_id, lower(v_src), v_med, v_cmp, v_cnt, v_path, v_at, v_post)
  on conflict (lead_id) do nothing
  returning id into v_id;
  return jsonb_build_object('ok', true, 'recorded', v_id is not null, 'post_id', v_post);
end
$fn$;
