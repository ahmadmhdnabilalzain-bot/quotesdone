-- AN ARTICLE CHANGE THE FOUNDER ASKS FOR IS REDRAWN AND OFFERED AGAIN.
-- Seat: marketing. 29 Sep 2026. Follows the_marketing_seat_puts_its_plan_geo_articles_launch_and_competitor_work_on_a_clock.sql (#1039).
--
-- WHAT WAS WRONG (review of #1039): his change to an article was written to marketing_article.founder_change_request
-- and nothing read it. The draft was excluded from every later offer, while the reply told him the change had been
-- "passed to the marketing seat". The change went nowhere.
--
-- WHAT THIS DOES
--   1. approval_hash: the fingerprint of the article's content (every field in both languages) at the moment it was
--      sent to him. founder_changes: every change he asked for, in order.
--   2. fn_marketing_article_revise_due(): the draft carrying his change and NOT yet redrawn (its content still has the
--      fingerprint he was sent). supabase/functions/marketing/duties.ts 'article_revise' redraws it with the model
--      (task class marketing_article_revise), runs the same gate as any article (checkArticle: the style lint in both
--      languages, the same structure in English and Arabic, and no number that is not already in the grounded draft or
--      in his own words) and writes it back through fn_marketing_article_ingest. Under the founder's model hold nothing
--      is called and the draft waits.
--   3. fn_marketing_article_release_duty(): a redrawn draft (fingerprint differs from approval_hash) is sent to him
--      again at once on a working day, with his change quoted, a new token, and the change moved into founder_changes.
--      It is sent ONCE per redraw: the new approval_hash is the redrawn content, so the next day is quiet.
--   4. The reply now says what happens: the seat redraws the article with his change and sends it back.
--
-- Prevented by: scripts/checks/marketing_duties_are_on_a_clock.test.mjs (an article change is read by the redraw and
-- the re-offer), and the probe in scripts/sql/pending/ for this file.

alter table public.marketing_article add column if not exists approval_hash text;
alter table public.marketing_article add column if not exists founder_changes jsonb not null default '[]'::jsonb;

create or replace function public.fn_marketing_article_fingerprint(p_id bigint)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select md5(concat_ws(E'\x1f', title_en, excerpt_en, meta_desc_en, category_en, body_html_en,
                                 title_ar, excerpt_ar, meta_desc_ar, category_ar, body_html_ar))
    from public.marketing_article where id = p_id
$fn$;
revoke execute on function public.fn_marketing_article_fingerprint(bigint) from public, anon, authenticated;

-- An article sent before this file has no approval_hash; its content is what he was sent.
update public.marketing_article set approval_hash = public.fn_marketing_article_fingerprint(id)
 where approval_sent_at is not null and approval_hash is null;

-- The one draft waiting for its redraw (oldest change first). The edge duty reads it and writes the redraw back.
create or replace function public.fn_marketing_article_revise_due()
returns table (id bigint, slug text, kind text, change text, earlier_changes jsonb, sources jsonb, article jsonb)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select a.id, a.slug, a.kind, a.founder_change_request, a.founder_changes, a.sources,
         jsonb_build_object(
           'en', jsonb_build_object('title', a.title_en, 'excerpt', a.excerpt_en, 'meta_desc', a.meta_desc_en, 'category', a.category_en, 'body_html', a.body_html_en),
           'ar', jsonb_build_object('title', a.title_ar, 'excerpt', a.excerpt_ar, 'meta_desc', a.meta_desc_ar, 'category', a.category_ar, 'body_html', a.body_html_ar))
    from public.marketing_article a
   where a.status = 'draft' and not a.is_demo and a.founder_change_request is not null
     and public.fn_marketing_article_fingerprint(a.id) is not distinct from a.approval_hash
   order by a.updated_at, a.id limit 1
$fn$;
revoke execute on function public.fn_marketing_article_revise_due() from public, anon, authenticated;

create or replace function public.fn_marketing_article_release_duty()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_now timestamp := now() at time zone 'Asia/Dubai';
  a public.marketing_article; v_token text; v_nid bigint; v_stuck text; v_sent text; v_resent text; v_change text;
begin
  select slug into v_stuck from public.marketing_article
   where status = 'approved' and approved_by = 'founder' and not is_demo and approved_at < now() - interval '8 days' limit 1;
  if v_stuck is not null and public.fn_marketing_publishing_live() then
    raise exception 'article % was approved by the founder more than 8 days ago and is not released', v_stuck;
  end if;
  if public.fn_is_working_day(v_now::date) then
    -- 1. a draft redrawn with his change goes back to him at once, once per redraw
    select * into a from public.marketing_article m
     where m.status = 'draft' and not m.is_demo and m.founder_change_request is not null and m.approval_hash is not null
       and public.fn_marketing_article_fingerprint(m.id) is distinct from m.approval_hash
     order by m.updated_at, m.id limit 1 for update skip locked;
    if found then
      v_change := a.founder_change_request;
      v_token := encode(extensions.gen_random_bytes(16), 'hex');
      v_nid := public.fn_marketing_mail_founder('marketing_article_approval',
        'Redrawn with your change: ' || left(a.title_en, 110) || ' [approve ' || v_token || ']',
        'The article is redrawn with the change you asked for:' || E'\n' || '"' || left(v_change, 1000) || '"' || E'\n\n'
        || a.title_en || E'\n' || a.excerpt_en || E'\n\n' || a.title_ar || E'\n' || a.excerpt_ar || E'\n\n'
        || 'It publishes on quotesdone.ae/blog/' || a.slug || '. Reply "approve" and it is released on the next UAE working day '
        || '(never a weekend or a public holiday) with its LinkedIn post. Any other reply is another change, and nothing is published.',
        null, 'approve+' || v_token || '@mail.quotesdone.com');
      update public.marketing_article
         set approval_token = v_token, approval_sent_at = now(), approval_hash = public.fn_marketing_article_fingerprint(a.id),
             founder_changes = founder_changes || to_jsonb(v_change), founder_change_request = null, updated_at = now()
       where id = a.id;
      v_resent := a.slug;
    -- 2. otherwise the week's new draft, once a Dubai week
    -- (a draft sent this week and waiting for its redraw still counts: his change does not open a second new offer)
    elsif not exists (select 1 from public.marketing_article where status = 'draft' and approval_sent_at is not null and not is_demo
                        and approval_sent_at at time zone 'Asia/Dubai' >= date_trunc('week', v_now)) then
      select * into a from public.marketing_article
       where status = 'draft' and not is_demo and approval_sent_at is null and founder_change_request is null
       order by created_at, id limit 1 for update skip locked;
      if found then
        v_token := encode(extensions.gen_random_bytes(16), 'hex');
        v_nid := public.fn_marketing_mail_founder('marketing_article_approval',
          'Article for this week: ' || left(a.title_en, 120) || ' [approve ' || v_token || ']',
          'This week''s article, ready to publish on quotesdone.ae/blog/' || a.slug || E' in English and Arabic:\n\n'
          || a.title_en || E'\n' || a.excerpt_en || E'\n\n' || a.title_ar || E'\n' || a.excerpt_ar || E'\n\n'
          || 'Reply "approve" and it is released on the next UAE working day (never a weekend or a public holiday) with its LinkedIn post. '
          || 'Any other reply is a change: the marketing seat redraws the article with it and sends it back to you.',
          null, 'approve+' || v_token || '@mail.quotesdone.com');
        update public.marketing_article set approval_token = v_token, approval_sent_at = now(),
               approval_hash = public.fn_marketing_article_fingerprint(a.id), updated_at = now() where id = a.id;
        v_sent := a.slug;
      end if;
    end if;
  end if;
  return jsonb_build_object('requested', v_sent, 'resent_after_change', v_resent,
    'drafts', (select count(*) from public.marketing_article where status = 'draft' and not is_demo),
    'awaiting_founder', (select count(*) from public.marketing_article where status = 'draft' and approval_token is not null and not is_demo),
    'awaiting_redraw', (select count(*) from public.fn_marketing_article_revise_due()),
    'approved', (select count(*) from public.marketing_article where status = 'approved' and not is_demo),
    'live', (select count(*) from public.marketing_article where status = 'live' and not is_demo));
end $fn$;
revoke execute on function public.fn_marketing_article_release_duty() from public, anon, authenticated;

-- His reply. Unchanged from #1039 except that an article change now says what really happens to it.
create or replace function public.fn_marketing_approval_reply(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_token text := lower(coalesce(p->>'token', '')); v_from text := lower(btrim(coalesce(p->>'from_email', '')));
  a public.marketing_article; d public.marketing_plan_doc; v_out text; v_what text; v_msg text;
begin
  if v_from is distinct from public.fn_marketing_founder_email() then return jsonb_build_object('outcome', 'not_the_founder'); end if;
  select * into a from public.marketing_article where approval_token = v_token and v_token <> '' for update;
  if a.id is null then select * into d from public.marketing_plan_doc where approval_token = v_token and v_token <> '' for update; end if;
  v_what := coalesce('article "' || a.title_en || '"', case when d.id is not null then 'launch plan for ' || to_char(d.period, 'FMMonth YYYY') end);
  if v_what is null then
    v_out := 'unknown'; v_msg := 'Your reply did not match an approval email, so nothing was changed. Please reply to the latest one.';
  elsif not coalesce((p->>'authenticated')::boolean, false) then
    v_out := 'not_authenticated';
    v_msg := 'A reply about the ' || v_what || ' arrived with your address but could not be verified as coming from your mailbox, so nothing was changed.';
  elsif (a.id is not null and a.status <> 'draft') or (d.id is not null and d.status <> 'sent_to_founder') then
    v_out := 'already_decided'; v_msg := 'The ' || v_what || ' was already decided; nothing was changed.';
  elsif p->>'intent' = 'approve' then
    if a.id is not null then perform public.fn_marketing_article_approve(a.slug, 'founder');
    else update public.marketing_plan_doc set status = 'approved', decided_at = now(), updated_at = now() where id = d.id; end if;
    v_out := 'approved';
    v_msg := 'Approved: the ' || v_what || '. ' || case when a.id is not null
      then 'It is released on the next UAE working day on the weekly cadence.' else 'The marketing seat runs it from 1 January 2027.' end;
  elsif btrim(coalesce(p->>'text', '')) = '' then
    -- an empty reply is not a change: nothing is filed, the token stays valid, and the item is still his to approve
    v_out := 'empty_reply';
    v_msg := 'Your reply about the ' || v_what || ' was empty, so nothing was changed and it is still waiting for you. '
          || 'Reply "approve" to the same email, or write the change you want.';
  else
    if a.id is not null then
      update public.marketing_article set founder_change_request = left(btrim(p->>'text'), 4000), approval_token = null, updated_at = now() where id = a.id;
      v_msg := 'Your change to the ' || v_what || ' is with the marketing seat: it redraws the article with it and sends it back to you '
            || 'for approval. Nothing is published until you approve the new version.';
    else
      -- his change joins the plan (founder_changes) and the next daily redraw is re-sent to him with it
      update public.marketing_plan_doc set status = 'change_requested', founder_note = left(btrim(p->>'text'), 4000),
             founder_changes = founder_changes || to_jsonb(left(btrim(p->>'text'), 4000)),
             approval_token = null, decided_at = now(), updated_at = now() where id = d.id;
      v_msg := 'Your change to the ' || v_what || ' is written into the plan, which is sent back to you with it. '
            || 'Nothing is run until you approve the new version.';
    end if;
    v_out := 'change_requested';
  end if;
  perform public.fn_marketing_mail_founder('marketing_approval_reply',
    case when v_out = 'approved' then 'Approved: ' when v_out = 'change_requested' then 'Change noted: ' else 'Not changed: ' end || coalesce(v_what, 'approval'), v_msg);
  return jsonb_build_object('outcome', v_out, 'article', a.slug, 'plan_doc', d.id);
end $fn$;
revoke execute on function public.fn_marketing_approval_reply(jsonb) from public, anon, authenticated;

-- The redraw is a judgement in his words, in both languages: the judgement/Arabic row, as marketing_plan is. The whole
-- article comes back (two languages, ~4k characters each), so the class allows 8000 tokens; the gateway's per-class
-- max_tokens is the ceiling, and a truncated answer is refused by the duty rather than written.
insert into public.model_policy (task_class, tier, model_primary, model_fallback, max_tokens, rationale, deterministic_alternative, active, cache_ttl_min) values
 ('marketing_article_revise', 'large', 'openai/gpt-5.6-sol', 'anthropic/claude-opus-5.5', 8000,
  'Redraw a draft article (English and Arabic) with the change the founder asked for, keeping its structure and adding no fact that is not already in it or in his words. A JUDGEMENT on his free text in two languages -> the judgement/Arabic row. Rare: only when he asks for a change.',
  'The gate after it is code: checkArticle (style lint both languages, same structure EN/AR, no ungrounded number) and fn_marketing_article_ingest', true, 0)
on conflict (task_class) do update set tier = excluded.tier, model_primary = excluded.model_primary, model_fallback = excluded.model_fallback,
  max_tokens = excluded.max_tokens, rationale = excluded.rationale, deterministic_alternative = excluded.deterministic_alternative,
  active = excluded.active, cache_ttl_min = excluded.cache_ttl_min;

select case
  when to_regprocedure('public.fn_marketing_article_revise_due()') is null then 'PROBE FAILED: fn_marketing_article_revise_due is missing'
  when not exists (select 1 from public.model_policy where task_class = 'marketing_article_revise' and active) then 'PROBE FAILED: no marketing_article_revise class'
  when exists (select 1 from public.marketing_article where approval_sent_at is not null and approval_hash is null) then 'PROBE FAILED: a sent article has no fingerprint'
  else 'PROBE OK' end as verdict;
