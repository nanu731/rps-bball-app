"""Disposable synthetic local Auth/gateway verification; never prints tokens or keys."""
from pathlib import Path
import os, subprocess, json, urllib.parse, urllib.request, urllib.error, re, uuid, time, argparse, tomllib
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cli',type=Path,required=True)
parser.add_argument('--runtime-home',type=Path,required=True)
parser.add_argument('--workdir',type=Path,default=Path(__file__).resolve().parents[2])
parser.add_argument('--client-config',type=Path)
parser.add_argument('--evidence',type=Path)
ARGS=parser.parse_args()
PRIMARY=ARGS.workdir.resolve(); HOME=ARGS.runtime_home.resolve(); CLI=ARGS.cli.resolve()
CONFIG=tomllib.loads((PRIMARY/'supabase/config.toml').read_text())
assert not CONFIG['auth']['email']['smtp']['enabled'], 'External SMTP must be disabled'
assert all(not CONFIG['auth']['sms'][name]['enabled'] for name in ['twilio','twilio_verify','messagebird','textlocal','vonage']), 'All SMS providers must be disabled'
assert all(not hook['enabled'] for hook in CONFIG['auth']['hook'].values()), 'Auth hooks must be disabled'
assert CONFIG['local_smtp']['enabled'], 'Local mail capture required'
NAMESPACE='synthetic-gateway-'+uuid.uuid4().hex[:8]
OWNER_EMAIL=NAMESPACE+'-owner@example.invalid'
MEMBER_EMAIL=NAMESPACE+'-member@example.invalid'
PENDING_EMAIL=NAMESPACE+'-pending@example.invalid'
ENV=dict(os.environ,SUPABASE_HOME=str(HOME),SUPABASE_EXPERIMENTAL_STACK='1',SUPABASE_TELEMETRY_DISABLED='1')
status=subprocess.run([str(CLI),'--workdir',str(PRIMARY),'status','--output-format','json'],env=ENV,capture_output=True,text=True,check=True)
STATE=json.loads(status.stdout); SETTINGS=STATE['env']
API=SETTINGS['API_URL'].rstrip('/'); REST=SETTINGS['REST_URL'].rstrip('/'); MAIL=SETTINGS['MAILPIT_URL'].rstrip('/')
for endpoint in [API,REST,MAIL,SETTINGS['DB_URL']]:
 assert urllib.parse.urlparse(endpoint).hostname in ['127.0.0.1','localhost','::1']
KEY=SETTINGS['ANON_KEY']
DB=urllib.parse.urlparse(SETTINGS['DB_URL']); PG=HOME/'cache/stack/slim-services/postgres/17.11.0.004-r1/darwin-arm64/bin'
PGENV=dict(ENV,PGHOST=DB.hostname,PGPORT=str(DB.port),PGUSER=urllib.parse.unquote(DB.username),PGPASSWORD=urllib.parse.unquote(DB.password),PGDATABASE=DB.path.lstrip('/'))
RESULTS=[]
def request(url,method='GET',body=None,token=None,authkey=True):
 headers={'Content-Type':'application/json'}
 if authkey: headers['apikey']=KEY
 if token: headers['Authorization']='Bearer '+token
 req=urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,headers=headers,method=method)
 try:
  with urllib.request.urlopen(req,timeout=15) as response: data=response.read(); code=response.status
 except urllib.error.HTTPError as error: data=error.read(); code=error.code
 try: parsed=json.loads(data)
 except Exception: parsed=None
 return code,parsed

def check(name,condition,details=None):
 RESULTS.append({'check':name,'passed':bool(condition),'details':details})
 print(('PASS ' if condition else 'FAIL ')+name+((' '+json.dumps(details)) if details is not None else ''),flush=True)
 assert condition, name

def sql(query):
 result=subprocess.run([str(PG/'psql'),'-X','-A','-t','-v','ON_ERROR_STOP=1'],input=query,env=PGENV,capture_output=True,text=True)
 if result.returncode:
  print('FAIL trusted synthetic fixture SQL; diagnostic class', 'permission' if 'permission' in result.stderr.lower() else 'SQL',flush=True)
  raise RuntimeError('Fixture SQL failed; raw result intentionally not logged')
 return result.stdout.strip().splitlines()

def rpc(session,name,arguments): return request(REST+'/rpc/'+name,'POST',arguments,session['access_token'])
def access(session,team):
 code,data=rpc(session,'team_access',{'p_team_id':team}); check('server access snapshot available',code==200)
 return data

def mutate(session,team,name,arguments,expected=None):
 arguments=dict(arguments,p_team_id=team,p_expected_access_revision=access(session,team)['access_revision'] if expected is None else expected)
 return rpc(session,name,arguments)

def email_session(address):
 code,reply=request(API+'/auth/v1/otp','POST',{'email':address,'create_user':True})
 check('actual email OTP request accepted',code==200,{'status':code})
 message=None
 for attempt in range(20):
  mc,messages=request(MAIL+'/api/v1/messages',authkey=False)
  for item in (messages or {}).get('messages',[]):
   recipients=[person.get('Address','') for person in item.get('To',[])]
   if address in recipients: message=item; break
  if message: break
  time.sleep(0.2)
 check('synthetic email captured by local inbox',message is not None)
 _,content=request(MAIL+'/api/v1/message/'+message['ID'],authkey=False)
 html=content.get('HTML','')+'\n'+content.get('Text','')
 code_match=re.search(r'(?im)^\s*(\d{6})\s*$',content.get('Text',''))
 links=re.findall(r'https?[^\s"<>]+',html)
 verification=None
 for link in links:
  link=link.replace('&amp;','&')
  parsed=urllib.parse.urlparse(link); query=urllib.parse.parse_qs(parsed.query)
  if query.get('token') and query.get('type'):
   verification={'token_hash':query['token'][0],'type':query['type'][0]}; break
 check('captured default email provides verification link',verification is not None)
 code,session=request(API+'/auth/v1/verify','POST',verification)
 check('actual captured email link creates signed session',code==200 and bool(session.get('access_token')),{'status':code,'typed_code_observed':bool(code_match)})
 return session

def main():
 # The actual local phone request is blocked by current runtime enablement; do not enable a sender.
 code,settings=request(API+'/auth/v1/settings')
 check('local runtime has no enabled phone delivery path',code==200 and settings.get('external',{}).get('phone') is False)
 code,phone_error=request(API+'/auth/v1/otp','POST',{'phone':'+15555550101','create_user':True})
 check('all-provider-disabled phone path rejects delivery attempt',code==400 and phone_error.get('error_code')=='phone_provider_disabled',{'status':code,'error_code':phone_error.get('error_code')})
 owner=email_session(OWNER_EMAIL)
 member=email_session(MEMBER_EMAIL)
 # This third independent Auth account uses a clearly marked trusted LOCAL test link,
 # proving real Auth verification/session handling but no email delivery for this fixture.
 code,generated=request(API+'/auth/v1/admin/generate_link','POST',{'type':'magiclink','email':PENDING_EMAIL},SETTINGS['SERVICE_ROLE_KEY'])
 check('trusted local TEST ONLY link generation accepted',code==200 and bool(generated.get('hashed_token')),{'status':code})
 code,pending=request(API+'/auth/v1/verify','POST',{'type':generated['verification_type'],'token_hash':generated['hashed_token']})
 check('third local test link creates independent signed session',code==200 and bool(pending.get('access_token')),{'status':code,'delivery_evidence':False})
 ids=[str(uuid.UUID(s['user']['id'])) for s in [owner,member,pending]]
 check('independently verified identities have distinct Auth UUIDs',len(set(ids))==3)
 team=str(uuid.uuid4())
 sql("insert into public.teams(id,name,owner_auth_uuid) values ('"+team+"','SYNTHETIC GATEWAY TEAM','"+ids[0]+"');")
 owner_access=access(owner,team)
 check('trusted verified UUID establishes immutable owner',owner_access['is_owner'] is True and len(owner_access['capabilities'])==14 and owner_access['access_revision']==1)
 code,data=request(REST+'/teams?id=eq.'+team+'&select=id',token=member['access_token'])
 check('signed nonmember cannot read existing team',code==200 and data==[],{'status':code})
 code,data=rpc(pending,'team_request_membership',{'p_team_id':team})
 check('gateway admission remains pending',code==200 and data=='pending',{'status':code})
 code,data=rpc(pending,'team_access',{'p_team_id':team})
 check('signed pending member denied team access RPC',code==403 and data.get('code')=='42501',{'status':code,'sqlstate':data.get('code')})
 code,_=mutate(owner,team,'team_set_membership',{'p_user_id':ids[1],'p_status':'active'})
 check('owner gateway command activates verified member',code in [200,204],{'status':code})
 member_access=access(member,team)
 check('ordinary active member receives stats proposal baseline only',member_access['can_propose_stats'] and member_access['capabilities']==[] and not member_access['is_owner'])
 code,roster=mutate(owner,team,'team_save_roster',{'p_display_name':'SYNTHETIC GATEWAY PLAYER','p_jersey_number':'99'})
 check('owner gateway roster create succeeds',code==200 and bool(roster),{'status':code})
 code,rows=request(REST+'/roster_entries?team_id=eq.'+team+'&select=id,version,archived_at',token=member['access_token'])
 check('active signed member reads real persisted roster fixture',code==200 and len(rows)==1 and rows[0]['id']==roster)
 code,rows=request(REST+'/roster_entries?team_id=eq.'+team+'&select=id',token=pending['access_token'])
 check('pending signed session cannot read existing roster fixture',code==200 and rows==[])
 code,reply=rpc(member,'team_set_capability',{'p_team_id':team,'p_user_id':ids[0],'p_capability':'stats.publish','p_enabled':True,'p_expected_access_revision':access(member,team)['access_revision']})
 check('ordinary signed member denied owner/grant tampering',code==403 and reply.get('code')=='42501',{'status':code,'sqlstate':reply.get('code')})
 code,reply=request(REST+'/teams','POST',{'name':'SYNTHETIC FORGED OWNER','owner_auth_uuid':ids[1]},member['access_token'])
 check('gateway rejects authenticated owner bootstrap',code==403 and reply.get('code')=='42501',{'status':code,'sqlstate':reply.get('code')})
 captured=access(owner,team)['access_revision']
 code,_=mutate(owner,team,'team_set_membership',{'p_user_id':ids[1],'p_status':'removed'})
 check('owner gateway removal succeeds',code in [200,204])
 code,reply=mutate(owner,team,'team_set_membership',{'p_user_id':ids[1],'p_status':'active'},captured)
 check('signed stale membership RPC cannot undo removal',code in [409,500] and reply.get('code')=='40001',{'status':code,'sqlstate':reply.get('code')})
 code,rows=request(REST+'/teams?id=eq.'+team+'&select=id',token=member['access_token'])
 check('removed signed member immediately loses existing team read',code==200 and rows==[])
 code,_=mutate(owner,team,'team_set_membership',{'p_user_id':ids[1],'p_status':'active'})
 check('fresh signed admission succeeds',code in [200,204])
 # Delete the real session via sign-out, then reuse its still-unexpired signed JWT against RLS/RPC.
 code,_=request(API+'/auth/v1/logout?scope=local','POST',{},member['access_token'])
 check('real Auth local logout removes member session',code in [200,204],{'status':code})
 code,rows=request(REST+'/teams?id=eq.'+team+'&select=id',token=member['access_token'])
 check('revoked live Auth session blocks reads with old signed JWT',code==200 and rows==[],{'status':code})
 code,reply=rpc(member,'team_access',{'p_team_id':team})
 check('revoked live Auth session blocks RPC with old signed JWT',code==403 and reply.get('code')=='42501',{'status':code,'sqlstate':reply.get('code')})
 code,reply=request(REST+'/rpc/team_access','POST',{'p_team_id':team})
 check('anonymous gateway denies protected RPC',code in [401,403] and reply.get('code')=='42501',{'status':code,'sqlstate':reply.get('code')})
 if ARGS.client_config:
  code,native_test_link=request(API+'/auth/v1/admin/generate_link','POST',{'type':'magiclink','email':OWNER_EMAIL},SETTINGS['SERVICE_ROLE_KEY'])
  check('TEST ONLY owner email code generated for native client session checks',code==200 and bool(native_test_link.get('email_otp')),{'status':code,'delivery_evidence':False})
  client={'syntheticEmail':OWNER_EMAIL,'syntheticEmailTestCode':native_test_link['email_otp'],'apiRoot':API,'publishableKey':SETTINGS['PUBLISHABLE_KEY'],'anonymousKey':KEY,'syntheticOwnerAuthUUID':ids[0],'syntheticTeamID':team,'runtimeHome':str(HOME),'environment':'localTest'}
  write_new(ARGS.client_config,client)
 if ARGS.evidence:
  proof={'checks':RESULTS,'actual_auth_methods':['captured_default_email_link','trusted_local_test_link'],'phone_result':'blocked: phone_provider_disabled with all senders disabled','fixture_scope':'disposable local runtime only','provider_delivery':'unverified; no external delivery enabled','team_access_snapshot':{k:v for k,v in owner_access.items() if k not in ['user_id','team_id']}}
  write_new(ARGS.evidence,proof)
 print('Actual gateway checks passed:',len(RESULTS),flush=True)

def write_new(path,value):
 # Generated client material stays in explicitly chosen private files and is never overwritten.
 with os.fdopen(os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w') as output:
  output.write(json.dumps(value,indent=2)+'\n')

if __name__=='__main__':
 try: main()
 except Exception as exc:
  print('Gateway verification stopped:',type(exc).__name__,flush=True)
  # Never print raw Auth/server exceptions or captured mail.
  raise SystemExit(1)
