-- EVERY FOUNDER MAIL FROM THE MARKETING SEAT NAMES ITS KIND (22 Sep 2026; seat: marketing).
--
-- WHAT WAS MEASURED (22 Sep 2026, read-only, production htdblwldjkcgjvmqkbeh):
--   * scripts/checks/the_founder_is_emailed_exceptions_only.test.mjs is red on "every fn_notify_founder call
--     names p_kind". Two live routines call fn_notify_founder once each and name p_kind zero times:
--       fn_marketing_social_hand_to_human(bigint,text)          every_social_message_is_answered.sql (#835)
--       fn_marketing_outreach_deliver(date,bigint[],text,text)  the_marketing_seat_writes_articles_and_
--                                                               drafts_linkedin_outreach.sql (#837)
--   * Both pass their kind POSITIONALLY (the 4th argument of fn_notify_founder(p_event, p_detail, p_level,
--     p_kind, p_dedupe_key, p_owner_agent)), so the right kind already arrives at run time. The rule the check
--     enforces is that a caller SAYS which argument is its kind, so a reordered or shortened call cannot pass
--     a dedupe key or a level as the kind without anyone seeing it.
--   * Both kinds are registered: founder_mail_policy social_human_request (allowed, owner marketing) and
--     marketing_outreach_list (allowed, owner marketing).
--   * The live bodies (pg_get_functiondef) equal the bodies in those two files, each routine's last definer
--     in MANIFEST.txt. Both are SECURITY DEFINER with search_path public, pg_temp; EXECUTE is held by
--     postgres and service_role only.
--
-- WHAT IS WRONG: the two calls are positional, so the check cannot see the kind and stays red.
--
-- WHAT THIS CHANGES: each routine is redefined from its current definer with every argument of its
--   fn_notify_founder call NAMED (p_event, p_detail, p_level, p_kind, p_dedupe_key, p_owner_agent).
--   Same values, same order, same kinds.
--
-- WHAT IS NOT CHANGED: no other line of either body; no kind, level, dedupe key or owner. Security definer,
--   search_path and the revokes are restated exactly (CREATE OR REPLACE keeps the ACL; the revoke is
--   restated anyway). No table, trigger or policy row is touched. Nothing is sent.
--
-- PREVENTED BY: the_founder_is_emailed_exceptions_only.test.mjs, twice: on production (calls = named kinds
--   per routine) and in the repository, where it reads each routine's LAST definition in scripts/sql
--   (MANIFEST order, then the files not yet applied) and fails the pull request BEFORE the apply.
--
--   node scripts/apply_sql.mjs scripts/sql/every_founder_mail_from_the_marketing_seat_names_its_kind.sql --apply --ddl
--
-- Rolled-back proof before the PR: the routines were created inside a transaction, the check's query was run
-- against them there, and the transaction was rolled back (reported in the pull request).
--
--
--

-- ── 1. fn_marketing_social_hand_to_human (from every_social_message_is_answered.sql) ──────────────────
create or replace function public.fn_marketing_social_hand_to_human(p_conversation_id bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  c public.social_conversation%rowtype;
  v_last text;
  v_detail text;
begin
  select * into c from public.social_conversation where id = p_conversation_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no_such_conversation'); end if;
  -- Already with him: a second "agent" in the same conversation does not email him twice.
  if c.status = 'handed_to_human' then return jsonb_build_object('ok', true, 'notified', false, 'reason', 'already_handed'); end if;

  update public.social_conversation
     set status = 'handed_to_human', handed_at = now(), handed_reason = left(coalesce(p_reason, ''), 500),
         handoff_count = handoff_count + 1
   where id = c.id;

  select string_agg(to_char(m.occurred_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || '  '
                    || case m.author when 'person' then coalesce(c.handle, 'them') when 'seat' then 'QuotesDone (auto)' else 'QuotesDone (team)' end
                    || ': ' || left(m.body, 400), E'\n' order by m.occurred_at)
    into v_last
    from (select * from public.social_message where conversation_id = c.id order by occurred_at desc limit 8) m;

  v_detail := 'Someone on ' || initcap(c.platform) || ' asked to speak with a person. The marketing seat has stopped '
    || 'auto-replying in this conversation and it is waiting for you.' || E'\n\n'
    || 'Platform: ' || initcap(c.platform) || E'\n'
    || 'Handle: ' || coalesce(nullif(c.handle, ''), '(not shared by Meta)') || '  (id ' || c.user_id || ')' || E'\n'
    || 'Conversation: #' || c.id || E'\n\n'
    || 'Last messages (Dubai time):' || E'\n' || coalesce(v_last, '(none)') || E'\n\n'
    || 'Continue in the Meta inbox: https://business.facebook.com/latest/inbox/all' || E'\n'
    || 'When you are done, hand it back to the seat: select public.fn_marketing_social_set_status('
    || c.id || ', ''auto'', ''founder'');';

  return jsonb_build_object('ok', true, 'notified', true, 'notify',
    public.fn_notify_founder(
      p_event       => 'Someone on ' || initcap(c.platform) || ' asked to speak with you' || coalesce(' (' || nullif(c.handle, '') || ')', ''),
      p_detail      => v_detail,
      p_level       => 'high',
      p_kind        => 'social_human_request',
      p_dedupe_key  => 'social_human:' || c.id || ':' || (c.handoff_count + 1),
      p_owner_agent => 'marketing'));
end
$fn$;
revoke execute on function public.fn_marketing_social_hand_to_human(bigint, text) from public, anon, authenticated;

-- ── 2. fn_marketing_outreach_deliver (from the_marketing_seat_writes_articles_and_drafts_linkedin_outreach.sql)
create or replace function public.fn_marketing_outreach_deliver(p_day date, p_ids bigint[], p_subject text, p_body text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_listed int; v_res jsonb; v_delivery jsonb;
begin
  select count(*) into v_listed from public.marketing_outreach_message where id = any (p_ids) and status = 'listed' and not is_demo;
  if public.fn_marketing_publishing_live() and v_listed > 0 then
    v_res := public.fn_notify_founder(p_event => p_subject, p_detail => p_body, p_level => 'normal',
                                      p_kind => 'marketing_outreach_list', p_dedupe_key => 'marketing_outreach_list:' || p_day);
    v_delivery := jsonb_build_object('mode', 'emailed', 'at', now(), 'notify', v_res);
  else
    v_delivery := jsonb_build_object('mode', 'dry_run', 'at', now(),
      'why', case when v_listed = 0 then 'nothing listed (held or demo)' else 'marketing_golive is not true' end,
      'subject', p_subject, 'body', left(p_body, 6000));
  end if;
  update public.marketing_outreach_message set delivery = v_delivery, updated_at = now() where id = any (p_ids);
  return v_delivery - 'body';
end $fn$;
revoke execute on function public.fn_marketing_outreach_deliver(date, bigint[], text, text) from public, anon, authenticated;
