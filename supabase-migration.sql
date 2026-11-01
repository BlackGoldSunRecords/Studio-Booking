
-- Black Gold Sun Records
-- Separate Music Studio and Tattoo Space bookings and access.
-- Existing bookings remain assigned to Music Studio.
-- Run once in Supabase SQL Editor after backing up existing data.

create extension if not exists btree_gist;

-- 1. Add separate room permissions to member profiles.
alter table public.profiles
  add column if not exists music_access boolean not null default true,
  add column if not exists tattoo_access boolean not null default false;

-- Existing bookings already have a space column and valid space constraint.
-- Keep the existing bookings_space_check and no-overlap constraints intact.
-- Existing bookings remain assigned to Music Studio.

-- 2. Internal room-access check.
-- Only database functions and triggers should call this directly.
create or replace function public.bgs_can_access_space(
  p_user_id uuid,
  p_space text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = p_user_id
      and coalesce(p.is_suspended,false) = false
      and (
        coalesce(p.is_approved,false)
        or coalesce(p.is_admin,false)
      )
      and (
        coalesce(p.is_admin,false)
        or (p_space = 'music' and coalesce(p.music_access,false))
        or (p_space = 'tattoo' and coalesce(p.tattoo_access,false))
      )
  );
$$;

revoke all on function public.bgs_can_access_space(uuid,text)
  from public, anon, authenticated;

-- 3. Check the booking host has access before a booking
-- is created or its owner/space is changed.
create or replace function public.bgs_check_booking_space_access()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.space not in ('music','tattoo') then
    raise exception 'Unknown booking space';
  end if;

  if not public.bgs_can_access_space(new.user_id,new.space) then
    raise exception 'Your membership does not include access to this space';
  end if;

  return new;
end;
$$;

drop trigger if exists bgs_booking_space_access
  on public.bookings;

create trigger bgs_booking_space_access
before insert or update of user_id,space
on public.bookings
for each row
execute function public.bgs_check_booking_space_access();

-- 4. Check invited participants have access to the booked room.
-- Recheck permission when an invitation is accepted.
create or replace function public.bgs_check_participant_space_access()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  booking_space text;
begin
  -- Allow a member to decline their own invitation even if
  -- their room access has subsequently been revoked.
  -- Do not bypass the check if booking_id or user_id changes.
  if tg_op = 'UPDATE'
     and new.status = 'declined'
     and new.booking_id = old.booking_id
     and new.user_id = old.user_id then
    return new;
  end if;

  select b.space
  into booking_space
  from public.bookings b
  where b.id = new.booking_id;

  if booking_space is null then
    raise exception 'Booking not found';
  end if;

  if not public.bgs_can_access_space(new.user_id,booking_space) then
    raise exception 'This member does not have access to the booked space';
  end if;

  return new;
end;
$$;

drop trigger if exists bgs_participant_space_access
  on public.booking_participants;

create trigger bgs_participant_space_access
before insert or update of booking_id,user_id,status
on public.booking_participants
for each row
execute function public.bgs_check_participant_space_access();

-- 5. Admin-only room permission control.
create or replace function public.admin_set_member_access(
  p_user_id uuid,
  p_music_access boolean,
  p_tattoo_access boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and is_admin = true
      and coalesce(is_suspended,false) = false
  ) then
    raise exception 'Admin access required';
  end if;

  update public.profiles
  set music_access = coalesce(p_music_access,false),
      tattoo_access = coalesce(p_tattoo_access,false)
  where id = p_user_id;

  if not found then
    raise exception 'Member profile not found';
  end if;
end;
$$;

revoke all on function public.admin_set_member_access(uuid,boolean,boolean)
  from public, anon, authenticated;

grant execute on function public.admin_set_member_access(uuid,boolean,boolean)
  to authenticated;

-- 6. Public calendar: confirmed booking times and room only.
create or replace view public.public_space_availability as
  select starts_at, ends_at, space
  from public.bookings
  where status = 'confirmed';

grant select on public.public_space_availability
  to anon, authenticated;

-- 7. Member booking details.
-- Only active, approved members and admins can see member names.
create or replace view public.member_space_booking_details as
  select
    b.id,
    b.starts_at,
    b.ends_at,
    b.space,
    coalesce(p.display_name,'Member') as display_name
  from public.bookings b
  left join public.profiles p on p.id = b.user_id
  where b.status = 'confirmed'
    and exists (
      select 1
      from public.profiles viewer
      where viewer.id = auth.uid()
        and coalesce(viewer.is_suspended,false) = false
        and (
          coalesce(viewer.is_approved,false)
          or coalesce(viewer.is_admin,false)
        )
    );

revoke all on public.member_space_booking_details from public, anon;
grant select on public.member_space_booking_details to authenticated;

-- 8. Access-controlled directory for invitation pickers.
create or replace view public.approved_space_member_directory as
  select
    p.id,
    p.display_name,
    p.music_access,
    p.tattoo_access
  from public.profiles p
  where (p.is_approved = true or p.is_admin = true)
    and coalesce(p.is_suspended,false) = false
    and exists (
      select 1
      from public.profiles viewer
      where viewer.id = auth.uid()
        and coalesce(viewer.is_suspended,false) = false
        and (
          coalesce(viewer.is_approved,false)
          or coalesce(viewer.is_admin,false)
        )
    );

revoke all on public.approved_space_member_directory from public, anon;
grant select on public.approved_space_member_directory to authenticated;

-- 9. Invitation details, retaining the existing invitation view's
-- recipient filtering and adding the room attached to each booking.
create or replace view public.member_space_invitation_details as
  select
    i.invitation_id,
    i.booking_id,
    i.starts_at,
    i.ends_at,
    i.host_name,
    b.space
  from public.member_invitation_details i
  join public.bookings b on b.id = i.booking_id
  where exists (
    select 1
    from public.profiles viewer
    where viewer.id = auth.uid()
      and coalesce(viewer.is_suspended,false) = false
      and (
        coalesce(viewer.is_approved,false)
        or coalesce(viewer.is_admin,false)
      )
  );

revoke all on public.member_space_invitation_details from public, anon;
grant select on public.member_space_invitation_details to authenticated;

-- 10. Admin-only member directory, including email and room permissions.
create or replace function public.admin_list_space_members()
returns table (
  id uuid,
  display_name text,
  email text,
  is_admin boolean,
  is_approved boolean,
  is_suspended boolean,
  music_access boolean,
  tattoo_access boolean
)
language plpgsql
security definer
set search_path = public,auth
as $$
begin
  if not exists (
    select 1
    from public.profiles
    where profiles.id = auth.uid()
      and profiles.is_admin = true
      and coalesce(profiles.is_suspended,false) = false
  ) then
    raise exception 'Admin access required';
  end if;

  return query
    select
      p.id,
      p.display_name,
      u.email,
      coalesce(p.is_admin,false),
      coalesce(p.is_approved,false),
      coalesce(p.is_suspended,false),
      (coalesce(p.music_access,false) or coalesce(p.is_admin,false)),
      (coalesce(p.tattoo_access,false) or coalesce(p.is_admin,false))
    from public.profiles p
    left join auth.users u on u.id = p.id
    order by p.display_name nulls last;
end;
$$;

revoke all on function public.admin_list_space_members()
  from public, anon, authenticated;

grant execute on function public.admin_list_space_members()
  to authenticated;

-- 11. Admin-only confirmed booking list.
create or replace function public.admin_list_space_bookings()
returns table (
  id uuid,
  member_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  status text,
  space text
)
language plpgsql
security definer
set search_path = public,auth
as $$
begin
  if not exists (
    select 1
    from public.profiles
    where profiles.id = auth.uid()
      and profiles.is_admin = true
      and coalesce(profiles.is_suspended,false) = false
  ) then
    raise exception 'Admin access required';
  end if;

  return query
    select
      b.id,
      coalesce(p.display_name,'Member'),
      b.starts_at,
      b.ends_at,
      b.status::text,
      b.space
    from public.bookings b
    left join public.profiles p on p.id = b.user_id
    where b.status = 'confirmed'
    order by b.starts_at;
end;
$$;

revoke all on function public.admin_list_space_bookings()
  from public, anon, authenticated;

grant execute on function public.admin_list_space_bookings()
  to authenticated;

-- Refresh the PostgREST schema cache.
notify pgrst, 'reload schema';
