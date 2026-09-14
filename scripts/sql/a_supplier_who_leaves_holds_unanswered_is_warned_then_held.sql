-- a_supplier_who_leaves_holds_unanswered_is_warned_then_held.sql
-- Assigned: sales_engineer — the supplier-portal hold desk, delivered by customer_support.
--
-- THE FOUNDER, 14 Sep 2026, verbatim (founder_instruction #158): "we notify directly. and there is no
-- deadline until the customer reveal one of the quotes, otherwise it remains in the system and held
-- for future reference for us to know that this supplier was collaborating, if the incidient is
-- repeated more than 3 times in a row, then the sales agent need to keep that supplier on hold and
-- stop sharing quotes with him. but before than, on 2nd repetitive time he ignores the notification,
-- the sales agent will inform the customer support agent that this is happening, and the sales agent
-- will draft an email and whatsapp letter saying that after the 3rd time you get removed from the
-- suppliers matching algorithm but of course in a very professional gentle way."
-- And #160: "removal from the hold will be on me. i will update you here in a session if that happens
-- because i will have to call the supplier manually and understand the reason for ignoring us".
-- And #143: the sales engineer reaches the supplier through customer_support, on WhatsApp and email.
--
-- MEASURED BEFORE (production, 14 Sep 2026):
--   * quote_spec_hold (PR #610) had no end: a hold outlived its request forever and nothing recorded
--     whether the supplier ever answered it.
--   * Matching already excludes leads.matching_blocked: fn_match_capability and match_suppliers_kw
--     both call fn_is_matchable(…, matching_blocked, …), and customer_api writes inquiry_matches only
--     from their results. The invite routines (enqueue_supplier_invites, fn_invite_ramp) address
--     unregistered leads, which a supplier with quotes is not.
--   * fn_reconcile_doc_blocks clears matching_blocked, but only where matching_block_reason is its own
--     ('licence_expired', 'insurance_expired'); the fraud unban path clears it for any reason. So a
--     hold resting on matching_blocked alone could be lifted by a routine that never heard of it.
--   * fn_contact_timeline (customer_support's case view, #614) shows every notification by lead_id and
--     its requested_by seat, and every support_case; it had no record of a supplier's collaboration.
--
-- WHAT THIS CHANGES:
--   1. A hold still open when the customer reveals a quote on that request is closed as
--      'unresolved_at_decision' (trigger on transactions.revealed_at) and stays as a record.
--   2. That is an "ignored hold" incident for the supplier: public.supplier_collaboration keeps the
--      consecutive count; public.supplier_collaboration_event keeps every incident, append-only.
--      Answering a hold before the decision (released, or superseded by a resubmission) resets the
--      run to 0.
--   3. Second in a row: a support_case for customer_support, and a warning drafted by the sales
--      engineer, sent by customer_support on email and WhatsApp in the supplier's language.
--   4. Third in a row: leads.collaboration_hold_at + matching_blocked (reason 'collaboration_hold'),
--      a support_case, and a notice. A guard trigger refuses clearing it on any path but
--      fn_supplier_collaboration_hold_lift, which only the service role can run, only with a
--      founder_instruction that names the supplier, and which sends a "welcome back" note.
--   5. fn_contact_timeline carries the collaboration events. It is redefined here, whole, with one
--      branch added: the branch reads a table this file creates, so the earlier definition in
--      customer_support_is_the_only_sender_on_email_and_whatsapp.sql (whose own probe runs first in
--      MANIFEST order) could not carry it. This file is canonical for the routine from now on.
--   6. fn.supplier_api may call send_outbox and send_whatsapp: the notice goes out at once, not at the
--      next tick ("we notify directly").
--
-- WHAT IT DOES NOT DO: no reminders and no expiry timer (the founder replaced them); nothing touches a
-- released quote or a reveal; no agent seat can lift a matching hold.

-- ── 1. A hold outlives its request only as a record ─────────────────────────────────────────────
alter table public.quote_spec_hold add column if not exists decided_at timestamptz;
alter table public.quote_spec_hold drop constraint if exists quote_spec_hold_state_check;
alter table public.quote_spec_hold add constraint quote_spec_hold_state_check
  check (state in ('open', 'awaiting_approval', 'released', 'superseded', 'unresolved_at_decision'));

-- ── 2. The supplier's collaboration record ──────────────────────────────────────────────────────
alter table public.leads add column if not exists collaboration_hold_at timestamptz;
comment on column public.leads.collaboration_hold_at is 'Set by the sales engineer when a third consecutive held quote is left unanswered at the customer''s decision (founder_instruction #158). While set, matching_blocked stays true. Cleared only by fn_supplier_collaboration_hold_lift on the founder''s instruction (#160).';

create table if not exists public.supplier_collaboration (
  lead_id             bigint primary key references public.leads(id) on delete cascade,
  consecutive_ignored integer not null default 0 check (consecutive_ignored >= 0),
  total_ignored       integer not null default 0 check (total_ignored >= 0),
  last_incident_at    timestamptz,
  warned_at           timestamptz,
  held_at             timestamptz,
  lifted_at           timestamptz,
  owner_seat          text not null default 'sales_engineer' check (owner_seat = 'sales_engineer'),
  updated_at          timestamptz not null default now()
);
comment on table public.supplier_collaboration is 'Per supplier: how many held quotes in a row were left unanswered when the customer decided (founder_instruction #158). Owned by the sales_engineer seat, service role only.';

create table if not exists public.supplier_collaboration_event (
  id                     bigint generated always as identity primary key,
  lead_id                bigint not null,
  kind                   text not null check (kind in ('ignored_hold', 'cooperated', 'warning_sent', 'matching_hold', 'hold_lifted')),
  inquiry_id             uuid,
  quote_id               uuid,
  hold_id                bigint,
  consecutive_after      integer not null,
  founder_instruction_id bigint references public.founder_instruction(id),
  detail                 jsonb not null default '{}'::jsonb,
  actor                  text not null check (actor in ('sales_engineer', 'founder')),
  created_at             timestamptz not null default now()
);
comment on table public.supplier_collaboration_event is 'The full, append-only history of a supplier''s collaboration: every held quote left unanswered at a decision, every reset by answering, the warning, the matching hold and its lifting. Kept permanently "for future reference for us to know that this supplier was collaborating" (founder, 14 Sep 2026).';
create index if not exists supplier_collaboration_event_by_lead on public.supplier_collaboration_event (lead_id, created_at);

alter table public.supplier_collaboration enable row level security;
drop policy if exists supplier_collaboration_service_role_only on public.supplier_collaboration;
create policy supplier_collaboration_service_role_only on public.supplier_collaboration as permissive for all to public using (false) with check (false);
revoke all on public.supplier_collaboration from anon, authenticated;
alter table public.supplier_collaboration_event enable row level security;
drop policy if exists supplier_collaboration_event_service_role_only on public.supplier_collaboration_event;
create policy supplier_collaboration_event_service_role_only on public.supplier_collaboration_event as permissive for all to public using (false) with check (false);
revoke all on public.supplier_collaboration_event from anon, authenticated;

create or replace function public.fn_supplier_collaboration_event_append_only()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  raise exception 'supplier_collaboration_event is append-only: a supplier''s collaboration history is kept whole (founder, 14 Sep 2026)';
end $fn$;
revoke execute on function public.fn_supplier_collaboration_event_append_only() from public, anon, authenticated;
drop trigger if exists a10_supplier_collaboration_event_append_only on public.supplier_collaboration_event;
create trigger a10_supplier_collaboration_event_append_only before update or delete on public.supplier_collaboration_event
  for each row execute function public.fn_supplier_collaboration_event_append_only();

-- ── 3. A notice to a supplier: the sales engineer asks, customer_support sends, email and WhatsApp ─
create or replace function public.fn_supplier_notice(p_lead bigint, p_type text, p_subject_en text, p_body_en text,
                                                     p_subject_ar text, p_body_ar text, p_inquiry uuid default null, p_quote uuid default null)
returns integer language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare l record; v_ar boolean; v_subject text; v_body text; n int := 0;
begin
  select id, company_name, locale,
         coalesce(nullif(btrim(claimed_by), ''), nullif(btrim(email), '')) as mail,
         coalesce(nullif(btrim(whatsapp), ''), nullif(btrim(phone), ''))  as tel
    into l from public.leads where id = p_lead;
  if not found then return 0; end if;
  v_ar := lower(coalesce(l.locale, '')) like 'ar%';
  v_subject := case when v_ar then p_subject_ar else p_subject_en end;
  v_body := replace(case when v_ar then p_body_ar else p_body_en end, '{company}',
                    coalesce(nullif(btrim(l.company_name), ''), case when v_ar then 'شريكنا' else 'partner' end));
  if l.mail is not null then
    insert into public.notifications (type, kind, to_email, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by, sender)
    values (p_type, 'sales_engineer_' || p_type, l.mail, 'supplier', p_lead, p_inquiry, p_quote, 'email', v_subject, v_body, 'queued', 'sales_engineer', 'customer_support');
    n := n + 1;
  end if;
  -- trg_wa_fanout has already made a WhatsApp twin for a supplier who opted in; otherwise queue one.
  if l.tel is not null and not exists (select 1 from public.notifications
                                        where channel = 'whatsapp' and lead_id = p_lead and type = p_type and created_at = now()) then
    insert into public.notifications (type, kind, to_email, to_phone, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by, sender)
    values (p_type, 'sales_engineer_' || p_type, l.mail, l.tel, 'supplier', p_lead, p_inquiry, p_quote, 'whatsapp', v_subject, v_body, 'queued', 'sales_engineer', 'customer_support');
    n := n + 1;
  end if;
  return n;
end $fn$;
revoke execute on function public.fn_supplier_notice(bigint, text, text, text, text, text, uuid, uuid) from public, anon, authenticated;

-- ── 4. An ignored hold, and what the second and third in a row mean ──────────────────────────────
-- The warning and the hold notice are drafts for the founder's review (PR body). Warm, specific,
-- and they say how to avoid it.
create or replace function public.fn_supplier_collaboration_incident(p_lead bigint, p_inquiry uuid, p_quote uuid, p_hold bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_n int; v_held timestamptz; v_warn int := 0; v_hold int := 0;
        v_ref text := upper(left(coalesce(p_inquiry::text, ''), 8));
begin
  insert into public.supplier_collaboration (lead_id) values (p_lead) on conflict (lead_id) do nothing;
  update public.supplier_collaboration
     set consecutive_ignored = consecutive_ignored + 1, total_ignored = total_ignored + 1, last_incident_at = now(), updated_at = now()
   where lead_id = p_lead returning consecutive_ignored into v_n;
  insert into public.supplier_collaboration_event (lead_id, kind, inquiry_id, quote_id, hold_id, consecutive_after, actor, detail)
  values (p_lead, 'ignored_hold', p_inquiry, p_quote, p_hold, v_n, 'sales_engineer', jsonb_build_object('rfq', v_ref));

  if v_n = 2 then
    insert into public.support_case (case_ref, party_kind, party_id, inquiry_ref, subject, owner_role_id)
    values ('SE-COLLAB-' || p_lead || '-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'), 'supplier', p_lead::text, p_inquiry::text,
            'From the sales engineer: this supplier has left 2 held quotes unanswered in a row (the customer decided before the missing details came). The warning was sent on email and WhatsApp; a third in a row puts them on matching hold.',
            'customer_support');
    v_warn := public.fn_supplier_notice(p_lead, 'supplier_collaboration_warning',
      'A note about your recent quotes on QuotesDone',
      $en$Dear {company},

Thank you for quoting on QuotesDone. We value the time you put into every request.

On your last two requests, your quotation was placed on hold because some details the customer needs to compare quotes fairly were missing (for example the exact material specification, the delivery date, installation or warranty), and the customer made their decision before those details arrived. Complete details help customers choose with confidence, and they give your offer the best chance of being selected.

Whenever a quote is on hold, you can fill in the missing details directly on your supplier portal (we then prepare the standardised quotation for your approval), or upload a revised quotation. It only takes a few minutes.

To keep matching fair for customers, if a third consecutive quotation is still on hold when the customer decides, we will pause new requests to your company until we have spoken with you. We would much rather keep working together, so please reach out if anything is making it difficult to respond.

With thanks,
QuotesDone sales engineer$en$,
      'ملاحظة حول عروضك الأخيرة على QuotesDone',
      $ar$عزيزنا {company}،

شكرًا لتقديمك عروض الأسعار عبر QuotesDone، ونقدّر الوقت الذي تخصصه لكل طلب.

في آخر طلبين، عُلّق عرضك لأن بعض التفاصيل التي يحتاجها العميل ليقارن العروض بإنصاف كانت ناقصة (مثل مواصفات المواد الدقيقة أو تاريخ التسليم أو التركيب أو الضمان)، واتخذ العميل قراره قبل وصول هذه التفاصيل. التفاصيل الكاملة تساعد العملاء على الاختيار بثقة، وتمنح عرضك أفضل فرصة للفوز.

عندما يُعلَّق أي عرض، يمكنك إكمال التفاصيل الناقصة مباشرة من بوابة المورّدين (ونُعدّ لك العرض بالصيغة الموحّدة لتعتمده)، أو رفع عرض معدّل. لا يستغرق ذلك سوى دقائق.

وحرصًا على عدالة المطابقة للعملاء، إذا بقي عرض ثالث على التوالي معلّقًا عند اتخاذ العميل قراره، سنوقف إرسال الطلبات الجديدة إلى شركتكم مؤقتًا إلى أن نتحدث معكم. نحن نفضّل كثيرًا أن نستمر في العمل معًا، فلا تتردد في التواصل معنا إن كان هناك ما يصعّب عليك الرد.

مع خالص الشكر،
مهندس المبيعات في QuotesDone$ar$,
      p_inquiry, p_quote);
    update public.supplier_collaboration set warned_at = now(), updated_at = now() where lead_id = p_lead;
    insert into public.supplier_collaboration_event (lead_id, kind, inquiry_id, quote_id, hold_id, consecutive_after, actor, detail)
    values (p_lead, 'warning_sent', p_inquiry, p_quote, p_hold, v_n, 'sales_engineer', jsonb_build_object('delivery_requests', v_warn));

  elsif v_n >= 3 then
    select collaboration_hold_at into v_held from public.leads where id = p_lead;
    if v_held is null then
      update public.leads set collaboration_hold_at = now(), matching_blocked = true, matching_block_reason = 'collaboration_hold' where id = p_lead;
      update public.supplier_collaboration set held_at = now(), updated_at = now() where lead_id = p_lead;
      insert into public.support_case (case_ref, party_kind, party_id, inquiry_ref, subject, owner_role_id)
      values ('SE-HOLD-' || p_lead || '-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'), 'supplier', p_lead::text, p_inquiry::text,
              'From the sales engineer: supplier put on matching hold after 3 held quotes in a row were left unanswered. New requests are no longer matched to them. Lifting it is the founder''s decision after he calls the supplier (founder_instruction #160).',
              'customer_support');
      v_hold := public.fn_supplier_notice(p_lead, 'supplier_matching_hold',
        'New requests to your company are paused on QuotesDone',
        $en$Dear {company},

Thank you for your time on QuotesDone. On your last three consecutive requests, your quotation was still on hold for missing details when the customer made their decision. As we mentioned in our earlier message, we have therefore paused new requests to your company for now. Your account, your existing quotations and any revealed jobs are not affected.

Our team will be in touch to understand what happened and how we can make responding easier. You are welcome to reply to this message at any time.

With thanks,
QuotesDone sales engineer$en$,
        'تم إيقاف إرسال الطلبات الجديدة إلى شركتكم مؤقتًا على QuotesDone',
        $ar$عزيزنا {company}،

شكرًا لوقتك على QuotesDone. في آخر ثلاثة طلبات متتالية، كان عرضك لا يزال معلّقًا بسبب تفاصيل ناقصة عندما اتخذ العميل قراره، ولذلك، كما ذكرنا في رسالتنا السابقة، أوقفنا إرسال الطلبات الجديدة إلى شركتكم في الوقت الحالي. لا يتأثر حسابك ولا عروضك الحالية ولا الأعمال التي كُشف عنها.

سيتواصل معكم فريقنا لفهم ما حدث وكيف يمكننا تسهيل الرد، ويسعدنا أن تردّ على هذه الرسالة في أي وقت.

مع خالص الشكر،
مهندس المبيعات في QuotesDone$ar$,
        p_inquiry, p_quote);
      insert into public.supplier_collaboration_event (lead_id, kind, inquiry_id, quote_id, hold_id, consecutive_after, actor, detail)
      values (p_lead, 'matching_hold', p_inquiry, p_quote, p_hold, v_n, 'sales_engineer', jsonb_build_object('delivery_requests', v_hold));
    end if;
  end if;
  return jsonb_build_object('lead_id', p_lead, 'consecutive', v_n, 'warning_requests', v_warn, 'hold_requests', v_hold);
end $fn$;
revoke execute on function public.fn_supplier_collaboration_incident(bigint, uuid, uuid, bigint) from public, anon, authenticated;

-- Answering a hold before the decision is cooperation: the run starts again. The history stays.
create or replace function public.fn_supplier_collaboration_cooperated(p_lead bigint, p_quote uuid, p_hold bigint)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_prev int;
begin
  select consecutive_ignored into v_prev from public.supplier_collaboration where lead_id = p_lead for update;
  if coalesce(v_prev, 0) = 0 then return false; end if;
  update public.supplier_collaboration set consecutive_ignored = 0, updated_at = now() where lead_id = p_lead;
  insert into public.supplier_collaboration_event (lead_id, kind, quote_id, hold_id, consecutive_after, actor, detail)
  values (p_lead, 'cooperated', p_quote, p_hold, 0, 'sales_engineer', jsonb_build_object('reset_from', v_prev));
  return true;
end $fn$;
revoke execute on function public.fn_supplier_collaboration_cooperated(bigint, uuid, bigint) from public, anon, authenticated;

create or replace function public.trg_hold_answered_resets_the_run()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if OLD.state in ('open', 'awaiting_approval') and NEW.state in ('released', 'superseded') and NEW.supplier_id is not null then
    perform public.fn_supplier_collaboration_cooperated(NEW.supplier_id, NEW.quote_id, NEW.id);
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_hold_answered_resets_the_run() from public, anon, authenticated;
drop trigger if exists z10_hold_answered_resets_the_run on public.quote_spec_hold;
create trigger z10_hold_answered_resets_the_run after update of state on public.quote_spec_hold
  for each row execute function public.trg_hold_answered_resets_the_run();

-- The decision: the customer reveals a quote on the request. Every hold still open on it is closed
-- as unresolved and counted, once per supplier per request.
create or replace function public.fn_quote_holds_close_at_decision(p_inquiry uuid)
returns integer language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; v_n int := 0; v_seen bigint[] := '{}';
begin
  for r in select h.id, h.quote_id, h.supplier_id from public.quote_spec_hold h join public.quotes q on q.id = h.quote_id
            where q.inquiry_id = p_inquiry and h.state in ('open', 'awaiting_approval') order by h.id
  loop
    update public.quote_spec_hold set state = 'unresolved_at_decision', decided_at = now(), updated_at = now() where id = r.id;
    v_n := v_n + 1;
    if r.supplier_id is not null and not (r.supplier_id = any (v_seen)) then
      v_seen := v_seen || r.supplier_id;
      perform public.fn_supplier_collaboration_incident(r.supplier_id, p_inquiry, r.quote_id, r.id);
    end if;
  end loop;
  return v_n;
end $fn$;
revoke execute on function public.fn_quote_holds_close_at_decision(uuid) from public, anon, authenticated;

create or replace function public.trg_decision_closes_unanswered_holds()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if NEW.revealed_at is null or NEW.inquiry_id is null then return NEW; end if;
  if TG_OP = 'UPDATE' and OLD.revealed_at is not null then return NEW; end if;
  perform public.fn_quote_holds_close_at_decision(NEW.inquiry_id);
  return NEW;
end $fn$;
revoke execute on function public.trg_decision_closes_unanswered_holds() from public, anon, authenticated;
drop trigger if exists z30_decision_closes_unanswered_holds on public.transactions;
create trigger z30_decision_closes_unanswered_holds after insert or update of revealed_at on public.transactions
  for each row execute function public.trg_decision_closes_unanswered_holds();

-- ── 5. The hold cannot be lifted by any path but the founder's ────────────────────────────────────
create or replace function public.fn_leads_collaboration_hold_guard()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if OLD.collaboration_hold_at is not null then
    if NEW.collaboration_hold_at is null and coalesce(current_setting('app.collaboration_hold_lift', true), '') <> 'founder' then
      raise exception 'A supplier matching hold is lifted by the founder only, in a working session, with his founder_instruction (fn_supplier_collaboration_hold_lift). No agent path may lift it (founder_instruction #160).';
    end if;
    -- Any other writer that clears matching_blocked (a document restore, an unban) leaves the hold in force.
    if NEW.collaboration_hold_at is not null and (NEW.matching_blocked is distinct from true or NEW.matching_block_reason is distinct from 'collaboration_hold') then
      NEW.matching_blocked := true; NEW.matching_block_reason := 'collaboration_hold';
    end if;
  end if;
  return NEW;
end $fn$;
revoke execute on function public.fn_leads_collaboration_hold_guard() from public, anon, authenticated;
drop trigger if exists zzz_collaboration_hold_guard on public.leads;
create trigger zzz_collaboration_hold_guard before update on public.leads
  for each row execute function public.fn_leads_collaboration_hold_guard();

-- The only door. Service role only; called in a working session when the founder instructs it; the
-- founder_instruction must exist and name the supplier (its id or its company name).
create or replace function public.fn_supplier_collaboration_hold_lift(p_lead bigint, p_founder_instruction bigint, p_why text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare fi record; l record; v_text text; v_n int;
begin
  if coalesce(btrim(p_why), '') = '' then raise exception 'lifting a matching hold needs the reason the founder gave'; end if;
  select id, instruction, coalesce(subject, '') as subject, coalesce(note, '') as note into fi from public.founder_instruction where id = p_founder_instruction;
  if not found then raise exception 'no founder_instruction %: only the founder lifts a matching hold (#160)', p_founder_instruction; end if;
  select id, company_name, collaboration_hold_at, matching_block_reason into l from public.leads where id = p_lead;
  if not found then raise exception 'no supplier %', p_lead; end if;
  v_text := lower(fi.instruction || ' ' || fi.subject || ' ' || fi.note);
  if not (v_text ~ ('(^|[^0-9])' || p_lead::text || '([^0-9]|$)')
          or (length(btrim(coalesce(l.company_name, ''))) >= 3 and position(lower(btrim(l.company_name)) in v_text) > 0)) then
    raise exception 'founder_instruction % does not name supplier % (%): the founder''s instruction must name who is lifted', p_founder_instruction, p_lead, l.company_name;
  end if;
  if l.collaboration_hold_at is null then raise exception 'supplier % is not on a collaboration matching hold', p_lead; end if;

  perform set_config('app.collaboration_hold_lift', 'founder', true);
  update public.leads
     set collaboration_hold_at = null,
         matching_blocked = case when matching_block_reason = 'collaboration_hold' then false else matching_blocked end,
         matching_block_reason = case when matching_block_reason = 'collaboration_hold' then null else matching_block_reason end
   where id = p_lead;
  perform set_config('app.collaboration_hold_lift', '', true);

  update public.supplier_collaboration set consecutive_ignored = 0, lifted_at = now(), updated_at = now() where lead_id = p_lead;
  select coalesce(max(consecutive_ignored), 0) into v_n from public.supplier_collaboration where lead_id = p_lead;
  insert into public.supplier_collaboration_event (lead_id, kind, consecutive_after, founder_instruction_id, actor, detail)
  values (p_lead, 'hold_lifted', v_n, p_founder_instruction, 'founder',
          jsonb_build_object('why', p_why, 'executed_by', session_user, 'at', now()));
  perform public.fn_supplier_notice(p_lead, 'supplier_matching_hold_lifted',
    'Welcome back to QuotesDone',
    $en$Dear {company},

Thank you for speaking with us. We have resumed new requests to your company, and matching requests will start reaching you again. Whenever a quote needs more detail, you can complete it on your supplier portal in a few minutes.

We look forward to working with you.

With thanks,
QuotesDone sales engineer$en$,
    'مرحبًا بعودتكم إلى QuotesDone',
    $ar$عزيزنا {company}،

شكرًا لحديثكم معنا. استأنفنا إرسال الطلبات الجديدة إلى شركتكم، وستبدأ طلبات المطابقة بالوصول إليكم مجددًا. وعندما يحتاج أي عرض إلى تفاصيل إضافية، يمكنكم إكمالها من بوابة المورّدين خلال دقائق.

نتطلع إلى العمل معكم.

مع خالص الشكر،
مهندس المبيعات في QuotesDone$ar$);
  return jsonb_build_object('ok', true, 'lead_id', p_lead, 'founder_instruction', p_founder_instruction, 'consecutive_ignored', v_n);
end $fn$;
revoke execute on function public.fn_supplier_collaboration_hold_lift(bigint, bigint, text) from public, anon, authenticated;

-- ── 6. customer_support's case timeline carries the collaboration record ─────────────────────────
create or replace function public.fn_contact_timeline(p_contact text, p_limit integer default 60)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $function$
declare
  v_raw text := btrim(coalesce(p_contact, ''));
  v_email text; v_tail text;
  v_cust uuid[]; v_lead bigint[]; v_inq uuid[]; v_txn uuid[]; v_ref bigint[];
  v_events jsonb; v_counts jsonb;
begin
  v_raw := regexp_replace(v_raw, '^whatsapp:', '', 'i');
  if position('@' in v_raw) > 0 then
    v_email := lower(v_raw);
  elsif length(regexp_replace(v_raw, '[^0-9]', '', 'g')) >= 7 then
    v_tail := right(regexp_replace(v_raw, '[^0-9]', '', 'g'), 9);   -- +9715..., 05..., 5...
  else
    return jsonb_build_object('contact', v_raw, 'known', false, 'event_count', 0, 'events', '[]'::jsonb);
  end if;

  select coalesce(array_agg(c.id), '{}') into v_cust from public.customers c
   where (v_email is not null and lower(c.email) = v_email)
      or (v_tail is not null and right(regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g'), 9) = v_tail);
  select coalesce(array_agg(l.id), '{}') into v_lead from public.leads l
   where (v_email is not null and (lower(l.email) = v_email or lower(l.claimed_by) = v_email))
      or (v_tail is not null and v_tail in (right(regexp_replace(coalesce(l.phone_e164, ''), '[^0-9]', '', 'g'), 9),
                                            right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 9),
                                            right(regexp_replace(coalesce(l.whatsapp, ''), '[^0-9]', '', 'g'), 9)));
  select coalesce(array_agg(i.id), '{}') into v_inq from public.inquiries i where i.customer_id = any (v_cust);
  select coalesce(array_agg(t.id), '{}') into v_txn from public.transactions t
   where t.customer_id = any (v_cust) or t.supplier_id = any (v_lead);
  select coalesce(array_agg(r.id), '{}') into v_ref from public.refunds r
   where r.customer_id = any (v_cust) or r.supplier_lead_id = any (v_lead) or r.transaction_id = any (v_txn);

  with ev(at, kind, channel, direction, seat, ref, summary) as (
    -- what they asked for
    select i.created_at, 'request', 'portal', 'in', 'sales_engineer', i.id::text,
           coalesce(i.status, '') || ': ' || left(coalesce(i.summary_masked, i.summary, i.category, ''), 140)
      from public.inquiries i where i.id = any (v_inq)
    -- quotes on their requests: state only, never a supplier or an amount (the pre-reveal rule)
    union all
    select q.created_at, 'quote', 'portal', 'in', 'sales_engineer', q.id::text,
           case when exists (select 1 from public.transactions t where t.quote_id = q.id and t.revealed_at is not null)
                then 'released (revealed)' else 'held (' || coalesce(q.status, 'received') || ')' end
      from public.quotes q where q.inquiry_id = any (v_inq)
    -- quotes they submitted, when the contact is a supplier
    union all
    select q.created_at, 'quote_submitted', 'portal', 'out', 'sales_engineer', q.id::text, coalesce(q.status, 'submitted')
      from public.quotes q where q.supplier_id = any (v_lead)
    -- reveals and what was paid
    union all
    select t.revealed_at, 'reveal', 'portal', 'out', 'accountant', t.id::text, 'fee ' || coalesce(t.fee_status, 'unknown')
      from public.transactions t where t.id = any (v_txn) and t.revealed_at is not null
    union all
    select ri.created_at, 'invoice', 'portal', 'out', 'accountant', ri.invoice_no, 'reveal invoice issued'
      from public.reveal_invoices ri where ri.transaction_id = any (v_txn)
    -- refunds, and the CEO's decision on each (the refund loop)
    union all
    select coalesce(r.updated_at, r.created_at), 'refund', 'portal', 'out', 'accountant', r.id::text,
           coalesce(r.status, '') || coalesce(' — ' || r.reason_code, '')
      from public.refunds r where r.id = any (v_ref)
    union all
    select coalesce(rc.updated_at, rc.created_at), 'refund_case', 'internal', 'internal', 'accountant', rc.case_id::text,
           coalesce(rc.state, '') || coalesce(' — ' || rc.decision, '')
      from public.refund_case rc where rc.refund_id = any (v_ref)
    union all
    select a.decided_at, 'ceo_decision', 'internal', 'internal', 'ceo', a.decision_id::text,
           coalesce(a.subject_kind, '') || ': ' || coalesce(a.decision, '')
      from public.ceo_approval a where a.subject_kind ilike 'refund%' and a.subject_id = any (v_ref::text[])
    -- support cases
    union all
    select coalesce(s.last_activity_at, s.opened_at), 'support_case', 'internal', 'internal',
           coalesce(s.owner_role_id, 'customer_support'), s.case_ref, coalesce(s.state, '') || ': ' || left(coalesce(s.subject, ''), 120)
      from public.support_case s
     where (s.party_kind = 'customer' and s.party_id = any (v_cust::text[]))
        or (s.party_kind = 'supplier' and s.party_id = any (v_lead::text[]))
    -- every message the company sent them, and the seat that asked for it
    union all
    select n.created_at, 'message', coalesce(n.channel, 'email'), 'out', coalesce(n.requested_by, 'customer_support'),
           n.id::text, coalesce(n.status, 'queued') || ': ' || left(coalesce(n.subject, n.type, ''), 140)
      from public.notifications n
     where (v_email is not null and lower(n.to_email) = v_email)
        or (v_tail is not null and right(regexp_replace(coalesce(n.to_phone, ''), '[^0-9]', '', 'g'), 9) = v_tail)
        or n.lead_id = any (v_lead) or n.inquiry_id = any (v_inq)
    -- every message they sent the company
    union all
    select m.created_at, 'message', 'email', 'in', 'customer_support', m.id::text, left(coalesce(m.subject, ''), 140)
      from public.inbound_messages m
     where (v_email is not null and lower(m.from_email) = v_email) or m.lead_id = any (v_lead)
    union all
    select w.at, 'message', 'whatsapp', w.direction, 'customer_support', w.id::text, left(coalesce(w.transcript, w.body, ''), 140)
      from public.wa_turn w join public.wa_conversation c on c.id = w.conversation_id
     where (v_tail is not null and right(regexp_replace(coalesce(c.phone_e164, ''), '[^0-9]', '', 'g'), 9) = v_tail)
        or (c.party_kind = 'customer' and c.party_id = any (v_cust::text[]))
        or (c.party_kind = 'supplier' and c.party_id = any (v_lead::text[]))
    union all
    select pm.created_at, 'message', 'portal_chat', case when pm.customer_id = any (v_cust) and pm.sender = 'customer' then 'in' else 'out' end,
           'sales_engineer', pm.id::text, left(coalesce(pm.redacted_body, ''), 140)
      from public.messages pm where pm.customer_id = any (v_cust) or pm.supplier_id = any (v_lead)
    union all
    select cm.created_at, 'message', 'contact_form', 'in', 'customer_support', cm.id::text, left(coalesce(cm.message, ''), 140)
      from public.contact_messages cm
     where (v_email is not null and lower(cm.email) = v_email)
        or (v_tail is not null and right(regexp_replace(coalesce(cm.phone, ''), '[^0-9]', '', 'g'), 9) = v_tail)
    -- the sales engineer's record of this supplier's collaboration: holds left unanswered at a
    -- decision, resets, the warning, the matching hold and its lifting (founder, 14 Sep 2026)
    union all
    select e.created_at, 'collaboration', 'internal', 'internal', e.actor, e.id::text,
           e.kind || ' — ' || e.consecutive_after || ' in a row' || coalesce(' — RFQ ' || upper(left(e.inquiry_id::text, 8)), '')
      from public.supplier_collaboration_event e where e.lead_id = any (v_lead)
  )
  select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'kind', e.kind, 'channel', e.channel, 'direction', e.direction,
                                               'seat', e.seat, 'ref', e.ref, 'summary', e.summary) order by e.at desc), '[]'::jsonb)
    into v_events
    from (select * from ev where at is not null order by at desc limit greatest(1, least(coalesce(p_limit, 60), 500))) e;

  select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) into v_counts
    from (select x ->> 'kind' k, count(*) n from jsonb_array_elements(v_events) x group by 1) z;

  return jsonb_build_object(
    'contact', coalesce(v_email, v_tail),
    'known', cardinality(v_cust) + cardinality(v_lead) > 0,
    'customer_ids', to_jsonb(v_cust), 'supplier_lead_ids', to_jsonb(v_lead),
    'event_count', jsonb_array_length(v_events), 'counts', v_counts,
    'events', v_events,
    'assembled_by', 'fn_contact_timeline (deterministic; no model)');
end $function$;

-- ── 7. The notice goes out at once ─────────────────────────────────────────────────────────────
update public.internal_credential
   set scope = (select array_agg(distinct s) from unnest(scope || array['send_outbox', 'send_whatsapp']) s)
 where context = 'fn.supplier_api' and not (scope @> array['send_outbox', 'send_whatsapp']);

-- PROBE (catalog only; this file defines things, so it ends in a notice). The behaviour — the run,
-- the reset, the warning through support, the hold, the refused lifts, the founder's lift, the
-- timeline — is proved against production in scripts/checks/a_supplier_who_ignores_holds_is_warned_then_held.test.mjs,
-- inside a transaction that is rolled back.
do $probe$
begin
  if to_regclass('public.supplier_collaboration') is null or to_regclass('public.supplier_collaboration_event') is null then
    raise exception 'CHK<<collaboration tables missing>>';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'z30_decision_closes_unanswered_holds' and tgrelid = 'public.transactions'::regclass)
     or not exists (select 1 from pg_trigger where tgname = 'zzz_collaboration_hold_guard' and tgrelid = 'public.leads'::regclass)
     or not exists (select 1 from pg_trigger where tgname = 'z10_hold_answered_resets_the_run' and tgrelid = 'public.quote_spec_hold'::regclass) then
    raise exception 'CHK<<a collaboration trigger is missing>>';
  end if;
  if has_function_privilege('anon', 'public.fn_supplier_collaboration_hold_lift(bigint,bigint,text)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_supplier_collaboration_hold_lift(bigint,bigint,text)', 'execute') then
    raise exception 'CHK<<the lift is executable by a client role>>';
  end if;
  if not exists (select 1 from public.internal_credential where context = 'fn.supplier_api' and scope @> array['send_outbox', 'send_whatsapp']) then
    raise exception 'CHK<<fn.supplier_api cannot kick the dispatchers>>';
  end if;
  raise notice 'CHK<<holds close at the decision; the run, the warning and the matching hold are wired; only the founder lifts>>';
end $probe$;
