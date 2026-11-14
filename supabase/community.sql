-- Locus community: teams, leaderboards, team chat and the team feed.
--
-- Run once in the Supabase dashboard: SQL Editor → New query → paste → Run.
-- Safe to run again: everything is "if not exists" / "or replace".
--
-- What leaves a phone, and only after its owner ticks it: a display name, a
-- colour, and one number per day for each metric they chose to share
-- (recovery %, day strain, hours slept). Nothing else. Chat messages and feed
-- posts are seen only by the team they were written to.

-- ─────────────────────────── tables ───────────────────────────

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default 'Member'
    check (char_length(display_name) between 1 and 40),
  hue smallint not null default 0 check (hue between 0 and 359),
  share_recovery boolean not null default false,
  share_strain boolean not null default false,
  share_sleep boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 40),
  code text not null unique,
  is_open boolean not null default false,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

-- The one open community: leaderboard only, everyone in unless they opt out.
create unique index if not exists teams_one_open on public.teams (is_open)
  where is_open;
insert into public.teams (name, code, is_open)
values ('Locus community', 'OPEN', true)
on conflict do nothing;

create table if not exists public.team_members (
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  -- For the unread badge: everything newer than this is new to them.
  last_read_at timestamptz not null default now(),
  primary key (team_id, user_id)
);
create index if not exists team_members_user on public.team_members (user_id);

create table if not exists public.daily_scores (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  recovery smallint check (recovery between 0 and 100),
  strain real check (strain between 0 and 21),
  sleep_min smallint check (sleep_min between 0 and 1440),
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

create table if not exists public.messages (
  id bigint generated always as identity primary key,
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists messages_team_time on public.messages (team_id, created_at desc);

create table if not exists public.posts (
  id bigint generated always as identity primary key,
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  caption text not null default '' check (char_length(caption) <= 500),
  image_path text not null,
  created_at timestamptz not null default now()
);
create index if not exists posts_team_time on public.posts (team_id, created_at desc);

create table if not exists public.blocks (
  blocker uuid not null references auth.users (id) on delete cascade,
  blocked uuid not null references auth.users (id) on delete cascade,
  primary key (blocker, blocked)
);

create table if not exists public.reports (
  id bigint generated always as identity primary key,
  reporter uuid not null references auth.users (id) on delete cascade,
  team_id uuid references public.teams (id) on delete cascade,
  message_id bigint references public.messages (id) on delete set null,
  post_id bigint references public.posts (id) on delete set null,
  reason text not null default '' check (char_length(reason) <= 500),
  created_at timestamptz not null default now()
);

-- ─────────────────────────── helpers ───────────────────────────
-- security definer so policies can ask about membership without recursing
-- into team_members' own policy.

create or replace function public.is_member(t uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from team_members where team_id = t and user_id = auth.uid());
$$;

create or replace function public.is_open_team(t uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_open from teams where id = t), false);
$$;

create or replace function public.shares_team(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from team_members a
    join team_members b on a.team_id = b.team_id
    where a.user_id = auth.uid() and b.user_id = other);
$$;

-- A new account gets a profile, and joins the open community.
create or replace function public.on_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- Never the email address: the open community would see it. The app asks
  -- for a name straight after the first sign-in.
  insert into profiles (id, display_name, hue)
  values (new.id, 'Member ' || upper(substr(new.id::text, 1, 4)),
          floor(random() * 360)::smallint)
  on conflict do nothing;
  insert into team_members (team_id, user_id)
  select id, new.id from teams where is_open
  on conflict do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.on_new_user();

-- Join by code. The only way into a team: teams are not readable by people
-- outside them, so a code cannot be looked up any other way.
create or replace function public.join_team(join_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select id into t from teams where code = upper(trim(join_code));
  if t is null then raise exception 'No team has that code'; end if;
  insert into team_members (team_id, user_id) values (t, auth.uid())
  on conflict do nothing;
  return t;
end $$;

create or replace function public.create_team(team_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare t uuid; c text;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  loop
    -- Six characters with no 0/O or 1/I to misread.
    c := (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
                                   1 + floor(random() * 32)::int, 1), '')
          from generate_series(1, 6));
    exit when not exists (select 1 from teams where code = c);
  end loop;
  insert into teams (name, code, created_by) values (trim(team_name), c, auth.uid())
  returning id into t;
  insert into team_members (team_id, user_id, role) values (t, auth.uid(), 'owner');
  return t;
end $$;

-- Delete my account and everything in it.
create or replace function public.delete_me()
returns void language sql security definer set search_path = public as $$
  delete from auth.users where id = auth.uid();
$$;

-- ─────────────────────────── row level security ───────────────────────────

alter table public.profiles enable row level security;
alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.daily_scores enable row level security;
alter table public.messages enable row level security;
alter table public.posts enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;

drop policy if exists "profiles read" on public.profiles;
create policy "profiles read" on public.profiles for select
  using (id = auth.uid() or public.shares_team(id));
drop policy if exists "profiles write own" on public.profiles;
create policy "profiles write own" on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "teams read mine" on public.teams;
create policy "teams read mine" on public.teams for select
  using (public.is_member(id));
drop policy if exists "teams rename own" on public.teams;
create policy "teams rename own" on public.teams for update
  using (created_by = auth.uid() and not is_open)
  with check (created_by = auth.uid() and not is_open);

drop policy if exists "members read" on public.team_members;
create policy "members read" on public.team_members for select
  using (public.is_member(team_id));
drop policy if exists "members leave" on public.team_members;
create policy "members leave" on public.team_members for delete
  using (user_id = auth.uid());
drop policy if exists "members mark read" on public.team_members;
create policy "members mark read" on public.team_members for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- A day's numbers: only your own, directly. Other members' come through
-- team_scores() below, which hands back only what each of them shares.
drop policy if exists "scores read" on public.daily_scores;
create policy "scores read" on public.daily_scores for select
  using (user_id = auth.uid());
drop policy if exists "scores write own" on public.daily_scores;
create policy "scores write own" on public.daily_scores for insert
  with check (user_id = auth.uid());
drop policy if exists "scores update own" on public.daily_scores;
create policy "scores update own" on public.daily_scores for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "scores delete own" on public.daily_scores;
create policy "scores delete own" on public.daily_scores for delete
  using (user_id = auth.uid());

-- Chat and feed: members of a team that is not the open one.
drop policy if exists "messages read" on public.messages;
create policy "messages read" on public.messages for select
  using (public.is_member(team_id) and not public.is_open_team(team_id));
drop policy if exists "messages write" on public.messages;
create policy "messages write" on public.messages for insert
  with check (user_id = auth.uid() and public.is_member(team_id)
              and not public.is_open_team(team_id));
drop policy if exists "messages delete own" on public.messages;
create policy "messages delete own" on public.messages for delete
  using (user_id = auth.uid());

drop policy if exists "posts read" on public.posts;
create policy "posts read" on public.posts for select
  using (public.is_member(team_id) and not public.is_open_team(team_id));
drop policy if exists "posts write" on public.posts;
create policy "posts write" on public.posts for insert
  with check (user_id = auth.uid() and public.is_member(team_id)
              and not public.is_open_team(team_id));
drop policy if exists "posts delete own" on public.posts;
create policy "posts delete own" on public.posts for delete
  using (user_id = auth.uid());

drop policy if exists "blocks own" on public.blocks;
create policy "blocks own" on public.blocks for all
  using (blocker = auth.uid()) with check (blocker = auth.uid());

drop policy if exists "reports write" on public.reports;
create policy "reports write" on public.reports for insert
  with check (reporter = auth.uid());

-- A team's numbers since a day, each metric blanked unless its owner shares
-- it (you always see your own). Only for a team you are in.
create or replace function public.team_scores(t uuid, since date)
returns table (user_id uuid, day date, recovery smallint, strain real,
               sleep_min smallint)
language sql stable security definer set search_path = public as $$
  select s.user_id, s.day,
         case when p.share_recovery or s.user_id = auth.uid() then s.recovery end,
         case when p.share_strain or s.user_id = auth.uid() then s.strain end,
         case when p.share_sleep or s.user_id = auth.uid() then s.sleep_min end
  from daily_scores s
  join profiles p on p.id = s.user_id
  join team_members m on m.user_id = s.user_id and m.team_id = t
  where s.day >= since and public.is_member(t);
$$;

grant execute on function public.join_team(text) to authenticated;
grant execute on function public.create_team(text) to authenticated;
grant execute on function public.delete_me() to authenticated;
grant execute on function public.team_scores(uuid, date) to authenticated;

-- ─────────────────────────── live chat ───────────────────────────

do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null; end $$;

-- ─────────────────────────── feed pictures ───────────────────────────
-- Private bucket; a picture lives at <team id>/<user id>/<name>.jpg and only
-- that team's members can read it.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('posts', 'posts', false, 2097152, array['image/jpeg', 'image/png'])
on conflict (id) do nothing;

drop policy if exists "posts pictures read" on storage.objects;
create policy "posts pictures read" on storage.objects for select
  using (bucket_id = 'posts'
         and public.is_member(((storage.foldername(name))[1])::uuid));
drop policy if exists "posts pictures write" on storage.objects;
create policy "posts pictures write" on storage.objects for insert
  with check (bucket_id = 'posts'
              and (storage.foldername(name))[2] = auth.uid()::text
              and public.is_member(((storage.foldername(name))[1])::uuid)
              and not public.is_open_team(((storage.foldername(name))[1])::uuid));
drop policy if exists "posts pictures delete own" on storage.objects;
create policy "posts pictures delete own" on storage.objects for delete
  using (bucket_id = 'posts' and (storage.foldername(name))[2] = auth.uid()::text);
