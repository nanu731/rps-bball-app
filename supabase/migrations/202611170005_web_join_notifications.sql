-- Disabled, owner-configured signup notifications. No SMTP credentials in SQL.
begin;
alter table team_private.web_signup_settings add column notification_enabled boolean not null default false;

create function team_private.join_notice_actor(p_request uuid,p_actor uuid,p_session uuid,p_exp bigint) returns boolean
language sql stable security definer set search_path=pg_catalog as $$
 select p_exp>extract(epoch from clock_timestamp()) and exists(
  select 1 from public.web_join_requests r join auth.users u on u.id=p_actor
  join auth.sessions s on s.user_id=u.id and s.id=p_session
  where r.id=p_request and u.deleted_at is null and u.is_anonymous is not true
  and (u.banned_until is null or u.banned_until<=clock_timestamp())
  and (u.email_confirmed_at is not null or u.phone_confirmed_at is not null)
  and (s.not_after is null or s.not_after>clock_timestamp())
  and (r.user_id=p_actor or (team_private.is_active(r.team_id,p_actor) and team_private.is_owner(r.team_id,p_actor))))
$$;
revoke all on function team_private.join_notice_actor(uuid,uuid,uuid,bigint) from public,anon,authenticated,service_role;

-- The worker first verifies the ORIGINAL signed JWT through Auth. Only its trusted
-- service credential may supply that verified actor/session/expiry envelope here.
create function public.web_join_notice_claim(p_request_id uuid,p_actor uuid,p_session uuid,p_exp bigint) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare r public.web_join_requests;n team_private.web_join_notifications;token uuid;
begin
 if team_private.join_notice_actor(p_request_id,p_actor,p_session,p_exp) is distinct from true then raise exception 'Current request or owner access required' using errcode='42501';end if;
 select * into r from public.web_join_requests where id=p_request_id for update;
 select * into n from team_private.web_join_notifications where request_id=r.id for update;
 if not found then raise exception 'Notification unavailable' using errcode='42501';end if;
 if r.status<>'pending' then return jsonb_build_object('state','cancelled');end if;
 if n.state in ('sent','cancelled','manual_review') then return jsonb_build_object('state',n.state);end if;
 if n.state='sending' then
  if n.claim_expires_at>clock_timestamp() then return jsonb_build_object('state','busy');end if;
  update team_private.web_join_notifications set state='manual_review',last_error='uncertain' where request_id=r.id;
  return jsonb_build_object('state','manual_review');
 end if;
 if not exists(select 1 from team_private.web_signup_settings where id and enabled and notification_enabled and team_id=r.team_id) then
  update team_private.web_join_notifications set last_error='disabled' where request_id=r.id;
  return jsonb_build_object('state','disabled');
 end if;
 if n.attempts>=5 then
  update team_private.web_join_notifications set state='manual_review',last_error='capacity' where request_id=r.id;
  return jsonb_build_object('state','manual_review');
 end if;
 if n.next_attempt_at>clock_timestamp() then return jsonb_build_object('state','retry_wait');end if;
 -- Keep current actor/session eligibility through the claim commit.
 perform 1 from auth.sessions where id=p_session and user_id=p_actor and (not_after is null or not_after>clock_timestamp()) for share;
 if not found then raise exception 'Current session required' using errcode='42501';end if;
 perform 1 from auth.users where id=p_actor and deleted_at is null and (banned_until is null or banned_until<=clock_timestamp()) for share;
 if not found then raise exception 'Current account required' using errcode='42501';end if;
 -- Recheck after locks; revocation while waiting must not authorize a send.
 if team_private.join_notice_actor(r.id,p_actor,p_session,p_exp) is distinct from true then raise exception 'Current request or owner access required' using errcode='42501';end if;
 token:=gen_random_uuid();
 update team_private.web_join_notifications set state='sending',attempts=attempts+1,claim_token=token,claim_expires_at=clock_timestamp()+interval '60 seconds',claim_actor=p_actor,claim_session=p_session,claim_jwt_expires_at=to_timestamp(p_exp),last_error=null where request_id=r.id;
 return jsonb_build_object('state','claimed','claim',token,'team_id',r.team_id,'first_name',r.first_name,'last_name',r.last_name,'verified_email',r.verified_email,'requested_role',r.requested_role);
end$$;

create function public.web_join_notice_finish(p_request_id uuid,p_claim uuid,p_outcome text) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare n team_private.web_join_notifications;
begin
 if p_outcome is null or p_outcome not in ('sent','transient','configuration','permanent','uncertain') then raise exception 'Invalid notification outcome' using errcode='22023';end if;
 perform 1 from public.web_join_requests where id=p_request_id for update;
 select * into n from team_private.web_join_notifications where request_id=p_request_id for update;
 if not found or n.state<>'sending' or n.claim_token is distinct from p_claim or n.claim_expires_at<=clock_timestamp() then return jsonb_build_object('state','stale');end if;
 if team_private.join_notice_actor(p_request_id,n.claim_actor,n.claim_session,extract(epoch from n.claim_jwt_expires_at)::bigint) is distinct from true then p_outcome:='uncertain';end if;
 update team_private.web_join_notifications set
  state=case when p_outcome='sent' then 'sent' when p_outcome='transient' and attempts<5 then 'retry' else 'manual_review' end,
  last_error=case when p_outcome='sent' then null else p_outcome end,
  next_attempt_at=clock_timestamp()+make_interval(secs=>least(900,30*power(2,attempts-1))*(0.5+random())),
  sent_at=case when p_outcome='sent' then clock_timestamp() else sent_at end,
  claim_token=null,claim_expires_at=null where request_id=p_request_id returning * into n;
 return jsonb_build_object('state',n.state);
end$$;
revoke all on function public.web_join_notice_claim(uuid,uuid,uuid,bigint),public.web_join_notice_finish(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.web_join_notice_claim(uuid,uuid,uuid,bigint),public.web_join_notice_finish(uuid,uuid,text) to service_role;

create function public.web_retry_join_notice(p_team_id uuid,p_request_id uuid,p_expected_revision bigint,p_expected_access_revision bigint,p_acknowledge_possible_duplicate boolean default false) returns void
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.command_actor(p_team_id,p_expected_access_revision);r public.web_join_requests;n team_private.web_join_notifications;
begin
 perform 1 from auth.users where id=a and deleted_at is null and (banned_until is null or banned_until<=clock_timestamp()) for share;
 if not found or not team_private.is_owner(p_team_id,a) then raise exception 'Current owner required' using errcode='42501';end if;
 select * into r from public.web_join_requests where id=p_request_id and team_id=p_team_id for update;
 if not found or r.status<>'pending' or r.revision is distinct from p_expected_revision then raise exception 'Reload applicant request' using errcode='PT409';end if;
 select * into n from team_private.web_join_notifications where request_id=r.id for update;
 if n.state='sending' and n.claim_expires_at<=clock_timestamp() then n.state:='manual_review';n.last_error:='uncertain';end if;
 if n.state not in ('pending','retry','manual_review') then raise exception 'Notification is already sent or in progress' using errcode='PT409';end if;
 if n.last_error='uncertain' and p_acknowledge_possible_duplicate is distinct from true then raise exception 'A prior email may have arrived; explicitly acknowledge possible duplicate' using errcode='22023';end if;
 update team_private.web_join_notifications set state='pending',attempts=0,next_attempt_at=clock_timestamp(),last_error=null,claim_token=null,claim_expires_at=null where request_id=r.id;
 perform team_private.audit(p_team_id,a,'signup.notification_retry',r.id);
end$$;
revoke all on function public.web_retry_join_notice(uuid,uuid,bigint,bigint,boolean) from public,anon;
grant execute on function public.web_retry_join_notice(uuid,uuid,bigint,bigint,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
