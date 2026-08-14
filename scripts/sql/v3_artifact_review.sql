-- Stage 9 — visual and media intelligence.
--
-- review_chain already separates author from reviewer for text, and it has 1,882 rows. What
-- no path did was put the RENDERED ARTIFACT in front of the reviewer: a social post was
-- approved from its caption and its brief, never from the image that would actually be
-- published. A vision model asked to check a design it has not seen will describe the design
-- it was told about — that failure has been recorded here before.
--
-- So an artifact review is anchored to bytes: the reviewer records the sha256 and the pixel
-- dimensions it actually measured. A publish gate then refuses any artifact whose bytes do
-- not match a passing review, which is also what forces a NEW review after a regeneration.

create table if not exists artifact_review (
  id             bigserial primary key,
  subject_type   text not null,               -- social_post | brand_asset | document | ad_creative
  subject_id     text not null,
  artifact_url   text not null,
  artifact_sha256 text not null,
  revision       integer not null default 1,
  bytes          integer,
  mime           text,
  width          integer,
  height         integer,
  aspect_ratio   numeric,
  author_agent   text,
  reviewer_agent text not null,
  deterministic  jsonb not null default '{}'::jsonb,   -- measured checks and their verdicts
  vision         jsonb not null default '{}'::jsonb,   -- what the reviewing model observed
  verdict        text not null check (verdict in ('pass','fail','blocked')),
  failures       text[] not null default '{}',
  created_at     timestamptz not null default now()
);
create index if not exists artifact_review_subject on artifact_review (subject_type, subject_id, created_at desc);
create unique index if not exists artifact_review_bytes on artifact_review (subject_type, subject_id, artifact_sha256, revision);
alter table artifact_review enable row level security;

-- The creator may not be the sole final reviewer of a consequential published asset.
create or replace function fn_artifact_review_valid() returns trigger
language plpgsql as $$
begin
  if new.verdict = 'pass' and new.author_agent is not null
     and new.reviewer_agent = new.author_agent then
    raise exception 'the agent that produced % % cannot be its only reviewer', new.subject_type, new.subject_id;
  end if;
  return new;
end $$;

drop trigger if exists a00_artifact_review_author_is_not_reviewer on artifact_review;
create trigger a00_artifact_review_author_is_not_reviewer
  before insert or update on artifact_review
  for each row execute function fn_artifact_review_valid();

-- The publish gate. Answers about a specific set of bytes, so a regenerated image — same
-- url, different content — is unreviewed by construction.
create or replace function fn_artifact_publish_blocked(
  p_subject_type text, p_subject_id text, p_sha256 text
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r artifact_review;
begin
  if p_sha256 is null or btrim(p_sha256) = '' then
    return jsonb_build_object('blocked', true, 'reason', 'no_artifact_digest',
      'detail', 'publishing needs the digest of the bytes that will be published');
  end if;
  select * into r from artifact_review
   where subject_type = p_subject_type and subject_id = p_subject_id
     and artifact_sha256 = p_sha256
   order by created_at desc limit 1;

  if r.id is null then
    return jsonb_build_object('blocked', true, 'reason', 'no_review_for_these_bytes',
      'detail', 'the artifact was never reviewed, or it changed after the review');
  end if;
  if r.verdict <> 'pass' then
    return jsonb_build_object('blocked', true, 'reason', 'review_failed',
      'failures', to_jsonb(r.failures), 'review_id', r.id);
  end if;
  return jsonb_build_object('blocked', false, 'review_id', r.id, 'reviewer', r.reviewer_agent,
                            'reviewed_at', r.created_at);
end $$;
revoke all on function fn_artifact_publish_blocked(text, text, text) from public;
grant execute on function fn_artifact_publish_blocked(text, text, text) to service_role;

-- Which platform constraints a given channel imposes. Data, not code, so a new channel is a
-- row: the deterministic checks read this and nothing is hard-coded in the reviewer.
create table if not exists artifact_platform_spec (
  platform     text not null,
  kind         text not null,
  min_width    integer,
  min_height   integer,
  aspect_min   numeric,
  aspect_max   numeric,
  max_bytes    integer,
  allowed_mime text[] not null default '{image/png,image/jpeg}',
  safe_zone_pct numeric not null default 0.05,
  primary key (platform, kind)
);
alter table artifact_platform_spec enable row level security;

insert into artifact_platform_spec (platform, kind, min_width, min_height, aspect_min, aspect_max, max_bytes) values
  ('instagram', 'feed',   1080, 1080, 0.79, 1.92, 8000000),
  ('instagram', 'story',  1080, 1920, 0.55, 0.58, 8000000),
  ('linkedin',  'feed',   1200,  627, 1.80, 1.95, 5000000),
  ('facebook',  'feed',   1200,  630, 1.80, 1.95, 8000000),
  ('x',         'feed',   1200,  675, 1.70, 1.85, 5000000),
  ('generic',   'image',   600,  400, 0.20, 5.00, 10000000)
on conflict (platform, kind) do update set
  min_width = excluded.min_width, min_height = excluded.min_height,
  aspect_min = excluded.aspect_min, aspect_max = excluded.aspect_max,
  max_bytes = excluded.max_bytes;
