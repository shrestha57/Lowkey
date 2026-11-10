-- Lowkey database setup for Supabase (free plan).
-- Paste this whole file into Supabase: SQL Editor -> New query -> Run.
--
-- Privacy design: the tables have row-level security turned on and NO policies,
-- so the public key cannot read or write them directly. The app can only call the
-- functions below, and plan_status() returns the group's combined budget level,
-- never anyone's individual answer.

create table if not exists public.plans (
  code           text primary key,
  title          text not null default 'Our hangout',
  host_name      text not null,
  area_label     text not null,
  lat            double precision not null,
  lon            double precision not null,
  radius_mi      int  not null default 5,
  bonus          int  not null default 0,      -- levels added by passed stretch votes
  stretch_round  int  not null default 0,
  stretch_open   boolean not null default false,
  stretch_result text,                          -- 'passed' | 'stayed' | null
  created_at     timestamptz not null default now()
);

create table if not exists public.members (
  plan_code  text not null references public.plans(code) on delete cascade,
  device_id  text not null,
  name       text not null,
  tier       int  not null check (tier between 0 and 4),
  vote_round int,
  vote_yes   boolean,
  joined_at  timestamptz not null default now(),
  primary key (plan_code, device_id)
);

alter table public.plans   enable row level security;
alter table public.members enable row level security;

-- Create a plan and return its invite code.
create or replace function public.create_plan(
  p_title text, p_host text, p_area text,
  p_lat double precision, p_lon double precision, p_radius int
) returns text
language plpgsql security definer set search_path = public as $$
declare v_code text;
begin
  if length(coalesce(trim(p_host), '')) = 0 then raise exception 'name required'; end if;
  loop
    v_code := substr(md5(random()::text || clock_timestamp()::text), 1, 8);
    exit when not exists (select 1 from plans where code = v_code);
  end loop;
  insert into plans (code, title, host_name, area_label, lat, lon, radius_mi)
  values (v_code,
          left(coalesce(nullif(trim(p_title), ''), 'Our hangout'), 40),
          left(trim(p_host), 24),
          left(coalesce(p_area, 'Somewhere'), 80),
          p_lat, p_lon,
          greatest(1, least(coalesce(p_radius, 5), 25)));
  return v_code;
end $$;

-- Join a plan (or update your answer) with a private budget level 0-4.
create or replace function public.join_plan(
  p_code text, p_device text, p_name text, p_tier int
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from plans where code = p_code) then raise exception 'plan not found'; end if;
  if p_tier is null or p_tier < 0 or p_tier > 4 then raise exception 'bad budget'; end if;
  if length(coalesce(trim(p_name), '')) = 0 then raise exception 'name required'; end if;
  if (select count(*) from members where plan_code = p_code and device_id <> p_device) >= 12 then
    raise exception 'plan is full';
  end if;
  insert into members (plan_code, device_id, name, tier)
  values (p_code, left(p_device, 64), left(trim(p_name), 24), p_tier)
  on conflict (plan_code, device_id) do update set name = excluded.name, tier = excluded.tier;
end $$;

-- Everything a phone needs to show the plan. Only the group's lowest level is returned.
create or replace function public.plan_status(p_code text, p_device text)
returns json
language sql security definer set search_path = public stable as $$
  select json_build_object(
    'code', p.code, 'title', p.title, 'host', p.host_name, 'area', p.area_label,
    'lat', p.lat, 'lon', p.lon, 'radius', p.radius_mi,
    'names', coalesce((select json_agg(m.name order by m.joined_at) from members m where m.plan_code = p.code), '[]'::json),
    'count', (select count(*) from members m where m.plan_code = p.code),
    'tier', (select least(4, min(m.tier) + p.bonus) from members m where m.plan_code = p.code),
    'me_joined', exists (select 1 from members m where m.plan_code = p.code and m.device_id = p_device),
    'stretch_open', p.stretch_open,
    'stretch_round', p.stretch_round,
    'stretch_result', p.stretch_result,
    'votes_in', (select count(*) from members m where m.plan_code = p.code and p.stretch_open and m.vote_round = p.stretch_round),
    'me_voted', exists (select 1 from members m where m.plan_code = p.code and m.device_id = p_device and m.vote_round = p.stretch_round)
  )
  from plans p where p.code = p_code;
$$;

-- Open a private vote on going one budget level higher.
create or replace function public.start_stretch(p_code text)
returns void
language plpgsql security definer set search_path = public as $$
declare v_tier int;
begin
  select least(4, min(m.tier) + p.bonus) into v_tier
  from plans p join members m on m.plan_code = p.code
  where p.code = p_code group by p.bonus;
  if v_tier is null or v_tier >= 4 then return; end if;
  update plans set stretch_open = true, stretch_round = stretch_round + 1, stretch_result = null
  where code = p_code and not stretch_open;
end $$;

-- Cast a private yes/no. When everyone has voted, the result is decided.
create or replace function public.vote_stretch(p_code text, p_device text, p_yes boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare v_round int; v_open boolean; v_total int; v_votes int; v_yes int;
begin
  select stretch_round, stretch_open into v_round, v_open from plans where code = p_code for update;
  if not coalesce(v_open, false) then return; end if;
  update members set vote_round = v_round, vote_yes = p_yes where plan_code = p_code and device_id = p_device;
  select count(*),
         count(*) filter (where vote_round = v_round),
         count(*) filter (where vote_round = v_round and vote_yes)
    into v_total, v_votes, v_yes
  from members where plan_code = p_code;
  if v_votes >= v_total then
    if v_yes = v_total then
      update plans set bonus = bonus + 1, stretch_open = false, stretch_result = 'passed' where code = p_code;
    else
      update plans set stretch_open = false, stretch_result = 'stayed' where code = p_code;
    end if;
  end if;
end $$;

grant execute on function public.create_plan(text, text, text, double precision, double precision, int) to anon, authenticated;
grant execute on function public.join_plan(text, text, text, int) to anon, authenticated;
grant execute on function public.plan_status(text, text) to anon, authenticated;
grant execute on function public.start_stretch(text) to anon, authenticated;
grant execute on function public.vote_stretch(text, text, boolean) to anon, authenticated;
