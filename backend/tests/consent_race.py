#!/usr/bin/env python3
"""Run only against the disposable database created with tests/bootstrap.sql."""
import argparse
import subprocess

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--psql',default='psql')
parser.add_argument('--socket',required=True)
parser.add_argument('--port',default='55433')
a=parser.parse_args()
command=[a.psql,'-h',a.socket,'-p',a.port,'-d','postgres','-Atq','-v','ON_ERROR_STOP=1']
claims='''set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
'''
def run(sql):
 return subprocess.run(command,input=sql,text=True,capture_output=True,check=True,timeout=10).stdout.strip()

def race(first,second):
 p=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 p.stdin.write('begin;\n'+claims+first+"\nselect 'LOCK_HELD';\nselect pg_sleep(1);\ncommit;\n")
 p.stdin.close()
 for line in p.stdout:
  if line.strip()=='LOCK_HELD':break
 else:raise AssertionError(p.stderr.read())
 run(claims+second)
 if p.wait(timeout=10):raise AssertionError(p.stderr.read())
 state=run("select share_exploration::text||':'||(select count(*) from public.wn_explorations where user_id=p.id) from public.wn_profiles p where id='00000000-0000-0000-0000-000000000001';")
 assert state=='false:0',state

run(claims+"select public.update_my_profile('Alice','globe',true);")
race("select public.sync_explorations(array['FR']);", "select public.update_my_profile('Alice','globe',false);")
run(claims+"select public.update_my_profile('Alice','globe',true);")
race("select public.update_my_profile('Alice','globe',false);", "select public.sync_explorations(array['JP']);")
run("delete from public.wn_profiles where id='00000000-0000-0000-0000-000000000001';")
print('PASS: concurrent sync-before-opt-out and opt-out-before-sync both leave sharing disabled and zero cloud explorations.')
