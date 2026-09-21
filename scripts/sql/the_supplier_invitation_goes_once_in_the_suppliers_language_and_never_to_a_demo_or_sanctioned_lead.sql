-- THE SUPPLIER INVITATION GOES ONCE, IN THE SUPPLIER'S LANGUAGE, AND NEVER TO A DEMO OR SANCTIONED LEAD
-- (21 Sep 2026, customer_support seat — it owns every outbound send — under ceo oversight).
--
-- The founder launches the supplier registration campaign in about two days. Before it does, the
-- pipeline was walked end to end against production (htdblwldjkcgjvmqkbeh), read-only.
--
-- MEASURED, 21 Sep 2026:
--   leads 22,272; with an email 19,904; never invited, unclaimed, not self-registered 19,725;
--   of those: fn_email_sendable refuses 1,797, permanently closed 2, banned 0, is_demo 0,
--   sanctions_ban 0, open screening hits 0  ->  17,926 distinct addresses eligible today.
--   leads.locale = 'ar' among them: 0.  leads with an upper-case letter in email: 47.
--   invite_status: 161 'sent', 10 'bounced'; notifications of type supplier_invite: 0 rows.
--   (171 leads say they were invited and there is no delivery record of any of them. That is the
--   "status column is not a delivery record" lesson again; they are excluded from this campaign by
--   invite_status and are NOT re-invited here.)
--
-- WHAT WAS WRONG, each measured on the live definitions:
--   1. NO DEMO EXCLUSION IN THE RECIPIENT SET. enqueue_supplier_invites' `cand` CTE reads neither
--      leads.is_demo nor a ZZ DEMO name nor a reserved test domain. Only the downstream capture
--      trigger stood between a fixture lead and a queued invitation.
--   2. NO SANCTIONS-SCREENING EXCLUSION. `cand` excludes `banned`, but a lead with an OPEN
--      supplier_screening_hit (screened, matched, undecided) was eligible. a02 on notifications only
--      refuses a CONFIRMED ban, so an undecided match would have been invited.
--   3. "NEVER TWICE" WAS A STATUS COLUMN. The only dedupe was `invite_status is null`. Nothing in the
--      outbox itself refused a second supplier_invite to the same address; resetting one column
--      would re-invite. Now a unique index on the outbox refuses it.
--   4. ENGLISH ONLY, AND AN ARABIC-LOCALE LEAD WOULD HAVE RECEIVED NONSENSE. There is no Arabic
--      invitation. a04_notifications_speak_the_recipients_language sets lang from leads.locale and,
--      finding English copy for an 'ar' recipient, REPLACES subject and body with the generic
--      notification_copy '*' row ("You have a new update... sign in to your portal") — no link, no
--      invitation. Zero leads carry 'ar' today, so it has not happened; the first one would.
--   5. NO DRY RUN. There was no way to see exactly who would receive what before the switch opens.
--   6. WEEKENDS. The batch is queued daily at 09:00 UTC (13:00 Gulf) including Saturday and Sunday,
--      the UAE weekend; a cold B2B invitation lands under Monday's pile.
--
-- WHAT THIS CHANGES:
--   * fn_supplier_invite_eligible(leads)    — the ONE eligibility rule; the pool count and the
--                                             recipient set both call it, so they cannot diverge.
--   * fn_supplier_invite_candidates(limit)  — the ONE recipient selection, returning the exact
--                                             subject/body/lang each lead would get. It is the
--                                             dry run: select * from fn_supplier_invite_candidates(50).
--   * enqueue_supplier_invites              — inserts from the candidates; holds on the UAE weekend.
--   * notifications_supplier_invite_once_uidx — one supplier_invite per address, ever.
--   * a07_notifications_supplier_invite_is_whole — refuses an invitation to an ineligible lead, one
--                                             with no portal link, or one whose language and body
--                                             disagree (runs after a04 so it sees the final row).
--   * app_secrets invite_subject_ar / invite_body_ar — the Arabic invitation (inserted, never
--                                             overwritten).
--   * fn_supplier_invite_test_send(lang)    — "send one to the test path": writes one invitation
--                                             to a fresh @example.invalid address, which the
--                                             zzzz_notifications_demo_capture trigger records as
--                                             'suppressed' and never hands to Resend.
--
-- WHAT THIS DOES NOT CHANGE: invite_enabled and supplier_outreach_golive stay false (the founder's
-- go), invite_daily_cap and the bounce brake are untouched, the 171 historical rows are untouched.
-- The unsubscribe link, suppression case-folding and the plain-text part live in send_outbox and
-- resend_webhook (same PR). Nothing here sends anything.

-- ── 1. the Arabic invitation ─────────────────────────────────────────────────────────────────────
-- Written as original Gulf business correspondence, not translated from the English (founder
-- instruction 586, 21 Sep 2026: "it feels like a pure translation only. it should feel much more
-- professional"). Formal UAE conventions: السادة/ ... المحترمين, تحية طيبة وبعد, procurement terms
-- (طلبات عروض الأسعار، ترسية، عروض مغلقة), and the formal close وتفضلوا بقبول فائق الاحترام والتقدير.
-- The same commercial facts as the English, and no claim the English does not make. The brand stays
-- "QuotesDone": the DET licence registers the trade name in Latin script only (QuotesDone
-- Technologies), so there is no registered Arabic name to print.
-- The signature is the frame's, not the body's: email_signature_name_ar / 'المؤسس' (send_outbox).
insert into public.app_secrets (key, value) values ('invite_subject_ar',
  'دعوة للانضمام إلى الموردين المؤسِّسين في QuotesDone — دون أي عمولة')
on conflict (key) do nothing;

insert into public.app_secrets (key, value) values ('email_signature_name_ar', 'أحمد الزين')
on conflict (key) do nothing;

insert into public.app_secrets (key, value) values ('invite_body_ar', $ar$السادة/ {{company}} المحترمين،

تحية طيبة وبعد،

يسرّنا أن ندعوكم للانضمام بصفة «مورِّد مؤسِّس» إلى QuotesDone، المنصة الإماراتية لطلبات عروض الأسعار التي تربط العملاء بالموردين المؤهَّلين في مختلف المشاريع والخدمات.

آلية العمل واضحة: يطرح العميل طلبه مرفقًا بالمواصفات أو المخططات أو الصور، فنحيله حصرًا إلى الموردين القادرين على تسعيره فعليًا، لتصلكم طلبات تتوافق مع نشاطكم دون سواها.

وتتضمّن مزايا التسجيل المبكر ما يلي:

- لا عمولة على الإطلاق، وتحتفظون بكامل قيمة الأعمال التي تُرسى عليكم.
- التسجيل مجاني لجميع الموردين حتى 31 يوليو 2027، ويُطبَّق بعدها اشتراك سنوي قدره 1,000 درهم إماراتي اعتبارًا من 1 أغسطس 2027، ويُعفى منه نهائيًا أول 1,000 مورِّد يسجّلون.
- الأولوية في استلام طلبات عروض الأسعار فور بدء استقبال طلبات العملاء.
- عروض أسعار مغلقة، يقارنها العميل على أساس الجدارة، ولا يطّلع أي مورِّد على أسعار غيره.

وأيًّا كان نشاطكم أو منتجكم، فمتى أمكن تسعيره من مواصفات أو مخططات أو صور، فإن مكانه على المنصة.

للتسجيل، يُرجى الدخول إلى بوابة الموردين الخاصة بكم عبر الرابط التالي واستكمال الملف التعريفي للشركة:

{{link}}

ونوصي بتجهيز نسخة من الرخصة التجارية الإماراتية سارية المفعول، إذ تُمنح الأولوية في الطلبات للموردين الموثَّقين، ويُنجَز التوثيق سريعًا بعد رفع الرخصة.

للعلم، لن نطلب منكم بأي حال سداد مبالغ أو الإفصاح عن كلمات المرور عبر البريد الإلكتروني. وفي حال عدم رغبتكم في تلقي مراسلات مماثلة، يكفي الرد على هذه الرسالة لإزالة عنوانكم من القائمة.

نتطلع إلى انضمامكم وإلى تعاون مثمر.

وتفضلوا بقبول فائق الاحترام والتقدير،$ar$)
on conflict (key) do nothing;

-- ── 2. the one eligibility rule ──────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_invite_eligible(p public.leads)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(btrim(p.email), '') <> ''
     and p.invite_status is null
     and coalesce(p.source, '') <> 'self_registered'
     and coalesce(p.claimed, false) = false
     and coalesce(p.banned, false) = false
     and coalesce(p.permanently_closed, false) = false
     -- a fixture is never a supplier: the flag, the naming convention, and the reserved domains
     and coalesce(p.is_demo, false) = false
     and coalesce(p.company_name, '') !~* '^\s*zz\s*demo'
     and not public.fn_is_demo_email(p.email)
     -- screened and matched but undecided is not cleared; a confirmed ban is total
     and not exists (select 1 from public.sanctions_ban b where b.lead_id = p.id)
     and not exists (select 1 from public.supplier_screening_hit h
                      where h.lead_id = p.id and h.status in ('open', 'confirmed'))
     -- never twice, read from the outbox rather than from a status column
     and not exists (select 1 from public.notifications n
                      where n.type = 'supplier_invite' and lower(btrim(n.to_email)) = lower(btrim(p.email)))
     and coalesce((public.fn_email_sendable(p.email)->>'ok')::boolean, false)
$fn$;
revoke execute on function public.fn_supplier_invite_eligible(public.leads) from public, anon, authenticated;

-- ── 3. the one recipient selection, which is also the dry run ────────────────────────────────────
create or replace function public.fn_supplier_invite_candidates(p_limit integer)
returns table (lead_id bigint, to_email text, company_name text, lang text, subject text, body text)
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_site text; v_target int;
  v_subj text; v_body text; v_subj_ar text; v_body_ar text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');
  select value into v_subj    from app_secrets where key = 'invite_subject';
  select value into v_body    from app_secrets where key = 'invite_body';
  select value into v_subj_ar from app_secrets where key = 'invite_subject_ar';
  select value into v_body_ar from app_secrets where key = 'invite_body_ar';
  -- A template without the link placeholder is the 62-invitations-with-no-way-in failure. Refuse.
  if coalesce(v_body, '') not like '%{{link}}%' then
    raise exception 'app_secrets.invite_body has no {{link}} placeholder: an invitation with no way in is refused';
  end if;
  v_target := coalesce((select nullif(value,'')::int from app_secrets where key='invite_target_per_category'),
                       (select nullif(value,'')::int from app_secrets where key='invite_target_per_trade'), 10);

  -- MATERIALIZED, 4 Aug 2026, and it is load-bearing (see enqueue_supplier_invites' history): both
  -- CTEs are read from a correlated subquery and would otherwise be recomputed per candidate.
  return query
  with activated as materialized (
    select ls.domain_slug, count(distinct l.id) ct
    from leads l join lead_subcategory ls on ls.lead_id = l.id
    where coalesce(l.claimed,false) = true
    group by ls.domain_slug
  ),
  under as materialized (
    select d.slug as domain_slug, coalesce(a.ct,0) as have
    from catalog_domains d left join activated a on a.domain_slug = d.slug
    where coalesce(a.ct,0) < v_target
  ),
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.claim_token, l.email_domain, l.email_verified,
           -- Arabic only where the lead's own locale says so AND the Arabic copy exists; otherwise
           -- English, which is also what a04 assumes for an unregistered recipient.
           case when lower(coalesce(l.locale, '')) like 'ar%' and coalesce(v_body_ar, '') like '%{{link}}%'
                     and coalesce(v_subj_ar, '') <> '' then 'ar' else 'en' end as lang
    from leads l
    where public.fn_supplier_invite_eligible(l)
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.claim_token, c.email_domain, c.lang,
      coalesce((select u.domain_slug from lead_subcategory ls join under u on u.domain_slug = ls.domain_slug
                 where ls.lead_id = c.id order by u.have asc, ls.score desc limit 1), '~none') as pdomain,
      case when c.email_verified in ('verified','true') then 0 else 1 end as unverified_rank,
      case when split_part(lower(c.email),'@',1) in
             ('info','sales','admin','contact','enquiry','enquiries','inquiry','office','mail',
              'support','hello','marketing','general','accounts','reception','careers','hr')
           then 1 else 0 end as role_rank
    from cand c
  ),
  elig as (
    select r.id, r.email, r.company_name, r.claim_token, r.lang from (
      select p.*,
        case when p.pdomain='~none' then 1 else 0 end as is_none,
        row_number() over (partition by p.pdomain order by p.unverified_rank, p.role_rank, p.id) as rk,
        row_number() over (partition by coalesce(p.email_domain, split_part(p.email,'@',2)) order by p.unverified_rank, p.role_rank, p.id) as domain_rk
      from prio p
    ) r
    where r.domain_rk <= 5
    order by r.is_none, r.rk, r.unverified_rank, r.role_rank, r.pdomain
    limit greatest(coalesce(p_limit, 0), 0)
  )
  select e.id, btrim(e.email), e.company_name, e.lang,
         case when e.lang = 'ar' then v_subj_ar else v_subj end,
         replace(
           replace(case when e.lang = 'ar'
                        then case when coalesce(btrim(e.company_name), '') = ''
                                  then replace(v_body_ar, 'السادة/ {{company}} المحترمين،', 'السادة الكرام،')
                                  else v_body_ar end
                        else v_body end,
                   '{{company}}', coalesce(nullif(btrim(e.company_name),''), case when e.lang = 'ar' then 'الكرام' else 'there' end)),
           '{{link}}', v_site || '/' || e.lang || '/portal?t=' || e.claim_token::text)
  from elig e;
end
$fn$;
revoke execute on function public.fn_supplier_invite_candidates(integer) from public, anon, authenticated;

-- ── 4. never twice, enforced by the outbox itself ────────────────────────────────────────────────
-- Measured 0 supplier_invite rows today, so this cannot fail to build on existing duplicates.
create unique index if not exists notifications_supplier_invite_once_uidx
  on public.notifications (lower(btrim(to_email)))
  where type = 'supplier_invite';

-- ── 5. an invitation is whole or it is refused ───────────────────────────────────────────────────
-- Named a07 so it fires AFTER a04 (language) has set lang and possibly rewritten the body: it
-- judges the row as it will be stored. A fixture address is let through deliberately — that is the
-- test path, and zzzz_notifications_demo_capture records it as 'suppressed' without sending.
create or replace function public.fn_notifications_supplier_invite_is_whole()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare l public.leads;
begin
  if coalesce(new.type, '') <> 'supplier_invite' then return new; end if;
  if coalesce(new.body, '') !~ '/(en|ar)/portal[?]t=[0-9a-f-]{36}' then
    raise exception 'SUPPLIER_INVITE_REFUSED: the invitation to % carries no portal link', new.to_email using errcode = 'check_violation';
  end if;
  if coalesce(new.lang, 'en') = 'ar' and coalesce(new.body, '') !~ '[؀-ۿ]' then
    raise exception 'SUPPLIER_INVITE_REFUSED: an Arabic invitation to % has no Arabic in it', new.to_email using errcode = 'check_violation';
  end if;
  if public.fn_is_demo_email(new.to_email) then return new; end if;   -- the test path
  if new.lead_id is null then
    raise exception 'SUPPLIER_INVITE_REFUSED: an invitation to % names no lead', new.to_email using errcode = 'check_violation';
  end if;
  select * into l from public.leads where id = new.lead_id;
  if not found or lower(btrim(coalesce(l.email, ''))) <> lower(btrim(coalesce(new.to_email, '')))
     or not public.fn_supplier_invite_eligible(l) then
    raise exception 'SUPPLIER_INVITE_REFUSED: lead #% is not eligible for an invitation (demo, banned, screened, closed, already invited, unsendable, or the address is not the lead''s)', new.lead_id
      using errcode = 'check_violation';
  end if;
  return new;
end
$fn$;
revoke execute on function public.fn_notifications_supplier_invite_is_whole() from public, anon, authenticated;

drop trigger if exists a07_notifications_supplier_invite_is_whole on public.notifications;
create trigger a07_notifications_supplier_invite_is_whole
  before insert on public.notifications
  for each row execute function public.fn_notifications_supplier_invite_is_whole();

-- ── 6. the composer ──────────────────────────────────────────────────────────────────────────────
-- Transformed from the LIVE definition read on 21 Sep 2026. Unchanged: the calendar hold (still
-- before the invite_schedule upsert), the two gates, the bounce brake, the per-day cap. Changed:
-- the UAE weekend hold, the pool count and the recipients both come from the eligibility rule
-- above, and the insert carries lang and cannot write a second invitation to one address.
create or replace function public.enqueue_supplier_invites(p_cap integer default null::integer)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_today date := (now() at time zone 'UTC')::date;
  v_planned int; v_used int; v_remaining int; v_count int;
  v_inv_recent int; v_bounced_recent int; v_rate numeric; v_max_rate numeric; v_cap int;
  v_pause boolean := false; v_why text; v_go boolean; v_pool int;
  v_hol_name text; v_hol_action text; v_hol_end date;
begin
  select c.event_name, c.action, c.ends_on into v_hol_name, v_hol_action, v_hol_end
    from public.company_calendar c
   where c.kind = 'public_holiday'
     and v_today between c.starts_on and coalesce(c.ends_on, c.starts_on)
   order by c.starts_on limit 1;
  if v_hol_name is not null then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok',
            jsonb_build_object('queued', 0, 'calendar_paused', true, 'resumes_on', coalesce(v_hol_end, v_today) + 1),
            'Invites held: company_calendar has "' || v_hol_name || '" covering today. Its recorded action: '
            || coalesce(v_hol_action, '(none recorded)'), now(), now());
    return 0;
  end if;

  -- THE UAE WEEKEND IS SATURDAY AND SUNDAY. A cold invitation queued then waits under Monday's pile.
  -- Self-clearing like the holiday hold: nothing is switched off, Monday simply runs.
  if extract(isodow from (now() at time zone 'Asia/Dubai')) in (6, 7) then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'weekend_hold', true),
            'Invites held: it is the UAE weekend in Dubai; the next weekday batch runs as normal.', now(), now());
    return 0;
  end if;

  v_go  := (coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') = 'true')
           and public.fn_supplier_outreach_golive();
  v_cap := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), 10);
  select count(*) into v_pool from leads l where public.fn_supplier_invite_eligible(l);
  v_planned := least(coalesce(p_cap, v_cap), v_cap, v_pool);
  insert into invite_schedule(day, planned, status, note)
  values (v_today, greatest(v_planned, 0),
          case when v_go then 'approved' else 'pending' end,
          'batch of ' || greatest(v_planned, 0) || ' from a pool of ' || v_pool || ' eligible never-invited lead(s), cap ' || v_cap
          || case when v_go then '; sending open'
                  when not public.fn_supplier_outreach_golive() then '; HELD — real invitations wait for the founder''s go (app_secrets.supplier_outreach_golive is false)'
                  else '; HELD — real invitations wait for the founder''s go (app_secrets.invite_enabled)' end)
    on conflict (day) do update
      set planned = excluded.planned, status = excluded.status, note = excluded.note;

  if not v_go then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok',
            jsonb_build_object('queued', 0, 'planned', greatest(v_planned, 0), 'pool', v_pool, 'cap', v_cap, 'held', true),
            'Invites planned and HELD: ' || greatest(v_planned, 0) || ' of a pool of ' || v_pool
            || ' would be queued at cap ' || v_cap || '; '
            || case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive' else 'invite_enabled' end
            || ' is false, so nothing was written to the outbox.', now(), now());
    return 0;
  end if;
  if v_planned <= 0 then return 0; end if;

  v_max_rate := coalesce((select nullif(value,'')::numeric from app_secrets where key='invite_max_bounce_rate'), 0.08);
  select count(*) into v_inv_recent from leads where invited_at > now() - interval '3 days';
  select count(*) into v_bounced_recent from leads where invite_status='bounced' and invited_at > now() - interval '3 days';
  v_rate := round(v_bounced_recent::numeric / greatest(v_inv_recent,1), 3);

  if v_inv_recent >= 15 and v_rate > v_max_rate then
    v_pause := true;
    v_why := 'bounce rate '||(v_rate*100)||'% over 3 days ('||v_bounced_recent||'/'||v_inv_recent||') exceeds the '||(v_max_rate*100)||'% limit';
  end if;
  if not v_pause and v_bounced_recent >= greatest(5, ceil(v_inv_recent * v_max_rate)::int) then
    v_pause := true;
    v_why := v_bounced_recent||' hard bounces in 3 days against '||v_inv_recent||' sent. Regardless of rate, that is a list-quality problem';
  end if;

  if v_pause then
    update app_secrets set value='false' where key='invite_enabled';
    update invite_schedule set status = 'pending', note = coalesce(note,'') || '; auto-paused: ' || v_why where day = v_today;
    if not exists (select 1 from founder_alerts where event='invite_paused_bounce' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values('crit','invite_paused_bounce','Supplier invites AUTO-PAUSED: '||v_why||'. Clean the list before resuming.','system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('invite_paused_bounce', coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com'),'admin','email','Supplier invites paused - deliverability risk','Invites were auto-paused: '||v_why||'. Validate the list, then re-enable.','queued');
    end if;
    return 0;
  end if;

  -- test-path rows (fixture addresses) are not invitations and must not spend the day's cap:
  -- measured in the rolled-back rehearsal, two test sends plus one real row cut a batch of 5 to 2.
  select count(*) into v_used from notifications where type='supplier_invite' and (created_at at time zone 'UTC')::date = v_today
     and not public.fn_is_demo_email(to_email);
  v_remaining := greatest(0, v_planned - v_used);
  if v_remaining <= 0 then return 0; end if;

  with ins as (
    insert into notifications(type, to_email, to_role, lead_id, subject, body, lang, status, created_at)
    select 'supplier_invite', c.to_email, 'supplier', c.lead_id, c.subject, c.body, c.lang, 'queued', now()
      from public.fn_supplier_invite_candidates(v_remaining) c
    on conflict (lower(btrim(to_email))) where type = 'supplier_invite' do nothing
    returning lead_id
  )
  update leads set invite_status='queued', invited_at=now()
  where invite_status is null and id in (select lead_id from ins);
  get diagnostics v_count = row_count;
  update invite_schedule set sent = sent + v_count where day = v_today;
  insert into agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('supplier_invites', 'ok',
          jsonb_build_object('queued', v_count, 'planned', v_planned, 'pool', v_pool, 'cap', v_cap, 'held', false),
          'Invites: ' || v_count || ' queued of ' || v_planned || ' planned (pool ' || v_pool || ', cap ' || v_cap || ').', now(), now());
  return v_count;
end;
$function$;
revoke execute on function public.enqueue_supplier_invites(integer) from public, anon, authenticated;

-- ── 7. send one to the test path ─────────────────────────────────────────────────────────────────
-- Composes exactly what a real lead would get (same template, same link shape, a zero token that
-- matches no lead) and writes it to a fresh @example.invalid address. zzzz_notifications_demo_capture
-- marks it 'suppressed' before any dispatcher can see it, and send_outbox refuses reserved domains
-- before any provider call as a second wall. It proves the composition and the guards, NOT provider
-- delivery: that needs a real inbox and is deliberately not done here.
create or replace function public.fn_supplier_invite_test_send(p_lang text default 'en')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_lang text := case when lower(coalesce(p_lang, 'en')) = 'ar' then 'ar' else 'en' end;
  v_site text; v_subj text; v_body text; v_to text; v_id bigint; v_status text; v_err text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from app_secrets where key = 'public_site_url';
  select value into v_subj from app_secrets where key = case when v_lang = 'ar' then 'invite_subject_ar' else 'invite_subject' end;
  select value into v_body from app_secrets where key = case when v_lang = 'ar' then 'invite_body_ar' else 'invite_body' end;
  v_to := 'zz-demo-supplier-invite-' || v_lang || '-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS') || '@example.invalid';
  if not public.fn_is_demo_email(v_to) then raise exception 'test address % is not a fixture address', v_to; end if;
  insert into notifications(type, to_email, to_role, subject, body, lang, status)
  values ('supplier_invite', v_to, 'supplier', v_subj,
          replace(replace(v_body, '{{company}}', 'ZZ DEMO Supplier'),
                  '{{link}}', coalesce(v_site, 'https://quotesdone.com') || '/' || v_lang || '/portal?t=00000000-0000-0000-0000-000000000000'),
          v_lang, 'queued')
  returning id, status, last_error into v_id, v_status, v_err;
  return jsonb_build_object('id', v_id, 'to', v_to, 'lang', v_lang, 'status', v_status, 'captured_note', v_err,
                            'subject', v_subj, 'never_reaches_resend', v_status = 'suppressed');
end
$fn$;
revoke execute on function public.fn_supplier_invite_test_send(text) from public, anon, authenticated;
