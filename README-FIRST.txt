BLACK GOLD SUN — PRIVATE WEBSITE UPDATE

Included
- index.html: updated private-members website with separate Music Studio and Tattoo Space booking forms. Both calendars show all confirmed bookings in both rooms, with each booking labelled by room.
- assets/black-gold-sun-logo.png: bundled transparent white logo used in the header and calendar watermark.
- assets/logo-cursor.png: compact logo cursor for desktop pointers (touch devices retain normal controls).
- supabase-migration.sql: additive database migration for room-specific bookings, access permissions and overlap handling.

IMPORTANT — DATABASE STEP REQUIRED
The website and database must be updated together. The migration has been prepared from the current website schema references but has NOT been executed or verified against your live Supabase database. Do not run it or upload the new website yet. First, we should review the migration against the live table/function definitions together in Supabase SQL Editor and take a database backup. Then apply it once and test both calendars. The migration replaces the confirmed existing exclusion constraint named "no overlapping bookings" with a room-specific rule. It preserves existing bookings and marks them as Music Studio bookings. Existing approved members retain Music Studio access; Tattoo Space access starts disabled until you grant it in the admin dashboard.

After the migration succeeds, upload index.html and the assets folder together to the website host. Keep the folder structure exactly as shown. The website ZIP does not deploy itself and does not overwrite the live site merely by being downloaded.

Notes
- The site continues to use the existing Supabase project and public anon/publishable key; no service-role key is included.
- The existing invitation workflow is reused. The invitation picker only lists members with access to the relevant space, and a database trigger prevents participants without access from joining.
- Both calendars show occupancy in both rooms because the kitchen and shared facilities are communal. Calendar watermarks are intentionally faint so dates and booking markers remain readable.
- Test with one Music-only member, one Tattoo-only member and one Both member before opening bookings to everyone.

If the live schema differs from the assumptions in the migration, we will adjust the SQL before running it. Do not upload the website until the migration has been successfully applied and both calendars have been tested.
