-- Prepared web pilot contract. No existing grants, data, providers or schedules change.
begin;
create or replace function team_private.capabilities() returns text[] language sql immutable
set search_path=pg_catalog as $$ select array['stats.review','stats.publish','datasets.reopen','roster.manage','members.manage','plays.author','plays.review','plays.publish','practice.upload','practice.review','practice.publish','film.upload','film.review','film.publish','scouting.upload','scouting.read','shots.record','shots.review','shots.publish','sessions.manage','sessions.record','sessions.review','sessions.publish','sessions.reopen','sessions.clock']::text[] $$;

create table public.web_sessions (
 id uuid primary key,team_id uuid not null references public.teams(id),kind text not null check(kind in ('practice','game')),
 game_id uuid,author_user_id uuid not null references auth.users(id),title text not null check(length(btrim(title)) between 1 and 100),session_date date not null,
 revision bigint not null default 1 check(revision>0),status text not null default 'draft' check(status in ('draft','submitted','published','rejected')),
 current_snapshot_id uuid,accepted_snapshot_id uuid,base_accepted_snapshot_id uuid,
 recorder_user_id uuid not null references auth.users(id),clock_user_id uuid not null references auth.users(id),assignment_revision bigint not null default 1,
 clock_revision bigint not null default 0,clock_period text not null default 'Period 1',clock_seconds numeric not null default 0 check(clock_seconds>=0),clock_started_at timestamptz,
 edit_requested_by uuid references auth.users(id),edit_source_id uuid,
 created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),
 unique(team_id,id),foreign key(team_id,game_id) references public.games(team_id,id),check((kind='game')=(game_id is not null))
);
create table public.web_session_snapshots (
 id uuid primary key default gen_random_uuid(),team_id uuid not null,session_id uuid not null,revision bigint not null,
 author_user_id uuid not null references auth.users(id),document jsonb not null,created_at timestamptz not null default clock_timestamp(),
 unique(team_id,session_id,id),unique(session_id,revision),foreign key(team_id,session_id) references public.web_sessions(team_id,id)
);
create table public.web_session_publications (
 team_id uuid not null,session_id uuid not null,snapshot_id uuid not null,accepted_by uuid not null references auth.users(id),accepted_at timestamptz not null default clock_timestamp(),
 primary key(session_id,snapshot_id),foreign key(team_id,session_id,snapshot_id) references public.web_session_snapshots(team_id,session_id,id)
);
create table public.web_session_receipts (
 team_id uuid not null,actor_user_id uuid not null references auth.users(id),operation_id uuid not null,session_id uuid not null,
 action text not null,payload_hash text not null,result jsonb not null,created_at timestamptz not null default clock_timestamp(),
 primary key(team_id,actor_user_id,operation_id),foreign key(team_id,session_id) references public.web_sessions(team_id,id)
);
alter table public.web_sessions add foreign key(team_id,id,current_snapshot_id) references public.web_session_snapshots(team_id,session_id,id) deferrable initially deferred;
alter table public.web_sessions add foreign key(team_id,id,accepted_snapshot_id) references public.web_session_snapshots(team_id,session_id,id) deferrable initially deferred;
alter table public.web_sessions add foreign key(team_id,id,base_accepted_snapshot_id) references public.web_session_snapshots(team_id,session_id,id) deferrable initially deferred;
create index web_sessions_team_date on public.web_sessions(team_id,session_date,id);
create index web_session_snapshots_session on public.web_session_snapshots(team_id,session_id,revision);

create function team_private.web_keys(v jsonb,allowed text[]) returns void language plpgsql immutable set search_path=pg_catalog as $$
begin if jsonb_typeof(v) is distinct from 'object' or exists(select 1 from jsonb_object_keys(v) k where not(k=any(allowed))) then raise exception 'Unsupported document fields' using errcode='22023';end if;end $$;
create function team_private.web_require(v jsonb,required text[]) returns void language plpgsql immutable set search_path=pg_catalog as $$
begin if jsonb_typeof(v) is distinct from 'object' or not(v ?& required) then raise exception 'Required fields missing' using errcode='22023';end if;end $$;
create function team_private.web_count(v jsonb) returns numeric language plpgsql immutable set search_path=pg_catalog as $$
declare n numeric;
begin if v is null or v='null'::jsonb or v='""'::jsonb then return null;end if;
 if jsonb_typeof(v)<>'string' or (v#>>'{}')!~'^[0-9]+$' or length(v#>>'{}')>16 then raise exception 'Invalid count' using errcode='22023';end if;
 n:=(v#>>'{}')::numeric;if n>9007199254740991 then raise exception 'Count overflow' using errcode='22023';end if;return n;end $$;
create function team_private.web_text(v jsonb,maximum integer,required boolean default false) returns void language plpgsql immutable set search_path=pg_catalog as $$
begin if jsonb_typeof(v)<>'string' or length(v#>>'{}')>maximum or(required and length(btrim(v#>>'{}'))=0) or v is null then raise exception 'Invalid text' using errcode='22023';end if;end $$;
create function team_private.web_template(v jsonb) returns void language plpgsql immutable set search_path=pg_catalog as $$
begin perform team_private.web_require(v,array['id','name','kind','definition','version']);perform team_private.web_keys(v,array['id','name','kind','definition','version']);perform (v->>'id')::uuid;perform team_private.web_text(v->'name',100,true);perform team_private.web_text(v->'definition',4000,true);
 if jsonb_typeof(v->'id') is distinct from 'string' or jsonb_typeof(v->'version') is distinct from 'number' or coalesce(v->>'kind','') not in ('count','makes','timed','note') or(v->>'version')!~'^[1-9][0-9]*$' or(v->>'version')::numeric>9007199254740991 then raise exception 'Invalid template' using errcode='22023';end if;end $$;
create function team_private.web_values(v jsonb,t jsonb,note jsonb) returns void language plpgsql immutable set search_path=pg_catalog as $$
declare m numeric;a numeric;
begin perform team_private.web_template(t);perform team_private.web_text(note,4000,t->>'kind'='note');
 if t->>'kind'='makes' then perform team_private.web_keys(v,array['made','attempts']);m:=team_private.web_count(v->'made');a:=team_private.web_count(v->'attempts');if m>a then raise exception 'Makes exceed attempts' using errcode='22023';end if;
 elsif t->>'kind' in ('count','timed') then perform team_private.web_keys(v,array['count']);perform team_private.web_count(v->'count');else perform team_private.web_keys(v,array[]::text[]);end if;end $$;
create function team_private.web_document(p_team uuid,p_session uuid,p_kind text,d jsonb,previous jsonb default null) returns void language plpgsql security definer set search_path=pg_catalog as $$
declare s jsonb;p jsonb;r jsonb;v jsonb;k text;c jsonb;e jsonb;before_event jsonb;after_event jsonb;events jsonb:='{}';seen text[]:=array[]::text[];players text[]:=array[]::text[];changes jsonb;old_changes jsonb;found_change jsonb;event_ids text[]:=array[]::text[];undone text[]:=array[]::text[];i integer;version_number bigint;old jsonb;
begin
 if octet_length(d::text)>2097152 then raise exception 'Document too large' using errcode='22023';end if;
 perform team_private.web_require(d,array['schema','session']);if jsonb_typeof(d->'schema') is distinct from 'number' then raise exception 'Invalid schema type' using errcode='22023';end if;perform team_private.web_keys(d,array['schema','session']);if d->>'schema' is distinct from '1' then raise exception 'Unknown schema' using errcode='22023';end if;s:=d->'session';
 perform team_private.web_require(s,array['id','kind','title','date','venue','season','players','spots','protocol','plan','shooting','ft','observations','changes','savedAt']);perform team_private.web_keys(s,array['id','kind','title','date','venue','season','players','spots','protocol','plan','shooting','ft','observations','changes','savedAt']);perform team_private.web_text(s->'savedAt',40,true);perform(s->>'savedAt')::timestamptz;
 if(s->>'id')::uuid is distinct from p_session or s->>'kind' is distinct from p_kind then raise exception 'Wrong session identity' using errcode='22023';end if;
 perform team_private.web_text(s->'title',100,true);perform team_private.web_text(s->'protocol',4000);perform (s->>'date')::date;if coalesce(s->>'date','')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or not isfinite((s->>'date')::date) then raise exception 'Invalid session date' using errcode='22023';end if;
 if coalesce(s->>'venue','') not in ('home','away') or coalesce(s->>'season','') not in ('regularSeason','playoff') then raise exception 'Invalid game metadata' using errcode='22023';end if;
 if jsonb_typeof(s->'players') is distinct from 'array' or jsonb_array_length(s->'players')>500 or jsonb_typeof(s->'spots') is distinct from 'array' or jsonb_array_length(s->'spots')<>9 or jsonb_typeof(s->'plan') is distinct from 'array' or jsonb_array_length(s->'plan')>500 or jsonb_typeof(s->'observations') is distinct from 'array' or jsonb_typeof(s->'changes') is distinct from 'array' then raise exception 'Invalid session collections' using errcode='22023';end if;
 for p in select value from jsonb_array_elements(s->'players') loop
 perform team_private.web_require(p,array['id','name','number','version']);perform team_private.web_keys(p,array['id','name','number','version']);if jsonb_typeof(p->'id') is distinct from 'string' or jsonb_typeof(p->'version') is distinct from 'number' then raise exception 'Invalid roster types' using errcode='22023';end if;perform team_private.web_text(p->'name',100,true);perform team_private.web_text(p->'number',10,true);version_number:=(p->>'version')::bigint;
 if lower(p->>'id')=any(players) or not exists(select 1 from public.roster_entry_revisions rr where rr.team_id=p_team and rr.roster_id=(p->>'id')::uuid and rr.version=version_number and rr.display_name=p->>'name' and rr.jersey_number=p->>'number' and rr.archived_at is null) then raise exception 'Real roster revision required' using errcode='22023';end if;players:=array_append(players,lower(p->>'id'));end loop;
 for p in select value from jsonb_array_elements(s->'spots') loop perform team_private.web_text(p,80,true);end loop;
 for p in select value from jsonb_array_elements(s->'plan') loop perform team_private.web_require(p,array['id','name','minutes','instructions']);perform team_private.web_text(p->'id',36,true);perform team_private.web_keys(p,array['id','name','minutes','instructions','template']);perform(p->>'id')::uuid;perform team_private.web_text(p->'name',100);perform team_private.web_count(p->'minutes');perform team_private.web_text(p->'instructions',4000);if p?'template' then perform team_private.web_template(p->'template');end if;end loop;
 perform team_private.web_keys(s->'shooting',players);perform team_private.web_keys(s->'ft',players);
 for k,r in select key,value from jsonb_each(s->'shooting') loop perform team_private.web_keys(r,array['0','1','2','3','4','5','6','7','8']);for v in select value from jsonb_each(r) loop perform team_private.web_values(v,'{"id":"00000000-0000-0000-0000-000000000001","name":"Observed shooting","kind":"makes","definition":"Observed makes and attempts","version":1}','""');end loop;end loop;
 for v in select value from jsonb_each(s->'ft') loop perform team_private.web_values(v,'{"id":"00000000-0000-0000-0000-000000000001","name":"Observed free throws","kind":"makes","definition":"Observed makes and attempts","version":1}','""');end loop;
 for p in select value from jsonb_array_elements(s->'observations') loop
 perform team_private.web_require(p,array['id','playerID','template','values','note','at']);perform team_private.web_keys(p,array['id','playerID','template','values','note','at','supersedes','withdrawn','correctedAt']);perform team_private.web_text(p->'id',36,true);perform team_private.web_text(p->'at',40,true);perform(p->>'id')::uuid;
 if p->>'id'=any(seen) or p?'supersedes' and not(p->>'supersedes'=any(seen)) then raise exception 'Invalid observation lineage' using errcode='22023';end if;seen:=array_append(seen,p->>'id');
 if p->'playerID'<>'null'::jsonb and not(lower(p->>'playerID')=any(players)) then raise exception 'Wrong observation player' using errcode='22023';end if;
 perform(p->>'at')::timestamptz;if not isfinite((p->>'at')::timestamptz) then raise exception 'Invalid observation time' using errcode='22023';end if;perform team_private.web_values(p->'values',p->'template',p->'note');
 if p?'withdrawn' and jsonb_typeof(p->'withdrawn')<>'boolean' then raise exception 'Invalid withdrawal' using errcode='22023';end if;
 end loop;
 changes:=s->'changes';old_changes:=coalesce(previous->'session'->'changes','[]');
 if jsonb_array_length(changes)<jsonb_array_length(old_changes) then raise exception 'History cannot be removed' using errcode='22023';end if;
 if previous is not null then
 for i in 0..jsonb_array_length(old_changes)-1 loop if changes->i is distinct from old_changes->i then raise exception 'History prefix changed' using errcode='22023';end if;end loop;
 old:=previous->'session'->'observations';if jsonb_array_length(s->'observations')<jsonb_array_length(old) then raise exception 'Observation history cannot be removed' using errcode='22023';end if;
 for i in 0..jsonb_array_length(old)-1 loop if s->'observations'->i is distinct from old->i then raise exception 'Observation history prefix changed' using errcode='22023';end if;end loop;
 if previous->'session'->'players' is distinct from s->'players' then raise exception 'Session roster is immutable' using errcode='22023';end if;
 if (previous->'session'->'shooting'<>'{}' or previous->'session'->'ft'<>'{}' or jsonb_array_length(old)>0 or jsonb_array_length(old_changes)>0) and ((previous->'session'->'plan') is distinct from s->'plan' or(previous->'session'->'spots') is distinct from s->'spots' or(previous->'session'->'protocol') is distinct from s->'protocol') then raise exception 'Used session definitions are frozen; create a new session for new definitions' using errcode='22023';end if;
 end if;
 seen:=array[]::text[];
 for c in select value from jsonb_array_elements(changes) loop
 perform team_private.web_require(c,array['id','eventID','before','after','at']);perform team_private.web_keys(c,array['id','eventID','before','after','at','undoOf']);perform team_private.web_text(c->'id',36,true);perform team_private.web_text(c->'eventID',36,true);perform team_private.web_text(c->'at',40,true);perform(c->>'id')::uuid;perform(c->>'eventID')::uuid;perform(c->>'at')::timestamptz;
 if not isfinite((c->>'at')::timestamptz) or c->>'id'=any(seen) then raise exception 'Invalid change identity/time' using errcode='22023';end if;
 before_event:=coalesce(c->'before','null');after_event:=coalesce(c->'after','null');if coalesce(events->(c->>'eventID'),'null') is distinct from before_event then raise exception 'Invalid correction before-image' using errcode='22023';end if;
 if after_event='null' and not(c?'undoOf') or before_event='null' and after_event<>'null' and c->>'eventID'=any(event_ids) and not(c?'undoOf') then raise exception 'Only validated Undo can remove or restore an existing event' using errcode='22023';end if;
 if before_event='null' and after_event='null' then raise exception 'Empty history change' using errcode='22023';end if;
 if c?'undoOf' then
 select value into found_change from jsonb_array_elements(changes) where value->>'id'=c->>'undoOf' and value->>'id'=any(seen);
 if found_change is null or found_change?'undoOf' or c->>'undoOf'=any(undone) or found_change->>'eventID'<>c->>'eventID' or coalesce(found_change->'after','null') is distinct from before_event or coalesce(found_change->'before','null') is distinct from after_event then raise exception 'Invalid Undo target' using errcode='22023';end if;undone:=array_append(undone,c->>'undoOf');end if;
 for e in select value from jsonb_array_elements(jsonb_build_array(before_event,after_event)) where value<>'null' loop
 perform team_private.web_require(e,array['id','kind','team','playerID','x','y','value','made','label','note','at','period','clock']);perform team_private.web_keys(e,array['id','kind','team','playerID','x','y','value','made','label','note','at','period','clock','template','values']);perform team_private.web_text(e->'id',36,true);perform team_private.web_text(e->'at',40,true);if jsonb_typeof(e->'clock') is distinct from 'number' or jsonb_typeof(e->'value') is distinct from 'number' then raise exception 'Invalid event number types' using errcode='22023';end if;
 if e->>'id'<>c->>'eventID' or coalesce(e->>'kind','') not in ('shot','freeThrow','event') or coalesce(e->>'team','') not in ('ours','opponent') or(e->>'clock')!~'^[0-9]+$' or(e->>'clock')::numeric>9007199254740991 then raise exception 'Invalid captured event' using errcode='22023';end if;
 perform(e->>'at')::timestamptz;if not isfinite((e->>'at')::timestamptz) then raise exception 'Invalid captured time' using errcode='22023';end if;perform team_private.web_text(e->'period',40,true);perform team_private.web_text(e->'note',4000);perform team_private.web_text(e->'label',100);
 if e->>'team'='ours' and not(coalesce(lower(e->>'playerID'),'')=any(players)) or e->>'team'='opponent' and e->'playerID' is distinct from 'null'::jsonb then raise exception 'Wrong player attribution' using errcode='22023';end if;
 if e->>'kind'='shot' then if e->>'value' not in ('2','3') or jsonb_typeof(e->'x') is distinct from 'number' or jsonb_typeof(e->'y') is distinct from 'number' or(e->>'x')::numeric not between 0 and 1 or(e->>'y')::numeric not between 0 and 1 then raise exception 'Invalid court location/value' using errcode='22023';end if;
 else if e->'x' is distinct from 'null'::jsonb or e->'y' is distinct from 'null'::jsonb then raise exception 'Non-court event cannot have location' using errcode='22023';end if;end if;
 if e->>'kind'='freeThrow' and e->>'value'<>'1' or e->>'kind'<>'event' and jsonb_typeof(e->'made') is distinct from 'boolean' then raise exception 'Invalid attempt result' using errcode='22023';end if;
 if e->>'kind'='event' then if e->'made' is distinct from 'null'::jsonb then raise exception 'Event is not an attempt' using errcode='22023';end if;perform team_private.web_values(e->'values',e->'template',e->'note');end if;
 end loop;
 if before_event<>'null' and after_event<>'null' and (before_event->'at' is distinct from after_event->'at' or before_event->'clock' is distinct from after_event->'clock' or before_event->'period' is distinct from after_event->'period') then raise exception 'Historical event reading cannot change' using errcode='22023';end if;
 if after_event='null' then events:=events-(c->>'eventID');else events:=jsonb_set(events,array[c->>'eventID'],after_event,true);end if;seen:=array_append(seen,c->>'id');event_ids:=array_append(event_ids,c->>'eventID');
 end loop;
exception when invalid_text_representation or datetime_field_overflow or invalid_datetime_format or numeric_value_out_of_range then raise exception 'Malformed session payload' using errcode='22023';
end $$;

alter table public.web_sessions add column contributors uuid[] not null default '{}';
create function team_private.web_permission(p_team uuid,p_action text) returns boolean language sql stable security definer set search_path=pg_catalog as $$
 select team_private.can_read(p_team) and case
 when p_action='create' or p_action='assign' then team_private.has_capability(p_team,team_private.actor(),'sessions.manage')
 when p_action in ('save','submit','request_edit') then team_private.has_capability(p_team,team_private.actor(),'sessions.record') or team_private.has_capability(p_team,team_private.actor(),'sessions.manage')
 when p_action='review' then team_private.has_capability(p_team,team_private.actor(),'sessions.review')
 when p_action='publish' then team_private.has_capability(p_team,team_private.actor(),'sessions.publish')
 when p_action='reopen' then team_private.has_capability(p_team,team_private.actor(),'sessions.reopen')
 when p_action in ('clock_set','clock_start','clock_stop') then team_private.has_capability(p_team,team_private.actor(),'sessions.clock') else false end
$$;
create function team_private.web_read_snapshot(p_team uuid,p_session uuid,p_snapshot uuid) returns boolean language sql stable security definer set search_path=pg_catalog as $$
 select team_private.can_read(p_team) and (exists(select 1 from public.web_session_publications where team_id=p_team and session_id=p_session and snapshot_id=p_snapshot) or exists(select 1 from public.web_sessions s where s.team_id=p_team and s.id=p_session and(team_private.actor()=s.author_user_id or team_private.actor()=s.recorder_user_id or team_private.actor()=any(s.contributors))) or team_private.has_capability(p_team,team_private.actor(),'sessions.review') or team_private.has_capability(p_team,team_private.actor(),'sessions.reopen'))
$$;
create function team_private.web_visible_receipt(r jsonb,p_team uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
begin if not team_private.web_read_snapshot(p_team,(r->'session'->>'id')::uuid,(r->'session'->>'current_snapshot_id')::uuid) then return jsonb_set(r,'{document}','null')||jsonb_build_object('visibility','metadata_only');end if;return r;end $$;
create function public.web_session_command(p_team_id uuid,p_operation_id uuid,p_action text,p_session_id uuid,p_expected_revision bigint,p_expected_access_revision bigint,p_document jsonb default null,p_argument jsonb default '{}') returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare actor uuid;s public.web_sessions;prior jsonb;snapshot uuid;result jsonb;receipt public.web_session_receipts;fingerprint text;new_doc jsonb;seconds numeric;now_at timestamptz:=clock_timestamp();game uuid;clock_actor uuid;recorder uuid;cap text;changed_records boolean;
begin
 actor:=team_private.command_actor(p_team_id,p_expected_access_revision);
 if not team_private.web_permission(p_team_id,p_action) then raise exception 'Session capability required' using errcode='42501';end if;
 if p_operation_id is null or p_session_id is null or p_expected_revision is null or p_expected_revision<0 or octet_length(p_argument::text)>16384 then raise exception 'Invalid command identity or argument' using errcode='22023';end if;
 fingerprint:=encode(sha256(convert_to(jsonb_build_object('action',p_action,'session',p_session_id,'expected',p_expected_revision,'document',p_document,'argument',p_argument)::text,'UTF8')),'hex');
 select * into receipt from public.web_session_receipts where team_id=p_team_id and actor_user_id=actor and operation_id=p_operation_id;
 if found then if receipt.payload_hash<>fingerprint then raise exception 'Operation identity reused with changed content' using errcode='PT409';end if;return team_private.web_visible_receipt(receipt.result,p_team_id);end if;
 if p_action='create' then
 if p_expected_revision<>0 or exists(select 1 from public.web_sessions where id=p_session_id) then raise exception 'Session already exists' using errcode='PT409';end if;
 if (p_document->'session'->'shooting'<>'{}' or p_document->'session'->'ft'<>'{}' or jsonb_array_length(p_document->'session'->'observations')>0 or jsonb_array_length(p_document->'session'->'changes')>0) and not team_private.has_capability(p_team_id,actor,'sessions.record') then raise exception 'Collection authority required for populated creation' using errcode='42501';end if;
 perform team_private.web_keys(p_argument,array['game_id']);game:=(p_argument->>'game_id')::uuid;
 perform team_private.web_document(p_team_id,p_session_id,p_document->'session'->>'kind',p_document);
 if game is not null and not exists(select 1 from public.games where team_id=p_team_id and id=game) then raise exception 'Wrong game scope' using errcode='42501';end if;
 insert into public.web_sessions(id,team_id,kind,game_id,author_user_id,title,session_date,recorder_user_id,clock_user_id,contributors)
 values(p_session_id,p_team_id,p_document->'session'->>'kind',game,actor,p_document->'session'->>'title',(p_document->'session'->>'date')::date,actor,actor,array[actor]) returning * into s;
 insert into public.web_session_snapshots(team_id,session_id,revision,author_user_id,document) values(p_team_id,p_session_id,1,actor,p_document) returning id into snapshot;
 update public.web_sessions set current_snapshot_id=snapshot where id=s.id returning * into s;
 else
 select * into s from public.web_sessions where team_id=p_team_id and id=p_session_id for update;
 if not found then raise exception 'Session access denied' using errcode='42501';end if;
 select document into prior from public.web_session_snapshots where id=s.current_snapshot_id;
 if p_action like 'clock_%' then
 if actor<>s.clock_user_id or not team_private.has_capability(p_team_id,actor,'sessions.clock') then raise exception 'Assigned clock recorder required' using errcode='42501';end if;
 if p_action='clock_set' then perform team_private.web_require(p_argument,array['assignment_revision','period','seconds']);perform team_private.web_keys(p_argument,array['assignment_revision','period','seconds']);else perform team_private.web_require(p_argument,array['assignment_revision']);perform team_private.web_keys(p_argument,array['assignment_revision']);end if;
 if p_expected_revision<>s.clock_revision or(p_argument->>'assignment_revision')::bigint is distinct from s.assignment_revision then raise exception 'Stale clock authority/revision' using errcode='PT409';end if;
 seconds:=greatest(0,s.clock_seconds-case when s.clock_started_at is null then 0 else extract(epoch from(now_at-s.clock_started_at)) end);
 if p_action='clock_set' then
 perform team_private.web_text(p_argument->'period',40,true);
 if jsonb_typeof(p_argument->'seconds')<>'number' or(p_argument->>'seconds')!~'^[0-9]+$' or(p_argument->>'seconds')::numeric>9007199254740991 then raise exception 'Invalid clock seconds' using errcode='22023';end if;
 update public.web_sessions set clock_period=p_argument->>'period',clock_seconds=(p_argument->>'seconds')::numeric,clock_started_at=null,clock_revision=clock_revision+1,updated_at=now_at where id=s.id returning * into s;
 elsif p_action='clock_start' then if seconds<=0 or s.clock_started_at is not null then raise exception 'Clock must be stopped with remaining time' using errcode='PT409';end if;
 update public.web_sessions set clock_seconds=seconds,clock_started_at=now_at,clock_revision=clock_revision+1,updated_at=now_at where id=s.id returning * into s;
 else update public.web_sessions set clock_seconds=seconds,clock_started_at=null,clock_revision=clock_revision+1,updated_at=now_at where id=s.id returning * into s;end if;
 elsif p_action='assign' then
 perform team_private.web_keys(p_argument,array['recorder_user_id','clock_user_id','assignment_revision']);
 if p_expected_revision<>s.revision or(p_argument->>'assignment_revision')::bigint is distinct from s.assignment_revision then raise exception 'Stale assignment' using errcode='PT409';end if;
 recorder:=(p_argument->>'recorder_user_id')::uuid;clock_actor:=(p_argument->>'clock_user_id')::uuid;
 if not team_private.has_capability(p_team_id,recorder,'sessions.record') or not team_private.has_capability(p_team_id,clock_actor,'sessions.clock') then raise exception 'Eligible recorders required' using errcode='42501';end if;
 seconds:=greatest(0,s.clock_seconds-case when s.clock_started_at is null then 0 else extract(epoch from(now_at-s.clock_started_at)) end);
 update public.web_sessions set recorder_user_id=recorder,clock_user_id=clock_actor,assignment_revision=assignment_revision+1,clock_seconds=seconds,clock_started_at=null,clock_revision=clock_revision+1,updated_at=now_at where id=s.id returning * into s;
 else
 if p_expected_revision<>s.revision then raise exception 'Stale session revision' using errcode='PT409';end if;
 if p_action='save' then
 perform team_private.web_keys(p_argument,array['assignment_revision']);
 if s.status<>'draft' then raise exception 'Frozen proposal requires approved reopening' using errcode='PT409';end if;
 if(p_argument->>'assignment_revision')::bigint is distinct from s.assignment_revision then raise exception 'Stale recorder fence' using errcode='PT409';end if;
 perform team_private.web_document(p_team_id,s.id,s.kind,p_document,prior);
 changed_records:=(p_document->'session'->'shooting') is distinct from prior->'session'->'shooting' or(p_document->'session'->'ft') is distinct from prior->'session'->'ft' or(p_document->'session'->'observations') is distinct from prior->'session'->'observations' or(p_document->'session'->'changes') is distinct from prior->'session'->'changes';
 if changed_records and(actor<>s.recorder_user_id or not team_private.has_capability(p_team_id,actor,'sessions.record')) then raise exception 'Assigned collection recorder required' using errcode='42501';end if;
 if ((p_document->'session')-array['shooting','ft','observations','changes','savedAt']) is distinct from ((prior->'session')-array['shooting','ft','observations','changes','savedAt']) and not team_private.has_capability(p_team_id,actor,'sessions.manage') then raise exception 'Plan authority required' using errcode='42501';end if;
 new_doc:=p_document;
 elsif p_action='submit' then
 if s.status<>'draft' or actor<>s.recorder_user_id then raise exception 'Only current recorder can submit a draft' using errcode='42501';end if;
 update public.web_sessions set status='submitted' where id=s.id;s.status:='submitted';new_doc:=prior;
 elsif p_action in ('review','publish') then
 perform team_private.web_keys(p_argument,array['approve']);
 if s.status<>'submitted' then raise exception 'Exact submitted proposal required' using errcode='PT409';end if;
 if p_action='review' and actor=any(s.contributors) and not team_private.is_owner(p_team_id,actor) then raise exception 'Independent reviewer required' using errcode='42501';end if;
 if p_action='publish' and actor<>s.author_user_id and actor<>s.recorder_user_id then raise exception 'Publication bypass is for own proposal' using errcode='42501';end if;
 if p_action='review' and jsonb_typeof(p_argument->'approve') is distinct from 'boolean' then raise exception 'Review answer required' using errcode='22023';end if;
 if p_action='publish' or(p_argument->>'approve')::boolean then
 insert into public.web_session_publications(team_id,session_id,snapshot_id,accepted_by) values(p_team_id,s.id,s.current_snapshot_id,actor);
 update public.web_sessions set accepted_snapshot_id=current_snapshot_id,status='published' where id=s.id returning * into s;
 else update public.web_sessions set status='rejected' where id=s.id returning * into s;end if;new_doc:=prior;
 elsif p_action='request_edit' then
 perform team_private.web_keys(p_argument,array[]::text[]);if s.status not in ('published','submitted','rejected') or s.edit_requested_by is not null then raise exception 'No frozen proposal available or request pending' using errcode='PT409';end if;
 update public.web_sessions set edit_requested_by=actor,edit_source_id=current_snapshot_id where id=s.id returning * into s;new_doc:=prior;
 elsif p_action='reopen' then
 perform team_private.web_keys(p_argument,array[]::text[]);if s.edit_requested_by is null or not exists(select 1 from public.web_session_snapshots source where source.id=s.edit_source_id and source.team_id=s.team_id and source.session_id=s.id and source.document=prior) then raise exception 'Current edit request required' using errcode='PT409';end if;
 if not team_private.has_capability(p_team_id,s.edit_requested_by,'sessions.record') then raise exception 'Eligible requester required' using errcode='42501';end if;
 if actor=s.edit_requested_by and not team_private.is_owner(p_team_id,actor) then raise exception 'Independent reopening approval required' using errcode='42501';end if;
 update public.web_sessions set status='draft',base_accepted_snapshot_id=accepted_snapshot_id,author_user_id=edit_requested_by,recorder_user_id=edit_requested_by,contributors=array[edit_requested_by],edit_requested_by=null,edit_source_id=null,assignment_revision=assignment_revision+1 where id=s.id returning * into s;new_doc:=prior;
 else raise exception 'Unsupported session action' using errcode='22023';end if;
 insert into public.web_session_snapshots(team_id,session_id,revision,author_user_id,document) values(p_team_id,s.id,s.revision+1,actor,new_doc) returning id into snapshot;
 update public.web_sessions set revision=revision+1,current_snapshot_id=snapshot,title=new_doc->'session'->>'title',session_date=(new_doc->'session'->>'date')::date,contributors=case when p_action='save' and not(actor=any(contributors)) then array_append(contributors,actor) else contributors end,updated_at=now_at where id=s.id returning * into s;
 end if;
 end if;
 select document into new_doc from public.web_session_snapshots where id=s.current_snapshot_id;
 if not team_private.web_read_snapshot(p_team_id,s.id,s.current_snapshot_id) then new_doc:=null;end if;
 result:=jsonb_build_object('session',to_jsonb(s),'document',new_doc,'server_time',now_at,'operation_id',p_operation_id);
 insert into public.web_session_receipts(team_id,actor_user_id,operation_id,session_id,action,payload_hash,result) values(p_team_id,actor,p_operation_id,s.id,p_action,fingerprint,result);
 insert into public.team_audit_events(team_id,actor_user_id,action,target_id) values(p_team_id,actor,'web_session.'||p_action,s.id);
 return result;
end $$;

create function public.web_session_receipt(p_team_id uuid,p_operation_id uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare r public.web_session_receipts;actor uuid:=team_private.actor();
begin select * into r from public.web_session_receipts where team_id=p_team_id and actor_user_id=actor and operation_id=p_operation_id;
 if actor is null or not team_private.can_read(p_team_id) or found and not team_private.web_permission(p_team_id,r.action) then raise exception 'Receipt access denied' using errcode='42501';end if;
 return case when r.operation_id is null then null else team_private.web_visible_receipt(r.result,p_team_id) end;end $$;
create function public.web_session_state(p_team_id uuid,p_session_id uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare s public.web_sessions;d jsonb;snapshot uuid;scope text;revision bigint;at_time timestamptz:=clock_timestamp();
begin if not team_private.can_read(p_team_id) then raise exception 'Current team membership required' using errcode='42501';end if;
 select * into s from public.web_sessions where team_id=p_team_id and id=p_session_id for share;
 if not found then raise exception 'Session unavailable' using errcode='42501';end if;
 if team_private.web_read_snapshot(p_team_id,s.id,s.current_snapshot_id) then snapshot:=s.current_snapshot_id;scope:='working';
 elsif s.accepted_snapshot_id is not null then snapshot:=s.accepted_snapshot_id;scope:='accepted';else scope:='unavailable';end if;
 if snapshot is not null then select document,web_session_snapshots.revision into d,revision from public.web_session_snapshots where id=snapshot;end if;
 return jsonb_build_object('session',to_jsonb(s),'document',d,'document_scope',scope,'document_snapshot_id',snapshot,'document_revision',revision,'server_time',at_time);
end $$;
revoke all on function public.web_session_state(uuid,uuid) from public,anon;
grant execute on function public.web_session_state(uuid,uuid) to authenticated;
alter table public.web_sessions enable row level security;
alter table public.web_session_snapshots enable row level security;
alter table public.web_session_publications enable row level security;
alter table public.web_session_receipts enable row level security;
create policy web_sessions_read on public.web_sessions for select to authenticated using(team_private.can_read(team_id));
create policy web_snapshots_read on public.web_session_snapshots for select to authenticated using(team_private.web_read_snapshot(team_id,session_id,id));
create policy web_publications_read on public.web_session_publications for select to authenticated using(team_private.can_read(team_id));
create policy web_receipts_read on public.web_session_receipts for select to authenticated using(actor_user_id=team_private.actor() and team_private.web_permission(team_id,action));
revoke all on public.web_sessions,public.web_session_snapshots,public.web_session_publications,public.web_session_receipts from public,anon,authenticated;
grant select on public.web_sessions,public.web_session_snapshots,public.web_session_publications to authenticated;
revoke all on function team_private.web_visible_receipt(jsonb,uuid),team_private.web_require(jsonb,text[]),team_private.web_keys(jsonb,text[]),team_private.web_count(jsonb),team_private.web_text(jsonb,integer,boolean),team_private.web_template(jsonb),team_private.web_values(jsonb,jsonb,jsonb),team_private.web_document(uuid,uuid,text,jsonb,jsonb),team_private.web_permission(uuid,text),team_private.web_read_snapshot(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function team_private.web_permission(uuid,text),team_private.web_read_snapshot(uuid,uuid,uuid) to authenticated;
revoke all on function public.web_session_command(uuid,uuid,text,uuid,bigint,bigint,jsonb,jsonb),public.web_session_receipt(uuid,uuid) from public,anon;
grant execute on function public.web_session_command(uuid,uuid,text,uuid,bigint,bigint,jsonb,jsonb),public.web_session_receipt(uuid,uuid) to authenticated;
commit;
