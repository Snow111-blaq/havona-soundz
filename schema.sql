-- Havona Soundz starter schema for Supabase Postgres
-- Run only after creating your own Supabase project. Review before production use.
create extension if not exists pgcrypto;

create type public.account_role as enum ('owner', 'artist', 'listener');
create type public.release_status as enum ('draft', 'pending_review', 'approved', 'rejected', 'taken_down');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'New listener',
  role public.account_role not null default 'listener',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.artist_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  artist_name text not null,
  bio text,
  links jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.releases (
  id uuid primary key default gen_random_uuid(),
  artist_user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  release_type text not null default 'single' check (release_type in ('single','ep','album')),
  genre text,
  description text,
  audio_object_path text,
  artwork_object_path text,
  status public.release_status not null default 'draft',
  rights_confirmed boolean not null default false,
  reviewer_notes text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.copyright_reports (
  id uuid primary key default gen_random_uuid(),
  release_id uuid references public.releases(id) on delete set null,
  reporter_name text not null,
  reporter_email text not null,
  claim_details text not null,
  status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  created_at timestamptz not null default now()
);

-- Security defaults: enable RLS everywhere. Add policies after configuring and testing the owner bootstrap.
alter table public.profiles enable row level security;
alter table public.artist_applications enable row level security;
alter table public.releases enable row level security;
alter table public.copyright_reports enable row level security;

-- Users may read/update only their own basic profile; role is not client-editable in production.
create policy "profiles_select_own" on public.profiles for select to authenticated using (auth.uid() = id);
create policy "profiles_update_own_name" on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- Artists may see their own applications and releases. Public approved-release reads can be enabled later
-- after audio storage and rights review are configured.
create policy "applications_select_own" on public.artist_applications for select to authenticated using (auth.uid() = user_id);
create policy "applications_insert_own" on public.artist_applications for insert to authenticated with check (auth.uid() = user_id);
create policy "releases_select_own" on public.releases for select to authenticated using (auth.uid() = artist_user_id);
create policy "releases_insert_own_draft" on public.releases for insert to authenticated with check (auth.uid() = artist_user_id and status = 'draft');
create policy "releases_update_own_draft" on public.releases for update to authenticated using (auth.uid() = artist_user_id and status in ('draft','rejected')) with check (auth.uid() = artist_user_id and status in ('draft','pending_review','rejected'));

-- IMPORTANT OWNER BOOTSTRAP:
-- Do NOT allow public users to set their own role. Create the first owner only through a trusted
-- server-side/admin process after verifying your account ID. Never put service-role keys in browser code.
-- Do not deploy until admin-only policies and owner bootstrap have been reviewed and tested.
