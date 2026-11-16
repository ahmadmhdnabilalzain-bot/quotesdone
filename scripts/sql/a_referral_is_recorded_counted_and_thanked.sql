-- A REFERRAL IS RECORDED, COUNTED AND THANKED.
--
-- Assigned: customer_support (the customer's word and the thanks), sales_engineer (the supplier's link), ceo (the count).
-- Agent: W3_PEOPLE, 16 Nov 2026. Founder ledgers 1711-1713; the hole hunts of 16 Nov: CUSTOMER #11 ("Ahmed sent me": no
-- referral instrument anywhere, while the CEO's customer-experience objective names "referral demand") and SUPPLIER #11 ("Can I
-- invite my friend's company?": the CEO channel row supplier_referral reads "not built"; cold invitations fail Microsoft placement
-- 0/21 and the target is 1,000 suppliers).
--
-- MEASURED BEFORE WRITING (16 Nov 2026, light SELECTs on production): no column or table named like referr% or heard% exists;
-- fn_ceo_supplier_channel_measure (md5 92d3a7f0eaaae89280e2c96d0d40569e) hard-writes supplier_referral 'missing'; a registration
-- already carries the browser's first tagged visit to fn_marketing_first_touch_record (src/lib/firstTouch.ts ->
-- supplier_api create_company / claim), which keeps any tag of the shape ^[A-Za-z0-9._-]{1,100}$.
--
-- WHO DECIDES WHAT (rulings 1663/1664): what the customer SAID about how he heard of us is read by the intake model (it returns his
-- words and, when he gave one, the referrer's number or address: inquiry_intake/customer_record.ts referralOf). Code only does what
-- must be exact: a referrer is a customer only when that number or address IS a customer's verified one, one match or none.
--
-- THE PARTS
--   1. supplier_referral_code + fn_supplier_referral_link: an APPROVED supplier's one stable code and his link. The link is the
--      supplier's own (he sends it to whom he knows, which is consented mail; we send nothing cold). It carries the code as the
--      link's own tags (utm_source=referral, utm_medium=supplier, utm_content=<code>), so the first-touch path already in place
--      brings it to the registration with no new door.
--   2. supplier_referral + trigger z40 on marketing_first_touch: a registration whose first touch is a referral code records its
--      referrer once. His own code, an unknown code and an ordinary tagged visit record nothing; the touch is kept as before.
--   3. customer_referral + fn_customer_referral_record: "how did you hear about us", his own words, kept on his FIRST request
--      (no earlier inquiry), once. A referrer who is a verified customer is thanked once through fn_sales_engineer_writes (his
--      account address, the transactional path every customer notice takes), without naming the newcomer.
--   4. fn_ceo_referrals: registrations per referring supplier (and how many were approved), and the customers' words; the CEO's
--      weekly figures read it (the_ceos_weekly_figures_read_referrals_and_offers_to_pay_for_leads.sql). The CEO channel row
--      supplier_referral is measured from it (fn_ceo_supplier_channel_measure, rebuilt from the production body; only that row's
--      line changes).
--
-- prevented by: a_referral_is_recorded_counted_and_thanked_probe.sql (LOCAL Postgres 16), inquiry_intake/a_referral_is_heard_once.test.ts,
-- supplier_api/referral_link.test.ts and _shared/supplier_company_instruction.test.ts (the refer_company kind).

set local lock_timeout = '3s';

-- ── 1. the supplier's link ─────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.supplier_referral_code (
  lead_id    bigint primary key references public.leads(id),
  code       text not null unique check (code ~ '^[A-Za-z0-9._-]{6,40}$'),
  created_at timestamptz not null default now()
);
alter table public.supplier_referral_code enable row level security;
drop policy if exists supplier_referral_code_service_role_only on public.supplier_referral_code;
create policy supplier_referral_code_service_role_only on public.supplier_referral_code as permissive for all to public using (false) with check (false);
revoke all on public.supplier_referral_code from anon, authenticated;

create or replace function public.fn_supplier_referral_link(p_lead bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare l record; v_code text; v_try int := 0;
begin
  select id, company_name, approval_status, coalesce(permanently_closed, false) as closed into l from public.leads where id = p_lead;
  if not found then return jsonb_build_object('ok', false, 'code', 'no_company'); end if;
  if coalesce(l.approval_status, '') <> 'approved' or l.closed
     or exists (select 1 from public.sanctions_ban b where b.lead_id = p_lead) then
    return jsonb_build_object('ok', false, 'code', 'not_approved',
      'why', 'A referral link is given once the company is approved on QuotesDone.');
  end if;
  select code into v_code from public.supplier_referral_code where lead_id = p_lead;
  while v_code is null and v_try < 5 loop
    v_try := v_try + 1;
    insert into public.supplier_referral_code (lead_id, code)
    values (p_lead, 'qd' || substr(md5(gen_random_uuid()::text), 1, 10))
    on conflict do nothing
    returning code into v_code;
    if v_code is null then select code into v_code from public.supplier_referral_code where lead_id = p_lead; end if;
  end loop;
  if v_code is null then return jsonb_build_object('ok', false, 'code', 'unavailable'); end if;
  return jsonb_build_object('ok', true, 'referral_code', v_code,
    'url', 'https://quotesdone.com/en/supplier?utm_source=referral&utm_medium=supplier&utm_content=' || v_code,
    'registered', (select count(*) from public.supplier_referral r where r.referrer_lead_id = p_lead),
    'approved', (select count(*) from public.supplier_referral r join public.leads x on x.id = r.referred_lead_id
                  where r.referrer_lead_id = p_lead and x.approval_status = 'approved'),
    'how', 'Send this link to companies you know in your trade. When one registers through it we record that you referred it. '
        || 'Registration is free; nobody pays to rank higher or for more requests.');
end $fn$;
revoke execute on function public.fn_supplier_referral_link(bigint) from public, anon, authenticated;
grant execute on function public.fn_supplier_referral_link(bigint) to service_role;

-- ── 2. a registration through it ───────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.supplier_referral (
  id               bigint generated always as identity primary key,
  referrer_lead_id bigint not null references public.leads(id),
  referred_lead_id bigint not null unique references public.leads(id),
  code             text not null,
  recorded_at      timestamptz not null default now(),
  check (referrer_lead_id <> referred_lead_id)
);
create index if not exists supplier_referral_referrer_idx on public.supplier_referral (referrer_lead_id);
alter table public.supplier_referral enable row level security;
drop policy if exists supplier_referral_service_role_only on public.supplier_referral;
create policy supplier_referral_service_role_only on public.supplier_referral as permissive for all to public using (false) with check (false);
revoke all on public.supplier_referral from anon, authenticated;

create or replace function public.trg_marketing_first_touch_records_a_referral()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_ref bigint;
begin
  if new.utm_source is distinct from 'referral' or new.utm_content is null then return null; end if;
  select c.lead_id into v_ref from public.supplier_referral_code c where c.code = new.utm_content;
  if v_ref is null or v_ref = new.lead_id then return null; end if;
  insert into public.supplier_referral (referrer_lead_id, referred_lead_id, code)
  values (v_ref, new.lead_id, new.utm_content)
  on conflict (referred_lead_id) do nothing;
  return null;
end $fn$;
revoke execute on function public.trg_marketing_first_touch_records_a_referral() from public, anon, authenticated;
drop trigger if exists z40_marketing_first_touch_records_a_referral on public.marketing_first_touch;
create trigger z40_marketing_first_touch_records_a_referral after insert on public.marketing_first_touch
  for each row execute function public.trg_marketing_first_touch_records_a_referral();

-- ── 3. the customer's word ─────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.customer_referral (
  customer_id          uuid primary key references public.customers(id),
  words                text not null,
  referrer_contact     text,
  referrer_customer_id uuid references public.customers(id),
  source               text,
  thanked_at           timestamptz,
  thanks_handoff       bigint,
  recorded_at          timestamptz not null default now(),
  check (referrer_customer_id is distinct from customer_id)
);
create index if not exists customer_referral_referrer_idx on public.customer_referral (referrer_customer_id) where referrer_customer_id is not null;
alter table public.customer_referral enable row level security;
drop policy if exists customer_referral_service_role_only on public.customer_referral;
create policy customer_referral_service_role_only on public.customer_referral as permissive for all to public using (false) with check (false);
revoke all on public.customer_referral from anon, authenticated;

create or replace function public.fn_customer_referral_record(p_customer uuid, p_words text, p_contact text default null, p_source text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_words text := nullif(left(btrim(coalesce(p_words, '')), 500), ''); v_contact text := nullif(left(btrim(coalesce(p_contact, '')), 120), '');
        v_tail text; v_ref uuid; v_n int := 0; v_h bigint; r record;
begin
  if p_customer is null or v_words is null then return jsonb_build_object('ok', false, 'recorded', false, 'code', 'nothing_said'); end if;
  if not exists (select 1 from public.customers where id = p_customer) then return jsonb_build_object('ok', false, 'recorded', false, 'code', 'no_customer'); end if;
  if exists (select 1 from public.customer_referral where customer_id = p_customer) then
    return jsonb_build_object('ok', true, 'recorded', false, 'code', 'already_recorded');
  end if;
  -- HIS FIRST REQUEST ONLY: a customer with an earlier request did not just hear of us
  if exists (select 1 from public.inquiries i where i.customer_id = p_customer and i.created_at < now() - interval '10 minutes') then
    return jsonb_build_object('ok', true, 'recorded', false, 'code', 'not_first_request');
  end if;
  -- THE REFERRER IS A CUSTOMER ONLY ON AN EXACT FACT: his verified address, or his verified number (last nine digits and, when
  -- both name one, the same country). One match or none; never the newcomer himself.
  if v_contact is not null and position('@' in v_contact) > 0 then
    for r in select c.id from public.customers c where lower(c.email) = lower(v_contact) and coalesce(c.email_verified, false) and c.id <> p_customer loop
      v_n := v_n + 1; v_ref := r.id;
    end loop;
  elsif v_contact is not null then
    v_tail := right(regexp_replace(v_contact, '[^0-9]', '', 'g'), 9);
    if length(v_tail) = 9 then
      for r in select c.id from public.customers c
                where coalesce(c.phone_verified, false) and c.id <> p_customer
                  and right(regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g'), 9) = v_tail
                  and coalesce(public.fn_phone_prefix(c.phone) = public.fn_phone_prefix(v_contact), true) loop
        v_n := v_n + 1; v_ref := r.id;
      end loop;
    end if;
  end if;
  if v_n <> 1 then v_ref := null; end if;

  insert into public.customer_referral (customer_id, words, referrer_contact, referrer_customer_id, source)
  values (p_customer, v_words, v_contact, v_ref, left(p_source, 120))
  on conflict (customer_id) do nothing;
  if not found then return jsonb_build_object('ok', true, 'recorded', false, 'code', 'already_recorded'); end if;

  -- THANKED ONCE, never naming the newcomer (he told us, not the referrer)
  if v_ref is not null then
    v_h := public.fn_sales_engineer_writes('customer_referral_thanks', 'customer', (select email from public.customers where id = v_ref),
      null, v_ref, null, null,
      'Thank you for recommending QuotesDone',
      'Someone you recommended has just come to QuotesDone and named you. Thank you for passing our name on: it is the best '
      || 'thing a customer can do for us.',
      'شكرًا لتوصيتك بـ QuotesDone',
      'أحد من نصحتهم بنا جاء للتو إلى QuotesDone وذكر اسمك. شكرًا لأنك ذكرت اسمنا، فهذا أفضل ما يمكن أن يقدّمه لنا عميل.',
      '{}'::text[], 'customer_referral_thanks:' || p_customer);
    update public.customer_referral set thanked_at = now(), thanks_handoff = v_h where customer_id = p_customer;
  end if;
  return jsonb_build_object('ok', true, 'recorded', true, 'referrer_is_customer', v_ref is not null, 'thanked', v_ref is not null);
end $fn$;
revoke execute on function public.fn_customer_referral_record(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_customer_referral_record(uuid, text, text, text) to service_role;

-- ── 4. the CEO's count ─────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_referrals(p_days integer default 30)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  with w as (select now() - make_interval(days => greatest(1, coalesce(p_days, 30))) as since),
  s as (select r.*, a.company_name as referrer, b.approval_status as referred_status
          from public.supplier_referral r join public.leads a on a.id = r.referrer_lead_id join public.leads b on b.id = r.referred_lead_id, w
         where r.recorded_at > w.since),
  c as (select x.* from public.customer_referral x, w where x.recorded_at > w.since)
  select jsonb_build_object(
    'days', greatest(1, coalesce(p_days, 30)),
    'suppliers', jsonb_build_object(
      'links_issued', (select count(*) from public.supplier_referral_code),
      'registered_through_a_link', (select count(*) from s),
      'approved_of_those', (select count(*) from s where referred_status = 'approved'),
      'by_referrer', coalesce((select jsonb_agg(jsonb_build_object('supplier', referrer, 'registered', n, 'approved', a) order by n desc, referrer)
                                 from (select referrer, count(*) n, count(*) filter (where referred_status = 'approved') a from s group by referrer) g), '[]'::jsonb)),
    'customers', jsonb_build_object(
      'said_how_they_heard', (select count(*) from c),
      'named_a_customer', (select count(*) from c where referrer_customer_id is not null),
      'thanked', (select count(*) from c where thanked_at is not null),
      'their_words', coalesce((select jsonb_agg(left(words, 200) order by recorded_at desc) from (select * from c order by recorded_at desc limit 20) z), '[]'::jsonb)),
    'note', 'A supplier referral is a registration whose first visit came through another supplier''s own link; a customer''s words are what he told the intake about how he heard of us.');
$fn$;
revoke execute on function public.fn_ceo_referrals(integer) from public, anon, authenticated;
grant execute on function public.fn_ceo_referrals(integer) to service_role;

-- The channel row is measured, not written as "not built": fn_ceo_supplier_channel_measure from the production body
-- (md5 92d3a7f0eaaae89280e2c96d0d40569e, read 16 Nov 2026); only the supplier_referral line changes.
CREATE OR REPLACE FUNCTION public.fn_ceo_supplier_channel_measure()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_secret jsonb := (select jsonb_object_agg(key, value) from public.app_secrets
                      where key in ('invite_enabled', 'invite_m365_enabled', 'invite_m365_mailbox', 'wa_supplier_invite_golive'));
  v_open text[] := public.fn_invite_placement_open_providers((now() at time zone 'Asia/Dubai')::date);
  v_sent7 int; v_optins int; v_tmpl int; v_q public.wa_sender_quality_reading; v_brake boolean; v_posts int; v_wa_why text[] := '{}';
  v_links int; v_ref30 int;
begin
  select count(*) into v_sent7 from public.notifications where type = 'supplier_invite' and status = 'sent' and sent_at > now() - interval '7 days';
  select count(*) into v_optins from public.supplier_whatsapp_optin o join public.leads l on l.id = o.lead_id where not coalesce(l.is_demo, false);
  select count(*) into v_tmpl from public.messaging_template where template_key = 'supplier_invite' and channel = 'whatsapp' and status = 'approved';
  select * into v_q from public.wa_sender_quality_reading order by read_at desc, id desc limit 1;
  v_brake := exists (select 1 from public.it_watch_finding f where f.detector_key = 'deliverability:supplier_invite_wa' and f.status = 'open');
  select count(*) into v_posts from public.marketing_post where status = 'published' and created_at > now() - interval '30 days';
  select count(*) into v_links from public.supplier_referral_code;
  select count(*) into v_ref30 from public.supplier_referral where recorded_at > now() - interval '30 days';

  update public.ceo_supplier_channel set measured_at = now(),
    state = case when v_secret->>'invite_enabled' = 'true' and cardinality(v_open) > 0 and v_sent7 > 0 then 'on' else 'paused' end,
    state_why = format('invite_enabled %s; placement open for %s; %s sent in 7 days from %s', v_secret->>'invite_enabled', coalesce(array_to_string(v_open, ', '), 'none'), v_sent7, v_secret->>'invite_m365_mailbox'),
    measured = jsonb_build_object('open_classes', to_jsonb(v_open), 'sent_7d', v_sent7)
   where channel = 'email_supplier_mailbox';

  if v_optins = 0 then v_wa_why := v_wa_why || 'no opt-in on record'::text; end if;
  if v_tmpl = 0 then v_wa_why := v_wa_why || 'template supplier_invite is not approved'::text; end if;
  if v_q.id is null or v_q.read_at < now() - interval '26 hours' then v_wa_why := v_wa_why || 'no sender reading in 26 hours'::text;
  elsif not v_q.ok then v_wa_why := v_wa_why || ('sender reads ' || coalesce(v_q.rating, 'unknown') || ' / ' || v_q.status); end if;
  if v_brake then v_wa_why := v_wa_why || 'the brake finding is open'::text; end if;
  if v_secret->>'invite_enabled' is distinct from 'true' then v_wa_why := v_wa_why || 'the email channel is paused, and WhatsApp never runs ahead of it'::text; end if;
  update public.ceo_supplier_channel set measured_at = now(),
    state = case when cardinality(v_wa_why) > 0 then 'blocked' when v_secret->>'wa_supplier_invite_golive' = 'true' then 'on' else 'ready' end,
    state_why = coalesce(nullif(array_to_string(v_wa_why, '; '), ''), 'every condition is measured true'),
    measured = jsonb_build_object('opt_ins', v_optins, 'template_approved', v_tmpl > 0, 'reading', v_q.rating, 'read_at', v_q.read_at, 'brake', v_brake)
   where channel = 'whatsapp_opt_in';

  update public.ceo_supplier_channel set measured_at = now(), state = 'missing',
    state_why = 'no send path: the lane reads one mailbox setting', measured = jsonb_build_object('mailboxes_in_the_lane', 1) where channel = 'email_extra_mailboxes';
  update public.ceo_supplier_channel set measured_at = now(), state = 'missing',
    state_why = 'no outbound call routine exists', measured = '{}'::jsonb where channel = 'phone_outbound';
  -- W3_PEOPLE 16 Nov 2026 (SUPPLIER #11): built (a_referral_is_recorded_counted_and_thanked.sql), so measured
  update public.ceo_supplier_channel set measured_at = now(), state = case when v_links > 0 then 'on' else 'ready' end,
    state_why = format('%s approved suppliers hold a referral link; %s companies registered through one in 30 days', v_links, v_ref30),
    measured = jsonb_build_object('links_issued', v_links, 'registered_30d', v_ref30) where channel = 'supplier_referral';
  update public.ceo_supplier_channel set measured_at = now(), state = case when v_posts > 0 then 'on' else 'paused' end,
    state_why = format('%s posts published in 30 days', v_posts), measured = jsonb_build_object('published_30d', v_posts) where channel = 'organic_social';
  update public.ceo_supplier_channel set measured_at = now(), state = 'missing',
    state_why = 'the target list is built; no person sends it', measured = '{}'::jsonb where channel = 'linkedin_manual';

  return (select jsonb_object_agg(channel, jsonb_build_object('state', state, 'why', state_why)) from public.ceo_supplier_channel);
end $function$
;
revoke execute on function public.fn_ceo_supplier_channel_measure() from public, anon, authenticated;
grant execute on function public.fn_ceo_supplier_channel_measure() to service_role;
