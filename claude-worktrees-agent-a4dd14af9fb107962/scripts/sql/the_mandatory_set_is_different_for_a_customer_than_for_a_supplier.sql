-- THE MANDATORY SET IS DIFFERENT FOR A CUSTOMER THAN FOR A SUPPLIER
--
-- Founder rulings, 7 September 2026:
--   Suppliers: "name/mobile/email/trade license/company profile/terms and conditions signed copy.
--               nothing else is mandatory, the rest are extra"  ... and the mobile must be a UAE mobile.
--   Customers: "mandatory fields are different for customers. its just mobile, email and name and
--               signed terms and conditions"
--
-- So it is SIX for a supplier and FOUR for a customer. A customer is buying, not selling, and does not
-- need a trade licence or a company profile to post a request or to pay a reveal fee.
--
-- WHY THIS IS A FUNCTION AND NOT A NOTE. The estate already held a ten-item document score that nobody
-- had ruled on, and it was being read as policy. Two different mandatory sets living only in prose is
-- how a customer gets approved without signing the terms, which is the state the one real customer is
-- in right now: registered 6 Sep, email verified, mobile unverified, and signed_terms_path null.
--
-- MEASURED AT BUILD TIME, 7 Sep 2026: customers = 1 row (younis). name yes, email verified yes,
-- phone present but phone_verified false, signed terms entirely absent. So the only genuine customer
-- in the company does not meet the founder's own four.

begin;

create table if not exists public.mandatory_field_policy (
  party_kind    text        not null check (party_kind in ('supplier','customer')),
  field_key     text        not null,
  label         text        not null,
  sort          int         not null default 100,
  how_checked   text        not null,
  authority     text        not null,
  active        boolean     not null default true,
  primary key (party_kind, field_key)
);

comment on table public.mandatory_field_policy is
  'The founder-ruled mandatory set per party kind. Six for a supplier, four for a customer. Anything not listed here is extra and may never block.';

insert into public.mandatory_field_policy (party_kind, field_key, label, sort, how_checked, authority) values
  ('supplier','company_name','Company name',            10,'leads.company_name is non-empty','Founder ruling 7 Sep 2026'),
  ('supplier','mobile',      'UAE mobile number',       20,'leads.phone_e164 is a +9715 number','Founder ruling 7 Sep 2026: "we need UAE mobile number"'),
  ('supplier','email',       'Email address',           30,'leads.email is non-empty and verified','Founder ruling 7 Sep 2026'),
  ('supplier','trade_licence','Trade licence',          40,'leads.license_doc_path is non-empty','Founder ruling 7 Sep 2026'),
  ('supplier','company_profile','Company profile',      50,'leads.company_profile_doc_path is non-empty','Founder ruling 7 Sep 2026'),
  ('supplier','signed_terms','Signed terms and conditions',60,'leads.signed_terms_path is non-empty','Founder ruling 7 Sep 2026'),

  ('customer','full_name',   'Name',                    10,'customers.full_name is non-empty','Founder ruling 7 Sep 2026'),
  ('customer','mobile',      'Mobile number',           20,'customers.phone is non-empty and phone_verified','Founder ruling 7 Sep 2026'),
  ('customer','email',       'Email address',           30,'customers.email is non-empty and email_verified','Founder ruling 7 Sep 2026'),
  ('customer','signed_terms','Signed terms and conditions',40,'customers.signed_terms_path is non-empty','Founder ruling 7 Sep 2026')
on conflict (party_kind, field_key) do update set
  label = excluded.label, sort = excluded.sort,
  how_checked = excluded.how_checked, authority = excluded.authority;

commit;

-- ---------------------------------------------------------------------------------------------
-- THE CHECKS. One per party kind. Both return the same shape so a caller can treat them alike.
-- ---------------------------------------------------------------------------------------------

-- fn_supplier_mandatory_check (the supplier six) moved on 15 Sep 2026 to
-- the_mandatory_six_have_one_definition_and_the_sales_engineer_verifies.sql, where it reads the one
-- definition, public.fn_supplier_mandatory_six. Two files defining one routine means the MANIFEST decides
-- which is real; this file keeps the customer four.

create or replace function public.fn_customer_mandatory_check(p_customer_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare c record; miss text[] := '{}'; have text[] := '{}';
begin
  select * into c from public.customers where id = p_customer_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'No such customer.');
  end if;

  if coalesce(btrim(c.full_name),'') = '' then miss := array_append(miss,'Name');
  else have := array_append(have,'Name'); end if;

  -- The founder said "mobile" for a customer without naming a country, so this checks that a number
  -- exists and has been verified, rather than imposing a UAE prefix he did not ask for. A buyer may
  -- reasonably be abroad; a supplier holding a UAE trade licence may not.
  if coalesce(btrim(c.phone),'') = '' then miss := array_append(miss,'Mobile number');
  elsif not coalesce(c.phone_verified,false) then miss := array_append(miss,'Mobile number (not yet verified)');
  else have := array_append(have,'Mobile number'); end if;

  if coalesce(btrim(c.email),'') = '' then miss := array_append(miss,'Email address');
  elsif not coalesce(c.email_verified,false) then miss := array_append(miss,'Email address (not yet verified)');
  else have := array_append(have,'Email address'); end if;

  if coalesce(btrim(c.signed_terms_path),'') = '' and c.tos_accepted_at is null
  then miss := array_append(miss,'Signed terms and conditions');
  else have := array_append(have,'Signed terms and conditions'); end if;

  return jsonb_build_object(
    'ok', true, 'party_kind','customer', 'id', p_customer_id::text, 'name', c.full_name,
    'complete', coalesce(array_length(miss,1),0) = 0,
    'have', to_jsonb(have), 'missing', to_jsonb(miss),
    'missing_count', coalesce(array_length(miss,1),0),
    'mandatory_total', 4
  );
end;
$$;

revoke execute on function public.fn_customer_mandatory_check(uuid) from public;

comment on function public.fn_customer_mandatory_check(uuid) is
  'The founder four for a customer: name, mobile, email, signed terms. No licence, no profile.';

-- ---------------------------------------------------------------------------------------------
-- THE WHATSAPP AGENT LEARNS THE DIFFERENCE
--   Its registration answer was giving the supplier six to everyone, including buyers.
-- ---------------------------------------------------------------------------------------------

update public.wa_reply_intent set
  label = 'How to register as a supplier',
  match_patterns = array['register as a supplier','supplier registration','become a supplier','sell on','i am a supplier','quote for you'],
  answer_template = 'To register as a supplier we need six things: your company name, a UAE mobile '
                 || 'number, an email address, your trade licence, your company profile, and a signed '
                 || 'copy of our terms. Registration is free for the first {{free_count}} suppliers. '
                 || 'Reply SUPPLIER and I will send you the link.',
  resolver_note = 'The founder six, 7 Sep 2026. Never the ten from v_supplier_doc_score.'
 where intent_key = 'how_to_register';

insert into public.wa_reply_intent (intent_key, label, sort, match_patterns, requires_identity, requires_number, scope, answer_template, resolver_note) values
('how_to_register_customer', 'How to register as a buyer', 45,
 array['register as a buyer','i want to buy','post a request','need a quote','looking for supplier','i am a customer','buyer registration'],
 false, false, 'company',
 'To post a request as a buyer we need four things: your name, a mobile number, an email address, and '
 || 'a signed copy of our terms. There is no charge to post a request or to receive quotes. You only '
 || 'pay {{reveal_rate}} of the quoted value if you choose to reveal and contact a supplier. Reply '
 || 'BUYER and I will send you the link.',
 'The founder four, 7 Sep 2026. A buyer needs no trade licence and no company profile.'),

('how_to_register_generic', 'Register, side not yet stated', 55,
 array['register','sign up','signup','join','how do i become','apply'],
 false, false, 'company',
 'Are you looking to sell or to buy? Reply SUPPLIER if you want to send quotes, or BUYER if you want '
 || 'to receive them. The two need different things from you, so I would rather ask than send you the '
 || 'wrong list.',
 'Disambiguates before answering, because the two mandatory sets differ.')

on conflict (intent_key) do update set
  label = excluded.label, sort = excluded.sort, match_patterns = excluded.match_patterns,
  answer_template = excluded.answer_template, resolver_note = excluded.resolver_note;

-- ORDER MATTERS AND IT IS THE WHOLE POINT. The two specific intents are tried first; the generic
-- 'register' catch-all is tried last, so a bare 'i want to register' asks which side you are on
-- rather than guessing and sending a buyer the supplier's list.
update public.wa_reply_intent set sort = 46 where intent_key = 'how_to_register';
update public.wa_reply_intent set sort = 47 where intent_key = 'how_to_register_customer';
update public.wa_reply_intent set sort = 48 where intent_key = 'how_to_register_generic';
