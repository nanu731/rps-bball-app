-- Preparation only: apply solely to a fresh isolated synthetic database in this task.
begin;
create table team_private.shot_coverage_attestations (
 id uuid primary key, team_id uuid not null, game_id uuid not null, snapshot_id uuid not null,
 actor_user_id uuid not null references auth.users(id), assignment_revision bigint not null check(assignment_revision>0),
 expected_revision bigint not null check(expected_revision>0), state_revision bigint not null check(state_revision=expected_revision+1),
 decision text not null check(decision in ('confirm','approve')), confirmation_id uuid,
 created_at timestamptz not null default now(),
 check((decision='confirm' and confirmation_id is null) or (decision='approve' and confirmation_id is not null)),
 unique(game_id,snapshot_id,id), unique(game_id,snapshot_id,assignment_revision,decision),
 foreign key(team_id,game_id) references public.games(team_id,id),
 foreign key(game_id,snapshot_id) references team_private.shot_snapshots(game_id,id),
 foreign key(game_id,snapshot_id,confirmation_id) references team_private.shot_coverage_attestations(game_id,snapshot_id,id)
);
alter table team_private.shot_coverage_attestations enable row level security;
revoke all on team_private.shot_coverage_attestations from public,anon,authenticated,service_role;
create trigger shot_coverage_immutable before update or delete on team_private.shot_coverage_attestations
 for each row execute function team_private.append_only();

create function team_private.shot_coverage(p_team uuid,p_game uuid,p_snapshot uuid,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare s team_private.shot_sessions;c team_private.shot_coverage_attestations;v team_private.shot_coverage_attestations;
begin
 select * into s from team_private.shot_sessions where game_id=p_game and team_id=p_team;
 select * into c from team_private.shot_coverage_attestations where game_id=p_game and snapshot_id=p_snapshot
  and decision='confirm' and assignment_revision=s.assignment_revision;
 select * into v from team_private.shot_coverage_attestations where game_id=p_game and snapshot_id=p_snapshot
  and decision='approve' order by created_at desc,id desc limit 1;
 return jsonb_build_object('snapshot_id',p_snapshot,
  'status',case when p_snapshot is null then 'not_recorded' when v.id is not null then 'approved' when c.id is not null then 'awaiting_review' else 'not_confirmed' end,
  'confirmation_id',coalesce(v.confirmation_id,c.id),'approval_id',v.id,
  'can_confirm',p_snapshot is not null and p_snapshot=s.latest_snapshot_id and c.id is null and v.id is null and s.recorder_user_id=p_actor and team_private.has_capability(p_team,p_actor,'shots.record'),
  'can_approve',p_snapshot is not null and p_snapshot=s.latest_snapshot_id and c.id is not null and v.id is null and team_private.has_capability(p_team,p_actor,'stats.review'));
end $$;
revoke all on function team_private.shot_coverage(uuid,uuid,uuid,uuid) from public,anon,authenticated,service_role;

create or replace function public.shots_state(p_team_id uuid,p_game_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.shot_actor(p_team_id);s team_private.shot_sessions;v team_private.shot_snapshots; privileged boolean;
begin
 perform 1 from public.games where team_id=p_team_id and id=p_game_id;
 if not found then raise exception 'Game access denied' using errcode='42501'; end if;
 select * into s from team_private.shot_sessions where game_id=p_game_id and team_id=p_team_id;
 privileged:=team_private.has_capability(p_team_id,a,'stats.review') or team_private.has_capability(p_team_id,a,'shots.review') or (s.recorder_user_id=a and team_private.has_capability(p_team_id,a,'shots.record'));
 if privileged then select * into v from team_private.shot_snapshots where id=s.latest_snapshot_id;
 else select * into v from team_private.shot_snapshots where id=s.published_snapshot_id; end if;
 return jsonb_build_object('team_id',p_team_id,'game_id',p_game_id,'session_id',s.session_id,'recorder_user_id',s.recorder_user_id,
  'assignment_revision',coalesce(s.assignment_revision,0),'state_revision',coalesce(s.revision,0),
  'snapshot_id',v.id,'document',v.document,'coverage_claim',v.coverage_claim,'coverage',team_private.shot_coverage(p_team_id,p_game_id,v.id,a),
  'status',case when s.game_id is null then 'not_started' when not coalesce(privileged,false) then case when v.id is null then 'no_published_capture' else 'published' end else s.head_status end,
  'can_record',coalesce(s.recorder_user_id=a and team_private.has_capability(p_team_id,a,'shots.record'),false),
  'server_time',clock_timestamp(),'recording_valid_until',(select min(g.expires_at) from public.capability_grants g where g.team_id=p_team_id and g.user_id=a and g.capability='shots.record' and g.revoked_at is null and g.expires_at>clock_timestamp()),
  'can_review',team_private.has_capability(p_team_id,a,'shots.review'),'can_publish',team_private.has_capability(p_team_id,a,'shots.publish'));
end $$;

create function team_private.shot_coverage_receipt(v team_private.shot_coverage_attestations) returns jsonb
language sql immutable set search_path=pg_catalog as $$
 select jsonb_build_object('batch_id',v.id,'operation','coverage_'||v.decision,'team_id',v.team_id,'game_id',v.game_id,
  'actor_user_id',v.actor_user_id,'snapshot_id',v.snapshot_id,'confirmation_id',coalesce(v.confirmation_id,v.id),
  'assignment_revision',v.assignment_revision,'state_revision',v.state_revision)
$$;
revoke all on function team_private.shot_coverage_receipt(team_private.shot_coverage_attestations) from public,anon,authenticated,service_role;

create function public.shots_coverage_decide(p_team_id uuid,p_game_id uuid,p_assignment_revision bigint,p_expected_revision bigint,p_batch_id uuid,p_snapshot_id uuid,p_action text,p_confirmation_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.shot_actor(p_team_id);s team_private.shot_sessions;r team_private.shot_coverage_attestations;c team_private.shot_coverage_attestations;
begin
 select * into s from team_private.shot_sessions where team_id=p_team_id and game_id=p_game_id for update;
 if s.game_id is null then raise exception 'Saved capture required' using errcode='42501';end if;
 if p_action='confirm' then
  if s.recorder_user_id<>a or not team_private.has_capability(p_team_id,a,'shots.record') then raise exception 'Current designated recorder required' using errcode='42501';end if;
 elsif p_action='approve' then
  if not team_private.has_capability(p_team_id,a,'stats.review') then raise exception 'Current statistics review authority required' using errcode='42501';end if;
 else raise exception 'Coverage decision required' using errcode='22023';end if;
 if p_batch_id is null or p_batch_id='00000000-0000-0000-0000-000000000000' or p_snapshot_id is null or p_snapshot_id='00000000-0000-0000-0000-000000000000'
  or p_assignment_revision is null or p_assignment_revision<=0 or p_expected_revision is null or p_expected_revision<=0
  or (p_action='confirm' and p_confirmation_id is not null) or (p_action='approve' and (p_confirmation_id is null or p_confirmation_id='00000000-0000-0000-0000-000000000000')) then
  raise exception 'Exact saved version and decision identity required' using errcode='22023';end if;
 select * into r from team_private.shot_coverage_attestations where id=p_batch_id;
 if found then
  if (r.team_id,r.game_id,r.actor_user_id,r.assignment_revision,r.expected_revision,r.snapshot_id,r.decision,r.confirmation_id) is distinct from
   (p_team_id,p_game_id,a,p_assignment_revision,p_expected_revision,p_snapshot_id,p_action,p_confirmation_id) then raise exception 'Coverage command identity conflict' using errcode='PT409';end if;
  if r.assignment_revision<>s.assignment_revision then raise exception 'Coverage receipt assignment changed' using errcode='PT409';end if;
  return team_private.shot_coverage_receipt(r);
 end if;
 if s.assignment_revision<>p_assignment_revision or s.revision<>p_expected_revision or s.latest_snapshot_id is distinct from p_snapshot_id then
  raise exception 'Capture or assignment changed' using errcode='PT409';end if;
 if exists(select 1 from team_private.shot_coverage_attestations where game_id=p_game_id and snapshot_id=p_snapshot_id
  and (decision='approve' or (decision=p_action and assignment_revision=s.assignment_revision))) then raise exception 'Coverage already decided for this version' using errcode='PT409';end if;
 if p_action='approve' then
  select * into c from team_private.shot_coverage_attestations where id=p_confirmation_id and team_id=p_team_id and game_id=p_game_id
   and snapshot_id=p_snapshot_id and assignment_revision=s.assignment_revision and decision='confirm' and actor_user_id=s.recorder_user_id;
  if c.id is null then raise exception 'Current manager confirmation required for this exact version' using errcode='PT409';end if;
 end if;
 if team_private.shot_actor(p_team_id) is distinct from a or not team_private.has_capability(p_team_id,a,case when p_action='confirm' then 'shots.record' else 'stats.review' end) then
  raise exception 'Current coverage authority required' using errcode='42501';end if;
 update team_private.shot_sessions set revision=revision+1 where game_id=p_game_id returning * into s;
 insert into team_private.shot_coverage_attestations(id,team_id,game_id,snapshot_id,actor_user_id,assignment_revision,expected_revision,state_revision,decision,confirmation_id)
  values(p_batch_id,p_team_id,p_game_id,p_snapshot_id,a,p_assignment_revision,p_expected_revision,s.revision,p_action,p_confirmation_id) returning * into r;
 perform team_private.audit(p_team_id,a,'shots.coverage_'||p_action,p_batch_id);
 return team_private.shot_coverage_receipt(r);
end $$;

create function public.shots_coverage_receipt(p_team_id uuid,p_game_id uuid,p_batch_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.shot_actor(p_team_id);s team_private.shot_sessions;r team_private.shot_coverage_attestations;
begin
 select * into s from team_private.shot_sessions where team_id=p_team_id and game_id=p_game_id;
 if not (team_private.has_capability(p_team_id,a,'stats.review') or (s.recorder_user_id=a and team_private.has_capability(p_team_id,a,'shots.record'))) then raise exception 'Current coverage authority required' using errcode='42501';end if;
 select * into r from team_private.shot_coverage_attestations where id=p_batch_id and team_id=p_team_id and game_id=p_game_id and actor_user_id=a;
 if not found then return null;end if;
 if (r.decision='confirm' and (s.recorder_user_id<>a or not team_private.has_capability(p_team_id,a,'shots.record')))
  or (r.decision='approve' and not team_private.has_capability(p_team_id,a,'stats.review')) then raise exception 'Current decision authority required' using errcode='42501';end if;
 if r.assignment_revision<>s.assignment_revision then raise exception 'Coverage receipt assignment changed' using errcode='PT409';end if;
 return team_private.shot_coverage_receipt(r);
end $$;
revoke all on function public.shots_coverage_decide(uuid,uuid,bigint,bigint,uuid,uuid,text,uuid),public.shots_coverage_receipt(uuid,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.shots_coverage_decide(uuid,uuid,bigint,bigint,uuid,uuid,text,uuid),public.shots_coverage_receipt(uuid,uuid,uuid) to authenticated;
-- Compare representation only at native UUID-typed paths. Stored JSON and raw digests stay exact.
-- Each document still independently passes the existing validator, including before/Undo/no-op rules.
create function team_private.shot_identity_comparison(v jsonb,p_kind text) returns jsonb
language plpgsql immutable set search_path=pg_catalog as $$
declare result jsonb:=v;keys text[];k text;items jsonb;
begin
 if jsonb_typeof(v) is distinct from 'object' then return v;end if;
 keys:=case p_kind when 'document' then array['id'] when 'context' then array['gameID','teamID','actorID']
  when 'change' then array['id','eventID','undoOf'] when 'event' then array['id'] else array[]::text[] end;
 foreach k in array keys loop
  if jsonb_typeof(v->k)='string' and v->>k ~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' then
   result:=jsonb_set(result,array[k],to_jsonb(lower(v->>k)),false);
  end if;
 end loop;
 if p_kind='document' then
  if jsonb_typeof(v->'context')='object' then result:=jsonb_set(result,array['context'],team_private.shot_identity_comparison(v->'context','context'),false);end if;
  if jsonb_typeof(v->'journal')='array' then
   select coalesce(jsonb_agg(team_private.shot_identity_comparison(x.value,'change') order by x.ordinality),'[]'::jsonb) into items
    from jsonb_array_elements(v->'journal') with ordinality x(value,ordinality);
   result:=jsonb_set(result,array['journal'],items,false);
  end if;
 elsif p_kind='change' then
  foreach k in array array['before','after'] loop
   if jsonb_typeof(v->k)='object' then result:=jsonb_set(result,array[k],team_private.shot_identity_comparison(v->k,'event'),false);end if;
  end loop;
 end if;
 return result;
end $$;
revoke all on function team_private.shot_identity_comparison(jsonb,text) from public,anon,authenticated,service_role;

create or replace function public.shots_save(p_team_id uuid,p_game_id uuid,p_assignment_revision bigint,p_expected_revision bigint,p_batch_id uuid,p_document_text text,p_coverage_claim text) returns jsonb
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
  if s.session_id<>team_private.shot_uuid(doc->'id') or team_private.shot_identity_comparison(doc-'journal','document') is distinct from team_private.shot_identity_comparison(previous.document-'journal','document') or jsonb_array_length(doc->'journal')<previous.local_revision then raise exception 'Capture history changed' using errcode='PT409'; end if;
  for i in 0..previous.local_revision-1 loop
   if team_private.shot_identity_comparison(doc->'journal'->i,'change') is distinct from team_private.shot_identity_comparison(previous.document->'journal'->i,'change') then raise exception 'Capture branch requires explicit recovery review' using errcode='PT409'; end if;
  end loop;
 end if;
 insert into team_private.shot_snapshots(team_id,game_id,session_id,creator_user_id,uploader_user_id,assignment_revision,local_revision,document,document_digest,parent_snapshot_id,coverage_claim)
  values(p_team_id,p_game_id,team_private.shot_uuid(doc->'id'),team_private.shot_uuid(doc->'context'->'actorID'),a,s.assignment_revision,jsonb_array_length(doc->'journal'),doc,payload_digest,s.latest_snapshot_id,p_coverage_claim) returning id into v_id;
 update team_private.shot_sessions set latest_snapshot_id=v_id,revision=revision+1,head_status='draft' where game_id=p_game_id returning * into s;
 return team_private.shot_receipt(p_team_id,p_game_id,a,p_batch_id,d,'save',jsonb_build_object('batch_id',p_batch_id,'operation','save','team_id',p_team_id,'game_id',p_game_id,'actor_user_id',a,'session_id',s.session_id,'assignment_revision',s.assignment_revision,'state_revision',s.revision,'snapshot_id',v_id,'document_revision',jsonb_array_length(doc->'journal'),'document_digest',payload_digest,'expected_revision',p_expected_revision));
end $$;


create or replace function public.shots_recovery(p_team_id uuid,p_game_id uuid,p_assignment_revision bigint,p_expected_revision bigint,p_batch_id uuid,p_document_text text) returns jsonb
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
 if team_private.shot_identity_comparison(doc-'journal','document') is distinct from team_private.shot_identity_comparison(head.document-'journal','document') then raise exception 'Recovery must preserve registered capture identity' using errcode='22023';end if;
 insert into team_private.shot_snapshots(team_id,game_id,session_id,creator_user_id,uploader_user_id,assignment_revision,local_revision,document,document_digest,parent_snapshot_id,recovery,coverage_claim)
 values(p_team_id,p_game_id,s.session_id,head.creator_user_id,a,s.assignment_revision,jsonb_array_length(doc->'journal'),doc,payload,s.latest_snapshot_id,true,'unknown') returning id into v_id;
 update team_private.shot_sessions set revision=revision+1 where game_id=p_game_id returning * into s;
 return team_private.shot_receipt(p_team_id,p_game_id,a,p_batch_id,d,'recovery',jsonb_build_object('batch_id',p_batch_id,'operation','recovery','team_id',p_team_id,'game_id',p_game_id,'actor_user_id',a,'assignment_revision',s.assignment_revision,'state_revision',s.revision,'snapshot_id',v_id,'document_revision',jsonb_array_length(doc->'journal'),'document_digest',payload,'displaced_snapshot_id',s.latest_snapshot_id));
end $$;
commit;
