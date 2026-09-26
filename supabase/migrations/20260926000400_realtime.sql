-- Realtime: postgres_changes on postcards. Realtime checks the postcards SELECT policy per
-- subscriber, so only the sender and recipient receive an event. Events are hints to refetch.

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end;
$$;

alter publication supabase_realtime add table public.postcards;
