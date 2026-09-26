-- Realtime carries postcard INSERTs only; that is all clients subscribe to (backend/README.md).
-- Postcards are immutable, so UPDATE events never carry meaning. DELETE events (for example from
-- an account deletion cascade) are not filtered by RLS in Realtime, so every subscriber of the
-- table would receive the deleted postcard's id.
--
-- Postgres sets the published operations per publication, not per table, so this applies to every
-- table in supabase_realtime. public.postcards is the only one Postcard adds; revisit this if a
-- table that needs UPDATE or DELETE events joins the publication.
alter publication supabase_realtime set (publish = 'insert');
