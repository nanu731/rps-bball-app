-- Source preparation only: isolated synthetic deployment; no existing/hosted activation.
begin;
create or replace function team_private.capabilities() returns text[] language sql immutable
set search_path=pg_catalog as $$ select array['stats.review','stats.publish','datasets.reopen','roster.manage','members.manage','plays.author','plays.review','plays.publish','practice.upload','practice.review','practice.publish','film.upload','film.review','film.publish','scouting.upload','scouting.read','shots.record','shots.review','shots.publish']::text[] $$;

create table team_private.shot_sessions (
 game_id uuid primary key, team_id uuid not null, session_id uuid unique,
 recorder_user_id uuid not null references auth.users(id),
 assignment_revision bigint not null check(assignment_revision>0), revision bigint not null check(revision>0),
 latest_snapshot_id uuid, published_snapshot_id uuid,
 head_status text not null default 'draft' check(head_status in ('draft','submitted','rejected','published')),
 foreign key(team_id,game_id) references public.games(team_id,id)
);
create table team_private.shot_snapshots (
 id uuid primary key default gen_random_uuid(), team_id uuid not null, game_id uuid not null,
 session_id uuid not null references team_private.shot_sessions(session_id),
 creator_user_id uuid not null references auth.users(id), uploader_user_id uuid not null references auth.users(id),
 assignment_revision bigint not null check(assignment_revision>0), local_revision integer not null check(local_revision between 0 and 20000),
 document jsonb not null, document_digest text not null check(document_digest ~ '^[0-9a-f]{64}$'),
 parent_snapshot_id uuid, recovery boolean not null default false,
 coverage_claim text not null check(coverage_claim in ('unknown','partial','manager_declared_full_game')),
 created_at timestamptz not null default now(), unique(game_id,id),
 foreign key(team_id,game_id) references public.games(team_id,id),
 foreign key(game_id,parent_snapshot_id) references team_private.shot_snapshots(game_id,id)
);
alter table team_private.shot_sessions add foreign key(game_id,latest_snapshot_id) references team_private.shot_snapshots(game_id,id);
alter table team_private.shot_sessions add foreign key(game_id,published_snapshot_id) references team_private.shot_snapshots(game_id,id);
create table team_private.shot_assignments (
 id uuid primary key default gen_random_uuid(), team_id uuid not null, game_id uuid not null,
 assignment_revision bigint not null, recorder_user_id uuid not null references auth.users(id),
 actor_user_id uuid not null references auth.users(id), reason text not null check(length(btrim(reason)) between 1 and 500),
 created_at timestamptz not null default now(), unique(game_id,assignment_revision),
 foreign key(team_id,game_id) references public.games(team_id,id)
);
create table team_private.shot_decisions (
 id uuid primary key default gen_random_uuid(),team_id uuid not null,game_id uuid not null,snapshot_id uuid not null,
 actor_user_id uuid not null references auth.users(id), decision text not null check(decision in ('submit','approve','reject','publish','adopt')),
 reason text not null check(length(reason)<=500),displaced_snapshot_id uuid,created_at timestamptz not null default now(),
 foreign key(team_id,game_id) references public.games(team_id,id),
 foreign key(game_id,snapshot_id) references team_private.shot_snapshots(game_id,id),
 foreign key(game_id,displaced_snapshot_id) references team_private.shot_snapshots(game_id,id)
);
create table team_private.shot_receipts (
 batch_id uuid primary key,team_id uuid not null,game_id uuid not null,actor_user_id uuid not null references auth.users(id),
 operation text not null,request_digest text not null,result jsonb not null,created_at timestamptz not null default now(),
 foreign key(team_id,game_id) references public.games(team_id,id)
);
create trigger shot_snapshot_immutable before update or delete on team_private.shot_snapshots for each row execute function team_private.append_only();
create trigger shot_assignment_immutable before update or delete on team_private.shot_assignments for each row execute function team_private.append_only();
create trigger shot_decision_immutable before update or delete on team_private.shot_decisions for each row execute function team_private.append_only();
create trigger shot_receipt_immutable before update or delete on team_private.shot_receipts for each row execute function team_private.append_only();

-- Team, verified user, then session locks. A signed JWT alone cannot preserve revoked rights.
create function team_private.shot_actor(p_team uuid) returns uuid language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid;
begin
 perform 1 from public.teams where id=p_team for update;
 a:=team_private.actor();
 if a is null then raise exception 'Verified access required' using errcode='42501'; end if;
 perform 1 from auth.users where id=a and deleted_at is null and (banned_until is null or banned_until<=clock_timestamp()) for share;
 if not found then raise exception 'Verified access required' using errcode='42501'; end if;
 perform 1 from auth.sessions where id=(auth.jwt()->>'session_id')::uuid and user_id=a and (not_after is null or not_after>clock_timestamp()) for share;
 if not found or team_private.actor() is distinct from a or not team_private.is_active(p_team,a) then
  raise exception 'Active access required' using errcode='42501';
 end if;
 return a;
end $$;

create function team_private.shot_prior(p_team uuid,p_game uuid,p_actor uuid,p_batch uuid,p_digest text) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare r team_private.shot_receipts;s team_private.shot_sessions;
begin
 if p_batch is null or p_batch='00000000-0000-0000-0000-000000000000' then raise exception 'Command identity required' using errcode='22023'; end if;
 select * into r from team_private.shot_receipts where batch_id=p_batch;
 if found then
  if r.team_id<>p_team or r.game_id<>p_game or r.actor_user_id<>p_actor or r.request_digest<>p_digest then raise exception 'Command identity conflict' using errcode='PT409'; end if;
  select * into s from team_private.shot_sessions where game_id=p_game;
  if (r.result->>'assignment_revision')::bigint is distinct from s.assignment_revision then raise exception 'Receipt assignment changed' using errcode='PT409';end if;
  if (r.operation<>'recovery' and not team_private.has_capability(p_team,p_actor,case when r.operation in ('save','submit') then 'shots.record' when r.operation='publish' then 'shots.publish' else 'shots.review' end))
   or (r.operation in ('save','submit') and s.recorder_user_id<>p_actor)
   or (r.operation='recovery' and not (team_private.has_capability(p_team,p_actor,'shots.review') or (s.recorder_user_id=p_actor and team_private.has_capability(p_team,p_actor,'shots.record')))) then raise exception 'Current command authority required' using errcode='42501';end if;
  return r.result;
 end if;
 return null;
end $$;
create function team_private.shot_receipt(p_team uuid,p_game uuid,p_actor uuid,p_batch uuid,p_digest text,p_operation text,p_result jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
begin
 if team_private.shot_actor(p_team) is distinct from p_actor or not (case when p_operation='recovery' then team_private.has_capability(p_team,p_actor,'shots.review') or team_private.has_capability(p_team,p_actor,'shots.record') else team_private.has_capability(p_team,p_actor,
  case when p_operation in ('save','submit') then 'shots.record' when p_operation='publish' then 'shots.publish' else 'shots.review' end) end) then
  raise exception 'Current shot authority required' using errcode='42501';
 end if;
 insert into team_private.shot_receipts values(p_batch,p_team,p_game,p_actor,p_operation,p_digest,p_result,now());
 perform team_private.audit(p_team,p_actor,'shots.'||p_operation,p_batch);
 return p_result;
end $$;

create function public.shots_state(p_team_id uuid,p_game_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.shot_actor(p_team_id);s team_private.shot_sessions;v team_private.shot_snapshots; privileged boolean;
begin
 perform 1 from public.games where team_id=p_team_id and id=p_game_id;
 if not found then raise exception 'Game access denied' using errcode='42501'; end if;
 select * into s from team_private.shot_sessions where game_id=p_game_id and team_id=p_team_id;
 privileged:=team_private.has_capability(p_team_id,a,'shots.review') or (s.recorder_user_id=a and team_private.has_capability(p_team_id,a,'shots.record'));
 if privileged then select * into v from team_private.shot_snapshots where id=s.latest_snapshot_id;
 else select * into v from team_private.shot_snapshots where id=s.published_snapshot_id; end if;
 return jsonb_build_object('team_id',p_team_id,'game_id',p_game_id,'session_id',s.session_id,'recorder_user_id',s.recorder_user_id,
  'assignment_revision',coalesce(s.assignment_revision,0),'state_revision',coalesce(s.revision,0),
  'snapshot_id',v.id,'document',v.document,'coverage_claim',v.coverage_claim,
  'status',case when s.game_id is null then 'not_started' when not coalesce(privileged,false) then case when v.id is null then 'no_published_capture' else 'published' end else s.head_status end,
  'can_record',coalesce(s.recorder_user_id=a and team_private.has_capability(p_team_id,a,'shots.record'),false),
  'server_time',clock_timestamp(),'recording_valid_until',(select min(g.expires_at) from public.capability_grants g where g.team_id=p_team_id and g.user_id=a and g.capability='shots.record' and g.revoked_at is null and g.expires_at>clock_timestamp()),
  'can_review',team_private.has_capability(p_team_id,a,'shots.review'),'can_publish',team_private.has_capability(p_team_id,a,'shots.publish'));
end $$;

create function public.shots_assign(p_team_id uuid,p_game_id uuid,p_recorder_user_id uuid,p_expected_assignment bigint,p_expected_revision bigint,p_batch_id uuid,p_reason text) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.shot_actor(p_team_id);s team_private.shot_sessions;d text;r jsonb;
begin
 if not team_private.has_capability(p_team_id,a,'shots.review') then raise exception 'Assignment authority required' using errcode='42501'; end if;
 d:=encode(sha256(convert_to(jsonb_build_array('assign',p_team_id,p_game_id,p_recorder_user_id,p_expected_assignment,p_expected_revision,p_reason)::text,'UTF8')),'hex');
 r:=team_private.shot_prior(p_team_id,p_game_id,a,p_batch_id,d); if r is not null then return r; end if;
 perform 1 from public.games where id=p_game_id and team_id=p_team_id for update;
 if not found then raise exception 'Game access denied' using errcode='42501'; end if;
 if p_reason is null or length(btrim(p_reason)) not between 1 and 500 or p_expected_assignment is null or p_expected_revision is null then raise exception 'Explicit assignment details required' using errcode='22023'; end if;
 if not team_private.has_capability(p_team_id,p_recorder_user_id,'shots.record') or not exists(
  select 1 from auth.users where id=p_recorder_user_id and deleted_at is null and is_anonymous is not true
   and (email_confirmed_at is not null or phone_confirmed_at is not null) and (banned_until is null or banned_until<=clock_timestamp())) then
  raise exception 'An authorized recording account is required' using errcode='42501';
 end if;
 select * into s from team_private.shot_sessions where game_id=p_game_id for update;
 if coalesce(s.assignment_revision,0)<>p_expected_assignment or coalesce(s.revision,0)<>p_expected_revision then raise exception 'Assignment changed' using errcode='PT409'; end if;
 if s.game_id is null then
  insert into team_private.shot_sessions(game_id,team_id,recorder_user_id,assignment_revision,revision) values(p_game_id,p_team_id,p_recorder_user_id,1,1);
 else
  update team_private.shot_sessions set recorder_user_id=p_recorder_user_id,assignment_revision=assignment_revision+1,revision=revision+1 where game_id=p_game_id;
 end if;
 select * into s from team_private.shot_sessions where game_id=p_game_id;
 insert into team_private.shot_assignments(team_id,game_id,assignment_revision,recorder_user_id,actor_user_id,reason)
  values(p_team_id,p_game_id,s.assignment_revision,p_recorder_user_id,a,p_reason);
 return team_private.shot_receipt(p_team_id,p_game_id,a,p_batch_id,d,'assign',jsonb_build_object('batch_id',p_batch_id,'operation','assign','team_id',p_team_id,'game_id',p_game_id,'actor_user_id',a,'assignment_revision',s.assignment_revision,'state_revision',s.revision));
end $$;

create function team_private.shot_uuid(v jsonb) returns uuid language plpgsql immutable set search_path=pg_catalog as $$
declare result uuid;
begin
 if jsonb_typeof(v) is distinct from 'string' then raise exception 'Capture identity required' using errcode='22023'; end if;
 result:=(v#>>'{}')::uuid;
 if result='00000000-0000-0000-0000-000000000000' then raise exception 'Capture identity required' using errcode='22023'; end if;
 return result;
end $$;
create function team_private.shot_integer(v jsonb,lo bigint,hi bigint) returns bigint language plpgsql immutable set search_path=pg_catalog as $$
declare result numeric;
begin
 if jsonb_typeof(v) is distinct from 'number' or v::text !~ '^(0|[1-9][0-9]*)$' then raise exception 'Whole-number capture value required' using errcode='22023'; end if;
 result:=v::text::numeric;
 if result<lo or result>hi then raise exception 'Capture integer range exceeded' using errcode='22023'; end if;
 return result::bigint;
end $$;
create function team_private.shot_event(e jsonb,players jsonb) returns void language plpgsql immutable set search_path=pg_catalog as $$
declare p uuid;n bigint;answer jsonb;indices jsonb:='{}';i bigint;location jsonb;value jsonb;outcome text;
begin
 if jsonb_typeof(e) is distinct from 'object' or e-array['id','kind','team','playerID','location','basket','value','outcome','freeThrowAttempts','answers']<>'{}' then raise exception 'Invalid capture observation' using errcode='22023'; end if;
 perform team_private.shot_uuid(e->'id');
 if e->>'team'='our' then
  p:=team_private.shot_uuid(e->'playerID');
  if not exists(select 1 from jsonb_array_elements(players) x where team_private.shot_uuid(x->'id')=p) then raise exception 'Capture player unavailable' using errcode='22023'; end if;
 elsif e->>'team'='opponent' then
  if nullif(e->'playerID','null') is not null then raise exception 'Opponent observations are team-only' using errcode='22023'; end if;
 else raise exception 'Capture team required' using errcode='22023'; end if;
 if jsonb_typeof(e->'answers') is distinct from 'array' then raise exception 'Capture answers required' using errcode='22023'; end if;
 value:=nullif(e->'value','null');outcome:=e->>'outcome';
 if e->>'kind'='fieldGoal' then
  location:=e->'location';
  if jsonb_typeof(location) is distinct from 'object' or location-array['x','y']<>'{}'
   or jsonb_typeof(location->'x') is distinct from 'number' or jsonb_typeof(location->'y') is distinct from 'number' then raise exception 'Capture location required' using errcode='22023'; end if;
  if (location->>'x')::numeric not between 0 and 1 or (location->>'y')::numeric not between 0 and 1
   or e->>'basket' is null or e->>'basket' not in ('top','bottom') or jsonb_array_length(e->'answers')<>0
   or nullif(e->'freeThrowAttempts','null') is not null then raise exception 'Invalid field goal' using errcode='22023'; end if;
  if value is not null and team_private.shot_integer(value,2,3) not in (2,3) then raise exception 'Explicit shot value required' using errcode='22023'; end if;
  if outcome is not null and (outcome not in ('made','missed') or value is null) then raise exception 'Explicit shot result required' using errcode='22023'; end if;
 elsif e->>'kind'='freeThrows' then
  if nullif(e->'location','null') is not null or nullif(e->'basket','null') is not null or value is not null or outcome is not null then raise exception 'Free throws have no court location' using errcode='22023'; end if;
  n:=team_private.shot_integer(e->'freeThrowAttempts',1,2147483647);
  if jsonb_array_length(e->'answers')>20000 then raise exception 'Capture answer bound exceeded' using errcode='22023'; end if;
  for answer in select * from jsonb_array_elements(e->'answers') loop
   if jsonb_typeof(answer) is distinct from 'object' or answer-array['index','outcome']<>'{}' or answer->>'outcome' is null or answer->>'outcome' not in ('made','missed') then raise exception 'Invalid free throw answer' using errcode='22023'; end if;
   i:=team_private.shot_integer(answer->'index',1,n);
   if indices ? i::text then raise exception 'Repeated free throw identity' using errcode='22023'; end if;
   indices:=indices||jsonb_build_object(i::text,true);
  end loop;
 else raise exception 'Capture observation kind required' using errcode='22023'; end if;
end $$;
create function team_private.shot_validate(doc jsonb,p_team uuid,p_game uuid) returns jsonb
language plpgsql immutable set search_path=pg_catalog as $$
declare players jsonb;player jsonb;change jsonb;state jsonb:='{}';ids jsonb:='{}';ever jsonb:='{}';undoable jsonb:='[]';ordering jsonb:='[]';roster_ids jsonb:='{}';
 before_event jsonb;after_event jsonb;last_change jsonb;eid text;cid text;n integer:=0;stamp timestamptz;result jsonb;
begin
 if jsonb_typeof(doc) is distinct from 'object' or doc-array['schemaVersion','id','context','players','journal']<>'{}' or doc->'schemaVersion' is distinct from '1'::jsonb then raise exception 'Unsupported capture document' using errcode='22023'; end if;
 perform team_private.shot_uuid(doc->'id');
 if jsonb_typeof(doc->'context') is distinct from 'object' or (doc->'context')-array['gameID','teamID','actorID','assignmentRevision']<>'{}'
  or team_private.shot_uuid(doc->'context'->'gameID')<>p_game or team_private.shot_uuid(doc->'context'->'teamID')<>p_team then raise exception 'Capture context mismatch' using errcode='22023'; end if;
 perform team_private.shot_uuid(doc->'context'->'actorID');perform team_private.shot_integer(doc->'context'->'assignmentRevision',1,9223372036854775807);
 players:=doc->'players';
 if jsonb_typeof(players) is distinct from 'array' or jsonb_array_length(players)>1000 or jsonb_typeof(doc->'journal') is distinct from 'array' or jsonb_array_length(doc->'journal')>20000 then raise exception 'Capture bounds exceeded' using errcode='22023'; end if;
 for player in select * from jsonb_array_elements(players) loop
  cid:=team_private.shot_uuid(player->'id')::text;
  if jsonb_typeof(player) is distinct from 'object' or player-array['id','name','number','temporary']<>'{}' or player->'temporary' is distinct from 'false'::jsonb
   or jsonb_typeof(player->'name') is distinct from 'string' or length(btrim(player->>'name')) not between 1 and 100
   or jsonb_typeof(player->'number') is distinct from 'string' or length(btrim(player->>'number')) not between 1 and 10 or roster_ids ? cid then raise exception 'Actual roster identity required' using errcode='22023'; end if;
  roster_ids:=roster_ids||jsonb_build_object(cid,true);
 end loop;
 for change in select * from jsonb_array_elements(doc->'journal') loop
  n:=n+1;cid:=team_private.shot_uuid(change->'id')::text;eid:=team_private.shot_uuid(change->'eventID')::text;
  if jsonb_typeof(change) is distinct from 'object' or change-array['id','revision','recordedAt','eventID','before','after','undoOf']<>'{}'
   or team_private.shot_integer(change->'revision',1,20000)<>n or ids ? cid or jsonb_typeof(change->'recordedAt') is distinct from 'string' then raise exception 'Invalid capture history' using errcode='22023'; end if;
  stamp:=(change->>'recordedAt')::timestamptz;
  if not isfinite(stamp) or stamp<'1970-01-01T00:00:00Z'::timestamptz or stamp>'9999-12-31T23:59:59Z'::timestamptz then raise exception 'Invalid capture provenance date' using errcode='22023'; end if;
  before_event:=nullif(change->'before','null');after_event:=nullif(change->'after','null');
  if before_event is distinct from state->eid or before_event is not distinct from after_event then raise exception 'Capture history disagrees with observation' using errcode='22023'; end if;
  if before_event is not null then perform team_private.shot_event(before_event,players);if team_private.shot_uuid(before_event->'id')::text<>eid then raise exception 'Capture identity changed' using errcode='22023'; end if;end if;
  if after_event is not null then perform team_private.shot_event(after_event,players);if team_private.shot_uuid(after_event->'id')::text<>eid then raise exception 'Capture identity changed' using errcode='22023'; end if;end if;
  if nullif(change->'undoOf','null') is not null then
   last_change:=undoable->-1;
   if last_change is null or team_private.shot_uuid(change->'undoOf')<>team_private.shot_uuid(last_change->'id') or team_private.shot_uuid(last_change->'eventID')::text<>eid
    or before_event is distinct from nullif(last_change->'after','null') or after_event is distinct from nullif(last_change->'before','null') then raise exception 'Invalid capture Undo' using errcode='22023'; end if;
   undoable:=undoable-(jsonb_array_length(undoable)-1);
  else
   if after_event is null or (before_event is not null and before_event->>'kind' is distinct from after_event->>'kind') then raise exception 'Invalid capture correction' using errcode='22023'; end if;
   if before_event is null then
    if ever ? eid then raise exception 'Capture observation identity reused' using errcode='22023'; end if;
    ever:=ever||jsonb_build_object(eid,true);ordering:=ordering||jsonb_build_array(eid);
   end if;
   undoable:=undoable||jsonb_build_array(change);
  end if;
  if after_event is null then state:=state-eid;else state:=state||jsonb_build_object(eid,after_event);end if;
  ids:=ids||jsonb_build_object(cid,true);
 end loop;
 select coalesce(jsonb_agg(state->x.value order by x.ordinality),'[]') into result from jsonb_array_elements_text(ordering) with ordinality x(value,ordinality) where state ? x.value;
 return result;
end $$;

create function public.shots_save(p_team_id uuid,p_game_id uuid,p_assignment_revision bigint,p_expected_revision bigint,p_batch_id uuid,p_document_text text,p_coverage_claim text) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.shot_actor(p_team_id);s team_private.shot_sessions;previous team_private.shot_snapshots;doc jsonb;events jsonb;d text;r jsonb;v_id uuid;payload_digest text;i integer;pl jsonb;
begin
 if not team_private.has_capability(p_team_id,a,'shots.record') then raise exception 'Recording authority required' using errcode='42501'; end if;
 if p_document_text is null or octet_length(p_document_text)>10485760 then raise exception 'Capture byte bound exceeded' using errcode='22023'; end if;
 payload_digest:=encode(sha256(convert_to(p_document_text,'UTF8')),'hex');
 d:=encode(sha256(convert_to(jsonb_build_array('save',p_team_id,p_game_id,p_assignment_revision,p_expected_revision,p_coverage_claim,payload_digest)::text,'UTF8')),'hex');
 r:=team_private.shot_prior(p_team_id,p_game_id,a,p_batch_id,d);if r is not null then return r;end if;
 select * into s from team_private.shot_sessions where game_id=p_game_id and team_id=p_team_id for update;
 if s.recorder_user_id is distinct from a then raise exception 'Designated recorder required' using errcode='42501'; end if;
 if p_assignment_revision is distinct from s.assignment_revision or p_expected_revision is distinct from s.revision then raise exception 'Capture or assignment changed' using errcode='PT409'; end if;
 if p_coverage_claim is null or p_coverage_claim not in ('unknown','partial','manager_declared_full_game') then raise exception 'Explicit coverage declaration required' using errcode='22023'; end if;
 doc:=p_document_text::jsonb;events:=team_private.shot_validate(doc,p_team_id,p_game_id);
 if s.session_id is null then
  if team_private.shot_uuid(doc->'context'->'actorID')<>a or team_private.shot_integer(doc->'context'->'assignmentRevision',1,9223372036854775807)<>s.assignment_revision or jsonb_array_length(doc->'journal')<>0 then raise exception 'Register an empty authorized capture first' using errcode='22023'; end if;
  for pl in select * from jsonb_array_elements(doc->'players') loop
   if not exists(select 1 from public.roster_entries where team_id=p_team_id and id=team_private.shot_uuid(pl->'id') and archived_at is null and display_name=pl->>'name' and jersey_number=pl->>'number' and identity_kind='real') then raise exception 'Current actual roster required' using errcode='22023'; end if;
  end loop;
  update team_private.shot_sessions set session_id=team_private.shot_uuid(doc->'id') where game_id=p_game_id;
 else
  select * into previous from team_private.shot_snapshots where id=s.latest_snapshot_id;
  if s.session_id<>team_private.shot_uuid(doc->'id') or doc-'journal' is distinct from previous.document-'journal' or jsonb_array_length(doc->'journal')<previous.local_revision then raise exception 'Capture history changed' using errcode='PT409'; end if;
  for i in 0..previous.local_revision-1 loop
   if doc->'journal'->i is distinct from previous.document->'journal'->i then raise exception 'Capture branch requires explicit recovery review' using errcode='PT409'; end if;
  end loop;
 end if;
 insert into team_private.shot_snapshots(team_id,game_id,session_id,creator_user_id,uploader_user_id,assignment_revision,local_revision,document,document_digest,parent_snapshot_id,coverage_claim)
  values(p_team_id,p_game_id,team_private.shot_uuid(doc->'id'),team_private.shot_uuid(doc->'context'->'actorID'),a,s.assignment_revision,jsonb_array_length(doc->'journal'),doc,payload_digest,s.latest_snapshot_id,p_coverage_claim) returning id into v_id;
 update team_private.shot_sessions set latest_snapshot_id=v_id,revision=revision+1,head_status='draft' where game_id=p_game_id returning * into s;
 return team_private.shot_receipt(p_team_id,p_game_id,a,p_batch_id,d,'save',jsonb_build_object('batch_id',p_batch_id,'operation','save','team_id',p_team_id,'game_id',p_game_id,'actor_user_id',a,'session_id',s.session_id,'assignment_revision',s.assignment_revision,'state_revision',s.revision,'snapshot_id',v_id,'document_revision',jsonb_array_length(doc->'journal'),'document_digest',payload_digest,'expected_revision',p_expected_revision));
end $$;

create function public.shots_decide(p_team_id uuid,p_game_id uuid,p_assignment_revision bigint,p_expected_revision bigint,p_batch_id uuid,p_snapshot_id uuid,p_action text,p_reason text,p_displaced_snapshot_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.shot_actor(p_team_id);s team_private.shot_sessions;v team_private.shot_snapshots;d text;r jsonb;events jsonb;
begin
 if p_action is null or p_action not in ('submit','approve','reject','publish','adopt') or p_reason is null or length(p_reason)>500 or (p_action<>'adopt' and p_displaced_snapshot_id is not null) then raise exception 'Explicit shot decision required' using errcode='22023'; end if;
 if not team_private.has_capability(p_team_id,a,case when p_action='submit' then 'shots.record' when p_action='publish' then 'shots.publish' else 'shots.review' end) then raise exception 'Shot decision authority required' using errcode='42501'; end if;
 d:=encode(sha256(convert_to(jsonb_build_array(p_action,p_team_id,p_game_id,p_assignment_revision,p_expected_revision,p_snapshot_id,p_reason,p_displaced_snapshot_id)::text,'UTF8')),'hex');
 r:=team_private.shot_prior(p_team_id,p_game_id,a,p_batch_id,d);if r is not null then return r;end if;
 select * into s from team_private.shot_sessions where team_id=p_team_id and game_id=p_game_id for update;
 if s.game_id is null then raise exception 'Capture access denied' using errcode='42501';end if;
 if p_assignment_revision is distinct from s.assignment_revision or p_expected_revision is distinct from s.revision or (p_action<>'adopt' and p_snapshot_id is distinct from s.latest_snapshot_id) then raise exception 'Capture decision changed' using errcode='PT409';end if;
 select * into v from team_private.shot_snapshots where id=p_snapshot_id and game_id=p_game_id;
 if p_action='adopt' then
  if v.id is null or not v.recovery or p_displaced_snapshot_id is distinct from s.latest_snapshot_id or length(btrim(p_reason))=0 then raise exception 'Explicit recovery and displaced head required' using errcode='PT409';end if;
 elsif p_action='submit' then
  if s.recorder_user_id<>a then raise exception 'Designated recorder required' using errcode='42501';end if;
  if s.head_status not in ('draft','rejected') then raise exception 'Capture status changed' using errcode='PT409';end if;
 elsif p_action='publish' then
  if not team_private.is_owner(p_team_id,a) and v.uploader_user_id<>a then raise exception 'Publication bypass is for own capture only' using errcode='42501';end if;
 elsif p_action in ('approve','reject') then
  if s.head_status<>'submitted' then raise exception 'Capture is not submitted' using errcode='PT409';end if;
  if not team_private.is_owner(p_team_id,a) and exists(select 1 from team_private.shot_snapshots where game_id=p_game_id and uploader_user_id=a) then raise exception 'Independent review required' using errcode='42501';end if;
  if p_action='reject' and length(btrim(p_reason))=0 then raise exception 'Review reason required' using errcode='22023';end if;
 end if;
 if p_action in ('approve','publish') then
  events:=team_private.shot_validate(v.document,p_team_id,p_game_id);
  if exists(select 1 from jsonb_array_elements(events) e where case when e->>'kind'='fieldGoal' then e->>'outcome' is null else jsonb_array_length(e->'answers')<>(e->>'freeThrowAttempts')::bigint end) then raise exception 'Pending outcomes remain; keep this capture as a draft' using errcode='22023';end if;
 end if;
 insert into team_private.shot_decisions(team_id,game_id,snapshot_id,actor_user_id,decision,reason,displaced_snapshot_id) values(p_team_id,p_game_id,p_snapshot_id,a,p_action,p_reason,p_displaced_snapshot_id);
 update team_private.shot_sessions set revision=revision+1,
  latest_snapshot_id=case when p_action='adopt' then p_snapshot_id else latest_snapshot_id end,
  head_status=case p_action when 'adopt' then 'draft' when 'submit' then 'submitted' when 'reject' then 'rejected' else 'published' end,
  published_snapshot_id=case when p_action in ('approve','publish') then p_snapshot_id else published_snapshot_id end where game_id=p_game_id returning * into s;
 return team_private.shot_receipt(p_team_id,p_game_id,a,p_batch_id,d,case when p_action in ('approve','reject') then 'review' else p_action end,
  jsonb_build_object('batch_id',p_batch_id,'operation',p_action,'team_id',p_team_id,'game_id',p_game_id,'actor_user_id',a,'assignment_revision',s.assignment_revision,'state_revision',s.revision,'snapshot_id',p_snapshot_id));
end $$;
create function public.shots_receipt(p_team_id uuid,p_game_id uuid,p_batch_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.shot_actor(p_team_id);
begin
 if not(team_private.has_capability(p_team_id,a,'shots.record') or team_private.has_capability(p_team_id,a,'shots.review') or team_private.has_capability(p_team_id,a,'shots.publish')) then raise exception 'Current shot authority required' using errcode='42501';end if;
 return (select team_private.shot_prior(p_team_id,p_game_id,a,p_batch_id,request_digest) from team_private.shot_receipts where team_id=p_team_id and game_id=p_game_id and batch_id=p_batch_id and actor_user_id=a);
end $$;

-- A fork is a proposal, never a replacement or a former-recorder upload exception.
create function public.shots_recovery(p_team_id uuid,p_game_id uuid,p_assignment_revision bigint,p_expected_revision bigint,p_batch_id uuid,p_document_text text) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.shot_actor(p_team_id);s team_private.shot_sessions;head team_private.shot_snapshots;doc jsonb;d text;r jsonb;v_id uuid;payload text;
begin
 select * into s from team_private.shot_sessions where team_id=p_team_id and game_id=p_game_id for update;
 if not(team_private.has_capability(p_team_id,a,'shots.review') or (s.recorder_user_id=a and team_private.has_capability(p_team_id,a,'shots.record'))) then raise exception 'Recovery authority required' using errcode='42501';end if;
 if p_document_text is null or octet_length(p_document_text)>10485760 then raise exception 'Capture byte bound exceeded' using errcode='22023';end if;
 payload:=encode(sha256(convert_to(p_document_text,'UTF8')),'hex');
 d:=encode(sha256(convert_to(jsonb_build_array('recovery',p_team_id,p_game_id,p_assignment_revision,p_expected_revision,payload)::text,'UTF8')),'hex');
 r:=team_private.shot_prior(p_team_id,p_game_id,a,p_batch_id,d);if r is not null then return r;end if;
 if p_assignment_revision is distinct from s.assignment_revision or p_expected_revision is distinct from s.revision or s.session_id is null then raise exception 'Recovery context changed' using errcode='PT409';end if;
 doc:=p_document_text::jsonb;perform team_private.shot_validate(doc,p_team_id,p_game_id);
 select * into head from team_private.shot_snapshots where id=s.latest_snapshot_id;
 if doc-'journal' is distinct from head.document-'journal' then raise exception 'Recovery must preserve registered capture identity' using errcode='22023';end if;
 insert into team_private.shot_snapshots(team_id,game_id,session_id,creator_user_id,uploader_user_id,assignment_revision,local_revision,document,document_digest,parent_snapshot_id,recovery,coverage_claim)
 values(p_team_id,p_game_id,s.session_id,head.creator_user_id,a,s.assignment_revision,jsonb_array_length(doc->'journal'),doc,payload,s.latest_snapshot_id,true,'unknown') returning id into v_id;
 update team_private.shot_sessions set revision=revision+1 where game_id=p_game_id returning * into s;
 return team_private.shot_receipt(p_team_id,p_game_id,a,p_batch_id,d,'recovery',jsonb_build_object('batch_id',p_batch_id,'operation','recovery','team_id',p_team_id,'game_id',p_game_id,'actor_user_id',a,'assignment_revision',s.assignment_revision,'state_revision',s.revision,'snapshot_id',v_id,'document_revision',jsonb_array_length(doc->'journal'),'document_digest',payload,'displaced_snapshot_id',s.latest_snapshot_id));
end $$;
create function public.shots_recoveries(p_team_id uuid,p_game_id uuid,p_after uuid default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.shot_actor(p_team_id);
begin
 if not team_private.has_capability(p_team_id,a,'shots.review') then raise exception 'Recovery review authority required' using errcode='42501';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('snapshot_id',s.id,'local_revision',s.local_revision,'parent_snapshot_id',s.parent_snapshot_id,'uploader_user_id',s.uploader_user_id) order by s.id) from (select s.* from team_private.shot_snapshots s where s.team_id=p_team_id and s.game_id=p_game_id and s.recovery and (p_after is null or s.id>p_after) and not exists(select 1 from team_private.shot_decisions d where d.snapshot_id=s.id and d.decision='adopt') order by s.id limit 50) s),'[]');
end $$;

create function public.shots_recovery_document(p_team_id uuid,p_game_id uuid,p_snapshot_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.shot_actor(p_team_id);doc jsonb;
begin
 if not team_private.has_capability(p_team_id,a,'shots.review') then raise exception 'Recovery review authority required' using errcode='42501';end if;
 select document into doc from team_private.shot_snapshots where team_id=p_team_id and game_id=p_game_id and id=p_snapshot_id and recovery;
 if doc is null then raise exception 'Recovery unavailable' using errcode='42501';end if;return doc;
end $$;

-- Every table remains inaccessible directly, even if a client guesses its name.
do $secure$ declare r record; begin
 for r in select tablename from pg_tables where schemaname='team_private' and tablename like 'shot_%' loop
  execute format('alter table team_private.%I enable row level security',r.tablename);
  execute format('revoke all on team_private.%I from public,anon,authenticated,service_role',r.tablename);
 end loop;
 for r in select p.oid,n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where (n.nspname='public' and p.proname like 'shots_%') or (n.nspname='team_private' and p.proname like 'shot_%') loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',r.oid::regprocedure);
  if r.nspname='public' then execute format('grant execute on function %s to authenticated',r.oid::regprocedure); end if;
 end loop;
end $secure$;
commit;
