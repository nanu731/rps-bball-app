-- TEST ONLY platform stand-ins in a newly created, isolated database.
-- This is not Supabase Auth, a JWT gateway, Storage service or account recovery.
create schema auth;
comment on schema auth is 'TEST ONLY recovery drill platform stand-in';
create table auth.users (
 id uuid primary key, email text, phone text, email_confirmed_at timestamptz,
 phone_confirmed_at timestamptz, is_anonymous boolean default false, deleted_at timestamptz, banned_until timestamptz,
 raw_user_meta_data jsonb not null default '{}'
);
create table auth.sessions (
 id uuid primary key, user_id uuid not null references auth.users(id), not_after timestamptz
);
create function auth.jwt() returns jsonb language sql stable as $$
 select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb
$$;
create function auth.uid() returns uuid language sql stable as $$
 select (auth.jwt()->>'sub')::uuid
$$;
grant usage on schema auth to anon, authenticated, service_role;
revoke all on auth.users,auth.sessions from public,anon,authenticated;
create schema extensions;
grant usage on schema extensions to public; -- pgTAP helpers are called under all test roles, including service_role.
create schema storage;
create table storage.buckets (
 id text primary key, name text not null, public boolean not null default false,
 file_size_limit bigint, allowed_mime_types text[]
);
create table storage.objects (
 id uuid primary key, bucket_id text references storage.buckets(id), name text not null,
 unique(bucket_id,name)
);
alter table storage.objects enable row level security;
grant usage on schema storage to anon,authenticated;
grant select,insert,update,delete on storage.objects to anon,authenticated;
create schema supabase_migrations;
create table supabase_migrations.schema_migrations (
 version text primary key, name text, statements text[]
);
revoke all on schema supabase_migrations from public,anon,authenticated;
revoke all on supabase_migrations.schema_migrations from public,anon,authenticated;
alter table supabase_migrations.schema_migrations enable row level security;
