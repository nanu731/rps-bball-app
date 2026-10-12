-- Accepted-version export snapshots. No destination or provider is activated.
begin;
create table public.stat_export_destinations (
  team_id uuid primary key references public.teams(id),
  spreadsheet_id text not null unique check(spreadsheet_id ~ '^[A-Za-z0-9_-]{1,200}$'),
  ledger_sheet_id integer not null check(ledger_sheet_id>=0),
  snapshot_min integer not null check(snapshot_min>=0),
  snapshot_max integer not null check(snapshot_max>=snapshot_min),
  ledger_rows integer not null check(ledger_rows between 2 and 100001),
  next_sheet_id bigint not null,
  next_ledger_row integer not null default 1,
  check(ledger_sheet_id not between snapshot_min and snapshot_max)
);
create table public.stat_export_snapshots (
  job_id uuid primary key references public.stat_export_outbox(id),
  team_id uuid not null references public.teams(id),
  accepted_version_id uuid not null unique references public.stat_versions(id),
  payload_text text not null,
  payload_sha256 text not null check(payload_sha256 ~ '^[a-f0-9]{64}$'),
  check(payload_sha256=encode(sha256(convert_to(payload_text,'UTF8')),'hex'))
);
create trigger export_snapshot_append_only before update or delete on public.stat_export_snapshots
  for each row execute function team_private.append_only();
create table public.stat_export_deliveries (
  job_id uuid primary key references public.stat_export_snapshots(job_id),
  team_id uuid not null references public.teams(id),
  spreadsheet_id text,
  sheet_id integer check(sheet_id>=0),
  ledger_sheet_id integer check(ledger_sheet_id>=0),
  ledger_row integer check(ledger_row>=1),
  state text not null default 'queued' check(state in ('queued','reserved','failed','delivered')),
  attempts bigint not null default 0 check(attempts>=0),
  error_code text,
  delivered_at timestamptz,
  updated_at timestamptz not null default now(),
  unique(spreadsheet_id,sheet_id), unique(spreadsheet_id,ledger_row),
  check((spreadsheet_id is null and sheet_id is null and ledger_sheet_id is null and ledger_row is null)
    or (spreadsheet_id is not null and sheet_id is not null and ledger_sheet_id is not null and ledger_row is not null)),
  check((state='delivered')=(delivered_at is not null))
);
create function team_private.export_capture() returns trigger
language plpgsql security definer set search_path=pg_catalog as $$
declare v public.stat_versions; g public.games; labels jsonb; payload text;
begin
  select * into v from public.stat_versions where id=new.accepted_version_id;
  select * into g from public.games where id=new.game_id;
  if v.status is distinct from 'published' or v.team_id is distinct from new.team_id
    or v.game_id is distinct from new.game_id or g.team_id is distinct from new.team_id then
    raise exception 'Only accepted team datasets may be exported' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',h.roster_id,'version',h.version,
    'display_name',h.display_name,'jersey_number',h.jersey_number) order by h.roster_id),'[]'::jsonb)
    into labels from jsonb_array_elements(v.covered_roster) r
    join public.roster_entry_revisions h on h.roster_id=(r->>'id')::uuid and h.version=(r->>'version')::bigint
    join public.roster_entries e on e.id=h.roster_id
    where h.team_id=new.team_id and e.identity_kind='real';
  if jsonb_array_length(labels)<>jsonb_array_length(v.covered_roster) then
    raise exception 'Accepted historical roster required' using errcode='22023';
  end if;
  payload := jsonb_build_object('schema',1,'team_id',new.team_id,
    'accepted_version_id',v.id,'dataset_id',v.dataset_id,'dataset_type',v.dataset_type,
    'revision',v.revision,'publication_generation',new.publication_generation,
    'game',jsonb_build_object('id',g.id,'date',g.date,'opponent',g.opponent,
      'home_away',g.home_away,'game_type',g.game_type),'records',v.records,'roster',labels)::text;
  insert into public.stat_export_snapshots(job_id,team_id,accepted_version_id,payload_text,payload_sha256)
    values(new.id,new.team_id,v.id,payload,encode(sha256(convert_to(payload,'UTF8')),'hex'));
  insert into public.stat_export_deliveries(job_id,team_id) values(new.id,new.team_id);
  return new;
end $$;
create trigger capture_accepted_export after insert on public.stat_export_outbox
  for each row execute function team_private.export_capture();
-- Backfill existing immutable accepted outbox facts, without modifying them.
-- Reuse the exact capture trigger contract through a temporary relation.
create temporary table export_backfill (like public.stat_export_outbox including defaults) on commit drop;
create trigger capture_export_backfill after insert on export_backfill
  for each row execute function team_private.export_capture();
insert into export_backfill select * from public.stat_export_outbox;

create function team_private.export_service() returns void language plpgsql set search_path=pg_catalog as $$
begin
  if current_setting('role',true) is distinct from 'service_role' then
    raise exception 'Trusted export runtime required' using errcode='42501';
  end if;
end $$;
create function public.stats_export_configure(p_team_id uuid,p_spreadsheet_id text,p_ledger_sheet_id integer,
  p_snapshot_min integer,p_snapshot_max integer,p_ledger_rows integer) returns void
language plpgsql security definer set search_path=pg_catalog as $$
declare existing public.stat_export_destinations;
begin
  perform team_private.export_service();
  perform 1 from public.teams where id=p_team_id for update;
  if not found then raise exception 'Unknown team' using errcode='22023'; end if;
  select * into existing from public.stat_export_destinations where team_id=p_team_id;
  if found then
    if existing.spreadsheet_id is distinct from p_spreadsheet_id
      or existing.ledger_sheet_id is distinct from p_ledger_sheet_id
      or existing.snapshot_min is distinct from p_snapshot_min or existing.snapshot_max is distinct from p_snapshot_max
      or existing.ledger_rows is distinct from p_ledger_rows then
      raise exception 'Export destination is already bound' using errcode='40001';
    end if;
    return;
  end if;
  if p_spreadsheet_id is null or p_spreadsheet_id !~ '^[A-Za-z0-9_-]{1,200}$'
    or p_ledger_sheet_id is null or p_ledger_sheet_id<0 or p_snapshot_min is null or p_snapshot_min<0
    or p_snapshot_max is null or p_snapshot_max<p_snapshot_min or p_ledger_rows is null
    or p_ledger_rows not between 2 and 100001 or p_ledger_sheet_id between p_snapshot_min and p_snapshot_max then
    raise exception 'Bounded disjoint destination ranges required' using errcode='22023';
  end if;
  insert into public.stat_export_destinations(team_id,spreadsheet_id,ledger_sheet_id,snapshot_min,snapshot_max,ledger_rows,next_sheet_id)
    values(p_team_id,p_spreadsheet_id,p_ledger_sheet_id,p_snapshot_min,p_snapshot_max,p_ledger_rows,p_snapshot_min);
end $$;
create function public.stats_export_jobs(p_limit integer default 3) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
begin
  perform team_private.export_service();
  if p_limit is null or p_limit not between 1 and 10 then raise exception 'Bounded job count required' using errcode='22023'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('job_id',q.job_id)),'[]'::jsonb) from
    (select d.job_id from public.stat_export_deliveries d join public.stat_export_outbox o on o.id=d.job_id
      where d.state<>'delivered' order by d.updated_at,o.created_at,o.id limit p_limit) q);
end $$;
create function public.stats_export_reserve(p_job_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare s public.stat_export_snapshots; d public.stat_export_deliveries; config public.stat_export_destinations;
begin
  perform team_private.export_service();
  select * into s from public.stat_export_snapshots where job_id=p_job_id;
  if not found then raise exception 'Unknown accepted export' using errcode='22023'; end if;
  -- Same team-first ordering as publishing; concurrent workers receive one reservation.
  perform 1 from public.teams where id=s.team_id for update;
  select * into d from public.stat_export_deliveries where job_id=p_job_id for update;
  if d.sheet_id is null then
    select * into config from public.stat_export_destinations where team_id=s.team_id for update;
    if not found then raise exception 'Export destination unavailable' using errcode='55000'; end if;
    if config.next_sheet_id>config.snapshot_max or config.next_ledger_row>=config.ledger_rows then
      raise exception 'Reserved destination capacity exhausted' using errcode='54000';
    end if;
    update public.stat_export_deliveries set spreadsheet_id=config.spreadsheet_id,
      ledger_sheet_id=config.ledger_sheet_id,sheet_id=config.next_sheet_id::integer,ledger_row=config.next_ledger_row
      where job_id=p_job_id returning * into d;
    update public.stat_export_destinations set next_sheet_id=next_sheet_id+1,next_ledger_row=next_ledger_row+1
      where team_id=s.team_id;
  end if;
  if d.state<>'delivered' then
    update public.stat_export_deliveries set state='reserved',attempts=attempts+1,error_code=null,updated_at=clock_timestamp()
      where job_id=p_job_id returning * into d;
  end if;
  return jsonb_build_object('job_id',s.job_id,'accepted_version_id',s.accepted_version_id,
    'payload_text',s.payload_text,'payload_sha256',s.payload_sha256,'spreadsheet_id',d.spreadsheet_id,
    'sheet_id',d.sheet_id,'ledger_sheet_id',d.ledger_sheet_id,'ledger_row',d.ledger_row,'state',d.state);
end $$;
create function public.stats_export_finish(p_job_id uuid,p_receipt jsonb) returns void
language plpgsql security definer set search_path=pg_catalog as $$
declare s public.stat_export_snapshots; d public.stat_export_deliveries;
begin
  perform team_private.export_service();
  select * into s from public.stat_export_snapshots where job_id=p_job_id;
  if not found then raise exception 'Unknown accepted export' using errcode='22023'; end if;
  perform 1 from public.teams where id=s.team_id for update;
  select * into d from public.stat_export_deliveries where job_id=p_job_id for update;
  if d.sheet_id is null or p_receipt is null or jsonb_typeof(p_receipt)<>'object'
    or p_receipt is distinct from jsonb_build_object('accepted_version_id',s.accepted_version_id,
      'payload_sha256',s.payload_sha256,'spreadsheet_id',d.spreadsheet_id,'sheet_id',d.sheet_id,'ledger_row',d.ledger_row) then
    raise exception 'Verified immutable receipt required' using errcode='22023';
  end if;
  if d.state<>'delivered' then
    update public.stat_export_deliveries set state='delivered',error_code=null,
      delivered_at=clock_timestamp(),updated_at=clock_timestamp() where job_id=p_job_id;
  end if;
end $$;
create function public.stats_export_fail(p_job_id uuid,p_error_code text) returns void
language plpgsql security definer set search_path=pg_catalog as $$
begin
  perform team_private.export_service();
  if p_error_code is null or p_error_code not in ('budget_disabled','configuration_invalid','request_limit','payload_too_large',
    'payload_hash_mismatch','payload_identity_mismatch','destination_conflict','destination_capacity','provider_response',
    'provider_timeout','provider_transport','response_too_large','redirect_denied','backend_transport')
    and p_error_code !~ '^provider_http_[1-5][0-9]{2}$' then
    raise exception 'Fixed sanitized error code required' using errcode='22023';
  end if;
  update public.stat_export_deliveries set state='failed',error_code=p_error_code,updated_at=clock_timestamp()
    where job_id=p_job_id and state<>'delivered';
  if not found and not exists(select 1 from public.stat_export_deliveries where job_id=p_job_id) then
    raise exception 'Unknown accepted export' using errcode='22023';
  end if;
end $$;
create function public.stats_export_status(p_team_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare actor uuid := team_private.member_actor(p_team_id);
begin
  if not team_private.is_owner(p_team_id,actor) then raise exception 'Owner export status required' using errcode='42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('job_id',o.id,'game_id',o.game_id,'accepted_version_id',o.accepted_version_id,
    'dataset_type',v.dataset_type,'publication_generation',o.publication_generation,'state',d.state,'attempts',d.attempts,
    'error_code',d.error_code,'delivered_at',d.delivered_at) order by o.created_at,o.publication_generation),'[]'::jsonb)
    from public.stat_export_outbox o join public.stat_versions v on v.id=o.accepted_version_id
    join public.stat_export_deliveries d on d.job_id=o.id where o.team_id=p_team_id);
end $$;
create function public.stats_export_latest(p_team_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare actor uuid := team_private.member_actor(p_team_id);
begin
  if not team_private.is_owner(p_team_id,actor) then raise exception 'Owner export status required' using errcode='42501'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(latest) order by latest.game_id,latest.dataset_type),'[]'::jsonb) from
    (select distinct on(o.game_id,v.dataset_type) o.game_id,v.dataset_type,o.accepted_version_id,o.publication_generation,d.state
      from public.stat_export_outbox o join public.stat_versions v on v.id=o.accepted_version_id
      join public.stat_export_deliveries d on d.job_id=o.id where o.team_id=p_team_id
      order by o.game_id,v.dataset_type,o.publication_generation desc) latest);
end $$;

alter table public.stat_export_destinations enable row level security;
alter table public.stat_export_snapshots enable row level security;
alter table public.stat_export_deliveries enable row level security;
create policy export_delivery_owner_read on public.stat_export_deliveries for select to authenticated
  using(team_private.can_owner_read(team_id));
revoke all on public.stat_export_destinations,public.stat_export_snapshots,public.stat_export_deliveries from public,anon,authenticated,service_role;
-- Owner sees only state; destinations and payloads remain behind trusted commands.
grant select(job_id,team_id,state,attempts,error_code,delivered_at,updated_at) on public.stat_export_deliveries to authenticated;
revoke execute on function team_private.export_capture(),team_private.export_service() from public,anon,authenticated,service_role;
revoke execute on function public.stats_export_configure(uuid,text,integer,integer,integer,integer),public.stats_export_jobs(integer),
  public.stats_export_reserve(uuid),public.stats_export_finish(uuid,jsonb),public.stats_export_fail(uuid,text),
  public.stats_export_status(uuid),public.stats_export_latest(uuid) from public,anon,authenticated,service_role;
grant execute on function public.stats_export_configure(uuid,text,integer,integer,integer,integer),public.stats_export_jobs(integer),
  public.stats_export_reserve(uuid),public.stats_export_finish(uuid,jsonb),public.stats_export_fail(uuid,text) to service_role;
grant execute on function public.stats_export_status(uuid),public.stats_export_latest(uuid) to authenticated;
commit;
