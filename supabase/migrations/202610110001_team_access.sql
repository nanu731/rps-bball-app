-- Team administration only. No local-record upload or privileged client bootstrap.
begin;
create schema if not exists team_private;
revoke all on schema team_private from public, anon, authenticated;

create function team_private.capabilities() returns text[] language sql immutable
set search_path = pg_catalog as $$
  select array['stats.review','stats.publish','datasets.reopen','roster.manage',
    'members.manage','plays.author','plays.review','plays.publish','practice.upload',
    'practice.review','practice.publish','film.upload','film.review','film.publish']::text[]
$$;

create table public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 100),
  owner_auth_uuid uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
create table public.team_memberships (
  team_id uuid not null references public.teams(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  status text not null check (status in ('pending','active','removed')),
  updated_at timestamptz not null default now(),
  primary key (team_id, user_id)
);
create table public.delegation_envelopes (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete restrict,
  delegate_user_id uuid not null,
  allowed_capabilities text[] not null check (
    cardinality(allowed_capabilities) > 0 and
    array_position(allowed_capabilities, null) is null and
    allowed_capabilities <@ team_private.capabilities()),
  expires_at timestamptz not null check (isfinite(expires_at)),
  issued_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  foreign key (team_id, delegate_user_id) references public.team_memberships(team_id, user_id),
  unique (team_id, id)
);
create table public.capability_grants (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete restrict,
  user_id uuid not null,
  capability text not null check (capability = any(team_private.capabilities())),
  issued_by uuid not null references auth.users(id) on delete restrict,
  envelope_id uuid,
  expires_at timestamptz check (expires_at is null or isfinite(expires_at)),
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  foreign key (team_id, user_id) references public.team_memberships(team_id,user_id),
  foreign key (team_id, envelope_id) references public.delegation_envelopes(team_id,id)
);
create unique index capability_grants_current on public.capability_grants(team_id,user_id,capability)
where revoked_at is null;
create index delegation_envelopes_member on public.delegation_envelopes(team_id,delegate_user_id);
create table public.roster_entries (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete restrict,
  display_name text not null check (length(btrim(display_name)) between 1 and 100),
  jersey_number text not null check (length(btrim(jersey_number)) between 1 and 10),
  -- Fresh server identities represent real players only; temporary local IDs are never imported.
  identity_kind text not null default 'real' check (identity_kind='real'),
  version bigint not null default 1 check (version > 0),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  unique (team_id,id)
);
create table public.roster_entry_revisions (
  roster_id uuid not null,
  team_id uuid not null,
  version bigint not null,
  display_name text not null,
  jersey_number text not null,
  archived_at timestamptz,
  recorded_at timestamptz not null default now(),
  primary key (roster_id,version),
  foreign key (team_id,roster_id) references public.roster_entries(team_id,id) on delete restrict
);
create table public.team_audit_events (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  action text not null,
  target_id uuid,
  capability text,
  recorded_at timestamptz not null default now()
);

-- A subject string alone is insufficient: Auth must have verified it and retained its session.
-- The gateway validates the signed JWT; this additionally blocks a still-unexpired JWT
-- immediately after its server session is removed. No app/user metadata is trusted.
create function team_private.actor() returns uuid language sql stable security definer
set search_path = pg_catalog as $$
  select u.id from auth.users u join auth.sessions s on s.user_id=u.id
  where u.id=auth.uid() and s.id=(auth.jwt()->>'session_id')::uuid
    and (u.email_confirmed_at is not null or u.phone_confirmed_at is not null)
    and u.is_anonymous is not true
    and coalesce((auth.jwt()->>'is_anonymous')::boolean,false)=false
    and (auth.jwt()->>'exp')::numeric > extract(epoch from clock_timestamp())
    and (s.not_after is null or s.not_after > clock_timestamp())
$$;
create function team_private.is_active(p_team uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = pg_catalog as $$
  select exists(select 1 from public.team_memberships
    where team_id=p_team and user_id=p_user and status='active')
$$;
create function team_private.is_owner(p_team uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = pg_catalog as $$
  select exists(select 1 from public.teams where id=p_team and owner_auth_uuid=p_user)
$$;
create function team_private.has_capability(p_team uuid, p_user uuid, p_capability text)
returns boolean language sql stable security definer set search_path = pg_catalog as $$
  select team_private.is_active(p_team,p_user) and
    (team_private.is_owner(p_team,p_user) or exists (
      select 1 from public.capability_grants g
      left join public.delegation_envelopes e on e.id=g.envelope_id and e.team_id=g.team_id
      where g.team_id=p_team and g.user_id=p_user and g.capability=p_capability
        and g.revoked_at is null and (g.expires_at is null or g.expires_at > clock_timestamp())
        and (g.envelope_id is null or (
          e.revoked_at is null and e.expires_at > clock_timestamp()
          and e.delegate_user_id=g.issued_by
          and g.capability=any(e.allowed_capabilities)
          and g.expires_at <= e.expires_at
          and team_private.is_active(p_team,e.delegate_user_id)))))
$$;
create function team_private.can_read(p_team uuid) returns boolean
language sql stable security definer set search_path = pg_catalog as $$
  select team_private.is_active(p_team,team_private.actor())
$$;
create function team_private.can_admin_read(p_team uuid) returns boolean
language sql stable security definer set search_path = pg_catalog as $$
  select team_private.can_read(p_team) and (
    team_private.is_owner(p_team,team_private.actor()) or
    team_private.has_capability(p_team,team_private.actor(),'members.manage') or exists (
      select 1 from public.delegation_envelopes where team_id=p_team
      and delegate_user_id=team_private.actor() and revoked_at is null
      and expires_at > clock_timestamp()))
$$;
create function team_private.can_owner_read(p_team uuid) returns boolean
language sql stable security definer set search_path = pg_catalog as $$
  select team_private.can_read(p_team) and team_private.is_owner(p_team,team_private.actor())
$$;
-- Serialize commands on the team before rechecking current membership/grants.
-- Hold the Auth session row too, so concurrent session removal waits for this command.
create function team_private.command_actor(p_team uuid) returns uuid
language plpgsql security definer set search_path = pg_catalog as $$
declare v_actor uuid;
begin
  perform 1 from public.teams where id=p_team for update;
  if not found then raise exception 'Team access denied' using errcode='42501'; end if;
  v_actor := team_private.actor();
  if v_actor is null then raise exception 'Verified session required' using errcode='42501'; end if;
  perform 1 from auth.sessions where id=(auth.jwt()->>'session_id')::uuid and user_id=v_actor
    and (not_after is null or not_after > clock_timestamp()) for share;
  if not found or team_private.actor() is null or not team_private.is_active(p_team,v_actor) then
    raise exception 'Active membership required' using errcode='42501';
  end if;
  return v_actor;
end $$;
create function team_private.audit(p_team uuid,p_actor uuid,p_action text,p_target uuid default null,p_cap text default null)
returns void language sql security definer set search_path = pg_catalog as $$
  insert into public.team_audit_events(team_id,actor_user_id,action,target_id,capability)
  values(p_team,p_actor,p_action,p_target,p_cap)
$$;
create function team_private.append_only() returns trigger language plpgsql
set search_path = pg_catalog as $$
begin raise exception 'History is append-only' using errcode='42501'; end $$;
create trigger audit_append_only before update or delete on public.team_audit_events
for each row execute function team_private.append_only();
create trigger roster_history_append_only before update or delete on public.roster_entry_revisions
for each row execute function team_private.append_only();
create function team_private.protect_owner() returns trigger language plpgsql security definer
set search_path = pg_catalog as $$
begin
  if tg_op='DELETE' or new.id<>old.id or new.owner_auth_uuid<>old.owner_auth_uuid then
    raise exception 'Team owner identity is immutable' using errcode='42501';
  end if;
  return new;
end $$;
create trigger immutable_team_owner before update or delete on public.teams
for each row execute function team_private.protect_owner();
create function team_private.protect_owner_membership() returns trigger language plpgsql security definer
set search_path = pg_catalog as $$
begin
  if tg_op <> 'INSERT' and team_private.is_owner(old.team_id,old.user_id) then
    if tg_op='DELETE' or new.team_id<>old.team_id or new.user_id<>old.user_id or new.status<>'active' then
      raise exception 'Owner membership is protected' using errcode='42501';
    end if;
  elsif tg_op='INSERT' and team_private.is_owner(new.team_id,new.user_id) and new.status<>'active' then
    raise exception 'Owner membership must be active' using errcode='42501';
  end if;
  return case when tg_op='DELETE' then old else new end;
end $$;
create trigger protect_owner_membership before insert or update or delete on public.team_memberships
for each row execute function team_private.protect_owner_membership();
create function team_private.bootstrap_owner() returns trigger language plpgsql security definer
set search_path = pg_catalog as $$
begin
  if not exists(select 1 from auth.users where id=new.owner_auth_uuid
    and (email_confirmed_at is not null or phone_confirmed_at is not null) and is_anonymous is not true) then
    raise exception 'Bootstrap requires actual verified Auth UUID' using errcode='42501';
  end if;
  insert into public.team_memberships(team_id,user_id,status) values(new.id,new.owner_auth_uuid,'active');
  perform team_private.audit(new.id,new.owner_auth_uuid,'team.bootstrapped',new.owner_auth_uuid);
  return new;
end $$;
create trigger bootstrap_verified_owner after insert on public.teams
for each row execute function team_private.bootstrap_owner();
create function team_private.roster_history() returns trigger language plpgsql security definer
set search_path = pg_catalog as $$
begin
  if tg_op='DELETE' then raise exception 'Archive roster entries instead' using errcode='42501'; end if;
  if tg_op='UPDATE' and (new.id<>old.id or new.team_id<>old.team_id or new.identity_kind<>old.identity_kind
    or old.archived_at is not null or new.version<>old.version+1) then
    raise exception 'Roster identity/history protected' using errcode='42501';
  end if;
  insert into public.roster_entry_revisions(roster_id,team_id,version,display_name,jersey_number,archived_at)
  values(new.id,new.team_id,new.version,new.display_name,new.jersey_number,new.archived_at);
  return new;
end $$;
-- AFTER ensures the referenced entry exists; any invalid update rolls back atomically.
create trigger record_roster_history after insert or update or delete on public.roster_entries
for each row execute function team_private.roster_history();

create function public.team_request_membership(p_team_id uuid) returns text
language plpgsql security definer set search_path = pg_catalog as $$
declare v_actor uuid;
begin
  perform 1 from public.teams where id=p_team_id for update;
  if not found then raise exception 'Team access denied' using errcode='42501'; end if;
  v_actor := team_private.actor();
  if v_actor is null then raise exception 'Verified session required' using errcode='42501'; end if;
  perform 1 from auth.sessions where id=(auth.jwt()->>'session_id')::uuid and user_id=v_actor for share;
  if not found or team_private.actor() is null then raise exception 'Verified session required' using errcode='42501'; end if;
  insert into public.team_memberships(team_id,user_id,status) values(p_team_id,v_actor,'pending')
  on conflict(team_id,user_id) do nothing;
  if found then perform team_private.audit(p_team_id,v_actor,'membership.requested',v_actor); end if;
  return (select status from public.team_memberships where team_id=p_team_id and user_id=v_actor);
end $$;
create function public.team_set_membership(p_team_id uuid,p_user_id uuid,p_status text) returns void
language plpgsql security definer set search_path = pg_catalog as $$
declare v_actor uuid := team_private.command_actor(p_team_id);
begin
  if not team_private.has_capability(p_team_id,v_actor,'members.manage') or p_user_id=v_actor
    or team_private.is_owner(p_team_id,p_user_id) then
    raise exception 'Membership administration denied' using errcode='42501';
  end if;
  if p_status not in ('pending','active','removed') or p_status is null then
    raise exception 'Invalid membership status' using errcode='22023';
  end if;
  if not exists(select 1 from auth.users where id=p_user_id and is_anonymous is not true
    and (email_confirmed_at is not null or phone_confirmed_at is not null)) then
    raise exception 'Verified account required' using errcode='42501';
  end if;
  insert into public.team_memberships(team_id,user_id,status) values(p_team_id,p_user_id,p_status)
  on conflict(team_id,user_id) do update set status=excluded.status,updated_at=now();
  -- Admission restoration must not restore old operational or grant authority.
  if p_status<>'active' then
    update public.capability_grants set revoked_at=now() where team_id=p_team_id and user_id=p_user_id and revoked_at is null;
    update public.delegation_envelopes set revoked_at=now() where team_id=p_team_id and delegate_user_id=p_user_id and revoked_at is null;
  end if;
  perform team_private.audit(p_team_id,v_actor,'membership.'||p_status,p_user_id);
end $$;

create function public.team_delegate(p_team_id uuid,p_user_id uuid,p_allowed_capabilities text[],p_expires_at timestamptz)
returns uuid language plpgsql security definer set search_path = pg_catalog as $$
declare v_actor uuid := team_private.command_actor(p_team_id); v_id uuid;
begin
  if not team_private.is_owner(p_team_id,v_actor) or p_user_id=v_actor
    or not team_private.is_active(p_team_id,p_user_id) then
    raise exception 'Only owner may delegate to another active member' using errcode='42501';
  end if;
  if p_expires_at is null or not isfinite(p_expires_at) or p_expires_at<=clock_timestamp()
    or p_allowed_capabilities is null or cardinality(p_allowed_capabilities)=0
    or array_position(p_allowed_capabilities,null) is not null
    or not p_allowed_capabilities <@ team_private.capabilities() then
    raise exception 'Explicit capabilities and future finite expiry required' using errcode='22023';
  end if;
  insert into public.delegation_envelopes(team_id,delegate_user_id,allowed_capabilities,expires_at,issued_by)
  values(p_team_id,p_user_id,p_allowed_capabilities,p_expires_at,v_actor) returning id into v_id;
  perform team_private.audit(p_team_id,v_actor,'delegation.issued',v_id);
  return v_id;
end $$;
create function public.team_revoke_delegation(p_team_id uuid,p_envelope_id uuid) returns void
language plpgsql security definer set search_path = pg_catalog as $$
declare v_actor uuid := team_private.command_actor(p_team_id);
begin
  if not team_private.is_owner(p_team_id,v_actor) then
    raise exception 'Only owner may revoke delegation' using errcode='42501';
  end if;
  update public.delegation_envelopes set revoked_at=coalesce(revoked_at,now()) where team_id=p_team_id and id=p_envelope_id;
  if not found then raise exception 'Delegation not found' using errcode='22023'; end if;
  perform team_private.audit(p_team_id,v_actor,'delegation.revoked',p_envelope_id);
end $$;
create function public.team_set_capability(p_team_id uuid,p_user_id uuid,p_capability text,p_enabled boolean,p_expires_at timestamptz default null)
returns void language plpgsql security definer set search_path = pg_catalog as $$
declare v_actor uuid := team_private.command_actor(p_team_id); v_envelope uuid; v_expiry timestamptz := p_expires_at;
begin
  if p_user_id=v_actor or team_private.is_owner(p_team_id,p_user_id) or not team_private.is_active(p_team_id,p_user_id) then
    raise exception 'Grant target must be another active nonowner member' using errcode='42501';
  end if;
  if p_enabled is null or p_capability is null or not p_capability=any(team_private.capabilities()) then
    raise exception 'Invalid capability command' using errcode='22023';
  end if;
  if not team_private.is_owner(p_team_id,v_actor) then
    select id, coalesce(p_expires_at,expires_at) into v_envelope,v_expiry from public.delegation_envelopes
    where team_id=p_team_id and delegate_user_id=v_actor and revoked_at is null
      and expires_at>clock_timestamp() and p_capability=any(allowed_capabilities)
      and (p_expires_at is null or p_expires_at<=expires_at)
    order by expires_at desc limit 1;
    if v_envelope is null then raise exception 'Bounded grant authority required' using errcode='42501'; end if;
  end if;
  if v_expiry is not null and (not isfinite(v_expiry) or v_expiry<=clock_timestamp()) then
    raise exception 'Future finite grant expiry required' using errcode='22023';
  end if;
  update public.capability_grants set revoked_at=now()
  where team_id=p_team_id and user_id=p_user_id and capability=p_capability and revoked_at is null;
  if p_enabled then
    insert into public.capability_grants(team_id,user_id,capability,issued_by,envelope_id,expires_at)
    values(p_team_id,p_user_id,p_capability,v_actor,v_envelope,v_expiry);
  end if;
  perform team_private.audit(p_team_id,v_actor,case when p_enabled then 'capability.granted' else 'capability.revoked' end,p_user_id,p_capability);
end $$;

create function public.team_save_roster(p_team_id uuid,p_display_name text,p_jersey_number text,p_roster_id uuid default null,p_expected_version bigint default null)
returns uuid language plpgsql security definer set search_path = pg_catalog as $$
declare v_actor uuid := team_private.command_actor(p_team_id); v_entry public.roster_entries; v_id uuid;
begin
  if not team_private.has_capability(p_team_id,v_actor,'roster.manage') then
    raise exception 'Roster administration denied' using errcode='42501';
  end if;
  if p_display_name is null or length(btrim(p_display_name)) not between 1 and 100
    or p_jersey_number is null or length(btrim(p_jersey_number)) not between 1 and 10 then
    raise exception 'Player name and jersey number required' using errcode='22023';
  end if;
  if p_roster_id is null then
    insert into public.roster_entries(team_id,display_name,jersey_number)
    values(p_team_id,btrim(p_display_name),btrim(p_jersey_number)) returning id into v_id;
  else
    select * into v_entry from public.roster_entries where team_id=p_team_id and id=p_roster_id;
    if not found or v_entry.archived_at is not null then raise exception 'Roster entry unavailable' using errcode='42501'; end if;
    if p_expected_version is null or v_entry.version<>p_expected_version then
      raise exception 'Roster version changed' using errcode='40001';
    end if;
    update public.roster_entries set display_name=btrim(p_display_name),jersey_number=btrim(p_jersey_number),version=version+1
    where team_id=p_team_id and id=p_roster_id;
    v_id := p_roster_id;
  end if;
  perform team_private.audit(p_team_id,v_actor,case when p_roster_id is null then 'roster.added' else 'roster.edited' end,v_id);
  return v_id;
end $$;
create function public.team_archive_roster(p_team_id uuid,p_roster_id uuid,p_expected_version bigint) returns void
language plpgsql security definer set search_path = pg_catalog as $$
declare v_actor uuid := team_private.command_actor(p_team_id); v_entry public.roster_entries;
begin
  if not team_private.has_capability(p_team_id,v_actor,'roster.manage') then
    raise exception 'Roster administration denied' using errcode='42501';
  end if;
  select * into v_entry from public.roster_entries where team_id=p_team_id and id=p_roster_id;
  if not found or v_entry.archived_at is not null then raise exception 'Roster entry unavailable' using errcode='42501'; end if;
  if p_expected_version is null or v_entry.version<>p_expected_version then raise exception 'Roster version changed' using errcode='40001'; end if;
  update public.roster_entries set archived_at=now(),version=version+1 where team_id=p_team_id and id=p_roster_id;
  perform team_private.audit(p_team_id,v_actor,'roster.archived',p_roster_id);
end $$;
create function public.team_access(p_team_id uuid) returns jsonb
language plpgsql stable security definer set search_path = pg_catalog as $$
declare v_actor uuid := team_private.actor(); v_caps jsonb; v_envelopes jsonb;
begin
  if v_actor is null or not team_private.is_active(p_team_id,v_actor) then
    raise exception 'Active membership required' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(c),'[]'::jsonb) into v_caps from unnest(team_private.capabilities()) c
  where team_private.has_capability(p_team_id,v_actor,c);
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'allowed_capabilities',allowed_capabilities,'expires_at',expires_at)),'[]'::jsonb)
  into v_envelopes from public.delegation_envelopes
  where team_id=p_team_id and delegate_user_id=v_actor and revoked_at is null and expires_at>clock_timestamp();
  return jsonb_build_object('team_id',p_team_id,'user_id',v_actor,'is_owner',team_private.is_owner(p_team_id,v_actor),
    'can_propose_stats',true,'capabilities',v_caps,'grant_envelopes',v_envelopes);
end $$;

alter table public.teams enable row level security;
alter table public.team_memberships enable row level security;
alter table public.capability_grants enable row level security;
alter table public.delegation_envelopes enable row level security;
alter table public.roster_entries enable row level security;
alter table public.roster_entry_revisions enable row level security;
alter table public.team_audit_events enable row level security;
create policy teams_active_read on public.teams for select to authenticated using (team_private.can_read(id));
create policy roster_active_read on public.roster_entries for select to authenticated using (team_private.can_read(team_id));
create policy roster_history_active_read on public.roster_entry_revisions for select to authenticated using (team_private.can_read(team_id));
create policy membership_admin_read on public.team_memberships for select to authenticated using (team_private.can_admin_read(team_id));
create policy grants_admin_read on public.capability_grants for select to authenticated using (team_private.can_admin_read(team_id));
create policy envelopes_admin_read on public.delegation_envelopes for select to authenticated using (team_private.can_admin_read(team_id));
create policy audit_owner_read on public.team_audit_events for select to authenticated
using (team_private.can_owner_read(team_id));

revoke all on public.teams,public.team_memberships,public.capability_grants,public.delegation_envelopes,
  public.roster_entries,public.roster_entry_revisions,public.team_audit_events from public,anon,authenticated;
grant select on public.teams,public.team_memberships,public.capability_grants,public.delegation_envelopes,
  public.roster_entries,public.roster_entry_revisions,public.team_audit_events to authenticated;
revoke execute on all functions in schema team_private from public,anon,authenticated;
-- RLS predicates alone are callable from clients; privileged helpers remain inaccessible.
grant usage on schema team_private to authenticated;
grant execute on function team_private.can_read(uuid),team_private.can_admin_read(uuid),
  team_private.can_owner_read(uuid) to authenticated;
revoke execute on function public.team_request_membership(uuid),public.team_set_membership(uuid,uuid,text),
  public.team_delegate(uuid,uuid,text[],timestamptz),public.team_revoke_delegation(uuid,uuid),
  public.team_set_capability(uuid,uuid,text,boolean,timestamptz),public.team_save_roster(uuid,text,text,uuid,bigint),
  public.team_archive_roster(uuid,uuid,bigint),public.team_access(uuid) from public,anon,authenticated;
grant execute on function public.team_request_membership(uuid),public.team_set_membership(uuid,uuid,text),
  public.team_delegate(uuid,uuid,text[],timestamptz),public.team_revoke_delegation(uuid,uuid),
  public.team_set_capability(uuid,uuid,text,boolean,timestamptz),public.team_save_roster(uuid,text,text,uuid,bigint),
  public.team_archive_roster(uuid,uuid,bigint),public.team_access(uuid) to authenticated;
commit;
