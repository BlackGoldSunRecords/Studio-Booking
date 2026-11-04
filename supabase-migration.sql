-- 7. Member booking details.
-- Only active, approved members and admins can see member names.
-- Show the booking host plus every participant who has accepted an invitation.
create or replace view public.member_space_booking_details as
  select
    b.id,
    b.starts_at,
    b.ends_at,
    b.space,
    coalesce(m.display_name, 'Member') as display_name
  from public.bookings b
  left join lateral (
    select string_agg(names.display_name, ', ' order by names.display_name) as display_name
    from (
      select p.display_name
      from public.profiles p
      where p.id = b.user_id

      union

      select p.display_name
      from public.booking_participants bp
      join public.profiles p on p.id = bp.user_id
      where bp.booking_id = b.id
        and bp.status = 'accepted'
    ) as names
  ) as m on true
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
