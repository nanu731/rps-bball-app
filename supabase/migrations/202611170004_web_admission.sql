-- Verified, owner-reviewed web signup. No existing account/grant or provider activation.
begin;
create table team_private.web_signup_settings(
 id boolean primary key default true check(id),team_id uuid references public.teams(id),enabled boolean not null default false,
 check(not enabled or team_id is not null)
);
insert into team_private.web_signup_settings(id) values(true);
alter table team_private.web_signup_settings enable row level security;
create table public.web_join_requests(
 id uuid primary key default gen_random_uuid(),team_id uuid not null,user_id uuid not null unique references auth.users(id),
 first_name text not null check(length(btrim(first_name)) between 1 and 80 and first_name!~'[[:cntrl:]]'),
 last_name text not null check(length(btrim(last_name)) between 1 and 80 and last_name!~'[[:cntrl:]]'),
 verified_email text not null check(length(verified_email) between 3 and 320),
 requested_role text not null check(requested_role in ('player','coach','manager')),
 status text not null default 'pending' check(status in ('pending','approved','declined')),
 confirmed_role text check(confirmed_role in ('player','coach','manager')),revision bigint not null default 1 check(revision>0),
 reviewed_by uuid references auth.users(id),reviewed_at timestamptz,created_at timestamptz not null default clock_timestamp(),
 foreign key(team_id,user_id) references public.team_memberships(team_id,user_id)
);
create table team_private.web_join_notifications(
 request_id uuid primary key references public.web_join_requests(id),state text not null default 'pending' check(state in ('pending','retry','sending','sent','manual_review','cancelled')),
 attempts integer not null default 0 check(attempts between 0 and 5),next_attempt_at timestamptz not null default clock_timestamp(),
 claim_token uuid,claim_expires_at timestamptz,claim_actor uuid references auth.users(id),claim_session uuid,claim_jwt_expires_at timestamptz,
 last_error text check(last_error in ('disabled','configuration','transient','uncertain','permanent','capacity')),sent_at timestamptz
);
alter table public.web_join_requests enable row level security;
alter table team_private.web_join_notifications enable row level security;
revoke all on team_private.web_signup_settings,team_private.web_join_notifications from public,anon,authenticated;
create function team_private.join_request_visible(t uuid,u uuid) returns boolean language sql stable security definer set search_path=pg_catalog as $$
 select exists(select 1 from auth.users where id=team_private.actor() and deleted_at is null and (banned_until is null or banned_until<=clock_timestamp())) and (u=team_private.actor() or (team_private.can_read(t) and team_private.is_owner(t,team_private.actor())))
$$;
revoke all on function team_private.join_request_visible(uuid,uuid) from public,anon;
grant execute on function team_private.join_request_visible(uuid,uuid) to authenticated;
create policy own_or_owner_request on public.web_join_requests for select to authenticated using(team_private.join_request_visible(team_id,user_id));
-- Notification settings, private worker leases and current contact lookup remain server-only.
revoke all on public.web_join_requests from public,anon,authenticated;
grant select(id,team_id,user_id,first_name,last_name,requested_role,status,confirmed_role,revision,created_at) on public.web_join_requests to authenticated;
create function team_private.verified_email_actor() returns uuid language plpgsql stable security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.actor();
begin
 if a is null or not exists(select 1 from auth.users where id=a and email_confirmed_at is not null and email is not null and is_anonymous is not true and deleted_at is null and (banned_until is null or banned_until<=clock_timestamp())) then raise exception 'Verified email required' using errcode='42501';end if;
 return a;
end$$;
revoke all on function team_private.verified_email_actor() from public,anon,authenticated;
-- Configured web admission requires owner role review; existing active memberships are preserved.
do $$
declare definition text;needle text:='  if not team_private.has_capability(p_team_id,v_actor,''members.manage'')';
begin
 definition:=pg_get_functiondef('public.team_set_membership(uuid,uuid,text,bigint)'::regprocedure);
 if position(needle in definition)=0 then raise exception 'Unexpected membership command definition';end if;
 -- Removing authority must remain possible after the target loses verification.
 definition:=replace(definition,'  if not exists(select 1 from auth.users where id=p_user_id and is_anonymous is not true','  if p_status<>''removed'' and not exists(select 1 from auth.users where id=p_user_id and is_anonymous is not true');
 execute replace(definition,needle,'  if p_status=''active'' and (exists(select 1 from public.web_join_requests where team_id=p_team_id and user_id=p_user_id and status<>''approved'') or (exists(select 1 from team_private.web_signup_settings where id and enabled and team_id=p_team_id) and not team_private.is_active(p_team_id,p_user_id) and not exists(select 1 from public.web_join_requests where team_id=p_team_id and user_id=p_user_id and status=''approved''))) then raise exception ''Review the verified signup request and confirm its role first'' using errcode=''42501'';end if;'||chr(10)||needle);
end$$;
create function public.web_signup_status() returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.actor();r public.web_join_requests;notice team_private.web_join_notifications;
begin
 if a is null then raise exception 'Verified account required' using errcode='42501';end if;
 select * into r from public.web_join_requests where user_id=a;
 select * into notice from team_private.web_join_notifications where request_id=r.id;
 return jsonb_build_object('has_access',exists(select 1 from public.teams t where t.owner_auth_uuid=a or exists(select 1 from public.team_memberships m where m.team_id=t.id and m.user_id=a and m.status='active')),
 'configured',exists(select 1 from team_private.web_signup_settings where id and enabled and team_id is not null),
 'request',case when r.id is null then null else jsonb_build_object('id',r.id,'first_name',r.first_name,'last_name',r.last_name,'requested_role',r.requested_role,'status',r.status,'confirmed_role',r.confirmed_role,'revision',r.revision,'notification',notice.state,'notification_error',notice.last_error) end);
end$$;
create function public.web_request_access(p_first_name text,p_last_name text,p_requested_role text) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.verified_email_actor();t uuid;r public.web_join_requests;membership text;address text;
begin
 -- Stable Auth identity, not email or untrusted signup metadata, bounds duplicate requests.
 perform pg_advisory_xact_lock(hashtextextended(a::text,418));
 if exists(select 1 from public.teams x where x.owner_auth_uuid=a or exists(select 1 from public.team_memberships m where m.team_id=x.id and m.user_id=a and m.status='active')) then return public.web_signup_status();end if;
 select * into r from public.web_join_requests where user_id=a;
 if found then return public.web_signup_status();end if;
 if p_first_name is null or p_last_name is null or length(btrim(p_first_name)) not between 1 and 80 or length(btrim(p_last_name)) not between 1 and 80 or p_first_name~'[[:cntrl:]]' or p_last_name~'[[:cntrl:]]' or p_requested_role is null or p_requested_role not in ('player','coach','manager') then raise exception 'First name, last name and requested role required' using errcode='22023';end if;
 select team_id into t from team_private.web_signup_settings where id and enabled for update;
 if t is null then raise exception 'Owner approval requests are not configured' using errcode='PT503';end if;
 membership:=public.team_request_membership(t);
 if membership<>'pending' then raise exception 'Ask the owner about prior access' using errcode='42501';end if;
 select email into address from auth.users where id=a and email_confirmed_at is not null;
 insert into public.web_join_requests(team_id,user_id,first_name,last_name,verified_email,requested_role) values(t,a,btrim(p_first_name),btrim(p_last_name),address,p_requested_role) returning * into r;
 insert into team_private.web_join_notifications(request_id) values(r.id);
 perform team_private.audit(t,a,'signup.requested',r.id);
 return public.web_signup_status();
end$$;
create function public.web_list_join_requests(p_team_id uuid) returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.actor();result jsonb;
begin
 if not team_private.can_read(p_team_id) or not team_private.is_owner(p_team_id,a) or not exists(select 1 from auth.users where id=a and deleted_at is null and (banned_until is null or banned_until<=clock_timestamp())) then raise exception 'Current owner applicant review required' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'user_id',r.user_id,'first_name',r.first_name,'last_name',r.last_name,'verified_email',r.verified_email,
 'current_verified_email',case when u.email_confirmed_at is not null and u.deleted_at is null and (u.banned_until is null or u.banned_until<=clock_timestamp()) then u.email else null end,'requested_role',r.requested_role,'status',r.status,'confirmed_role',r.confirmed_role,'revision',r.revision,'created_at',r.created_at,
 'notification',n.state,'notification_error',n.last_error,'notification_attempts',n.attempts) order by (r.status='pending') desc,r.created_at desc),'[]') into result
 from public.web_join_requests r join auth.users u on u.id=r.user_id left join team_private.web_join_notifications n on n.request_id=r.id where r.team_id=p_team_id;
 if octet_length(result::text)>1048576 then raise exception 'Applicant list exceeds display limit' using errcode='22023';end if;
 return result;
end$$;
create function public.web_review_join_request(p_team_id uuid,p_request_id uuid,p_expected_revision bigint,p_expected_access_revision bigint,p_confirm_identity boolean,p_role text,p_approve boolean default true) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.command_actor(p_team_id,p_expected_access_revision);r public.web_join_requests;wanted text:=case when p_approve then 'approved' else 'declined' end;
begin
 if not team_private.can_read(p_team_id) or not team_private.is_owner(p_team_id,a) or not exists(select 1 from auth.users where id=a and deleted_at is null and (banned_until is null or banned_until<=clock_timestamp())) then raise exception 'Current owner applicant review required' using errcode='42501';end if;
 perform 1 from auth.users where id=a and deleted_at is null and (banned_until is null or banned_until<=clock_timestamp()) for share;
 if not found then raise exception 'Current owner required' using errcode='42501';end if;
 if (p_approve and p_confirm_identity is distinct from true) or p_role is null or p_role not in ('player','coach','manager') or p_approve is null then raise exception 'Verify the applicant and confirm the role' using errcode='22023';end if;
 select * into r from public.web_join_requests where id=p_request_id and team_id=p_team_id for update;
 if not found then raise exception 'Applicant unavailable' using errcode='42501';end if;
 if r.status=wanted and (not p_approve or r.confirmed_role=p_role) then return to_jsonb(r);end if;
 if r.status<>'pending' or r.revision is distinct from p_expected_revision then raise exception 'Applicant review changed; reload' using errcode='PT409';end if;
 if p_approve then
  perform 1 from auth.users where id=r.user_id and email_confirmed_at is not null and is_anonymous is not true and deleted_at is null and (banned_until is null or banned_until<=clock_timestamp()) for share;
  if not found then raise exception 'Current verified applicant required' using errcode='42501';end if;
 end if;
 -- Status and permissions commit atomically; any failed primitive rolls the review back.
 update public.web_join_requests set status=wanted,confirmed_role=case when p_approve then p_role else null end,reviewed_by=a,reviewed_at=clock_timestamp(),revision=revision+1 where id=r.id returning * into r;
 perform public.team_set_membership(p_team_id,r.user_id,case when p_approve then 'active' else 'removed' end,(select access_revision from public.teams where id=p_team_id));
 if p_approve then perform public.team_apply_staff_preset(p_team_id,r.user_id,p_role,(select access_revision from public.teams where id=p_team_id));end if;
 update team_private.web_join_notifications set state='cancelled' where request_id=r.id and state in ('pending','retry');
 perform team_private.audit(p_team_id,a,'signup.'||wanted,r.id,p_role);
 return to_jsonb(r);
end$$;
revoke all on function public.web_signup_status(),public.web_request_access(text,text,text),public.web_list_join_requests(uuid),public.web_review_join_request(uuid,uuid,bigint,bigint,boolean,text,boolean) from public,anon;
grant execute on function public.web_signup_status(),public.web_request_access(text,text,text),public.web_list_join_requests(uuid),public.web_review_join_request(uuid,uuid,bigint,bigint,boolean,text,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
