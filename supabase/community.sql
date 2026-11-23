-- Locus community: teams and their leaderboards, team chat, and Humans
-- (people you follow).
--
-- Run in the Supabase dashboard: SQL Editor → New query → paste → Run.
-- Safe to run again, and safe over the first version: everything is
-- "if not exists" / "or replace", and the one-off moves are guarded.
--
-- What leaves a phone:
--   * a display name, a username, a colour, optionally a photo, age and region
--     (each with its own "who sees this" setting);
--   * one row a day of the person's numbers and a row per workout — uploaded
--     only while a team they joined boards that metric, or their privacy
--     setting lets followers see it.
-- Who reads them is decided here, never by the app:
--   * a team sees exactly the boards it was created with (joining a team is
--     agreeing to that, and the join screen says so);
--   * a follower the person accepted sees what that person's privacy setting
--     for each metric allows.

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
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists birth_year smallint;
alter table public.profiles add column if not exists region text;
alter table public.profiles add column if not exists avatar_path text;
-- Who can find me, and what they see when they do: 'all', 'followers', 'none'.
alter table public.profiles add column if not exists searchable text not null default 'all';
alter table public.profiles add column if not exists show_age text not null default 'all';
alter table public.profiles add column if not exists show_region text not null default 'all';
alter table public.profiles add column if not exists show_lists text not null default 'all';
alter table public.profiles add column if not exists show_photo text not null default 'all';
alter table public.profiles add column if not exists mutual_follow boolean not null default true;
-- Per metric: {"who": "followers"|"none", "daily": bool, "trends": bool}.
alter table public.profiles add column if not exists privacy jsonb not null default
  '{"sleep":{"who":"followers","daily":true,"trends":true},
    "recovery":{"who":"followers","daily":true,"trends":true},
    "strain":{"who":"followers","daily":true,"trends":true},
    "activities":{"who":"followers"},
    "age":{"who":"followers"},
    "achievements":{"who":"followers"}}'::jsonb;
create unique index if not exists profiles_username on public.profiles (lower(username))
  where username is not null;

create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 40),
  code text not null unique,
  is_open boolean not null default false,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.teams add column if not exists description text not null default '';
alter table public.teams add column if not exists is_public boolean not null default false;
alter table public.teams add column if not exists chat_enabled boolean not null default true;
-- The boards: set at creation and never changed, so nobody's consent moves
-- under them.
alter table public.teams add column if not exists board_strain boolean not null default true;
alter table public.teams add column if not exists board_recovery boolean not null default true;
alter table public.teams add column if not exists board_sleep boolean not null default true;
-- A bundled picture's key ('banner_3') or a storage path in the teams bucket.
alter table public.teams add column if not exists banner text not null default 'banner_1';
alter table public.teams add column if not exists logo text not null default 'heart';

create unique index if not exists teams_one_open on public.teams (is_open)
  where is_open;
insert into public.teams (name, code, is_open)
values ('Locus community', 'OPEN', true)
on conflict do nothing;

create table if not exists public.team_members (
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  last_read_at timestamptz not null default now(),
  primary key (team_id, user_id)
);
create index if not exists team_members_user on public.team_members (user_id);
alter table public.team_members drop constraint if exists team_members_role_check;
alter table public.team_members add constraint team_members_role_check
  check (role in ('owner', 'admin', 'member'));

create table if not exists public.daily_scores (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  recovery smallint check (recovery between 0 and 100),
  strain real check (strain between 0 and 21),
  sleep_min smallint check (sleep_min between 0 and 1440),
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);
alter table public.daily_scores add column if not exists sleep_perf smallint;
alter table public.daily_scores add column if not exists hrv real;
alter table public.daily_scores add column if not exists rhr real;
alter table public.daily_scores add column if not exists calories real;
alter table public.daily_scores add column if not exists hr_max smallint;
alter table public.daily_scores add column if not exists locus_age real;

-- One row per finished workout: what, when, how hard.
create table if not exists public.activities (
  user_id uuid not null references auth.users (id) on delete cascade,
  local_id text not null,
  day date not null,
  started_at timestamptz not null,
  kind text not null,
  strain real,
  calories real,
  primary key (user_id, local_id)
);
create index if not exists activities_user_day on public.activities (user_id, day);

create table if not exists public.messages (
  id bigint generated always as identity primary key,
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);
alter table public.messages add column if not exists image_path text;
-- What a shared card shows ('Daily overview', 'Weekly recovery'…), for the
-- picture's caption and its screen-reader label.
alter table public.messages add column if not exists card text;
alter table public.messages drop constraint if exists messages_body_check;
alter table public.messages add constraint messages_body_check
  check (char_length(body) <= 2000 and (char_length(body) > 0 or image_path is not null));
create index if not exists messages_team_time on public.messages (team_id, created_at desc);

-- The old picture feed. Kept so nothing is lost; the app no longer writes it.
create table if not exists public.posts (
  id bigint generated always as identity primary key,
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  caption text not null default '' check (char_length(caption) <= 500),
  image_path text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.follows (
  follower uuid not null references auth.users (id) on delete cascade,
  followee uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (follower, followee),
  check (follower <> followee)
);
create index if not exists follows_followee on public.follows (followee);

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

create table if not exists public.community_migrations (
  name text primary key,
  at timestamptz not null default now()
);

-- ─────────────────────────── one-off moves ───────────────────────────

do $$ begin
  if not exists (select 1 from community_migrations where name = 'v2') then
    -- Everyone was put in the open community without being asked what it
    -- would see. Under per-team sharing, joining is the asking: take them
    -- out, they rejoin from Recommended teams.
    delete from team_members where team_id in (select id from teams where is_open);
    update teams set is_public = true, chat_enabled = false,
      description = 'Everyone with Locus, on one board.'
      where is_open;
    -- The old feed's posts become chat pictures.
    insert into messages (team_id, user_id, body, image_path, created_at)
      select team_id, user_id, caption, image_path, created_at from posts;
    insert into community_migrations (name) values ('v2');
  end if;
end $$;

-- ─────────────────────────── helpers ───────────────────────────
-- security definer so policies can ask without recursing into each other.

create or replace function public.is_member(t uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from team_members where team_id = t and user_id = auth.uid());
$$;

create or replace function public.is_admin(t uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from team_members
                 where team_id = t and user_id = auth.uid() and role in ('owner', 'admin'));
$$;

create or replace function public.is_open_team(t uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_open from teams where id = t), false);
$$;

create or replace function public.chat_on(t uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select chat_enabled and not is_open from teams where id = t), false);
$$;

create or replace function public.shares_team(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from team_members a
    join team_members b on a.team_id = b.team_id
    where a.user_id = auth.uid() and b.user_id = other);
$$;

create or replace function public.follows_me(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from follows where follower = other and followee = auth.uid()
                 and status = 'accepted');
$$;

create or replace function public.i_follow(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from follows where follower = auth.uid() and followee = other
                 and status = 'accepted');
$$;

-- Does the viewer get [metric] of [owner]? 'strain' | 'recovery' | 'sleep' |
-- 'activities' | 'age' | 'achievements'. Through a shared team that boards
-- it (activities ride on the strain board), or as an accepted follower when
-- the owner's setting says followers.
create or replace function public.can_see(owner uuid, metric text)
returns boolean language sql stable security definer set search_path = public as $$
  select owner = auth.uid()
    or exists (
      select 1 from team_members a
      join team_members b on a.team_id = b.team_id
      join teams t on t.id = a.team_id
      where a.user_id = auth.uid() and b.user_id = owner
        and case metric
              when 'strain' then t.board_strain
              when 'activities' then t.board_strain
              when 'recovery' then t.board_recovery
              when 'sleep' then t.board_sleep
              else false end)
    or (public.i_follow(owner)
        and coalesce((select privacy -> metric ->> 'who' from profiles where id = owner),
                     'none') = 'followers');
$$;

-- A follower's extra switches: 'daily' values, 'trends' beyond today. A team
-- sees both for its boards.
create or replace function public.can_see_part(owner uuid, metric text, part text)
returns boolean language sql stable security definer set search_path = public as $$
  select owner = auth.uid()
    or exists (
      select 1 from team_members a
      join team_members b on a.team_id = b.team_id
      join teams t on t.id = a.team_id
      where a.user_id = auth.uid() and b.user_id = owner
        and case metric
              when 'strain' then t.board_strain
              when 'recovery' then t.board_recovery
              when 'sleep' then t.board_sleep
              else false end)
    or (public.i_follow(owner)
        and coalesce((select (privacy -> metric ->> part)::boolean from profiles
                       where id = owner), false)
        and coalesce((select privacy -> metric ->> 'who' from profiles where id = owner),
                     'none') = 'followers');
$$;

-- A profile field the owner set to 'all' / 'followers' / 'none'.
create or replace function public.field_visible(setting text, owner uuid)
returns boolean language sql stable as $$
  select owner = auth.uid() or setting = 'all'
    or (setting = 'followers' and public.i_follow(owner));
$$;

-- ─────────────────────────── new accounts ───────────────────────────

create or replace function public.on_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- Never the email address. No team either: joining one is the person's
  -- own choice, made on its join screen.
  insert into profiles (id, display_name, hue)
  values (new.id, 'Member ' || upper(substr(new.id::text, 1, 4)),
          floor(random() * 360)::smallint)
  on conflict do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.on_new_user();

-- ─────────────────────────── teams ───────────────────────────

-- What the join screen shows before anyone joins: by code, or any public team.
create or replace function public.team_preview(join_code text default null, team uuid default null)
returns table (id uuid, name text, description text, is_public boolean,
               chat_enabled boolean, board_strain boolean, board_recovery boolean,
               board_sleep boolean, banner text, logo text, members bigint,
               joined boolean)
language sql stable security definer set search_path = public as $$
  select t.id, t.name, t.description, t.is_public, t.chat_enabled and not t.is_open,
         t.board_strain, t.board_recovery, t.board_sleep, t.banner, t.logo,
         (select count(*) from team_members m where m.team_id = t.id),
         public.is_member(t.id)
  from teams t
  where (join_code is not null and t.code = upper(trim(join_code)))
     or (team is not null and t.id = team and (t.is_public or public.is_member(t.id)));
$$;

-- Public teams, biggest first, optionally narrowed by name.
create or replace function public.public_teams(q text default '', lim int default 30)
returns table (id uuid, name text, description text, banner text, logo text,
               members bigint, joined boolean)
language sql stable security definer set search_path = public as $$
  select t.id, t.name, t.description, t.banner, t.logo,
         (select count(*) from team_members m where m.team_id = t.id) as n,
         public.is_member(t.id)
  from teams t
  where t.is_public and (q = '' or t.name ilike '%' || q || '%')
  order by t.is_open desc, n desc, t.name
  limit greatest(1, least(lim, 100));
$$;

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

create or replace function public.join_public(team uuid)
returns uuid language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if not exists (select 1 from teams where id = team and is_public) then
    raise exception 'That team is private';
  end if;
  insert into team_members (team_id, user_id) values (team, auth.uid())
  on conflict do nothing;
  return team;
end $$;

drop function if exists public.create_team(text);
create or replace function public.create_team(
  team_name text, about text default '', public_team boolean default false,
  chat boolean default true, strain boolean default true,
  recovery boolean default true, sleep boolean default true,
  banner_key text default 'banner_1', logo_key text default 'heart')
returns uuid language plpgsql security definer set search_path = public as $$
declare t uuid; c text;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if not (strain or recovery or sleep) then
    raise exception 'Pick at least one leaderboard';
  end if;
  loop
    -- Six characters with no 0/O or 1/I to misread.
    c := (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
                                   1 + floor(random() * 32)::int, 1), '')
          from generate_series(1, 6));
    exit when not exists (select 1 from teams where code = c);
  end loop;
  insert into teams (name, description, code, created_by, is_public, chat_enabled,
                     board_strain, board_recovery, board_sleep, banner, logo)
  values (trim(team_name), trim(about), c, auth.uid(), public_team, chat,
          strain, recovery, sleep, banner_key, logo_key)
  returning id into t;
  insert into team_members (team_id, user_id, role) values (t, auth.uid(), 'owner');
  return t;
end $$;

-- An admin takes someone out. The owner cannot be removed.
create or replace function public.remove_member(team uuid, member uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin(team) then raise exception 'Only an admin can do that'; end if;
  delete from team_members
   where team_id = team and user_id = member and role <> 'owner';
end $$;

-- The owner leaves and the team goes with them.
create or replace function public.delete_team(team uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from team_members
                 where team_id = team and user_id = auth.uid() and role = 'owner') then
    raise exception 'Only the owner can delete the team';
  end if;
  delete from teams where id = team and not is_open;
end $$;

create or replace function public.delete_me()
returns void language sql security definer set search_path = public as $$
  delete from auth.users where id = auth.uid();
$$;

-- ─────────────────────────── numbers ───────────────────────────

-- A team's days since [since], each column only where the team boards it.
drop function if exists public.team_scores(uuid, date);
create or replace function public.team_scores(t uuid, since date, until date default null)
returns table (user_id uuid, day date, recovery smallint, strain real,
               sleep_min smallint, sleep_perf smallint, hrv real, rhr real,
               calories real, updated_at timestamptz)
language sql stable security definer set search_path = public as $$
  select s.user_id, s.day,
         case when tm.board_recovery then s.recovery end,
         case when tm.board_strain then s.strain end,
         case when tm.board_sleep then s.sleep_min end,
         case when tm.board_sleep then s.sleep_perf end,
         case when tm.board_recovery then s.hrv end,
         case when tm.board_recovery then s.rhr end,
         case when tm.board_strain then s.calories end,
         s.updated_at
  from daily_scores s
  join team_members m on m.user_id = s.user_id and m.team_id = t
  join teams tm on tm.id = t
  where s.day >= since and (until is null or s.day <= until) and public.is_member(t)
    and s.user_id not in (select blocked from blocks where blocker = auth.uid());
$$;

create or replace function public.team_activities(t uuid, since date, until date default null)
returns table (user_id uuid, day date, started_at timestamptz, kind text,
               strain real, calories real)
language sql stable security definer set search_path = public as $$
  select a.user_id, a.day, a.started_at, a.kind, a.strain, a.calories
  from activities a
  join team_members m on m.user_id = a.user_id and m.team_id = t
  join teams tm on tm.id = t
  where tm.board_strain and a.day >= since and (until is null or a.day <= until)
    and public.is_member(t);
$$;

-- One person's days, as the viewer may see them (a team in common, or as a
-- follower under that person's settings). Without trends, only today.
create or replace function public.member_scores(other uuid, since date)
returns table (day date, recovery smallint, strain real, sleep_min smallint,
               sleep_perf smallint, hrv real, rhr real, calories real,
               hr_max smallint, locus_age real)
language sql stable security definer set search_path = public as $$
  with v as (
    select public.can_see(other, 'recovery') rec, public.can_see(other, 'strain') str,
           public.can_see(other, 'sleep') slp, public.can_see(other, 'age') age,
           public.can_see_part(other, 'recovery', 'daily') rec_d,
           public.can_see_part(other, 'strain', 'daily') str_d,
           public.can_see_part(other, 'sleep', 'daily') slp_d,
           public.can_see_part(other, 'recovery', 'trends') rec_t,
           public.can_see_part(other, 'strain', 'trends') str_t,
           public.can_see_part(other, 'sleep', 'trends') slp_t)
  select s.day,
         case when v.rec and (v.rec_t or s.day >= current_date - 1) then s.recovery end,
         case when v.str and (v.str_t or s.day >= current_date - 1) then s.strain end,
         case when v.slp and v.slp_d and (v.slp_t or s.day >= current_date - 1) then s.sleep_min end,
         case when v.slp and (v.slp_t or s.day >= current_date - 1) then s.sleep_perf end,
         case when v.rec and v.rec_d and (v.rec_t or s.day >= current_date - 1) then s.hrv end,
         case when v.rec and v.rec_d and (v.rec_t or s.day >= current_date - 1) then s.rhr end,
         case when v.str and v.str_d and (v.str_t or s.day >= current_date - 1) then s.calories end,
         case when v.str and v.str_d then s.hr_max end,
         case when v.age then s.locus_age end
  from daily_scores s, v
  where s.user_id = other and s.day >= since
    and other not in (select blocked from blocks where blocker = auth.uid());
$$;

create or replace function public.member_activities(other uuid, since date)
returns table (day date, started_at timestamptz, kind text, strain real, calories real)
language sql stable security definer set search_path = public as $$
  select a.day, a.started_at, a.kind, a.strain, a.calories
  from activities a
  where a.user_id = other and a.day >= since and public.can_see(other, 'activities');
$$;

-- My place in each of my teams for one board over [since, until]: strain by
-- the best day, recovery and sleep by the mean. Null rank when I have no
-- figure in that window.
create or replace function public.my_ranks(metric text, since date, until date)
returns table (team_id uuid, rank bigint, of_count bigint)
language sql stable security definer set search_path = public as $$
  with mine as (select team_id from team_members where user_id = auth.uid()),
  vals as (
    select m.team_id, s.user_id,
           case metric
             when 'strain' then max(s.strain)
             when 'recovery' then avg(s.recovery)
             else avg(s.sleep_perf) end as v
    from mine m
    join teams t on t.id = m.team_id
    join team_members tm on tm.team_id = m.team_id
    join daily_scores s on s.user_id = tm.user_id
    where s.day between since and until
      and case metric when 'strain' then t.board_strain
                      when 'recovery' then t.board_recovery
                      else t.board_sleep end
    group by m.team_id, s.user_id),
  ranked as (
    select team_id, user_id, rank() over (partition by team_id order by v desc) r,
           count(*) over (partition by team_id) n
    from vals where v is not null)
  select m.team_id, r.r, coalesce(r.n, 0)
  from mine m left join ranked r on r.team_id = m.team_id and r.user_id = auth.uid();
$$;

-- ─────────────────────────── humans ───────────────────────────

-- People to follow: by name or username, honouring who may find them and
-- what they show.
create or replace function public.search_profiles(q text)
returns table (id uuid, display_name text, username text, hue smallint,
               avatar_path text, birth_year smallint, region text,
               follow_state text, follows_me boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, p.username, p.hue,
         case when public.field_visible(p.show_photo, p.id) then p.avatar_path end,
         case when public.field_visible(p.show_age, p.id) then p.birth_year end,
         case when public.field_visible(p.show_region, p.id) then p.region end,
         (select status from follows where follower = auth.uid() and followee = p.id),
         public.follows_me(p.id)
  from profiles p
  where p.id <> auth.uid() and char_length(trim(q)) >= 2
    and (p.display_name ilike '%' || trim(q) || '%'
         or p.username ilike '%' || ltrim(trim(q), '@') || '%')
    and (p.searchable = 'all' or (p.searchable = 'followers' and public.follows_me(p.id)))
    and p.id not in (select blocked from blocks where blocker = auth.uid())
    and auth.uid() not in (select blocked from blocks where blocker = p.id)
  order by p.display_name
  limit 30;
$$;

-- One person as I may see them.
create or replace function public.profile_card(other uuid)
returns table (id uuid, display_name text, username text, hue smallint,
               avatar_path text, birth_year smallint, region text,
               member_since timestamptz, follow_state text, follows_me boolean,
               followers bigint, following bigint, lists_visible boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, p.username, p.hue,
         case when public.field_visible(p.show_photo, p.id) then p.avatar_path end,
         case when public.field_visible(p.show_age, p.id) then p.birth_year end,
         case when public.field_visible(p.show_region, p.id) then p.region end,
         p.created_at,
         (select status from follows where follower = auth.uid() and followee = p.id),
         public.follows_me(p.id),
         (select count(*) from follows where followee = p.id and status = 'accepted'),
         (select count(*) from follows where follower = p.id and status = 'accepted'),
         public.field_visible(p.show_lists, p.id)
  from profiles p
  where p.id = other
    and (p.id = auth.uid() or public.shares_team(p.id) or public.i_follow(p.id)
         or public.follows_me(p.id)
         or exists (select 1 from follows where follower = auth.uid() and followee = p.id)
         or p.searchable = 'all');
$$;

create or replace function public.follow(other uuid)
returns text language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or other = auth.uid() then raise exception 'Not possible'; end if;
  if exists (select 1 from blocks where blocker = other and blocked = auth.uid()) then
    raise exception 'Not possible';
  end if;
  insert into follows (follower, followee) values (auth.uid(), other)
  on conflict do nothing;
  return (select status from follows where follower = auth.uid() and followee = other);
end $$;

-- Accept a request. With mutual following on, the accepter follows back.
create or replace function public.accept_follow(requester uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update follows set status = 'accepted'
   where follower = requester and followee = auth.uid();
  if (select mutual_follow from profiles where id = auth.uid()) then
    insert into follows (follower, followee, status)
    values (auth.uid(), requester, 'accepted')
    on conflict (follower, followee) do update set status = 'accepted';
  end if;
end $$;

-- Lists of someone's people, if they show them (always your own).
create or replace function public.follow_list(other uuid, which text)
returns table (id uuid, display_name text, username text, hue smallint,
               avatar_path text, status text)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, p.username, p.hue,
         case when public.field_visible(p.show_photo, p.id) then p.avatar_path end,
         f.status
  from follows f
  join profiles p on p.id = case which when 'followers' then f.follower else f.followee end
  where (case which when 'followers' then f.followee else f.follower end) = other
    and (f.status = 'accepted' or other = auth.uid())
    and (other = auth.uid()
         or public.field_visible((select show_lists from profiles where id = other), other))
  order by f.status desc, p.display_name;
$$;

-- ─────────────────────────── row level security ───────────────────────────

alter table public.profiles enable row level security;
alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.daily_scores enable row level security;
alter table public.activities enable row level security;
alter table public.messages enable row level security;
alter table public.posts enable row level security;
alter table public.follows enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;
alter table public.community_migrations enable row level security;

-- Profiles: names and colours of people you share a team or a follow with.
-- The private columns (privacy, birth year…) reach others only through the
-- functions above, which mask them.
drop policy if exists "profiles read" on public.profiles;
create policy "profiles read" on public.profiles for select
  using (id = auth.uid() or public.shares_team(id) or public.i_follow(id)
         or public.follows_me(id));
drop policy if exists "profiles write own" on public.profiles;
create policy "profiles write own" on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "teams read mine" on public.teams;
create policy "teams read mine" on public.teams for select
  using (public.is_member(id) or is_public);
drop policy if exists "teams rename own" on public.teams;
drop policy if exists "teams admin edit" on public.teams;
create policy "teams admin edit" on public.teams for update
  using (public.is_admin(id) and not is_open)
  with check (public.is_admin(id) and not is_open);
-- The boards never change after creation.
create or replace function public.keep_boards()
returns trigger language plpgsql as $$
begin
  new.board_strain := old.board_strain;
  new.board_recovery := old.board_recovery;
  new.board_sleep := old.board_sleep;
  new.code := old.code;
  new.is_open := old.is_open;
  new.created_by := old.created_by;
  return new;
end $$;
drop trigger if exists teams_keep_boards on public.teams;
create trigger teams_keep_boards before update on public.teams
  for each row execute function public.keep_boards();

drop policy if exists "members read" on public.team_members;
create policy "members read" on public.team_members for select
  using (public.is_member(team_id));
drop policy if exists "members leave" on public.team_members;
create policy "members leave" on public.team_members for delete
  using (user_id = auth.uid() and role <> 'owner');
drop policy if exists "members mark read" on public.team_members;
create policy "members mark read" on public.team_members for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());

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

drop policy if exists "activities own" on public.activities;
create policy "activities own" on public.activities for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Chat: members of a team whose admin has chat on.
drop policy if exists "messages read" on public.messages;
create policy "messages read" on public.messages for select
  using (public.is_member(team_id) and public.chat_on(team_id));
drop policy if exists "messages write" on public.messages;
create policy "messages write" on public.messages for insert
  with check (user_id = auth.uid() and public.is_member(team_id)
              and public.chat_on(team_id));
drop policy if exists "messages delete own" on public.messages;
create policy "messages delete own" on public.messages for delete
  using (user_id = auth.uid() or public.is_admin(team_id));

drop policy if exists "posts read" on public.posts;
drop policy if exists "posts write" on public.posts;
drop policy if exists "posts delete own" on public.posts;
create policy "posts delete own" on public.posts for delete
  using (user_id = auth.uid());

drop policy if exists "follows read" on public.follows;
create policy "follows read" on public.follows for select
  using (follower = auth.uid() or followee = auth.uid());
drop policy if exists "follows decide" on public.follows;
-- The followee declines (or removes a follower); the follower withdraws or
-- unfollows. Requests and accepting go through follow() / accept_follow().
drop policy if exists "follows remove" on public.follows;
create policy "follows remove" on public.follows for delete
  using (follower = auth.uid() or followee = auth.uid());

drop policy if exists "blocks own" on public.blocks;
create policy "blocks own" on public.blocks for all
  using (blocker = auth.uid()) with check (blocker = auth.uid());

drop policy if exists "reports write" on public.reports;
create policy "reports write" on public.reports for insert
  with check (reporter = auth.uid());

grant execute on function public.join_team(text) to authenticated;
grant execute on function public.join_public(uuid) to authenticated;
grant execute on function public.team_preview(text, uuid) to authenticated;
grant execute on function public.public_teams(text, int) to authenticated;
grant execute on function public.create_team(text, text, boolean, boolean, boolean,
  boolean, boolean, text, text) to authenticated;
grant execute on function public.remove_member(uuid, uuid) to authenticated;
grant execute on function public.delete_team(uuid) to authenticated;
grant execute on function public.delete_me() to authenticated;
grant execute on function public.team_scores(uuid, date, date) to authenticated;
grant execute on function public.team_activities(uuid, date, date) to authenticated;
grant execute on function public.member_scores(uuid, date) to authenticated;
grant execute on function public.member_activities(uuid, date) to authenticated;
grant execute on function public.my_ranks(text, date, date) to authenticated;
grant execute on function public.search_profiles(text) to authenticated;
grant execute on function public.profile_card(uuid) to authenticated;
grant execute on function public.follow(uuid) to authenticated;
grant execute on function public.accept_follow(uuid) to authenticated;
grant execute on function public.follow_list(uuid, text) to authenticated;

-- ─────────────────────────── live ───────────────────────────

do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.follows;
exception when duplicate_object then null; end $$;

-- ─────────────────────────── pictures ───────────────────────────
-- 'posts': chat pictures at <team id>/<user id>/<name>, read by that team.
-- 'teams': uploaded banners and logos at <team id>/<name>, read by anyone
--          signed in (public teams show them before joining), written by the
--          team's admins.
-- 'avatars': profile photos at <user id>/<name>, read by anyone signed in
--          (profile_card hands the path out only where show_photo allows).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('posts', 'posts', false, 2097152, array['image/jpeg', 'image/png'])
on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('teams', 'teams', false, 2097152, array['image/jpeg', 'image/png'])
on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 1048576, array['image/jpeg', 'image/png'])
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
              and public.chat_on(((storage.foldername(name))[1])::uuid));
drop policy if exists "posts pictures delete own" on storage.objects;
create policy "posts pictures delete own" on storage.objects for delete
  using (bucket_id = 'posts' and (storage.foldername(name))[2] = auth.uid()::text);

drop policy if exists "team pictures read" on storage.objects;
create policy "team pictures read" on storage.objects for select
  using (bucket_id = 'teams' and auth.uid() is not null);
drop policy if exists "team pictures write" on storage.objects;
create policy "team pictures write" on storage.objects for insert
  with check (bucket_id = 'teams'
              and public.is_admin(((storage.foldername(name))[1])::uuid));

drop policy if exists "avatars read" on storage.objects;
create policy "avatars read" on storage.objects for select
  using (bucket_id = 'avatars' and auth.uid() is not null);
drop policy if exists "avatars write own" on storage.objects;
create policy "avatars write own" on storage.objects for insert
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "avatars delete own" on storage.objects;
create policy "avatars delete own" on storage.objects for delete
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ─────────────────────────── column privacy ───────────────────────────
-- Row security lets a teammate or follower read a profile row; these grants
-- keep the private columns of it (age, region, photo, settings) out of that
-- read. Others get them only masked, through the functions above; the owner
-- gets the whole row through my_profile().

revoke select on public.profiles from authenticated, anon;
grant select (id, display_name, username, hue, created_at) on public.profiles to authenticated;
grant update (display_name, username, hue, birth_year, region, avatar_path, searchable,
              show_age, show_region, show_lists, show_photo, mutual_follow, privacy)
  on public.profiles to authenticated;

create or replace function public.my_profile()
returns setof public.profiles
language sql stable security definer set search_path = public as $$
  select * from profiles where id = auth.uid();
$$;

-- A team's people, photos only where each allows it.
create or replace function public.team_people(t uuid)
returns table (id uuid, display_name text, username text, hue smallint,
               avatar_path text, role text, joined_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, p.username, p.hue,
         case when p.show_photo = 'all' or p.id = auth.uid()
                   or (p.show_photo = 'followers' and public.i_follow(p.id))
              then p.avatar_path end,
         m.role, m.joined_at
  from team_members m join profiles p on p.id = m.user_id
  where m.team_id = t and public.is_member(t)
    and p.id not in (select blocked from blocks where blocker = auth.uid())
  order by case m.role when 'owner' then 0 when 'admin' then 1 else 2 end, p.display_name;
$$;

grant execute on function public.my_profile() to authenticated;
grant execute on function public.team_people(uuid) to authenticated;
