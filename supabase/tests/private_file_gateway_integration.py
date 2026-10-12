"""Opt-in actual local signed Auth/Storage/validator private-file acceptance.

Preserves synthetic fixture records for inspection; never touches simulator data,
real identities, hosted endpoints or bootstrap. Does not apply migrations. Tokens,
keys and raw provider errors remain in memory; public output is sanitized checks.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import io
import json
import os
import subprocess
import tomllib
import urllib.error
import urllib.parse
import urllib.request
import uuid

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cli',type=Path,required=True)
parser.add_argument('--runtime-home',type=Path,required=True)
parser.add_argument('--workdir',type=Path,required=True)
parser.add_argument('--validator-config',type=Path,required=True)
parser.add_argument('--evidence',type=Path,required=True)
args=parser.parse_args()
config=tomllib.loads((args.workdir/'supabase/config.toml').read_text())
assert config['auth']['email']['smtp']['enabled'] is False,'External SMTP must remain disabled'
assert all(provider['enabled'] is False for name,provider in config['auth']['sms'].items() if isinstance(provider,dict) and 'enabled' in provider),'SMS remains disabled'
assert all(hook['enabled'] is False for hook in config['auth']['hook'].values()),'Auth hooks must remain disabled'
assert config['local_smtp']['enabled'] is True,'Local mail capture required'
assert args.evidence.resolve().name.endswith('.local.json'),'Evidence must be explicitly private'
assert not args.evidence.exists(),'Preserve existing evidence'
env=dict(os.environ,SUPABASE_HOME=str(args.runtime_home.resolve()),SUPABASE_EXPERIMENTAL_STACK='1',SUPABASE_TELEMETRY_DISABLED='1')
status=subprocess.run([str(args.cli),'--workdir',str(args.workdir),'status','--output-format','json'],env=env,capture_output=True,text=True)
if status.returncode:raise SystemExit('Local runtime status unavailable; raw diagnostics withheld')
settings=json.loads(status.stdout)['env']
api=settings['API_URL'].rstrip('/');rest=settings['REST_URL'].rstrip('/')
key=settings['ANON_KEY'];service=settings['SERVICE_ROLE_KEY'];db=urllib.parse.urlsplit(settings['DB_URL'])
for endpoint in (api,rest,settings['DB_URL']):assert urllib.parse.urlsplit(endpoint).hostname in ('127.0.0.1','localhost','::1'),'Only isolated loopback runtime permitted'
pg=args.runtime_home/'cache/stack/slim-services/postgres/17.11.0.004-r1/darwin-arm64/bin/psql'
pgenv=dict(env,PGHOST=db.hostname,PGPORT=str(db.port),PGUSER=urllib.parse.unquote(db.username),PGPASSWORD=urllib.parse.unquote(db.password),PGDATABASE=db.path.lstrip('/'))
validator=json.loads(args.validator_config.read_text())
assert validator.get('mode')=='isolated_local' and validator.get('hosted_enabled') is False
spec=importlib.util.spec_from_file_location('private_file_gateway',Path(__file__).parents[1]/'private_file_gateway.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
gateway=module.FileGateway(module.Providers(validator),module.TrustedValidator(validator))
results=[]
def check(name,condition):
 results.append({'check':name,'passed':bool(condition)});print(('PASS ' if condition else 'FAIL ')+name,flush=True)
 if not condition:raise RuntimeError('Acceptance failed; private evidence retained')
def sql(query):
 result=subprocess.run([str(pg),'-X','-A','-t','-v','ON_ERROR_STOP=1'],input=query,env=pgenv,capture_output=True,text=True)
 if result.returncode:raise RuntimeError('Trusted synthetic fixture SQL failed; raw diagnostic withheld')
 return result.stdout.strip().splitlines()
def request(url,body=None,token=None):
 headers={'apikey':key,'Authorization':'Bearer '+(token or key)}
 if body is not None:headers['Content-Type']='application/json'
 req=urllib.request.Request(url,data=json.dumps(body).encode() if body is not None else None,headers=headers,method='POST' if body is not None else 'GET')
 try:
  with urllib.request.urlopen(req,timeout=20) as response:data=response.read(65536);code=response.status
 except urllib.error.HTTPError as error:data=error.read(65536);code=error.code
 try:reply=json.loads(data)
 except ValueError:reply=None
 return code,reply
namespace='synthetic-private-file-'+uuid.uuid4().hex

def session(label):
 code,link=request(api+'/auth/v1/admin/generate_link',{'type':'magiclink','email':namespace+'-'+label+'@example.invalid'},service)
 check('local trusted synthetic verification link created',code==200 and isinstance(link,dict))
 code,reply=request(api+'/auth/v1/verify',{'type':'magiclink','token_hash':link['properties']['hashed_token']})
 check('actual distinct signed local Auth session verified',code==200 and bool(reply.get('access_token')))
 return reply

def rpc(account,name,arguments):return request(rest+'/rpc/'+name,arguments,account['access_token'])
def deny(function,code='access_denied'):
 try:function()
 except module.FileFailure as failure:return failure.code==code
 return False

def pdf():
 # Clearly synthetic structurally valid one-page PDF; native renderer must accept actual bytes.
 stream=b'0 0 20 20 re S\n'
 bodies=[b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R >>',b'<< /Length '+str(len(stream)).encode()+b' >>\nstream\n'+stream+b'endstream']
 data=b'%PDF-1.4\n';offsets=[0]
 for n,body in enumerate(bodies,1):offsets.append(len(data));data+=str(n).encode()+b' 0 obj\n'+body+b'\nendobj\n'
 start=len(data);data+=b'xref\n0 5\n0000000000 65535 f \n'
 for offset in offsets[1:]:data+=('%010d 00000 n \n'%offset).encode()
 data+=b'trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n'+str(start).encode()+b'\n%%EOF\n'
 return data
try:
 check('new private-file schema already independently installed locally',sql("select to_regclass('public.file_resources') is not null;")==['t'])
 check('trusted gateway matches same local REST and service key',gateway.providers.rest==rest and gateway.providers.service_key==service)
 owner,author,reader,outsider=[session(label) for label in ('owner','author','reader','outsider')]
 ids=[str(uuid.uuid4()) for _ in range(5)];team,game,resource_id,operation,_=ids
 owner_id=owner['user']['id'];author_id=author['user']['id'];reader_id=reader['user']['id']
 for value in (team,game,resource_id,operation,owner_id,author_id,reader_id):module.identifier(value)
 sql(f"insert into public.teams(id,name,owner_auth_uuid) values('{team}','TEST ONLY PRIVATE BYTES','{owner_id}');insert into public.team_memberships(team_id,user_id,status) values('{team}','{author_id}','active'),('{team}','{reader_id}','active');insert into public.games(id,team_id,date,opponent,home_away,game_type,created_by) values('{game}','{team}','2026-10-12','TEST ONLY PRIVATE BYTE VERIFICATION','home','regularSeason','{owner_id}');")
 # Trusted SYNTHETIC local budget counts prior retained bytes and never resets transfers.
 sql("update team_private.file_budget set known_until=now()+interval '15 minutes',storage_limit=(select coalesce(sum(reserved_bytes),0)+20971520 from team_private.file_uploads),transfer_limit=transfer_charged+104857600 where id;")
 def access():
  code,body=rpc(owner,'team_access',{'p_team_id':team});check('signed owner access snapshot',code==200);return body
 for user,capability in ((author_id,'scouting.upload'),(reader_id,'scouting.read')):
  code,_=rpc(owner,'team_set_capability',{'p_team_id':team,'p_user_id':user,'p_capability':capability,'p_enabled':True,'p_expected_access_revision':access()['access_revision']})
  check('signed owner assigned synthetic scoped capability',code==200)
 data=pdf();arguments={'p_team_id':team,'p_resource_id':resource_id,'p_kind':'scouting','p_target_id':game,'p_operation_id':operation,'p_declared_bytes':len(data),'p_title':'TEST ONLY ACTUAL PDF BYTES'}
 code,version=rpc(author,'file_reserve',arguments);check('signed eligible author reserves immutable upload',code==200)
 code,repeated=rpc(author,'file_reserve',arguments);check('reservation lost-reply retry keeps exact identity',code==200 and repeated['id']==version['id'])
 receipt=gateway.upload(author['access_token'],operation,io.BytesIO(data),len(data))
 check('actual private Storage and trusted renderer establish exact receipt',receipt['status']=='ready' and receipt['byte_count']==len(data) and receipt['sha256']==hashlib.sha256(data).hexdigest())
 check('ordinary reader cannot retrieve pending real bytes',deny(lambda:gateway.download(reader['access_token'],receipt['id'],str(uuid.uuid4()))))
 code,submitted=rpc(author,'file_transition',{'p_team_id':team,'p_version_id':receipt['id'],'p_expected_revision':receipt['revision'],'p_action':'submit'})
 check('signed author submits exact stored PDF',code==200 and submitted['status']=='submitted')
 code,published=rpc(owner,'file_transition',{'p_team_id':team,'p_version_id':receipt['id'],'p_expected_revision':submitted['revision'],'p_action':'approve'})
 check('signed owner approves immutable exact real-byte version',code==200 and published['status']=='published')
 fetched,_=gateway.download(reader['access_token'],receipt['id'],str(uuid.uuid4()))
 check('current read-authorized account receives exact actual stored body',fetched==data)
 check('independent signed nonmember cannot retrieve approved body',deny(lambda:gateway.download(outsider['access_token'],receipt['id'],str(uuid.uuid4()))))
 # Direct private-bucket read and write cannot bypass the ledger, even for the author.
 path=team+'/'+resource_id+'/'+receipt['id'];object_url=gateway.providers.object_url(path)
 for account,label in ((reader,'reader'),(author,'uploader')):
  try:
   gateway.providers.request(object_url,'GET',None,{'apikey':key,'Authorization':'Bearer '+account['access_token']},len(data));allowed=True
  except module.FileFailure:allowed=False
  check('direct Storage '+label+' read denied',not allowed)
  try:
   gateway.providers.request(object_url,'POST',data,{'apikey':key,'Authorization':'Bearer '+account['access_token'],'Content-Type':'application/pdf','x-upsert':'false'},4096);allowed=True
  except module.FileFailure:allowed=False
  check('direct Storage '+label+' write denied',not allowed)
 code,_=rpc(owner,'team_set_capability',{'p_team_id':team,'p_user_id':reader_id,'p_capability':'scouting.read','p_enabled':False,'p_expected_access_revision':access()['access_revision']})
 check('signed synthetic read grant revoked',code==200)
 check('same signed account immediately denied future remote bytes',deny(lambda:gateway.download(reader['access_token'],receipt['id'],str(uuid.uuid4()))))
 code,owner_view=rpc(owner,'file_delivery',{'p_team_id':team,'p_version_id':receipt['id'],'p_operation_id':str(uuid.uuid4())})
 check('revocation preserves owner accepted metadata and bytes',code==200 and owner_view['sha256']==receipt['sha256'])
 code,response=request(api+'/auth/v1/logout',{},author['access_token'])
 check('actual synthetic Auth logout succeeds',code in (200,204))
 code,_=rpc(author,'file_reserve',arguments)
 check('old signed JWT denied after actual session logout',code>=400)
finally:
 evidence={'kind':'actual isolated local Auth/Storage/validator checks','checks':results,'hosted':False,'physical_device':False}
 with open(args.evidence,'x') as output:os.chmod(args.evidence,0o600);json.dump(evidence,output)
