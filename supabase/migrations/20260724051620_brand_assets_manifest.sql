-- ============================================================================
-- BRAND ASSETS — official brand kit files hosted in the public social-media bucket (brand/ prefix)
-- so the pipeline and agents reference the real files instead of re-drawing them. Files were uploaded
-- to Storage via a one-time service-role function (since decommissioned); this migration recreates the
-- manifest table, the rows, and the app_secrets defaults. Re-uploading the raster files themselves is a
-- separate step (source: knowledge/ or the brand kit zip).
-- ============================================================================
create table if not exists public.brand_assets (
  id bigserial primary key,
  kind text not null,        -- avatar | logo | cover | template
  platform text,
  filename text not null,
  url text not null unique,
  created_at timestamptz default now()
);
alter table public.brand_assets enable row level security;
drop policy if exists brand_assets_public_read on public.brand_assets;
create policy brand_assets_public_read on public.brand_assets for select to anon, authenticated using (true);

insert into public.brand_assets(kind,platform,filename,url) values
('avatar','Facebook','avatar_Facebook_500x500.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/01_Social_Avatars/avatar_Facebook_500x500.png'),
('avatar','GoogleBusiness','avatar_GoogleBusiness_250x250.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/01_Social_Avatars/avatar_GoogleBusiness_250x250.png'),
('avatar','Instagram','avatar_Instagram_320x320.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/01_Social_Avatars/avatar_Instagram_320x320.png'),
('avatar','LinkedIn','avatar_LinkedIn_400x400.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/01_Social_Avatars/avatar_LinkedIn_400x400.png'),
('avatar','Pinterest','avatar_Pinterest_280x280.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/01_Social_Avatars/avatar_Pinterest_280x280.png'),
('avatar','Threads','avatar_Threads_400x400.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/01_Social_Avatars/avatar_Threads_400x400.png'),
('avatar','TikTok','avatar_TikTok_200x200.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/01_Social_Avatars/avatar_TikTok_200x200.png'),
('avatar','Universal','avatar_Universal_Master_1000x1000.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/01_Social_Avatars/avatar_Universal_Master_1000x1000.png'),
('avatar','WhatsApp','avatar_WhatsApp_640x640.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/01_Social_Avatars/avatar_WhatsApp_640x640.png'),
('avatar','X_Twitter','avatar_X_Twitter_400x400.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/01_Social_Avatars/avatar_X_Twitter_400x400.png'),
('avatar','YouTube','avatar_YouTube_800x800.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/01_Social_Avatars/avatar_YouTube_800x800.png'),
('logo','','horizontal_Black_Mono_transparent.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/05_Logo_Lockups/horizontal_Black_Mono_transparent.png'),
('logo','','horizontal_OnDark_transparent.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/05_Logo_Lockups/horizontal_OnDark_transparent.png'),
('logo','','horizontal_OnLight_transparent.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/05_Logo_Lockups/horizontal_OnLight_transparent.png'),
('logo','','horizontal_on_navy.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/05_Logo_Lockups/horizontal_on_navy.png'),
('logo','','horizontal_on_white.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/05_Logo_Lockups/horizontal_on_white.png'),
('logo','','mark_only_transparent_1200.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/05_Logo_Lockups/mark_only_transparent_1200.png'),
('logo','','mark_white_transparent_1200.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/05_Logo_Lockups/mark_white_transparent_1200.png'),
('cover','Facebook','Facebook_Cover_820x312.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/02_Social_Covers/Facebook_Cover_820x312.png'),
('cover','LinkedIn','LinkedIn_Company_Cover_1128x191.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/02_Social_Covers/LinkedIn_Company_Cover_1128x191.png'),
('cover','LinkedIn','LinkedIn_Personal_Cover_1584x396.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/02_Social_Covers/LinkedIn_Personal_Cover_1584x396.png'),
('cover','X_Twitter','X_Twitter_Header_1500x500.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/02_Social_Covers/X_Twitter_Header_1500x500.png'),
('cover','YouTube','YouTube_Channel_Art_2560x1440_safe1546x423.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/02_Social_Covers/YouTube_Channel_Art_2560x1440_safe1546x423.png'),
('template','Instagram','Instagram_Portrait_1080x1350.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/03_Social_Post_Templates/Instagram_Portrait_1080x1350.png'),
('template','Instagram','Instagram_Square_Post_1080x1080.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/03_Social_Post_Templates/Instagram_Square_Post_1080x1080.png'),
('template','','Landscape_Post_1200x675.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/03_Social_Post_Templates/Landscape_Post_1200x675.png'),
('template','TikTok','Story_Reel_TikTok_1080x1920.png','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/03_Social_Post_Templates/Story_Reel_TikTok_1080x1920.png')
on conflict (url) do nothing;
insert into public.app_secrets(key,value) values
('brand_avatar_url','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/01_Social_Avatars/avatar_Universal_Master_1000x1000.png'),
('brand_logo_on_navy_url','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/05_Logo_Lockups/horizontal_on_navy.png'),
('brand_logo_on_white_url','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/05_Logo_Lockups/horizontal_on_white.png'),
('brand_mark_transparent_url','https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/social-media/brand/05_Logo_Lockups/mark_only_transparent_1200.png')
on conflict (key) do update set value=excluded.value;
