-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727002216   name: brand_protection_and_secops
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ 9. BRAND PROTECTION ============
create table if not exists public.brand_signal (
  id          bigserial primary key,
  signal_type text not null check (signal_type in ('fake_supplier','scam_rfq','fake_review','brand_misuse','reputation','social')),
  severity    text not null default 'medium' check (severity in ('low','medium','high','critical')),
  subject_type text not null,
  subject_id   text,
  rule_key     text,
  detail       text not null,
  evidence     jsonb default '{}'::jsonb,
  status       text not null default 'open' check (status in ('open','investigating','confirmed','dismissed','actioned')),
  detected_by  text not null default 'fn_brand_scan',
  detected_at  timestamptz not null default now()
);
create index if not exists brand_signal_open_idx on public.brand_signal (status, severity, detected_at desc);
create unique index if not exists brand_signal_dedupe_idx
  on public.brand_signal (signal_type, subject_type, coalesce(subject_id,''), coalesce(rule_key,''));

-- Deterministic scan. No model call. Rules are SQL, so they are testable and free.
create or replace function public.fn_brand_scan() returns table (rule_key text, hits integer)
language plpgsql security definer set search_path = public as $fn$
begin
  -- 1. Supplier claims to be registered but has no trade licence number.
  insert into brand_signal (signal_type, severity, subject_type, subject_id, rule_key, detail, evidence)
  select 'fake_supplier','high','lead', l.id::text, 'no_trade_licence',
         'Supplier reached registration without a trade licence number.',
         jsonb_build_object('company', l.company_name, 'status', l.registration_status)
  from leads l
  where l.registration_submitted_at is not null
    and coalesce(nullif(trim(l.trade_license_no),''), null) is null
  on conflict do nothing;

  -- 2. Licence expired but still approved to receive RFQs.
  insert into brand_signal (signal_type, severity, subject_type, subject_id, rule_key, detail, evidence)
  select 'fake_supplier','critical','lead', l.id::text, 'licence_expired_but_approved',
         'Approved supplier holds an expired trade licence.',
         jsonb_build_object('company', l.company_name, 'expiry', l.license_expiry)
  from leads l
  where l.approval_status = 'approved' and l.license_expiry is not null and l.license_expiry < current_date
  on conflict do nothing;

  -- 3. Two different suppliers claiming the same trade licence number.
  insert into brand_signal (signal_type, severity, subject_type, subject_id, rule_key, detail, evidence)
  select 'fake_supplier','critical','trade_license', t.lic, 'duplicate_trade_licence',
         'The same trade licence number is claimed by more than one supplier record.',
         jsonb_build_object('licence', t.lic, 'count', t.n)
  from (
    select trim(trade_license_no) as lic, count(*) as n
    from leads where coalesce(trim(trade_license_no),'') <> ''
    group by 1 having count(*) > 1
  ) t
  on conflict do nothing;

  -- 4. Supplier name impersonating QuotesDone.
  insert into brand_signal (signal_type, severity, subject_type, subject_id, rule_key, detail, evidence)
  select 'brand_misuse','high','lead', l.id::text, 'name_impersonates_platform',
         'Supplier trading name contains the platform brand.',
         jsonb_build_object('company', l.company_name)
  from leads l
  where l.company_name ~* '(quotes ?done|quotesdone)'
  on conflict do nothing;

  -- 5. Scam RFQ: request for money, gift cards or advance payment inside a buyer brief.
  insert into brand_signal (signal_type, severity, subject_type, subject_id, rule_key, detail, evidence)
  select 'scam_rfq','high','inquiry', i.id::text, 'advance_payment_solicitation',
         'Buyer brief solicits an advance payment, gift card or wire transfer.',
         jsonb_build_object('excerpt', left(coalesce(i.raw_input,''), 240))
  from inquiries i
  where coalesce(i.raw_input,'') ~* '(gift ?card|western union|wire transfer|advance fee|upfront payment to release|crypto payment)'
  on conflict do nothing;

  -- 6. Scam RFQ: attempt to move the conversation off-platform before reveal.
  insert into brand_signal (signal_type, severity, subject_type, subject_id, rule_key, detail, evidence)
  select 'scam_rfq','medium','inquiry', i.id::text, 'off_platform_contact',
         'Buyer brief pushes contact off-platform before a paid reveal.',
         jsonb_build_object('excerpt', left(coalesce(i.raw_input,''), 240))
  from inquiries i
  where coalesce(i.raw_input,'') ~* '(whatsapp me on|call me directly on|contact me at .*@|my number is [+0-9])'
  on conflict do nothing;

  -- 7. Fake review: a supplier with a high rating and an implausible review count for its footprint.
  insert into brand_signal (signal_type, severity, subject_type, subject_id, rule_key, detail, evidence)
  select 'fake_review','medium','lead', l.id::text, 'implausible_review_profile',
         'Perfect rating with a high review count and no verifiable web presence.',
         jsonb_build_object('company', l.company_name, 'rating', l.rating, 'reviews', l.reviews)
  from leads l
  where l.rating is not null and l.rating >= 4.9 and coalesce(l.reviews,0) >= 100
    and coalesce(nullif(trim(l.website),''), null) is null
  on conflict do nothing;

  return query
    select b.rule_key, count(*)::integer
    from brand_signal b
    where b.detected_at > now() - interval '5 minutes'
    group by b.rule_key;
end; $fn$;

revoke execute on function public.fn_brand_scan() from anon, authenticated, public;

-- ============ 18. SECURITY OPERATIONS ============
create table if not exists public.secops_rule (
  rule_key    text primary key,
  category    text not null check (category in ('auth','api_abuse','suspicious','data_leak','prompt_injection','credential','audit')),
  description text not null,
  pattern     text,
  severity    text not null default 'medium' check (severity in ('low','medium','high','critical')),
  response    text not null,
  active      boolean not null default true
);

insert into public.secops_rule (rule_key, category, description, pattern, severity, response) values
('injection_ignore_instructions','prompt_injection','Untrusted content instructing the model to disregard its instructions.','ignore (all |any )?(previous|prior|above) (instructions|prompts)','critical','Quarantine the document, flag the submitting supplier, do not process the content.'),
('injection_role_claim','prompt_injection','Untrusted content claiming system, admin or developer authority.','(you are now|act as) (the )?(system|admin|administrator|developer)','critical','Quarantine and alert IT.'),
('injection_exfiltration','prompt_injection','Untrusted content asking for keys, prompts or configuration.','(reveal|print|show|output) (your )?(system prompt|api key|secret|credentials|instructions)','critical','Quarantine, alert IT, rotate nothing automatically - human decision.'),
('injection_supplier_identity','prompt_injection','Content attempting to make the platform disclose supplier identity before reveal.','(tell|give|send) (me |the customer )?(the )?(supplier|company) (name|email|phone|contact)','high','Block the response path; this attacks the core product.'),
('auth_failed_burst','auth','Repeated failed authentication from one source.',null,'medium','Rate limit the source; alert if it continues past 30 minutes.'),
('api_abuse_volume','api_abuse','A single caller exceeding a normal request profile for its role.',null,'medium','Throttle; investigate before banning.'),
('data_leak_pre_reveal','data_leak','Supplier identifying data present in a payload before a paid reveal.',null,'critical','P0. Block the response, page IT, treat as an incident not a bug.'),
('credential_in_content','credential','An API key or token pattern appearing in stored content or a log line.','(sk-[A-Za-z0-9]{16,}|Bearer [A-Za-z0-9._-]{20,})','critical','Redact, rotate the credential, record the incident.'),
('audit_gap','audit','A significant action with no corresponding audit row.',null,'high','Wire the missing audit write before the capability is used again.')
on conflict (rule_key) do update set description=excluded.description, pattern=excluded.pattern,
  severity=excluded.severity, response=excluded.response;

create or replace function public.fn_secops_test(sample text)
returns table (rule_key text, category text, severity text, response text)
language sql stable as $fn$
  select r.rule_key, r.category, r.severity, r.response
  from public.secops_rule r
  where r.active and r.pattern is not null and sample ~* r.pattern;
$fn$;

alter table public.brand_signal enable row level security;
alter table public.secops_rule enable row level security;
