-- THE INVITATIONS GO OUT EVERY DAY, AND A STARTED REGISTRATION IS FOLLOWED (21 Sep 2026, sales_engineer).
--
-- MEASURED 21 Sep 2026 on production (htdblwldjkcgjvmqkbeh), read-only:
--   * enqueue_supplier_invites has NO CALLER. Its last plan in invite_schedule is 7 Sep (pg_cron was
--     removed and nothing replaced the 09:00 UTC job); agent_runs has no 'supplier_invites' row at all.
--     The pool it would draw from today: 17,926 eligible leads (counted in 3.5 s; the dry run of 10 in 5.6 s).
--   * Nobody follows up a supplier who starts and stops. The only action on an unfinished registration
--     is fn_sales_engineer_supplier_documents_tick closing it on day 14. leads.exception_reminders and
--     exception_last_reminder_at exist and nothing has ever written a reminder.
--   * A click on the invitation is not recorded anywhere: claim_lookup resolves the token and forgets.
--   * A SUBMITTED registration left 'pending' (pricing_config.auto_approve_suppliers off, or a
--     verification that failed after the submit) has no clock. Today: 2 submitted, both ZZ DEMO, both
--     approved — the gap is structural, not yet a stranded supplier.
--
-- WHAT THIS CHANGES — one daily duty of the sales engineer, on the company heartbeat:
--   * resilience_step 'supplierOutreach' (every 30 min) + resilience_ping STEP_RUN.supplierOutreach ->
--     fn_sales_engineer_supplier_outreach_tick(), which acts ONCE per Asia/Dubai day, from 09:00 Dubai:
--       1. enqueue_supplier_invites() — unchanged; it already holds on the gates, the UAE weekend and
--          holidays, and records the held plan (invite_schedule + agent_runs 'supplier_invites').
--       2. registration reminders — day 2 and day 6 after the supplier's last activity, in the lead's
--          language, through customer_support's delivery door (the normal outbox). HELD while
--          invite_enabled / supplier_outreach_golive are off: counted, recorded, nothing written.
--       3. the 24-hour clock — a submitted registration still undecided 24 h later is re-verified by
--          the sales engineer and, if still undecided, reported to the CEO (support_ceo_report), never
--          to the founder.
--     and records the day in agent_runs (agent 'sales_engineer', job 'supplier_outreach'), held or not.
--   * leads.invite_clicked_at — written by claim_lookup the first time an invitation link is opened.
--
-- WHAT THIS DOES NOT CHANGE: invite_enabled and supplier_outreach_golive stay 'false'. The per-day cap,
-- the bounce brake, one-invitation-per-address and the recipient rule stay inside
-- enqueue_supplier_invites / fn_supplier_invite_eligible (customer_support's file, PR #787) and are not
-- reimplemented. The day-14 close is not moved. The CEO's decision on the new report is its existing
-- 'read' branch: this file does not let any seat approve a supplier that auto-approve would not.
--
-- Ends in a verdict row (PROBE OK / PROBE FAILED): a rolled-back rehearsal on ZZ DEMO fixtures.
--   node scripts/apply_sql.mjs scripts/sql/the_invitations_go_out_every_day_and_a_started_registration_is_followed.sql --apply --ddl

-- ── 0. the click is recorded ─────────────────────────────────────────────────────────────────────
-- Nullable, no default: a catalogue-only change, but it still needs the table lock for an instant, so
-- it waits at most 3 s rather than queueing behind a long read and holding sign-in behind it.
set local lock_timeout = '3s';
alter table public.leads add column if not exists invite_clicked_at timestamptz;
comment on column public.leads.invite_clicked_at is
  'First time the invitation link (claim_token) was opened, written by claim_lookup. Read by fn_supplier_registration_reminders_due.';

-- ── 1. the step on the heartbeat ─────────────────────────────────────────────────────────────────
-- `every` is how often the tick ASKS; the routine's own gate is once per Dubai day.
insert into public.resilience_step (step, every, budget_ms, place, rank, note) values
  ('supplierOutreach', interval '30 min', 12000, 'plan', 0,
   'sales_engineer: the daily supplier invitation batch, registration reminders and the 24-hour clock on a submitted registration (fn_sales_engineer_supplier_outreach_tick, once per Dubai day from 09:00). MEASURED 21 Sep: the held path counts the pool in 3.5 s; an open day adds the 5.6 s selection')
on conflict (step) do update
   set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place, rank = excluded.rank, note = excluded.note;

-- ── 2. who may be written to at all ──────────────────────────────────────────────────────────────
-- The same walls as fn_supplier_invite_eligible, minus its never-invited clauses (a reminder goes to
-- someone who already engaged): never a fixture, never banned, screened, closed, bounced or unsendable.
create or replace function public.fn_supplier_outreach_reachable(p public.leads, p_to text)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(btrim(p_to), '') <> ''
     and coalesce(p.is_demo, false) = false
     and coalesce(p.company_name, '') !~* '^\s*zz\s*demo'
     and not public.fn_is_demo_email(p_to)
     and not public.fn_is_demo_email(p.email)
     and coalesce(p.banned, false) = false
     and coalesce(p.permanently_closed, false) = false
     and coalesce(p.invite_status, '') <> 'bounced'
     and not exists (select 1 from public.sanctions_ban b where b.lead_id = p.id)
     and not exists (select 1 from public.supplier_screening_hit h where h.lead_id = p.id and h.status in ('open', 'confirmed'))
     and coalesce((public.fn_email_sendable(p_to)->>'ok')::boolean, false)
$fn$;
revoke execute on function public.fn_supplier_outreach_reachable(public.leads, text) from public, anon, authenticated;

-- ── 3. the reminder, in the supplier's language ──────────────────────────────────────────────────
-- Three stages, two steps each (1 = day 2, 2 = day 6 and the last):
--   clicked     opened the invitation, never claimed             -> the invitation link again
--   started     claimed, never submitted                          -> the portal, "continue where you left off"
--   incomplete  submitted, still missing items (action_required)  -> the items, and the day-14 date
-- The Arabic is written as Gulf business correspondence in the register of app_secrets.invite_body_ar
-- (السادة/ ... المحترمين، تحية طيبة وبعد، ... وتفضلوا بقبول فائق الاحترام والتقدير)، not translated line by
-- line. The signature is the frame's (send_outbox), as for the invitation.
create or replace function public.fn_supplier_registration_reminder_compose(p public.leads, p_stage text, p_step integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_ar boolean := lower(coalesce(p.locale, '')) like 'ar%';
  v_lang text; v_site text; v_link text; v_name text := nullif(btrim(coalesce(p.company_name, '')), '');
  v_items_en text; v_items_ar text; v_due_en text; v_due_ar text; v_last boolean := p_step >= 2;
  v_greet text; v_subj text; v_body text;
  v_label jsonb := jsonb_build_object(
    'reg_name',        jsonb_build_array('company name', 'اسم الشركة'),
    'reg_mobile',      jsonb_build_array('a verified UAE mobile number', 'رقم جوال إماراتي تم التحقق منه'),
    'reg_email',       jsonb_build_array('a verified e-mail address', 'بريد إلكتروني تم التحقق منه'),
    'reg_licence',     jsonb_build_array('trade licence', 'الرخصة التجارية'),
    'reg_profile',     jsonb_build_array('company profile', 'الملف التعريفي للشركة'),
    'reg_terms',       jsonb_build_array('the signed supplier terms', 'الموافقة الموقّعة على شروط المورِّد'));
begin
  if p_stage not in ('clicked', 'started', 'incomplete') or p_step not in (1, 2) then
    raise exception 'fn_supplier_registration_reminder_compose: unknown stage % or step %', p_stage, p_step;
  end if;
  v_lang := case when v_ar then 'ar' else 'en' end;
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');
  v_link := v_site || '/' || v_lang || '/portal'
            || case when p_stage = 'clicked' and p.claim_token is not null then '?t=' || p.claim_token::text else '' end;

  if p_stage = 'incomplete' then
    select string_agg(coalesce(v_label->k->>0, k), ', ' order by o), string_agg(coalesce(v_label->k->>1, k), '، ' order by o)
      into v_items_en, v_items_ar from unnest(public.fn_supplier_mandatory_six(p)) with ordinality u(k, o);
    if p.license_expiry is not null and p.license_expiry < current_date then
      v_items_en := concat_ws(', ', v_items_en, 'a trade licence that is in date');
      v_items_ar := concat_ws('، ', v_items_ar, 'رخصة تجارية سارية المفعول');
    end if;
    v_items_en := coalesce(v_items_en, 'the items shown in your portal');
    v_items_ar := coalesce(v_items_ar, 'البنود الموضّحة في بوابتكم');
    v_due_en := to_char(coalesce(p.exception_due_at, now() + interval '14 days') at time zone 'Asia/Dubai', 'DD Mon YYYY');
    v_due_ar := to_char(coalesce(p.exception_due_at, now() + interval '14 days') at time zone 'Asia/Dubai', 'DD/MM/YYYY');
  end if;

  if v_ar then
    v_greet := case when v_name is null then 'السادة الكرام،' else 'السادة/ ' || v_name || ' المحترمين،' end;
    v_subj := case when v_last then 'تذكير أخير: ' else '' end
      || case p_stage when 'clicked' then 'دعوتكم للانضمام إلى الموردين المؤسِّسين في QuotesDone'
                      else 'استكمال تسجيلكم كمورِّد في QuotesDone' end;
    v_body := v_greet || E'\n\nتحية طيبة وبعد،\n\n'
      || case p_stage
           when 'clicked' then
             'نشكر لكم اطّلاعكم على دعوتنا للانضمام بصفة «مورِّد مؤسِّس» إلى QuotesDone، ونودّ إفادتكم بأن تسجيل شركتكم لم يبدأ بعد. '
             || 'ولا يستغرق التسجيل سوى دقائق معدودة، وهو مجاني دون أي عمولة على الأعمال التي تُرسى عليكم.'
             || E'\n\nللتسجيل، يُرجى الدخول إلى بوابة الموردين الخاصة بكم عبر الرابط التالي:\n\n' || v_link
           when 'started' then
             'نشكر لكم بدء تسجيل شركتكم مورِّدًا على منصة QuotesDone، ونودّ إفادتكم بأن طلب التسجيل لم يُستكمل بعد. '
             || 'ولا يستغرق استكماله سوى دقائق معدودة: بيانات الشركة، ورقم جوال وبريد إلكتروني يتم التحقق منهما، والرخصة التجارية، '
             || 'والملف التعريفي للشركة، والموافقة على شروط المورِّد.'
             || E'\n\nيمكنكم متابعة التسجيل من حيث توقفتم عبر الرابط التالي:\n\n' || v_link
           else
             'نفيدكم بأن طلب تسجيل شركتكم محفوظ لدينا، غير أنه ما زال ينقصه: ' || v_items_ar || '. '
             || 'ويُرجى استكماله في موعد أقصاه ' || v_due_ar || '، إذ يُغلق طلب التسجيل تلقائيًا بعد هذا التاريخ، ويمكنكم التسجيل من جديد في أي وقت.'
             || E'\n\nيمكنكم استكمال البنود المطلوبة عبر بوابة الموردين:\n\n' || v_link
         end
      || case when v_last then E'\n\nوهذا آخر تذكير نرسله إليكم بهذا الشأن.' else '' end
      || E'\n\nوفي حال عدم رغبتكم في تلقي هذه التذكيرات، يكفي الرد على هذه الرسالة لإزالة عنوانكم من القائمة.'
      || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
  else
    v_greet := case when v_name is null then 'Dear Sir or Madam,' else 'Dear ' || v_name || ',' end;
    v_subj := case when v_last then 'A last reminder: ' else '' end
      || case p_stage when 'clicked' then 'your invitation to join QuotesDone as a founding supplier'
                      else 'complete your QuotesDone supplier registration' end;
    v_body := v_greet || E'\n\n'
      || case p_stage
           when 'clicked' then
             'Thank you for opening our invitation to join QuotesDone as a founding supplier. Your company has not registered yet. '
             || 'It takes a few minutes, it is free, and there is no commission on the work you win.'
             || E'\n\nTo register, open your supplier portal here:\n\n' || v_link
           when 'started' then
             'Thank you for starting to register your company as a supplier on QuotesDone. The registration is not finished yet. '
             || 'It takes a few minutes: company details, a verified mobile number and e-mail address, your trade licence, '
             || 'your company profile and acceptance of the supplier terms.'
             || E'\n\nContinue where you left off:\n\n' || v_link
           else
             'Your registration is saved, but it still needs: ' || v_items_en || '. '
             || 'Please complete it by ' || v_due_en || '; after that date the registration closes automatically, and you are welcome to start again at any time.'
             || E'\n\nComplete the missing items in your supplier portal:\n\n' || v_link
         end
      || case when v_last then E'\n\nThis is the last reminder we will send about it.' else '' end
      || E'\n\nIf you would rather not receive these reminders, reply to this e-mail and we will remove your address.';
  end if;
  return jsonb_build_object('lang', v_lang, 'subject', v_subj, 'body', v_body, 'link', v_link);
end
$fn$;
revoke execute on function public.fn_supplier_registration_reminder_compose(public.leads, text, integer) from public, anon, authenticated;

-- ── 4. who is due a reminder today ───────────────────────────────────────────────────────────────
-- Step 1 is due from day 2 to day 6 after the last activity, step 2 from day 6 to day 14; a step is
-- due once per activity (the delivery key carries the activity's epoch, so new activity starts a new
-- episode). Stops by construction on finish (the stage no longer matches), on the day-14 close
-- (window closed, or 14 days passed), and on unsubscribe / bounce / screening (fn_supplier_outreach_reachable).
-- "Already sent" is read from the delivery requests themselves, not from a status column.
create or replace function public.fn_supplier_registration_reminders_due()
returns table (lead_id bigint, stage text, step integer, last_activity timestamptz, to_email text, dedupe_key text)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with s as (
    select l.id, lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email))) as to_email,
           case when coalesce(l.approval_status, '') = 'action_required'
                     and l.exception_opened_at is not null and l.exception_closed_at is null
                     and coalesce(l.exception_due_at, 'infinity') > now() then 'incomplete'
                when coalesce(l.claimed, false) and l.registration_submitted_at is null
                     and coalesce(l.approval_status, '') not in ('approved', 'rejected', 'pending', 'action_required') then 'started'
                when not coalesce(l.claimed, false) and l.invite_clicked_at is not null then 'clicked'
           end as stage,
           case when coalesce(l.approval_status, '') = 'action_required'
                  then greatest(l.exception_opened_at, coalesce(l.portal_updated_at, l.exception_opened_at))
                when coalesce(l.claimed, false)
                  then coalesce(l.portal_updated_at, l.invite_clicked_at, l.invited_at, l.created_at)
                else l.invite_clicked_at end as last_activity,
           l as lead
      from public.leads l
     where l.invite_clicked_at is not null or coalesce(l.claimed, false) or l.approval_status = 'action_required'
  ), d as (
    select s.*, case when now() >= s.last_activity + interval '6 days' then 2
                     when now() >= s.last_activity + interval '2 days' then 1 end as step
      from s
     where s.stage is not null and s.last_activity is not null
       and now() < s.last_activity + interval '14 days'
  )
  select d.id, d.stage, d.step, d.last_activity, d.to_email,
         'supplier_registration_reminder:' || d.id || ':' || extract(epoch from d.last_activity)::bigint || ':' || d.step
    from d
   where d.step is not null
     and public.fn_supplier_outreach_reachable(d.lead, d.to_email)
     and not exists (select 1 from public.agent_actions a
                      where a.kind = 'handoff' and a.agent = 'customer_support'
                        and a.target_id = 'delivery.request:supplier_registration_reminder:' || d.id || ':'
                                          || extract(epoch from d.last_activity)::bigint || ':' || d.step)
   order by d.id
$fn$;
revoke execute on function public.fn_supplier_registration_reminders_due() from public, anon, authenticated;

-- ── 5. one reminder, through the normal outbox ───────────────────────────────────────────────────
-- Refuses unless the campaign is open AND the lead is reachable — except a fixture address, which is
-- the test path: zzzz_notifications_demo_capture records it 'suppressed' and it never reaches Resend
-- (the same rule a07 applies to the invitation).
create or replace function public.fn_sales_engineer_sends_registration_reminder(p_lead_id bigint, p_stage text, p_step integer, p_last_activity timestamptz)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare l public.leads; v_to text; v_fixture boolean; v_go boolean; m jsonb; v_key text; v_out jsonb;
begin
  select * into l from public.leads where id = p_lead_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'lead_not_found'); end if;
  v_to := lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email)));
  v_fixture := public.fn_is_demo_email(v_to);
  v_go := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
          and public.fn_supplier_outreach_golive();
  if not v_fixture and not v_go then
    return jsonb_build_object('ok', false, 'held', true, 'reason', 'the supplier campaign is not open (invite_enabled / supplier_outreach_golive)');
  end if;
  if not v_fixture and not public.fn_supplier_outreach_reachable(l, v_to) then
    return jsonb_build_object('ok', false, 'reason', 'not reachable: fixture, banned, screened, closed, bounced, suppressed or unsendable');
  end if;
  m := public.fn_supplier_registration_reminder_compose(l, p_stage, p_step);
  v_key := 'supplier_registration_reminder:' || l.id || ':' || extract(epoch from p_last_activity)::bigint || ':' || p_step;
  v_out := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
    'type', 'supplier_registration_reminder', 'requested_by', 'sales_engineer', 'channel', 'email',
    'to_email', v_to, 'to_role', 'supplier', 'lead_id', l.id, 'lang', m->>'lang',
    'subject', m->>'subject', 'body', m->>'body', 'dedupe_key', v_key)));
  return jsonb_build_object('ok', true, 'lead_id', l.id, 'stage', p_stage, 'step', p_step, 'lang', m->>'lang', 'fixture', v_fixture,
                            'delivery', v_out->0);
end
$fn$;
revoke execute on function public.fn_sales_engineer_sends_registration_reminder(bigint, text, integer, timestamptz) from public, anon, authenticated;

-- ── 6. the 24-hour clock on a submitted registration ─────────────────────────────────────────────
-- The sales engineer acts first (re-runs its own verification: with auto-approve on, a complete
-- registration is approved here). If it is still undecided, it reports to the CEO — its parent in
-- org_reporting_edge — once per submission (the idempotency key carries the submission time).
-- p_include_fixtures exists for the probe only; the daily run never escalates a ZZ DEMO fixture.
create or replace function public.fn_sales_engineer_raises_undecided_submissions(p_include_fixtures boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r record; v jsonb; rep jsonb; v_acted int := 0; v_raised int := 0; v_already int := 0; v_refused jsonb := '[]'::jsonb;
begin
  for r in select l.id, l.company_name, l.registration_submitted_at, l.approval_status
             from public.leads l
            where l.registration_submitted_at < now() - interval '24 hours'
              and coalesce(l.approval_status, '') in ('', 'pending')
              and coalesce(l.banned, false) = false
              and (p_include_fixtures or not (coalesce(l.is_demo, false) or coalesce(l.company_name, '') ~* '^\s*zz\s*demo'
                                              or public.fn_is_demo_email(l.email)))
            order by l.registration_submitted_at loop
    v := public.fn_sales_engineer_verifies_supplier(r.id, 'submission_24h_clock');
    if coalesce((v->>'ok')::boolean, false) and coalesce(v->>'approval_status', '') not in ('', 'pending') then
      v_acted := v_acted + 1;
      continue;
    end if;
    rep := public.fn_support_report_to_ceo(
      'supplier_submission_undecided:' || r.id || ':' || extract(epoch from r.registration_submitted_at)::bigint,
      'elevated',
      'A supplier registration submitted ' || floor(extract(epoch from now() - r.registration_submitted_at) / 3600)::int
        || ' h ago is still undecided — ' || left(coalesce(r.company_name, 'supplier #' || r.id), 120),
      jsonb_build_object('supplier_id', r.id, 'submitted_at', r.registration_submitted_at,
                         'approval_status', coalesce(v->>'approval_status', r.approval_status), 'verification', v),
      jsonb_build_array('sales_engineer re-ran its verification at the 24-hour mark: '
                        || coalesce(v->>'approval_status', 'the verification did not complete (' || coalesce(v->>'error', 'no error') || ')')),
      case when coalesce((v->>'auto_approve')::boolean, true) = false
           then 'Decide the approval. The six items are complete and pricing_config.auto_approve_suppliers is off, so the sales engineer may not approve alone.'
           else 'Decide why the verification cannot settle this registration, and settle it.' end,
      'leads#' || r.id, p_source_agent => 'sales_engineer');
    if not coalesce((rep->>'ok')::boolean, false) then
      v_refused := v_refused || jsonb_build_array(jsonb_build_object('supplier_id', r.id, 'reason', rep->>'reason'));
    elsif coalesce((rep->>'duplicate')::boolean, false) then v_already := v_already + 1;
    else v_raised := v_raised + 1;
    end if;
  end loop;
  return jsonb_build_object('acted', v_acted, 'raised_to_ceo', v_raised, 'already_raised', v_already, 'refused', v_refused);
end
$fn$;
revoke execute on function public.fn_sales_engineer_raises_undecided_submissions(boolean) from public, anon, authenticated;

-- ── 7. the daily duty ────────────────────────────────────────────────────────────────────────────
-- Once per Asia/Dubai day from 09:00 Dubai. The day is recorded whether it sent or held, so a held
-- day is a row in agent_runs, not silence. p_force skips the time-of-day gate for the probe only.
create or replace function public.fn_sales_engineer_supplier_outreach_tick(p_force boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_now_dxb timestamp := now() at time zone 'Asia/Dubai';
  v_go boolean; v_weekend boolean; v_invited int; r record; s jsonb;
  v_due int := 0; v_sent int := 0; v_failed jsonb := '[]'::jsonb; v_clock jsonb; v_out jsonb; v_why text;
begin
  if not p_force then
    if extract(hour from v_now_dxb) < 9 then return jsonb_build_object('due', false, 'reason', 'before 09:00 Dubai'); end if;
    if exists (select 1 from public.agent_runs a
                where a.agent = 'sales_engineer' and a.counts->>'job' = 'supplier_outreach'
                  and a.started_at > now() - interval '1 day'
                  and (a.started_at at time zone 'Asia/Dubai')::date = v_now_dxb::date) then
      return jsonb_build_object('due', false, 'reason', 'already ran this Dubai day');
    end if;
  end if;

  v_go := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
          and public.fn_supplier_outreach_golive();
  v_weekend := extract(isodow from v_now_dxb) in (6, 7);
  v_why := case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
                when not v_go then 'invite_enabled is false'
                when v_weekend then 'it is the UAE weekend' end;

  -- 1. The batch. enqueue_supplier_invites holds itself (gates, weekend, holiday, bounce brake, cap).
  v_invited := public.enqueue_supplier_invites(null);

  -- 2. Reminders: always counted; written only on an open weekday.
  for r in select * from public.fn_supplier_registration_reminders_due() loop
    v_due := v_due + 1;
    if v_why is not null then continue; end if;
    s := public.fn_sales_engineer_sends_registration_reminder(r.lead_id, r.stage, r.step, r.last_activity);
    if coalesce((s->>'ok')::boolean, false) then v_sent := v_sent + 1;
    else v_failed := v_failed || jsonb_build_array(jsonb_build_object('lead_id', r.lead_id, 'reason', s->>'reason'));
    end if;
  end loop;

  -- 3. The 24-hour clock: internal, so not held by the campaign gates.
  v_clock := public.fn_sales_engineer_raises_undecided_submissions(false);

  v_out := jsonb_build_object('job', 'supplier_outreach', 'dubai_day', v_now_dxb::date, 'held', v_why is not null, 'held_because', v_why,
    'invites', jsonb_build_object('queued', v_invited),
    'reminders', jsonb_build_object('due', v_due, 'sent', v_sent, 'failed', v_failed),
    'submissions', v_clock);
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('sales_engineer', case when jsonb_array_length(v_failed) > 0 then 'warn' else 'ok' end, now(), now(), v_out,
          case when v_why is not null
               then 'Supplier outreach HELD (' || v_why || '): ' || v_invited || ' invitation(s) queued, ' || v_due
                    || ' reminder(s) due and none written; ' || coalesce(v_clock->>'raised_to_ceo', '0') || ' undecided submission(s) raised to the CEO.'
               else 'Supplier outreach: ' || v_invited || ' invitation(s) queued, ' || v_sent || ' of ' || v_due
                    || ' reminder(s) sent; ' || coalesce(v_clock->>'raised_to_ceo', '0') || ' undecided submission(s) raised to the CEO.' end);
  return v_out;
end
$fn$;
revoke execute on function public.fn_sales_engineer_supplier_outreach_tick(boolean) from public, anon, authenticated;

-- ── 8. PROBE — a rolled-back rehearsal on ZZ DEMO fixtures, ending in ONE verdict row ────────────
-- It refuses to run at all if either gate is open: with the gates shut, nothing in the tick can write
-- an invitation or a reminder to a real address, so running the whole tick inside a block that its own
-- raise rolls back touches nothing real. Fixtures only: 'ZZ DEMO …' names and @example.invalid.
create temp table if not exists zz_outreach_probe (verdict text) on commit drop;
do $probe$
declare
  v_gates_open boolean; t jsonb; v_held_run int; v_invites_before int; v_invites_after int; v_rem_rows int;
  v_click bigint; v_start bigint; v_due_demo int; c_en jsonb; c_ar jsonb; s jsonb; v_note_lang text; v_note_status text;
  v_sub bigint; v_six bigint; v_clock jsonb; v_clock2 jsonb; v_rep int; v_left int; v_fail text[] := '{}';
begin
  v_gates_open := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
                  or public.fn_supplier_outreach_golive();
  if v_gates_open then
    insert into zz_outreach_probe values ('PROBE FAILED: a campaign gate is open; the rehearsal refused to run');
    return;
  end if;
  begin
    -- (1) the held day: whole tick, gates shut
    select count(*) into v_invites_before from public.notifications where type = 'supplier_invite';
    t := public.fn_sales_engineer_supplier_outreach_tick(true);
    select count(*) into v_invites_after from public.notifications where type = 'supplier_invite';
    select count(*) into v_held_run from public.agent_runs
     where agent = 'sales_engineer' and counts->>'job' = 'supplier_outreach' and (counts->>'held')::boolean and started_at >= now();
    select count(*) into v_rem_rows from public.notifications where type = 'supplier_registration_reminder' and created_at >= now();

    -- (2) fixtures in every stage are never due
    insert into public.leads (company_name, email, source, locale, claim_token)
    values ('ZZ DEMO outreach clicked', 'zz-demo-outreach-clicked@example.invalid', 'probe', 'ar', gen_random_uuid()) returning id into v_click;
    update public.leads set invite_clicked_at = now() - interval '3 days' where id = v_click;
    insert into public.leads (company_name, email, source, locale, claimed, claimed_by, portal_updated_at)
    values ('ZZ DEMO outreach started', 'zz-demo-outreach-started@example.invalid', 'probe', 'en', true,
            'zz-demo-outreach-started@example.invalid', now() - interval '7 days') returning id into v_start;
    select count(*) into v_due_demo from public.fn_supplier_registration_reminders_due() where lead_id in (v_click, v_start);

    -- (3) composition in both languages, and the test path through the real outbox
    c_ar := public.fn_supplier_registration_reminder_compose((select l from public.leads l where l.id = v_click), 'clicked', 1);
    c_en := public.fn_supplier_registration_reminder_compose((select l from public.leads l where l.id = v_start), 'started', 2);
    s := public.fn_sales_engineer_sends_registration_reminder(v_click, 'clicked', 1, now() - interval '3 days');
    select lang, status into v_note_lang, v_note_status from public.notifications
     where lead_id = v_click and type = 'supplier_registration_reminder' order by id desc limit 1;

    -- (4) the 24-hour clock: a fixture submitted 25 h ago and still undecided reaches the CEO, once
    insert into public.leads (company_name, email, source, locale, claimed, claimed_by)
    values ('ZZ DEMO outreach submitted', 'zz-demo-outreach-submitted@example.invalid', 'probe', 'en', true,
            'zz-demo-outreach-submitted@example.invalid') returning id into v_sub;
    update public.leads set registration_submitted_at = now() - interval '25 hours' where id = v_sub;
    update public.pricing_config set auto_approve_suppliers = false where id = 1;
    -- the verification decides action_required for an empty fixture (the six are missing), which is the
    -- sales engineer ACTING — so the clock must count it acted and raise nothing …
    v_clock := public.fn_sales_engineer_raises_undecided_submissions(true);
    if coalesce((v_clock->>'acted')::int, 0) < 1 then v_fail := v_fail || ('the clock did not act on an undecided submission: ' || v_clock::text); end if;
    select count(*) into v_rep from public.support_ceo_report where idempotency_key like 'supplier_submission_undecided:' || v_sub || ':%';
    if v_rep <> 0 then v_fail := v_fail || text 'an acted-on submission was still raised to the CEO'; end if;
    -- … and a COMPLETE fixture (the six present) with auto-approve off stays pending, so it is raised to
    -- the CEO exactly once, however many days the clock runs.
    select l.id into v_six from public.leads l
     where coalesce(l.is_demo, false) and coalesce(l.banned, false) = false and l.approval_status = 'approved'
       and public.fn_is_demo_email(coalesce(l.claimed_by, l.email)) and cardinality(public.fn_supplier_mandatory_six(l)) = 0
       and (l.license_expiry is null or l.license_expiry >= current_date)
     order by l.id limit 1;
    if v_six is null then
      v_fail := v_fail || text 'no complete ZZ DEMO supplier exists to rehearse the CEO branch on';
    else
      update public.leads set approval_status = 'pending', verified = false, registration_submitted_at = now() - interval '25 hours' where id = v_six;
      v_clock := public.fn_sales_engineer_raises_undecided_submissions(true);
      v_clock2 := public.fn_sales_engineer_raises_undecided_submissions(true);
      select count(*) into v_rep from public.support_ceo_report
       where idempotency_key like 'supplier_submission_undecided:' || v_six || ':%' and source_agent = 'sales_engineer' and status = 'sent';
      if v_rep <> 1 or coalesce((v_clock2->>'already_raised')::int, 0) < 1 then
        v_fail := v_fail || ('a complete undecided submission was not raised to the CEO exactly once: reports=' || v_rep
                            || ' first=' || v_clock::text || ' second=' || v_clock2::text);
      end if;
    end if;

    if not (t->>'held')::boolean then v_fail := v_fail || ('the tick did not report held: ' || t::text); end if;
    if coalesce((t->'invites'->>'queued')::int, -1) <> 0 then v_fail := v_fail || text 'a held day queued invitations'; end if;
    if v_invites_after <> v_invites_before then v_fail := v_fail || text 'a held day wrote a supplier_invite row'; end if;
    if coalesce((t->'reminders'->>'sent')::int, -1) <> 0 or v_rem_rows <> 0 then v_fail := v_fail || text 'a held day wrote a reminder'; end if;
    if v_held_run <> 1 then v_fail := v_fail || ('the held day was recorded ' || v_held_run || ' times, expected once'); end if;
    if v_due_demo <> 0 then v_fail := v_fail || text 'a ZZ DEMO fixture was due a real reminder'; end if;
    if c_ar->>'lang' <> 'ar' or c_ar->>'body' !~ '[؀-ۿ]' or c_ar->>'body' !~ '/ar/portal[?]t=[0-9a-f-]{36}' then
      v_fail := v_fail || text 'the Arabic clicked reminder has no Arabic or no invitation link'; end if;
    if c_en->>'lang' <> 'en' or c_en->>'body' !~ '/en/portal' or c_en->>'subject' !~ '^A last reminder' then
      v_fail := v_fail || text 'the English last reminder is malformed'; end if;
    if not coalesce((s->>'ok')::boolean, false) or v_note_lang is distinct from 'ar' or v_note_status is distinct from 'suppressed' then
      v_fail := v_fail || ('the fixture reminder did not go through the outbox as a suppressed Arabic row: send=' || coalesce(s::text, 'null')
                          || ' lang=' || coalesce(v_note_lang, 'null') || ' status=' || coalesce(v_note_status, 'null'));
    end if;
    raise exception 'zz_outreach_probe_done';
  exception when others then
    if sqlerrm <> 'zz_outreach_probe_done' then v_fail := v_fail || ('the rehearsal raised: ' || sqlerrm); end if;
  end;
  select count(*) into v_left from public.leads where company_name like 'ZZ DEMO outreach %' and source = 'probe';
  if v_left <> 0 then v_fail := v_fail || (v_left || ' fixture lead(s) survived the rollback'); end if;
  insert into zz_outreach_probe values (case when cardinality(v_fail) = 0
    then 'PROBE OK: the held day is recorded and writes nothing; fixtures are never due; EN and AR reminders compose and take the outbox test path; the 24-hour clock acts, and raises a still-undecided submission to the CEO exactly once'
    else 'PROBE FAILED: ' || array_to_string(v_fail, '; ') end);
end $probe$;
select verdict from zz_outreach_probe;
