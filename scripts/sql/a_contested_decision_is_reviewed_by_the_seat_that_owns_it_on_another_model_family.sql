-- A CONTESTED AUTOMATED DECISION GOES TO THE SEAT THAT OWNS THE DECISION,
-- AND A DIFFERENT MODEL FAMILY DECIDES IT (founder ledger 1152, 19 Oct 2026). Seat: ceo.
--
-- The spec (ledger 1152, as worded under ruling 1264): "a request to review an automated decision goes to the owning seat
-- (sales_engineer: matching, specs, quotes, reports; accountant: fees, refunds, charges; customer_support:
-- messaging, account; it_engineer: security, access), reviewed by a different seat or model family than the
-- one that made the original decision. Disputes and approvals go to the CEO. Nothing goes to the founder."
--
-- MEASURED BEFORE THIS FILE (production, 19 Oct 2026):
--   * no table or routine recorded a request to review an automated decision. The nearest owners were
--     public.seat_handoff_kind / fn_seat_handoff (the seat conversation registry, 100+ kinds) and
--     model_policy_by_identity (each seat's primary / fallback / escalation model). Both are REUSED here.
--   * an automated decision's model is a 'provider/model' id (openai/gpt-6-luna-pro, anthropic/claude-sonnet-5.5);
--     its FAMILY is the provider prefix. A decision made by code with no model is family 'deterministic'.
--
-- WHAT THIS CHANGES
--   1. public.review_route: the routing TABLE. One row per decision type -> its owning seat. Routing is a
--      primary-key lookup, never a reading of words (routine work is code, not LLM). owner_seat is a foreign
--      key to org_role, so a route can only name a live seat; the founder is not a seat and a CHECK refuses
--      the word as well, so "nothing goes to the founder" is a property of the schema, not of a comment.
--   2. public.decision_review_request: one row per request. (decision_type, owner_seat) is a foreign key to
--      review_route, so a row cannot land with any seat but the route's. original_family / reviewer_family
--      are generated from the model ids, and a CHECK refuses a verdict whose reviewer family equals the
--      original decision's family. The constraint, not the caller, guarantees a different family decides.
--   3. fn_review_request_open: the one door. It looks the route up, files the row, and hands it to the owning
--      seat through fn_seat_handoff (kind review.requested, registered below for every owning seat). A demo
--      subject is filed in this table but raises no handoff (fn_seat_handoff, ruling 1199).
--   4. fn_review_request_reviewer_model: the owning seat's own model ladder (model_policy_by_identity),
--      first model whose family differs from the original decision's. Deterministic.
--   5. fn_review_request_decide: records the verdict with the reviewing model, closes the handoff as its
--      originator (customer_support, which takes every request in), and refuses a same-family verdict.
--   6. THE REVIEW IS DECIDED, NOT LEFT WAITING (agents act). fn_review_request_due hands the open requests to
--      the CEO seat's heartbeat (resilience_ping step review_requests -> ceo_agent action review_requests,
--      _shared/review_decide.ts), which asks the reviewing model through ai_gateway with counterpart_model =
--      the original decision's model, so fn_ai_route_review picks another family. fn_review_request_conclude
--      records the verdict with the model that ACTUALLY answered (the CHECK refuses a same family), the owning
--      seat records the reversed decision in decision_log on an overturn/amendment, and customer_support replies
--      to the requester through its own delivery.request (none is filed for a demo requester, ruling 1199).
--
--   7. RULING 1264 (19 Oct 2026): no option to have a person decide exists anywhere; the app is fully automated and the
--      different-model-family review above IS the review. The ONE exception is an EXPLICIT request for a person,
--      made in chat (WhatsApp, site chat) or e-mail: route 'person' files it (owner_seat customer_support keeps
--      the record) and it reaches the founder through founder_mail_policy, fn_notify_founder with p_kind
--      whatsapp_human_request (WhatsApp, the same dedupe key as fn_wa_human_request, so he is told once) or
--      person_request (site chat, e-mail). The CHECK decision_review_founder_only_for_an_explicit_person_request
--      refuses a founder delivery on any other row, and that branch is the only call to fn_notify_founder here.
--
-- WHAT THIS DOES NOT DO: no review of a decision ever reaches the founder (no founder_alerts, no founder
-- notification); it does not change what "Talk to a person" on the WhatsApp menu does today. The entry points
-- (wa_inbound, email_triage, site_assistant) reach this door through supabase/functions/_shared/review_request.ts.
--
-- Prevented by: scripts/checks/a_contested_decision_is_reviewed_by_the_seat_that_owns_it_on_another_model_family.test.mjs
-- Proved by:    scripts/sql/a_contested_decision_is_reviewed_by_the_seat_that_owns_it_on_another_model_family_probe.sql

create table if not exists public.review_route (
  decision_type text primary key check (decision_type ~ '^[a-z_]+$'),
  owner_seat    text not null references public.org_role (role_id)
                check (owner_seat <> 'founder'),
  meaning       text not null check (btrim(meaning) <> ''),
  unique (decision_type, owner_seat)
);
alter table public.review_route enable row level security;
drop policy if exists review_route_service_role_only on public.review_route;
create policy review_route_service_role_only on public.review_route
  as permissive for all to public using (false) with check (false);
revoke all on public.review_route from anon, authenticated;
comment on table public.review_route is
  'Ledger 1152: which seat reviews a request to review each kind of automated decision. Disputes and approvals go to the ceo; no route names the founder (FK to org_role + CHECK).';

insert into public.review_route (decision_type, owner_seat, meaning) values
  ('matching', 'sales_engineer',   'which suppliers were matched to an inquiry, or why a supplier was not matched'),
  ('specs',    'sales_engineer',   'a specification that was required, held, or judged equivalent or not'),
  ('quotes',   'sales_engineer',   'how a quote was read, compared, ranked or held'),
  ('reports',  'sales_engineer',   'a report or document the platform produced about an inquiry or a supplier'),
  ('fees',     'accountant',       'a reveal fee, subscription fee or penalty that was set or charged'),
  ('refunds',  'accountant',       'a refund that was granted, declined or delayed'),
  ('charges',  'accountant',       'a card or invoice charge, or a payment that was held'),
  ('messaging','customer_support', 'a message the platform sent, held or did not send'),
  ('account',  'customer_support', 'an account or sign-up that was approved, held, archived or refused'),
  ('security', 'it_engineer',      'a security block, a flag or a screening result'),
  ('access',   'it_engineer',      'access to a portal, a document or a feature that was refused or removed'),
  ('dispute',  'ceo',              'a dispute between a customer and a supplier, or with the platform'),
  ('approval', 'ceo',              'an approval or a rejection that was decided automatically'),
  ('person',   'customer_support', 'not a decision: they explicitly ask to speak to a person (ruling 1264, delivered to the founder through founder_mail_policy)')
on conflict (decision_type) do update set owner_seat = excluded.owner_seat, meaning = excluded.meaning;

create table if not exists public.decision_review_request (
  id                bigint generated always as identity primary key,
  decision_type     text not null,
  owner_seat        text not null,
  -- ruling 1264: a contest enters only when the person raises it themselves in chat or e-mail; no portal option exists
  channel           text not null check (channel in ('whatsapp', 'site_chat', 'email')),
  requester         text not null check (btrim(requester) <> ''),
  subject_table     text,
  subject_id        text,
  request_text      text not null check (btrim(request_text) <> ''),
  original_seat     text references public.org_role (role_id),
  original_model    text,
  original_decision_log_id bigint,
  original_family   text generated always as (coalesce(nullif(split_part(original_model, '/', 1), ''), 'deterministic')) stored,
  status            text not null default 'open' check (status in ('open', 'decided', 'with_founder')),
  founder_notified  jsonb,
  reviewer_seat     text references public.org_role (role_id),
  reviewer_model    text,
  reviewer_family   text generated always as (nullif(split_part(reviewer_model, '/', 1), '')) stored,
  verdict           text check (verdict in ('upheld', 'overturned', 'amended')),
  verdict_reason    text,
  handoff_id        bigint,
  evidence          jsonb not null default '{}'::jsonb,
  attempts          integer not null default 0,
  last_attempt_at   timestamptz,
  last_error        text,
  reply_text        text,
  reply_handoff_id  bigint,
  seat_decision_log_id bigint,
  dedupe_key        text unique,
  created_at        timestamptz not null default now(),
  decided_at        timestamptz,
  foreign key (decision_type, owner_seat) references public.review_route (decision_type, owner_seat),
  -- the ruling itself: the review is decided by a different model family than the decision under review
  constraint decision_review_is_decided_by_a_different_model_family
    check (reviewer_model is null
           or split_part(reviewer_model, '/', 1) is distinct from coalesce(nullif(split_part(original_model, '/', 1), ''), 'deterministic')),
  -- ruling 1264: the founder is reached ONLY by an explicit person request made in chat or e-mail
  constraint decision_review_founder_only_for_an_explicit_person_request
    check ((founder_notified is null and status <> 'with_founder')
           or (decision_type = 'person' and channel in ('whatsapp', 'site_chat', 'email') and status = 'with_founder')),
  constraint decision_review_a_person_request_is_never_decided_by_a_model
    check (decision_type <> 'person' or (status <> 'decided' and reviewer_model is null)),
  constraint decision_review_decided_has_its_verdict
    check (status <> 'decided' or (verdict is not null and reviewer_model is not null and reviewer_seat is not null
                               and btrim(coalesce(verdict_reason, '')) <> '' and decided_at is not null))
);

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('review_route', true, 'ceo', 'Which seat owns the review of each kind of automated decision (ledger 1152).', 'ceo'),
  ('decision_review_request', true, 'ceo', 'Each request by a person to review an automated decision, and its outcome (ledger 1152).', 'ceo')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;
create index if not exists decision_review_request_open_idx on public.decision_review_request (owner_seat) where status = 'open';
alter table public.decision_review_request enable row level security;
drop policy if exists decision_review_request_service_role_only on public.decision_review_request;
create policy decision_review_request_service_role_only on public.decision_review_request
  as permissive for all to public using (false) with check (false);
revoke all on public.decision_review_request from anon, authenticated;
comment on table public.decision_review_request is
  'Ledger 1152: a request to review an automated decision, routed by review_route to its owning seat and decided by a different model family (CHECK).';

-- the conversation each owning seat receives; customer_support takes every request in and closes it after the verdict
insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
select 'review.requested', 'customer_support', s.seat,
       'A customer or supplier asked us to review an automated decision this seat owns (review_route); decide it with a different model family than the original decision.',
       'fn_review_request_waits', interval '48 hours', true,
       'scripts/sql/a_contested_decision_is_reviewed_by_the_seat_that_owns_it_on_another_model_family.sql'
  from (select distinct owner_seat as seat from public.review_route where decision_type <> 'person') s
on conflict (type, from_seat, to_seat) do update set handler = excluded.handler, meaning = excluded.meaning,
  reply_within = excluded.reply_within, originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role)
values ('person_request', true,
        'Ruling 1264: an explicit request for a person made in site chat or e-mail is the one thing that reaches the founder (WhatsApp uses whatsapp_human_request).',
        'customer_support')
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason, owner_role = excluded.owner_role;

create or replace function public.fn_review_request_waits(p_id bigint)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('waiting', 'the ' || a.agent || ' verdict on review request '
                            || coalesce(a.detail ->> 'review_request_id', '?') || ', by a different model family')
    from public.agent_actions a where a.id = p_id
$fn$;

create or replace function public.fn_review_request_reviewer_model(p_id bigint)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select m.model
    from public.decision_review_request r
    join public.model_policy_by_identity p on p.identity_key = r.owner_seat
    cross join lateral (values (1, p.primary_model), (2, p.fallback_model), (3, p.escalation_model)) m(rank, model)
   where r.id = p_id and m.model is not null
     and split_part(m.model, '/', 1) is distinct from r.original_family
   order by m.rank
   limit 1
$fn$;

create or replace function public.fn_review_request_open(
  p_decision_type text, p_channel text, p_requester text, p_request_text text,
  p_subject_table text default null, p_subject_id text default null,
  p_original_seat text default null, p_original_model text default null,
  p_original_decision_log_id bigint default null, p_dedupe_key text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_route public.review_route; v_id bigint; v_handoff bigint; v_note jsonb;
begin
  select * into v_route from public.review_route where decision_type = p_decision_type;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'no review_route for decision type ' || coalesce(p_decision_type, 'null'));
  end if;
  -- ruling 1264: no portal (or any other) option; a contest or a person request enters only from chat or e-mail
  if coalesce(p_channel, '') not in ('whatsapp', 'site_chat', 'email') then
    return jsonb_build_object('ok', false, 'error', 'a contest or a person request enters only from chat or e-mail, not ' || coalesce(p_channel, 'null'));
  end if;
  if p_dedupe_key is not null then
    select id, handoff_id into v_id, v_handoff from public.decision_review_request where dedupe_key = p_dedupe_key;
    if v_id is not null then
      return jsonb_build_object('ok', true, 'id', v_id, 'owner_seat', v_route.owner_seat, 'handoff_id', v_handoff, 'existing', true);
    end if;
  end if;
  insert into public.decision_review_request (decision_type, owner_seat, channel, requester, subject_table, subject_id,
         request_text, original_seat, original_model, original_decision_log_id, dedupe_key)
  values (v_route.decision_type, v_route.owner_seat, p_channel, p_requester, p_subject_table, p_subject_id,
          left(p_request_text, 4000), p_original_seat, p_original_model, p_original_decision_log_id, p_dedupe_key)
  returning id into v_id;
  -- RULING 1264, THE ONE FOUNDER ROUTE: an explicit person request, through founder_mail_policy. Nothing else here
  -- reaches him. WhatsApp shares fn_wa_human_request's kind and dedupe key, so the same ask pages him once.
  if v_route.decision_type = 'person' then
    v_note := public.fn_notify_founder(
      p_event => 'A ' || replace(p_channel, '_', ' ') || ' contact asked to speak to a person',
      p_detail => left(p_request_text, 1500) || E'\nFrom: ' || p_requester || ' (request ' || v_id || ')',
      p_level => 'high',
      p_kind => case when p_channel = 'whatsapp' then 'whatsapp_human_request' else 'person_request' end,
      p_dedupe_key => case when p_channel = 'whatsapp'
                           then 'wa_human:' || regexp_replace(p_requester, '[^0-9]', '', 'g') || ':' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD')
                           else 'person_request:' || p_channel || ':' || lower(p_requester) || ':' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD') end,
      p_owner_agent => 'customer_support');
    update public.decision_review_request set status = 'with_founder', founder_notified = coalesce(v_note, '{}'::jsonb) where id = v_id;
    return jsonb_build_object('ok', true, 'id', v_id, 'owner_seat', 'founder', 'founder_notified', v_note);
  end if;
  -- the owning seat's queue; null for a demo subject (fn_seat_handoff files no handoff from a demo row)
  v_handoff := public.fn_seat_handoff('customer_support', v_route.owner_seat, 'review.requested',
                 'decision_review_request', v_id::text,
                 jsonb_build_object('review_request_id', v_id, 'decision_type', v_route.decision_type,
                                    'channel', p_channel, 'requester', p_requester, 'original_model', p_original_model,
                                    'request', left(p_request_text, 500), 'email', case when p_requester like '%@%' then p_requester end,
                                    'subject_table', p_subject_table, 'subject_ref', p_subject_id));
  update public.decision_review_request set handoff_id = v_handoff where id = v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'owner_seat', v_route.owner_seat, 'handoff_id', v_handoff);
end $fn$;

create or replace function public.fn_review_request_decide(
  p_id bigint, p_verdict text, p_reason text, p_reviewer_model text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.decision_review_request; v_model text;
begin
  select * into r from public.decision_review_request where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no review request ' || p_id); end if;
  if r.status = 'decided' then return jsonb_build_object('ok', true, 'id', r.id, 'verdict', r.verdict, 'existing', true); end if;
  v_model := coalesce(p_reviewer_model, public.fn_review_request_reviewer_model(p_id));
  if v_model is null then
    return jsonb_build_object('ok', false, 'error', r.owner_seat || ' has no model of a family other than ' || r.original_family);
  end if;
  -- the CHECK decision_review_is_decided_by_a_different_model_family refuses a same-family verdict here
  update public.decision_review_request
     set status = 'decided', verdict = p_verdict, verdict_reason = p_reason, reviewer_seat = r.owner_seat,
         reviewer_model = v_model, decided_at = now()
   where id = p_id
  returning * into r;
  if r.handoff_id is not null then
    perform set_config('qd.handoff_closer', 'customer_support', true);
    perform public.fn_seat_handoff_complete(r.handoff_id, jsonb_build_object(
      'verified_by', 'customer_support', 'verified_at', now(), 'review_request_id', r.id,
      'verdict', r.verdict || ' by ' || r.reviewer_seat || ' on ' || r.reviewer_model
                 || ' (original family ' || r.original_family || '): ' || left(r.verdict_reason, 400)));
    perform set_config('qd.handoff_closer', '', true);
  end if;
  return jsonb_build_object('ok', true, 'id', r.id, 'verdict', r.verdict, 'reviewer_seat', r.reviewer_seat,
                            'reviewer_model', r.reviewer_model, 'reviewer_family', r.reviewer_family,
                            'original_family', r.original_family);
end $fn$;

-- The open requests a heartbeat decides now: oldest first, at most five attempts, fifteen minutes apart. Each carries
-- what the reviewer needs: the route's meaning, the requester's words, the original decision (decision_log when
-- linked) and the model it is reviewed AGAINST (counterpart), plus the owning seat's other-family model as a hint.
create or replace function public.fn_review_request_due(p_limit integer default 5, p_id bigint default null)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(jsonb_agg(x order by (x ->> 'id')::bigint), '[]'::jsonb) from (
    select jsonb_build_object(
             'id', r.id, 'owner_seat', r.owner_seat, 'decision_type', r.decision_type, 'meaning', rt.meaning,
             'channel', r.channel, 'requester', r.requester, 'request_text', r.request_text,
             'original_seat', r.original_seat, 'original_family', r.original_family,
             'counterpart_model', coalesce(nullif(r.original_model, ''), 'deterministic'),
             'reviewer_model_hint', public.fn_review_request_reviewer_model(r.id),
             'subject_table', r.subject_table, 'subject_id', r.subject_id, 'evidence', r.evidence,
             'original_decision', (select jsonb_build_object('actor', d.actor, 'kind', d.kind, 'decision', d.decision,
                                                             'reasons', d.reasons, 'ctx', d.ctx, 'at', d.created_at)
                                     from public.decision_log d where d.id = r.original_decision_log_id)) x
      from public.decision_review_request r join public.review_route rt on rt.decision_type = r.decision_type
     where r.status = 'open' and r.attempts < 5
       and (p_id is null or r.id = p_id)
       and (p_id is not null or r.last_attempt_at is null or r.last_attempt_at < now() - interval '15 minutes')
     order by r.last_attempt_at nulls first, r.id
     limit greatest(1, least(coalesce(p_limit, 5), 20))) s
$fn$;

create or replace function public.fn_review_request_attempt_failed(p_id bigint, p_error text)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp' as $fn$
  update public.decision_review_request
     set attempts = attempts + 1, last_attempt_at = now(), last_error = left(coalesce(p_error, 'unknown'), 500)
   where id = p_id and status = 'open'
  returning jsonb_build_object('id', id, 'attempts', attempts, 'last_error', last_error)
$fn$;

-- The verdict the reviewing model reached, recorded with the model that actually answered. Then the seats act:
-- an overturn or amendment is the owning seat's new decision (decision_log, superseding the original), and
-- customer_support answers the requester on the channel they used, through its own delivery.request.
create or replace function public.fn_review_request_conclude(
  p_id bigint, p_verdict text, p_reason text, p_reviewer_model text, p_reply text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.decision_review_request; v_dec jsonb; v_log bigint; v_reply bigint; v_wa boolean;
begin
  update public.decision_review_request set attempts = attempts + 1, last_attempt_at = now() where id = p_id;
  v_dec := public.fn_review_request_decide(p_id, p_verdict, p_reason, p_reviewer_model);
  if not coalesce((v_dec ->> 'ok')::boolean, false) or coalesce((v_dec ->> 'existing')::boolean, false) then return v_dec; end if;
  select * into r from public.decision_review_request where id = p_id;

  if r.verdict in ('overturned', 'amended') then
    insert into public.decision_log (actor, kind, ctx, decision, reasons, route_to)
    values (r.owner_seat, 'review_' || r.verdict,
            jsonb_build_object('review_request_id', r.id, 'decision_type', r.decision_type,
                               'supersedes_decision_log_id', r.original_decision_log_id,
                               'subject_table', r.subject_table, 'subject_id', r.subject_id,
                               'reviewer_model', r.reviewer_model, 'original_family', r.original_family),
            r.verdict || ': ' || left(r.verdict_reason, 1000), jsonb_build_array(r.verdict_reason), r.owner_seat)
    returning id into v_log;
  end if;

  if btrim(coalesce(p_reply, '')) <> '' then
    v_wa := r.channel = 'whatsapp';
    -- null for a demo requester: fn_seat_handoff files nothing from a demo row (ruling 1199)
    v_reply := public.fn_seat_handoff('customer_support', 'customer_support', 'delivery.request',
                 'decision_review_request', r.id::text || ':reply',
                 jsonb_build_object('review_request_id', r.id, 'email', case when r.requester like '%@%' then r.requester end,
                   'prepared', jsonb_build_object(
                     'type', 'review_verdict', 'kind', 'review_verdict', 'to_role', 'customer',
                     'channel', case when v_wa then 'whatsapp' else 'email' end,
                     'to_email', case when r.requester like '%@%' then r.requester end,
                     'to_phone', case when v_wa then regexp_replace(r.requester, '[^0-9+]', '', 'g') end,
                     'subject', 'Your review request ' || r.id, 'body', left(p_reply, 3000))));
  end if;
  update public.decision_review_request
     set reply_text = nullif(btrim(coalesce(p_reply, '')), ''), reply_handoff_id = v_reply, seat_decision_log_id = v_log, last_error = null
   where id = p_id;
  return v_dec || jsonb_build_object('seat_decision_log_id', v_log, 'reply_handoff_id', v_reply);
end $fn$;

revoke execute on function public.fn_review_request_due(integer, bigint) from public, anon, authenticated;
revoke execute on function public.fn_review_request_attempt_failed(bigint, text) from public, anon, authenticated;
revoke execute on function public.fn_review_request_conclude(bigint, text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_review_request_due(integer, bigint) to service_role;
grant execute on function public.fn_review_request_attempt_failed(bigint, text) to service_role;
grant execute on function public.fn_review_request_conclude(bigint, text, text, text, text) to service_role;
revoke execute on function public.fn_review_request_waits(bigint) from public, anon, authenticated;
revoke execute on function public.fn_review_request_reviewer_model(bigint) from public, anon, authenticated;
revoke execute on function public.fn_review_request_open(text, text, text, text, text, text, text, text, bigint, text) from public, anon, authenticated;
revoke execute on function public.fn_review_request_decide(bigint, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_review_request_open(text, text, text, text, text, text, text, text, bigint, text) to service_role;
grant execute on function public.fn_review_request_decide(bigint, text, text, text) to service_role;
