"""Explicit isolated local Auth lifecycle check; no hosted mode or message delivery.

Reads existing ignored CLI status privately. Creates only new synthetic confirmed
accounts, retains them, and never changes provider settings or existing grants.
Not part of public CI: it requires the separately authorized actual local Auth runtime.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import base64
import hashlib
import hmac
import json
from pathlib import Path
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid


def run(status, evidence, wait_after_reuse=False):
    settings = json.loads(status.read_text())['env']
    api = settings['API_URL'].rstrip('/')
    parsed = urllib.parse.urlsplit(api)
    if parsed.scheme != 'http' or parsed.hostname != '127.0.0.1' or parsed.port != 55431:
        raise ValueError('Only the existing isolated local Auth runtime is supported')
    key, service = settings['ANON_KEY'], settings['SERVICE_ROLE_KEY']
    results = []
    with evidence.open('x') as stream: json.dump({'checks':results,'complete':False},stream)
    evidence.chmod(0o600)
    def check(name, valid, fatal=True):
        results.append({'check':name,'passed':bool(valid)})
        evidence.write_text(json.dumps({'localAuth':True,'hostedAuth':False,'checks':results,'complete':False},indent=2)+'\n')
        if not valid and fatal: raise RuntimeError('Local synthetic Auth assertion: ' + name)
    def request(route, body=None, token=None, administrator=False):
        headers={'Content-Type':'application/json','apikey':key}
        if token or administrator: headers['Authorization']='Bearer '+(service if administrator else token)
        req=urllib.request.Request(api+'/auth/v1/'+route, data=json.dumps(body).encode() if body is not None else None,
                                   headers=headers,method='POST' if body is not None else 'GET')
        try:
            with urllib.request.urlopen(req,timeout=10) as response: code=response.status; data=response.read(1024*1024+1)
        except urllib.error.HTTPError as error: code=error.code; data=error.read(8192)
        if len(data)>1024*1024: raise ValueError('Auth response exceeded bound')
        return code,json.loads(data) if data else None
    password='SYNTHETIC-'+uuid.uuid4().hex
    email='test-network-'+uuid.uuid4().hex+'@example.invalid'
    code,user=request('admin/users',{'email':email,'password':password,'email_confirm':True},administrator=True)
    check('new synthetic account created without email delivery',code in (200,201))
    user_id=user['id']
    code,session=request('token?grant_type=password',{'email':email,'password':password})
    check('actual local Auth sign-in',code==200 and session['user']['id']==user_id)
    original=session['refresh_token']
    # An expired token is signed only with this local fixture's configured test key.
    # This does not rotate a signing key or change any provider configuration.
    if settings.get('JWT_SECRET'):
        parts=session['access_token'].split('.')
        decode=lambda value:json.loads(base64.urlsafe_b64decode(value+'='*((-len(value))%4)))
        encode=lambda value:base64.urlsafe_b64encode(json.dumps(value,separators=(',',':')).encode()).decode().rstrip('=')
        check('local expiry fixture uses HS256 only',decode(parts[0])['alg']=='HS256')
        claims=decode(parts[1]); claims['exp']=int(time.time())-60
        message=parts[0]+'.'+encode(claims)
        signature=base64.urlsafe_b64encode(hmac.new(settings['JWT_SECRET'].encode(),message.encode(),hashlib.sha256).digest()).decode().rstrip('=')
        code,_=request('user',token=message+'.'+signature)
        check('expired signed local access token rejected',code==401)
    code,rotated=request('token?grant_type=refresh_token',{'refresh_token':original})
    check('refresh rotates credentials preserving identity',code==200 and rotated['refresh_token']!=original and rotated['user']['id']==user_id)
    with ThreadPoolExecutor(max_workers=2) as pool:
        replies=list(pool.map(lambda _:request('token?grant_type=refresh_token',{'refresh_token':rotated['refresh_token']}),range(2)))
    check('concurrent local refresh accepted within reuse window',all(code==200 and reply['user']['id']==user_id for code,reply in replies))
    latest=replies[-1][1]
    # Original is now a grandparent, not the immediate-parent concurrency exception.
    time.sleep(11)
    code,denial=request('token?grant_type=refresh_token',{'refresh_token':original})
    check('old grandparent reuse outside local10s interval rejected',code==400 and denial.get('error_code')=='refresh_token_already_used')
    if wait_after_reuse: time.sleep(11)  # Diagnose the separate post-revocation grace boundary.
    code,_=request('token?grant_type=refresh_token',{'refresh_token':latest['refresh_token']})
    results.append({'observation':'refresh after rejected grandparent reuse','status':code})
    check('refresh family blocked'+(' after additional reuse interval' if wait_after_reuse else ' immediately after rejected reuse'),code in (400,401,403),fatal=False)
    code,new=request('token?grant_type=password',{'email':email,'password':password})
    check('explicit fresh sign-in recovers without changing account',code==200 and new['user']['id']==user_id)
    code,_=request('logout?scope=local',{},token=new['access_token'])
    check('local sign-out confirmed',code in (200,204))
    code,_=request('token?grant_type=refresh_token',{'refresh_token':new['refresh_token']})
    check('signed-out refresh rejected',code==400)
    # Raw tokens, passwords and user contacts never enter evidence or stdout.
    receipt={'localAuth':True,'hostedAuth':False,'signingKeyRotationTested':False,'accessTokenExpiryTested':bool(settings.get('JWT_SECRET')),'checks':results,
             'waitedAfterRejectedReuse':wait_after_reuse,
             'syntheticAccountsRetained':1,'providerConfigurationChanged':False}
    evidence.write_text(json.dumps(dict(receipt,complete=True),indent=2)+'\n')
    evidence.chmod(0o600)
    failures=sum(item.get('passed') is False for item in results)
    print('Local Auth:',len(results),'observations;',failures,'failed guarantees; no hosted/key-rotation claim')
    return failures


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--local-status',type=Path,required=True)
    parser.add_argument('--evidence',type=Path,required=True)
    parser.add_argument('--wait-after-reuse',action='store_true')
    args=parser.parse_args()
    raise SystemExit(1 if run(args.local_status,args.evidence,args.wait_after_reuse) else 0)
