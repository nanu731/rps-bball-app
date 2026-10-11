-- After-game connected datasets only; no automatic upload, export worker or extra fields.
begin;
create table public.games (
  id uuid primary key,
  team_id uuid not null references public.teams(id) on delete restrict,
  date date not null check (isfinite(date)),
  opponent text not null check (length(btrim(opponent)) between 1 and 100),
  home_away text not null check (home_away in ('home','away')),
  game_type text not null check (game_type in ('regularSeason','playoff')),
  publication_generation bigint not null default 0,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(team_id,id)
);
create table public.stat_datasets (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  game_id uuid not null,
  dataset_type text not null check (dataset_type in
    ('box_scores','our_possessions','opponent_possessions','player_paint_touches')),
  published_version_id uuid,
  foreign key(team_id,game_id) references public.games(team_id,id),
  unique(game_id,dataset_type), unique(team_id,id)
);
create table public.stat_versions (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  game_id uuid not null,
  dataset_id uuid not null,
  dataset_type text not null,
  author_user_id uuid not null references auth.users(id),
  revision bigint not null default 1 check(revision>0),
  status text not null default 'draft' check(status in ('draft','completed','submitted','rejected','published')),
  records jsonb not null default '[]',
  covered_roster jsonb not null default '[]',
  base_published_version_id uuid references public.stat_versions(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  review_actor_user_id uuid references auth.users(id),
  review_reason text not null default '' check(length(review_reason)<=500),
  foreign key(team_id,dataset_id) references public.stat_datasets(team_id,id),
  foreign key(team_id,game_id) references public.games(team_id,id),
  unique(dataset_id,id)
);
alter table public.stat_datasets add constraint dataset_published_version
  foreign key(id,published_version_id) references public.stat_versions(dataset_id,id);
create unique index one_author_working_version on public.stat_versions(dataset_id,author_user_id) where status='draft';
create index stat_versions_team_game on public.stat_versions(team_id,game_id);
create table public.stat_edit_requests (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id),
  source_version_id uuid not null references public.stat_versions(id),
  requester_user_id uuid not null references auth.users(id),
  revision bigint not null default 1 check(revision>0),
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  reason text not null default '' check(length(reason)<=500),
  review_reason text not null default '' check(length(review_reason)<=500),
  working_version_id uuid references public.stat_versions(id),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);
create unique index one_pending_edit_request on public.stat_edit_requests(source_version_id,requester_user_id) where status='pending';
create table public.stat_user_preferences (
  user_id uuid primary key references auth.users(id),
  suppress_numeric_warning boolean not null default false
);
create table public.stat_export_outbox (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id),
  game_id uuid not null references public.games(id),
  accepted_version_id uuid not null unique references public.stat_versions(id),
  publication_generation bigint not null check(publication_generation>0),
  created_at timestamptz not null default now(),
  unique(game_id,publication_generation)
);
create trigger stat_export_append_only before update or delete on public.stat_export_outbox
  for each row execute function team_private.append_only();

-- Same commit-time identity/locking protocol as administration without its revision.
create function team_private.member_actor(p_team uuid) returns uuid
language plpgsql security definer set search_path=pg_catalog as $$
declare v_actor uuid;
begin
  perform 1 from public.teams where id=p_team for update;
  if not found then raise exception 'Team access denied' using errcode='42501'; end if;
  v_actor := team_private.actor();
  if v_actor is null then raise exception 'Verified session required' using errcode='42501'; end if;
  perform 1 from auth.sessions where id=(auth.jwt()->>'session_id')::uuid and user_id=v_actor
    and (not_after is null or not_after>clock_timestamp()) for share;
  if not found or team_private.actor() is null or not team_private.is_active(p_team,v_actor) then
    raise exception 'Active membership required' using errcode='42501';
  end if;
  return v_actor;
end $$;
create function team_private.stat_visible(p_team uuid,p_author uuid,p_status text) returns boolean
language sql stable security definer set search_path=pg_catalog as $$
  select team_private.can_read(p_team) and (p_status='published' or p_author=team_private.actor()
    or (p_status in ('submitted','rejected') and team_private.has_capability(p_team,team_private.actor(),'stats.review')))
$$;
create function team_private.edit_source_visible(p_team uuid,p_version uuid) returns boolean
language sql stable security definer set search_path=pg_catalog as $$
  select team_private.can_read(p_team) and team_private.has_capability(p_team,team_private.actor(),'datasets.reopen')
    and exists(select 1 from public.stat_edit_requests where team_id=p_team and source_version_id=p_version and status='pending')
$$;
create function team_private.edit_visible(p_team uuid,p_requester uuid) returns boolean
language sql stable security definer set search_path=pg_catalog as $$
  select team_private.can_read(p_team) and (p_requester=team_private.actor()
    or team_private.has_capability(p_team,team_private.actor(),'datasets.reopen'))
$$;
create function team_private.stat_immutable() returns trigger language plpgsql set search_path=pg_catalog as $$
begin
  if tg_op='DELETE' or old.status='published' or new.id<>old.id or new.team_id<>old.team_id
    or new.game_id<>old.game_id or new.dataset_id<>old.dataset_id or new.dataset_type<>old.dataset_type
    or new.author_user_id<>old.author_user_id or new.base_published_version_id is distinct from old.base_published_version_id
    or new.created_at<>old.created_at or new.revision<>old.revision+1
    or (old.status<>'draft' and (new.records is distinct from old.records or new.covered_roster is distinct from old.covered_roster)) then
    raise exception 'Completed version data is immutable' using errcode='42501';
  end if;
  return new;
end $$;
create trigger protect_stat_version before update or delete on public.stat_versions
  for each row execute function team_private.stat_immutable();
create function team_private.stat_fields(p_type text) returns text[] language sql immutable set search_path=pg_catalog as $$
  select case when p_type='box_scores' then
    array['points','offensiveRebounds','defensiveRebounds','assists','turnovers','steals','blocks','fouls','chargesDrawn',
      'twosMade','twosMissed','threesMade','threesMissed','freeThrowsMade','freeThrowsMissed']
  else array['paintTouches','offensiveRebounds','twosMade','twosMissed','threesMade','threesMissed','freeThrowsMade','freeThrowsMissed'] end
$$;
create function team_private.valid_count(p_value jsonb) returns boolean language sql immutable set search_path=pg_catalog as $$
  select case when p_value is null or p_value='null'::jsonb then true
    when jsonb_typeof(p_value)='number' and p_value::text ~ '^[0-9]+$'
    then (p_value::text)::numeric<=9223372036854775807 else false end
$$;
create function team_private.validate_stats(p_team uuid,p_game uuid,p_type text,p_records jsonb,p_roster jsonb,p_complete boolean)
returns void language plpgsql security definer set search_path=pg_catalog as $$
declare r jsonb; k text; val jsonb; v_ids uuid[] := '{}'; v_numbers bigint[] := '{}';
  v_players uuid[] := '{}'; v_roster uuid[] := '{}'; v_id uuid; v_number bigint; v_lower numeric; v_points numeric;
begin
  if p_records is null or jsonb_typeof(p_records)<>'array' or p_roster is null or jsonb_typeof(p_roster)<>'array'
    or octet_length(p_records::text)+octet_length(p_roster::text)>4194304 then
    raise exception 'Record arrays required within request byte limit' using errcode='22023';
  end if;
  for r in select value from jsonb_array_elements(p_roster) loop
    if jsonb_typeof(r)<>'object' or not r ?& array['id','version']
      or exists(select 1 from jsonb_object_keys(r) x where x not in ('id','version'))
      or not team_private.valid_count(r->'version') or r->>'version' is null or (r->>'version')::numeric<1 then
      raise exception 'Invalid covered roster' using errcode='22023';
    end if;
    v_id := (r->>'id')::uuid;
    if v_id is null or v_id=any(v_roster) or not exists(select 1 from public.roster_entry_revisions h
      join public.roster_entries e on e.id=h.roster_id where h.team_id=p_team and h.roster_id=v_id
      and h.version=(r->>'version')::bigint and e.identity_kind='real') then
      raise exception 'Covered roster must identify unique real roster revisions' using errcode='22023';
    end if;
    v_roster := array_append(v_roster,v_id);
  end loop;
  if p_type in ('our_possessions','opponent_possessions') and cardinality(v_roster)>0 then
    raise exception 'Possessions have no player roster' using errcode='22023';
  end if;
  for r in select value from jsonb_array_elements(p_records) loop
    if jsonb_typeof(r)<>'object' or not r ? 'gameID' or (r->>'gameID')::uuid is distinct from p_game then
      raise exception 'Every record must identify its game' using errcode='22023';
    end if;
    if p_type in ('box_scores','player_paint_touches') then
      if not r ? 'playerID' or exists(select 1 from jsonb_object_keys(r) x where x<>all(
        case when p_type='box_scores' then array['gameID','playerID','values'] else array['gameID','playerID','total'] end)) then
        raise exception 'Unknown player record field' using errcode='22023';
      end if;
      v_id := (r->>'playerID')::uuid;
      if v_id is null or v_id=any(v_players) or not exists(select 1 from public.roster_entries
        where team_id=p_team and id=v_id and identity_kind='real') then
        raise exception 'Unique real team player required' using errcode='22023';
      end if;
      v_players := array_append(v_players,v_id);
      if p_type='player_paint_touches' and not team_private.valid_count(r->'total') then
        raise exception 'Invalid paint-touch total' using errcode='22023';
      end if;
    else
      if not r ?& array['id','team','number','values'] or exists(select 1 from jsonb_object_keys(r) x
        where x not in ('id','gameID','team','number','values','turnover'))
        or r->>'team' is distinct from (case when p_type='our_possessions' then 'ours' else 'opponent' end)
        or not team_private.valid_count(r->'number') or r->>'number' is null or (r->>'number')::numeric<1
        or (r ? 'turnover' and jsonb_typeof(r->'turnover') not in ('boolean','null')) then
        raise exception 'Invalid possession record' using errcode='22023';
      end if;
      v_id := (r->>'id')::uuid; v_number := (r->>'number')::bigint;
      if v_id is null or v_id=any(v_ids) or v_number=any(v_numbers) then
        raise exception 'Duplicate possession identity or number' using errcode='22023';
      end if;
      v_ids := array_append(v_ids,v_id); v_numbers := array_append(v_numbers,v_number);
      if p_complete and jsonb_typeof(r->'turnover') is distinct from 'boolean' then
        raise exception 'Every possession needs a Yes or No turnover answer' using errcode='22023';
      end if;
    end if;
    if p_type<>'player_paint_touches' then
      if not r ? 'values' or jsonb_typeof(r->'values')<>'object' then
        raise exception 'Values object required' using errcode='22023';
      end if;
      for k,val in select key,value from jsonb_each(r->'values') loop
        if k<>all(team_private.stat_fields(p_type)) or not team_private.valid_count(val) then
          raise exception 'Unknown or invalid statistic count' using errcode='22023';
        end if;
      end loop;
      if p_complete then
        v_lower := coalesce((r->'values'->>'twosMade')::numeric,0)*2+
          coalesce((r->'values'->>'threesMade')::numeric,0)*3+coalesce((r->'values'->>'freeThrowsMade')::numeric,0);
        v_points := (r->'values'->>'points')::numeric;
        if v_lower>9223372036854775807 then raise exception 'Derived scoring overflow' using errcode='22023'; end if;
        if p_type='box_scores' and v_points is not null and (v_lower>v_points or
          (r->'values'->>'twosMade' is not null and r->'values'->>'threesMade' is not null
            and r->'values'->>'freeThrowsMade' is not null and v_lower<>v_points)) then
          raise exception 'Points disagree with entered made shots' using errcode='22023';
        end if;
      end if;
    end if;
  end loop;
  if cardinality(v_numbers)>0 and (select max(n) from unnest(v_numbers) n)<>cardinality(v_numbers) then
    raise exception 'Possession numbering must be independently contiguous' using errcode='22023';
  end if;
  if p_complete then
    if jsonb_array_length(p_records)=0 then raise exception 'Empty dataset cannot be completed' using errcode='22023'; end if;
    if p_type in ('box_scores','player_paint_touches') and (cardinality(v_roster)=0
      or not v_roster @> v_players or not v_players @> v_roster) then
      raise exception 'Confirm the exact real covered roster' using errcode='22023';
    end if;
  end if;
exception when invalid_text_representation or numeric_value_out_of_range then
  raise exception 'Invalid record identity or integer' using errcode='22023';
end $$;

create function public.stats_create_game(p_team_id uuid,p_game_id uuid,p_date date,p_opponent text,p_home_away text,p_game_type text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid := team_private.member_actor(p_team_id); g public.games;
begin
  if p_game_id is null or p_date is null or not isfinite(p_date) or p_opponent is null
    or length(btrim(p_opponent)) not between 1 and 100 or p_home_away is null or p_home_away not in ('home','away')
    or p_game_type is null or p_game_type not in ('regularSeason','playoff') then
    raise exception 'Four valid game metadata fields and stable UUID required' using errcode='22023';
  end if;
  select * into g from public.games where id=p_game_id for update;
  if found then
    if g.team_id<>p_team_id then raise exception 'Game access denied' using errcode='42501'; end if;
    if g.date<>p_date or g.opponent<>btrim(p_opponent) or g.home_away<>p_home_away or g.game_type<>p_game_type then
      raise exception 'Game UUID already has different metadata' using errcode='40001';
    end if;
    return to_jsonb(g);
  end if;
  insert into public.games(id,team_id,date,opponent,home_away,game_type,created_by)
  values(p_game_id,p_team_id,p_date,btrim(p_opponent),p_home_away,p_game_type,a) returning * into g;
  perform team_private.audit(p_team_id,a,'game.created',g.id);
  return to_jsonb(g);
end $$;
create function public.stats_open_draft(p_team_id uuid,p_game_id uuid,p_dataset_type text) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid := team_private.member_actor(p_team_id); d public.stat_datasets; v public.stat_versions;
begin
  perform 1 from public.games where team_id=p_team_id and id=p_game_id for update;
  if not found then raise exception 'Game access denied' using errcode='42501'; end if;
  if p_dataset_type is null or p_dataset_type not in ('box_scores','our_possessions','opponent_possessions','player_paint_touches') then
    raise exception 'Invalid dataset type' using errcode='22023';
  end if;
  insert into public.stat_datasets(team_id,game_id,dataset_type) values(p_team_id,p_game_id,p_dataset_type)
    on conflict(game_id,dataset_type) do nothing;
  select * into d from public.stat_datasets where game_id=p_game_id and dataset_type=p_dataset_type for update;
  select * into v from public.stat_versions where dataset_id=d.id and author_user_id=a and status='draft';
  if found then return to_jsonb(v); end if;
  if d.published_version_id is not null or exists(select 1 from public.stat_versions where dataset_id=d.id and author_user_id=a) then
    raise exception 'Completed dataset requires approved edit request' using errcode='42501';
  end if;
  insert into public.stat_versions(team_id,game_id,dataset_id,dataset_type,author_user_id)
  values(p_team_id,p_game_id,d.id,p_dataset_type,a) returning * into v;
  perform team_private.audit(p_team_id,a,'stats.draft_opened',v.id);
  return to_jsonb(v);
end $$;
-- Team lock precedes game lock and version lock, including reviewer commands.
create function team_private.lock_stat(p_team uuid,p_id uuid,p_expected bigint) returns public.stat_versions
language plpgsql security definer set search_path=pg_catalog as $$
declare v public.stat_versions; g uuid;
begin
  select game_id into g from public.stat_versions where team_id=p_team and id=p_id;
  if not found then raise exception 'Version access denied' using errcode='42501'; end if;
  perform 1 from public.games where team_id=p_team and id=g for update;
  select * into v from public.stat_versions where team_id=p_team and id=p_id for update;
  if p_expected is distinct from v.revision then raise exception 'Statistic revision changed; reload' using errcode='40001'; end if;
  return v;
end $$;
create function public.stats_save_draft(p_team_id uuid,p_version_id uuid,p_expected_revision bigint,p_records jsonb,p_covered_roster jsonb default '[]')
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid := team_private.member_actor(p_team_id); v public.stat_versions;
begin
  v := team_private.lock_stat(p_team_id,p_version_id,p_expected_revision);
  if v.author_user_id<>a or v.status<>'draft' then raise exception 'Only author may save an unfinished draft' using errcode='42501'; end if;
  perform team_private.validate_stats(p_team_id,v.game_id,v.dataset_type,p_records,p_covered_roster,false);
  update public.stat_versions set records=p_records,covered_roster=p_covered_roster,revision=revision+1,updated_at=now()
    where id=v.id returning * into v;
  perform team_private.audit(p_team_id,a,'stats.draft_saved',v.id);
  return to_jsonb(v);
end $$;
-- A single user Save action for paired sheets either saves every editable side or none.
create function public.stats_save_drafts(p_team_id uuid,p_items jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid := team_private.member_actor(p_team_id); item jsonb; ids uuid[] := '{}'; id uuid;
  result jsonb := '[]';
begin
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 4
    or octet_length(p_items::text)>4194304 then raise exception 'One to four draft items within request byte limit required' using errcode='22023'; end if;
  for item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(item)<>'object' or not item ?& array['version_id','expected_revision','records']
      or exists(select 1 from jsonb_object_keys(item) k where k not in ('version_id','expected_revision','records','covered_roster'))
      or not team_private.valid_count(item->'expected_revision') or item->>'expected_revision' is null
      or (item->>'expected_revision')::numeric<1 then
      raise exception 'Invalid draft batch item' using errcode='22023';
    end if;
    id := (item->>'version_id')::uuid;
    if id is null or id=any(ids) then raise exception 'Unique draft UUIDs required' using errcode='22023'; end if;
    ids := array_append(ids,id);
  end loop;
  for item in select value from jsonb_array_elements(p_items) loop
    result := result || jsonb_build_array(public.stats_save_draft(p_team_id,(item->>'version_id')::uuid,
      (item->>'expected_revision')::bigint,item->'records',coalesce(item->'covered_roster','[]'::jsonb)));
  end loop;
  return result;
exception when invalid_text_representation or numeric_value_out_of_range then
  raise exception 'Invalid draft batch identity or integer' using errcode='22023';
end $$;
create function public.stats_preferences(p_team_id uuid) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog as $$
declare a uuid := team_private.actor();
begin
  if a is null or not team_private.is_active(p_team_id,a) then raise exception 'Active membership required' using errcode='42501'; end if;
  return jsonb_build_object('suppress_numeric_warning',coalesce((select suppress_numeric_warning from public.stat_user_preferences where user_id=a),false));
end $$;
create function public.stats_complete(p_team_id uuid,p_version_id uuid,p_expected_revision bigint,p_confirm_roster boolean default false,
  p_confirm_numeric_zeros boolean default false,p_suppress_numeric_warning boolean default false) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid := team_private.member_actor(p_team_id); v public.stat_versions; r jsonb; converted jsonb := '[]';
  vals jsonb; k text; blanks boolean := false; suppressed boolean;
begin
  v := team_private.lock_stat(p_team_id,p_version_id,p_expected_revision);
  if v.author_user_id<>a or v.status<>'draft' then raise exception 'Only author may complete an unfinished draft' using errcode='42501'; end if;
  if v.dataset_type in ('box_scores','player_paint_touches') and p_confirm_roster is distinct from true then
    raise exception 'Covered roster confirmation required' using errcode='22023';
  end if;
  perform team_private.validate_stats(p_team_id,v.game_id,v.dataset_type,v.records,v.covered_roster,true);
  if v.dataset_type in ('our_possessions','opponent_possessions') then
    for r in select value from jsonb_array_elements(v.records) loop
      vals := r->'values';
      foreach k in array team_private.stat_fields(v.dataset_type) loop
        if vals->>k is null then vals := vals || jsonb_build_object(k,0); blanks := true; end if;
      end loop;
      converted := converted || jsonb_build_array(jsonb_set(r,'{values}',vals));
    end loop;
    select suppress_numeric_warning into suppressed from public.stat_user_preferences where user_id=a;
    if blanks and p_confirm_numeric_zeros is distinct from true and coalesce(suppressed,false)=false then
      raise exception 'Confirm numeric blanks become zero' using errcode='22023';
    end if;
    if p_suppress_numeric_warning is true then
      if p_confirm_numeric_zeros is distinct from true then raise exception 'Explicit confirmation required to save suppression' using errcode='22023'; end if;
      insert into public.stat_user_preferences(user_id,suppress_numeric_warning) values(a,true)
        on conflict(user_id) do update set suppress_numeric_warning=true;
    end if;
    v.records := converted;
  elsif p_suppress_numeric_warning is true or p_confirm_numeric_zeros is true then
    raise exception 'Numeric zero confirmation applies to possessions only' using errcode='22023';
  end if;
  update public.stat_versions set records=v.records,status='completed',revision=revision+1,updated_at=now()
    where id=v.id returning * into v;
  perform team_private.audit(p_team_id,a,'stats.completed',v.id);
  return to_jsonb(v);
end $$;
create function public.stats_submit(p_team_id uuid,p_version_id uuid,p_expected_revision bigint) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid := team_private.member_actor(p_team_id); v public.stat_versions;
begin
  v := team_private.lock_stat(p_team_id,p_version_id,p_expected_revision);
  if v.author_user_id<>a or v.status<>'completed' then raise exception 'Only author may submit completed data' using errcode='42501'; end if;
  update public.stat_versions set status='submitted',revision=revision+1,updated_at=now() where id=v.id returning * into v;
  perform team_private.audit(p_team_id,a,'stats.submitted',v.id);
  return to_jsonb(v);
end $$;
create function team_private.accept_stat(p_version public.stat_versions,p_actor uuid,p_reason text default null) returns public.stat_versions
language plpgsql security definer set search_path=pg_catalog as $$
declare v public.stat_versions := p_version; current_id uuid; generation bigint;
begin
  select published_version_id into current_id from public.stat_datasets where id=v.dataset_id for update;
  if current_id is distinct from v.base_published_version_id then
    raise exception 'Accepted version changed; request a revision from current data' using errcode='40001';
  end if;
  update public.stat_versions set status='published',revision=revision+1,updated_at=now(),
    review_actor_user_id=case when p_reason is null then review_actor_user_id else p_actor end,
    review_reason=coalesce(p_reason,review_reason) where id=v.id returning * into v;
  update public.stat_datasets set published_version_id=v.id where id=v.dataset_id;
  update public.games set publication_generation=publication_generation+1 where id=v.game_id returning publication_generation into generation;
  insert into public.stat_export_outbox(team_id,game_id,accepted_version_id,publication_generation)
    values(v.team_id,v.game_id,v.id,generation);
  perform team_private.audit(v.team_id,p_actor,'stats.published',v.id);
  return v;
end $$;
create function public.stats_publish(p_team_id uuid,p_version_id uuid,p_expected_revision bigint) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid := team_private.member_actor(p_team_id); v public.stat_versions;
begin
  v := team_private.lock_stat(p_team_id,p_version_id,p_expected_revision);
  if v.author_user_id<>a or v.status not in ('completed','submitted')
    or not team_private.has_capability(p_team_id,a,'stats.publish') then
    raise exception 'Author direct-publication capability required' using errcode='42501';
  end if;
  v := team_private.accept_stat(v,a); return to_jsonb(v);
end $$;
create function public.stats_review(p_team_id uuid,p_version_id uuid,p_expected_revision bigint,p_approve boolean,p_reason text default '')
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid := team_private.member_actor(p_team_id); v public.stat_versions;
begin
  v := team_private.lock_stat(p_team_id,p_version_id,p_expected_revision);
  if v.status<>'submitted' or not team_private.has_capability(p_team_id,a,'stats.review')
    or (p_approve is true and v.author_user_id=a and not team_private.is_owner(p_team_id,a)) then
    raise exception 'Independent statistic review required' using errcode='42501';
  end if;
  if p_approve is null or p_reason is null or length(p_reason)>500 then raise exception 'Invalid review decision' using errcode='22023'; end if;
  if p_approve then v := team_private.accept_stat(v,a,p_reason);
  else
    update public.stat_versions set status='rejected',revision=revision+1,updated_at=now(),
      review_actor_user_id=a,review_reason=p_reason where id=v.id returning * into v;
    perform team_private.audit(p_team_id,a,'stats.rejected',v.id);
  end if;
  return to_jsonb(v);
end $$;
create function public.stats_request_edit(p_team_id uuid,p_source_version_id uuid,p_expected_revision bigint,p_reason text default '')
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid := team_private.member_actor(p_team_id); v public.stat_versions; req public.stat_edit_requests;
begin
  v := team_private.lock_stat(p_team_id,p_source_version_id,p_expected_revision);
  if v.status='draft' or (v.status<>'published' and v.author_user_id<>a) then
    raise exception 'Published viewer or completed author required' using errcode='42501';
  end if;
  if p_reason is null or length(p_reason)>500 then raise exception 'Invalid edit request reason' using errcode='22023'; end if;
  select * into req from public.stat_edit_requests where source_version_id=v.id and requester_user_id=a and status='pending';
  if found then
    if req.reason<>p_reason then raise exception 'Pending request already has different reason' using errcode='40001'; end if;
    return to_jsonb(req);
  end if;
  insert into public.stat_edit_requests(team_id,source_version_id,requester_user_id,reason)
    values(p_team_id,v.id,a,p_reason) returning * into req;
  perform team_private.audit(p_team_id,a,'stats.edit_requested',req.id);
  return to_jsonb(req);
end $$;
create function public.stats_review_edit(p_team_id uuid,p_request_id uuid,p_expected_revision bigint,p_approve boolean,p_reason text default '')
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid := team_private.member_actor(p_team_id); req public.stat_edit_requests; source public.stat_versions;
  v public.stat_versions; base uuid;
begin
  select * into req from public.stat_edit_requests where team_id=p_team_id and id=p_request_id;
  if not found then raise exception 'Edit request access denied' using errcode='42501'; end if;
  select * into source from public.stat_versions where id=req.source_version_id;
  perform 1 from public.games where id=source.game_id for update;
  select * into req from public.stat_edit_requests where id=p_request_id for update;
  if req.revision is distinct from p_expected_revision then raise exception 'Edit request revision changed; reload' using errcode='40001'; end if;
  if req.status<>'pending' or not team_private.has_capability(p_team_id,a,'datasets.reopen')
    or (p_approve is true and req.requester_user_id=a and not team_private.is_owner(p_team_id,a))
    or not team_private.is_active(p_team_id,req.requester_user_id) then
    raise exception 'Independent completed-data review required' using errcode='42501';
  end if;
  if p_approve is null or p_reason is null or length(p_reason)>500 then raise exception 'Invalid edit review decision' using errcode='22023'; end if;
  if p_approve then
    select published_version_id into base from public.stat_datasets where id=source.dataset_id for update;
    if source.status='published' and source.id is distinct from base
      or source.status<>'published' and source.base_published_version_id is distinct from base then
      raise exception 'Source acceptance changed; request from current version' using errcode='40001';
    end if;
    if exists(select 1 from public.stat_versions where dataset_id=source.dataset_id
      and author_user_id=req.requester_user_id and status='draft') then
      raise exception 'Existing unfinished draft must be preserved' using errcode='40001';
    end if;
    insert into public.stat_versions(team_id,game_id,dataset_id,dataset_type,author_user_id,records,covered_roster,base_published_version_id)
      values(p_team_id,source.game_id,source.dataset_id,source.dataset_type,req.requester_user_id,source.records,source.covered_roster,base)
      returning * into v;
  end if;
  update public.stat_edit_requests set status=case when p_approve then 'approved' else 'rejected' end,
    revision=revision+1,review_reason=p_reason,working_version_id=v.id,reviewed_at=now() where id=req.id returning * into req;
  perform team_private.audit(p_team_id,a,case when p_approve then 'stats.edit_approved' else 'stats.edit_rejected' end,req.id);
  return jsonb_build_object('request',to_jsonb(req),'version',case when v.id is null then null else to_jsonb(v) end);
end $$;

alter table public.games enable row level security;
alter table public.stat_datasets enable row level security;
alter table public.stat_versions enable row level security;
alter table public.stat_edit_requests enable row level security;
alter table public.stat_user_preferences enable row level security;
alter table public.stat_export_outbox enable row level security;
create policy games_member_read on public.games for select to authenticated using(team_private.can_read(team_id));
create policy datasets_member_read on public.stat_datasets for select to authenticated using(team_private.can_read(team_id));
create policy versions_author_review_published_read on public.stat_versions for select to authenticated
  using(team_private.stat_visible(team_id,author_user_id,status)
    or (status<>'draft' and team_private.edit_source_visible(team_id,id)));
create policy edit_request_read on public.stat_edit_requests for select to authenticated
  using(team_private.edit_visible(team_id,requester_user_id));
create policy outbox_owner_read on public.stat_export_outbox for select to authenticated using(team_private.can_owner_read(team_id));
revoke all on public.games,public.stat_datasets,public.stat_versions,public.stat_edit_requests,public.stat_user_preferences,public.stat_export_outbox
  from public,anon,authenticated;
grant select on public.games,public.stat_datasets,public.stat_versions,public.stat_edit_requests,public.stat_user_preferences,public.stat_export_outbox to authenticated;
revoke execute on all functions in schema team_private from public,anon,authenticated;
-- Restore prior policy predicates; private actor/lock/validation/acceptance functions stay denied.
grant execute on function team_private.can_read(uuid),team_private.can_admin_read(uuid),team_private.can_owner_read(uuid),
  team_private.stat_visible(uuid,uuid,text),team_private.edit_visible(uuid,uuid),team_private.edit_source_visible(uuid,uuid) to authenticated;
-- Preference RLS uses a predicate rather than exposing the privileged identity helper.
create function team_private.own_preferences(p_user uuid) returns boolean language sql stable security definer set search_path=pg_catalog as $$
  select p_user=team_private.actor() and exists(select 1 from public.team_memberships where user_id=p_user and status='active')
$$;
create policy preferences_own_read on public.stat_user_preferences for select to authenticated using(team_private.own_preferences(user_id));
revoke execute on function team_private.own_preferences(uuid) from public,anon,authenticated;
grant execute on function team_private.own_preferences(uuid) to authenticated;
revoke execute on function public.stats_create_game(uuid,uuid,date,text,text,text),public.stats_open_draft(uuid,uuid,text),
  public.stats_save_draft(uuid,uuid,bigint,jsonb,jsonb),public.stats_save_drafts(uuid,jsonb),public.stats_complete(uuid,uuid,bigint,boolean,boolean,boolean),
  public.stats_submit(uuid,uuid,bigint),public.stats_publish(uuid,uuid,bigint),public.stats_review(uuid,uuid,bigint,boolean,text),
  public.stats_request_edit(uuid,uuid,bigint,text),public.stats_review_edit(uuid,uuid,bigint,boolean,text),public.stats_preferences(uuid)
  from public,anon,authenticated;
grant execute on function public.stats_create_game(uuid,uuid,date,text,text,text),public.stats_open_draft(uuid,uuid,text),
  public.stats_save_draft(uuid,uuid,bigint,jsonb,jsonb),public.stats_save_drafts(uuid,jsonb),public.stats_complete(uuid,uuid,bigint,boolean,boolean,boolean),
  public.stats_submit(uuid,uuid,bigint),public.stats_publish(uuid,uuid,bigint),public.stats_review(uuid,uuid,bigint,boolean,text),
  public.stats_request_edit(uuid,uuid,bigint,text),public.stats_review_edit(uuid,uuid,bigint,boolean,text),public.stats_preferences(uuid)
  to authenticated;
commit;
